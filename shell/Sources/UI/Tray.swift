// FreePlayer shell — tray (M5): status item, playback menu, media keys,
// login item. Communicates with the webview via evaluateJavaScript.
// All state crosses the bridge as plain JSON via messages.

import Cocoa
import WebKit
import MediaPlayer
import ServiceManagement
import UserNotifications

final class Tray: NSObject {
    static let shared = Tray()

    private var statusItem: NSStatusItem?
    private var playPauseItem: NSMenuItem?
    private var nowPlayingItem: NSMenuItem?
    private var menu: NSMenu? // NSStatusItem.menu is not reliably retained
    private var trackTitle = ""
    private var trackArtist = ""
    private var playing = false
    private var nowPlayingGen: Int64 = 0 // #6: stale-cover guard (main thread only)

    private func nowPlayingLabel() -> String {
        if trackTitle.isEmpty { return "♪ Nothing playing" }
        if trackArtist.isEmpty { return "♪ \(trackTitle)" }
        return "♪ \(trackTitle) — \(trackArtist)"
    }

    private func pushToWebview(_ fn: String, _ action: String) {
        DispatchQueue.main.async {
            if let webView = AppContext.shared.webView {
                webView.evaluateJavaScript("window.freeplayer.\(fn)('\(action)')")
            }
        }
    }

    func create() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "▶"
        statusItem?.button?.toolTip = "FreePlayer"

        let m = NSMenu()
        nowPlayingItem = NSMenuItem(title: nowPlayingLabel(), action: nil, keyEquivalent: "")
        nowPlayingItem?.isEnabled = false
        m.addItem(nowPlayingItem!)
        m.addItem(.separator())

        playPauseItem = NSMenuItem(title: "Play/Pause", action: #selector(playPause), keyEquivalent: "")
        playPauseItem?.target = self
        m.addItem(playPauseItem!)

        let next = NSMenuItem(title: "Next Track", action: #selector(nextTrack), keyEquivalent: "")
        next.target = self
        m.addItem(next)

        let prev = NSMenuItem(title: "Previous Track", action: #selector(prevTrack), keyEquivalent: "")
        prev.target = self
        m.addItem(prev)

        m.addItem(.separator())

        let show = NSMenuItem(title: "Show FreePlayer", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        m.addItem(show)

        let quit = NSMenuItem(title: "Quit FreePlayer", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        m.addItem(quit)

        statusItem?.menu = m
        menu = m // keep the menu (and its items) alive for the app lifetime

        // M14: request notification permission up front (UNUserNotificationCenter
        // requires it; the tray-hide notification then just works). Dev binaries
        // (no .app bundle) must skip this — the API throws
        // "bundleProxyForCurrentProcess is nil" outside a proper bundle.
        if Bundle.main.bundlePath.hasSuffix(".app") {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        NSLog("[tray] created; login item enabled=%d", Tray.loginItemEnabled() ? 1 : 0)

        // Media keys (macOS Control Center / keyboard media keys)
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in
            self?.pushToWebview("_pushMediaKey", "playpause"); return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.pushToWebview("_pushMediaKey", "playpause"); return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.pushToWebview("_pushMediaKey", "playpause"); return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.pushToWebview("_pushMediaKey", "next"); return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.pushToWebview("_pushMediaKey", "previous"); return .success
        }
    }

    func setPlaying(_ playing: Bool) {
        self.playing = playing
        DispatchQueue.main.async {
            guard let item = self.statusItem, let button = item.button, let pip = self.playPauseItem else { return }
            button.title = self.playing ? "⏸" : "▶"
            pip.title = self.playing ? "Pause" : "Play"
            // Control Center: keep the playback rate in sync (system advances the
            // progress bar from ElapsedPlaybackTime + rate + duration)
            let np = MPNowPlayingInfoCenter.default()
            if var info = np.nowPlayingInfo {
                info[MPNowPlayingInfoPropertyPlaybackRate] = self.playing ? 1.0 : 0.0
                np.nowPlayingInfo = info
            }
        }
    }

    // Safe path: track info comes from the DB (bridge playStart), never from
    // WebKit-owned objects. Also feeds Control Center (title/artist/artwork).
    func setNowPlaying(fromTrack track: [String: Any]) {
        trackTitle = track["title"] as? String ?? ""
        trackArtist = track["artist"] as? String ?? ""
        let album = track["album"] as? String
        let dur = (track["duration"] as? NSNumber)?.doubleValue ?? 0
        let cover = track["cover_path"] as? String
        // #6: generation guard — two rapid track changes decode out of order; only
        // the latest generation may publish to Control Center
        nowPlayingGen += 1
        let gen = nowPlayingGen
        // L4: decode the cover image off the main thread (fires on every track change)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let img = (cover?.count ?? 0) > 0 ? NSImage(contentsOfFile: cover!) : nil
            DispatchQueue.main.async {
                guard gen == self.nowPlayingGen else { return } // a newer track won the race
                if let nip = self.nowPlayingItem { nip.title = self.nowPlayingLabel() }
                if let item = self.statusItem {
                    item.button?.toolTip = self.trackTitle.isEmpty ? "FreePlayer" : self.trackTitle
                }

                var info: [String: Any] = [:]
                if !self.trackTitle.isEmpty { info[MPMediaItemPropertyTitle] = self.trackTitle }
                if !self.trackArtist.isEmpty { info[MPMediaItemPropertyArtist] = self.trackArtist }
                if let album { info[MPMediaItemPropertyAlbumTitle] = album }
                if dur > 0 { info[MPMediaItemPropertyPlaybackDuration] = dur }
                if let img {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: NSSize(width: 600, height: 600)) { _ in img }
                }
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
                info[MPNowPlayingInfoPropertyPlaybackRate] = self.playing ? 1.0 : 0.0
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    // ── menu actions ──
    @objc func playPause() { NSLog("[tray] menu: playPause"); pushToWebview("_pushControl", "playpause") }
    @objc func nextTrack() { NSLog("[tray] menu: next"); pushToWebview("_pushControl", "next") }
    @objc func prevTrack() { NSLog("[tray] menu: prev"); pushToWebview("_pushControl", "previous") }
    @objc func showWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            AppContext.shared.window?.makeKeyAndOrderFront(nil)
        }
    }
    @objc func quitApp() {
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    // ── Login item (M5) ──

    static func loginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setLoginItem(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            var err: NSError?
            let ok: Bool
            if enabled {
                do { try SMAppService.mainApp.register(); ok = true }
                catch let e as NSError { err = e; ok = false }
            } else {
                do { try SMAppService.mainApp.unregister(); ok = true }
                catch let e as NSError { err = e; ok = false }
            }
            if !ok {
                NSLog("[tray] login item %@ failed: %@", enabled ? "register" : "unregister",
                      err?.localizedDescription ?? "unknown error")
            }
            return ok
        }
        return false
    }

    // Coerce a DB setting (may be NSString or NSNumber) to a boolean
    static func settingBool(_ key: String, _ fallback: Bool) -> Bool {
        guard let val = Database.getSetting(key, nil), !(val is NSNull) else { return fallback }
        if let n = val as? NSNumber { return n.boolValue }
        if let s = val as? String {
            let lower = s.lowercased()
            return lower == "true" || lower == "1" || lower == "1.0"
                || lower == "yes" || lower == "on"
        }
        return fallback
    }

    // Notification when minimized to tray (tray_notify setting)
    static func showHiddenNotification() {
        if !settingBool("tray_notify", true) { return }
        if !Bundle.main.bundlePath.hasSuffix(".app") { return } // dev binary: no notifications
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let c = UNMutableNotificationContent()
            c.title = "FreePlayer"
            c.body = "App is still running in the system tray"
            let req = UNNotificationRequest(identifier: "tray-hide-notify", content: c, trigger: nil)
            center.add(req)
        }
    }
}