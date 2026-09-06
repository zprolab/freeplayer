// FreePlayer shell — fp注册层 (FreePlayer bridge registration) — composition
// root. System plumbing registers here; domain methods live in the
// FPBridge+*.swift siblings, wired up in registerAll below.
// Platform differences (dialogs, media keys, login item, plugins, import-mode
// policy) are delegated to the PlatformBridge conformance (平台分配层) — either
// by calling it from a handler (uploadLrc, playStart, setSetting, importFiles)
// or by the platform registering its own methods via
// PlatformBridge.registerAll (importDialog, getPlatform, login item, …).
// The renderer API (BridgeScript.swift / window.freeplayer) is untouched.

import Foundation

enum FPBridge {

    /// Register every cross-platform method. Platform is resolved per call via
    /// AppContext (set before any renderer message can arrive), so registering
    /// early — even before the platform bridge exists — is safe.
    static func registerAll(into core: BridgeCore) {

        // ── Settings / setup ──
        core.register("isSetup") { call in
            let dir = Database.getSetting("library_dir", nil) as? String
            let libraryDirValue: Any = dir ?? NSNull()
            call.reply(["setup": dir != nil, "libraryDir": libraryDirValue])
        }

        core.register("getSetting") { call in
            let v = Database.getSetting(call.args.first as? String ?? "", nil)
            call.reply(v ?? (NSNull() as Any?))
        }

        core.register("setSetting") { call in
            guard let d = call.args.first as? [String: Any] else { call.reply(false); return }
            guard let key = d["key"] as? String, !key.isEmpty else { call.reply(false); return }
            if key == "library_dir" { call.reply(false); return } // NEW-2: trust anchor — native-only
            if key == "import_mode" {
                let mode = "\(d["value"] ?? "")"
                // iOS sandbox cannot symlink out of the container — copy only
                let allowed = AppContext.shared.platformBridge?.allowedImportModes ?? ["copy", "symlink"]
                guard allowed.contains(mode) else { call.reply(false); return }
                call.reply(Database.setSetting(key, mode)); return
            }
            let plain: Set<String> = [
                "volume", "tray_enabled", "tray_notify", "start_hidden",
                "start_on_boot", "default_volume", "default_visualizer",
                "mono_font", "ui_mode",
            ]
            if plain.contains(key)
                || key.hasPrefix("plugin.")
                || key.hasPrefix("plugin_perms_")
                || key.hasPrefix("meta.") {
                let value = d["value"] as? String ?? "\(d["value"] ?? "")"
                call.reply(Database.setSetting(key, value))
            } else {
                call.reply(false)
            }
        }

        core.register("setDiagnosticsEnabled") { call in
            let enabled = (call.args.first as? NSNumber)?.boolValue ?? false
            DebugLog.enabled = enabled
            DebugLog.file("DIAGNOSTICS enabled=\(enabled)")
            call.reply(true)
        }
        core.register("getDiagnosticsPath") { call in call.reply(DebugLog.path()) }
        core.register("clearDiagnostics") { call in DebugLog.clear(); call.reply(true) }
        core.register("logDiagnostic") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            let plugin = String(describing: d["pluginId"] ?? "unknown")
            let level = String(describing: d["level"] ?? "info")
            let message = String(describing: d["message"] ?? "")
            DebugLog.file("PLUGIN id=\(plugin) level=\(level) message=\(message)")
            call.reply(true)
        }

        // Domain registrars (FPBridge+*.swift):
        registerEQ(into: core)
        registerTracks(into: core)
        registerPlayback(into: core)
        registerMedia(into: core)
        registerNetwork(into: core)
        registerPlaylists(into: core)
        registerImport(into: core)
    }
}

/// 组装（composition root）：把 fp 层 + 平台层一起注册进共享 BridgeCore，
/// 并接好出站事件。幂等——重复调用返回同一个 core。
enum BridgeBootstrap {
    static func install() -> BridgeCore {
        if let core = AppContext.shared.bridgeCore { return core }
        let core = BridgeCore()
        FPBridge.registerAll(into: core)
        AppContext.shared.platformBridge?.registerAll(into: core)
        core.emitter = { channel, payload in
            BridgeEmitter.push(channel, payload)
        }
        AppContext.shared.bridgeCore = core
        return core
    }
}
