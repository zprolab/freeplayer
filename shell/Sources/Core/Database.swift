// FreePlayer shell — SQLite layer (port of electron/database.js)
// Pure Swift: sqlite3 C API, results as [String: Any]/[Any].

import Foundation
import SQLite3

/// SQLite's SQLITE_TRANSIENT destructor marker ((sqlite3_destructor_type)-1) —
/// not exposed as a macro through the Swift module, re-created explicitly.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Database facade. All functions are null-safe against a closed DB so a
/// background import thread can never crash into a closed connection.
enum Database {
    private(set) static var isOpen = false

    // MARK: - row helpers

    private static func colValue(_ stmt: OpaquePointer, _ i: Int32) -> Any {
        switch sqlite3_column_type(stmt, i) {
        case SQLITE_INTEGER:
            return NSNumber(value: sqlite3_column_int64(stmt, i))
        case SQLITE_FLOAT:
            return NSNumber(value: sqlite3_column_double(stmt, i))
        case SQLITE_TEXT:
            guard let t = sqlite3_column_text(stmt, i) else { return NSNull() }
            // Q4: invalid UTF-8 must not DROP the column (String(data:encoding:)
            // returns nil on bad bytes, and dict[key]=nil removes the key) —
            // fall back to a lossy conversion so the row keeps its value
            let len = Int(sqlite3_column_bytes(stmt, i))
            let data = Data(bytes: t, count: len)
            if let s = String(data: data, encoding: .utf8) { return s }
            if let s = String(data: data, encoding: .isoLatin1) { return s }
            return NSNull()
        default:
            return NSNull()
        }
    }

    private static func rowToDict(_ stmt: OpaquePointer) -> [String: Any] {
        let n = sqlite3_column_count(stmt)
        var d = [String: Any](minimumCapacity: Int(n))
        for i in 0..<n {
            let key = String(cString: sqlite3_column_name(stmt, i))
            d[key] = colValue(stmt, i)
        }
        return d
    }

    private static func bindParam(_ stmt: OpaquePointer, _ i: Int32, _ p: Any) {
        if let num = p as? NSNumber {
            // M4: bind by type — binding everything as double truncates int64 > 2^53
            let t = CFNumberGetType(num as CFNumber)
            if t == .doubleType || t == .floatType || t == .cgFloatType {
                sqlite3_bind_double(stmt, i, num.doubleValue)
            } else {
                sqlite3_bind_int64(stmt, i, num.int64Value)
            }
        } else if p is NSNull {
            sqlite3_bind_null(stmt, i)
        } else {
            let s = "\(p)"
            sqlite3_bind_text(stmt, i, (s as NSString).utf8String, -1, SQLITE_TRANSIENT)
        }
    }

    private static func runQuery(_ sql: String, _ params: [Any]) -> [[String: Any]] {
        // Q1: the DB can be closed while a background import thread is mid-flight —
        // every entry point must tolerate a closed DB
        guard let db = gDb else { return [] }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            NSLog("[db] prepare failed: %s | %@", sqlite3_errmsg(db), sql)
            return []
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            bindParam(stmt!, Int32(i) + 1, p)
        }
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(rowToDict(stmt!))
        }
        return rows
    }

    @discardableResult
    private static func runExec(_ sql: String, _ params: [Any]) -> Bool {
        // Q1: see runQuery — never prepare on a closed DB
        guard let db = gDb else { return false }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            NSLog("[db] exec prepare failed: %s", sqlite3_errmsg(db))
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            bindParam(stmt!, Int32(i) + 1, p)
        }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    // MARK: - lifecycle

    static func defaultDbPath() -> String {
        // S12: FP_DB env override is a dev-binary convenience — a bundled release
        // must never point at an attacker/repo-controlled database path.
        // P3: Strengthened check — verify bundle is in a legitimate location.
        if let env = ProcessInfo.processInfo.environment["FP_DB"], !env.isEmpty {
            let bundlePath = Bundle.main.bundlePath
            let isDevBinary = bundlePath.contains("/DerivedData/")
                || bundlePath.hasPrefix("/tmp/")
                || bundlePath.hasPrefix("/var/")
                || bundlePath.contains("/Build/Products/")
            // Also allow if not inside a .app bundle (command-line tools)
            let isAppBundle = bundlePath.hasSuffix(".app")
            if isDevBinary || !isAppBundle {
                NSLog("[db] FP_DB override: %@", env)
                return env
            }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("freeplayer/freeplayer.db").path
    }

    @discardableResult
    static func open(_ path: String) -> Bool {
        gDbPath = path
        // sqlite3 creates the file but not its parent directory
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                           nil) != SQLITE_OK {
            NSLog("[db] open failed: %s", sqlite3_errmsg(db))
            return false
        }
        gDb = db
        isOpen = true
        // M11: check PRAGMA results; synchronous=NORMAL is safe under WAL and
        // avoids one fsync per commit; busy_timeout keeps concurrent threads sane
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, &err) != SQLITE_OK {
            NSLog("[db] WAL pragma failed: %s", err.map { String(cString: $0) } ?? "?")
            if let err { sqlite3_free(err) }
        }
        _ = sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        let schema = """
        CREATE TABLE IF NOT EXISTS tracks (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         title TEXT NOT NULL, artist TEXT DEFAULT 'Unknown Artist',
         album TEXT DEFAULT 'Unknown Album', track_number INTEGER, disc_number INTEGER,
         genre TEXT, year INTEGER, duration REAL NOT NULL DEFAULT 0,
         file_path TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL, file_size INTEGER DEFAULT 0,
         file_format TEXT, bitrate INTEGER, sample_rate INTEGER, channels INTEGER,
         cover_path TEXT, replaygain_gain REAL DEFAULT 0, replaygain_peak REAL DEFAULT 0,
         imported_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS play_history (
         id INTEGER PRIMARY KEY AUTOINCREMENT, track_id INTEGER NOT NULL,
         started_at DATETIME NOT NULL, ended_at DATETIME,
         duration_seconds REAL DEFAULT 0, play_percentage REAL DEFAULT 0,
         FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS playlists (
         id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT,
         created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE IF NOT EXISTS playlist_tracks (
         id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL, track_id INTEGER NOT NULL,
         position INTEGER NOT NULL DEFAULT 0, added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
         FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
         FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE,
         UNIQUE(playlist_id, track_id));
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS imported_symlinks (
         lib_path TEXT PRIMARY KEY, target TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
        CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);
        CREATE INDEX IF NOT EXISTS idx_tracks_imported_at ON tracks(imported_at);
        CREATE INDEX IF NOT EXISTS idx_tracks_file_path ON tracks(file_path);
        CREATE INDEX IF NOT EXISTS idx_tracks_cover_path ON tracks(cover_path);
        CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id);
        CREATE INDEX IF NOT EXISTS idx_play_history_started ON play_history(started_at);
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_track ON playlist_tracks(track_id);
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_composite ON playlist_tracks(playlist_id, position);
        -- P6: Composite indexes for common query patterns
        CREATE INDEX IF NOT EXISTS idx_tracks_artist_album ON tracks(artist, album);
        CREATE INDEX IF NOT EXISTS idx_tracks_year ON tracks(year) WHERE year IS NOT NULL;
        """
        if sqlite3_exec(db, schema, nil, nil, &err) != SQLITE_OK {
            NSLog("[db] schema failed: %s", err.map { String(cString: $0) } ?? "?")
            if let err { sqlite3_free(err) }
        }
        // Migrations (ignore failures — column already exists)
        _ = sqlite3_exec(db, "ALTER TABLE tracks ADD COLUMN replaygain_gain REAL DEFAULT 0", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE tracks ADD COLUMN replaygain_peak REAL DEFAULT 0", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE tracks ADD COLUMN lrc_path TEXT", nil, nil, nil)
        NSLog("[db] open ok: %@", path)
        return true
    }

    static func close() {
        guard let db = gDb else { return }
        // NEW-6: a still-running statement (import tail) makes sqlite3_close return
        // BUSY — retry briefly instead of dropping the connection mid-insert
        var tries = 0
        while sqlite3_close(db) == SQLITE_BUSY, tries < 50 {
            Thread.sleep(forTimeInterval: 0.1)
            tries += 1
        }
        gDb = nil
        isOpen = false
    }

    // MARK: - settings

    static func getSetting(_ key: String, _ def: Any?) -> Any? {
        let rows = runQuery("SELECT value FROM settings WHERE key = ?", [key])
        return rows.first?["value"] ?? def
    }

    @discardableResult
    static func setSetting(_ key: String, _ value: String?) -> Bool {
        runExec("INSERT INTO settings (key, value) VALUES (?, ?)"
                + " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [key, value ?? ""])
    }

    // MARK: - imported symlinks (S3e: trust anchor for library symlinks)

    @discardableResult
    static func recordSymlink(_ libPath: String, _ resolvedTarget: String) -> Bool {
        runExec("INSERT INTO imported_symlinks (lib_path, target) VALUES (?, ?)"
                + " ON CONFLICT(lib_path) DO UPDATE SET target = excluded.target",
                [libPath, resolvedTarget])
    }

    static func symlinkTarget(_ libPath: String) -> String? {
        let rows = runQuery("SELECT target FROM imported_symlinks WHERE lib_path = ?", [libPath])
        return rows.first?["target"] as? String
    }

    // MARK: - tracks

    static func getAllTracks(_ search: String, _ sortBy: String, _ sortDir: String) -> [[String: Any]] {
        let allowed = ["title", "artist", "album", "duration", "imported_at", "year"]
        let b = allowed.contains(sortBy) ? sortBy : "imported_at"
        let d = sortDir == "ASC" ? "ASC" : "DESC"
        var sql = "SELECT * FROM tracks"
        var params: [Any] = []
        if !search.isEmpty {
            sql += " WHERE title LIKE ? OR artist LIKE ? OR album LIKE ?"
            let term = "%\(search)%"
            params = [term, term, term]
        }
        sql += " ORDER BY \(b) \(d)"
        return runQuery(sql, params)
    }

    static func getTrackById(_ id: Int64) -> Any? {
        let rows = runQuery("SELECT * FROM tracks WHERE id = ?", [NSNumber(value: id)])
        return rows.first ?? NSNull()
    }

    @discardableResult
    static func insertTrack(_ t: [String: Any]) -> Bool {
        runExec(
            "INSERT INTO tracks (title, artist, album, track_number, disc_number, genre, year,"
            + " duration, file_path, file_name, file_size, file_format, bitrate, sample_rate,"
            + " channels, cover_path, replaygain_gain, replaygain_peak)"
            + " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            + " ON CONFLICT(file_path) DO UPDATE SET"
            + " title = excluded.title, artist = excluded.artist, album = excluded.album,"
            + " track_number = excluded.track_number, disc_number = excluded.disc_number,"
            + " genre = excluded.genre, year = excluded.year, duration = excluded.duration,"
            + " file_name = excluded.file_name, file_size = excluded.file_size,"
            + " file_format = excluded.file_format, bitrate = excluded.bitrate,"
            + " sample_rate = excluded.sample_rate, channels = excluded.channels,"
            + " cover_path = excluded.cover_path,"
            + " replaygain_gain = excluded.replaygain_gain, replaygain_peak = excluded.replaygain_peak,"
            + " updated_at = CURRENT_TIMESTAMP",
            [t["title"] ?? "", t["artist"] ?? "Unknown Artist", t["album"] ?? "Unknown Album",
             t["track_number"] ?? NSNull(), t["disc_number"] ?? NSNull(),
             t["genre"] ?? NSNull(), t["year"] ?? NSNull(),
             t["duration"] ?? 0, t["file_path"] ?? "", t["file_name"] ?? "",
             t["file_size"] ?? 0, t["file_format"] ?? NSNull(),
             t["bitrate"] ?? NSNull(), t["sample_rate"] ?? NSNull(),
             t["channels"] ?? NSNull(), t["cover_path"] ?? NSNull(),
             t["replaygain_gain"] ?? 0, t["replaygain_peak"] ?? 0])
    }

    @discardableResult
    static func updateTrack(_ id: Int64, _ fields: [String: Any]) -> Bool {
        let allowed = ["title", "artist", "album", "genre", "year", "track_number"]
        var sets: [String] = []
        var params: [Any] = []
        for key in allowed {
            if let v = fields[key] {
                sets.append("\(key) = ?")
                params.append(v)
            }
        }
        if sets.isEmpty { return true }
        params.append(NSNumber(value: id))
        let sql = "UPDATE tracks SET \(sets.joined(separator: ", ")), updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        return runExec(sql, params)
    }

    @discardableResult
    static func deleteTrack(_ id: Int64) -> Bool {
        runExec("DELETE FROM tracks WHERE id = ?", [NSNumber(value: id)])
    }

    static func getTrackCount() -> Int64 {
        let rows = runQuery("SELECT COUNT(*) as count FROM tracks", [])
        return (rows.first?["count"] as? NSNumber)?.int64Value ?? 0
    }

    static func getTotalDuration() -> Double {
        let rows = runQuery("SELECT COALESCE(SUM(duration), 0) as total FROM tracks", [])
        return (rows.first?["total"] as? NSNumber)?.doubleValue ?? 0
    }

    // MARK: - play history

    static func startPlaySession(_ trackId: Int64) -> Int64 {
        let rows = runQuery("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now')) RETURNING id",
                            [NSNumber(value: trackId)])
        if let id = rows.first?["id"] as? NSNumber {
            return id.int64Value
        }
        // L5: fallback for pre-3.35 SQLite — reuse the connection's last insert id
        if runExec("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))",
                   [NSNumber(value: trackId)]),
           let db = gDb {
            return Int64(sqlite3_last_insert_rowid(db))
        }
        return 0
    }

    @discardableResult
    static func endPlaySession(_ sessionId: Int64, _ durationSeconds: Double, _ playPercentage: Double) -> Bool {
        runExec("UPDATE play_history SET ended_at = datetime('now'), duration_seconds = ?, play_percentage = ? WHERE id = ?",
                [NSNumber(value: durationSeconds), NSNumber(value: playPercentage), NSNumber(value: sessionId)])
    }

    static func getPlayHistory(_ limit: Int) -> [[String: Any]] {
        runQuery("SELECT ph.*, t.title, t.artist, t.album, t.file_path, t.duration as track_duration"
                 + " FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
                 + " ORDER BY ph.started_at DESC LIMIT ?", [NSNumber(value: limit)])
    }

    static func getListeningStats() -> [String: Any] {
        let t = runQuery("SELECT COALESCE(SUM(duration_seconds), 0) as total FROM play_history WHERE ended_at IS NOT NULL", [])
        let c = runQuery("SELECT COUNT(*) as count FROM play_history", [])
        let u = runQuery("SELECT COUNT(DISTINCT track_id) as count FROM play_history", [])
        let topTracks = runQuery(
            "SELECT t.id, t.title, t.artist, t.album, t.duration as track_duration,"
            + " COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time"
            + " FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
            + " GROUP BY t.id ORDER BY play_count DESC LIMIT 10", [])
        let topArtists = runQuery(
            "SELECT t.artist, COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time"
            + " FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
            + " GROUP BY t.artist ORDER BY play_count DESC LIMIT 10", [])
        let dailyStats = runQuery(
            "SELECT DATE(started_at) as date, COUNT(*) as plays, COALESCE(SUM(duration_seconds), 0) as total_time"
            + " FROM play_history WHERE started_at >= datetime('now', '-30 days')"
            + " GROUP BY DATE(started_at) ORDER BY date DESC", [])
        return [
            "totalTime": (t.first?["total"] as? NSNumber) ?? 0,
            "totalPlays": (c.first?["count"] as? NSNumber) ?? 0,
            "uniqueTracksPlayed": (u.first?["count"] as? NSNumber) ?? 0,
            "topTracks": topTracks,
            "topArtists": topArtists,
            "dailyStats": dailyStats,
        ]
    }

    // MARK: - playlists

    static func createPlaylist(_ name: String, _ description: String?) -> Int64 {
        guard let db = gDb else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO playlists (name, description) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[db] createPlaylist prepare failed: %s", sqlite3_errmsg(db))
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, ((description ?? "") as NSString).utf8String, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
        return Int64(sqlite3_last_insert_rowid(db))
    }

    static func getAllPlaylists() -> [[String: Any]] {
        runQuery("SELECT * FROM playlists ORDER BY updated_at DESC", [])
    }

    @discardableResult
    static func addTrackToPlaylist(_ playlistId: Int64, _ trackId: Int64) -> Bool {
        let rows = runQuery("SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?",
                            [NSNumber(value: playlistId)])
        let pos = (rows.first?["next_pos"] as? NSNumber)?.int64Value ?? 0
        return runExec("INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                       [NSNumber(value: playlistId), NSNumber(value: trackId), NSNumber(value: pos)])
    }

    @discardableResult
    static func addTracksToPlaylist(_ playlistId: Int64, _ trackIds: [Any]) -> Bool {
        if trackIds.isEmpty { return true }
        guard let db = gDb else { return false }
        let rows = runQuery("SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?",
                            [NSNumber(value: playlistId)])
        var pos = (rows.first?["next_pos"] as? NSNumber)?.int64Value ?? 0
        // M8: check prepare — stepping a null stmt would crash on DB failure
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[db] addTracksToPlaylist prepare failed: %s", sqlite3_errmsg(db))
            return false
        }
        defer { sqlite3_finalize(stmt) }
        // Q6: a failed step must fail the call, not vanish
        var allOk = true
        for tid in trackIds {
            guard let num = tid as? NSNumber else { allOk = false; continue }
            sqlite3_bind_int64(stmt, 1, playlistId)
            sqlite3_bind_int64(stmt, 2, num.int64Value)
            sqlite3_bind_int64(stmt, 3, pos)
            pos += 1
            if sqlite3_step(stmt) != SQLITE_DONE { allOk = false }
            _ = sqlite3_reset(stmt)
        }
        return allOk
            && runExec("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", [NSNumber(value: playlistId)])
    }

    @discardableResult
    static func setPlaylistTracks(_ playlistId: Int64, _ trackIds: [Any]) -> Bool {
        guard runExec("DELETE FROM playlist_tracks WHERE playlist_id = ?", [NSNumber(value: playlistId)]),
              let db = gDb else { return false }
        // M8: check prepare — stepping a null stmt would crash on DB failure
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[db] setPlaylistTracks prepare failed: %s", sqlite3_errmsg(db))
            return false
        }
        defer { sqlite3_finalize(stmt) }
        // Q6: a failed step must fail the call, not vanish
        var pos: Int64 = 0
        var allOk = true
        for tid in trackIds {
            guard let num = tid as? NSNumber else { allOk = false; continue }
            sqlite3_bind_int64(stmt, 1, playlistId)
            sqlite3_bind_int64(stmt, 2, num.int64Value)
            sqlite3_bind_int64(stmt, 3, pos)
            pos += 1
            if sqlite3_step(stmt) != SQLITE_DONE { allOk = false }
            _ = sqlite3_reset(stmt)
        }
        return allOk
            && runExec("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", [NSNumber(value: playlistId)])
    }

    static func getPlaylistTracks(_ playlistId: Int64) -> [[String: Any]] {
        runQuery("SELECT t.*, pt.position, pt.added_at as added_to_playlist_at"
                 + " FROM playlist_tracks pt JOIN tracks t ON pt.track_id = t.id"
                 + " WHERE pt.playlist_id = ? ORDER BY pt.position", [NSNumber(value: playlistId)])
    }

    @discardableResult
    static func removeTrackFromPlaylist(_ playlistId: Int64, _ trackId: Int64) -> Bool {
        runExec("DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?",
                [NSNumber(value: playlistId), NSNumber(value: trackId)])
    }

    @discardableResult
    static func deletePlaylist(_ playlistId: Int64) -> Bool {
        runExec("DELETE FROM playlists WHERE id = ?", [NSNumber(value: playlistId)])
    }

    @discardableResult
    static func renamePlaylist(_ playlistId: Int64, _ name: String?) -> Bool {
        runExec("UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                [name ?? "", NSNumber(value: playlistId)])
    }

    // MARK: - transactions (batch writes: import, EQ save)

    static func beginTransaction() -> Bool { runExec("BEGIN IMMEDIATE", []) }
    static func commitTransaction() -> Bool { runExec("COMMIT", []) }
    static func rollbackTransaction() -> Bool { runExec("ROLLBACK", []) }

    // MARK: - LRC

    @discardableResult
    static func setTrackLrc(_ trackId: Int64, _ lrcPath: String?) -> Bool {
        runExec("UPDATE tracks SET lrc_path = ? WHERE id = ?", [lrcPath ?? NSNull(), NSNumber(value: trackId)])
    }

    @discardableResult
    static func setTrackCover(_ trackId: Int64, _ coverPath: String?) -> Bool {
        runExec("UPDATE tracks SET cover_path = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                [coverPath ?? NSNull(), NSNumber(value: trackId)])
    }

    static func getTrackLrc(_ trackId: Int64) -> String? {
        let rows = runQuery("SELECT lrc_path FROM tracks WHERE id = ?", [NSNumber(value: trackId)])
        guard let v = rows.first?["lrc_path"], !(v is NSNull) else { return nil }
        return v as? String
    }

    @discardableResult
    static func clearTrackLrc(_ trackId: Int64) -> Bool {
        runExec("UPDATE tracks SET lrc_path = NULL WHERE id = ?", [NSNumber(value: trackId)])
    }

    static func countTracksWithCover(_ coverPath: String) -> Int64 {
        let rows = runQuery("SELECT COUNT(*) AS c FROM tracks WHERE cover_path = ?", [coverPath])
        return (rows.first?["c"] as? NSNumber)?.int64Value ?? 0
    }

    @discardableResult
    static func resetDatabase() -> Bool {
        guard let db = gDb else { return false }
        // sqlite3_exec runs ALL statements; runExec only compiles the first
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db,
            "DELETE FROM playlist_tracks; DELETE FROM play_history; DELETE FROM playlists;"
            + " DELETE FROM tracks; DELETE FROM settings;",
            nil, nil, &err)
        if let err { sqlite3_free(err) }
        return rc == SQLITE_OK
    }

    // MARK: - state

    private static var gDb: OpaquePointer?
    private static var gDbPath: String?
}