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
        if url?.scheme == "app" {
            decisionHandler(.allow)
            return
        }
        let bundled = Bundle.main.bundlePath.hasSuffix(".app")
        if !bundled, let main = AppContext.shared.mainLoadURL, url.map({ NavGate.sameOrigin($0, main) }) == true {
            decisionHandler(.allow)
            return
        }
        NSLog("[shell] blocked main-frame navigation to %@", url?.absoluteString ?? "?")
        decisionHandler(.cancel)
    }
}