// FreePlayer shell — shared path-containment + audio-type helpers
// Q2: single implementation used by the bridge (getCover/getLrc/media writes)
// and the media:// scheme handler, instead of two divergent copies.

import Foundation

enum Paths {

    static let audioExtensions: Set<String> = [
        "mp3", "flac", "m4a", "mp4", "aac", "wav", "ogg", "oga", "opus",
        "wma", "aif", "aiff", "m4b", "ape", "wv", "tak", "ac3", "dts", "amr",
    ]

    /// True for audio file extensions the import pipeline + media:// accept
    /// (S3b / Q9): mp3 flac m4a mp4 aac wav ogg oga opus wma aif aiff m4b + more.
    static func isAudioFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && audioExtensions.contains(ext)
    }

    /// H#1: one-time backfill of import-created symlink records. The S3e
    /// containment check trusts only symlinks whose resolved target is recorded
    /// in imported_symlinks; tracks imported before that feature existed have no
    /// record and would silently stop streaming. Walk the track table once and
    /// record every in-library symlink. Guarded by a settings flag.
    static func symlinkBackfill() {
        if Database.getSetting("symlink_backfill_done", nil) != nil { return }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            for t in Database.getAllTracks("", "imported_at", "ASC") {
                guard let p = t["file_path"] as? String, !p.isEmpty else { continue }
                if (try? fm.attributesOfItem(atPath: p))?[.type] as? FileAttributeType == .typeSymbolicLink {
                    let resolved = URL(fileURLWithPath: p).resolvingSymlinksInPath().path
                    if !resolved.isEmpty { _ = Database.recordSymlink(p, resolved) }
                }
            }
            _ = Database.setSetting("symlink_backfill_done", "1")
        }
    }

    /// True when `path` (standardized) lives inside library_dir AND, after
    /// resolving symlinks, its final target still lives inside library_dir
    /// (S3d: a renderer-planted symlink to an arbitrary file must not read).
    static func isPathInLibrary(_ path: String) -> Bool {
        guard let libRaw = Database.getSetting("library_dir", nil) as? String, !libRaw.isEmpty else { return false }
        let libNorm = (libRaw as NSString).standardizingPath
        // H#3: the library root itself may be a symlink (common on macOS) — a
        // resolved path must be accepted against the RESOLVED root too, or every
        // read breaks for such libraries.
        let libResolved = URL(fileURLWithPath: libNorm).resolvingSymlinksInPath().path
        let pathNorm = (path as NSString).standardizingPath
        let prefixOk = pathNorm.hasPrefix(libNorm + "/") || pathNorm == libNorm
        if !prefixOk { return false }
        // S3d: resolve every symlink component — the final target must still be
        // inside the library, or a renderer-planted symlink becomes an arbitrary
        // local-file read via media:// / getCover. (Nonexistent tails resolve
        // to themselves, so write-path checks below stay usable.)
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved.isEmpty { return false }
        let resNorm = (resolved as NSString).standardizingPath
        let insideResolvedRoot = resNorm.hasPrefix(libResolved + "/") || resNorm == libResolved
        if resNorm.hasPrefix(libNorm + "/") || resNorm == libNorm || insideResolvedRoot {
            return true
        }
        // S3e: symlinks the import pipeline itself created are trusted — their
        // resolved targets are recorded in the DB at import time. A link only
        // passes when its CURRENT on-disk target still matches the recorded one:
        // a tampered or re-pointed symlink resolves differently and is rejected.
        // This keeps the app's symlink import mode working (its targets
        // legitimately live outside the library) while closing the boundary.
        if pathNorm != resNorm,
           let recorded = Database.symlinkTarget(pathNorm),
           resNorm == (recorded as NSString).standardizingPath {
            return true
        }
        return false
    }
}