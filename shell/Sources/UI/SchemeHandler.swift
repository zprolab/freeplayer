// FreePlayer shell — media:// + app:// scheme handlers
//   media://<encoded path>  — local audio files (Range support for <audio>)
//   app://<relative path>   — bundled web assets (prod UI)

import Foundation
import WebKit
import os

private let schemeLog = Logger(subsystem: "com.zprolab.FreePlayer", category: "scheme")

private func schemeDiag(_ msg: String) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scheme-diag.log")
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(("[\(Date())] \(msg)\n").data(using: .utf8)!); try? h.close()
    }
}

// S11: mirror the page's own CSP meta tag (index.html — including the
// `blob:` script allowance the plugin worker sandbox needs) — the app://
// response must not change what the bundled page is allowed to do — plus
// nosniff. Keep in sync with index.html's meta.
private let kAppCSP = "default-src 'self'; script-src 'self' blob:;"
    + " style-src 'self' 'unsafe-inline';"
    + " media-src 'self' media:; img-src 'self' data: media:;"
    + " font-src 'self'; connect-src 'self' app: ws://localhost:*"

func mimeForPath(_ path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "html", "htm": return "text/html; charset=utf-8"
    case "js", "mjs": return "text/javascript"
    case "css": return "text/css"
    case "json", "map": return "application/json"
    case "svg": return "image/svg+xml"
    case "woff2": return "font/woff2"
    case "woff": return "font/woff"
    case "ttf": return "font/ttf"
    case "ico": return "image/x-icon"
    case "flac": return "audio/flac"
    case "mp3": return "audio/mpeg"
    case "m4a", "mp4": return "audio/mp4"
    case "ogg", "oga": return "audio/ogg"
    case "wav": return "audio/wav"
    case "aac": return "audio/aac"
    case "opus": return "audio/ogg"
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "lrc", "txt": return "text/plain; charset=utf-8"
    case "ape": return "audio/x-ape"
    case "wv": return "audio/x-wavpack"
    case "tak": return "audio/x-tak"
    case "ac3": return "audio/ac3"
    case "dts": return "audio/vnd.dts"
    case "amr": return "audio/amr"
    default: return "application/octet-stream"
    }
}

final class SchemeHandler: NSObject, WKURLSchemeHandler {

    // Per-task cancellation flags (main-thread dictionary; the streaming loop
    // reads the flag from a background queue). WKURLSchemeTask is an AnyObject
    // with no stable identity — Objective-C pointer hashing, Swift identity.
    private var stoppedTasks: [ObjectIdentifier: AtomicBool] = [:]

    private func stoppedFlagForTask(_ task: any WKURLSchemeTask) -> AtomicBool {
        let key = ObjectIdentifier(task)
        if let flag = stoppedTasks[key] { return flag }
        let flag = AtomicBool(false)
        stoppedTasks[key] = flag
        return flag
    }

    private func clearStoppedFlag(_ task: any WKURLSchemeTask) {
        stoppedTasks.removeValue(forKey: ObjectIdentifier(task))
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        schemeLog.info("start \(task.request.url?.absoluteString ?? "?")")
        schemeDiag("start \(task.request.url?.absoluteString ?? "?")")
        guard let url = task.request.url else {
            task.didFailWithError(NSError(domain: "FreePlayerShell", code: 400))
            return
        }

        // ── web scheme — bundled web assets ──
        // macOS registers "app"; iOS must avoid the reserved app:// scheme and
        // registers "fpapp" instead. Same handler, same path-pinning logic.
        if url.scheme == "app" || url.scheme == "fpapp" {
            schemeDiag("app:// branch hit, path=\(url.path) scheme=\(url.scheme ?? "?")")
            var rel = url.path // "/index.html", "/assets/x.js"
            if rel.isEmpty || rel == "/" { rel = "/index.html" }
            // H6: standardize the path and pin it inside gWebRoot — ".." components
            // must never escape the bundled assets directory.
            guard let root = AppContext.shared.webRoot else {
                task.didFailWithError(NSError(domain: "FreePlayerShell", code: 400))
                return
            }
            let rootNorm = (root as NSString).standardizingPath
            let file = ((rootNorm as NSString).appendingPathComponent(
                rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) as NSString).standardizingPath
            if !file.hasPrefix(rootNorm + "/") && file != rootNorm {
                task.didFailWithError(NSError(domain: "FreePlayerShell", code: 400,
                                              userInfo: [NSLocalizedDescriptionKey: "invalid app:// path"]))
                return
            }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
                task.didFailWithError(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT),
                                              userInfo: [NSLocalizedDescriptionKey: file]))
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": mimeForPath(file),
                "Content-Length": "\(data.count)",
                "Cache-Control": "no-cache",
                // S11: no CSP/nosniff on app:// responses meant a compromised page
                // could load/execute attacker content under the app origin
                "Content-Security-Policy": kAppCSP,
                "X-Content-Type-Options": "nosniff",
            ])!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
            schemeDiag("app:// served \(file) (\(data.count) bytes)")
            return
        }

        // ── media:// — local audio files with Range support ──
        let raw = url.absoluteString // "media://%2FVolumes%2F..."
        guard raw.hasPrefix("media://") else {
            task.didFailWithError(NSError(domain: "FreePlayerShell", code: 400))
            return
        }
        let encodedPath = String(raw.dropFirst("media://".count))
        guard let path = encodedPath.removingPercentEncoding, !path.isEmpty else {
            task.didFailWithError(NSError(domain: "FreePlayerShell", code: 400))
            return
        }
        schemeDiag("media:// path=\(path)")

        // L2: only library-owned files may stream — Paths.isPathInLibrary
        // standardizes AND resolves symlinks, so a symlink-imported track that
        // points outside the library is rejected (S3d). Q9: media:// serves audio
        // only, so an extension allowlist is cheap defense in depth on top.
        guard Paths.isPathInLibrary(path), Paths.isAudioFile(path) else {
            task.didFailWithError(NSError(domain: "FreePlayerShell", code: 403,
                                          userInfo: [NSLocalizedDescriptionKey: "outside library"]))
            return
        }

        guard let fh = FileHandle(forReadingAtPath: path) else {
            task.didFailWithError(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT),
                                          userInfo: [NSLocalizedDescriptionKey: path]))
            return
        }
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0

        // Parse Range header — supports "bytes=start-end", "bytes=start-", "bytes=-suffix"
        var start: UInt64 = 0
        var end: UInt64 = fileSize > 0 ? fileSize - 1 : 0
        var hasRange = false
        var rangeInvalid = false
        if let range = task.request.value(forHTTPHeaderField: "Range"), !range.isEmpty {
            // M13: reject multi-range requests ("bytes=0-1,4-5") explicitly.
            // #7: range-unit is case-insensitive (RFC 7233); tolerate trailing space.
            let lower = range.lowercased()
            if !lower.hasPrefix("bytes=") {
                rangeInvalid = true
            } else {
                var rest = String(range.dropFirst("bytes=".count))
                if rest.hasPrefix("-") {
                    // Suffix range: last N bytes
                    rest = String(rest.dropFirst())
                    if let suffix = Int64(rest), suffix > 0, fileSize > 0 {
                        hasRange = true
                        start = UInt64(suffix) >= fileSize ? 0 : fileSize - UInt64(suffix)
                        end = fileSize - 1
                    } else {
                        rangeInvalid = true
                    }
                } else {
                    let parts = rest.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                    if let s = Int64(parts[0]), s >= 0 {
                        start = UInt64(s)
                        hasRange = true
                        if parts.count > 1, let e = Int64(parts[1]), e >= 0 {
                            end = UInt64(e)
                        }
                        // NEW-4: bytes=5-3 (end before start) is unsatisfiable → 416
                        if end < start {
                            rangeInvalid = true
                        } else if end >= fileSize {
                            end = fileSize > 0 ? fileSize - 1 : 0
                        }
                        // Anything left after the range (e.g. multi-range "0-1,4-5") is unsupported
                        if parts.count > 1 {
                            let tail = parts[1]
                            if Int64(tail) == nil {
                                if !tail.isEmpty { rangeInvalid = true }
                            }
                        }
                    } else {
                        rangeInvalid = true
                    }
                }
                if rangeInvalid { hasRange = false }
            }
        }

        // M13: unsatisfiable/invalid Range → 416 with Content-Range: bytes */size
        if rangeInvalid {
            let h416 = [
                "Content-Range": "bytes */\(fileSize)",
                "Content-Length": "0",
                "Accept-Ranges": "bytes",
            ]
            let r416 = HTTPURLResponse(url: url, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: h416)!
            let flag = stoppedFlagForTask(task)
            DispatchQueue.main.async {
                // #5: always clear the flag — an early return here would leak it
                if flag.value {
                    self.clearStoppedFlag(task)
                    return
                }
                task.didReceive(r416)
                task.didFinish()
                self.clearStoppedFlag(task)
            }
            return
        }

        let length: UInt64 = (end >= start) ? end - start + 1 : 0
        var headers: [String: String] = [
            "Content-Type": mimeForPath(path),
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
        ]
        var status = 200
        if hasRange {
            status = 206
            headers["Content-Range"] = "bytes \(start)-\(end)/\(fileSize)"
        }
        headers["Content-Length"] = "\(length)"
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!

        // Per-task cancellation flag (stop on THIS task must not kill others)
        let stopped = stoppedFlagForTask(task)
        DispatchQueue.main.async {
            if !stopped.value { task.didReceive(response) }
        }

        try? fh.seek(toOffset: start)
        // H1: read in 64KB chunks but flush to the main queue in ~1MB batches with
        // flow control (max ~8 batches in flight) so a large file can never queue
        // unbounded NSData on the main thread.
        let chunk: UInt64 = 64 * 1024
        let batchChunks: Int = 16 // 1MB per main-queue hop
        let maxInFlight = 8       // ~8MB of queued data at most
        let inFlight = AtomicInt(0)
        var remaining = length
        var buf = Data(capacity: batchChunks * Int(chunk))
        let finishedFlag = AtomicBool(false)

        DispatchQueue.global(qos: .userInitiated).async {
            func flushBatch(_ out: Data) {
                inFlight.increment()
                DispatchQueue.main.async {
                    if !stopped.value && !finishedFlag.value {
                        task.didReceive(out)
                    }
                    inFlight.decrement()
                }
            }
            while remaining > 0, !stopped.value {
                let n = Int(min(remaining, chunk))
                let data = fh.readData(ofLength: n)
                if data.isEmpty { break }
                buf.append(data)
                remaining -= UInt64(data.count)
                if buf.count >= batchChunks * Int(chunk) {
                    // Backpressure: wait until the main queue drains below the cap
                    while inFlight.current >= maxInFlight, !stopped.value {
                        usleep(2000)
                    }
                    if stopped.value { break }
                    flushBatch(buf)
                    buf.removeAll(keepingCapacity: true)
                }
            }
            if buf.count > 0, !stopped.value {
                while inFlight.current >= maxInFlight, !stopped.value { usleep(2000) }
                if !stopped.value { flushBatch(buf) }
            }
            DispatchQueue.main.async {
                fh.closeFile()
                if !stopped.value && !finishedFlag.value {
                    finishedFlag.store(true)
                    task.didFinish()
                }
                self.clearStoppedFlag(task)
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // NEW-5: only mark tasks we actually know — a post-completion stop must not
        // create a stuck flag that a future request (reusing the task pointer)
        // would inherit as an instant-cancel
        if let flag = stoppedTasks[ObjectIdentifier(task)] {
            flag.store(true)
        }
    }
}