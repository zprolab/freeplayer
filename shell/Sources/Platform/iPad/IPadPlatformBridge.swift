// FreePlayer shell — iPad platform bridge (PlatformBridge conformance).
// Maps every platform-specific bridge method to iOS equivalents:
// UIDocumentPicker (folder/file selection), UIAlertController (reset
// confirm), MPNowPlayingInfoCenter (Control Center), and no-op / degraded
// answers for macOS-only features (tray, login item, plugins, EQ window).
//
// iOS sandbox notes (import flow):
//  • A folder picked via UIDocumentPicker is only readable while its
//    security-scoped access is active. We adopt it (bookmark + startAccess)
//    and KEEP access for the process lifetime — releasing it in the picker
//    callback would make the subsequent scanDirectory/importFiles/… fail.
//  • library_dir is always inside the app sandbox (Documents/FreePlayer
//    Library) — the sandbox cannot write to user-picked folders, and symlink
//    import is impossible on iOS, so picked folders are read-only SOURCES.

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
    private var pendingUpload: ((Any?) -> Void)?
    private var pendingUploadPath: String?
    private var pendingUploadTrackId: Int64 = 0

    // MARK: - Library location (iOS sandbox)

    /// Where the library lives on iOS: inside the app sandbox. The sandbox
    /// cannot write to user-picked folders, so library_dir always points here
    /// and picked folders are read-only import SOURCES.
    private static func libraryDirPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("FreePlayer Library", isDirectory: true).path
    }

    /// Make sure the in-sandbox library exists and library_dir points at it.
    /// Idempotent: calling it twice changes nothing. Returns the library path.
    @discardableResult
    static func ensureLibraryDir() -> String {
        let lib = libraryDirPath()
        try? FileManager.default.createDirectory(
            atPath: lib, withIntermediateDirectories: true)
        if Database.getSetting("library_dir", nil) as? String != lib {
            _ = Database.setSetting("library_dir", lib)
        }
        return lib
    }

    /// Restore bookmarks + trusted roots at launch so folders picked in a
    /// previous session keep working (called by the iOS entry point).
    static func restorePickedFolders() {
        for path in SecurityScopedBookmarks.restoreAll() {
            AppContext.shared.addTrustedScanRoot(path)
        }
    }

    private func present(_ picker: UIDocumentPickerViewController) {
        guard let host = Host.viewController else {
            // nothing to present on — answer as cancelled
            let cancel: ((Any?) -> Void)? = pendingImport ?? pendingUpload
            cancel?(["canceled": true])
            pendingImport = nil; pendingUpload = nil
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
        // iOS: the library location is FIXED (in-sandbox Documents) — there is
        // nothing for the user to pick. Return the fixed library immediately;
        // only importDialog (pick a SOURCE folder) opens a picker.
        let lib = Self.ensureLibraryDir()
        reply(["canceled": false, "path": lib, "libraryDir": lib])
    }

    func uploadLrc(trackId: Int64, audioPath: String, reply: @escaping (Any?) -> Void) {
        pendingUpload = reply
        pendingUploadPath = audioPath
        pendingUploadTrackId = trackId
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
        // Adopt (bookmark + startAccess) and KEEP access alive: the sandbox
        // only allows reads while access is active, and scan/import run on
        // background queues after this callback returns.
        guard let path = SecurityScopedBookmarks.adopt(url) else {
            finishPending(["canceled": true, "error": "could not access the picked folder"])
            return
        }

        if let reply = pendingImport {
            pendingImport = nil
            // S7: the picked folder becomes a trusted scan root
            AppContext.shared.addTrustedScanRoot(path)
            // The web "Set Up Library" flow reaches us via importDialog; make
            // sure a writable library exists before the import runs.
            let lib = Self.ensureLibraryDir()
            reply(["canceled": false, "sourceDir": path, "libraryDir": lib])
        } else if let reply = pendingUpload, let audioPath = pendingUploadPath {
            pendingUpload = nil
            pendingUploadPath = nil
            let trackId = pendingUploadTrackId
            pendingUploadTrackId = 0
            // copy the .lrc next to the audio file (sandbox-friendly)
            let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent((path as NSString).lastPathComponent)
            // S13: never silently overwrite an existing sidecar; target must
            // stay inside the (sandboxed) library — mirrors the macOS handler
            if FileManager.default.fileExists(atPath: target) {
                reply(["success": false, "error": "A lyrics file with that name already exists"]); return
            }
            guard Paths.isPathInLibrary(target) else {
                reply(["success": false, "error": "target outside library"]); return
            }
            guard let raw = try? Data(contentsOf: url),
                  (try? raw.write(to: URL(fileURLWithPath: target), options: .atomic)) != nil else {
                reply(["success": false, "error": "could not copy lyrics file"]); return
            }
            let content = String(data: raw, encoding: .utf8)
                ?? String(data: raw, encoding: Metadata.gb18030)
            _ = Database.setTrackLrc(trackId, target)
            reply(["success": true, "content": content ?? "", "path": target])
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPending(["canceled": true])
    }

    private func finishPending(_ result: [String: Any]) {
        let reply = pendingImport ?? pendingUpload
        pendingImport = nil; pendingUpload = nil
        pendingUploadPath = nil; pendingUploadTrackId = 0
        reply?(result)
    }
}