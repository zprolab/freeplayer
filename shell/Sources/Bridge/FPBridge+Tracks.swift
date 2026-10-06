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

        // Re-apply the audio file's OWN metadata as the track's baseline.
        // extractAtPath blocks (async AVFoundation behind a semaphore), so this
        // runs off the main thread like getTracks/getTrack.
        core.register("resetTrackFromFile") { call in
            let tid = (call.args.first as? NSNumber)?.int64Value ?? 0
            DispatchQueue.global(qos: .userInitiated).async {
                let result = resetTrackFromFile(tid)
                DispatchQueue.main.async { call.reply(result) }
            }
        }
    }

    /// Re-read the file and make its own metadata the baseline again.
    ///
    /// Embedded tags replace whatever a plugin fetch or an earlier edit left
    /// behind; embedded artwork replaces the stored cover (and clears it when
    /// the file carries none); embedded lyrics are written into the host's
    /// `<stem>.<id>.lrc` slot unless a `.lrc` already sits next to the audio,
    /// which is a file baseline of its own. Returns the sources applied so the
    /// caller can refresh the row it renders.
    private static func resetTrackFromFile(_ tid: Int64) -> [String: Any] {
        guard tid > 0,
              let track = Database.getTrackById(tid) as? [String: Any],
              let audioPath = track["file_path"] as? String,
              Paths.isPathInLibrary(audioPath) else {
            return ["success": false, "error": "track not found"]
        }
        guard let meta = Metadata.extractAtPath(audioPath) else {
            return ["success": false, "error": "unreadable audio file"]
        }

        let metaSource = meta["meta_source"] as? String ?? "filename"
        _ = Database.updateTrack(tid, [
            "title": meta["title"] ?? "",
            "artist": meta["artist"] ?? "Unknown Artist",
            "album": meta["album"] ?? "Unknown Album",
            "genre": meta["genre"] ?? NSNull(),
            "year": meta["year"] ?? NSNull(),
            "track_number": meta["track_number"] ?? NSNull(),
            "disc_number": meta["disc_number"] ?? NSNull(),
            "meta_source": metaSource,
        ])

        var coverSource: String?
        if let artwork = meta["artwork"] as? Data,
           let coverPath = Metadata.writeEmbeddedCover(artwork, audioPath: audioPath) {
            _ = Database.setTrackCover(tid, coverPath, source: "file")
            coverSource = "file"
        } else {
            // Nothing in the file: the baseline is "no cover", so an online
            // cover recorded earlier is dropped rather than kept.
            _ = Database.setTrackCover(tid, nil)
        }

        var lyricsSource: String?
        if let sidecar = Metadata.findSidecarLrc(audioPath) {
            _ = Database.setTrackLrc(tid, sidecar, source: "sidecar")
            lyricsSource = "sidecar"
        } else if let lyrics = meta["lyrics"] as? String,
                  !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let dest = Paths.autoLrcPath(audioPath: audioPath, trackId: tid)
            if Paths.isPathInLibrary(dest),
               (try? lyrics.write(to: URL(fileURLWithPath: dest), atomically: true, encoding: .utf8)) != nil {
                _ = Database.setTrackLrc(tid, dest, source: "file")
                lyricsSource = "file"
            }
        } else {
            // No lyrics in the file either: drop the reference AND the file an
            // online backend wrote into the host's slot, so the next fetch (or
            // a later import) starts from a clean baseline.
            let stale = Paths.autoLrcPath(audioPath: audioPath, trackId: tid)
            if Paths.isPathInLibrary(stale) {
                try? FileManager.default.removeItem(atPath: stale)
            }
            _ = Database.setTrackLrc(tid, nil)
        }

        return ["success": true,
                "meta_source": metaSource,
                "cover_source": coverSource ?? NSNull(),
                "lyrics_source": lyricsSource ?? NSNull()]
    }
}
