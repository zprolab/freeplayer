// FreePlayer shell — 平台分配层 (platform dispatch layer).
// Platform-specific operations that differ between macOS/iPad. The fp layer
// (FPBridge) calls these for capabilities (platformId, allowedImportModes,
// uploadLrc, trackChanged) and the platform registers its own bridge methods
// via the registerAll extension below.
// IMPORTANT: no AppKit/UIKit types may appear in this protocol — the Router
// and Core/Bridge/UI sources must compile against the iOS SDK unchanged.

import Foundation

/// Abstracts every method the bridge needs that touches platform-only APIs
/// (file pickers, alerts, login item, plugins, window management). Each target
/// platform (macOS / iPad) provides its own conformance.
protocol PlatformBridge {
    // ── Platform identity / policy ──
    /// "macos" | "ios" — the renderer adapts its UI (getPlatform).
    var platformId: String { get }
    /// Import modes this platform permits. macOS: copy + symlink; the iOS
    /// sandbox is copy-only (defaults to both; iPad overrides).
    var allowedImportModes: Set<String> { get }

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

extension PlatformBridge {
    /// macOS default: both import modes (copy + symlink).
    var allowedImportModes: Set<String> { ["copy", "symlink"] }

    /// 平台分配层：把平台专属方法注册进通用桥层。每个平台实现只需声明
    /// platformId（必要时覆盖 allowedImportModes）；这里统一把协议方法映射
    /// 成 bridge 方法（对应原 BridgeRouter.platformBridgeDispatch 的分发）。
    func registerAll(into core: BridgeCore) {
        core.register("getPlatform") { call in
            call.reply(self.platformId)
        }
        core.register("__dragStart") { call in
            self.handleDragStart(sx: call.args.first as? Double ?? 0,
                                 sy: (call.args.count > 1 ? call.args[1] as? Double : 0) ?? 0)
        }
        core.register("openEqWindow") { call in
            self.openEqWindow(); call.reply(true)
        }
        core.register("finishOnboarding") { call in
            self.finishOnboarding(); call.reply(true)
        }
        core.register("setAppearance") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            self.setAppearance(dark: (d["dark"] as? Bool) ?? true)
            call.reply(true)
        }
        core.register("resetDatabase") { call in
            call.reply(self.resetDatabase())
        }
        core.register("sendPlaybackState") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            self.sendPlaybackState(playing: (d["isPlaying"] as? NSNumber)?.boolValue ?? false)
            call.reply(NSNull())
        }
        core.register("getLoginItemSettings") { call in
            call.reply(self.getLoginItemSettings())
        }
        core.register("setLoginItemSettings") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(["ok": self.setLoginItemSettings(d)])
        }
        core.register("listPlugins") { call in
            call.reply(self.listPlugins())
        }
        core.register("readPluginFile") { call in
            let pid = call.args.first as? String ?? ""
            let rel = call.args.count > 1 ? call.args[1] as? String : nil
            call.reply(self.readPluginFile(pid, rel ?? "") ?? NSNull())
        }
        core.register("openPluginsDir") { call in
            self.openPluginsDir(); call.reply(true)
        }
        core.register("uninstallPlugin") { call in
            call.reply(self.uninstallPlugin(call.args.first as? String ?? ""))
        }
        core.register("importDialog") { call in
            self.importDialog { call.reply($0) }
        }
        core.register("selectLibraryDir") { call in
            self.selectLibraryDir { call.reply($0) }
        }
    }
}
