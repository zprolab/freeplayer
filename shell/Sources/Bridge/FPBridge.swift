// FreePlayer shell — fp注册层 (FreePlayer bridge registration).
//
// Registers every cross-platform bridge method into the generic BridgeCore.
// Platform differences (dialogs, media keys, login item, plugins, import-mode
// policy) are delegated to the PlatformBridge conformance (平台分配层) — either
// by calling it from a handler here (uploadLrc, playStart, setSetting,
// importFiles) or by the platform registering its own methods via
// PlatformBridge.registerAll (importDialog, getPlatform, login item, …).
//
// Behavior is ported verbatim from the former BridgeRouter.dispatch: same
// guards, same validation, same reply shapes. The renderer API
// (BridgeScript.swift / window.freeplayer) is untouched.

import Foundation
import UniformTypeIdentifiers   // saveCover: UTType
import ImageIO                  // saveCover: CGImageSource / CGImageDestination

enum FPBridge {

    /// Register every cross-platform method. Platform is resolved per call via
    /// AppContext (set before any renderer message can arrive), so registering
    /// early — even before the platform bridge exists — is safe.
    static func registerAll(into core: BridgeCore) {

        // ── Settings / setup ──
        core.register("isSetup") { call in
            let dir = Database.getSetting("library_dir", nil) as? String
            let libraryDirValue: Any = dir ?? NSNull()
            call.reply(["setup": dir != nil, "libraryDir": libraryDirValue])
        }

        core.register("getSetting") { call in
            let v = Database.getSetting(call.args.first as? String ?? "", nil)
            call.reply(v ?? (NSNull() as Any?))
        }

        core.register("setSetting") { call in
            guard let d = call.args.first as? [String: Any] else { call.reply(false); return }
            guard let key = d["key"] as? String, !key.isEmpty else { call.reply(false); return }
            if key == "library_dir" { call.reply(false); return } // NEW-2: trust anchor — native-only
            if key == "import_mode" {
                let mode = "\(d["value"] ?? "")"
                // iOS sandbox cannot symlink out of the container — copy only
                let allowed = AppContext.shared.platformBridge?.allowedImportModes ?? ["copy", "symlink"]
                guard allowed.contains(mode) else { call.reply(false); return }
                call.reply(Database.setSetting(key, mode)); return
            }
            let plain: Set<String> = [
                "volume", "tray_enabled", "tray_notify", "start_hidden",
                "start_on_boot", "default_volume", "default_visualizer",
                "mono_font", "ui_mode",
            ]
            if plain.contains(key)
                || key.hasPrefix("plugin.")
                || key.hasPrefix("plugin_perms_")
                || key.hasPrefix("meta.") {
                let value = d["value"] as? String ?? "\(d["value"] ?? "")"
                call.reply(Database.setSetting(key, value))
            } else {
                call.reply(false)
            }
        }

        core.register("setDiagnosticsEnabled") { call in
            let enabled = (call.args.first as? NSNumber)?.boolValue ?? false
            DebugLog.enabled = enabled
            DebugLog.file("DIAGNOSTICS enabled=\(enabled)")
            call.reply(true)
        }
        core.register("getDiagnosticsPath") { call in call.reply(DebugLog.path()) }
        core.register("clearDiagnostics") { call in DebugLog.clear(); call.reply(true) }
        core.register("logDiagnostic") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            let plugin = String(describing: d["pluginId"] ?? "unknown")
            let level = String(describing: d["level"] ?? "info")
            let message = String(describing: d["message"] ?? "")
            DebugLog.file("PLUGIN id=\(plugin) level=\(level) message=\(message)")
            call.reply(true)
        }

        // ── Equalizer ──
        core.register("getEqState") { call in
            call.reply(eqStateDict())
        }

        core.register("setEq") { call in
            guard let d = call.args.first as? [String: Any] else { call.reply(false); return }
            // S17: validate gains — exactly 10, finite, within ±24 dB
            guard let gains = d["gains"] as? [Any], gains.count == 10,
                  gains.allSatisfy({ ($0 as? NSNumber).map { $0.doubleValue.isFinite && $0.doubleValue >= -24 && $0.doubleValue <= 24 } ?? false }) else { call.reply(false); return }
            saveEq(d)
            broadcastEq()
            call.reply(true)
        }

        // ── Tracks ──
        core.register("getTracks") { call in
            let p = call.args.first as? [String: Any] ?? [:]
            let search = p["search"] as? String ?? ""
            let sortBy = p["sortBy"] as? String ?? "imported_at"
            let sortDir = p["sortDir"] as? String ?? "DESC"
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Database.getAllTracks(search, sortBy, sortDir)
                DispatchQueue.main.async { call.reply(rows) }
            }
        }

        core.register("getTrack") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getTrackById(tid)) }
            }
        }

        core.register("updateTrack") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            let tid = (d["id"] as? NSNumber)?.int64Value ?? 0
            call.reply(Database.updateTrack(tid, d))
        }

        core.register("deleteTrack") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            let track = Database.getTrackById(tid)
            let ok = Database.deleteTrack(tid)
            // S9: shared album covers: only remove when no other track references
            if ok, let track = track as? [String: Any] {
                if let cover = track["cover_path"] as? String, !cover.isEmpty,
                   Paths.isPathInLibrary(cover),
                   Database.countTracksWithCover(cover) == 0 {
                    let fm = FileManager.default
                    try? fm.removeItem(atPath: cover)
                    let coverDir = (cover as NSString).deletingLastPathComponent
                    if let leftover = try? fm.contentsOfDirectory(atPath: coverDir), leftover.isEmpty {
                        try? fm.removeItem(atPath: coverDir)
                    }
                }
            }
            call.reply(ok)
        }

        core.register("getTrackCount") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(NSNumber(value: Database.getTrackCount())) }
            }
        }

        core.register("getTotalDuration") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(NSNumber(value: Database.getTotalDuration())) }
            }
        }

        // ── Playback history ──
        core.register("playStart") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            let sid = Database.startPlaySession(tid)
            if let track = Database.getTrackById(tid) as? [String: Any] {
                AppContext.shared.platformBridge?.trackChanged(track: track) // tray / Control Center
            }
            call.reply(NSNumber(value: sid))
        }

        core.register("playEnd") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.endPlaySession(
                (d["sessionId"] as? NSNumber)?.int64Value ?? 0,
                (d["durationSeconds"] as? NSNumber)?.doubleValue ?? 0,
                (d["playPercentage"] as? NSNumber)?.doubleValue ?? 0))
        }

        // ── Stats ──
        core.register("getPlayHistory") { call in
            var limit = (call.args.first as? NSNumber)?.intValue ?? 50
            if limit < 1 || limit > 1000 { limit = 50 }
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getPlayHistory(limit)) }
            }
        }

        core.register("getStats") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getListeningStats()) }
            }
        }

        // ── Cover art ──
        core.register("getCover") { call in
            guard let coverPath = call.args.first as? String,
                  Paths.isPathInLibrary(coverPath) else {
                call.reply(NSNull()); return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: URL(fileURLWithPath: coverPath))
                var encoded: String?
                if let data {
                    let ext = (coverPath as NSString).pathExtension.lowercased()
                    let mime = ext == "png" ? "image/png"
                        : ext == "webp" ? "image/webp" : "image/jpeg"
                    encoded = "data:\(mime);base64,\(data.base64EncodedString())"
                }
                DispatchQueue.main.async { call.reply(encoded ?? NSNull()) }
            }
        }

        // ── Network (native stack: no CORS, stable on unreliable links) ──
        core.register("httpGetJson") { call in
            let urlStr = call.args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { result, data in
                    let parsed = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
                    result["body"] = parsed
                },
                { result in call.reply(result) })
        }

        core.register("httpGetBase64") { call in
            let urlStr = call.args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { result, data in
                    result["base64"] = data.base64EncodedString()
                },
                { result in call.reply(result) })
        }

        // ── Playlists ──
        core.register("getPlaylists") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getAllPlaylists()) }
            }
        }

        core.register("createPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            guard let name = d["name"] as? String, !name.isEmpty, name.count <= 512,
                  (d["description"] as? String ?? "").count <= 4096 else { call.reply(["lastInsertRowid": 0, "error": "invalid playlist"]); return }
            call.reply(["lastInsertRowid": NSNumber(value: Database.createPlaylist(
                name, d["description"] as? String))])
        }

        core.register("renamePlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.renamePlaylist((d["id"] as? NSNumber)?.int64Value ?? 0, d["name"] as? String))
        }

        core.register("deletePlaylist") { call in
            call.reply(Database.deletePlaylist((call.args.first as? NSNumber)?.int64Value ?? 0))
        }

        core.register("getPlaylistTracks") { call in
            let pid = (call.args.first as? NSNumber)?.int64Value ?? 0
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getPlaylistTracks(pid)) }
            }
        }

        core.register("addToPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.addTrackToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        }

        core.register("addTracksToPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            guard let ids = d["trackIds"] as? [Any], ids.count <= 10000 else { call.reply(false); return }
            call.reply(Database.addTracksToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                ids,
                startAt: 0))
        }

        core.register("setPlaylistTracks") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            guard let ids = d["trackIds"] as? [Any], ids.count <= 10000 else { call.reply(false); return }
            call.reply(Database.setPlaylistTracks(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                ids))
        }

        core.register("removeFromPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.removeTrackFromPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        }

        // ── LRC ──
        core.register("getLrc") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            var lrcPath = Database.getTrackLrc(tid)
            if lrcPath == nil {
                if let track = Database.getTrackById(tid) as? [String: Any],
                   let filePath = track["file_path"] as? String {
                    lrcPath = Metadata.findSidecarLrc(filePath)
                }
            }
            if lrcPath == nil || !FileManager.default.fileExists(atPath: lrcPath!) {
                call.reply(NSNull())
            } else {
                guard Paths.isPathInLibrary(lrcPath!) else { call.reply(NSNull()); return }
                let raw = try? Data(contentsOf: URL(fileURLWithPath: lrcPath!))
                let decoded = raw.flatMap { String(data: $0, encoding: .utf8) }
                    ?? raw.flatMap { String(data: $0, encoding: Metadata.gb18030) }
                if let decoded {
                    call.reply(["content": decoded, "path": lrcPath!])
                } else {
                    call.reply(NSNull())
                }
            }
        }

        core.register("setLrc") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            let lrcPath = d["lrcPath"] as? String ?? ""
            guard Paths.isPathInLibrary(lrcPath) else { call.reply(false); return }
            call.reply(Database.setTrackLrc((d["trackId"] as? NSNumber)?.int64Value ?? 0, lrcPath))
        }

        core.register("saveLrcContent") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            let content = call.args.count > 1 ? call.args[1] as? String : nil
            guard let content, !content.isEmpty,
                  let track = Database.getTrackById(tid) as? [String: Any],
                  let audioPath = track["file_path"] as? String else {
                call.reply(["success": false]); return
            }
            let audioStem = Metadata.cleanAudioStem(((audioPath as NSString).lastPathComponent as NSString).deletingPathExtension)
            let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("\(audioStem).\(tid)") + ".lrc"
            guard Paths.isPathInLibrary(target) else { call.reply(["success": false]); return }
            do { try content.write(to: URL(fileURLWithPath: target), atomically: true, encoding: .utf8) }
            catch { call.reply(["success": false]); return }
            let ok = Database.setTrackLrc(tid, target)
            call.reply(ok ? ["success": true, "lrcPath": target] : ["success": false])
        }

        core.register("saveCover") { call in
            saveCover(call: call)
        }

        core.register("removeLrc") { call in
            call.reply(Database.clearTrackLrc((call.args.first as? NSNumber)?.int64Value ?? 0))
        }

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

        // ── LRC upload: shared DB lookup, platform picker ──
        core.register("uploadLrc") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            guard let track = Database.getTrackById(tid) as? [String: Any],
                  let audioPath = track["file_path"] as? String else {
                call.reply(["error": "Track not found"]); return
            }
            guard let platform = AppContext.shared.platformBridge else {
                call.reject("platform not available"); return
            }
            platform.uploadLrc(trackId: tid, audioPath: audioPath) { call.reply($0) }
        }
    }

    // MARK: - Equalizer helpers (cross-platform)

    private static func eqKey(_ suffix: String) -> String { "eq.\(suffix)" }

    // internal (not private): EqSettingsTests round-trips saveEq → eqStateDict
    static func eqStateDict() -> [String: Any] {
        var gains: [NSNumber] = []
        if let raw = Database.getSetting(eqKey("gains"), nil) as? String {
            for p in raw.components(separatedBy: ",") {
                gains.append(NSNumber(value: Double(p) ?? 0))
            }
        }
        while gains.count < 10 { gains.append(NSNumber(value: 0)) }
        // saveEq stores enabled as "1"/"0"; accept legacy "true" too — the
        // reader must match the writer or every setEq broadcast reverts it.
        let enabledRaw = (Database.getSetting(eqKey("enabled"), nil) as? String) ?? "0"
        return [
            "enabled": enabledRaw == "1" || enabledRaw == "true",
            "preset": (Database.getSetting(eqKey("preset"), nil) as? String) ?? "Flat",
            "gains": gains,
        ]
    }

    static func saveEq(_ d: [String: Any]) {
        let gains = (d["gains"] as? [Any] ?? []).map { String(format: "%.1f", ($0 as? NSNumber)?.doubleValue ?? 0) }
        let tx = Database.beginTransaction()
        _ = Database.setSetting(eqKey("enabled"), ((d["enabled"] as? NSNumber)?.boolValue ?? false) ? "1" : "0")
        _ = Database.setSetting(eqKey("preset"), d["preset"] as? String ?? "Custom")
        _ = Database.setSetting(eqKey("gains"), gains.joined(separator: ","))
        if tx { _ = Database.commitTransaction() }
    }

    /// Native → renderer: sync the EQ state to every FreePlayer webview.
    private static func broadcastEq() {
        AppContext.shared.bridgeCore?.emit("_pushEq", eqStateDict())
    }

    // MARK: - Save cover (cross-platform: CGImage + FileManager)

    private static func saveCover(call: BridgeCall) {
        let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
        let b64 = call.args.count > 1 ? call.args[1] as? String : nil
        guard let track = Database.getTrackById(tid) as? [String: Any],
              let b64, !b64.isEmpty,
              let audioPath = track["file_path"] as? String else {
            call.reply(["success": false]); return
        }
        guard let img = Data(base64Encoded: b64) else { call.reply(["success": false]); return }
        if b64.count > 7 * 1024 * 1024 || img.count > 5 * 1024 * 1024 {
            call.reply(["success": false]); return
        }
        // CGImage validation + JPEG re-encode
        guard let src = CGImageSourceCreateWithData(img as CFData, nil),
              let srcType = CGImageSourceGetType(src),
              let imgType = UTType(srcType as String) else {
            call.reply(["success": false]); return
        }
        let known = imgType.conforms(to: .jpeg) || imgType.conforms(to: .png)
            || imgType.conforms(to: .webP) || imgType.conforms(to: .heic)
        guard known else { call.reply(["success": false]); return }

        var outImg = img
        if !imgType.conforms(to: .jpeg) {
            guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                call.reply(["success": false]); return
            }
            let jpegData = NSMutableData()
            guard let dst = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
                call.reply(["success": false]); return
            }
            CGImageDestinationAddImage(dst, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(dst) else { call.reply(["success": false]); return }
            outImg = jpegData as Data
        }
        let coverDir = ((audioPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(".covers")
        let fm = FileManager.default
        if !fm.fileExists(atPath: coverDir) {
            do { try fm.createDirectory(atPath: coverDir, withIntermediateDirectories: true) }
            catch { call.reply(["success": false]); return }
        }
        let coverPath = (coverDir as NSString).appendingPathComponent("cover-\(tid).jpg")
        guard Paths.isPathInLibrary(coverPath) else { call.reply(["success": false]); return }
        do { try outImg.write(to: URL(fileURLWithPath: coverPath), options: .atomic) }
        catch { call.reply(["success": false]); return }
        let ok = Database.setTrackCover(tid, coverPath)
        call.reply(ok ? ["success": true, "coverPath": coverPath] : ["success": false])
    }
}

/// 组装（composition root）：把 fp 层 + 平台层一起注册进共享 BridgeCore，
/// 并接好出站事件。幂等——重复调用返回同一个 core。
enum BridgeBootstrap {
    static func install() -> BridgeCore {
        if let core = AppContext.shared.bridgeCore { return core }
        let core = BridgeCore()
        FPBridge.registerAll(into: core)
        AppContext.shared.platformBridge?.registerAll(into: core)
        core.emitter = { channel, payload in
            BridgeEmitter.push(channel, payload)
        }
        AppContext.shared.bridgeCore = core
        return core
    }
}
