// FreePlayer shell — sqlite layer declarations
#pragma once
#import <Foundation/Foundation.h>

namespace fpdb {
NSString *defaultDbPath();
BOOL open(NSString *path);
void close();

id getSetting(NSString *key, id def);
BOOL setSetting(NSString *key, NSString *value);

// ── imported symlinks (S3e: trust anchor for library symlinks) ──
// The symlink import mode creates links inside the library that point
// outside it by design. Their targets are recorded here at import time so
// the containment check can tell them apart from renderer-planted links.
BOOL recordSymlink(NSString *libPath, NSString *resolvedTarget);
NSString *symlinkTarget(NSString *libPath);

NSArray *getAllTracks(NSString *search, NSString *sortBy, NSString *sortDir);
id getTrackById(int64_t id);
BOOL insertTrack(NSDictionary *t);
BOOL updateTrack(int64_t id, NSDictionary *fields);
BOOL deleteTrack(int64_t id);
int64_t getTrackCount();
double getTotalDuration();

int64_t startPlaySession(int64_t trackId);
BOOL endPlaySession(int64_t sessionId, double durationSeconds, double playPercentage);
NSArray *getPlayHistory(int limit);
NSDictionary *getListeningStats();

int64_t createPlaylist(NSString *name, NSString *description);
NSArray *getAllPlaylists();
BOOL addTrackToPlaylist(int64_t playlistId, int64_t trackId);
BOOL addTracksToPlaylist(int64_t playlistId, NSArray *trackIds);
BOOL setPlaylistTracks(int64_t playlistId, NSArray *trackIds);
NSArray *getPlaylistTracks(int64_t playlistId);
BOOL removeTrackFromPlaylist(int64_t playlistId, int64_t trackId);
BOOL deletePlaylist(int64_t playlistId);
BOOL renamePlaylist(int64_t playlistId, NSString *name);

BOOL setTrackLrc(int64_t trackId, NSString *lrcPath);
BOOL setTrackCover(int64_t trackId, NSString *coverPath);
id getTrackLrc(int64_t trackId);
BOOL clearTrackLrc(int64_t trackId);

// ── transactions (batch writes: import, EQ save) ──
bool beginTransaction();
bool commitTransaction();
bool rollbackTransaction();

BOOL resetDatabase();
} // namespace fpdb
