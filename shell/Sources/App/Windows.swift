// FreePlayer shell — secondary native windows (Equalizer + Onboarding),
// each with its own WKWebView sharing the bridge + scheme handlers.

import Cocoa
import WebKit

enum Windows {

    private static func makeWebView(frame: NSRect, scheme: SchemeHandler, bridge: BridgeHandler) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.setURLSchemeHandler(scheme, forURLScheme: "media")
        config.setURLSchemeHandler(scheme, forURLScheme: "app")
        config.userContentController.add(bridge, name: "freeplayer")
        let bridgeScript = WKUserScript(source: BridgeScript.source,
                                        injectionTime: .atDocumentStart,
                                        forMainFrameOnly: true)
        config.userContentController.addUserScript(bridgeScript)
        let webView = WKWebView(frame: frame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        if let gate = AppContext.shared.navGate { webView.navigationDelegate = gate }
        return webView
    }

    private static func windowLikeMain(_ frame: NSRect, _ title: String, white: Bool = false) -> NSWindow {
        let win = NSWindow(contentRect: frame,
                           styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = title
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.backgroundColor = white
            ? NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
            : NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
        win.center()
        return win
    }

    // ── Equalizer window ──

    static func openEqWindow() {
        DispatchQueue.main.async {
            let ctx = AppContext.shared
            if let eqWindow = ctx.eqWindow {
                eqWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            let frame = NSRect(x: 0, y: 0, width: 580, height: 340)
            let win = windowLikeMain(frame, "Equalizer")
            let webView = makeWebView(frame: frame,
                                      scheme: SchemeHandler(),
                                      bridge: BridgeHandler())
            win.contentView = webView
            ctx.eqWebView = webView
            ctx.eqWindow = win

            // Q8: build the URL with URLComponents — stringByAppendingString
            // breaks dev URLs that already carry a query string
            var comp = URLComponents(url: ctx.mainLoadURL!, resolvingAgainstBaseURL: false)
            comp?.queryItems = [URLQueryItem(name: "view", value: "eq")]
            if let eqURL = comp?.url {
                webView.load(URLRequest(url: eqURL))
            }
            win.makeKeyAndOrderFront(nil)
        }
    }

    static func hideEqWindow() {
        DispatchQueue.main.async {
            AppContext.shared.eqWindow?.orderOut(nil)
        }
    }

    // ── Onboarding window: first-run wizard (640x480) ──

    static func openOnboardingWindow() {
        DispatchQueue.main.async {
            let ctx = AppContext.shared
            if let obWindow = ctx.onboardingWindow {
                obWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
            let win = windowLikeMain(frame, "Welcome to FreePlayer", white: true)
            win.styleMask.insert(.resizable)
            let webView = makeWebView(frame: frame,
                                      scheme: SchemeHandler(),
                                      bridge: BridgeHandler())
            win.contentView = webView
            ctx.onboardingWebView = webView
            ctx.onboardingWindow = win

            var comp = URLComponents(url: ctx.mainLoadURL!, resolvingAgainstBaseURL: false)
            comp?.queryItems = [URLQueryItem(name: "view", value: "onboarding")]
            if let obURL = comp?.url {
                webView.load(URLRequest(url: obURL))
            }
            win.makeKeyAndOrderFront(nil)
        }
    }

    static func closeOnboardingWindow() {
        DispatchQueue.main.async {
            AppContext.shared.onboardingWindow?.orderOut(nil)
        }
    }

    static func finishOnboarding() {
        DispatchQueue.main.async {
            let ctx = AppContext.shared
            ctx.onboardingWindow?.orderOut(nil)
            ctx.webView?.reload()
            ctx.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}