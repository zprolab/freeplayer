// FreePlayer shell — WKScriptMessageHandler transport (通用桥层 的 WebKit 适配).
// Security gate + console capture + reply serialization; every method call
// goes to the shared BridgeCore (installed by BridgeBootstrap). The generic
// core itself is WebKit-free — a future Android/Windows transport feeds the
// same dispatch semantics.

import Foundation
import WebKit
import os

private let bridgeLog = Logger(subsystem: "com.zprolab.FreePlayer", category: "bridge")

/// Pushes outbound bridge events to every FreePlayer webview as
/// `window.freeplayer.<channel>(<json>)` — the EQ sync path today, media-key
/// / tray pushes if they ever route through the core.
enum BridgeEmitter {
    static func push(_ channel: String, _ payload: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.freeplayer.\(channel)(\(json))"
        AppContext.shared.webView?.evaluateJavaScript(js)
        AppContext.shared.eqWebView?.evaluateJavaScript(js)
    }
}

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
            // P1: JSON is safe from JSONSerialization; defense-in-depth: verify encoding
            guard json.data(using: .utf8) != nil else {
                NSLog("[shell] reply: json encoding failed for %@", mid)
                return
            }
            DebugLog.file("BRIDGE_REPLY id=\(mid.int64Value) method=\(method) payload=\(json)")
            webView.evaluateJavaScript("window.freeplayer._resolve(\(mid.int64Value), \(json))")
        }

        func reject(_ mid: NSNumber, _ why: String?) {
            let data = try? JSONSerialization.data(withJSONObject: why ?? "error")
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"error\""
            // P1: JSON is safe from JSONSerialization; defense-in-depth: verify encoding
            guard json.data(using: .utf8) != nil else {
                NSLog("[shell] reject: json encoding failed for %@", mid)
                return
            }
            DebugLog.file("BRIDGE_REJECT id=\(mid.int64Value) method=\(method) reason=\(json)")
            webView.evaluateJavaScript("window.freeplayer._reject(\(mid.int64Value), \(json))")
        }

        // Trivial system events stay here for zero routing overhead
        if method == "__ready" {
            bridgeLog.info("bridge ready: \(webView.url?.absoluteString ?? "?")")
            if UserDefaults.standard.bool(forKey: "FP_SPECTRO_TEST") {
                webView.evaluateJavaScript("window.__FP_SPECTRO_TEST = true;")
            }
            return
        }
        if method == "__console" {
            let a = args
            let level = (a.first as? String) ?? "log"
            let message = Self.redactConsole((a.count > 1 && a[1] is String) ? (a[1] as! String) : "")
            NSLog("[page %@] %@", level, message)
            DebugLog.file("PAGE level=\(level) message=\(message)")
            return
        }

        // M7: verbose IPC logging
        if AppContext.shared.verboseLogging { NSLog("[shell] method=%@", method) }
        DebugLog.file("BRIDGE method=\(method) args=\(String(describing: args))")

        // Everything else goes to the shared generic core (fp + platform layers)
        BridgeBootstrap.install().dispatch(method: method, args: args, idNum: idNum,
                                           reply: reply, reject: reject)
    }
}
