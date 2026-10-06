// FreePlayer — XCTest unit tests for the SQLite Database layer.

import XCTest
@testable import FreePlayer

final class DatabaseTests: XCTestCase {

    private var tempDbPath: String!
    private var tempLibDir: String!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp_test_\(UUID().uuidString)")
        tempDbPath = tmp.appendingPathComponent("config.db").path
        tempLibDir = tmp.appendingPathComponent("library").path
        try? FileManager.default.createDirectory(atPath: tempLibDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Database.close()
        if let parent = (tempDbPath as NSString).deletingLastPathComponent as String? {
            try? FileManager.default.removeItem(atPath: parent)
        }
        super.tearDown()
    }

    private func openTracksDb() {
        Database.open(tempDbPath)
        Database.setSetting("library_dir", tempLibDir)
        Database.openTracksDb(tempLibDir + "/tracks.db")
    }

    private func insertTrack(_ title: String, _ path: String, _ duration: Double = 100) {
        Database.insertTrack([
            "title": title, "artist": "Artist", "album": "Album",
            "duration": duration, "file_path": path,
            "file_name": (path as NSString).lastPathComponent,
            "file_format": (path as NSString).pathExtension,
        ])
    }

    // MARK: - Open / Close

    func testOpenAndClose() {
        XCTAssertTrue(Database.open(tempDbPath))
        XCTAssertTrue(Database.isOpen)
        Database.close()
        XCTAssertFalse(Database.isOpen)
    }

    func testCloseWithoutOpenDoesNotCrash() {
        Database.close()
    }

    // MARK: - Settings

    func testSetAndGetSetting() {
        Database.open(tempDbPath)
        Database.setSetting("theme", "dark")
        XCTAssertEqual(Database.getSetting("theme", nil), "dark")
    }

    func testOverwriteSetting() {
        Database.open(tempDbPath)
        Database.setSetting("key", "old")
        Database.setSetting("key", "new")
        XCTAssertEqual(Database.getSetting("key", nil), "new")
    }

    func testDeleteSettingViaNil() {
        Database.open(tempDbPath)
        Database.setSetting("to_delete", "value")
        Database.setSetting("to_delete", nil)
        XCTAssertNil(Database.getSetting("to_delete", nil))
    }

    func testGetSettingReturnsDefault() {
        Database.open(tempDbPath)
        XCTAssertEqual(Database.getSetting("missing", "fallback"), "fallback")
    }

    func testUnicodeSetting() {
        Database.open(tempDbPath)
        Database.setSetting("jp", "日本語テスト")
        Database.setSetting("cn", "中文测试")
        XCTAssertEqual(Database.getSetting("jp", nil), "日本語テスト")
        XCTAssertEqual(Database.getSetting("cn", nil), "中文测试")
    }

    // MARK: - Tracks DB

    func testTracksDbOpen() {
        openTracksDb()
        XCTAssertNotNil(Database.tracksDbPath())
        Database.close()
    }

    func testTransactionCommit() {
        openTracksDb()
        XCTAssertTrue(Database.beginTransaction())
        XCTAssertTrue(Database.commitTransaction())
        Database.close()
    }

    func testTransactionRollback() {
        openTracksDb()
        XCTAssertTrue(Database.beginTransaction())
        XCTAssertTrue(Database.rollbackTransaction())
        Database.close()
    }

    // MARK: - Track CRUD

    func testInsertAndGetTrack() {
        openTracksDb()
        insertTrack("Test Song", "/tmp/test.mp3")
        XCTAssertEqual(Database.getTrackCount(), 1)
        let tracks = Database.getAllTracks("", "title", "ASC")
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?["title"] as? String, "Test Song")
        Database.close()
    }

    func testInsertMultipleTracks() {
        openTracksDb()
        insertTrack("Song A", "/tmp/a.mp3")
        insertTrack("Song B", "/tmp/b.mp3")
        insertTrack("Song C", "/tmp/c.mp3")
        XCTAssertEqual(Database.getTrackCount(), 3)
        Database.close()
    }

    func testDeleteTrack() {
        openTracksDb()
        insertTrack("Delete Me", "/tmp/delete.mp3")
        XCTAssertEqual(Database.getTrackCount(), 1)
        let tracks = Database.getAllTracks("", "imported_at", "ASC")
        if let trackId = tracks.first?["id"] as? Int64 {
            Database.deleteTrack(trackId)
        }
        XCTAssertEqual(Database.getTrackCount(), 0)
        Database.close()
    }

    func testGetTrackById() {
        openTracksDb()
        insertTrack("Findable", "/tmp/find.mp3")
        let tracks = Database.getAllTracks("", "imported_at", "ASC")
        guard let trackId = tracks.first?["id"] as? Int64 else {
            XCTFail("Track not found"); return
        }
        let found = Database.getTrackById(trackId) as? [String: Any]
        XCTAssertNotNil(found)
        XCTAssertEqual(found?["title"] as? String, "Findable")
        Database.close()
    }

    func testSearchTracks() {
        openTracksDb()
        insertTrack("Hello World", "/tmp/1.mp3")
        insertTrack("Goodbye World", "/tmp/2.mp3")
        insertTrack("Hello Again", "/tmp/3.mp3")
        let results = Database.getAllTracks("Hello", "title", "ASC")
        XCTAssertEqual(results.count, 2)
        Database.close()
    }

    func testSortTracks() {
        openTracksDb()
        insertTrack("Zebra", "/tmp/1.mp3")
        insertTrack("Apple", "/tmp/2.mp3")
        insertTrack("Mango", "/tmp/3.mp3")
        let asc = Database.getAllTracks("", "title", "ASC")
        XCTAssertEqual(asc.first?["title"] as? String, "Apple")
        XCTAssertEqual(asc.last?["title"] as? String, "Zebra")
        let desc = Database.getAllTracks("", "title", "DESC")
        XCTAssertEqual(desc.first?["title"] as? String, "Zebra")
        XCTAssertEqual(desc.last?["title"] as? String, "Apple")
        Database.close()
    }

    // MARK: - Stats

    func testGetTotalDuration() {
        openTracksDb()
        insertTrack("A", "/tmp/1.mp3", 120)
        insertTrack("B", "/tmp/2.mp3", 180)
        let total = Database.getTotalDuration()
        XCTAssertEqual(total, 300.0, accuracy: 0.1)
        Database.close()
    }

    func testGetStats() {
        openTracksDb()
        insertTrack("A", "/tmp/1.mp3")
        insertTrack("B", "/tmp/2.mp3")
        let stats = Database.getStats()
        let count = (stats["totalTracks"] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(count, 2)
        Database.close()
    }

    // MARK: - Play History

    func testPlayStartAndEnd() {
        openTracksDb()
        insertTrack("Play Test", "/tmp/play.mp3")
        let tracks = Database.getAllTracks("", "imported_at", "ASC")
        guard let trackId = tracks.first?["id"] as? Int64 else {
            XCTFail("Track not found"); return
        }
        Database.playStart(trackId)
        let history = Database.getPlayHistory(10)
        XCTAssertEqual(history.count, 1)
        Database.close()
    }

    // MARK: - Playlists

    func testCreatePlaylist() {
        openTracksDb()
        Database.createPlaylist("My Playlist", "A test playlist")
        let playlists = Database.getPlaylists()
        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?["name"] as? String, "My Playlist")
        Database.close()
    }

    func testDeletePlaylist() {
        openTracksDb()
        Database.createPlaylist("To Delete", nil)
        XCTAssertEqual(Database.getPlaylists().count, 1)
        let playlists = Database.getPlaylists()
        if let plId = playlists.first?["id"] as? Int64 {
            Database.deletePlaylist(plId)
        }
        XCTAssertEqual(Database.getPlaylists().count, 0)
        Database.close()
    }

    func testRenamePlaylist() {
        openTracksDb()
        Database.createPlaylist("Old Name", nil)
        let playlists = Database.getPlaylists()
        if let plId = playlists.first?["id"] as? Int64 {
            Database.renamePlaylist(plId, "New Name")
        }
        XCTAssertEqual(Database.getPlaylists().first?["name"] as? String, "New Name")
        Database.close()
    }

    // MARK: - LRC

    func testSetAndGetTrackLrc() {
        openTracksDb()
        insertTrack("LRC Test", "/tmp/lrc.mp3")
        let tracks = Database.getAllTracks("", "imported_at", "ASC")
        guard let trackId = tracks.first?["id"] as? Int64 else { return }
        Database.setTrackLrc(trackId, "/tmp/song.lrc")
        XCTAssertEqual(Database.getTrackLrc(trackId), "/tmp/song.lrc")
        Database.clearTrackLrc(trackId)
        XCTAssertNil(Database.getTrackLrc(trackId))
        Database.close()
    }

    // MARK: - Symlink

    func testRecordAndLookupSymlink() {
        Database.open(tempDbPath)
        Database.recordSymlink("/lib/link.mp3", "/real/source.mp3")
        XCTAssertEqual(Database.symlinkTarget("/lib/link.mp3"), "/real/source.mp3")
        XCTAssertNil(Database.symlinkTarget("/lib/nonexistent.mp3"))
        Database.close()
    }

    // MARK: - updateTrack allowlist (SQL-injection guard)

    func testUpdateTrackIgnoresNonWhitelistedAndInjectedKeys() {
        openTracksDb()
        insertTrack("Original", "/lib/original.mp3")
        guard let trackId = Database.getAllTracks("", "imported_at", "ASC").first?["id"] as? Int64 else {
            XCTFail("track insert failed"); Database.close(); return
        }
        // A whitelisted column updates; an un-whitelisted column and a key that
        // is a SQL fragment must be ignored rather than interpolated.
        Database.updateTrack(trackId, [
            "title": "Renamed",
            "file_path": "/lib/evil.mp3",
            "title = (SELECT file_path FROM tracks)": "x",
        ])
        let track = Database.getTrackById(trackId) as? [String: Any]
        XCTAssertEqual(track?["title"] as? String, "Renamed")
        XCTAssertEqual(track?["file_path"] as? String, "/lib/original.mp3")
        Database.close()
    }

    // MARK: - playlist append position

    func testAddTracksToPlaylistAppendsAfterTail() {
        openTracksDb()
        insertTrack("First", "/lib/1.mp3")
        insertTrack("Second", "/lib/2.mp3")
        let tracks = Database.getAllTracks("", "imported_at", "ASC")
        guard let p1 = tracks.first?["id"] as? Int64,
              let p2 = tracks.last?["id"] as? Int64 else {
            XCTFail("track inserts failed"); Database.close(); return
        }
        Database.createPlaylist("List", nil)
        guard let plId = Database.getPlaylists().first?["id"] as? Int64 else {
            XCTFail("playlist create failed"); Database.close(); return
        }
        Database.addTrackToPlaylist(plId, p1)
        // Pre-fix this hardcoded position 0 and collided with p1's slot.
        Database.addTracksToPlaylist(plId, [NSNumber(value: p2)])
        let rows = Database.getPlaylistTracks(plId)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?["id"] as? Int64, p1)
        let positions = rows.compactMap { ($0["position"] as? NSNumber)?.int64Value }
        XCTAssertEqual(positions, [0, 1])
        Database.close()
    }

    // MARK: - provenance (file baseline bookkeeping)

    private func trackRow(_ id: Int64) -> [String: Any]? {
        Database.getTrackById(id) as? [String: Any]
    }

    func testTrackSourcesAreRecordedAndCleared() {
        openTracksDb()
        Database.insertTrack([
            "title": "Song", "artist": "Artist", "album": "Album", "duration": 100,
            "file_path": "/lib/song.mp3", "file_name": "song.mp3", "file_format": "mp3",
            "cover_path": "/lib/.covers/cover.jpg", "cover_source": "file",
            "meta_source": "file",
        ])
        guard let id = Database.getTrackIdByPath("/lib/song.mp3") else {
            XCTFail("insert did not land"); Database.close(); return
        }
        XCTAssertEqual(trackRow(id)?["meta_source"] as? String, "file")
        XCTAssertEqual(trackRow(id)?["cover_source"] as? String, "file")

        // An online backend's cover/lyrics rewrite the reference AND record
        // where the new value came from.
        _ = Database.setTrackCover(id, "/lib/.covers/cover-\(id).jpg", source: "plugin")
        _ = Database.setTrackLrc(id, "/lib/song.\(id).lrc", source: "plugin")
        XCTAssertEqual(trackRow(id)?["cover_source"] as? String, "plugin")
        XCTAssertEqual(Database.getTrackLyricsSource(id), "plugin")

        // Clearing the value clears its provenance with it — there is nothing
        // left for a source to describe.
        _ = Database.setTrackCover(id, nil)
        _ = Database.setTrackLrc(id, nil)
        XCTAssertNil(trackRow(id)?["cover_source"] as? String)
        XCTAssertNil(Database.getTrackLyricsSource(id))
        XCTAssertNil(Database.getTrackLrc(id))
        Database.close()
    }

    func testUpdateTrackStampsProvenance() {
        openTracksDb()
        insertTrack("Original", "/lib/song.mp3")
        guard let id = Database.getTrackIdByPath("/lib/song.mp3") else {
            XCTFail("track insert failed"); Database.close(); return
        }
        // The online fill-in carries its stamp through the same allowlisted call.
        Database.updateTrack(id, ["title": "Fetched", "meta_source": "plugin"])
        XCTAssertEqual(trackRow(id)?["title"] as? String, "Fetched")
        XCTAssertEqual(trackRow(id)?["meta_source"] as? String, "plugin")
        // A manual edit stamps itself, and a file baseline can be restored.
        Database.updateTrack(id, ["title": "Hand Edited", "meta_source": "user"])
        XCTAssertEqual(trackRow(id)?["meta_source"] as? String, "user")
        Database.setTrackMetaSource(id, "file")
        XCTAssertEqual(trackRow(id)?["meta_source"] as? String, "file")
        Database.close()
    }

    func testReimportKeepsAnOnlineCoverButPrefersEmbeddedArtwork() {
        openTracksDb()
        insertTrack("Song", "/lib/song.mp3")
        guard let id = Database.getTrackIdByPath("/lib/song.mp3") else {
            XCTFail("track insert failed"); Database.close(); return
        }
        _ = Database.setTrackCover(id, "/lib/.covers/cover-\(id).jpg", source: "plugin")

        // Re-import of a file without artwork: the baseline has nothing to say
        // about the cover, so the online one survives (pre-fix: NULL).
        insertTrackWithCover(id: id, coverPath: NSNull(), coverSource: NSNull())
        XCTAssertEqual(trackRow(id)?["cover_path"] as? String, "/lib/.covers/cover-\(id).jpg")
        XCTAssertEqual(trackRow(id)?["cover_source"] as? String, "plugin")

        // Re-import of a file that does embed artwork: the file wins.
        insertTrackWithCover(id: id, coverPath: "/lib/.covers/cover.jpg", coverSource: "file")
        XCTAssertEqual(trackRow(id)?["cover_path"] as? String, "/lib/.covers/cover.jpg")
        XCTAssertEqual(trackRow(id)?["cover_source"] as? String, "file")
        Database.close()
    }

    private func insertTrackWithCover(id: Int64, coverPath: Any, coverSource: Any) {
        Database.insertTrack([
            "title": "Song", "artist": "Artist", "album": "Album", "duration": 100,
            "file_path": "/lib/song.mp3", "file_name": "song.mp3", "file_format": "mp3",
            "cover_path": coverPath, "cover_source": coverSource, "meta_source": "file",
        ])
    }
}
