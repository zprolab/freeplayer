import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import os from 'os';

let db;

function initTestDb() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'freeplayer-test-'));
  const dbPath = path.join(tmpDir, 'test.db');
  db = new Database(dbPath);
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
  `);

  return db;
}

function closeTestDb(database) {
  if (database) {
    const dbPath = database.name;
    database.close();
    try { fs.unlinkSync(dbPath); } catch {}
    try { fs.unlinkSync(dbPath + '-wal'); } catch {}
    try { fs.unlinkSync(dbPath + '-shm'); } catch {}
  }
}

describe('Tracks CRUD', () => {
  beforeEach(() => { db = initTestDb(); });
  afterEach(() => { closeTestDb(db); });

  it('inserts a track', () => {
    const stmt = db.prepare(`
      INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES (@title, @artist, @album, @duration, @file_path, @file_name)
    `);
    const result = stmt.run({
      title: 'Test Song', artist: 'Test Artist', album: 'Test Album',
      duration: 240, file_path: '/music/test.mp3', file_name: 'test.mp3',
    });
    expect(result.lastInsertRowid).toBeGreaterThan(0);
  });

  it('enforces UNIQUE constraint on file_path', () => {
    const stmt = db.prepare(`
      INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES (@title, @artist, @album, @duration, @file_path, @file_name)
    `);
    const params = {
      title: 'Song', artist: 'Artist', album: 'Album',
      duration: 100, file_path: '/music/dup.mp3', file_name: 'dup.mp3',
    };
    stmt.run(params);
    expect(() => stmt.run(params)).toThrow();
  });

  it('ON CONFLICT DO UPDATE replaces existing track', () => {
    const stmt = db.prepare(`
      INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES (@title, @artist, @album, @duration, @file_path, @file_name)
      ON CONFLICT(file_path) DO UPDATE SET
        title = excluded.title, artist = excluded.artist, album = excluded.album,
        duration = excluded.duration, updated_at = CURRENT_TIMESTAMP
    `);
    stmt.run({ title: 'V1', artist: 'A', album: 'B', duration: 100, file_path: '/m/s.mp3', file_name: 's.mp3' });
    stmt.run({ title: 'V2', artist: 'A', album: 'B', duration: 200, file_path: '/m/s.mp3', file_name: 's.mp3' });
    const row = db.prepare('SELECT title, duration FROM tracks WHERE file_path = ?').get('/m/s.mp3');
    expect(row.title).toBe('V2');
    expect(row.duration).toBe(200);
  });

  it('rejects invalid sort column via whitelist', () => {
    db.prepare(`INSERT INTO tracks (title, artist, album, duration, file_path, file_name, year)
      VALUES ('B', 'Y', 'Z', 100, '/m/1.mp3', '1.mp3', 2020)`).run();
    db.prepare(`INSERT INTO tracks (title, artist, album, duration, file_path, file_name, year)
      VALUES ('A', 'X', 'Y', 200, '/m/2.mp3', '2.mp3', 2021)`).run();

    const malicious = 'title; DROP TABLE tracks;--';
    const allowedSortColumns = ['title', 'artist', 'album', 'duration', 'imported_at', 'year'];
    let sortBy = malicious;
    if (!allowedSortColumns.includes(sortBy)) sortBy = 'imported_at';
    expect(sortBy).toBe('imported_at');

    const rows = db.prepare('SELECT title FROM tracks ORDER BY title ASC').all();
    expect(rows[0].title).toBe('A');
    expect(rows[1].title).toBe('B');
  });

  it('deletes track and cascades to play_history', () => {
    const t = db.prepare(`INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES ('T', 'A', 'B', 100, '/m/t.mp3', 't.mp3')`).run();
    const trackId = t.lastInsertRowid;
    db.prepare("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))").run(trackId);

    expect(db.prepare('SELECT COUNT(*) as c FROM play_history WHERE track_id = ?').get(trackId).c).toBe(1);

    db.prepare('DELETE FROM tracks WHERE id = ?').run(trackId);
    expect(db.prepare('SELECT COUNT(*) as c FROM play_history WHERE track_id = ?').get(trackId).c).toBe(0);
  });
});

describe('Playlist operations', () => {
  beforeEach(() => { db = initTestDb(); });
  afterEach(() => { closeTestDb(db); });

  it('creates a playlist', () => {
    const r = db.prepare("INSERT INTO playlists (name) VALUES ('My List')").run();
    expect(r.lastInsertRowid).toBeGreaterThan(0);
  });

  it('adds track with auto-increment position', () => {
    db.prepare("INSERT INTO tracks (title, file_path, file_name, duration) VALUES ('T', '/m/t.mp3', 't.mp3', 100)").run();
    db.prepare("INSERT INTO playlists (name) VALUES ('P')").run();

    const maxPos = db.prepare(
      "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?"
    ).get(1).next_pos;
    expect(maxPos).toBe(0);

    db.prepare("INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, ?)").run(maxPos);
    const pos2 = db.prepare(
      "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?"
    ).get(1).next_pos;
    expect(pos2).toBe(1);
  });

  it('prevents duplicate track in playlist', () => {
    db.prepare("INSERT INTO tracks (title, file_path, file_name, duration) VALUES ('T', '/m/t.mp3', 't.mp3', 100)").run();
    db.prepare("INSERT INTO playlists (name) VALUES ('P')").run();
    db.prepare("INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 0)").run();
    expect(() => {
      db.prepare("INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 1)").run();
    }).toThrow();
  });
});

describe('Settings operations', () => {
  beforeEach(() => { db = initTestDb(); });
  afterEach(() => { closeTestDb(db); });

  it('sets and gets a setting', () => {
    db.prepare("INSERT INTO settings (key, value) VALUES ('theme', 'dark')").run();
    const row = db.prepare("SELECT value FROM settings WHERE key = 'theme'").get();
    expect(row.value).toBe('dark');
  });

  it('upserts on conflict', () => {
    db.prepare("INSERT INTO settings (key, value) VALUES ('k', 'v1')").run();
    db.prepare("INSERT INTO settings (key, value) VALUES ('k', 'v2') ON CONFLICT(key) DO UPDATE SET value = excluded.value").run();
    const row = db.prepare("SELECT value FROM settings WHERE key = 'k'").get();
    expect(row.value).toBe('v2');
  });

  it('returns undefined for missing key', () => {
    const row = db.prepare("SELECT value FROM settings WHERE key = 'missing'").get();
    expect(row).toBeUndefined();
  });
});
