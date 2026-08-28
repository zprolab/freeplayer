// FreePlayer — XCTest unit tests for the FULL ImportPipeline.runImport flow
// (extract → copy → batched insert). The existing ImportPipelineTests only
// cover scanAudioFiles; runImport was untested until the "app crashes on
// import" report, so this reproduces the whole path headlessly.

import XCTest
import SQLite3
@testable import FreePlayer

/// Simulates the real post-split situation: the config DB still carries the
/// pre-split single-DB tables with rows while the tracks DB is fresh/empty.
/// migrateToSplitDb must copy the four tracks-related tables over, be
/// idempotent, and leave AUTOINCREMENT sequences above the migrated ids.
final class MigrationTests: XCTestCase {

    func testMigrateToSplitDbCopiesLegacyData() throws {
        let tmp = NSTemporaryDirectory() + "fp_migrate_\(UUID().uuidString)"
        let configDb = tmp + "/config.db"
        let libDir = tmp + "/library"
        try FileManager.default.createDirectory(atPath: libDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // 1. Legacy single-DB layout: all tables in one file, with rows.
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(configDb, &raw, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        let legacySchema = """
        CREATE TABLE tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, artist TEXT DEFAULT 'Unknown Artist', album TEXT DEFAULT 'Unknown Album', track_number INTEGER, disc_number INTEGER, genre TEXT, year INTEGER, duration REAL NOT NULL DEFAULT 0, file_path TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL, file_size INTEGER DEFAULT 0, file_format TEXT, bitrate INTEGER, sample_rate INTEGER, channels INTEGER, cover_path TEXT, replaygain_gain REAL DEFAULT 0, replaygain_peak REAL DEFAULT 0, imported_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, lrc_path TEXT);
        CREATE TABLE play_history (id INTEGER PRIMARY KEY AUTOINCREMENT, track_id INTEGER NOT NULL, started_at DATETIME NOT NULL, ended_at DATETIME, duration_seconds REAL DEFAULT 0, play_percentage REAL DEFAULT 0);
        CREATE TABLE playlists (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
        CREATE TABLE playlist_tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id INTEGER NOT NULL, track_id INTEGER NOT NULL, position INTEGER NOT NULL DEFAULT 0, added_at DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE(playlist_id, track_id));
        """
        XCTAssertEqual(sqlite3_exec(raw, legacySchema, nil, nil, nil), SQLITE_OK)
        let legacyData = """
        INSERT INTO tracks (title, artist, album, duration, file_path, file_name, file_format) VALUES
         ('Song A', 'Artist', 'Album', 100, '/lib/a.mp3', 'a.mp3', 'mp3'),
         ('Song B', 'Artist', 'Album', 200, '/lib/b.flac', 'b.flac', 'flac');
        INSERT INTO playlists (name) VALUES ('My List');
        INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 0);
        INSERT INTO play_history (track_id, started_at) VALUES (1, '2026-01-01 00:00:00');
        """
        XCTAssertEqual(sqlite3_exec(raw, legacyData, nil, nil, nil), SQLITE_OK)
        sqlite3_close(raw)

        // 2. App-style open order: config first, then a fresh empty tracks DB.
        XCTAssertTrue(Database.open(configDb))
        Database.setSetting("library_dir", libDir)
        XCTAssertTrue(Database.openTracksDb(libDir + "/tracks.db"))

        // 3. Migration copies the four tables.
        Database.migrateToSplitDb()
        XCTAssertEqual(Database.getTrackCount(), 2)
        XCTAssertEqual(Database.getAllPlaylists().count, 1)
        XCTAssertEqual(Database.getPlayHistory(10).count, 1)

        // 4. Idempotent: a second run changes nothing.
        Database.migrateToSplitDb()
        XCTAssertEqual(Database.getTrackCount(), 2)

        // 5. AUTOINCREMENT continues above the migrated ids — the next insert
        //    must get id 3, not collide with migrated ids 1 and 2.
        XCTAssertTrue(Database.insertTrack([
            "title": "Song C", "artist": "Artist", "album": "Album",
            "duration": 50, "file_path": "/lib/c.ogg", "file_name": "c.ogg",
            "file_format": "ogg",
        ]))
        let newTrack = Database.getTrackById(3) as? [String: Any]
        XCTAssertNotNil(newTrack, "new track should take id 3 (sequence above migrated ids)")
        XCTAssertEqual(newTrack?["title"] as? String, "Song C")

        Database.close()
    }
}


final class ImportRunImportTests: XCTestCase {

    private var tempRoot: String!
    private var configDb: String!
    private var libDir: String!
    private var sourceDir: String!

    override func setUp() {
        super.setUp()
        tempRoot = NSTemporaryDirectory() + "fp_runimport_\(UUID().uuidString)"
        configDb = (tempRoot as NSString).appendingPathComponent("config.db")
        libDir = (tempRoot as NSString).appendingPathComponent("library")
        sourceDir = (tempRoot as NSString).appendingPathComponent("source")
        try? FileManager.default.createDirectory(atPath: libDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        // App-style open order: config first, then tracks DB in library root.
        XCTAssertTrue(Database.open(configDb))
        Database.setSetting("library_dir", libDir)
        XCTAssertTrue(Database.openTracksDb((libDir as NSString).appendingPathComponent("tracks.db")))
        AppContext.shared.addTrustedScanRoot(sourceDir)
    }

    override func tearDown() {
        Database.close()
        AppContext.shared.bridgeCore = nil
        AppContext.shared.platformBridge = nil
        try? FileManager.default.removeItem(atPath: tempRoot)
        super.tearDown()
    }

    /// Create small but real audio files: WAV is trivially constructible and
    /// AVFoundation reads its metadata without a network or codec dependency.
    private func makeWav(_ name: String) throws {
        // 44-byte header + 1 second of silence (8000 Hz mono 16-bit)
        let sampleCount = 8000
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        var size = UInt32(36 + sampleCount * 2).littleEndian
        data.append(Data(bytes: &size, count: 4))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        var fmtSize = UInt32(16).littleEndian; data.append(Data(bytes: &fmtSize, count: 4))
        var audioFmt = UInt16(1).littleEndian; data.append(Data(bytes: &audioFmt, count: 2))
        var channels = UInt16(1).littleEndian; data.append(Data(bytes: &channels, count: 2))
        var sampleRate = UInt32(8000).littleEndian; data.append(Data(bytes: &sampleRate, count: 4))
        var byteRate = UInt32(16000).littleEndian; data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian; data.append(Data(bytes: &blockAlign, count: 2))
        var bits = UInt16(16).littleEndian; data.append(Data(bytes: &bits, count: 2))
        data.append("data".data(using: .ascii)!)
        var dataSize = UInt32(sampleCount * 2).littleEndian; data.append(Data(bytes: &dataSize, count: 4))
        data.append(Data(repeating: 0, count: sampleCount * 2))
        try data.write(to: URL(fileURLWithPath: (sourceDir as NSString).appendingPathComponent(name)))
    }

    func testRunImportHappyPath() throws {
        try makeWav("a.wav")
        try makeWav("b.wav")
        try makeWav("c.wav")

        let files = (try? FileManager.default.contentsOfDirectory(atPath: sourceDir))?
            .map { (sourceDir as NSString).appendingPathComponent($0) } ?? []

        let exp = expectation(description: "runImport completion")
        var result: [String: Any]?
        ImportPipeline.runImport(files: files, storedLib: libDir, importMode: "copy") { r in
            result = r
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)

        let imported = (result?["imported"] as? NSNumber)?.intValue ?? -1
        let errors = result?["errors"] as? [[String: Any]] ?? []
        XCTAssertEqual(imported, 3, "expected 3 imported, errors=\(errors)")
        XCTAssertEqual(Database.getTrackCount(), 3)
        XCTAssertTrue(errors.isEmpty, "unexpected errors: \(errors)")
    }

    func testRunImportSymlinkMode() throws {
        try makeWav("s1.wav")
        let files = [(sourceDir as NSString).appendingPathComponent("s1.wav")]

        let exp = expectation(description: "runImport symlink")
        var result: [String: Any]?
        ImportPipeline.runImport(files: files, storedLib: libDir, importMode: "symlink") { r in
            result = r
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)

        XCTAssertEqual((result?["imported"] as? NSNumber)?.intValue, 1)
        // symlink recorded in config DB so isPathInLibrary accepts the link
        let target = Database.symlinkTarget((libDir as NSString).appendingPathComponent("Unknown Artist/Unknown Album/s1.wav"))
        XCTAssertNotNil(target, "symlink should be recorded")
    }

    func testRunImportIdempotentReimport() throws {
        try makeWav("again.wav")
        let files = [(sourceDir as NSString).appendingPathComponent("again.wav")]

        let exp1 = expectation(description: "first import")
        ImportPipeline.runImport(files: files, storedLib: libDir, importMode: "copy") { _ in exp1.fulfill() }
        wait(for: [exp1], timeout: 30)
        XCTAssertEqual(Database.getTrackCount(), 1)

        // Second import of the same file: skipped (already exists), no crash,
        // still exactly one row.
        let exp2 = expectation(description: "reimport")
        var result: [String: Any]?
        ImportPipeline.runImport(files: files, storedLib: libDir, importMode: "copy") { r in
            result = r
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 30)
        XCTAssertEqual((result?["skipped"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(Database.getTrackCount(), 1)
    }

    /// Reproduce the post-split scenario: config DB that already contains the
    /// OLD single-DB tables (pre-split layout) while the tracks DB is fresh.
    /// Import must still work against the new tracks DB.
    func testRunImportWithLegacyConfigDb() throws {
        try makeWav("legacy.wav")
        let files = [(sourceDir as NSString).appendingPathComponent("legacy.wav")]

        // Simulate the old layout: tracks-related tables already exist in the
        // config DB (they are ignored by the split schema, but must not break
        // import which now writes to the tracks DB).
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(configDb, &raw, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        let legacy = "CREATE TABLE IF NOT EXISTS legacy_tracks (id INTEGER PRIMARY KEY, title TEXT);"
        XCTAssertEqual(sqlite3_exec(raw, legacy, nil, nil, nil), SQLITE_OK)
        sqlite3_close(raw)

        let exp = expectation(description: "legacy import")
        var result: [String: Any]?
        ImportPipeline.runImport(files: files, storedLib: libDir, importMode: "copy") { r in
            result = r
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)

        XCTAssertEqual((result?["imported"] as? NSNumber)?.intValue, 1, "errors=\(result?["errors"] ?? [])")
        XCTAssertEqual(Database.getTrackCount(), 1)
    }

    // MARK: - Real files (crash repro: the report says import crashes with the
    // user's real library, while synthetic WAVs pass)

    /// Copy a few real FLAC files from the macOS library (simulator apps can
    /// read the host filesystem) and run the full import on them.
    func testRunImportRealFlacFiles() throws {
        let realLib = "/Users/eason/Music/FreePlayer"
        guard FileManager.default.fileExists(atPath: realLib) else {
            throw XCTSkip("macOS library not present on this host")
        }
        let candidates = (try? FileManager.default.contentsOfDirectory(atPath: realLib)) ?? []
        var copied = 0
        for artist in candidates {
            let artistPath = (realLib as NSString).appendingPathComponent(artist)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: artistPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let albums = (try? FileManager.default.contentsOfDirectory(atPath: artistPath)) ?? []
            for album in albums {
                let albumPath = (artistPath as NSString).appendingPathComponent(album)
                let filesInAlbum = (try? FileManager.default.contentsOfDirectory(atPath: albumPath)) ?? []
                for f in filesInAlbum where f.hasSuffix(".flac") && copied < 3 {
                    try? FileManager.default.copyItem(
                        atPath: (albumPath as NSString).appendingPathComponent(f),
                        toPath: (sourceDir as NSString).appendingPathComponent(f))
                    copied += 1
                }
            }
        }
        guard copied > 0 else { throw XCTSkip("no real FLAC files found") }

        let files = (try? FileManager.default.contentsOfDirectory(atPath: sourceDir))?
            .map { (sourceDir as NSString).appendingPathComponent($0) } ?? []

        let exp = expectation(description: "real flac import")
        var result: [String: Any]?
        ImportPipeline.runImport(files: files, storedLib: libDir, importMode: "copy") { r in
            result = r
            exp.fulfill()
        }
        wait(for: [exp], timeout: 60)

        let imported = (result?["imported"] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(imported, copied, "errors=\(result?["errors"] ?? [])")
        XCTAssertEqual(Database.getTrackCount(), Int64(copied))
    }
}
