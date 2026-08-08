import Foundation
import UniformTypeIdentifiers

struct ImportResult {
    var imported: Int = 0
    var skipped: Int = 0
    var errors: [(file: String, error: String)] = []
}

/// Scans folders for audio files and imports them into the library directory
/// (copy or symlink), extracting metadata + cover art and inserting into the DB.
final class ImportManager {

    // ── Scan ──

    func scanAudioFiles(root: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else { return [] }
        var found: [String] = []
        for case let rel as String in enumerator {
            if rel.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }
            let full = root + "/" + rel
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if !isDir.boolValue && ExtractedMetadata.isAudioFile(full) {
                found.append(full)
            }
        }
        return found
    }

    /// True if path is a directory (for drop handling).
    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    /// Detect cover image type from magic bytes; defaults to jpg.
    static func coverExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        return "jpg"
    }

    // ── Import ──

    func importFiles(files: [String], libraryDir: String, importMode: ImportMode,
                     progress: ((Int, Int) -> Void)? = nil,
                     completion: @escaping (ImportResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var result = ImportResult()
            let fm = FileManager.default

            for (index, filePath) in files.enumerated() {
                autoreleasepool {
                    guard let meta = MetadataExtractor.extract(atPath: filePath) else {
                        result.errors.append((filePath, "Unreadable audio file"))
                        return
                    }

                    let safe = { (s: String) -> String in
                        s.replacingOccurrences(of: "/", with: "_")
                    }
                    let baseName = (filePath as NSString).lastPathComponent
                    let ext = (filePath as NSString).pathExtension.lowercased()
                    let albumDir = libraryDir + "/" + safe(meta.artist) + "/" + safe(meta.album)
                    try? fm.createDirectory(atPath: albumDir, withIntermediateDirectories: true)

                    let targetPath = albumDir + "/" + baseName
                    let exists = fm.fileExists(atPath: targetPath)
                    if !exists {
                        if importMode == .symlink {
                            try? fm.createSymbolicLink(at: URL(fileURLWithPath: targetPath),
                                                       withDestinationURL: URL(fileURLWithPath: filePath))
                        } else {
                            try? fm.copyItem(atPath: filePath, toPath: targetPath)
                        }
                    }

                    // Cover art -> <albumDir>/.covers/cover.<ext>
                    var coverPath: String? = nil
                    if let artwork = meta.artwork, !artwork.isEmpty {
                        let coverDir = albumDir + "/.covers"
                        try? fm.createDirectory(atPath: coverDir, withIntermediateDirectories: true)
                        let cover = coverDir + "/cover." + ImportManager.coverExtension(for: artwork)
                        if !fm.fileExists(atPath: cover) {
                            try? artwork.write(to: URL(fileURLWithPath: cover), options: .atomic)
                        }
                        coverPath = cover
                    }

                    let track = Track(
                        id: 0,
                        title: meta.title,
                        artist: meta.artist,
                        album: meta.album,
                        trackNumber: meta.trackNumber,
                        discNumber: meta.discNumber,
                        genre: meta.genre,
                        year: meta.year,
                        duration: meta.duration,
                        filePath: targetPath,
                        fileName: baseName,
                        fileSize: meta.fileSize,
                        fileFormat: ext,
                        bitrate: meta.bitrate,
                        sampleRate: meta.sampleRate,
                        channels: meta.channels,
                        coverPath: coverPath,
                        replaygainGain: 0,
                        replaygainPeak: 0,
                        lrcPath: nil,
                        playCount: 0,
                        lastPlayedAt: nil,
                        importedAt: nil,
                        updatedAt: nil
                    )
                    _ = Database.shared.insertTrack(track)
                    if exists { result.skipped += 1 } else { result.imported += 1 }
                }
                DispatchQueue.main.async { progress?(index + 1, files.count) }
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
