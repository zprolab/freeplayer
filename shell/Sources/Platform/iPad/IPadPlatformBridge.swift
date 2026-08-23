// FreePlayer shell — iPad platform bridge (PlatformBridge conformance).
// Maps every platform-specific bridge method to iOS equivalents:
// UIDocumentPicker (folder/file selection), UIAlertController (reset
// confirm), MPNowPlayingInfoCenter (Control Center), and no-op / degraded
// answers for macOS-only features (tray, login item, plugins, EQ window).

import UIKit
import UniformTypeIdentifiers
import MediaPlayer

/// Host for modal presentations — the iOS entry sets this to its root
/// view controller so the bridge can present document pickers/alerts.
enum Host {
    static weak var viewController: UIViewController?
}

final class IPadPlatformBridge: NSObject, PlatformBridge {

    // ── pending document-picker callbacks (one at a time) ──
    private var pendingImport: ((Any?) -> Void)?
    private var pendingSelect: ((Any?) -> Void)?
    private var pendingUpload: ((Any?) -> Void)?
    private var pendingUploadPath: String?

    private func present(_ picker: UIDocumentPickerViewController) {
        guard let host = Host.viewController else {
            // nothing to present on — answer as cancelled
            let cancel: ((Any?) -> Void)? = pendingImport ?? pendingSelect ?? pendingUpload
            cancel?(["canceled": true])
            pendingImport = nil; pendingSelect = nil; pendingUpload = nil
            return
        }
        host.present(picker, animated: true)
    }

    // MARK: - Window management

    func handleDragStart(sx: Double, sy: Double) {
        // no window dragging on iPad — the web chrome uses normal scroll areas
    }

    func openEqWindow() {
        // single-window app: EQ lives inside the web app; no native window.
        // If the renderer ever needs it, route via the menu action instead.
    }

    func finishOnboarding() {
        // onboarding is a web view state; reload returns to the main app
        AppContext.shared.webView?.reload()
    }

    func setAppearance(dark: Bool) {
        Host.viewController?.view.window?.backgroundColor = dark
            ? UIColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1) // #292b2f
            : .systemBackground
    }

    // MARK: - Native dialogs

    func importDialog(reply: @escaping (Any?) -> Void) {
        pendingImport = reply
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        present(picker)
    }

    func selectLibraryDir(reply: @escaping (Any?) -> Void) {
        pendingSelect = reply
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        present(picker)
    }

    func uploadLrc(trackId: Int64, audioPath: String, reply: @escaping (Any?) -> Void) {
        pendingUpload = reply
        pendingUploadPath = audioPath
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: false)
        picker.delegate = self
        present(picker)
    }

    func resetDatabase() -> Bool {
        // synchronous API — present the alert and run the wipe on confirm
        // (the renderer already double-confirms; this is a third gate)
        guard let host = Host.viewController else { return false }
        let alert = UIAlertController(title: "Reset Database",
                                      message: "This will permanently delete all tracks, playlists, listening history, and settings. This cannot be undone.",
                                      preferredStyle: .alert)
        var didReset = false
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset Everything", style: .destructive) { _ in
            didReset = Database.resetDatabase()
        })
        host.present(alert, animated: true)
        return didReset
    }

    // MARK: - Playback state (Control Center)

    func sendPlaybackState(playing: Bool) {
        updateNowPlaying(rate: playing ? 1.0 : 0.0)
    }

    func trackChanged(track: [String: Any]) {
        var info: [String: Any] = [:]
        if let t = track["title"] as? String, !t.isEmpty { info[MPMediaItemPropertyTitle] = t }
        if let a = track["artist"] as? String, !a.isEmpty { info[MPMediaItemPropertyArtist] = a }
        if let al = track["album"] as? String, !al.isEmpty { info[MPMediaItemPropertyAlbumTitle] = al }
        if let d = (track["duration"] as? NSNumber)?.doubleValue, d > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = d
        }
        if let cover = track["cover_path"] as? String,
           let img = UIImage(contentsOfFile: cover) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = playingRate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var playingRate = 0.0

    private func updateNowPlaying(rate: Double) {
        playingRate = rate
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Login item (not available on iOS)

    func getLoginItemSettings() -> [String: Any] {
        ["openAtLogin": false, "openAsHidden": false]
    }

    func setLoginItemSettings(_ d: [String: Any]) -> Bool { false }

    // MARK: - Plugin FS (sandboxed iOS has no plugin directory)

    func listPlugins() -> [[String: Any]] { [] }
    func readPluginFile(_ pluginId: String, _ relPath: String) -> String? { nil }
    func openPluginsDir() {}
    func uninstallPlugin(_ pluginId: String) -> Bool { false }
}

// MARK: - UIDocumentPickerDelegate

extension IPadPlatformBridge: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            finishPending(["canceled": true]); return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let path = url.path

        if let reply = pendingImport {
            pendingImport = nil
            // S7: the picked folder becomes a trusted scan root
            AppContext.shared.addTrustedScanRoot(path)
            let libDir = Database.getSetting("library_dir", nil) as? String
            let libDirValue: Any = libDir ?? NSNull()
            reply(["canceled": false, "sourceDir": path, "libraryDir": libDirValue])
        } else if let reply = pendingSelect {
            pendingSelect = nil
            AppContext.shared.addTrustedScanRoot(path)
            _ = Database.setSetting("library_dir", path)
            reply(["canceled": false, "path": path, "libraryDir": path])
        } else if let reply = pendingUpload, let audioPath = pendingUploadPath {
            pendingUpload = nil
            pendingUploadPath = nil
            // copy the .lrc next to the audio file (sandbox-friendly)
            let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent((path as NSString).lastPathComponent)
            guard FileManager.default.fileExists(atPath: target) == false,
                  let raw = try? Data(contentsOf: url),
                  (try? raw.write(to: URL(fileURLWithPath: target), options: .atomic)) != nil else {
                reply(["success": false, "error": "could not copy lyrics file"]); return
            }
            let content = String(data: raw, encoding: .utf8) ?? ""
            reply(["success": true, "content": content, "path": target])
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPending(["canceled": true])
    }

    private func finishPending(_ result: [String: Any]) {
        let reply = pendingImport ?? pendingSelect ?? pendingUpload
        pendingImport = nil; pendingSelect = nil; pendingUpload = nil; pendingUploadPath = nil
        reply?(result)
    }
}