// FreePlayer shell — cross-module runtime state (replaces the C globals).
// All webview/import state lives here so modules stay decoupled:
// Core knows nothing about UI, Bridge talks to App through this context.
// Platform-agnostic: compiles unchanged for macOS and iPad. Window state is
// guarded by canImport(AppKit) so the iOS SDK build skips it.

import Foundation
import WebKit
#if canImport(AppKit)
import AppKit
#endif

/// Lock-protected integer (import counter; std::atomic in the ObjC++ port).
final class AtomicInt {
    private let lock = NSLock()
    private var value: Int
    init(_ v: Int) { value = v }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    @discardableResult func decrement() -> Int { lock.lock(); defer { lock.unlock() }; value -= 1; return value }
}

/// Lock-guarded cancellation flag (WKURLSchemeTask stop marking; std::atomic<bool>).
final class AtomicBool {
    private let lock = NSLock()
    private var flag: Bool
    init(_ v: Bool = false) { flag = v }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func store(_ v: Bool) { lock.lock(); defer { lock.unlock() }; flag = v }
}

final class AppContext {
    static let shared = AppContext()
    private init() {}

    // ── webviews (main thread) — windows are platform-specific ──
    var webView: WKWebView?
    var eqWebView: WKWebView?
    var onboardingWebView: WKWebView?
    var navGate: NavGate?
    var mainLoadURL: URL?
    var webRoot: String?

    /// Platform-specific bridge (set by the platform AppDelegate on launch).
    var platformBridge: PlatformBridge?

    // ── import pipeline (M12: termination waits on this) ──
    let importTasks = AtomicInt(0)
    let importGroup = DispatchGroup()

    // ── S7: trusted scan roots (main thread only) ──
    private var trustedScanRoots: [String] = []

    func addTrustedScanRoot(_ root: String) {
        guard !root.isEmpty else { return }
        trustedScanRoots.append(root)
        if trustedScanRoots.count > 128 { trustedScanRoots.removeFirst() }
    }

    func isTrustedScanRoot(_ root: String) -> Bool {
        let norm = (root as NSString).standardizingPath
        for t in trustedScanRoots {
            let tn = (t as NSString).standardizingPath
            if norm.hasPrefix(tn + "/") || norm == tn { return true }
        }
        return false
    }

    /// S2: only our own webviews may talk to the bridge
    func isAppWebView(_ w: WKWebView) -> Bool {
        w === webView || w === eqWebView || w === onboardingWebView
    }

    var verboseLogging: Bool = {
        let v = getenv("FP_VERBOSE") != nil
            || UserDefaults.standard.bool(forKey: "FP_VERBOSE")
        return v
    }()

    // ── macOS-only window state ──
    #if canImport(AppKit)
    // strong: the window is hidden (orderOut) rather than closed for
    // close-to-tray, so the tray's "Show FreePlayer" must always find it
    var window: NSWindow?
    var eqWindow: NSWindow?
    var onboardingWindow: NSWindow?

    /// Window chrome color follows the sidebar/top-bar shade (dark = #292b2f,
    /// light = #fafafa) so the unified content card's corner gap always shows
    /// a color that matches the L-shaped frame.
    func applyAppearance(dark: Bool) {
        let color = dark
            ? NSColor(srgbRed: 0.1608, green: 0.1686, blue: 0.1843, alpha: 1.0) // #292b2f
            : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)      // #fafafa
        window?.backgroundColor = color
        eqWindow?.backgroundColor = color
        onboardingWindow?.backgroundColor = color
    }
    #endif
}