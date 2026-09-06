// FreePlayer shell — fp layer: playlists.
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation

extension FPBridge {

    static func registerPlaylists(into core: BridgeCore) {
        // ── Playlists ──
        core.register("getPlaylists") { call in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getAllPlaylists()) }
            }
        }

        core.register("createPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            guard let name = d["name"] as? String, !name.isEmpty, name.count <= 512,
                  (d["description"] as? String ?? "").count <= 4096 else { call.reply(["lastInsertRowid": 0, "error": "invalid playlist"]); return }
            call.reply(["lastInsertRowid": NSNumber(value: Database.createPlaylist(
                name, d["description"] as? String))])
        }

        core.register("renamePlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.renamePlaylist((d["id"] as? NSNumber)?.int64Value ?? 0, d["name"] as? String))
        }

        core.register("deletePlaylist") { call in
            call.reply(Database.deletePlaylist((call.args.first as? NSNumber)?.int64Value ?? 0))
        }

        core.register("getPlaylistTracks") { call in
            let pid = (call.args.first as? NSNumber)?.int64Value ?? 0
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async { call.reply(Database.getPlaylistTracks(pid)) }
            }
        }

        core.register("addToPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.addTrackToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        }

        core.register("addTracksToPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            guard let ids = d["trackIds"] as? [Any], ids.count <= 10000 else { call.reply(false); return }
            call.reply(Database.addTracksToPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                ids,
                startAt: 0))
        }

        core.register("setPlaylistTracks") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            guard let ids = d["trackIds"] as? [Any], ids.count <= 10000 else { call.reply(false); return }
            call.reply(Database.setPlaylistTracks(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                ids))
        }

        core.register("removeFromPlaylist") { call in
            let d = call.args.first as? [String: Any] ?? [:]
            call.reply(Database.removeTrackFromPlaylist(
                (d["playlistId"] as? NSNumber)?.int64Value ?? 0,
                (d["trackId"] as? NSNumber)?.int64Value ?? 0))
        }
    }
}
