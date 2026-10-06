// FreePlayer shell — navigation lockdown (S1)
// The bridge user script is injected on every main-frame load and the bridge
// stays registered across navigations, so a renderer redirect to any https://
// page would hand the attacker the whole window.freeplayer surface. Main-frame
// navigations may only go to app:// (bundled UI, eq, onboarding) or, in dev
// binaries, the same origin the shell was configured to load.

import WebKit

final class NavGate: NSObject, WKNavigationDelegate {

    static func sameOrigin(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b,
              a.scheme == b.scheme,
              a.host == b.host else { return false }
        let pa = a.port ?? (a.scheme == "https" ? 443 : 80)
        let pb = b.port ?? (b.scheme == "https" ? 443 : 80)
        return pa == pb
    }

    /// The single policy both transports share: a main-frame navigation is
    /// allowed only to the bundled UI (`app` on macOS, `fpapp` on iOS) or, for
    /// dev binaries, the origin the shell was configured to load. Anything else
    /// (https://…, file://…, data:…) is a bridge-hijack vector and is blocked.
    static func allowsMainFrame(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == "app" || url.scheme == "fpapp" { return true }
        let bundled = Bundle.main.bundlePath.hasSuffix(".app")
        if !bundled, let main = AppContext.shared.mainLoadURL, sameOrigin(url, main) {
            return true
        }
        return false
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // New-window requests (target=_blank / window.open): never open them
        guard let frame = navigationAction.targetFrame else {
            decisionHandler(.cancel); return
        }
        // Subframes get no bridge (S2) — their navigations are harmless
        guard frame.isMainFrame else {
            decisionHandler(.allow); return
        }
        let url = navigationAction.request.url
        if NavGate.allowsMainFrame(url) {
            decisionHandler(.allow)
            return
        }
        NSLog("[shell] blocked main-frame navigation to %@", url?.absoluteString ?? "?")
        decisionHandler(.cancel)
    }
}