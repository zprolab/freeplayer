// FreePlayer shell — fp layer: library import pipeline.
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation

extension FPBridge {

    static func registerImport(into core: BridgeCore) {
        // ── Import pipeline ──
        core.register("scanDirectory") { call in
            let dir = call.args.first as? String ?? ""
            DebugLog.file("IMPORT_SCAN_START dir=\(dir) trusted=\(AppContext.shared.isTrustedScanRoot(dir))")
            guard AppContext.shared.isTrustedScanRoot(dir) else { DebugLog.file("IMPORT_SCAN_REJECT dir=\(dir) reason=untrusted-root"); call.reply([]); return }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ImportPipeline.scanAudioFiles(dir)
                DebugLog.file("IMPORT_SCAN_RESULT dir=\(dir) files=\(result.files.count) scanned=\(result.scannedCount) truncated=\(result.truncated)")
                // P2: Return truncation info so the UI can warn the user
                let response: [String: Any] = [
                    "files": result.files,
                    "truncated": result.truncated,
                    "scannedCount": result.scannedCount
                ]
                DispatchQueue.main.async { call.reply(response) }
            }
        }

        core.register("importFiles") { call in
            // S5: validate the payload shape BEFORE touching a background queue —
            // malformed args must never reach the importer. S17: cap the batch
            // and require every file to live under a trusted scan root.
            DebugLog.file("IMPORT_START args=\(String(describing: call.args.first))")
            guard let data = call.args.first as? [String: Any],
                  let files = data["files"] as? [Any],
                  files.count > 0, files.count <= 1000,
                  files.allSatisfy({ ($0 as? String).map { AppContext.shared.isTrustedScanRoot(($0 as NSString).deletingLastPathComponent) } ?? false }) else {
                DebugLog.file("IMPORT_REJECT reason=bad-payload"); call.reply(["imported": 0, "errors": [], "error": "bad import payload"]); return
            }
            guard let storedLib = Database.getSetting("library_dir", nil) as? String,
                  !storedLib.isEmpty else {
                DebugLog.file("IMPORT_REJECT reason=library-not-set"); call.reply(["imported": 0, "errors": [], "error": "library not set"]); return
            }
            let importMode = (Database.getSetting("import_mode", "copy") as? String) ?? "copy"
            // iOS sandbox cannot create symlinks into (or read-through) picked
            // folders — always copy on iOS, whatever the stored preference says.
            let allowed = AppContext.shared.platformBridge?.allowedImportModes ?? ["copy", "symlink"]
            let effectiveMode = allowed.contains(importMode) ? importMode : "copy"
            DebugLog.file("IMPORT_ACCEPT files=\(files.count) library=\(storedLib) requestedMode=\(importMode) effectiveMode=\(effectiveMode)")
            ImportPipeline.runImport(files: files.compactMap { $0 as? String },
                                     storedLib: storedLib,
                                     importMode: effectiveMode) { result in
                DebugLog.file("IMPORT_RESULT result=\(String(describing: result))")
                call.reply(result)
            }
        }
    }
}
