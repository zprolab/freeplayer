// FreePlayer shell — import pipeline (M3): trusted-root directory scan and
// the concurrent extract → copy/symlink → batched-insert import flow.

import Foundation

/// Box so concurrently-executing dispatch blocks may mutate the payload
/// (Swift 5 mode tolerates captured-var races only with warnings; be explicit).
private final class Box<T> {
    var value: T
    init(_ v: T) { value = v }
}

enum ImportPipeline {

    /// Recursive audio file scan (M3: skip hidden dirs without descending; S7:
    /// cap at 100k entries / 60s so a hostile root can't wedge the app)
    static func scanAudioFiles(_ root: String) -> [String] {
        var found: [String] = []
        let fm = FileManager.default
        let en = fm.enumerator(atPath: root)
        var scanned = 0
        let start = CFAbsoluteTimeGetCurrent()
        while let rel = en?.nextObject() as? String {
            scanned += 1
            if scanned >= 100000 || CFAbsoluteTimeGetCurrent() - start > 60.0 { break }
            let full = (root as NSString).appendingPathComponent(rel)
            guard let attrs = try? fm.attributesOfItem(atPath: full) else { continue }
            if attrs[.type] as? FileAttributeType == .typeDirectory {
                // Hidden directory (.git, .Trashes, downloader caches): don't descend
                if (rel as NSString).lastPathComponent.hasPrefix(".") { en?.skipDescendants() }
                continue
            }
            if (rel as NSString).lastPathComponent.hasPrefix(".") { continue } // hidden file
            if Paths.isAudioFile(full) {
                found.append(full)
            }
        }
        return found
    }

    /// S4: replace path separators AND "."/".." components with underscores —
    /// ".." in artist/album tags must never escape the library.
    private static func safePathComponent(_ s: Any?) -> String {
        guard let s = s as? String else { return "" }
        return s.components(separatedBy: "/")
            .map { ($0 == "." || $0 == "..") ? "_" : $0 }
            .joined(separator: "_")
    }

    /// Full import flow. `onMain` receives the shaped result dict.
    /// M12/Q1: termination waits on AppContext.importGroup before closing the DB.
    static func runImport(files: [String], storedLib: String, importMode: String,
                          onMain: @escaping ([String: Any]) -> Void) {
        let ctx = AppContext.shared
        ctx.importTasks.increment()
        ctx.importGroup.enter()

        func finish(_ result: [String: Any]) {
            ctx.importTasks.decrement()
            ctx.importGroup.leave()
            DispatchQueue.main.async { onMain(result) }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // H4: extract metadata concurrently (bounded), keep order-insensitive
            let extractQ = DispatchQueue(label: "fp.extract", attributes: .concurrent)
            let collectQ = DispatchQueue(label: "fp.collect")
            let group = DispatchGroup()
            let prepared = Box<[(String, [String: Any]?)]>([])
            var boxErrors: [[String: Any]] = []
            for filePath in files {
                // S3b: only audio files may enter the library — everything else is
                // skipped with a recorded error (defense in depth on the source
                // paths, which the renderer controls)
                if !Paths.isAudioFile(filePath) {
                    boxErrors.append(["file": filePath, "error": "not an audio file"])
                    continue
                }
                extractQ.async(group: group) {
                    let meta = Metadata.extractAtPath(filePath)
                    // Track the nested append inside the group: the queue async
                    // counts only this block's return, so the append must
                    // enter/leave the group itself or notify could race it.
                    group.enter()
                    collectQ.async {
                        prepared.value.append((filePath, meta))
                        group.leave()
                    }
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                let fm = FileManager.default
                // Phase 2: copy/symlink + build track rows WITHOUT holding the DB
                // write lock (file IO is the slow part — see #3). No transaction
                // here, so main-thread writes (playStart, settings, EQ) stay fast.
                var tracksToInsert: [[String: Any]] = []
                var imported = 0
                var skipped = 0
                for (filePath, meta) in prepared.value {
                    guard let meta else {
                        boxErrors.append(["file": filePath, "error": "Unreadable audio file"])
                        continue
                    }
                    let baseName = (filePath as NSString).lastPathComponent
                    let artist = safePathComponent(meta["artist"])
                    let album = safePathComponent(meta["album"])
                    let albumDir = NSString.path(withComponents: [storedLib, artist, album])
                    // S4: belt-and-braces — the sanitized dir must still be inside
                    // the (standardized) library
                    if !Paths.isPathInLibrary(albumDir) {
                        boxErrors.append(["file": filePath, "error": "unsafe album path"])
                        continue
                    }
                    // Q5: every file op records its failure into `errors` instead
                    // of being silently dropped (UNIQUE collisions etc.)
                    if !fm.fileExists(atPath: albumDir) {
                        do {
                            try fm.createDirectory(atPath: albumDir, withIntermediateDirectories: true)
                        } catch {
                            boxErrors.append(["file": filePath, "error": error.localizedDescription])
                            continue
                        }
                    }
                    let targetPath = (albumDir as NSString).appendingPathComponent(baseName)
                    let exists = fm.fileExists(atPath: targetPath)
                    if !exists {
                        do {
                            if importMode == "symlink" {
                                try fm.createSymbolicLink(atPath: targetPath, withDestinationPath: filePath)
                            } else {
                                try fm.copyItem(atPath: filePath, toPath: targetPath)
                            }
                        } catch {
                            boxErrors.append(["file": filePath, "error": error.localizedDescription])
                            continue
                        }
                    }
                    // S3e: if the created (or already present) library entry is a
                    // symlink — symlink mode always, copy mode when the source was
                    // itself a symlink — record its RESOLVED target in the DB.
                    // Paths.isPathInLibrary then allows it (target matches the
                    // record) while still rejecting renderer-planted/tampered links.
                    if (try? fm.attributesOfItem(atPath: targetPath))?[.type] as? FileAttributeType == .typeSymbolicLink {
                        let resolvedTarget = URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().path
                        if !resolvedTarget.isEmpty {
                            _ = Database.recordSymlink(targetPath, resolvedTarget)
                        }
                    }

                    // Cover art -> <albumDir>/.covers/cover.ext
                    var coverPath: String?
                    if let artwork = meta["artwork"] as? Data {
                        let coverDir = (albumDir as NSString).appendingPathComponent(".covers")
                        if !fm.fileExists(atPath: coverDir) {
                            try? fm.createDirectory(atPath: coverDir, withIntermediateDirectories: true)
                        }
                        let cp = (coverDir as NSString).appendingPathComponent("cover.jpg")
                        if !fm.fileExists(atPath: cp) {
                            do {
                                try artwork.write(to: URL(fileURLWithPath: cp), options: .atomic)
                                coverPath = cp
                            } catch {
                                NSLog("[bridge] cover write failed: %@", "\(error)")
                                coverPath = nil // keep the track, drop only the cover
                            }
                        } else {
                            coverPath = cp
                        }
                    }

                    var trackData = meta
                    trackData["file_path"] = targetPath
                    trackData["cover_path"] = coverPath ?? NSNull()
                    trackData["replaygain_gain"] = 0
                    trackData["replaygain_peak"] = 0
                    trackData.removeValue(forKey: "artwork")

                    tracksToInsert.append(trackData)
                    if exists { skipped += 1 } else { imported += 1 }
                }

                // Phase 3: batched inserts — short transactions so the write lock
                // is never held for the whole import (main-thread writers stall
                // on busy_timeout while it is). Q5: failed inserts are counted and
                // reported instead of being ignored.
                let insertBatch = 50
                var i = 0
                while i < tracksToInsert.count {
                    let tx = Database.beginTransaction()
                    let end = Swift.min(i + insertBatch, tracksToInsert.count)
                    for j in i..<end {
                        let td = tracksToInsert[j]
                        if !Database.insertTrack(td) {
                            boxErrors.append(["file": td["file_path"] ?? "?", "error": "database insert failed"])
                            imported -= 1
                        }
                    }
                    if tx { _ = Database.commitTransaction() }
                    i = end
                }
                finish([
                    "imported": imported,
                    "skipped": skipped,
                    "errors": boxErrors,
                ])
            }
        }
    }
}