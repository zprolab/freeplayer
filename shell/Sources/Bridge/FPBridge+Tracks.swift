// FreePlayer shell — fp layer: track queries + edits.
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation

extension FPBridge {

    static func registerTracks(into core: BridgeCore) {
        // ── Tracks ──
        core.register("getTracks") { call in
            let p = call.args.first as? [String: Any] ?? [:]
            let search = p["search"] as? String ?? ""
            let sortBy = p["sortBy"] as? String ?? "imported_at"
            let sortDir = p["sortDir"] as? String ?? "DESC"
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = Database.getAllTracks(search, sortBy, sortDir)
                DispatchQueue.main.async { call.reply(rows) }
            }
        }

        core.register("getTrack") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getTrackById(tid)) }
            }
        }

        core.register("updateTrack") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            let tid = (d["id"] as? NSNumber)?.int64Value ?? 0
            call.reply(Database.updateTrack(tid, d))
        }

        core.register("deleteTrack") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            let track = Database.getTrackById(tid)
            let ok = Database.deleteTrack(tid)
            // S9: shared album covers: only remove when no other track references
            if ok, let track = track as? [String: Any] {
                if let cover = track["cover_path"] as? String, !cover.isEmpty,
                   Paths.isPathInLibrary(cover),
                   Database.countTracksWithCover(cover) == 0 {
                    let fm = FileManager.default
                    try? fm.removeItem(atPath: cover)
                    let coverDir = (cover as NSString).deletingLastPathComponent
                    if let leftover = try? fm.contentsOfDirectory(atPath: coverDir), leftover.isEmpty {
                        try? fm.removeItem(atPath: coverDir)
                    }
                }
            }
            call.reply(ok)
        }

        core.register("getTrackCount") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(NSNumber(value: Database.getTrackCount())) }
            }
        }

        core.register("getTotalDuration") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(NSNumber(value: Database.getTotalDuration())) }
            }
        }
    }
}
