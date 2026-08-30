// FreePlayer shell — SQLite layer (port of electron/database.js)
// Pure Swift: sqlite3 C API, results as [String: Any]/[Any].
// P: Split into config DB (settings, symlinks) and tracks DB (tracks, playlists, history).

import Foundation
import SQLite3

/// SQLite's SQLITE_TRANSIENT destructor marker ((sqlite3_destructor_type)-1) —
/// not exposed as a macro through the Swift module, re-created explicitly.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Database facade. All functions are null-safe against a closed DB so a
/// background import thread can never crash into a closed connection.
enum Database {
    private(set) static var isOpen = false

    // MARK: - dual database state
    // Config DB: settings, imported_symlinks (lives in Application Support)
    private static var gDb: OpaquePointer?
    private static var gDbPath: String?
    // Tracks DB: tracks, playlists, playlist_tracks, play_history (lives in library root)
    private static var gTracksDb: OpaquePointer?
    private static var gTracksDbPath: String?

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

    /// Execute a query on a specific database handle.
    private static func runQueryOn(_ db: OpaquePointer?, _ sql: String, _ params: [Any]) -> [[String: Any]] {
        guard let db else { return [] }
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
    private static func runExecOn(_ db: OpaquePointer?, _ sql: String, _ params: [Any]) -> Bool {
        guard let db else { return false }
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

    // Config DB query/exec (settings, symlinks)
    private static func runQuery(_ sql: String, _ params: [Any]) -> [[String: Any]] {
        runQueryOn(gDb, sql, params)
    }

    @discardableResult
    private static func runExec(_ sql: String, _ params: [Any]) -> Bool {
        runExecOn(gDb, sql, params)
    }

    // Tracks DB query/exec (tracks, playlists, history)
    private static func runTracksQuery(_ sql: String, _ params: [Any]) -> [[String: Any]] {
        runQueryOn(gTracksDb, sql, params)
    }

    @discardableResult
    private static func runTracksExec(_ sql: String, _ params: [Any]) -> Bool {
        runExecOn(gTracksDb, sql, params)
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

    /// P: Tracks DB path — stored in library root as tracks.db
    static func defaultTracksDbPath() -> String {
        guard let libDir = getSetting("library_dir", nil) as? String, !libDir.isEmpty else {
            // Fallback: same location as config DB
            return (defaultDbPath() as NSString).deletingLastPathComponent + "/tracks.db"
        }
        return (libDir as NSString).appendingPathComponent("tracks.db")
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
        // Config DB schema: only settings and symlinks
        let configSchema = """
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS imported_symlinks (
         lib_path TEXT PRIMARY KEY, target TEXT NOT NULL);
        """
        if sqlite3_exec(db, configSchema, nil, nil, &err) != SQLITE_OK {
            NSLog("[db] config schema failed: %s", err.map { String(cString: $0) } ?? "?")
            if let err { sqlite3_free(err) }
        }
        NSLog("[db] config open ok: %@", path)
        return true
    }

    /// P: Open the tracks database in the library root.
    @discardableResult
    static func openTracksDb(_ path: String) -> Bool {
        gTracksDbPath = path
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db,
                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                           nil) != SQLITE_OK {
            NSLog("[db] tracks open failed: %s", sqlite3_errmsg(db))
            return false
        }
        gTracksDb = db
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, &err) != SQLITE_OK {
            NSLog("[db] tracks WAL failed: %s", err.map { String(cString: $0) } ?? "?")
            if let err { sqlite3_free(err) }
        }
        _ = sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        // Tracks DB schema
        let tracksSchema = """
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
        CREATE INDEX IF NOT EXISTS idx_tracks_artist_album ON tracks(artist, album);
        CREATE INDEX IF NOT EXISTS idx_tracks_year ON tracks(year) WHERE year IS NOT NULL;
        """
        if sqlite3_exec(db, tracksSchema, nil, nil, &err) != SQLITE_OK {
            NSLog("[db] tracks schema failed: %s", err.map { String(cString: $0) } ?? "?")
            if let err { sqlite3_free(err) }
        }
        // Migrations
        _ = sqlite3_exec(db, "ALTER TABLE tracks ADD COLUMN replaygain_gain REAL DEFAULT 0", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE tracks ADD COLUMN replaygain_peak REAL DEFAULT 0", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE tracks ADD COLUMN lrc_path TEXT", nil, nil, nil)
        NSLog("[db] tracks open ok: %@", path)
        return true
    }

    /// P: Migrate tracks data from the pre-split single config DB into the tracks DB.
    ///
    /// The split shipped without a call site, and the original migration bailed
    /// whenever the tracks file already existed — but openTracksDb creates it
    /// empty at every launch, so pre-split libraries showed 0 tracks forever.
    /// This version runs AFTER openTracksDb, checks whether the legacy config DB
    /// still holds track rows AND the tracks DB is empty, then copies the four
    /// tracks-related tables across (column order is identical in both schemas).
    /// Idempotent: once the tracks DB has rows, it does nothing.
    static func migrateToSplitDb() {
        guard let oldDbPath = gDbPath, let dest = gTracksDb else { return }
        // Legacy source: the config DB may still carry the pre-split tables.
        var old: OpaquePointer?
        guard sqlite3_open_v2(oldDbPath, &old, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(old) }

        // Does the legacy DB hold any tracks at all?
        var countStmt: OpaquePointer?
        var legacyCount: Int64 = 0
        if sqlite3_prepare_v2(old, "SELECT COUNT(*) FROM tracks", -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW { legacyCount = sqlite3_column_int64(countStmt, 0) }
            sqlite3_finalize(countStmt)
        }
        guard legacyCount > 0 else { return }

        // Already migrated (tracks DB already has rows)?
        var destCount: Int64 = 0
        var dStmt: OpaquePointer?
        if sqlite3_prepare_v2(dest, "SELECT COUNT(*) FROM tracks", -1, &dStmt, nil) == SQLITE_OK {
            if sqlite3_step(dStmt) == SQLITE_ROW { destCount = sqlite3_column_int64(dStmt, 0) }
            sqlite3_finalize(dStmt)
        }
        guard destCount == 0 else { return }

        NSLog("[db] migrating %lld legacy tracks to split tracks DB", legacyCount)
        var err: UnsafeMutablePointer<CChar>?
        // Copy with FKs off so table order does not matter; restore afterwards.
        _ = sqlite3_exec(dest, "PRAGMA foreign_keys=OFF;", nil, nil, &err)
        if let err { sqlite3_free(err) }
        err = nil

        // Attach the legacy DB read-only to this connection for cross-db SELECT.
        var attachStmt: OpaquePointer?
        if sqlite3_prepare_v2(dest, "ATTACH DATABASE ? AS legacy", -1, &attachStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(attachStmt, 1, oldDbPath, -1, SQLITE_TRANSIENT)
            sqlite3_step(attachStmt)
            sqlite3_finalize(attachStmt)
        }

        let tables = ["tracks", "playlists", "playlist_tracks", "play_history"]
        for table in tables {
            let sql = "INSERT INTO main.\(table) SELECT * FROM legacy.\(table)"
            if sqlite3_exec(dest, sql, nil, nil, &err) != SQLITE_OK {
                NSLog("[db] migration copy failed for %@: %s", table, err.map { String(cString: $0) } ?? "?")
                if let err { sqlite3_free(err) }
                err = nil
            }
        }
        // Keep AUTOINCREMENT sequences above the copied ids so future inserts
        // (which pass NULL rowids) never collide with migrated rows.
        for table in tables {
            let seqSQL = "DELETE FROM main.sqlite_sequence WHERE name = '\(table)';"
                + " INSERT INTO main.sqlite_sequence(name, seq) SELECT '\(table)', MAX(id) FROM main.\(table);"
            _ = sqlite3_exec(dest, seqSQL, nil, nil, &err)
            if let err { sqlite3_free(err) }
            err = nil
        }
        _ = sqlite3_exec(dest, "DETACH DATABASE legacy; PRAGMA foreign_keys=ON;", nil, nil, nil)
        NSLog("[db] migration complete")
    }

    static func close() {
        guard let db = gDb else { return }
        // NEW-6: a still-running statement (import tail) makes sqlite3_close return
        // BUSY — retry briefly instead of dropping the connection mid-insert
        var tries = 0
        while sqlite3_close(db) == SQLITE_BUSY, tries < 50 {
            tries += 1
            usleep(100_000) // 100ms
        }
        gDb = nil
        isOpen = false
        // Also close tracks DB
        if let tracksDb = gTracksDb {
            var t = 0
            while sqlite3_close(tracksDb) == SQLITE_BUSY, t < 50 {
                t += 1
                usleep(100_000)
            }
            gTracksDb = nil
        }
        NSLog("[db] closed (config + tracks)")
    }

    // MARK: - settings (config DB)

    static func getSetting(_ key: String, _ defaultValue: String?) -> String? {
        let rows = runQuery("SELECT value FROM settings WHERE key = ?", [key])
        guard let v = rows.first?["value"], !(v is NSNull) else { return defaultValue }
        return v as? String
    }

    @discardableResult
    static func setSetting(_ key: String, _ value: String?) -> Bool {
        guard let value else { return runExec("DELETE FROM settings WHERE key = ?", [key]) }
        return runExec("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", [key, value])
    }

    // MARK: - imported_symlinks (config DB)

    static func symlinkTarget(_ libPath: String) -> String? {
        let rows = runQuery("SELECT target FROM imported_symlinks WHERE lib_path = ?", [libPath])
        guard let v = rows.first?["target"], !(v is NSNull) else { return nil }
        return v as? String
    }

    @discardableResult
    static func recordSymlink(_ libPath: String, _ target: String) -> Bool {
        runExec("INSERT OR REPLACE INTO imported_symlinks (lib_path, target) VALUES (?, ?)", [libPath, target])
    }

    // MARK: - tracks (tracks DB)

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
        return runTracksQuery(sql, params)
    }

    static func getTrackById(_ id: Int64) -> Any? {
        let rows = runTracksQuery("SELECT * FROM tracks WHERE id = ?", [NSNumber(value: id)])
        return rows.first ?? NSNull()
    }

    @discardableResult
    static func insertTrack(_ t: [String: Any]) -> Bool {
        runTracksExec(
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
        var sets: [String] = []
        var vals: [Any] = []
        for (k, v) in fields {
            guard k != "id", k != "imported_at" else { continue }
            sets.append("\(k) = ?")
            vals.append(v)
        }
        guard !sets.isEmpty else { return false }
        sets.append("updated_at = CURRENT_TIMESTAMP")
        vals.append(NSNumber(value: id))
        return runTracksExec("UPDATE tracks SET \(sets.joined(separator: ", ")) WHERE id = ?", vals)
    }

    @discardableResult
    static func deleteTrack(_ id: Int64) -> Bool {
        runTracksExec("DELETE FROM tracks WHERE id = ?", [NSNumber(value: id)])
    }

    static func getTrackCount() -> Int64 {
        let rows = runTracksQuery("SELECT COUNT(*) AS c FROM tracks", [])
        return (rows.first?["c"] as? NSNumber)?.int64Value ?? 0
    }

    static func getTotalDuration() -> Double {
        let rows = runTracksQuery("SELECT COALESCE(SUM(duration), 0) AS d FROM tracks", [])
        return (rows.first?["d"] as? NSNumber)?.doubleValue ?? 0
    }

    // MARK: - play_history (tracks DB)

    @discardableResult
    static func playStart(_ trackId: Int64) -> Bool {
        runTracksExec("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))",
                [NSNumber(value: trackId)])
    }

    @discardableResult
    static func playEnd(_ historyId: Int64, _ duration: Double, _ percentage: Double) -> Bool {
        runTracksExec("UPDATE play_history SET ended_at = datetime('now'), duration_seconds = ?, play_percentage = ? WHERE id = ?",
                [NSNumber(value: duration), NSNumber(value: percentage), NSNumber(value: historyId)])
    }

    static func getPlayHistory(_ limit: Int) -> [[String: Any]] {
        runTracksQuery("SELECT ph.*, t.title, t.artist, t.album, t.file_path, t.cover_path"
                 + " FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
                 + " ORDER BY ph.started_at DESC LIMIT ?", [NSNumber(value: limit)])
    }

    static func getStats() -> [String: Any] {
        var d: [String: Any] = [:]
        let r1 = runTracksQuery("SELECT COUNT(*) AS c FROM tracks", [])
        d["totalTracks"] = r1.first?["c"] ?? 0
        let r2 = runTracksQuery("SELECT COALESCE(SUM(duration), 0) AS d FROM tracks", [])
        d["totalDuration"] = r2.first?["d"] ?? 0
        let r3 = runTracksQuery("SELECT COUNT(*) AS c FROM play_history", [])
        d["totalPlays"] = r3.first?["c"] ?? 0
        let r4 = runTracksQuery("SELECT COUNT(DISTINCT track_id) AS c FROM play_history", [])
        d["uniqueTracks"] = r4.first?["c"] ?? 0
        return d
    }

    // MARK: - playlists (tracks DB)

    @discardableResult
    static func createPlaylist(_ name: String, _ description: String?) -> Bool {
        runTracksExec("INSERT INTO playlists (name, description) VALUES (?, ?)",
                [name, description ?? NSNull()])
    }

    static func getPlaylists() -> [[String: Any]] {
        runTracksQuery("SELECT * FROM playlists ORDER BY updated_at DESC", [])
    }

    @discardableResult
    static func addToPlaylist(_ playlistId: Int64, _ trackId: Int64) -> Bool {
        let rows = runTracksQuery("SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?", [NSNumber(value: playlistId)])
        let pos = (rows.first?["next_pos"] as? NSNumber)?.int64Value ?? 0
        return runTracksExec("INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                [NSNumber(value: playlistId), NSNumber(value: trackId), NSNumber(value: pos)])
    }

    @discardableResult
    static func addTracksToPlaylist(_ playlistId: Int64, _ trackIds: [Any], startAt pos: Int64) -> Bool {
        insertPlaylistTracks(playlistId, trackIds, startAt: pos, orIgnore: true)
    }

    // P9: Shared helper for playlist track insertion to avoid code duplication
    private static func insertPlaylistTracks(_ playlistId: Int64, _ trackIds: [Any], startAt pos: Int64, orIgnore: Bool = false) -> Bool {
        guard let db = gTracksDb else { return false }
        let insertSQL = orIgnore
            ? "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)"
            : "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[db] insertPlaylistTracks prepare failed: %s", sqlite3_errmsg(db))
            return false
        }
        defer { sqlite3_finalize(stmt) }
        var currentPos = pos
        var allOk = true
        for tid in trackIds {
            guard let num = tid as? NSNumber else { allOk = false; continue }
            sqlite3_bind_int64(stmt, 1, playlistId)
            sqlite3_bind_int64(stmt, 2, num.int64Value)
            sqlite3_bind_int64(stmt, 3, currentPos)
            currentPos += 1
            if sqlite3_step(stmt) != SQLITE_DONE { allOk = false }
            _ = sqlite3_reset(stmt)
        }
        return allOk
            && runTracksExec("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", [NSNumber(value: playlistId)])
    }

    @discardableResult
    static func setPlaylistTracks(_ playlistId: Int64, _ trackIds: [Any]) -> Bool {
        guard runTracksExec("DELETE FROM playlist_tracks WHERE playlist_id = ?", [NSNumber(value: playlistId)]) else { return false }
        return insertPlaylistTracks(playlistId, trackIds, startAt: 0, orIgnore: false)
    }

    static func getPlaylistTracks(_ playlistId: Int64) -> [[String: Any]] {
        runTracksQuery("SELECT t.*, pt.position, pt.added_at as added_to_playlist_at"
                 + " FROM playlist_tracks pt JOIN tracks t ON pt.track_id = t.id"
                 + " WHERE pt.playlist_id = ? ORDER BY pt.position", [NSNumber(value: playlistId)])
    }

    @discardableResult
    static func removeTrackFromPlaylist(_ playlistId: Int64, _ trackId: Int64) -> Bool {
        runTracksExec("DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?",
                [NSNumber(value: playlistId), NSNumber(value: trackId)])
    }

    @discardableResult
    static func deletePlaylist(_ playlistId: Int64) -> Bool {
        runTracksExec("DELETE FROM playlists WHERE id = ?", [NSNumber(value: playlistId)])
    }

    @discardableResult
    static func renamePlaylist(_ playlistId: Int64, _ name: String?) -> Bool {
        runTracksExec("UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                [name ?? "", NSNumber(value: playlistId)])
    }

    // MARK: - transactions (tracks DB)

    static func beginTransaction() -> Bool { runTracksExec("BEGIN IMMEDIATE", []) }
    static func commitTransaction() -> Bool { runTracksExec("COMMIT", []) }
    static func rollbackTransaction() -> Bool { runTracksExec("ROLLBACK", []) }

    // MARK: - LRC (tracks DB)

    @discardableResult
    static func setTrackLrc(_ trackId: Int64, _ lrcPath: String?) -> Bool {
        runTracksExec("UPDATE tracks SET lrc_path = ? WHERE id = ?", [lrcPath ?? NSNull(), NSNumber(value: trackId)])
    }

    @discardableResult
    static func setTrackCover(_ trackId: Int64, _ coverPath: String?) -> Bool {
        runTracksExec("UPDATE tracks SET cover_path = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                [coverPath ?? NSNull(), NSNumber(value: trackId)])
    }

    static func getTrackLrc(_ trackId: Int64) -> String? {
        let rows = runTracksQuery("SELECT lrc_path FROM tracks WHERE id = ?", [NSNumber(value: trackId)])
        guard let v = rows.first?["lrc_path"], !(v is NSNull) else { return nil }
        return v as? String
    }

    @discardableResult
    static func clearTrackLrc(_ trackId: Int64) -> Bool {
        runTracksExec("UPDATE tracks SET lrc_path = NULL WHERE id = ?", [NSNumber(value: trackId)])
    }

    static func countTracksWithCover(_ coverPath: String) -> Int64 {
        let rows = runTracksQuery("SELECT COUNT(*) AS c FROM tracks WHERE cover_path = ?", [coverPath])
        return (rows.first?["c"] as? NSNumber)?.int64Value ?? 0
    }

    @discardableResult
    static func resetDatabase() -> Bool {
        guard let db = gTracksDb else { return false }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db,
            "DELETE FROM playlist_tracks; DELETE FROM play_history; DELETE FROM playlists;"
            + " DELETE FROM tracks;",
            nil, nil, &err)
        if let err { sqlite3_free(err) }
        return rc == SQLITE_OK
    }

    // MARK: - tracks DB path accessor

    static func tracksDbPath() -> String? { gTracksDbPath }

    // MARK: - play session helpers

    @discardableResult
    static func startPlaySession(_ trackId: Int64) -> Int64 {
        guard let db = gTracksDb else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, trackId)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    @discardableResult
    static func endPlaySession(_ historyId: Int64, _ duration: Double, _ percentage: Double) -> Bool {
        runTracksExec("UPDATE play_history SET ended_at = datetime('now'), duration_seconds = ?, play_percentage = ? WHERE id = ?",
                [NSNumber(value: duration), NSNumber(value: percentage), NSNumber(value: historyId)])
    }

    static func getListeningStats() -> [String: Any] {
        var d: [String: Any] = [:]
        let r1 = runTracksQuery("SELECT COUNT(*) AS c FROM tracks", [])
        d["totalTracks"] = r1.first?["c"] ?? 0
        let r2 = runTracksQuery("SELECT COALESCE(SUM(duration), 0) AS d FROM tracks", [])
        d["totalDuration"] = r2.first?["d"] ?? 0
        let r3 = runTracksQuery("SELECT COUNT(*) AS c FROM play_history", [])
        d["totalPlays"] = r3.first?["c"] ?? 0
        let r4 = runTracksQuery("SELECT COUNT(DISTINCT track_id) AS c FROM play_history", [])
        d["uniqueTracks"] = r4.first?["c"] ?? 0
        // Keep the response shape aligned with the Stats view. Older builds
        // returned only the four summary counters, which made the renderer
        // dereference missing arrays and turn the whole page black.
        let r5 = runTracksQuery("SELECT COALESCE(SUM(duration_seconds), 0) AS t FROM play_history", [])
        d["totalTime"] = r5.first?["t"] ?? 0
        d["uniqueTracksPlayed"] = d["uniqueTracks"] ?? 0
        d["topTracks"] = runTracksQuery("""
            SELECT t.id, t.title, t.artist,
                   COUNT(h.id) AS play_count,
                   COALESCE(SUM(h.duration_seconds), 0) AS total_listen_time
            FROM play_history h JOIN tracks t ON t.id = h.track_id
            GROUP BY h.track_id ORDER BY play_count DESC, total_listen_time DESC LIMIT 20
            """, [])
        d["topArtists"] = runTracksQuery("""
            SELECT t.artist,
                   COUNT(h.id) AS play_count,
                   COALESCE(SUM(h.duration_seconds), 0) AS total_listen_time
            FROM play_history h JOIN tracks t ON t.id = h.track_id
            GROUP BY t.artist ORDER BY play_count DESC, total_listen_time DESC LIMIT 20
            """, [])
        d["dailyStats"] = runTracksQuery("""
            SELECT date(started_at) AS date,
                   COALESCE(SUM(duration_seconds), 0) AS total_time,
                   COUNT(*) AS plays
            FROM play_history GROUP BY date(started_at)
            ORDER BY date DESC LIMIT 30
            """, [])
        return d
    }

    static func getAllPlaylists() -> [[String: Any]] {
        runTracksQuery("SELECT * FROM playlists ORDER BY updated_at DESC", [])
    }

    @discardableResult
    static func addTrackToPlaylist(_ playlistId: Int64, _ trackId: Int64) -> Bool {
        let rows = runTracksQuery("SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?", [NSNumber(value: playlistId)])
        let pos = (rows.first?["next_pos"] as? NSNumber)?.int64Value ?? 0
        return runTracksExec("INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                [NSNumber(value: playlistId), NSNumber(value: trackId), NSNumber(value: pos)])
    }

}
