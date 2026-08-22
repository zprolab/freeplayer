// FreePlayer shell — native HTTP helpers (M1: shared session for json/base64).

import Foundation

enum HttpClient {

    static let kMaxHttpBytes = 8 * 1024 * 1024 // H5: response cap

    private static var sharedSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = true            // L1: don't fail instantly offline
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    // S6: SSRF guard — https-only (http is tolerated solely for localhost, i.e.
    // the dev server), and the host must not resolve to loopback / link-local /
    // private / multicast / unspecified addresses. Every resolved address must
    // be public: a hostname that resolves to a mix of public + private IPs is
    // rejected (getaddrinfo on the bare host, then one check per address).
    static func urlAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https" || url.scheme == "http" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if url.scheme == "http" && host != "localhost" { return false }
        if host == "localhost" { return true }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, nil, &hints, &res) != 0 { return false }
        defer { if let res { freeaddrinfo(res) } }
        var allowed = true
        var ai = res
        while let cur = ai {
            if cur.pointee.ai_family == AF_INET {
                cur.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sa in
                    let a = UInt32(bigEndian: sa.pointee.sin_addr.s_addr)
                    let v = a as UInt32
                    if v == 0                  // 0.0.0.0
                        || (v >> 24) == 127    // 127.0.0.0/8
                        || (v >> 16) == 0xA9FE // 169.254.0.0/16 link-local
                        || (v >> 24) == 10     // 10.0.0.0/8
                        || (v >> 20) == 0xAC1  // 172.16.0.0/12
                        || (v >> 16) == 0xC0A8 // 192.168.0.0/16
                        || (v >> 28) == 0xE {  // 224.0.0.0/4 multicast
                        allowed = false
                    }
                }
            } else if cur.pointee.ai_family == AF_INET6 {
                cur.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sa6 in
                    // IN6_IS_ADDR_* are C macros — reimplement on the raw bytes
                    // (network byte order)
                    let addr = sa6.pointee.sin6_addr
                    let bytes = withUnsafeBytes(of: addr) { Array($0) }
                    let allZero = bytes.allSatisfy { $0 == 0 }
                    let loopback = bytes[0...14].allSatisfy { $0 == 0 } && bytes[15] == 1
                    let linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
                    let multicast = bytes[0] == 0xff
                    if allZero || loopback || linkLocal || multicast {
                        allowed = false
                    }
                }
            } else {
                allowed = false
            }
            ai = cur.pointee.ai_next
            if !allowed { break }
        }
        return allowed
    }

    // Shared GET pipeline: validates scheme + host (S6 — never file://, and no
    // loopback/private targets), follows redirects only when each hop re-passes
    // urlAllowed (cap 5), enforces a size cap, shapes {ok, status, retryAfter?,
    // error?}, hands the body to `fill` on success, and hops back to the main
    // thread to reply. `onMain` is the reply closure.
    static func httpGet(_ urlStr: String,
                        _ fill: @escaping (inout [String: Any], Data) -> Void,
                        _ onMain: @escaping ([String: Any]) -> Void) {
        guard !urlStr.isEmpty else { onMain(["ok": false, "error": "empty url"]); return }
        guard let url = URL(string: urlStr) else { onMain(["ok": false, "error": "bad url"]); return }
        guard urlAllowed(url) else { onMain(["ok": false, "error": "url not allowed"]); return }

        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        let ua = "FreePlayer/\(ver) (+https://github.com/zprolab/FreePlayer)"

        DispatchQueue.global(qos: .userInitiated).async {
            var result: [String: Any] = [:]
            var current = url
            var done = false
            var redirects = 0
            while !done {
                var req = URLRequest(url: current)
                req.timeoutInterval = 10
                // Descriptive User-Agent — LRCLIB and iTunes both ask clients to
                // identify themselves so abuse is attributable instead of IP-banned.
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                let sem = DispatchSemaphore(value: 0)
                var loopAgain = false
                let task = sharedSession.dataTask(with: req) { data, resp, err in
                    defer { sem.signal() }
                    let http = resp as? HTTPURLResponse
                    if let err {
                        result["ok"] = false
                        result["error"] = err.localizedDescription
                        done = true
                    } else if let code = http?.statusCode, (300..<400).contains(code) {
                        // Redirect: re-validate the target, then loop (manual follow so
                        // every hop passes urlAllowed — the session would follow
                        // redirects implicitly otherwise)
                        let loc = http?.allHeaderFields["Location"] as? String
                        let next = loc.flatMap { URL(string: $0, relativeTo: current)?.absoluteURL }
                        if let next, urlAllowed(next) {
                            current = next
                            loopAgain = true
                        } else {
                            result["ok"] = false
                            result["error"] = (loc?.isEmpty == false) ? "redirect target not allowed" : "redirect without location"
                            done = true
                        }
                    } else if let code = http?.statusCode, code >= 400 {
                        result["ok"] = false
                        result["status"] = code
                        result["error"] = "http error"
                        if let ra = http?.allHeaderFields["Retry-After"] as? String, !ra.isEmpty {
                            result["retryAfter"] = ra
                        }
                        done = true
                    } else if let data, data.count > kMaxHttpBytes {
                        result["ok"] = false
                        result["error"] = "response too large"
                        done = true
                    } else {
                        result["ok"] = true
                        result["status"] = http?.statusCode ?? 200
                        var out = result
                        fill(&out, data ?? Data())
                        result = out
                        done = true
                    }
                }
                task.resume()
                _ = sem.wait(timeout: .distantFuture)
                if loopAgain {
                    redirects += 1
                    if redirects > 5 {
                        result["ok"] = false
                        result["error"] = "too many redirects"
                        break
                    }
                }
            }
            DispatchQueue.main.async { onMain(result) }
        }
    }
}