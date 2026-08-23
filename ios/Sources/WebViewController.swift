// FreePlayer — iPad web container. Sets up the WKWebView (scheme handlers,
// bridge injection) exactly like the macOS shell, loads the bundled React
// assets from <bundle>/web via app://, and wires the iPad platform bridge.

import UIKit
import WebKit
import AVFoundation

final class WebViewController: UIViewController {

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        Host.viewController = self
        AppContext.shared.platformBridge = IPadPlatformBridge()

        // Background audio: allow the webview to play without user action and
        // keep audio alive while the app is in the background (Info.plist
        // declares UIBackgroundModes=audio).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // app:// + media:// served from the single source of truth
        let scheme = SchemeHandler()
        config.setURLSchemeHandler(scheme, forURLScheme: "media")
        config.setURLSchemeHandler(scheme, forURLScheme: "app")
        let bridge = BridgeHandler()
        config.userContentController.add(bridge, name: "freeplayer")
        config.userContentController.addUserScript(
            WKUserScript(source: BridgeScript.source,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = NavGate()
        view.addSubview(webView)

        // Bundled web assets at <bundle>/web (Xcode folder reference to dist/)
        if let webRoot = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: webRoot.path) {
            AppContext.shared.webRoot = webRoot.path
            AppContext.shared.mainLoadURL = URL(string: "app://index.html")!
            webView.load(URLRequest(url: AppContext.shared.mainLoadURL!))
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // stop media playback when leaving the container
        webView?.evaluateJavaScript("document.querySelectorAll('audio,video').forEach(a => a.pause())")
    }
}