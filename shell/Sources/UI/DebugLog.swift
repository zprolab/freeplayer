// FreePlayer shell — debug-only file logging helper.
// P4: File-based diagnostics are only active in DEBUG builds to avoid
// writing sensitive information to disk in release builds.

import Foundation
import os

enum DebugLog {
    /// Log a message to a file only in DEBUG builds. In Release, this is a no-op.
    static func file(_ msg: String, to filename: String) {
        #if DEBUG
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            let logLine = "[\(Date())] \(msg)\n"
            h.write(logLine.data(using: .utf8)!)
            try? h.close()
        }
        #endif
    }
}
