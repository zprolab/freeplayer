// FreePlayer — iPad web container. Sets up the WKWebView (scheme handlers,
// bridge injection) exactly like the macOS shell, loads the bundled React
// assets from <bundle>/web via app://, and wires the iPad platform bridge.

import UIKit
import WebKit
import AVFoundation
import os

private let log = Logger(subsystem: "com.zprolab.FreePlayer", category: "web")

final class WebViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!

    /// P4: Diagnostics only in DEBUG builds to avoid writing to disk in release.
    private func diag(_ msg: String) {
        DebugLog.file(msg, to: "diag.log")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        Host.viewController = self
        AppContext.shared.platformBridge = IPadPlatformBridge()
        // Re-grant security-scoped access to folders picked in previous
        // sessions and re-register them as trusted scan roots.
        IPadPlatformBridge.restorePickedFolders()
        diag("viewDidLoad: platform bridge wired")

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
        AppContext.shared.schemeHandler = scheme
        config.setURLSchemeHandler(scheme, forURLScheme: "media")
        config.setURLSchemeHandler(scheme, forURLScheme: "fpapp")
        let bridge = BridgeHandler()
        config.userContentController.add(bridge, name: "freeplayer")
        config.userContentController.addUserScript(
            WKUserScript(source: BridgeScript.source,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)
        // The renderer owns safe-area spacing (including iPhone's home
        // indicator). Prevent UIKit from applying a second inset.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delaysContentTouches = false
        // Register with AppContext: BridgeHandler.isAppWebView() rejects every
        // message from a webview that is not one of ours, and the macOS shell
        // assigns this in its AppDelegate — without it all bridge calls from
        // the page (isSetup/getSetting/getTracks/…) hang forever.
        AppContext.shared.webView = webView

        // Open the SQLite database first (macOS does this in AppDelegate.applicationDidFinishLaunching).
        if !Database.isOpen {
            let opened = Database.open(Database.defaultDbPath())
            diag("Database.open(\(Database.defaultDbPath())) -> \(opened)")
        }
        
        // Library location is fixed on iOS (in-sandbox) — make it exists and
        // is recorded, so isSetup/import work even before any folder is picked.
        // P: Must set library_dir BEFORE opening tracks DB so it goes in the right place.
        let lib = IPadPlatformBridge.ensureLibraryDir()
        diag("library_dir=\(lib)")
        
        // P: Open tracks database in library root (after library_dir is set)
        if Database.tracksDbPath() == nil {
            Database.openTracksDb(Database.defaultTracksDbPath())
        }
        // P: carry pre-split library data (tracks/playlists/history) into tracks.db
        Database.migrateToSplitDb()

        // Bundled web assets: Xcode packs dist/ as a folder reference, so it
        // lands at <bundle>/dist (the macOS bundle calls it "web"). Accept both.
        let candidates = ["web", "dist"]
            .compactMap { Bundle.main.resourceURL?.appendingPathComponent($0) }
        if let webRoot = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            AppContext.shared.webRoot = webRoot.path
            AppContext.shared.mainLoadURL = URL(string: "fpapp://localhost/index.html")!
            diag("loading webRoot=\(webRoot.path) url=\(AppContext.shared.mainLoadURL!.absoluteString)")
            webView.load(URLRequest(url: AppContext.shared.mainLoadURL!))
        } else {
            diag("web assets NOT FOUND; candidates=\(candidates.map { $0.path }.joined(separator: ","))")
        }
    }

    // MARK: - WKNavigationDelegate diagnostics

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        diag("didFinish: \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        diag("didFail: \(webView.url?.absoluteString ?? "?") error=\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        diag("didFailProvisional: \(error.localizedDescription) url=\(webView.url?.absoluteString ?? "?")")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // stop media playback when leaving the container
        webView?.evaluateJavaScript("document.querySelectorAll('audio,video').forEach(a => a.pause())")
    }
}
