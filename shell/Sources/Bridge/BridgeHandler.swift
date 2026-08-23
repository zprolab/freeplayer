// FreePlayer shell — WKScriptMessageHandler: security gate + console capture,
// delegates all dispatch to BridgeRouter (cross-platform) which in turn
// delegates platform-specific calls to PlatformBridge (macOS / iPad).

import Foundation
import WebKit

final class BridgeHandler: NSObject, WKScriptMessageHandler {

    private let router = BridgeRouter()

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
        // S2: only main-frame messages from a webview this app owns
        guard message.frameInfo.isMainFrame,
              let webView = message.webView,
              AppContext.shared.isAppWebView(webView) else { return }
        guard let body = message.body as? [String: Any],
              let idNum = body["id"] as? NSNumber,
              let method = body["method"] as? String else { return }
        let args = body["args"] as? [Any] ?? []

        func reply(_ mid: NSNumber, _ obj: Any?) {
            let json: String
            if obj == nil || obj is NSNull {
                json = "null"
            } else {
                let data = try? JSONSerialization.data(withJSONObject: obj as Any, options: [.fragmentsAllowed])
                guard let data, let s = String(data: data, encoding: .utf8) else { NSLog("[shell] reply failed for %@", mid); return }
                json = s
            }
            webView.evaluateJavaScript("window.freeplayer._resolve(\(mid.int64Value), \(json))")
        }

        func reject(_ mid: NSNumber, _ why: String?) {
            let data = try? JSONSerialization.data(withJSONObject: why ?? "error")
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"error\""
            webView.evaluateJavaScript("window.freeplayer._reject(\(mid.int64Value), \(json))")
        }

        // Trivial system events stay here for zero routing overhead
        if method == "__ready" {
            NSLog("[shell] bridge ready, %@", webView.url?.absoluteString ?? "?")
            if UserDefaults.standard.bool(forKey: "FP_SPECTRO_TEST") {
                webView.evaluateJavaScript("window.__FP_SPECTRO_TEST = true;")
            }
            return
        }
        if method == "__console" {
            let a = args
            NSLog("[page %@] %@", (a.first as? String) ?? "log",
                  Self.redactConsole((a.count > 1 && a[1] is String) ? (a[1] as! String) : ""))
            return
        }

        // M7: verbose IPC logging
        if AppContext.shared.verboseLogging { NSLog("[shell] method=%@", method) }

        // Everything else goes to the router (which may delegate to PlatformBridge)
        router.dispatch(method: method, args: args, idNum: idNum, reply: reply, reject: reject)
    }
}
