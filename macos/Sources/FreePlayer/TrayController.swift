import AppKit
import MediaPlayer
import ServiceManagement

/// Menu-bar tray, playback media keys, Control Center integration, and
/// launch-at-login. The tray routes actions back through the app model via
/// closures (set up in the app bootstrap).
final class TrayController: NSObject {

    /// Callbacks wired from AppModel.
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onShowWindow: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var playPauseItem: NSMenuItem?
    private var nowPlayingItem: NSMenuItem?
    private var trackTitle = ""
    private var trackArtist = ""
    private var trackAlbum: String?
    private var trackDuration: Double = 0
    private var coverPath: String?
    private var isPlaying = false

    private override init() {
        super.init()
    }

    static let shared = TrayController()

    func create() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "▶"
        statusItem?.button?.toolTip = "FreePlayer"

        let menu = NSMenu()

        nowPlayingItem = NSMenuItem(title: nowPlayingLabel(), action: nil, keyEquivalent: "")
        nowPlayingItem?.isEnabled = false
        menu.addItem(nowPlayingItem!)
        menu.addItem(.separator())

        playPauseItem = NSMenuItem(title: "Play/Pause", action: #selector(playPauseAction), keyEquivalent: "")
        playPauseItem?.target = self
        menu.addItem(playPauseItem!)

        let next = NSMenuItem(title: "Next Track", action: #selector(nextAction), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let prev = NSMenuItem(title: "Previous Track", action: #selector(previousAction), keyEquivalent: "")
        prev.target = self
        menu.addItem(prev)

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show FreePlayer", action: #selector(showAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let quit = NSMenuItem(title: "Quit FreePlayer", action: #selector(quitAction), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu

        registerMediaCommands()
    }

    private func nowPlayingLabel() -> String {
        if trackTitle.isEmpty { return "♪ Nothing playing" }
        if trackArtist.isEmpty { return "♪ \(trackTitle)" }
        return "♪ \(trackTitle) — \(trackArtist)"
    }

    // ── State updates ──

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        DispatchQueue.main.async {
            self.statusItem?.button?.title = playing ? "⏸" : "▶"
            self.playPauseItem?.title = playing ? "Pause" : "Play"
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    func setNowPlaying(track: Track) {
        trackTitle = track.title
        trackArtist = track.artist
        trackAlbum = track.album == Track.unknownAlbum ? nil : track.album
        trackDuration = track.duration
        coverPath = track.coverPath

        DispatchQueue.main.async {
            self.nowPlayingItem?.title = self.nowPlayingLabel()
            self.statusItem?.button?.toolTip = self.trackTitle.isEmpty ? "FreePlayer" : self.trackTitle

            var info: [String: Any] = [:]
            if !self.trackTitle.isEmpty { info[MPMediaItemPropertyTitle] = self.trackTitle }
            if !self.trackArtist.isEmpty { info[MPMediaItemPropertyArtist] = self.trackArtist }
            if let album = self.trackAlbum { info[MPMediaItemPropertyAlbumTitle] = album }
            if self.trackDuration > 0 { info[MPMediaItemPropertyPlaybackDuration] = self.trackDuration }
            if let cover = self.coverPath, let img = NSImage(contentsOfFile: cover) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: NSSize(width: 600, height: 600)) { _ in img }
            }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
            info[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    // ── Media keys (Control Center / keyboard) ──

    private func registerMediaCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?()
            return .success
        }
    }

    // ── Menu actions ──

    @objc private func playPauseAction() { onPlayPause?() }
    @objc private func nextAction() { onNext?() }
    @objc private func previousAction() { onPrevious?() }
    @objc private func showAction() { onShowWindow?() }
    @objc private func quitAction() {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // ── Login item ──

    func loginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    func setLoginItem(enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                NSLog("[tray] login item %@ failed: %@", enabled ? "register" : "unregister", error.localizedDescription)
                return false
            }
        }
        return false
    }

    // ── Hidden-to-tray notification ──

    func showHiddenNotification() {
        guard Database.shared.getBoolSetting("tray_notify", fallback: true) else { return }
        let notification = NSUserNotification()
        notification.title = "FreePlayer"
        notification.informativeText = "App is still running in the system tray"
        NSUserNotificationCenter.default.deliver(notification)
    }
}
