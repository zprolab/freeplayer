// FreePlayer shell — fp layer: equalizer state + persistence.
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation

extension FPBridge {

    static func registerEQ(into core: BridgeCore) {
        // ── Equalizer ──
        core.register("getEqState") { call in
            call.reply(eqStateDict())
        }

        core.register("setEq") { call in
            guard let d = call.args.first as? [String: Any] else { call.reply(false); return }
            // S17: validate gains — exactly 10, finite, within ±24 dB
            guard let gains = d["gains"] as? [Any], gains.count == 10,
                  gains.allSatisfy({ ($0 as? NSNumber).map { $0.doubleValue.isFinite && $0.doubleValue >= -24 && $0.doubleValue <= 24 } ?? false }) else { call.reply(false); return }
            saveEq(d)
            broadcastEq()
            call.reply(true)
        }
    }

    // MARK: - Equalizer helpers (cross-platform)

    private static func eqKey(_ suffix: String) -> String { "eq.\(suffix)" }

    // internal (not private): EqSettingsTests round-trips saveEq → eqStateDict
    static func eqStateDict() -> [String: Any] {
        var gains: [NSNumber] = []
        if let raw = Database.getSetting(eqKey("gains"), nil) as? String {
            for p in raw.components(separatedBy: ",") {
                gains.append(NSNumber(value: Double(p) ?? 0))
            }
        }
        while gains.count < 10 { gains.append(NSNumber(value: 0)) }
        // saveEq stores enabled as "1"/"0"; accept legacy "true" too — the
        // reader must match the writer or every setEq broadcast reverts it.
        let enabledRaw = (Database.getSetting(eqKey("enabled"), nil) as? String) ?? "0"
        return [
            "enabled": enabledRaw == "1" || enabledRaw == "true",
            "preset": (Database.getSetting(eqKey("preset"), nil) as? String) ?? "Flat",
            "gains": gains,
        ]
    }

    static func saveEq(_ d: [String: Any]) {
        let gains = (d["gains"] as? [Any] ?? []).map { String(format: "%.1f", ($0 as? NSNumber)?.doubleValue ?? 0) }
        let tx = Database.beginTransaction()
        _ = Database.setSetting(eqKey("enabled"), ((d["enabled"] as? NSNumber)?.boolValue ?? false) ? "1" : "0")
        _ = Database.setSetting(eqKey("preset"), d["preset"] as? String ?? "Custom")
        _ = Database.setSetting(eqKey("gains"), gains.joined(separator: ","))
        if tx { _ = Database.commitTransaction() }
    }

    /// Native → renderer: sync the EQ state to every FreePlayer webview.
    private static func broadcastEq() {
        AppContext.shared.bridgeCore?.emit("_pushEq", eqStateDict())
    }
}
