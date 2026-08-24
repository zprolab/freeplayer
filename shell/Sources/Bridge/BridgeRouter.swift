// FreePlayer shell — cross-platform bridge method dispatch.
// Platform-specific calls go through the PlatformBridge protocol
// (implemented by MacPlatformBridge on macOS, IPadPlatformBridge on iPad).

import Foundation
import WebKit
import UniformTypeIdentifiers
import WebKit

final class BridgeRouter {

    /// Dispatch a single bridge method.  Every platform-agnostic path lives here;
    /// platform-specific paths delegate to AppContext.shared.platformBridge.
    func dispatch(method: String, args: [Any], idNum: NSNumber,
                  reply: @escaping (NSNumber, Any?) -> Void,
                  reject: @escaping (NSNumber, String?) -> Void) {

        let platform = AppContext.shared.platformBridge

        // ── Platform identity (renderer adapts its UI: iOS has a fixed
        // in-sandbox library and copy-only import; macOS has panels + symlink) ──
        if method == "getPlatform" {
            #if os(iOS)
            reply(idNum, "ios")
            #else
            reply(idNum, "macos")
            #endif
        }
        // ── Settings / setup ──
        else if method == "isSetup" {
            let dir = Database.getSetting("library_dir", nil) as? String
            let libraryDirValue: Any = dir ?? NSNull()
            reply(idNum, ["setup": dir != nil, "libraryDir": libraryDirValue])
        } else if method == "getSetting" {
            let v = Database.getSetting(args.first as? String ?? "", nil)
            reply(idNum, v ?? (NSNull() as Any?))
        } else if method == "setSetting" {
            guard let d = args.first as? [String: Any] else { reply(idNum, false); return }
            guard let key = d["key"] as? String, !key.isEmpty else { reply(idNum, false); return }
            if key == "library_dir" { reply(idNum, false); return } // NEW-2: trust anchor — native-only
            if key == "import_mode" {
                let mode = "\(d["value"] ?? "")"
                #if os(iOS)
                // iOS sandbox cannot symlink out of the container — copy only
                guard mode == "copy" else { reply(idNum, false); return }
                #else
                guard mode == "copy" || mode == "symlink" else { reply(idNum, false); return }
                #endif
                reply(idNum, Database.setSetting(key, mode)); return
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
                reply(idNum, Database.setSetting(key, value))
            } else {
                reply(idNum, false)
            }
        }
        // ── Equalizer ──
        else if method == "getEqState" {
            reply(idNum, eqStateDict())
        } else if method == "setEq" {
            guard let d = args.first as? [String: Any] else { reply(idNum, false); return }
            // S17: validate gains — exactly 10, finite, within ±24 dB
            guard let gains = d["gains"] as? [Any], gains.count == 10,
                  gains.allSatisfy({ ($0 as? NSNumber).map { $0.doubleValue.isFinite && $0.doubleValue >= -24 && $0.doubleValue <= 24 } ?? false }) else { reply(idNum, false); return }
            saveEq(d)
            broadcastEq()
            reply(idNum, true)
        }
        // ── Tracks ──
        else if method == "getTracks" {
            let p = args.first as? [String: Any] ?? [:]
            let search = p["search"] as? String ?? ""
            let sortBy = p["sortBy"] as? String ?? "imported_at"
            let sortDir = p["sortDir"] as? String ?? "DESC"
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Database.getAllTracks(search, sortBy, sortDir)
                DispatchQueue.main.async { reply(mid, rows) }
            }
        } else if method == "getTrack" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, Database.getTrackById(tid)) }
            }
        } else if method == "updateTrack" {
            let d = args.first as? [String: Any] ?? [:]
            let tid = (d["id"] as? NSNumber)?.int64Value ?? 0
            reply(idNum, Database.updateTrack(tid, d))
        } else if method == "deleteTrack" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
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
            reply(idNum, ok)
        } else if method == "getTrackCount" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, NSNumber(value: Database.getTrackCount())) }
            }
        } else if method == "getTotalDuration" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, NSNumber(value: Database.getTotalDuration())) }
            }
        }
        // ── Playback history ──
        else if method == "playStart" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let sid = Database.startPlaySession(tid)
            if let track = Database.getTrackById(tid) as? [String: Any] {
                platform?.trackChanged(track: track) // tray / Control Center
            }
            reply(idNum, NSNumber(value: sid))
        } else if method == "playEnd" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.endPlaySession(
                (d["sessionId"] as? NSNumber)?.int64Value ?? 0,
                (d["durationSeconds"] as? NSNumber)?.doubleValue ?? 0,
                (d["playPercentage"] as? NSNumber)?.doubleValue ?? 0))
        }
        // ── Stats ──
        else if method == "getPlayHistory" {
            var limit = (args.first as? NSNumber)?.intValue ?? 50
            if limit < 1 || limit > 1000 { limit = 50 }
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, Database.getPlayHistory(limit)) }
            }
        } else if method == "getStats" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, Database.getListeningStats()) }
            }
        }
        // ── Cover art ──
        else if method == "getCover" {
            guard let coverPath = args.first as? String, Paths.isPathInLibrary(coverPath) else {
                reply(idNum, NSNull()); return
            }
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: URL(fileURLWithPath: coverPath))
                var encoded: String?
                if let data {
                    let ext = (coverPath as NSString).pathExtension.lowercased()
                    let mime = ext == "png" ? "image/png"
                        : ext == "webp" ? "image/webp" : "image/jpeg"
                    encoded = "data:\(mime);base64,\(data.base64EncodedString())"
                }
                DispatchQueue.main.async { reply(mid, encoded ?? NSNull()) }
            }
        }
        // ── Network ──
        else if method == "httpGetJson" {
            let urlStr = args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { result, data in
                    let parsed = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
                    result["body"] = parsed
                },
                { result in reply(idNum, result) })
        } else if method == "httpGetBase64" {
            let urlStr = args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { result, data in
                    result["base64"] = data.base64EncodedString()
                },
                { result in reply(idNum, result) })
        }
        // ── Playlists ──
        else if method == "getPlaylists" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, Database.getAllPlaylists()) }
            }
        } else if method == "createPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            guard let name = d["name"] as? String, !name.isEmpty, name.count <= 512,
                  (d["description"] as? String ?? "").count <= 4096 else { reply(idNum, ["lastInsertRowid": 0, "error": "invalid playlist"]); return }
            reply(idNum, ["lastInsertRowid": NSNumber(value: Database.createPlaylist(
                name, d["description"] as? String))])
        } else if method == "renamePlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.renamePlaylist((d["id"] as? NSNumber)?.int64Value ?? 0, d["name"] as? String))
        } else if method == "deletePlaylist" {
            reply(idNum, Database.deletePlaylist((args.first as? NSNumber)?.int64Value ?? 0))
        } else if method == "getPlaylistTracks" {
            let pid = (args.first as? NSNumber)?.int64Value ?? 0
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { reply(mid, Database.getPlaylistTracks(pid)) }
            }
        } else if method == "addToPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.addTrackToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        } else if method == "addTracksToPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            guard let ids = d["trackIds"] as? [Any], ids.count <= 10000 else { reply(idNum, false); return }
            reply(idNum, Database.addTracksToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                ids,
                startAt: 0))
        } else if method == "setPlaylistTracks" {
            let d = args.first as? [String: Any] ?? [:]
            guard let ids = d["trackIds"] as? [Any], ids.count <= 10000 else { reply(idNum, false); return }
            reply(idNum, Database.setPlaylistTracks(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                ids))
        } else if method == "removeFromPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.removeTrackFromPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        }
        // ── LRC ──
        else if method == "getLrc" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            var lrcPath = Database.getTrackLrc(tid)
            if lrcPath == nil {
                if let track = Database.getTrackById(tid) as? [String: Any],
                   let filePath = track["file_path"] as? String {
                    lrcPath = Metadata.findSidecarLrc(filePath)
                }
            }
            if lrcPath == nil || !FileManager.default.fileExists(atPath: lrcPath!) {
                reply(idNum, NSNull())
            } else {
                guard Paths.isPathInLibrary(lrcPath!) else { reply(idNum, NSNull()); return }
                let raw = try? Data(contentsOf: URL(fileURLWithPath: lrcPath!))
                let decoded = raw.flatMap { String(data: $0, encoding: .utf8) }
                    ?? raw.flatMap { String(data: $0, encoding: Metadata.gb18030) }
                if let decoded {
                    reply(idNum, ["content": decoded, "path": lrcPath!])
                } else {
                    reply(idNum, NSNull())
                }
            }
        } else if method == "setLrc" {
            let d = args.first as? [String: Any] ?? [:]
            let lrcPath = d["lrcPath"] as? String ?? ""
            guard Paths.isPathInLibrary(lrcPath) else { reply(idNum, false); return }
            reply(idNum, Database.setTrackLrc((d["trackId"] as? NSNumber)?.int64Value ?? 0, lrcPath))
        } else if method == "saveLrcContent" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let content = args.count > 1 ? args[1] as? String : nil
            guard let content, !content.isEmpty,
                  let track = Database.getTrackById(tid) as? [String: Any],
                  let audioPath = track["file_path"] as? String else {
                reply(idNum, ["success": false]); return
            }
            let audioStem = Metadata.cleanAudioStem(((audioPath as NSString).lastPathComponent as NSString).deletingPathExtension)
            let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("\(audioStem).\(tid)") + ".lrc"
            guard Paths.isPathInLibrary(target) else { reply(idNum, ["success": false]); return }
            do { try content.write(to: URL(fileURLWithPath: target), atomically: true, encoding: .utf8) }
            catch { reply(idNum, ["success": false]); return }
            let ok = Database.setTrackLrc(tid, target)
            reply(idNum, ok ? ["success": true, "lrcPath": target] : ["success": false])
        } else if method == "saveCover" {
            saveCover(args: args, idNum: idNum, reply: reply)
        } else if method == "removeLrc" {
            reply(idNum, Database.clearTrackLrc((args.first as? NSNumber)?.int64Value ?? 0))
        }
        // ── Import pipeline ──
        else if method == "scanDirectory" {
            let dir = args.first as? String ?? ""
            guard AppContext.shared.isTrustedScanRoot(dir) else { reply(idNum, []); return }
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ImportPipeline.scanAudioFiles(dir)
                // P2: Return truncation info so the UI can warn the user
                let response: [String: Any] = [
                    "files": result.files,
                    "truncated": result.truncated,
                    "scannedCount": result.scannedCount
                ]
                DispatchQueue.main.async { reply(mid, response) }
            }
        } else if method == "importFiles" {
            // S5: validate the payload shape BEFORE touching a background queue —
            // malformed args must never reach the importer. S17: cap the batch
            // and require every file to live under a trusted scan root.
            guard let data = args.first as? [String: Any],
                  let files = data["files"] as? [Any],
                  files.count > 0, files.count <= 1000,
                  files.allSatisfy({ ($0 as? String).map { AppContext.shared.isTrustedScanRoot(($0 as NSString).deletingLastPathComponent) } ?? false }) else {
                reply(idNum, ["imported": 0, "errors": [], "error": "bad import payload"]); return
            }
            guard let storedLib = Database.getSetting("library_dir", nil) as? String,
                  !storedLib.isEmpty else {
                reply(idNum, ["imported": 0, "errors": [], "error": "library not set"]); return
            }
            let importMode = (Database.getSetting("import_mode", "copy") as? String) ?? "copy"
            // iOS sandbox cannot create symlinks into (or read-through) picked
            // folders — always copy on iOS, whatever the stored preference says.
            #if os(iOS)
            let effectiveMode = "copy"
            #else
            let effectiveMode = importMode
            #endif
            let mid = idNum
            ImportPipeline.runImport(files: files.compactMap { $0 as? String }, storedLib: storedLib, importMode: effectiveMode) { result in
                reply(mid, result)
            }
        }
        // ── EQ state (cross-platform) ──
        else if method == "getEqState" {
            reply(idNum, eqStateDict())
        } else if method == "setEq" {
            guard let d = args.first as? [String: Any] else { reply(idNum, false); return }
            saveEq(d); broadcastEq(); reply(idNum, true)
        }
        // ── Platform-specific: delegate everything else ──
        else { platformBridgeDispatch(method: method, args: args, idNum: idNum, platform: platform, reply: reply, reject: reject) }
    }

    // MARK: - Platform-delegated dispatch

    private func platformBridgeDispatch(method: String, args: [Any], idNum: NSNumber,
                                        platform: PlatformBridge?,
                                        reply: @escaping (NSNumber, Any?) -> Void,
                                        reject: @escaping (NSNumber, String?) -> Void) {
        guard let platform else {
            reject(idNum, "platform not available"); return
        }
        switch method {
        case "__dragStart":
            platform.handleDragStart(sx: args.first as? Double ?? 0,
                                     sy: (args.count > 1 ? args[1] as? Double : 0) ?? 0)
        case "openEqWindow":
            platform.openEqWindow(); reply(idNum, true)
        case "finishOnboarding":
            platform.finishOnboarding(); reply(idNum, true)
        case "setAppearance":
            let d = args.first as? [String: Any] ?? [:]
            platform.setAppearance(dark: (d["dark"] as? Bool) ?? true)
            reply(idNum, true)
        case "resetDatabase":
            reply(idNum, platform.resetDatabase())
        case "sendPlaybackState":
            let d = args.first as? [String: Any] ?? [:]
            platform.sendPlaybackState(playing: (d["isPlaying"] as? NSNumber)?.boolValue ?? false)
            reply(idNum, NSNull())
        case "getLoginItemSettings":
            reply(idNum, platform.getLoginItemSettings())
        case "setLoginItemSettings":
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, ["ok": platform.setLoginItemSettings(d)])
        case "listPlugins":
            reply(idNum, platform.listPlugins())
        case "readPluginFile":
            let pid = args.first as? String ?? ""
            let rel = args.count > 1 ? args[1] as? String : nil
            reply(idNum, platform.readPluginFile(pid, rel ?? "") ?? NSNull())
        case "openPluginsDir":
            platform.openPluginsDir(); reply(idNum, true)
        case "uninstallPlugin":
            reply(idNum, platform.uninstallPlugin(args.first as? String ?? ""))
        case "importDialog":
            platform.importDialog { reply(idNum, $0) }
        case "selectLibraryDir":
            platform.selectLibraryDir { reply(idNum, $0) }
        case "uploadLrc":
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            guard let track = Database.getTrackById(tid) as? [String: Any],
                  let audioPath = track["file_path"] as? String else {
                reply(idNum, ["error": "Track not found"]); return
            }
            platform.uploadLrc(trackId: tid, audioPath: audioPath) { reply(idNum, $0) }
        default:
            reject(idNum, "not implemented: \(method)")
        }
    }

    // MARK: - Equalizer helpers (cross-platform, used by dispatch above)

    private func eqKey(_ suffix: String) -> String { "eq.\(suffix)" }

    private func eqStateDict() -> [String: Any] {
        var gains: [NSNumber] = []
        if let raw = Database.getSetting(eqKey("gains"), nil) as? String {
            for p in raw.components(separatedBy: ",") {
                gains.append(NSNumber(value: Double(p) ?? 0))
            }
        }
        while gains.count < 10 { gains.append(NSNumber(value: 0)) }
        return [
            "enabled": (Database.getSetting(eqKey("enabled"), nil) as? String) == "true",
            "preset": (Database.getSetting(eqKey("preset"), nil) as? String) ?? "平坦",
            "gains": gains,
        ]
    }

    private func saveEq(_ d: [String: Any]) {
        let gains = (d["gains"] as? [Any] ?? []).map { String(format: "%.1f", ($0 as? NSNumber)?.doubleValue ?? 0) }
        let tx = Database.beginTransaction()
        _ = Database.setSetting(eqKey("enabled"), ((d["enabled"] as? NSNumber)?.boolValue ?? false) ? "1" : "0")
        _ = Database.setSetting(eqKey("preset"), d["preset"] as? String ?? "自定义")
        _ = Database.setSetting(eqKey("gains"), gains.joined(separator: ","))
        if tx { _ = Database.commitTransaction() }
    }

    func broadcastEq() {
        DispatchQueue.main.async {
            guard let data = try? JSONSerialization.data(withJSONObject: self.eqStateDict()),
                  let json = String(data: data, encoding: .utf8) else { return }
            let js = "window.freeplayer._pushEq(\(json))"
            AppContext.shared.webView?.evaluateJavaScript(js)
            AppContext.shared.eqWebView?.evaluateJavaScript(js)
        }
    }

    // MARK: - Save cover (cross-platform: CGImage + FileManager)

    private func saveCover(args: [Any], idNum: NSNumber,
                           reply: @escaping (NSNumber, Any?) -> Void) {
        let tid = (args.first as? NSNumber)?.int64Value ?? 0
        let b64 = args.count > 1 ? args[1] as? String : nil
        guard let track = Database.getTrackById(tid) as? [String: Any],
              let b64, !b64.isEmpty,
              let audioPath = track["file_path"] as? String else {
            reply(idNum, ["success": false]); return
        }
        guard let img = Data(base64Encoded: b64) else { reply(idNum, ["success": false]); return }
        if b64.count > 7 * 1024 * 1024 || img.count > 5 * 1024 * 1024 {
            reply(idNum, ["success": false]); return
        }
        // CGImage validation + JPEG re-encode
        guard let src = CGImageSourceCreateWithData(img as CFData, nil),
              let srcType = CGImageSourceGetType(src),
              let imgType = UTType(srcType as String) else {
            reply(idNum, ["success": false]); return
        }
        let known = imgType.conforms(to: .jpeg) || imgType.conforms(to: .png)
            || imgType.conforms(to: .webP) || imgType.conforms(to: .heic)
        guard known else { reply(idNum, ["success": false]); return }

        var outImg = img
        if !imgType.conforms(to: .jpeg) {
            guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                reply(idNum, ["success": false]); return
            }
            let jpegData = NSMutableData()
            guard let dst = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
                reply(idNum, ["success": false]); return
            }
            CGImageDestinationAddImage(dst, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(dst) else { reply(idNum, ["success": false]); return }
            outImg = jpegData as Data
        }
        let coverDir = ((audioPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(".covers")
        let fm = FileManager.default
        if !fm.fileExists(atPath: coverDir) {
            do { try fm.createDirectory(atPath: coverDir, withIntermediateDirectories: true) }
            catch { reply(idNum, ["success": false]); return }
        }
        let coverPath = (coverDir as NSString).appendingPathComponent("cover-\(tid).jpg")
        guard Paths.isPathInLibrary(coverPath) else { reply(idNum, ["success": false]); return }
        do { try outImg.write(to: URL(fileURLWithPath: coverPath), options: .atomic) }
        catch { reply(idNum, ["success": false]); return }
        let ok = Database.setTrackCover(tid, coverPath)
        reply(idNum, ok ? ["success": true, "coverPath": coverPath] : ["success": false])
    }
}