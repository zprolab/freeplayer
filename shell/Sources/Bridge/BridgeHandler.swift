// FreePlayer shell — JS<->native bridge method dispatch (WKScriptMessageHandler).
// Replies serialize with JSONSerialization (.fragmentsAllowed) so bare numbers /
// booleans / null round-trip exactly like the ObjC++ port.

import Cocoa
import WebKit
import UniformTypeIdentifiers
import ImageIO

final class BridgeHandler: NSObject, WKScriptMessageHandler {

    // S16: page console output goes to the system log — truncate and redact
    // common secret patterns (Bearer tokens, api keys, passwords, auth headers).
    private static let redactionPatterns: [NSRegularExpression] = [
        #"(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+"#,
        #"(?i)(api[_-]?key\s*[:=]\s*)[^\s,;]+"#,
        #"(?i)(password\s*[:=]\s*)[^\s,;]+"#,
        #"(?i)(authorization\s*[:=]\s*)[^\s,;]+"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static func redactConsole(_ msg: String) -> String {
        var m = msg
        if m.count > 300 { m = String(m.prefix(300)) }
        for re in redactionPatterns {
            m = re.stringByReplacingMatches(
                in: m, options: [], range: NSRange(location: 0, length: (m as NSString).length),
                withTemplate: "$1***")
        }
        return m
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "freeplayer" else { return }
        // S2: only main-frame messages from a webview this app owns — a subframe
        // (or a stray page in another webview) must never reach the bridge.
        guard message.frameInfo.isMainFrame,
              let webView = message.webView,
              AppContext.shared.isAppWebView(webView) else { return }
        guard let body = message.body as? [String: Any],
              let idNum = body["id"] as? NSNumber,
              let method = body["method"] as? String else { return }
        let args = body["args"] as? [Any] ?? []

        // reply: window.freeplayer._resolve(id, <json>)
        func reply(_ mid: NSNumber, _ obj: Any?) {
            let json: String
            if obj == nil || obj is NSNull {
                json = "null" // NSNull is not a valid JSON top-level type
            } else {
                let data = try? JSONSerialization.data(
                    withJSONObject: obj as Any,
                    options: [.fragmentsAllowed])
                guard let data, let s = String(data: data, encoding: .utf8) else {
                    NSLog("[shell] reply serialization failed for %@", mid)
                    return
                }
                json = s
            }
            // M2: JSON-encode the message — a JSON string is always valid JS
            webView.evaluateJavaScript("window.freeplayer._resolve(\(mid.int64Value), \(json))")
        }

        // M2: JSON-encode the error — a JSON string is always valid JS
        func reject(_ mid: NSNumber, _ why: String?) {
            let data = try? JSONSerialization.data(withJSONObject: why ?? "error")
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"error\""
            webView.evaluateJavaScript("window.freeplayer._reject(\(mid.int64Value), \(json))")
        }

        if method == "__ready" {
            NSLog("[shell] bridge ready, %@", webView.url?.absoluteString ?? "?")
            // Diagnostics toggles (set after the page is up, avoids injection races)
            if UserDefaults.standard.bool(forKey: "FP_SPECTRO_TEST") {
                webView.evaluateJavaScript("window.__FP_SPECTRO_TEST = true;")
            }
            return
        }
        if method == "__console" {
            let a = args
            let level = (a.first as? String) ?? "log"
            let text = (a.count > 1 && a[1] is String) ? (a[1] as! String) : ""
            NSLog("[page %@] %@", level, Self.redactConsole(text))
            return
        }
        if method == "__dragStart" {
            // Kick off AppKit's modal window drag with a synthetic mouse event.
            // Q3: WKWebView reports MouseEvent.screenX/screenY in points (CSS
            // pixels) already — do NOT scale by backingScaleFactor or the grab
            // point lands at 2x the real cursor on Retina and the window flies.
            // Use the screen that contains the window (multi-screen).
            guard let win = webView.window else { return }
            let sx = (args.first as? NSNumber)?.doubleValue ?? 0
            let sy = (args.count > 1 ? (args[1] as? NSNumber)?.doubleValue : 0) ?? 0
            let screen = win.screen ?? NSScreen.main
            let screenH = screen?.frame.height ?? 0
            let pRaw = NSPoint(x: sx, y: screenH - sy)
            let p = win.convertPoint(fromScreen: pRaw)
            let evt = NSEvent.mouseEvent(
                with: .leftMouseDown, location: p, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)
            if let evt { win.performDrag(with: evt) }
            return
        }

        // M7: verbose IPC logging gated behind FP_VERBOSE (env or defaults)
        if AppContext.shared.verboseLogging { NSLog("[shell] method=%@", method) }

        self.dispatch(method: method, args: args, idNum: idNum, webView: webView, reply: reply, reject: reject)
    }

    private func dispatch(method: String, args: [Any], idNum: NSNumber,
                          webView: WKWebView,
                          reply: @escaping (NSNumber, Any?) -> Void,
                          reject: @escaping (NSNumber, String?) -> Void) {
        // ── Settings / setup ──
        if method == "isSetup" {
            let dir = Database.getSetting("library_dir", nil) as? String
            let libraryDirValue: Any = dir ?? NSNull()
            reply(idNum, ["setup": dir != nil, "libraryDir": libraryDirValue])
        } else if method == "getSetting" {
            let v = Database.getSetting(args.first as? String ?? "", nil)
            reply(idNum, v ?? (NSNull() as Any?))
        } else if method == "setSetting" {
            guard let d = args.first as? [String: Any] else { reply(idNum, false); return }
            guard let key = d["key"] as? String, !key.isEmpty else { reply(idNum, false); return }
            // NEW-2: library_dir is the trust anchor for the file-read boundary —
            // only the native NSOpenPanel flows (importDialog/selectLibraryDir) may
            // set it; a renderer-writable anchor would let XSS widen the boundary
            // and read arbitrary files via getCover/media:///getLrc.
            if key == "library_dir" { reply(idNum, false); return }
            // S3c/Q11: renderer-writable keys are allowlisted — everything else
            // (incl. import_mode with an unvalidated value) is rejected.
            if key == "import_mode" {
                let mode = "\(d["value"] ?? "")"
                guard mode == "copy" || mode == "symlink" else { reply(idNum, false); return }
                reply(idNum, Database.setSetting(key, mode))
                return
            }
            let plain: Set<String> = [
                "volume", "tray_enabled", "tray_notify", "start_hidden",
                "start_on_boot", "default_volume", "default_visualizer",
                "mono_font",
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
        } else if method == "getEqState" {
            reply(idNum, eqStateDict())
        } else if method == "setEq" {
            guard let d = args.first as? [String: Any] else { reply(idNum, false); return }
            saveEq(d)
            broadcastEq()
            reply(idNum, true)
        } else if method == "openEqWindow" {
            Windows.openEqWindow()
            reply(idNum, true)
        } else if method == "resetDatabase" {
            // S8: the renderer's own confirm dialog is not enough — one IPC call
            // wipes every track/playlist/history entry AND all settings, so gate
            // it behind a native confirmation dialog too.
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Reset Database"
            alert.informativeText = "This will permanently delete all tracks, playlists, listening history, and settings. This cannot be undone."
            alert.addButton(withTitle: "Reset Everything")
            alert.addButton(withTitle: "Cancel")
            reply(idNum, alert.runModal() == .alertFirstButtonReturn && Database.resetDatabase())
        }
        // ── Tracks (H2: read-heavy queries + reply JSON off the main thread) ──
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
                let track = Database.getTrackById(tid)
                DispatchQueue.main.async { reply(mid, track) }
            }
        } else if method == "updateTrack" {
            let d = args.first as? [String: Any] ?? [:]
            let tid = (d["id"] as? NSNumber)?.int64Value ?? 0
            reply(idNum, Database.updateTrack(tid, d))
        } else if method == "deleteTrack" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let track = Database.getTrackById(tid)
            var ok = Database.deleteTrack(tid)
            // S9: remove the track's cover file ONLY when no other track still
            // references it. Album covers (import writes <album>/.covers/cover.jpg)
            // are SHARED by every track of the album — deleting one track must not
            // wipe the other tracks' covers. Auto-fetched covers are per-track
            // (cover-<tid>.jpg), so this guard only fires for shared files.
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
                let n = Database.getTrackCount()
                DispatchQueue.main.async { reply(mid, NSNumber(value: n)) }
            }
        } else if method == "getTotalDuration" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let d = Database.getTotalDuration()
                DispatchQueue.main.async { reply(mid, NSNumber(value: d)) }
            }
        }
        // ── Playback history ──
        else if method == "playStart" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let sid = Database.startPlaySession(tid)
            // Tray + Control Center: track info straight from the DB (safe objects)
            if let track = Database.getTrackById(tid) as? [String: Any] {
                Tray.shared.setNowPlaying(fromTrack: track)
            }
            reply(idNum, NSNumber(value: sid))
        } else if method == "playEnd" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.endPlaySession(
                (d["sessionId"] as? NSNumber)?.int64Value ?? 0,
                (d["durationSeconds"] as? NSNumber)?.doubleValue ?? 0,
                (d["playPercentage"] as? NSNumber)?.doubleValue ?? 0))
        }
        // ── Stats (H2: off main thread) ──
        else if method == "getPlayHistory" {
            // S14: clamp the limit — a renderer-supplied unbounded LIMIT would
            // serialize the whole history table into one reply
            var limit = (args.first as? NSNumber)?.intValue ?? 50
            if limit < 1 || limit > 1000 { limit = 50 }
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Database.getPlayHistory(limit)
                DispatchQueue.main.async { reply(mid, rows) }
            }
        } else if method == "getStats" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let stats = Database.getListeningStats()
                DispatchQueue.main.async { reply(mid, stats) }
            }
        }
        // ── Cover art (H3: file read + base64 off the main thread; L2: the path
        // must live inside the library — getCover is a renderer-facing arbitrary
        // file read otherwise) ──
        else if method == "getCover" {
            guard let coverPath = args.first as? String, Paths.isPathInLibrary(coverPath) else {
                reply(idNum, NSNull())
                return
            }
            let mid = idNum
            // Q7: base64-encode on the background queue — only the small reply
            // string hops to the main thread
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: URL(fileURLWithPath: coverPath))
                var encoded: String?
                if let data {
                    let ext = (coverPath as NSString).pathExtension.lowercased()
                    let mime = ext == "png" ? "image/png"
                        : ext == "webp" ? "image/webp"
                        : "image/jpeg"
                    encoded = "data:\(mime);base64,\(data.base64EncodedString())"
                }
                DispatchQueue.main.async { reply(mid, encoded ?? NSNull()) }
            }
        }
        // ── Network: JSON GET via native stack (no CORS, stable) ──
        else if method == "httpGetJson" {
            let urlStr = args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { (result: inout [String: Any], data: Data) in
                    let parsed = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
                    result["body"] = parsed
                },
                { result in reply(idNum, result) })
        }
        // ── Network: binary GET via native stack (cover art downloads) ──
        else if method == "httpGetBase64" {
            let urlStr = args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { (result: inout [String: Any], data: Data) in
                    result["base64"] = data.base64EncodedString()
                },
                { result in reply(idNum, result) })
        }
        // ── Playlists (H2: reads off main thread) ──
        else if method == "getPlaylists" {
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Database.getAllPlaylists()
                DispatchQueue.main.async { reply(mid, rows) }
            }
        } else if method == "createPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, ["lastInsertRowid": NSNumber(value: Database.createPlaylist(
                d["name"] as? String ?? "", d["description"] as? String))])
        } else if method == "renamePlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.renamePlaylist((d["id"] as? NSNumber)?.int64Value ?? 0, d["name"] as? String))
        } else if method == "deletePlaylist" {
            reply(idNum, Database.deletePlaylist((args.first as? NSNumber)?.int64Value ?? 0))
        } else if method == "getPlaylistTracks" {
            let pid = (args.first as? NSNumber)?.int64Value ?? 0
            let mid = idNum
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Database.getPlaylistTracks(pid)
                DispatchQueue.main.async { reply(mid, rows) }
            }
        } else if method == "addToPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.addTrackToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        } else if method == "addTracksToPlaylist" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.addTracksToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                d["trackIds"] as? [Any] ?? []))
        } else if method == "setPlaylistTracks" {
            let d = args.first as? [String: Any] ?? [:]
            reply(idNum, Database.setPlaylistTracks(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                d["trackIds"] as? [Any] ?? []))
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
                // Sidecar detection: "Artist - Title_L.lrc" next to "Artist - Title_EM.flac"
                if let track = Database.getTrackById(tid) as? [String: Any],
                   let filePath = track["file_path"] as? String {
                    lrcPath = Metadata.findSidecarLrc(filePath)
                }
            }
            if lrcPath == nil || !FileManager.default.fileExists(atPath: lrcPath!) {
                reply(idNum, NSNull())
            } else {
                // NEW-1: lrc_path is stored verbatim from setLrc — never read a file
                // outside the library (arbitrary local-file read via getLrc)
                guard Paths.isPathInLibrary(lrcPath!) else {
                    reply(idNum, NSNull())
                    return
                }
                let raw = try? Data(contentsOf: URL(fileURLWithPath: lrcPath!))
                let content = raw.flatMap { String(data: $0, encoding: .utf8) }
                let decoded: String?
                if let content {
                    decoded = content
                } else {
                    decoded = raw.flatMap { String(data: $0, encoding: Metadata.gb18030) }
                }
                if let decoded {
                    reply(idNum, ["content": decoded, "path": lrcPath!])
                } else {
                    reply(idNum, NSNull())
                }
            }
        } else if method == "setLrc" {
            let d = args.first as? [String: Any] ?? [:]
            let lrcPath = d["lrcPath"] as? String ?? ""
            // NEW-1: reject out-of-library lrc paths (getLrc would read them back)
            guard Paths.isPathInLibrary(lrcPath) else { reply(idNum, false); return }
            reply(idNum, Database.setTrackLrc((d["trackId"] as? NSNumber)?.int64Value ?? 0, lrcPath))
        } else if method == "saveLrcContent" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let content = args.count > 1 ? args[1] as? String : nil
            guard let content, !content.isEmpty,
                  let track = Database.getTrackById(tid) as? [String: Any],
                  let audioPath = track["file_path"] as? String else {
                reply(idNum, ["success": false])
                return
            }
            let audioStem = Metadata.cleanAudioStem(((audioPath as NSString).lastPathComponent as NSString).deletingPathExtension)
            // Name the sidecar with the track id: two files in one dir can share a
            // cleanStem (e.g. "Song.flac" + "Song_L.flac" both stem to "Song").
            // "<stem>.<tid>.lrc" never exact-matches a sibling, and findSidecarLrc's
            // prefix branch skips ".<digits>" stems, so no sibling can pick this
            // file up either. The DB lrc_path is what getLrc reads first anyway.
            let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("\(audioStem).\(tid)") + ".lrc"
            // S4: belt-and-braces — the target derives from a DB row, but never
            // write outside the library
            guard Paths.isPathInLibrary(target) else { reply(idNum, ["success": false]); return }
            do {
                try content.write(to: URL(fileURLWithPath: target), atomically: true, encoding: .utf8)
            } catch {
                reply(idNum, ["success": false])
                return
            }
            let ok = Database.setTrackLrc(tid, target)
            reply(idNum, ok ? ["success": true, "lrcPath": target] : ["success": false])
        } else if method == "saveCover" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            let b64 = args.count > 1 ? args[1] as? String : nil
            guard let track = Database.getTrackById(tid) as? [String: Any],
                  let b64, !b64.isEmpty,
                  let audioPath = track["file_path"] as? String else {
                reply(idNum, ["success": false])
                return
            }
            guard let img = Data(base64Encoded: b64) else { reply(idNum, ["success": false]); return }
            // S9: unbounded payloads are capped (~5 MB decoded ≈ 7M base64 chars)
            if b64.count > 7 * 1024 * 1024 || img.count > 5 * 1024 * 1024 {
                reply(idNum, ["success": false])
                return
            }
            guard let src = CGImageSourceCreateWithData(img as CFData, nil) else {
                reply(idNum, ["success": false])
                return
            }
            // S9: only JPEG/PNG/WebP/HEIC are accepted; anything else is rejected
            // instead of being written verbatim (format spoofing)
            guard let srcType = CGImageSourceGetType(src),
                  let imgType = UTType(srcType as String) else { reply(idNum, ["success": false]); return }
            let knownFormat = imgType.conforms(to: .jpeg) || imgType.conforms(to: .png)
                || imgType.conforms(to: .webP) || imgType.conforms(to: .heic)
            guard knownFormat else { reply(idNum, ["success": false]); return }
            // S9: non-JPEG input is re-encoded to JPEG so the .jpg name is honest
            var outImg = img
            if !imgType.conforms(to: .jpeg) {
                guard let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    reply(idNum, ["success": false])
                    return
                }
                let jpegData = NSMutableData()
                guard let dst = CGImageDestinationCreateWithData(
                    jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
                    reply(idNum, ["success": false])
                    return
                }
                let props = [kCGImageDestinationLossyCompressionQuality: 0.85]
                CGImageDestinationAddImage(dst, image, props as CFDictionary)
                guard CGImageDestinationFinalize(dst) else { reply(idNum, ["success": false]); return }
                outImg = jpegData as Data
            }
            let coverDir = ((audioPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(".covers")
            let fm = FileManager.default
            if !fm.fileExists(atPath: coverDir) {
                do {
                    try fm.createDirectory(atPath: coverDir, withIntermediateDirectories: true)
                } catch {
                    NSLog("[bridge] failed to create cover dir: %@", "\(error)")
                    reply(idNum, ["success": false])
                    return
                }
            }
            let coverPath = (coverDir as NSString).appendingPathComponent("cover-\(tid).jpg")
            // S4: belt-and-braces — never write outside the library
            guard Paths.isPathInLibrary(coverPath) else { reply(idNum, ["success": false]); return }
            do {
                try outImg.write(to: URL(fileURLWithPath: coverPath), options: .atomic)
            } catch {
                NSLog("[bridge] cover write failed: %@", "\(error)")
                reply(idNum, ["success": false])
                return
            }
            let ok = Database.setTrackCover(tid, coverPath)
            reply(idNum, ok ? ["success": true, "coverPath": coverPath] : ["success": false])
        } else if method == "removeLrc" {
            reply(idNum, Database.clearTrackLrc((args.first as? NSNumber)?.int64Value ?? 0))
        } else if method == "uploadLrc" {
            let tid = (args.first as? NSNumber)?.int64Value ?? 0
            guard let track = Database.getTrackById(tid) as? [String: Any],
                  let audioPath = track["file_path"] as? String else {
                reply(idNum, ["error": "Track not found"])
                return
            }
            let panel = NSOpenPanel()
            panel.title = "Select LRC Lyrics File"
            panel.allowedContentTypes = [.plainText]
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK {
                guard let chosen = panel.url?.path else { reply(idNum, ["canceled": true]); return }
                // Mirror electron: copy the .lrc next to the audio file
                let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent((chosen as NSString).lastPathComponent)
                // S13: never silently overwrite an existing sidecar, and surface
                // write failures instead of pretending the copy succeeded
                if FileManager.default.fileExists(atPath: target) {
                    reply(idNum, ["success": false, "error": "A lyrics file with that name already exists"])
                    return
                }
                guard Paths.isPathInLibrary(target) else {
                    reply(idNum, ["success": false, "error": "target outside library"])
                    return
                }
                guard let raw = try? Data(contentsOf: URL(fileURLWithPath: chosen)) else {
                    reply(idNum, ["success": false, "error": "read failed"])
                    return
                }
                do {
                    try raw.write(to: URL(fileURLWithPath: target), options: .atomic)
                } catch {
                    reply(idNum, ["success": false, "error": error.localizedDescription])
                    return
                }
                // Minor-2: only persist lrc_path when the copy actually succeeded —
                // otherwise the DB entry points outside the library (dead entry)
                _ = Database.setTrackLrc(tid, target)
                let content = String(data: raw, encoding: .utf8)
                    ?? String(data: raw, encoding: Metadata.gb18030)
                reply(idNum, ["success": true, "content": content, "path": target])
            } else {
                reply(idNum, ["canceled": true])
            }
        }
        // ── Import (M3) ──
        else if method == "importDialog" {
            let panel = NSOpenPanel()
            panel.title = "Select directory containing music files"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let sourceDir = panel.url?.path {
                // S7: the panel-selected directory becomes a trusted scan root
                AppContext.shared.addTrustedScanRoot(sourceDir)
                let libraryDir = Database.getSetting("library_dir", nil) as? String
                let libraryDirValue: Any = libraryDir ?? NSNull()
                reply(idNum, ["canceled": false, "sourceDir": sourceDir, "libraryDir": libraryDirValue])
            } else {
                reply(idNum, ["canceled": true])
            }
        } else if method == "scanDirectory" {
            // S7: only roots the user picked natively may be enumerated — a
            // renderer-supplied root is an arbitrary filesystem scan otherwise
            let dir = args.first as? String ?? ""
            guard AppContext.shared.isTrustedScanRoot(dir) else {
                reply(idNum, [])
                return
            }
            let mid = idNum
            // M3: directory walk off the main thread
            DispatchQueue.global(qos: .userInitiated).async {
                let files = ImportPipeline.scanAudioFiles(dir)
                DispatchQueue.main.async { reply(mid, files) }
            }
        } else if method == "importFiles" {
            // S5: validate the payload shape BEFORE touching a background queue —
            // malformed args must never reach the importer
            guard let data = args.first as? [String: Any],
                  let files = data["files"] as? [Any],
                  files.allSatisfy({ $0 is String }) else {
                reply(idNum, ["imported": 0, "errors": [], "error": "bad import payload"])
                return
            }
            // Library dir is native-set only (onboarding / Settings); the renderer
            // never supplies it — crafted metadata can no longer redirect writes.
            guard let storedLib = Database.getSetting("library_dir", nil) as? String,
                  !storedLib.isEmpty else {
                reply(idNum, ["imported": 0, "errors": [], "error": "library not set"])
                return
            }
            let importMode = (Database.getSetting("import_mode", "copy") as? String) ?? "copy"
            let filePaths = files.compactMap { $0 as? String }
            let mid = idNum
            ImportPipeline.runImport(files: filePaths, storedLib: storedLib, importMode: importMode) { result in
                reply(mid, result)
            }
        }
        // ── Tray (M5) ──
        else if method == "selectLibraryDir" {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.title = "Select Library Directory"
            if panel.runModal() == .OK, let dir = panel.url?.path {
                _ = Database.setSetting("library_dir", dir)
                reply(idNum, ["canceled": false, "path": dir, "libraryDir": dir])
            } else {
                reply(idNum, ["canceled": true])
            }
        } else if method == "sendPlaybackState" {
            let d = args.first as? [String: Any] ?? [:]
            Tray.shared.setPlaying((d["isPlaying"] as? NSNumber)?.boolValue ?? false)
            reply(idNum, NSNull())
        }
        // ── Login item (M5) ──
        else if method == "getLoginItemSettings" {
            let hidden = Tray.settingBool("start_hidden", false)
            reply(idNum, ["openAtLogin": Tray.loginItemEnabled(), "openAsHidden": hidden])
        } else if method == "setLoginItemSettings" {
            let d = args.first as? [String: Any] ?? [:]
            if let hidden = d["openAsHidden"] as? Bool {
                _ = Database.setSetting("start_hidden", hidden ? "1" : "0")
            }
            reply(idNum, ["ok": Tray.setLoginItem((d["openAtLogin"] as? Bool) ?? false)])
        }
        // ── Plugins ──
        else if method == "listPlugins" {
            reply(idNum, PluginFS.listPlugins())
        } else if method == "readPluginFile" {
            let pid = args.first as? String ?? ""
            let rel = args.count > 1 ? args[1] as? String : nil
            let content = PluginFS.readPluginFile(pid, rel ?? "")
            reply(idNum, content ?? NSNull())
        } else if method == "openPluginsDir" {
            PluginFS.openPluginsDir()
            reply(idNum, true)
        } else if method == "uninstallPlugin" {
            reply(idNum, PluginFS.removePlugin(args.first as? String ?? ""))
        } else if method == "finishOnboarding" {
            Windows.finishOnboarding()
            reply(idNum, true)
        } else {
            reject(idNum, "not implemented: \(method)")
        }
    }

    // MARK: - Equalizer state: settings table + cross-window broadcast

    private func eqKey(_ suffix: String) -> String { "eq.\(suffix)" }

    private func eqStateDict() -> [String: Any] {
        var gains: [NSNumber] = []
        if let raw = Database.getSetting(eqKey("gains"), nil) as? String {
            for p in raw.components(separatedBy: ",") {
                gains.append(NSNumber(value: Double(p) ?? 0))
            }
        }
        while gains.count < 10 { gains.append(NSNumber(value: 0)) }
        let enabled = Database.getSetting(eqKey("enabled"), nil) as? String
        let preset = Database.getSetting(eqKey("preset"), nil) as? String
        return [
            "enabled": enabled == "true" || enabled == "1",
            "preset": preset ?? "平坦",
            "gains": gains,
        ]
    }

    private func saveEq(_ d: [String: Any]) {
        let gains = (d["gains"] as? [Any] ?? []).map { (v: Any) -> String in
            String(format: "%.1f", (v as? NSNumber)?.doubleValue ?? 0)
        }
        // M6: one transaction instead of three autocommits (fsync per write);
        // if the transaction can't start, fall back to plain autocommit writes
        let tx = Database.beginTransaction()
        _ = Database.setSetting(eqKey("enabled"), ((d["enabled"] as? NSNumber)?.boolValue ?? false) ? "1" : "0")
        _ = Database.setSetting(eqKey("preset"), d["preset"] as? String ?? "自定义")
        _ = Database.setSetting(eqKey("gains"), gains.joined(separator: ","))
        if tx { _ = Database.commitTransaction() }
    }

    private func broadcastEq() {
        DispatchQueue.main.async {
            guard let data = try? JSONSerialization.data(withJSONObject: self.eqStateDict()),
                  let json = String(data: data, encoding: .utf8) else { return }
            let js = "window.freeplayer._pushEq(\(json))"
            AppContext.shared.webView?.evaluateJavaScript(js)
            AppContext.shared.eqWebView?.evaluateJavaScript(js)
        }
    }
}