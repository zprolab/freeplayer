// FreePlayer shell — macOS platform bridge (NSOpenPanel / NSAlert / Tray / PluginFS).

import Cocoa
import WebKit
import ServiceManagement

struct MacPlatformBridge: PlatformBridge {

    // MARK: - Window management

    func handleDragStart(sx: Double, sy: Double, win: NSWindow?) {
        guard let win else { return }
        // Q3: WKWebView reports screenX/screenY in CSS points — do NOT scale by
        // backingScaleFactor or the grab lands at 2x on Retina.
        let screen = win.screen ?? NSScreen.main
        let screenH = screen?.frame.height ?? 0
        let pRaw = NSPoint(x: sx, y: screenH - sy)
        let p = win.convertPoint(fromScreen: pRaw)
        if let evt = NSEvent.mouseEvent(
            with: .leftMouseDown, location: p, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0) {
            win.performDrag(with: evt)
        }
    }

    func openEqWindow() { Windows.openEqWindow() }
    func finishOnboarding() { Windows.finishOnboarding() }

    func setAppearance(dark: Bool) {
        AppContext.shared.applyAppearance(dark: dark)
    }

    // MARK: - Native dialogs

    func importDialog(reply: @escaping (Any?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select directory containing music files"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let sourceDir = panel.url?.path {
            // S7: the panel-selected directory becomes a trusted scan root
            AppContext.shared.addTrustedScanRoot(sourceDir)
            let libraryDir = Database.getSetting("library_dir", nil) as? String
            let libraryDirValue: Any = libraryDir ?? NSNull()
            reply(["canceled": false, "sourceDir": sourceDir, "libraryDir": libraryDirValue])
        } else {
            reply(["canceled": true])
        }
    }

    func selectLibraryDir(reply: @escaping (Any?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Select Library Directory"
        if panel.runModal() == .OK, let dir = panel.url?.path {
            _ = Database.setSetting("library_dir", dir)
            reply(["canceled": false, "path": dir, "libraryDir": dir])
        } else {
            reply(["canceled": true])
        }
    }

    func uploadLrc(trackId: Int64, audioPath: String, reply: @escaping (Any?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select LRC Lyrics File"
        panel.allowedContentTypes = [.plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url?.path else {
            reply(["canceled": true]); return
        }
        let target = ((audioPath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent((chosen as NSString).lastPathComponent)
        // S13: never silently overwrite an existing sidecar
        if FileManager.default.fileExists(atPath: target) {
            reply(["success": false, "error": "A lyrics file with that name already exists"]); return
        }
        guard Paths.isPathInLibrary(target) else {
            reply(["success": false, "error": "target outside library"]); return
        }
        guard let raw = try? Data(contentsOf: URL(fileURLWithPath: chosen)) else {
            reply(["success": false, "error": "read failed"]); return
        }
        do {
            try raw.write(to: URL(fileURLWithPath: target), options: .atomic)
        } catch {
            reply(["success": false, "error": error.localizedDescription]); return
        }
        _ = Database.setTrackLrc(trackId, target)
        let content = String(data: raw, encoding: .utf8)
            ?? String(data: raw, encoding: Metadata.gb18030)
        reply(["success": true, "content": content ?? "", "path": target])
    }

    func resetDatabase() -> Bool {
        // S8: gate behind a native confirmation dialog
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset Database"
        alert.informativeText = "This will permanently delete all tracks, playlists, listening history, and settings. This cannot be undone."
        alert.addButton(withTitle: "Reset Everything")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn && Database.resetDatabase()
    }

    // MARK: - Playback state

    func sendPlaybackState(playing: Bool) {
        Tray.shared.setPlaying(playing)
    }

    func trackChanged(track: [String: Any]) {
        Tray.shared.setNowPlaying(fromTrack: track)
    }

    // MARK: - Login item

    func getLoginItemSettings() -> [String: Any] {
        let hidden = Tray.settingBool("start_hidden", false)
        return ["openAtLogin": Tray.loginItemEnabled(), "openAsHidden": hidden]
    }

    func setLoginItemSettings(_ d: [String: Any]) -> Bool {
        if let hidden = d["openAsHidden"] as? Bool {
            _ = Database.setSetting("start_hidden", hidden ? "1" : "0")
        }
        return Tray.setLoginItem((d["openAtLogin"] as? Bool) ?? false)
    }

    // MARK: - Plugin FS

    func listPlugins() -> [[String: Any]] { PluginFS.listPlugins() }

    func readPluginFile(_ pluginId: String, _ relPath: String) -> String? {
        PluginFS.readPluginFile(pluginId, relPath)
    }

    func openPluginsDir() { PluginFS.openPluginsDir() }

    func uninstallPlugin(_ pluginId: String) -> Bool { PluginFS.removePlugin(pluginId) }
}