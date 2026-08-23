// FreePlayer shell — platform-specific operations that differ between macOS/iPad.
// Cross-platform code (Router) calls these via AppContext.shared.platformBridge.
// IMPORTANT: no AppKit/UIKit types may appear in this protocol — the Router
// and Core/Bridge/UI sources must compile against the iOS SDK unchanged.

import Foundation

/// Abstracts every method the bridge dispatch needs that touches platform-only
/// APIs (file pickers, alerts, login item, plugins, window management). Each
/// target platform (macOS / iPad) provides its own conformance.
protocol PlatformBridge {
    // ── Window management ──
    func handleDragStart(sx: Double, sy: Double)
    func openEqWindow()
    func finishOnboarding()
    func setAppearance(dark: Bool)

    // ── Native dialogs ──
    func importDialog(reply: @escaping (Any?) -> Void)
    func selectLibraryDir(reply: @escaping (Any?) -> Void)
    func uploadLrc(trackId: Int64, audioPath: String, reply: @escaping (Any?) -> Void)
    func resetDatabase() -> Bool

    // ── Playback state (Control Center / tray) ──
    func sendPlaybackState(playing: Bool)
    func trackChanged(track: [String: Any])

    // ── Login item ──
    func getLoginItemSettings() -> [String: Any]
    func setLoginItemSettings(_ d: [String: Any]) -> Bool

    // ── Plugin FS ──
    func listPlugins() -> [[String: Any]]
    func readPluginFile(_ pluginId: String, _ relPath: String) -> String?
    func openPluginsDir()
    func uninstallPlugin(_ pluginId: String) -> Bool
}