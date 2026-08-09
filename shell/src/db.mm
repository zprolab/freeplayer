// FreePlayer shell — SQLite layer (port of electron/database.js)
// Pure ObjC++: sqlite3 C API, results as NSDictionary/NSArray.

#import <Foundation/Foundation.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string>
#include "db.h"

namespace fpdb {

static sqlite3 *gDb = nullptr;
static NSString *gDbPath = nil;

// ── row helpers ──

static id colValue(sqlite3_stmt *stmt, int i) {
  switch (sqlite3_column_type(stmt, i)) {
    case SQLITE_INTEGER: return @(sqlite3_column_int64(stmt, i));
    case SQLITE_FLOAT:   return @(sqlite3_column_double(stmt, i));
    case SQLITE_TEXT: {
      const unsigned char *t = sqlite3_column_text(stmt, i);
      return t ? [NSString stringWithUTF8String:(const char *)t] : NSNull.null;
    }
    default: return NSNull.null;
  }
}

static NSDictionary *rowToDict(sqlite3_stmt *stmt) {
  int n = sqlite3_column_count(stmt);
  NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:n];
  for (int i = 0; i < n; i++) {
    NSString *key = [NSString stringWithUTF8String:sqlite3_column_name(stmt, i)];
    d[key] = colValue(stmt, i);
  }
  return d;
}

static NSArray *runQuery(NSString *sql, NSArray *params) {
  sqlite3_stmt *stmt = nullptr;
  if (sqlite3_prepare_v2(gDb, sql.UTF8String, -1, &stmt, nullptr) != SQLITE_OK) {
    NSLog(@"[db] prepare failed: %s | %@", sqlite3_errmsg(gDb), sql);
    return @[];
  }
  for (NSUInteger i = 0; i < params.count; i++) {
    id p = params[i];
    if ([p isKindOfClass:NSNumber.class]) {
      sqlite3_bind_double(stmt, (int)i + 1, [p doubleValue]);
    } else if (p == NSNull.null || p == nil) {
      sqlite3_bind_null(stmt, (int)i + 1);
    } else {
      NSString *s = [p description];
      sqlite3_bind_text(stmt, (int)i + 1, s.UTF8String, -1, SQLITE_TRANSIENT);
    }
  }
  NSMutableArray *rows = [NSMutableArray array];
  while (sqlite3_step(stmt) == SQLITE_ROW) {
    [rows addObject:rowToDict(stmt)];
  }
  sqlite3_finalize(stmt);
  return rows;
}

static BOOL runExec(NSString *sql, NSArray *params) {
  sqlite3_stmt *stmt = nullptr;
  if (sqlite3_prepare_v2(gDb, sql.UTF8String, -1, &stmt, nullptr) != SQLITE_OK) {
    NSLog(@"[db] exec prepare failed: %s", sqlite3_errmsg(gDb));
    return NO;
  }
  for (NSUInteger i = 0; i < params.count; i++) {
    id p = params[i];
    if ([p isKindOfClass:NSNumber.class]) {
      sqlite3_bind_double(stmt, (int)i + 1, [p doubleValue]);
    } else if (p == NSNull.null || p == nil) {
      sqlite3_bind_null(stmt, (int)i + 1);
    } else {
      NSString *s = [p description];
      sqlite3_bind_text(stmt, (int)i + 1, s.UTF8String, -1, SQLITE_TRANSIENT);
    }
  }
  BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
  sqlite3_finalize(stmt);
  return ok;
}

// ── lifecycle ──

NSString *defaultDbPath() {
  NSString *env = NSProcessInfo.processInfo.environment[@"FP_DB"];
  if (env.length > 0) return env;
  NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
  return [support stringByAppendingPathComponent:@"freeplayer/freeplayer.db"];
}

BOOL open(NSString *path) {
  gDbPath = path;
  // sqlite3 creates the file but not its parent directory
  [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                          withIntermediateDirectories:YES attributes:nil error:nil];
  if (sqlite3_open_v2(path.UTF8String, &gDb,
                      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                      nullptr) != SQLITE_OK) {
    NSLog(@"[db] open failed: %s", sqlite3_errmsg(gDb));
    return NO;
  }
  sqlite3_exec(gDb, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;", nullptr, nullptr, nullptr);
  const char *schema =
    "CREATE TABLE IF NOT EXISTS tracks ("
    " id INTEGER PRIMARY KEY AUTOINCREMENT,"
    " title TEXT NOT NULL, artist TEXT DEFAULT 'Unknown Artist',"
    " album TEXT DEFAULT 'Unknown Album', track_number INTEGER, disc_number INTEGER,"
    " genre TEXT, year INTEGER, duration REAL NOT NULL DEFAULT 0,"
    " file_path TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL, file_size INTEGER DEFAULT 0,"
    " file_format TEXT, bitrate INTEGER, sample_rate INTEGER, channels INTEGER,"
    " cover_path TEXT, replaygain_gain REAL DEFAULT 0, replaygain_peak REAL DEFAULT 0,"
    " imported_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);"
    "CREATE TABLE IF NOT EXISTS play_history ("
    " id INTEGER PRIMARY KEY AUTOINCREMENT, track_id INTEGER NOT NULL,"
    " started_at DATETIME NOT NULL, ended_at DATETIME,"
    " duration_seconds REAL DEFAULT 0, play_percentage REAL DEFAULT 0,"
    " FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE);"
    "CREATE TABLE IF NOT EXISTS playlists ("
    " id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT,"
    " created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);"
    "CREATE TABLE IF NOT EXISTS playlist_tracks ("
    " id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL, track_id INTEGER NOT NULL,"
    " position INTEGER NOT NULL DEFAULT 0, added_at DATETIME DEFAULT CURRENT_TIMESTAMP,"
    " FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,"
    " FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE,"
    " UNIQUE(playlist_id, track_id));"
    "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);"
    "CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);"
    "CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);"
    "CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album);"
    "CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id);"
    "CREATE INDEX IF NOT EXISTS idx_play_history_started ON play_history(started_at);"
    "CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist ON playlist_tracks(playlist_id);";
  sqlite3_exec(gDb, schema, nullptr, nullptr, nullptr);
  // Migrations (ignore failures — column already exists)
  sqlite3_exec(gDb, "ALTER TABLE tracks ADD COLUMN replaygain_gain REAL DEFAULT 0", nullptr, nullptr, nullptr);
  sqlite3_exec(gDb, "ALTER TABLE tracks ADD COLUMN replaygain_peak REAL DEFAULT 0", nullptr, nullptr, nullptr);
  sqlite3_exec(gDb, "ALTER TABLE tracks ADD COLUMN lrc_path TEXT", nullptr, nullptr, nullptr);
  NSLog(@"[db] open ok: %@", path);
  return YES;
}

void close() {
  if (gDb) { sqlite3_close(gDb); gDb = nullptr; }
}

// ── settings ──

id getSetting(NSString *key, id def) {
  NSArray *rows = runQuery(@"SELECT value FROM settings WHERE key = ?", @[ key ]);
  return rows.count ? rows[0][@"value"] : def;
}

BOOL setSetting(NSString *key, NSString *value) {
  return runExec(@"INSERT INTO settings (key, value) VALUES (?, ?)"
                 @" ON CONFLICT(key) DO UPDATE SET value = excluded.value", @[ key, value ?: @"" ]);
}

// ── tracks ──

NSArray *getAllTracks(NSString *search, NSString *sortBy, NSString *sortDir) {
  NSArray *allowed = @[ @"title", @"artist", @"album", @"duration", @"imported_at", @"year" ];
  if (![allowed containsObject:sortBy]) sortBy = @"imported_at";
  if (![sortDir isEqualToString:@"ASC"]) sortDir = @"DESC";
  NSString *sql = @"SELECT * FROM tracks";
  NSMutableArray *params = [NSMutableArray array];
  if (search.length > 0) {
    sql = [sql stringByAppendingString:@" WHERE title LIKE ? OR artist LIKE ? OR album LIKE ?"];
    NSString *term = [NSString stringWithFormat:@"%%%@%%", search];
    [params addObject:term]; [params addObject:term]; [params addObject:term];
  }
  sql = [sql stringByAppendingFormat:@" ORDER BY %@ %@", sortBy, sortDir];
  return runQuery(sql, params);
}

id getTrackById(int64_t id) {
  NSArray *rows = runQuery(@"SELECT * FROM tracks WHERE id = ?", @[ @(id) ]);
  return rows.count ? rows[0] : NSNull.null;
}

BOOL insertTrack(NSDictionary *t) {
  return runExec(
    @"INSERT INTO tracks (title, artist, album, track_number, disc_number, genre, year,"
    @" duration, file_path, file_name, file_size, file_format, bitrate, sample_rate,"
    @" channels, cover_path, replaygain_gain, replaygain_peak)"
    @" VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    @" ON CONFLICT(file_path) DO UPDATE SET"
    @" title = excluded.title, artist = excluded.artist, album = excluded.album,"
    @" track_number = excluded.track_number, disc_number = excluded.disc_number,"
    @" genre = excluded.genre, year = excluded.year, duration = excluded.duration,"
    @" file_name = excluded.file_name, file_size = excluded.file_size,"
    @" file_format = excluded.file_format, bitrate = excluded.bitrate,"
    @" sample_rate = excluded.sample_rate, channels = excluded.channels,"
    @" cover_path = excluded.cover_path,"
    @" replaygain_gain = excluded.replaygain_gain, replaygain_peak = excluded.replaygain_peak,"
    @" updated_at = CURRENT_TIMESTAMP",
    @[
      t[@"title"] ?: @"", t[@"artist"] ?: @"Unknown Artist", t[@"album"] ?: @"Unknown Album",
      t[@"track_number"] ?: NSNull.null, t[@"disc_number"] ?: NSNull.null,
      t[@"genre"] ?: NSNull.null, t[@"year"] ?: NSNull.null,
      t[@"duration"] ?: @0, t[@"file_path"] ?: @"", t[@"file_name"] ?: @"",
      t[@"file_size"] ?: @0, t[@"file_format"] ?: NSNull.null,
      t[@"bitrate"] ?: NSNull.null, t[@"sample_rate"] ?: NSNull.null,
      t[@"channels"] ?: NSNull.null, t[@"cover_path"] ?: NSNull.null,
      t[@"replaygain_gain"] ?: @0, t[@"replaygain_peak"] ?: @0,
    ]);
}

BOOL updateTrack(int64_t id, NSDictionary *fields) {
  NSArray *allowed = @[ @"title", @"artist", @"album", @"genre", @"year", @"track_number" ];
  NSMutableArray *sets = [NSMutableArray array];
  NSMutableArray *params = [NSMutableArray array];
  for (NSString *key in allowed) {
    if (fields[key] != nil) {
      [sets addObject:[NSString stringWithFormat:@"%@ = ?", key]];
      [params addObject:fields[key]];
    }
  }
  if (sets.count == 0) return YES;
  [params addObject:@(id)];
  NSString *sql = [NSString stringWithFormat:@"UPDATE tracks SET %@, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                   [sets componentsJoinedByString:@", "]];
  return runExec(sql, params);
}

BOOL deleteTrack(int64_t id) {
  return runExec(@"DELETE FROM tracks WHERE id = ?", @[ @(id) ]);
}

int64_t getTrackCount() {
  NSArray *rows = runQuery(@"SELECT COUNT(*) as count FROM tracks", @[]);
  return rows.count ? [rows[0][@"count"] longLongValue] : 0;
}

double getTotalDuration() {
  NSArray *rows = runQuery(@"SELECT COALESCE(SUM(duration), 0) as total FROM tracks", @[]);
  return rows.count ? [rows[0][@"total"] doubleValue] : 0;
}

// ── play history ──

int64_t startPlaySession(int64_t trackId) {
  NSArray *rows = runQuery(@"INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now')) RETURNING id", @[ @(trackId) ]);
  if (rows.count) return [rows[0][@"id"] longLongValue];
  sqlite3_stmt *stmt = nullptr;
  sqlite3_prepare_v2(gDb, "INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))", -1, &stmt, nullptr);
  sqlite3_bind_int64(stmt, 1, trackId);
  sqlite3_step(stmt);
  int64_t rid = (int64_t)sqlite3_last_insert_rowid(gDb);
  sqlite3_finalize(stmt);
  return rid;
}

BOOL endPlaySession(int64_t sessionId, double durationSeconds, double playPercentage) {
  return runExec(@"UPDATE play_history SET ended_at = datetime('now'), duration_seconds = ?, play_percentage = ? WHERE id = ?",
                 @[ @(durationSeconds), @(playPercentage), @(sessionId) ]);
}

NSArray *getPlayHistory(int limit) {
  return runQuery(@"SELECT ph.*, t.title, t.artist, t.album, t.file_path, t.duration as track_duration"
                  @" FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
                  @" ORDER BY ph.started_at DESC LIMIT ?", @[ @(limit) ]);
}

NSDictionary *getListeningStats() {
  NSArray *t = runQuery(@"SELECT COALESCE(SUM(duration_seconds), 0) as total FROM play_history WHERE ended_at IS NOT NULL", @[]);
  NSArray *c = runQuery(@"SELECT COUNT(*) as count FROM play_history", @[]);
  NSArray *u = runQuery(@"SELECT COUNT(DISTINCT track_id) as count FROM play_history", @[]);
  NSArray *topTracks = runQuery(
    @"SELECT t.id, t.title, t.artist, t.album, t.duration as track_duration,"
    @" COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time"
    @" FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
    @" GROUP BY t.id ORDER BY play_count DESC LIMIT 10", @[]);
  NSArray *topArtists = runQuery(
    @"SELECT t.artist, COUNT(ph.id) as play_count, COALESCE(SUM(ph.duration_seconds), 0) as total_listen_time"
    @" FROM play_history ph JOIN tracks t ON ph.track_id = t.id"
    @" GROUP BY t.artist ORDER BY play_count DESC LIMIT 10", @[]);
  NSArray *dailyStats = runQuery(
    @"SELECT DATE(started_at) as date, COUNT(*) as plays, COALESCE(SUM(duration_seconds), 0) as total_time"
    @" FROM play_history WHERE started_at >= datetime('now', '-30 days')"
    @" GROUP BY DATE(started_at) ORDER BY date DESC", @[]);
  return @{
    @"totalTime": t.count ? t[0][@"total"] : @0,
    @"totalPlays": c.count ? c[0][@"count"] : @0,
    @"uniqueTracksPlayed": u.count ? u[0][@"count"] : @0,
    @"topTracks": topTracks,
    @"topArtists": topArtists,
    @"dailyStats": dailyStats,
  };
}

// ── playlists ──

int64_t createPlaylist(NSString *name, NSString *description) {
  sqlite3_stmt *stmt = nullptr;
  sqlite3_prepare_v2(gDb, "INSERT INTO playlists (name, description) VALUES (?, ?)", -1, &stmt, nullptr);
  sqlite3_bind_text(stmt, 1, name.UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_bind_text(stmt, 2, (description ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
  sqlite3_step(stmt);
  int64_t rid = (int64_t)sqlite3_last_insert_rowid(gDb);
  sqlite3_finalize(stmt);
  return rid;
}

NSArray *getAllPlaylists() {
  return runQuery(@"SELECT * FROM playlists ORDER BY updated_at DESC", @[]);
}

BOOL addTrackToPlaylist(int64_t playlistId, int64_t trackId) {
  NSArray *rows = runQuery(@"SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?", @[ @(playlistId) ]);
  int64_t pos = rows.count ? [rows[0][@"next_pos"] longLongValue] : 0;
  return runExec(@"INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)",
                 @[ @(playlistId), @(trackId), @(pos) ]);
}

BOOL addTracksToPlaylist(int64_t playlistId, NSArray *trackIds) {
  if (trackIds.count == 0) return YES;
  NSArray *rows = runQuery(@"SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?", @[ @(playlistId) ]);
  int64_t pos = rows.count ? [rows[0][@"next_pos"] longLongValue] : 0;
  sqlite3_stmt *stmt = nullptr;
  sqlite3_prepare_v2(gDb, "INSERT OR IGNORE INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", -1, &stmt, nullptr);
  for (id tid in trackIds) {
    sqlite3_bind_int64(stmt, 1, playlistId);
    sqlite3_bind_int64(stmt, 2, [tid longLongValue]);
    sqlite3_bind_int64(stmt, 3, pos++);
    sqlite3_step(stmt);
    sqlite3_reset(stmt);
  }
  sqlite3_finalize(stmt);
  return runExec(@"UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", @[ @(playlistId) ]);
}

BOOL setPlaylistTracks(int64_t playlistId, NSArray *trackIds) {
  if (!runExec(@"DELETE FROM playlist_tracks WHERE playlist_id = ?", @[ @(playlistId) ])) return NO;
  sqlite3_stmt *stmt = nullptr;
  sqlite3_prepare_v2(gDb, "INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (?, ?, ?)", -1, &stmt, nullptr);
  int64_t pos = 0;
  for (id tid in trackIds) {
    sqlite3_bind_int64(stmt, 1, playlistId);
    sqlite3_bind_int64(stmt, 2, [tid longLongValue]);
    sqlite3_bind_int64(stmt, 3, pos++);
    sqlite3_step(stmt);
    sqlite3_reset(stmt);
  }
  sqlite3_finalize(stmt);
  return runExec(@"UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", @[ @(playlistId) ]);
}

NSArray *getPlaylistTracks(int64_t playlistId) {
  return runQuery(@"SELECT t.*, pt.position, pt.added_at as added_to_playlist_at"
                  @" FROM playlist_tracks pt JOIN tracks t ON pt.track_id = t.id"
                  @" WHERE pt.playlist_id = ? ORDER BY pt.position", @[ @(playlistId) ]);
}

BOOL removeTrackFromPlaylist(int64_t playlistId, int64_t trackId) {
  return runExec(@"DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?", @[ @(playlistId), @(trackId) ]);
}

BOOL deletePlaylist(int64_t playlistId) {
  return runExec(@"DELETE FROM playlists WHERE id = ?", @[ @(playlistId) ]);
}

BOOL renamePlaylist(int64_t playlistId, NSString *name) {
  return runExec(@"UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?", @[ name, @(playlistId) ]);
}

// ── LRC ──

BOOL setTrackLrc(int64_t trackId, NSString *lrcPath) {
  return runExec(@"UPDATE tracks SET lrc_path = ? WHERE id = ?", @[ lrcPath ?: NSNull.null, @(trackId) ]);
}

BOOL setTrackCover(int64_t trackId, NSString *coverPath) {
  return runExec(@"UPDATE tracks SET cover_path = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                 @[ coverPath, @(trackId) ]);
}

id getTrackLrc(int64_t trackId) {
  NSArray *rows = runQuery(@"SELECT lrc_path FROM tracks WHERE id = ?", @[ @(trackId) ]);
  return (rows.count && rows[0][@"lrc_path"] != NSNull.null) ? rows[0][@"lrc_path"] : nil;
}

BOOL clearTrackLrc(int64_t trackId) {
  return runExec(@"UPDATE tracks SET lrc_path = NULL WHERE id = ?", @[ @(trackId) ]);
}

BOOL resetDatabase() {
  // sqlite3_exec runs ALL statements; runExec only compiles the first
  char *err = nullptr;
  int rc = sqlite3_exec(gDb,
    "DELETE FROM playlist_tracks; DELETE FROM play_history; DELETE FROM playlists;"
    " DELETE FROM tracks; DELETE FROM settings;",
    nullptr, nullptr, &err);
  if (err) sqlite3_free(err);
  return rc == SQLITE_OK;
}

} // namespace fpdb
