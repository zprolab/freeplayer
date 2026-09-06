// FreePlayer shell — fp layer: play sessions + listening stats.
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation

extension FPBridge {

    static func registerPlayback(into core: BridgeCore) {
        // ── Playback history ──
        core.register("playStart") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            let sid = Database.startPlaySession(tid)
            if let track = Database.getTrackById(tid) as? [String: Any] {
                AppContext.shared.platformBridge?.trackChanged(track: track) // tray / Control Center
            }
            call.reply(NSNumber(value: sid))
        }

        core.register("playEnd") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.endPlaySession(
                (d["sessionId"] as? NSNumber)?.int64Value ?? 0,
                (d["durationSeconds"] as? NSNumber)?.doubleValue ?? 0,
                (d["playPercentage"] as? NSNumber)?.doubleValue ?? 0))
        }

        // ── Stats ──
        core.register("getPlayHistory") { call in
            var limit = (call.args.first as? NSNumber)?.intValue ?? 50
            if limit < 1 || limit > 1000 { limit = 50 }
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getPlayHistory(limit)) }
            }
        }

        core.register("getStats") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getListeningStats()) }
            }
        }
    }
}
