// FreePlayer shell — fp layer: cover art + lyrics files.
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation
import UniformTypeIdentifiers   // saveCover: UTType
import ImageIO                  // saveCover: CGImageSource / CGImageDestination

extension FPBridge {

    static func registerMedia(into core: BridgeCore) {
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
