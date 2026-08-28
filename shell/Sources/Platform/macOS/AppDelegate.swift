// FreePlayer shell — app entry delegate: frameless window + WKWebView
// Mirrors the Electron shell's chrome: hidden title bar (hiddenInset),
// traffic lights at (16, 14), full-size content view.

import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var backgroundActivity: NSObjectProtocol?

    // Menu actions targeting the renderer (playback, views, import) are routed
    // through one selector; the action string is a controlled whitelist in JS.
    @objc func menuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String, !action.isEmpty else { return }
        let js = "try { window.__freeplayerMenuAction && window.__freeplayerMenuAction('\(action)'); } catch (e) {}"
        DispatchQueue.main.async {
            AppContext.shared.webView?.evaluateJavaScript(js)
        }
    }

    // Playback/View menu items share the menuAction: selector; ⌘ modifier is
    // the default so only explicit modifiers need overrides.
    private func menuItem(_ title: String, action: String, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = action
        return item
    }

    func buildMenu() {
        let mainMenu = NSMenu()

        // ── FreePlayer (app) menu ──
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "FreePlayer")
        appMenu.addItem(withTitle: "About FreePlayer",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuAction(_:)), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.representedObject = "view-settings"
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FreePlayer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit FreePlayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // ── File ──
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let importItem = NSMenuItem(title: "Import Music…", action: #selector(menuAction(_:)), keyEquivalent: "o")
        importItem.target = self
        importItem.representedObject = "import"
        fileMenu.addItem(importItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        // ── Edit (standard responder chain — works with the webview) ──
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // ── Playback ──
        let playItem = NSMenuItem()
        mainMenu.addItem(playItem)
        let playMenu = NSMenu(title: "Playback")
        playMenu.addItem(menuItem("Play / Pause", action: "playpause", key: "p"))
        playMenu.addItem(menuItem("Next Track", action: "next", key: "→"))
        playMenu.addItem(menuItem("Previous Track", action: "prev", key: "←"))
        playItem.submenu = playMenu

        // ── View ──
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(menuItem("Library", action: "view-library", key: "1"))
        viewMenu.addItem(menuItem("Now Playing", action: "view-now-playing", key: "2"))
        viewMenu.addItem(menuItem("Statistics", action: "view-stats", key: "3"))
        viewMenu.addItem(menuItem("Plugins", action: "view-plugins", key: "4"))
        viewMenu.addItem(.separator())
        let eqItem = NSMenuItem(title: "Equalizer…", action: #selector(menuAction(_:)), keyEquivalent: "e")
        eqItem.keyEquivalentModifierMask = [.option, .command]
        eqItem.target = self
        eqItem.representedObject = "open-eq"
        viewMenu.addItem(eqItem)
        viewItem.submenu = viewMenu

        // ── Window ──
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winMenu.addItem(.separator())
        winMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        winItem.submenu = winMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Database.open(Database.defaultDbPath()) else {
            NSLog("[shell] FATAL: db open failed")
            NSApp.terminate(nil)
            return
        }
        // P: Open tracks database in library root
        Database.openTracksDb(Database.defaultTracksDbPath())
        // P: carry pre-split library data (tracks/playlists/history) into tracks.db
        Database.migrateToSplitDb()
        // Wire the macOS platform bridge so the cross-platform router can
        // delegate NSOpenPanel / NSAlert / Tray / PluginFS calls.
        AppContext.shared.platformBridge = MacPlatformBridge()
        Paths.symlinkBackfill()

        buildMenu()

        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "FreePlayer"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Programmatic windows default to releasedWhenClosed=YES, which over-releases
        // the window (AppKit registry + our own reference) at close → SIGSEGV at exit.
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 0.1608, green: 0.1686, blue: 0.1843, alpha: 1.0) // #292b2f — matches the sidebar so the rounded content card reads seamlessly
        window.minSize = NSSize(width: 960, height: 600)
        window.delegate = self
        AppContext.shared.window = window
        NSLog("[shell] window delegate set: %@", window.delegate != nil ? "yes" : "NO")
        window.center()

        // Prod/dev decision FIRST — WKWebViewConfiguration is copied at
        // initWithFrame:configuration:, so everything must be set before.
        // S12: a bundled .app fails closed when its web assets are missing (no
        // silent dev-server fallback), and env/userdefaults overrides
        // (FP_WEB_ROOT/FP_URL/FP_DB) apply to dev binaries only.
        let defs = UserDefaults.standard
        let bundled = Bundle.main.bundlePath.hasSuffix(".app")
        var webRoot: String?
        if bundled {
            webRoot = (Bundle.main.resourcePath as NSString?)?.appendingPathComponent("web")
            if let wr = webRoot, wr.isEmpty || !FileManager.default.fileExists(atPath: wr) {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "FreePlayer is damaged"
                alert.informativeText = "The bundled web assets were not found at \(wr).\n\nReinstall the app to fix this."
                alert.addButton(withTitle: "Quit")
                _ = alert.runModal()
                NSApp.terminate(nil)
                return
            }
        } else {
            var defRoot = defs.string(forKey: "FP_WEB_ROOT")
            if let r = defRoot, !r.isEmpty { webRoot = r }
            defRoot = ProcessInfo.processInfo.environment["FP_WEB_ROOT"]
            if let r = defRoot, !r.isEmpty { webRoot = r }
        }

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if let wr = webRoot, !wr.isEmpty, FileManager.default.fileExists(atPath: wr) {
            // Prod: no persistent cache/disk store needed
            config.websiteDataStore = .nonPersistent()
        }

        let scheme = SchemeHandler()
        config.setURLSchemeHandler(scheme, forURLScheme: "media")
        config.setURLSchemeHandler(scheme, forURLScheme: "app")

        let bridge = BridgeHandler()
        config.userContentController.add(bridge, name: "freeplayer")

        let bridgeScript = WKUserScript(source: BridgeScript.source,
                                        injectionTime: .atDocumentStart,
                                        forMainFrameOnly: true)
        config.userContentController.addUserScript(bridgeScript)

        let webView = WKWebView(frame: frame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        // Web Inspector (Safari > Develop > FreePlayer): on by default for dev
        // binaries (no .app bundle); bundled builds opt in via FP_INSPECT=1
        // (env or `defaults write`).
        if #available(macOS 13.3, *) {
            let dev = !Bundle.main.bundlePath.hasSuffix(".app")
            webView.isInspectable = dev
                || UserDefaults.standard.bool(forKey: "FP_INSPECT")
                || getenv("FP_INSPECT") != nil
        }
        // S1: every webview shares the navigation gate (main frame: app:// or the
        // configured dev origin only)
        let navGate = NavGate()
        if AppContext.shared.navGate == nil { AppContext.shared.navGate = navGate }
        webView.navigationDelegate = AppContext.shared.navGate
        AppContext.shared.webView = webView
        window.contentView = webView

        // Launch-at-login hidden: a login-item launch happens in the loginwindow
        // session before any user app activation, so the frontmost app is still
        // loginwindow here. Manual launches (Dock/terminal) have a real frontmost
        // app, so the window always shows for those.
        var hideOnLaunch = false
        if Database.getSetting("library_dir", nil) != nil, Tray.settingBool("start_hidden", false) {
            let front = NSWorkspace.shared.frontmostApplication
            hideOnLaunch = front?.bundleIdentifier == "com.apple.loginwindow"
        }
        if hideOnLaunch {
            window.orderOut(nil)
            NSApp.setActivationPolicy(.prohibited)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        Tray.shared.create()

        // Deterministic close for teardown debugging: FP_AUTOCLOSE_SECONDS
        if let autoClose = ProcessInfo.processInfo.environment["FP_AUTOCLOSE_SECONDS"],
           let secs = Double(autoClose) {
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                NSLog("[shell] auto-closing window")
                window.close()
            }
        }

        var loadURL: URL
        if let wr = webRoot, !wr.isEmpty, FileManager.default.fileExists(atPath: wr) {
            AppContext.shared.webRoot = wr
            loadURL = URL(string: "app://index.html")!
            NSLog("[shell] prod mode, webRoot=%@", wr)
        } else {
            // Dev binaries only — a bundled app already failed closed above, so the
            // FP_URL overrides below can never downgrade a release build to the
            // dev server.
            var url = defs.string(forKey: "FP_URL")
            if url == nil || url!.isEmpty { url = ProcessInfo.processInfo.environment["FP_URL"] }
            if url == nil || url!.isEmpty { url = "http://localhost:5173" }
            loadURL = URL(string: url!)!
            NSLog("[shell] dev mode, loading %@", url!)
        }
        webView.load(URLRequest(url: loadURL))
        AppContext.shared.mainLoadURL = loadURL

        // First-run: hide the main window and show the onboarding wizard until a
        // library directory is set (library_dir is native-set only).
        if Database.getSetting("library_dir", nil) == nil {
            window.orderOut(nil)
            Windows.openOnboardingWindow()
        }
    }

    // ── Close-to-tray: a music player must survive window close ──

    func setBackgroundPlayback(_ enabled: Bool) {
        if enabled && backgroundActivity == nil {
            // Keeps App Nap from throttling hidden background playback
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: .background, reason: "Background audio playback")
        } else if !enabled, backgroundActivity != nil {
            ProcessInfo.processInfo.endActivity(backgroundActivity!)
            backgroundActivity = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if Tray.settingBool("tray_enabled", true) {
            sender.orderOut(nil) // hide, keep playing in the tray
            Windows.hideEqWindow()
            setBackgroundPlayback(true)
            Tray.showHiddenNotification()
            return false
        }
        // Tray disabled: closing the window quits the app explicitly
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = AppContext.shared.window {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        setBackgroundPlayback(false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Close-to-tray: orderOut during performClose can look like a window close;
        // never auto-terminate here — windowShouldClose decides instead.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Q1: wait (bounded) for in-flight imports to finish instead of polling a
        // counter — the group drains exactly when the last import batch completed
        // (including the exception paths), so sqlite3_close no longer races a
        // background insert. Database functions are null-guarded as a safety net.
        _ = AppContext.shared.importGroup.wait(timeout: .now() + 10)
        Database.close()
    }
}