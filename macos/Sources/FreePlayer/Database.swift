import Foundation
import SQLite3

/// SQLite persistence layer. All calls are serialized on an internal queue,
/// so callers can safely invoke from any thread. Row reads return Swift models.
final class Database {
    static let shared = Database()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.freeplayer.db", qos: .userInitiated)

    private init() {}

    // ── Lifecycle ──

    static func defaultDbPath() -> String {
        if let env = ProcessInfo.processInfo.environment["FP_DB"], !env.isEmpty {
            return env
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("FreePlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.db").path
    }

    func open(path: String) -> Bool {
        queue.sync {
            let fm = FileManager.default
            let parent = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

            guard sqlite3_open_v2(path, &db,
                                  SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                                  nil) == SQLITE_OK else {
                NSLog("[db] open failed: %s", sqlite3_errmsg(db))
                return false
            }
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;", nil, nil, nil)
            createSchema()
            NSLog("[db] open ok: %@", path)
            return true
        }
    }

    func close() {
        queue.sync {
            if let db { sqlite3_close(db) }
            db = nil
        }
    }

    private func createSchema() {
        let schema = """
        CREATE TABLE IF NOT EXISTS tracks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          artist TEXT NOT NULL DEFAULT 'Unknown Artist',
          album TEXT NOT NULL DEFAULT 'Unknown Album',
          track_number INTEGER, disc_number INTEGER,
          genre TEXT, year INTEGER,
          duration REAL NOT NULL DEFAULT 0,
          file_path TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL,
          file_size INTEGER DEFAULT 0,
          file_format TEXT, bitrate INTEGER, sample_rate REAL, channels INTEGER,
          cover_path TEXT,
          replaygain_gain REAL DEFAULT 0, replaygain_peak REAL DEFAULT 0,
          lrc_path TEXT,
          play_count INTEGER DEFAULT 0, last_played_at DATETIME,
          imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS play_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          track_id INTEGER NOT NULL,
          started_at DATETIME NOT NULL,
          ended_at DATETIME,
          duration_seconds REAL DEFAULT 0,
          play_percentage REAL DEFAULT 0,
          FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS playlists (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, description TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS playlist_tracks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id INTEGER NOT NULL, track_id INTEGER NOT NULL,
          position INTEGER NOT NULL DEFAULT 0,
          added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
          FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE,
          UNIQUE(playlist_id, track_id)
        );
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
        CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);
        CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id);
        CREATE INDEX IF NOT EXISTS idx_play_history_started ON play_history(started_at);
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);
        """
        sqlite3_exec(db, schema, nil, nil, nil)
    }

    // ── Low-level helpers ──

    private func query(_ sql: String, _ params: [Any?] = []) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[db] prepare failed: %s | %@", sqlite3_errmsg(db), sql)
            return []
        }
        defer { sqlite3_finalize(stmt) }

        bind(params, stmt: stmt)
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                row[name] = colValue(stmt, i)
            }
            rows.append(row)
        }
        return rows
    }

    private func execute(_ sql: String, _ params: [Any?] = []) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[db] exec prepare failed: %s", sqlite3_errmsg(db))
            return false
        }
        defer { sqlite3_finalize(stmt) }
        bind(params, stmt: stmt)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func bind(_ params: [Any?], stmt: OpaquePointer?) {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case let d as Double:
                sqlite3_bind_double(stmt, idx, d)
            case let i as Int64:
                sqlite3_bind_int64(stmt, idx, i)
            case let i as Int:
                sqlite3_bind_int64(stmt, idx, Int64(i))
            case let s as String:
                sqlite3_bind_text(stmt, idx, s, -1, unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self))
            case let n as NSNumber:
                sqlite3_bind_double(stmt, idx, n.doubleValue)
            case is NSNull:
                sqlite3_bind_null(stmt, idx)
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func colValue(_ stmt: OpaquePointer?, _ i: Int32) -> Any {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER:
            return sqlite3_column_int64(stmt, i)
        case SQLITE_FLOAT:
            return sqlite3_column_double(stmt, i)
        case SQLITE_TEXT:
            let c = sqlite3_column_text(stmt, i)
            return c.map { String(cString: $0) } ?? NSNull()
        default:
            return NSNull()
        }
    }

    // ── Model mapping ──

    private func track(from row: [String: Any]) -> Track {
        Track(
            id: row["id"] as? Int64 ?? 0,
            title: row["title"] as? String ?? "",
            artist: row["artist"] as? String ?? Track.unknownArtist,
            album: row["album"] as? String ?? Track.unknownAlbum,
            trackNumber: intValue(row["track_number"]),
            discNumber: intValue(row["disc_number"]),
            genre: row["genre"] as? String,
            year: intValue(row["year"]),
            duration: row["duration"] as? Double ?? 0,
            filePath: row["file_path"] as? String ?? "",
            fileName: row["file_name"] as? String ?? "",
            fileSize: row["file_size"] as? Int64 ?? 0,
            fileFormat: row["file_format"] as? String,
            bitrate: intValue(row["bitrate"]),
            sampleRate: row["sample_rate"] as? Double,
            channels: intValue(row["channels"]),
            coverPath: row["cover_path"] as? String,
            replaygainGain: row["replaygain_gain"] as? Double ?? 0,
            replaygainPeak: row["replaygain_peak"] as? Double ?? 0,
            lrcPath: row["lrc_path"] as? String,
            playCount: row["play_count"] as? Int64 ?? 0,
            lastPlayedAt: parseDate(row["last_played_at"] as? String),
            importedAt: parseDate(row["imported_at"] as? String),
            updatedAt: parseDate(row["updated_at"] as? String)
        )
    }

    private func intValue(_ value: Any?) -> Int? {
        (value as? Int64).map(Int.init) ?? (value as? Int)
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        if let d = f.date(from: s) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    // ── Settings ──

    func getSetting(_ key: String, _ def: String? = nil) -> String? {
        queue.sync {
            let rows = query("SELECT value FROM settings WHERE key = ?", [key])
            if let v = rows.first?["value"] as? String { return v }
            return def
        }
    }

    func setSetting(_ key: String, _ value: String) {
        queue.sync {
            _ = execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                        [key, value])
        }
    }

    func getBoolSetting(_ key: String, fallback: Bool) -> Bool {
        guard let v = getSetting(key) else { return fallback }
        switch v.lowercased() {
        case "true", "1", "1.0", "yes", "on": return true
        default: return false
        }
    }

    // ── Tracks ──

    func getAllTracks(search: String = "", sortBy: String = "imported_at", sortDir: String = "DESC") -> [Track] {
        queue.sync {
            var sortKey = sortBy
            let allowed = ["title", "artist", "album", "duration", "imported_at", "year"]
            if !allowed.contains(sortKey) { sortKey = "imported_at" }
            var dir = sortDir
            if dir != "ASC" { dir = "DESC" }

            var sql = "SELECT * FROM tracks"
            var params: [Any?] = []
            if !search.isEmpty {
                sql += " WHERE title LIKE ? OR artist LIKE ? OR album LIKE ?"
                let term = "%\(search)%"
                params = [term, term, term]
            }
            sql += " ORDER BY \(sortKey) \(dir)"
            return query(sql, params).map(track(from:))
        }
    }

    func getTrack(id: Int64) -> Track? {
        queue.sync {
            query("SELECT * FROM tracks WHERE id = ?", [id]).first.map(track(from:))
        }
    }

    func insertTrack(_ t: Track) -> Bool {
        queue.sync {
            execute("""
            INSERT INTO tracks (title, artist, album, track_number, disc_number, genre, year,
                                duration, file_path, file_name, file_size, file_format, bitrate,
                                sample_rate, channels, cover_path, replaygain_gain, replaygain_peak)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
              title = excluded.title, artist = excluded.artist, album = excluded.album,
              track_number = excluded.track_number, disc_number = excluded.disc_number,
              genre = excluded.genre, year = excluded.year, duration = excluded.duration,
              file_name = excluded.file_name, file_size = excluded.file_size,
              file_format = excluded.file_format, bitrate = excluded.bitrate,
              sample_rate = excluded.sample_rate, channels = excluded.channels,
              cover_path = excluded.cover_path,
              replaygain_gain = excluded.replaygain_gain, replaygain_peak = excluded.replaygain_peak,
              updated_at = CURRENT_TIMESTAMP
            """, [t.title, t.artist, t.album, t.trackNumber, t.discNumber, t.genre, t.year,
                  t.duration, t.filePath, t.fileName, t.fileSize, t.fileFormat, t.bitrate,
                  t.sampleRate, t.channels, t.coverPath, t.replaygainGain, t.replaygainPeak])
        }
    }

    func updateTrack(id: Int64, fields: [String: Any]) -> Bool {
        queue.sync {
            let allowed = ["title", "artist", "album", "genre", "year", "track_number"]
            var sets: [String] = []
            var params: [Any?] = []
            for key in allowed where fields[key] != nil {
                sets.append("\(key) = ?")
                params.append(fields[key])
            }
            if sets.isEmpty { return true }
            params.append(id)
            return execute("UPDATE tracks SET \(sets.joined(separator: ", ")), updated_at = CURRENT_TIMESTAMP WHERE id = ?", params)
        }
    }

    func deleteTrack(id: Int64) -> Bool {
        queue.sync {
            execute("DELETE FROM tracks WHERE id = ?", [id])
        }
    }

    func trackCount() -> Int64 {
        queue.sync {
            (query("SELECT COUNT(*) as c FROM tracks").first?["c"] as? Int64) ?? 0
        }
    }

    func totalDuration() -> Double {
        queue.sync {
            (query("SELECT COALESCE(SUM(duration), 0) as t FROM tracks").first?["t"] as? Double) ?? 0
        }
    }

    // ── Play history ──

    func startPlaySession(trackId: Int64) -> Int64 {
        queue.sync {
            let rows = query("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now')) RETURNING id", [trackId])
            var sid: Int64 = rows.first?["id"] as? Int64 ?? 0
            if sid == 0 {
                _ = execute("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))", [trackId])
                sid = sqlite3_last_insert_rowid(db)
            }
            _ = execute("UPDATE tracks SET play_count = play_count + 1, last_played_at = datetime('now') WHERE id = ?", [trackId])
            return sid
        }
    }

    func endPlaySession(sessionId: Int64, durationSeconds: Double, playPercentage: Double) {
        queue.sync {
            _ = execute("UPDATE play_history SET ended_at = datetime('now'), duration_seconds = ?, play_percentage = ? WHERE id = ?",
                        [durationSeconds, playPercentage, sessionId])
        }
    }

    func playHistory(limit: Int) -> [PlayHistoryEntry] {
        queue.sync {
            query("""
            SELECT ph.*, t.title, t.artist, t.album, t.file_path, t.duration as track_duration
            FROM play_history ph JOIN tracks t ON ph.track_id = t.id
            ORDER BY ph.started_at DESC LIMIT ?
            """, [limit]).map { row in
                PlayHistoryEntry(
                    id: row["id"] as? Int64 ?? 0,
                    trackId: row["track_id"] as? Int64 ?? 0,
                    startedAt: parseDate(row["started_at"] as? String) ?? Date(),
                    endedAt: parseDate(row["ended_at"] as? String),
                    durationSeconds: row["duration_seconds"] as? Double ?? 0,
                    playPercentage: row["play_percentage"] as? Double ?? 0,
                    title: row["title"] as? String ?? "",
                    artist: row["artist"] as? String ?? "",
                    album: row["album"] as? String ?? "",
                    filePath: row["file_path"] as? String ?? "",
                    trackDuration: row["track_duration"] as? Double ?? 0
                )
            }
        }
    }

    func listeningStats() -> ListeningStats {
        queue.sync {
            let total = (query("SELECT COALESCE(SUM(duration_seconds), 0) as t FROM play_history WHERE ended_at IS NOT NULL").first?["t"] as? Double) ?? 0
            let plays = (query("SELECT COUNT(*) as c FROM play_history").first?["c"] as? Int64) ?? 0
            let unique = (query("SELECT COUNT(DISTINCT track_id) as c FROM play_history").first?["c"] as? Int64) ?? 0

            let topTracks = query("""
            SELECT t.id, t.title, t.artist, t.album, t.duration as track_duration,
                   COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time
            FROM play_history ph JOIN tracks t ON ph.track_id = t.id
            GROUP BY t.id ORDER BY play_count DESC LIMIT 10
            """).map { row in
                TopTrack(id: row["id"] as? Int64 ?? 0,
                         title: row["title"] as? String ?? "",
                         artist: row["artist"] as? String ?? "",
                         album: row["album"] as? String ?? "",
                         trackDuration: row["track_duration"] as? Double ?? 0,
                         playCount: row["play_count"] as? Int64 ?? 0,
                         totalListenTime: row["total_listen_time"] as? Double ?? 0)
            }

            let topArtists = query("""
            SELECT t.artist, COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time
            FROM play_history ph JOIN tracks t ON ph.track_id = t.id
            GROUP BY t.artist ORDER BY play_count DESC LIMIT 10
            """).map { row in
                TopArtist(artist: row["artist"] as? String ?? "",
                          playCount: row["play_count"] as? Int64 ?? 0,
                          totalListenTime: row["total_listen_time"] as? Double ?? 0)
            }

            let daily = query("""
            SELECT DATE(started_at) as date, COUNT(*) as plays, COALESCE(SUM(duration_seconds), 0) as total_time
            FROM play_history WHERE started_at >= datetime('now', '-30 days')
            GROUP BY DATE(started_at) ORDER BY date DESC
            """).map { row in
                DailyStat(date: row["date"] as? String ?? "",
                          plays: row["plays"] as? Int64 ?? 0,
                          totalTime: row["total_time"] as? Double ?? 0)
            }

            return ListeningStats(totalTime: total, totalPlays: plays, uniqueTracksPlayed: unique,
                                  topTracks: topTracks, topArtists: topArtists, dailyStats: daily)
        }
    }

    // ── Playlists ──

    func createPlaylist(name: String, description: String?) -> Int64 {
        queue.sync {
            _ = execute("INSERT INTO playlists (name, description) VALUES (?, ?)", [name, description ?? ""])
            return sqlite3_last_insert_rowid(db)
        }
    }

    func allPlaylists() -> [Playlist] {
        queue.sync {
            query("SELECT * FROM playlists ORDER BY updated_at DESC").map { row in
                Playlist(id: row["id"] as? Int64 ?? 0,
                         name: row["name"] as? String ?? "",
                         description: row["description"] as? String,
                         createdAt: parseDate(row["created_at"] as? String),
                         updatedAt: parseDate(row["updated_at"] as? String))
            }
        }
    }

    func renamePlaylist(id: Int64, name: String) -> Bool {
        queue.sync {
            execute("UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", [name, id])
        }
    }

    func deletePlaylist(id: Int64) -> Bool {
        queue.sync {
            execute("DELETE FROM playlists WHERE id = ?", [id])
        }
    }

    func addTrackToPlaylist(playlistId: Int64, trackId: Int64) -> Bool {
        queue.sync {
            let rows = query("SELECT COALESCE(MAX(position), -1) + 1 as p FROM playlist_tracks WHERE playlist_id = ?", [playlistId])
            let pos = (rows.first?["p"] as? Int64) ?? 0
            return execute("INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                           [playlistId, trackId, pos])
        }
    }

    func addTracksToPlaylist(playlistId: Int64, trackIds: [Int64]) {
        queue.sync {
            guard !trackIds.isEmpty else { return }
            let rows = query("SELECT COALESCE(MAX(position), -1) + 1 as p FROM playlist_tracks WHERE playlist_id = ?", [playlistId])
            var pos = (rows.first?["p"] as? Int64) ?? 0
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
            for tid in trackIds {
                sqlite3_bind_int64(stmt, 1, playlistId)
                sqlite3_bind_int64(stmt, 2, tid)
                sqlite3_bind_int64(stmt, 3, pos)
                pos += 1
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_finalize(stmt)
            _ = execute("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", [playlistId])
        }
    }

    func setPlaylistTracks(playlistId: Int64, trackIds: [Int64]) {
        queue.sync {
            guard execute("DELETE FROM playlist_tracks WHERE playlist_id = ?", [playlistId]) else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else { return }
            var pos: Int64 = 0
            for tid in trackIds {
                sqlite3_bind_int64(stmt, 1, playlistId)
                sqlite3_bind_int64(stmt, 2, tid)
                sqlite3_bind_int64(stmt, 3, pos)
                pos += 1
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
            sqlite3_finalize(stmt)
            _ = execute("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", [playlistId])
        }
    }

    func playlistTracks(playlistId: Int64) -> [Track] {
        queue.sync {
            query("""
            SELECT t.*, pt.position, pt.added_at as added_to_playlist_at
            FROM playlist_tracks pt JOIN tracks t ON pt.track_id = t.id
            WHERE pt.playlist_id = ? ORDER BY pt.position
            """, [playlistId]).map(track(from:))
        }
    }

    func removeTrackFromPlaylist(playlistId: Int64, trackId: Int64) -> Bool {
        queue.sync {
            execute("DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?", [playlistId, trackId])
        }
    }

    // ── LRC ──

    func setTrackLrc(trackId: Int64, lrcPath: String?) {
        queue.sync {
            _ = execute("UPDATE tracks SET lrc_path = ? WHERE id = ?", [lrcPath ?? NSNull(), trackId])
        }
    }

    func trackLrc(trackId: Int64) -> String? {
        queue.sync {
            let rows = query("SELECT lrc_path FROM tracks WHERE id = ?", [trackId])
            return rows.first?["lrc_path"] as? String
        }
    }

    // ── Danger zone ──

    func resetDatabase() -> Bool {
        queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db,
                "DELETE FROM playlist_tracks; DELETE FROM play_history; DELETE FROM playlists; DELETE FROM tracks; DELETE FROM settings;",
                nil, nil, &err)
            if let err { sqlite3_free(err) }
            return rc == SQLITE_OK
        }
    }
}
