package com.zprolab.FreePlayer.data

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * SQLite layer — port of the main version's shell/src/db.mm.
 * Same schema, same queries, same defaults.
 */
class Database private constructor(context: Context) : SQLiteOpenHelper(context, "freeplayer.db", null, 1) {

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
        // Android's SQLiteDatabase rejects PRAGMA via execSQL; rawQuery works.
        db.rawQuery("PRAGMA journal_mode=WAL", null).use { }
    }

    override fun onCreate(db: SQLiteDatabase) {
        // Android's execSQL compiles only the first statement — run each
        // CREATE statement separately.
        SCHEMA_STATEMENTS.forEach { db.execSQL(it) }
        migrate(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        migrate(db)
    }

    private fun migrate(db: SQLiteDatabase) {
        // Migrations (ignore failures — column already exists)
        runCatching { db.execSQL("ALTER TABLE tracks ADD COLUMN replaygain_gain REAL DEFAULT 0") }
        runCatching { db.execSQL("ALTER TABLE tracks ADD COLUMN replaygain_peak REAL DEFAULT 0") }
        runCatching { db.execSQL("ALTER TABLE tracks ADD COLUMN lrc_path TEXT") }
    }

    // ── settings ──

    fun getSetting(key: String, def: String?): String? {
        val db = readableDatabase
        db.query("settings", arrayOf("value"), "key = ?", arrayOf(key), null, null, null).use { c ->
            return if (c.moveToFirst()) c.getString(0) ?: def else def
        }
    }

    fun setSetting(key: String, value: String): Boolean {
        val db = writableDatabase
        return db.insertWithOnConflict(
            "settings", null,
            ContentValues().apply { put("key", key); put("value", value) },
            SQLiteDatabase.CONFLICT_REPLACE
        ) != -1L
    }

    // ── tracks ──

    fun getAllTracks(search: String, sortBy: String, sortDir: String): List<Track> {
        val allowed = listOf("title", "artist", "album", "duration", "imported_at", "year")
        val sb = if (allowed.contains(sortBy)) sortBy else "imported_at"
        val dir = if (sortDir == "ASC") "ASC" else "DESC"
        val selection = if (search.isNotEmpty()) {
            "title LIKE ? OR artist LIKE ? OR album LIKE ?"
        } else null
        val args = if (search.isNotEmpty()) {
            val term = "%$search%"
            arrayOf(term, term, term)
        } else null
        val db = readableDatabase
        return db.query("tracks", null, selection, args, null, null, "$sb $dir").use { c ->
            buildList { while (c.moveToNext()) add(trackFromCursor(c)) }
        }
    }

    fun getTrackById(id: Long): Track? {
        val db = readableDatabase
        return db.query("tracks", null, "id = ?", arrayOf(id.toString()), null, null, null).use { c ->
            if (c.moveToFirst()) trackFromCursor(c) else null
        }
    }

    fun getTrackByPath(path: String): Track? {
        val db = readableDatabase
        return db.query("tracks", null, "file_path = ?", arrayOf(path), null, null, null).use { c ->
            if (c.moveToFirst()) trackFromCursor(c) else null
        }
    }

    fun insertTrack(t: Track): Boolean {
        val db = writableDatabase
        val values = ContentValues().apply {
            put("title", t.title)
            put("artist", t.artist)
            put("album", t.album)
            putNullable("track_number", t.trackNumber)
            putNullable("disc_number", t.discNumber)
            putNullable("genre", t.genre)
            putNullable("year", t.year)
            put("duration", t.duration)
            put("file_path", t.filePath)
            put("file_name", t.fileName)
            put("file_size", t.fileSize)
            putNullable("file_format", t.fileFormat)
            putNullable("bitrate", t.bitrate)
            putNullable("sample_rate", t.sampleRate)
            putNullable("channels", t.channels)
            putNullable("cover_path", t.coverPath)
            put("replaygain_gain", t.replaygainGain)
            put("replaygain_peak", t.replaygainPeak)
            put("updated_at", nowUtc())
        }
        val inserted = db.insertWithOnConflict("tracks", null, values, SQLiteDatabase.CONFLICT_IGNORE) != -1L
        if (inserted) return true
        return db.update("tracks", values, "file_path = ?", arrayOf(t.filePath)) > 0
    }

    fun updateTrack(id: Long, fields: Map<String, Any?>): Boolean {
        val allowed = listOf("title", "artist", "album", "genre", "year", "track_number")
        val values = ContentValues()
        for (key in allowed) {
            if (fields.containsKey(key)) {
                val v = fields[key]
                when (v) {
                    null -> values.putNull(key)
                    is Int -> values.put(key, v)
                    is Long -> values.put(key, v)
                    is String -> values.put(key, v)
                    else -> values.put(key, v.toString())
                }
            }
        }
        if (values.size() == 0) return true
        values.put("updated_at", nowUtc())
        val db = writableDatabase
        return db.update("tracks", values, "id = ?", arrayOf(id.toString())) >= 0
    }

    fun deleteTrack(id: Long): Boolean {
        val db = writableDatabase
        return db.delete("tracks", "id = ?", arrayOf(id.toString())) >= 0
    }

    fun getTrackCount(): Long {
        val db = readableDatabase
        db.rawQuery("SELECT COUNT(*) as count FROM tracks", null).use { c ->
            return if (c.moveToFirst()) c.getLong(0) else 0L
        }
    }

    fun getTotalDuration(): Double {
        val db = readableDatabase
        db.rawQuery("SELECT COALESCE(SUM(duration), 0) as total FROM tracks", null).use { c ->
            return if (c.moveToFirst()) c.getDouble(0) else 0.0
        }
    }

    // ── play history ──

    fun startPlaySession(trackId: Long): Long {
        val db = writableDatabase
        db.execSQL("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))", arrayOf(trackId))
        return lastInsertId(db)
    }

    fun endPlaySession(sessionId: Long, durationSeconds: Double, playPercentage: Double): Boolean {
        val db = writableDatabase
        db.execSQL(
            "UPDATE play_history SET ended_at = datetime('now'), duration_seconds = ?, play_percentage = ? WHERE id = ?",
            arrayOf(durationSeconds, playPercentage, sessionId)
        )
        return true
    }

    fun getPlayHistory(limit: Int): List<PlayHistoryEntry> {
        val db = readableDatabase
        return db.rawQuery(
            "SELECT ph.*, t.title, t.artist, t.album, t.file_path, t.duration as track_duration" +
                " FROM play_history ph JOIN tracks t ON ph.track_id = t.id" +
                " ORDER BY ph.started_at DESC LIMIT ?",
            arrayOf(limit.toString())
        ).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(
                        PlayHistoryEntry(
                            id = c.getLong(c.getColumnIndexOrThrow("id")),
                            trackId = c.getLong(c.getColumnIndexOrThrow("track_id")),
                            startedAt = c.getString(c.getColumnIndexOrThrow("started_at")) ?: "",
                            endedAt = c.optString(c.getColumnIndexOrThrow("ended_at")),
                            durationSeconds = c.getDouble(c.getColumnIndexOrThrow("duration_seconds")),
                            playPercentage = c.getDouble(c.getColumnIndexOrThrow("play_percentage")),
                            title = c.getString(c.getColumnIndexOrThrow("title")) ?: "",
                            artist = c.getString(c.getColumnIndexOrThrow("artist")) ?: "",
                            album = c.getString(c.getColumnIndexOrThrow("album")) ?: "",
                            filePath = c.getString(c.getColumnIndexOrThrow("file_path")) ?: "",
                            trackDuration = c.getDouble(c.getColumnIndexOrThrow("track_duration")),
                        )
                    )
                }
            }
        }
    }

    fun getListeningStats(): ListeningStats {
        val db = readableDatabase
        val total = db.rawQuery("SELECT COALESCE(SUM(duration_seconds), 0) as total FROM play_history WHERE ended_at IS NOT NULL", null).use { c ->
            if (c.moveToFirst()) c.getDouble(0) else 0.0
        }
        val plays = db.rawQuery("SELECT COUNT(*) as count FROM play_history", null).use { c ->
            if (c.moveToFirst()) c.getLong(0) else 0L
        }
        val unique = db.rawQuery("SELECT COUNT(DISTINCT track_id) as count FROM play_history", null).use { c ->
            if (c.moveToFirst()) c.getLong(0) else 0L
        }
        val topTracks = db.rawQuery(
            "SELECT t.id, t.title, t.artist, t.album, t.duration as track_duration," +
                " COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time" +
                " FROM play_history ph JOIN tracks t ON ph.track_id = t.id" +
                " GROUP BY t.id ORDER BY play_count DESC LIMIT 10",
            null
        ).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(
                        TopTrackStat(
                            id = c.getLong(c.getColumnIndexOrThrow("id")),
                            title = c.getString(c.getColumnIndexOrThrow("title")) ?: "",
                            artist = c.getString(c.getColumnIndexOrThrow("artist")) ?: "",
                            album = c.getString(c.getColumnIndexOrThrow("album")) ?: "",
                            trackDuration = c.getDouble(c.getColumnIndexOrThrow("track_duration")),
                            playCount = c.getInt(c.getColumnIndexOrThrow("play_count")),
                            totalListenTime = c.getDouble(c.getColumnIndexOrThrow("total_listen_time")),
                        )
                    )
                }
            }
        }
        val topArtists = db.rawQuery(
            "SELECT t.artist, COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time" +
                " FROM play_history ph JOIN tracks t ON ph.track_id = t.id" +
                " GROUP BY t.artist ORDER BY play_count DESC LIMIT 10",
            null
        ).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(
                        TopArtistStat(
                            artist = c.getString(c.getColumnIndexOrThrow("artist")) ?: "",
                            playCount = c.getInt(c.getColumnIndexOrThrow("play_count")),
                            totalListenTime = c.getDouble(c.getColumnIndexOrThrow("total_listen_time")),
                        )
                    )
                }
            }
        }
        val daily = db.rawQuery(
            "SELECT DATE(started_at) as date, COUNT(*) as plays, COALESCE(SUM(duration_seconds), 0) as total_time" +
                " FROM play_history WHERE started_at >= datetime('now', '-30 days')" +
                " GROUP BY DATE(started_at) ORDER BY date DESC",
            null
        ).use { c ->
            buildList {
                while (c.moveToNext()) {
                    add(
                        DailyStat(
                            date = c.getString(c.getColumnIndexOrThrow("date")) ?: "",
                            plays = c.getInt(c.getColumnIndexOrThrow("plays")),
                            totalTime = c.getDouble(c.getColumnIndexOrThrow("total_time")),
                        )
                    )
                }
            }
        }
        return ListeningStats(total, plays, unique, topTracks, topArtists, daily)
    }

    // ── playlists ──

    fun createPlaylist(name: String, description: String?): Long {
        val db = writableDatabase
        db.execSQL("INSERT INTO playlists (name, description) VALUES (?, ?)", arrayOf(name, description ?: ""))
        return lastInsertId(db)
    }

    fun getAllPlaylists(): List<Playlist> {
        val db = readableDatabase
        return db.rawQuery("SELECT * FROM playlists ORDER BY updated_at DESC", null).use { c ->
            buildList { while (c.moveToNext()) add(playlistFromCursor(c)) }
        }
    }

    fun addTrackToPlaylist(playlistId: Long, trackId: Long): Boolean {
        val db = writableDatabase
        val pos = nextPlaylistPosition(db, playlistId)
        db.execSQL(
            "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
            arrayOf(playlistId, trackId, pos)
        )
        return true
    }

    fun addTracksToPlaylist(playlistId: Long, trackIds: List<Long>): Boolean {
        if (trackIds.isEmpty()) return true
        val db = writableDatabase
        var pos = nextPlaylistPosition(db, playlistId)
        db.beginTransaction()
        try {
            for (tid in trackIds) {
                db.execSQL(
                    "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                    arrayOf(playlistId, tid, pos)
                )
                pos++
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        db.execSQL("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", arrayOf(playlistId))
        return true
    }

    fun setPlaylistTracks(playlistId: Long, trackIds: List<Long>): Boolean {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("playlist_tracks", "playlist_id = ?", arrayOf(playlistId.toString()))
            var pos = 0
            for (tid in trackIds) {
                db.execSQL(
                    "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                    arrayOf(playlistId, tid, pos)
                )
                pos++
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        db.execSQL("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", arrayOf(playlistId))
        return true
    }

    fun getPlaylistTracks(playlistId: Long): List<Track> {
        val db = readableDatabase
        return db.rawQuery(
            "SELECT t.*, pt.position, pt.added_at as added_to_playlist_at" +
                " FROM playlist_tracks pt JOIN tracks t ON pt.track_id = t.id" +
                " WHERE pt.playlist_id = ? ORDER BY pt.position",
            arrayOf(playlistId.toString())
        ).use { c ->
            buildList { while (c.moveToNext()) add(trackFromCursor(c)) }
        }
    }

    fun removeTrackFromPlaylist(playlistId: Long, trackId: Long): Boolean {
        val db = writableDatabase
        return db.delete(
            "playlist_tracks", "playlist_id = ? AND track_id = ?",
            arrayOf(playlistId.toString(), trackId.toString())
        ) >= 0
    }

    fun deletePlaylist(playlistId: Long): Boolean {
        val db = writableDatabase
        return db.delete("playlists", "id = ?", arrayOf(playlistId.toString())) >= 0
    }

    fun renamePlaylist(playlistId: Long, name: String): Boolean {
        val db = writableDatabase
        db.execSQL(
            "UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            arrayOf(name, playlistId)
        )
        return true
    }

    // ── LRC ──

    fun setTrackLrc(trackId: Long, lrcPath: String?): Boolean {
        val db = writableDatabase
        val values = ContentValues().apply {
            if (lrcPath == null) putNull("lrc_path") else put("lrc_path", lrcPath)
        }
        return db.update("tracks", values, "id = ?", arrayOf(trackId.toString())) >= 0
    }

    fun getTrackLrc(trackId: Long): String? {
        val db = readableDatabase
        return db.query("tracks", arrayOf("lrc_path"), "id = ?", arrayOf(trackId.toString()), null, null, null).use { c ->
            if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
        }
    }

    // ── reset ──

    fun resetDatabase() {
        val db = writableDatabase
        db.execSQL("DELETE FROM playlist_tracks")
        db.execSQL("DELETE FROM play_history")
        db.execSQL("DELETE FROM playlists")
        db.execSQL("DELETE FROM tracks")
        db.execSQL("DELETE FROM settings")
    }

    // ── helpers ──

    private fun lastInsertId(db: SQLiteDatabase): Long {
        db.rawQuery("SELECT last_insert_rowid()", null).use { c ->
            return if (c.moveToFirst()) c.getLong(0) else -1L
        }
    }

    /** SQLite CURRENT_TIMESTAMP-compatible UTC "YYYY-MM-DD HH:MM:SS". */
    private fun nowUtc(): String =
        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
            .format(java.util.Date())

    private fun nextPlaylistPosition(db: SQLiteDatabase, playlistId: Long): Long {
        db.rawQuery(
            "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?",
            arrayOf(playlistId.toString())
        ).use { c ->
            return if (c.moveToFirst()) c.getLong(0) else 0L
        }
    }

    private fun trackFromCursor(c: Cursor): Track {
        fun col(name: String): Int = c.getColumnIndexOrThrow(name)
        fun optCol(name: String): Int? = if (c.columnNames.contains(name)) c.getColumnIndex(name) else null
        return Track(
            id = c.getLong(col("id")),
            title = c.optString(col("title")),
            artist = c.optString(col("artist")).ifEmpty { "Unknown Artist" },
            album = c.optString(col("album")).ifEmpty { "Unknown Album" },
            trackNumber = c.optInt(col("track_number")),
            discNumber = c.optInt(col("disc_number")),
            genre = c.optStringOrNull(col("genre")),
            year = c.optInt(col("year")),
            duration = c.getDouble(col("duration")),
            filePath = c.optString(col("file_path")),
            fileName = c.optString(col("file_name")),
            fileSize = c.getLong(col("file_size")),
            fileFormat = c.optStringOrNull(col("file_format")),
            bitrate = c.optInt(col("bitrate")),
            sampleRate = c.optInt(col("sample_rate")),
            channels = c.optInt(col("channels")),
            coverPath = c.optStringOrNull(col("cover_path")),
            replaygainGain = c.getDouble(col("replaygain_gain")),
            replaygainPeak = c.getDouble(col("replaygain_peak")),
            importedAt = c.optString(col("imported_at")),
            updatedAt = c.optString(col("updated_at")),
            lrcPath = c.optStringOrNull(col("lrc_path")),
            position = optCol("position")?.let { c.optInt(it) },
            addedToPlaylistAt = optCol("added_to_playlist_at")?.let { c.optStringOrNull(it) },
        )
    }

    private fun playlistFromCursor(c: Cursor): Playlist {
        fun col(name: String): Int = c.getColumnIndexOrThrow(name)
        return Playlist(
            id = c.getLong(col("id")),
            name = c.optString(col("name")).ifEmpty { "" },
            description = c.optString(col("description")),
            createdAt = c.optString(col("created_at")).ifEmpty { "" },
            updatedAt = c.optString(col("updated_at")).ifEmpty { "" },
        )
    }

    private fun Cursor.optString(index: Int): String {
        return if (isNull(index)) "" else getString(index)
    }

    private fun Cursor.optStringOrNull(index: Int): String? {
        return if (isNull(index)) null else getString(index)
    }

    private fun Cursor.optInt(index: Int): Int? {
        return if (isNull(index)) null else getInt(index)
    }

    private fun ContentValues.putNullable(key: String, value: Any?) {
        when (value) {
            null -> putNull(key)
            is Int -> put(key, value)
            is Long -> put(key, value)
            is Double -> put(key, value)
            is Float -> put(key, value)
            is Boolean -> put(key, value)
            is String -> put(key, value)
            else -> put(key, value.toString())
        }
    }

    companion object {
        private val SCHEMA_STATEMENTS = listOf(
            "CREATE TABLE IF NOT EXISTS tracks (" +
                " id INTEGER PRIMARY KEY AUTOINCREMENT," +
                " title TEXT NOT NULL, artist TEXT DEFAULT 'Unknown Artist'," +
                " album TEXT DEFAULT 'Unknown Album', track_number INTEGER, disc_number INTEGER," +
                " genre TEXT, year INTEGER, duration REAL NOT NULL DEFAULT 0," +
                " file_path TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL, file_size INTEGER DEFAULT 0," +
                " file_format TEXT, bitrate INTEGER, sample_rate INTEGER, channels INTEGER," +
                " cover_path TEXT, replaygain_gain REAL DEFAULT 0, replaygain_peak REAL DEFAULT 0," +
                " imported_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
                " lrc_path TEXT);",
            "CREATE TABLE IF NOT EXISTS play_history (" +
                " id INTEGER PRIMARY KEY AUTOINCREMENT, track_id INTEGER NOT NULL," +
                " started_at DATETIME NOT NULL, ended_at DATETIME," +
                " duration_seconds REAL DEFAULT 0, play_percentage REAL DEFAULT 0," +
                " FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE);",
            "CREATE TABLE IF NOT EXISTS playlists (" +
                " id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT," +
                " created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);",
            "CREATE TABLE IF NOT EXISTS playlist_tracks (" +
                " id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL, track_id INTEGER NOT NULL," +
                " position INTEGER NOT NULL DEFAULT 0, added_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
                " FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE," +
                " FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE," +
                " UNIQUE(playlist_id, track_id));",
            "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
            "CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);",
            "CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);",
            "CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);",
            "CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id);",
            "CREATE INDEX IF NOT EXISTS idx_play_history_started ON play_history(started_at);",
            "CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);",
        )

        @Volatile
        private var instance: Database? = null

        fun get(context: Context): Database {
            return instance ?: synchronized(this) {
                instance ?: Database(context.applicationContext).also { instance = it }
            }
        }
    }
}
