const Database = require('better-sqlite3');
const path = require('path');
const { app } = require('electron');

let db;

function getDbPath() {
  const userDataPath = app.getPath('userData');
  return path.join(userDataPath, 'freeplayer.db');
}

function initDatabase() {
  try {
    db = new Database(getDbPath());
  } catch (err) {
    console.error('Failed to initialize database:', err.message);
    console.error('Database path:', getDbPath());
    throw err;
  }
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  db.exec(`
    CREATE TABLE IF NOT EXISTS tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      artist TEXT DEFAULT 'Unknown Artist',
      album TEXT DEFAULT 'Unknown Album',
      track_number INTEGER,
      disc_number INTEGER,
      genre TEXT,
      year INTEGER,
      duration REAL NOT NULL DEFAULT 0,
      file_path TEXT NOT NULL UNIQUE,
      file_name TEXT NOT NULL,
      file_size INTEGER DEFAULT 0,
      file_format TEXT,
      bitrate INTEGER,
      sample_rate INTEGER,
      channels INTEGER,
      cover_path TEXT,
      replaygain_gain REAL DEFAULT 0,
      replaygain_peak REAL DEFAULT 0,
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
      name TEXT NOT NULL,
      description TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS playlist_tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL,
      track_id INTEGER NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
      FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE,
      UNIQUE(playlist_id, track_id)
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);
    CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
    CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);
    CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id);
    CREATE INDEX IF NOT EXISTS idx_play_history_started ON play_history(started_at);
    CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);
  `);

  // Migrations for existing databases
  const migrations = [
    'ALTER TABLE tracks ADD COLUMN replaygain_gain REAL DEFAULT 0',
    'ALTER TABLE tracks ADD COLUMN replaygain_peak REAL DEFAULT 0',
    'ALTER TABLE tracks ADD COLUMN lrc_path TEXT',
  ];
  for (const sql of migrations) {
    try { db.exec(sql); } catch { /* column already exists */ }
  }

  // Migration: fix table naming bug where settings was incorrectly used as play_history
  try {
    const settingsCols = db.pragma('table_info(settings)');
    const hasTrackId = settingsCols.some(c => c.name === 'track_id');
    if (hasTrackId) {
      db.exec('ALTER TABLE settings RENAME TO play_history');
    }
  } catch { /* clean install or already migrated */ }

  return db;
}

function getDatabase() {
  if (!db) {
    throw new Error('Database not initialized. Call initDatabase() first.');
  }
  return db;
}

function closeDatabase() {
  if (db) {
    db.close();
    db = null;
  }
}

// ── Track operations ──

function insertTrack(trackData) {
  const db = getDatabase();
  const stmt = db.prepare(`
    INSERT INTO tracks (title, artist, album, track_number, disc_number, genre, year,
      duration, file_path, file_name, file_size, file_format, bitrate, sample_rate,
      channels, cover_path, replaygain_gain, replaygain_peak)
    VALUES (@title, @artist, @album, @track_number, @disc_number, @genre, @year,
      @duration, @file_path, @file_name, @file_size, @file_format, @bitrate, @sample_rate,
      @channels, @cover_path, @replaygain_gain, @replaygain_peak)
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
  `);
  return stmt.run(trackData);
}

function getAllTracks(search = '', sortBy = 'imported_at', sortDir = 'DESC') {
  const db = getDatabase();
  const allowedSortColumns = ['title', 'artist', 'album', 'duration', 'imported_at', 'year'];
  if (!allowedSortColumns.includes(sortBy)) sortBy = 'imported_at';
  if (!['ASC', 'DESC'].includes(sortDir.toUpperCase())) sortDir = 'DESC';

  let query = 'SELECT * FROM tracks';
  const params = [];

  if (search) {
    query += ' WHERE title LIKE ? OR artist LIKE ? OR album LIKE ?';
    const term = `%${search}%`;
    params.push(term, term, term);
  }

  query += ` ORDER BY ${sortBy} ${sortDir}`;
  return db.prepare(query).all(...params);
}

function getTrackById(id) {
  const db = getDatabase();
  return db.prepare('SELECT * FROM tracks WHERE id = ?').get(id);
}

function deleteTrack(id) {
  const db = getDatabase();
  return db.prepare('DELETE FROM tracks WHERE id = ?').run(id);
}

function updateTrack(id, fields) {
  const db = getDatabase();
  const allowed = ['title', 'artist', 'album', 'genre', 'year', 'track_number'];
  const sets = [];
  const params = {};
  for (const key of allowed) {
    if (fields[key] !== undefined) {
      sets.push(`${key} = @${key}`);
      params[key] = fields[key];
    }
  }
  if (sets.length === 0) return { changes: 0 };
  params.id = id;
  return db.prepare(`UPDATE tracks SET ${sets.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE id = @id`).run(params);
}

function getTrackCount() {
  const db = getDatabase();
  return db.prepare('SELECT COUNT(*) as count FROM tracks').get().count;
}

// ── Play history operations ──

function startPlaySession(trackId) {
  const db = getDatabase();
  const result = db.prepare(
    'INSERT INTO play_history (track_id, started_at) VALUES (?, datetime(\'now\'))'
  ).run(trackId);
  return result.lastInsertRowid;
}

function endPlaySession(sessionId, durationSeconds, playPercentage = 100) {
  const db = getDatabase();
  db.prepare(`
    UPDATE play_history
    SET ended_at = datetime('now'),
        duration_seconds = ?,
        play_percentage = ?
    WHERE id = ?
  `).run(durationSeconds, playPercentage, sessionId);
}

function getPlayHistory(limit = 50) {
  const db = getDatabase();
  return db.prepare(`
    SELECT ph.*, t.title, t.artist, t.album, t.file_path, t.duration as track_duration
    FROM play_history ph
    JOIN tracks t ON ph.track_id = t.id
    ORDER BY ph.started_at DESC
    LIMIT ?
  `).all(limit);
}

function getListeningStats() {
  const db = getDatabase();
  const totalTime = db.prepare(
    'SELECT COALESCE(SUM(duration_seconds), 0) as total FROM play_history WHERE ended_at IS NOT NULL'
  ).get().total;

  const totalPlays = db.prepare(
    'SELECT COUNT(*) as count FROM play_history'
  ).get().count;

  const uniqueTracksPlayed = db.prepare(
    'SELECT COUNT(DISTINCT track_id) as count FROM play_history'
  ).get().count;

  const topTracks = db.prepare(`
    SELECT t.id, t.title, t.artist, t.album, t.duration as track_duration,
           COUNT(ph.id) as play_count,
           COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time
    FROM play_history ph
    JOIN tracks t ON ph.track_id = t.id
    GROUP BY t.id
    ORDER BY play_count DESC
    LIMIT 10
  `).all();

  const topArtists = db.prepare(`
    SELECT t.artist,
           COUNT(ph.id) as play_count,
           COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time
    FROM play_history ph
    JOIN tracks t ON ph.track_id = t.id
    GROUP BY t.artist
    ORDER BY play_count DESC
    LIMIT 10
  `).all();

  const dailyStats = db.prepare(`
    SELECT DATE(started_at) as date,
           COUNT(*) as plays,
           COALESCE(SUM(duration_seconds), 0) as total_time
    FROM play_history
    WHERE started_at >= datetime('now', '-30 days')
    GROUP BY DATE(started_at)
    ORDER BY date DESC
  `).all();

  return { totalTime, totalPlays, uniqueTracksPlayed, topTracks, topArtists, dailyStats };
}

// ── Playlist operations ──

function createPlaylist(name, description = '') {
  const db = getDatabase();
  return db.prepare(
    'INSERT INTO playlists (name, description) VALUES (?, ?)'
  ).run(name, description);
}

function getAllPlaylists() {
  const db = getDatabase();
  return db.prepare('SELECT * FROM playlists ORDER BY updated_at DESC').all();
}

function addTrackToPlaylist(playlistId, trackId) {
  const db = getDatabase();
  const maxPos = db.prepare(
    'SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?'
  ).get(playlistId).next_pos;
  return db.prepare(
    'INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)'
  ).run(playlistId, trackId, maxPos);
}

function addTracksToPlaylist(playlistId, trackIds) {
  if (!trackIds || trackIds.length === 0) return;
  const db = getDatabase();
  const nextPos = db.prepare(
    'SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?'
  ).get(playlistId).next_pos;

  const insertStmt = db.prepare(
    'INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)'
  );

  const transaction = db.transaction((ids) => {
    let pos = nextPos;
    for (const trackId of ids) {
      insertStmt.run(playlistId, trackId, pos);
      pos++;
    }
  });

  transaction(trackIds);
  db.prepare('UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(playlistId);
}

function setPlaylistTracks(playlistId, trackIds) {
  const db = getDatabase();
  const ids = trackIds || [];
  const transaction = db.transaction(() => {
    db.prepare('DELETE FROM playlist_tracks WHERE playlist_id = ?').run(playlistId);
    if (ids.length > 0) {
      const insertStmt = db.prepare(
        'INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)'
      );
      ids.forEach((trackId, idx) => {
        insertStmt.run(playlistId, trackId, idx);
      });
    }
  });
  transaction();
  db.prepare('UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(playlistId);
}

function getPlaylistTracks(playlistId) {
  const db = getDatabase();
  return db.prepare(`
    SELECT t.*, pt.position, pt.added_at as added_to_playlist_at
    FROM playlist_tracks pt
    JOIN tracks t ON pt.track_id = t.id
    WHERE pt.playlist_id = ?
    ORDER BY pt.position
  `).all(playlistId);
}

function removeTrackFromPlaylist(playlistId, trackId) {
  const db = getDatabase();
  return db.prepare(
    'DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?'
  ).run(playlistId, trackId);
}

function deletePlaylist(playlistId) {
  const db = getDatabase();
  return db.prepare('DELETE FROM playlists WHERE id = ?').run(playlistId);
}

function renamePlaylist(id, name) {
  const db = getDatabase();
  return db.prepare(
    'UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?'
  ).run(name, id);
}

// ── LRC (Lyrics) operations ──

function setTrackLrc(trackId, lrcPath) {
  const db = getDatabase();
  return db.prepare('UPDATE tracks SET lrc_path = ? WHERE id = ?').run(lrcPath, trackId);
}

function getTrackLrc(trackId) {
  const db = getDatabase();
  const row = db.prepare('SELECT lrc_path FROM tracks WHERE id = ?').get(trackId);
  return row ? row.lrc_path : null;
}

function clearTrackLrc(trackId) {
  const db = getDatabase();
  return db.prepare('UPDATE tracks SET lrc_path = NULL WHERE id = ?').run(trackId);
}

// ── Settings operations ──

function getSetting(key, defaultValue = null) {
  const db = getDatabase();
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key);
  return row ? row.value : defaultValue;
}

function setSetting(key, value) {
  const db = getDatabase();
  db.prepare(
    'INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value'
  ).run(key, String(value));
}

function resetDatabase() {
  const db = getDatabase();
  db.exec(`
    DELETE FROM playlist_tracks;
    DELETE FROM play_history;
    DELETE FROM playlists;
    DELETE FROM tracks;
    DELETE FROM settings;
  `);
}

module.exports = {
  initDatabase,
  getDatabase,
  closeDatabase,
  resetDatabase,
  insertTrack,
  getAllTracks,
  getTrackById,
  updateTrack,
  deleteTrack,
  getTrackCount,
  startPlaySession,
  endPlaySession,
  getPlayHistory,
  getListeningStats,
  createPlaylist,
  getAllPlaylists,
  addTrackToPlaylist,
  addTracksToPlaylist,
  setPlaylistTracks,
  getPlaylistTracks,
  removeTrackFromPlaylist,
  deletePlaylist,
  renamePlaylist,
  setTrackLrc,
  getTrackLrc,
  clearTrackLrc,
  getSetting,
  setSetting,
};
