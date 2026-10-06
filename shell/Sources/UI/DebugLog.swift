// FreePlayer shell — debug-only file logging helper.
// P4: File-based diagnostics are only active in DEBUG builds to avoid
// writing sensitive information to disk in release builds.

import Foundation
import os

enum DebugLog {
    // Deliberately fixed and documented so a user can always find diagnostics.
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FreePlayer/diagnostics", isDirectory: true)
    static let url = directory.appendingPathComponent("freeplayer-diagnostics.log")

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "FP_DIAGNOSTICS_ENABLED") }
        set { UserDefaults.standard.set(newValue, forKey: "FP_DIAGNOSTICS_ENABLED") }
    }

    static func path() -> String { url.path }

    // Serializes the read-modify-write in file(_:) (exists → rotate → append).
    // Callers run on the main thread (bridge), a global import queue and the
    // scheme handler at once; unsynchronized, two threads could both rotate or
    // interleave seekToEnd+write and corrupt/lose a log line.
    private static let queue = DispatchQueue(label: "com.zprolab.FreePlayer.diagnostics")

    static func file(_ msg: String, to filename: String? = nil) {
        guard enabled else { return }
        let target = filename.map { directory.appendingPathComponent($0) } ?? url
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path),
                   let size = try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber,
                   size.intValue > 20 * 1024 * 1024 {
                    let backup = target.deletingPathExtension().appendingPathExtension("old.log")
                    try? FileManager.default.removeItem(at: backup)
                    try? FileManager.default.moveItem(at: target, to: backup)
                }
                if !FileManager.default.fileExists(atPath: target.path) { FileManager.default.createFile(atPath: target.path, contents: nil) }
                let h = try FileHandle(forWritingTo: target)
                h.seekToEndOfFile()
                let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
                h.write(Data(line.utf8)); try h.close()
            } catch { NSLog("[diagnostics] cannot write log: %@", error.localizedDescription) }
        }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}
