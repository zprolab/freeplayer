import XCTest
@testable import FreePlayer

final class LRCTests: XCTestCase {
    func testParseSimple() {
        let raw = """
        [ti:Test Song]
        [00:01.00]First line
        [00:03.50]Second line
        [00:05.00]Third line
        """
        let lines = LRC.parse(raw)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[0].time, 1.0, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 5.0, accuracy: 0.001)
    }

    func testParseMultiTimestamp() {
        let raw = "[00:01.00][00:05.00]Repeated"
        let lines = LRC.parse(raw)
        // Adjacent identical lines are deduplicated (matching the original app)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 1.0, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "Repeated")
    }

    func testSortAndDedup() {
        let raw = """
        [00:03.00]B
        [00:01.00]A
        [00:02.00]B
        [00:04.00]B
        """
        let lines = LRC.parse(raw)
        // Sorted by time, then consecutive identical lines merged
        XCTAssertEqual(lines.map(\.time), [1.0, 2.0])
        XCTAssertEqual(lines.map(\.text), ["A", "B"])
    }

    func testSanitizeRemovesControlGlyphs() {
        let dirty = "a\u{200B}b\u{FFFD}c\u{00}\u{7F}"
        let clean = LRC.sanitize(dirty)
        XCTAssertEqual(clean, "a b c  ")
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.time(65), "1:05")
        XCTAssertEqual(Formatting.time(0), "0:00")
        XCTAssertEqual(Formatting.tableDuration(0), "--:--")
        XCTAssertEqual(Formatting.statsDuration(3720), "1h 2m")
    }
}

final class DatabaseTests: XCTestCase {
    private var dbPath: String!
    private let db = Database.shared

    override func setUpWithError() throws {
        dbPath = NSTemporaryDirectory() + "/fp-test-\(UUID().uuidString).db"
        try? FileManager.default.removeItem(atPath: dbPath)
        XCTAssertTrue(db.open(path: dbPath))
    }

    override func tearDownWithError() throws {
        db.close()
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(atPath: dbPath + "-wal")
        try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    func testSettings() {
        db.setSetting("volume", "0.5")
        XCTAssertEqual(db.getSetting("volume"), "0.5")
        XCTAssertEqual(db.getBoolSetting("tray_enabled", fallback: true), true)
    }

    func testTrackInsertAndFetch() {
        let t = Track(id: 0, title: "Song A", artist: "Artist A", album: "Album A",
                      trackNumber: 1, discNumber: nil, genre: "Rock", year: 2020,
                      duration: 180, filePath: "/tmp/a.mp3", fileName: "a.mp3",
                      fileSize: 1000, fileFormat: "mp3", bitrate: 320,
                      sampleRate: 44100, channels: 2, coverPath: nil,
                      replaygainGain: -3.5, replaygainPeak: 0.9, lrcPath: nil,
                      playCount: 0, lastPlayedAt: nil, importedAt: nil, updatedAt: nil)
        XCTAssertTrue(db.insertTrack(t))
        let fetched = db.getAllTracks()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].title, "Song A")
        XCTAssertEqual(fetched[0].replaygainGain, -3.5)
        XCTAssertEqual(fetched[0].bitrate, 320)
    }

    func testTrackUpsert() {
        let t = Track(id: 0, title: "V1", artist: "A", album: "B",
                      trackNumber: nil, discNumber: nil, genre: nil, year: nil,
                      duration: 10, filePath: "/tmp/dup.mp3", fileName: "dup.mp3",
                      fileSize: 1, fileFormat: "mp3", bitrate: nil,
                      sampleRate: nil, channels: nil, coverPath: nil,
                      replaygainGain: 0, replaygainPeak: 0, lrcPath: nil,
                      playCount: 0, lastPlayedAt: nil, importedAt: nil, updatedAt: nil)
        XCTAssertTrue(db.insertTrack(t))
        var t2 = t
        t2.title = "V2"
        XCTAssertTrue(db.insertTrack(t2))
        XCTAssertEqual(db.getAllTracks().count, 1)
        XCTAssertEqual(db.getAllTracks()[0].title, "V2")
    }

    func testPlayHistoryAndStats() {
        let t = Track(id: 0, title: "S", artist: "Ar", album: "Al",
                      trackNumber: nil, discNumber: nil, genre: nil, year: nil,
                      duration: 100, filePath: "/tmp/s.mp3", fileName: "s.mp3",
                      fileSize: 1, fileFormat: "mp3", bitrate: nil,
                      sampleRate: nil, channels: nil, coverPath: nil,
                      replaygainGain: 0, replaygainPeak: 0, lrcPath: nil,
                      playCount: 0, lastPlayedAt: nil, importedAt: nil, updatedAt: nil)
        db.insertTrack(t)
        let track = db.getAllTracks()[0]
        let sid = db.startPlaySession(trackId: track.id)
        XCTAssertGreaterThan(sid, 0)
        db.endPlaySession(sessionId: sid, durationSeconds: 42, playPercentage: 50)
        let stats = db.listeningStats()
        XCTAssertEqual(stats.totalPlays, 1)
        XCTAssertEqual(stats.totalTime, 42)
        XCTAssertEqual(stats.uniqueTracksPlayed, 1)
        XCTAssertEqual(db.getTrack(id: track.id)?.playCount, 1)
    }

    func testPlaylists() {
        let id = db.createPlaylist(name: "My List", description: "desc")
        XCTAssertGreaterThan(id, 0)
        let t = Track(id: 0, title: "X", artist: "Y", album: "Z",
                      trackNumber: nil, discNumber: nil, genre: nil, year: nil,
                      duration: 1, filePath: "/tmp/x.mp3", fileName: "x.mp3",
                      fileSize: 1, fileFormat: "mp3", bitrate: nil,
                      sampleRate: nil, channels: nil, coverPath: nil,
                      replaygainGain: 0, replaygainPeak: 0, lrcPath: nil,
                      playCount: 0, lastPlayedAt: nil, importedAt: nil, updatedAt: nil)
        db.insertTrack(t)
        let track = db.getAllTracks()[0]
        db.addTrackToPlaylist(playlistId: id, trackId: track.id)
        XCTAssertEqual(db.playlistTracks(playlistId: id).count, 1)
        db.renamePlaylist(id: id, name: "Renamed")
        XCTAssertEqual(db.allPlaylists()[0].name, "Renamed")
    }
}

final class MetadataTests: XCTestCase {
    func testWavExtraction() throws {        // Build a tiny 1s 440Hz mono 16-bit PCM WAV in memory
        let sampleRate = 8000
        let samples = sampleRate
        var data = Data()
        data.append(Data("RIFF".utf8))
        var fileSize: Int32 = 36 + Int32(samples) * 2
        data.append(withUnsafeBytes(of: &fileSize) { Data($0) })
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        var fmtChunkSize: UInt32 = 16
        data.append(withUnsafeBytes(of: &fmtChunkSize) { Data($0) })
        var audioFormat: UInt16 = 1
        data.append(withUnsafeBytes(of: &audioFormat) { Data($0) })
        var channels: UInt16 = 1
        data.append(withUnsafeBytes(of: &channels) { Data($0) })
        var rate: UInt32 = UInt32(sampleRate)
        data.append(withUnsafeBytes(of: &rate) { Data($0) })
        var byteRate: Int32 = Int32(sampleRate * 2)
        data.append(withUnsafeBytes(of: &byteRate) { Data($0) })
        var blockAlign: UInt16 = 2
        data.append(withUnsafeBytes(of: &blockAlign) { Data($0) })
        var bits: UInt16 = 16
        data.append(withUnsafeBytes(of: &bits) { Data($0) })
        data.append(Data("data".utf8))
        var dataSize: Int32 = Int32(samples) * 2
        data.append(withUnsafeBytes(of: &dataSize) { Data($0) })
        for i in 0..<samples {
            let v = Int16(sin(2 * .pi * 440 * Double(i) / Double(sampleRate)) * 20000)
            var le = v.littleEndian
            data.append(withUnsafeBytes(of: &le) { Data($0) })
        }

        let path = NSTemporaryDirectory() + "/fp-test-\(UUID().uuidString).wav"
        try data.write(to: URL(fileURLWithPath: path))

        defer { try? FileManager.default.removeItem(atPath: path) }

        let meta = MetadataExtractor.extract(atPath: path)
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.fileFormat, "wav")
        XCTAssertEqual(meta?.sampleRate ?? 0, Double(sampleRate), accuracy: 10)
        XCTAssertEqual(meta?.channels, 1)
        XCTAssertGreaterThan(meta?.duration ?? 0, 0.9)
    }

    func testSidecarLrcDetection() throws {
        let temp = NSTemporaryDirectory().hasSuffix("/")
            ? String(NSTemporaryDirectory().dropLast())
            : NSTemporaryDirectory()
        let dir = temp + "/fp-lrc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data("".utf8).write(to: URL(fileURLWithPath: dir + "/Artist - Title_L.lrc"))
        try Data("".utf8).write(to: URL(fileURLWithPath: dir + "/Artist - Title_EM.flac"))

        let found = MetadataExtractor.findSidecarLrc(forAudioPath: dir + "/Artist - Title_EM.flac")
        XCTAssertEqual(found, dir + "/Artist - Title_L.lrc")
    }
}

final class RemoteMetadataTests: XCTestCase {
    private func track(title: String = "Sun", artist: String = "A", album: String = "Album") -> Track {
        Track(id: 7, title: title, artist: artist, album: album,
              trackNumber: nil, discNumber: nil, genre: nil, year: nil,
              duration: 65.4, filePath: "/tmp/sun.mp3", fileName: "sun.mp3",
              fileSize: 1, fileFormat: "mp3", bitrate: nil, sampleRate: nil,
              channels: nil, coverPath: nil, replaygainGain: 0, replaygainPeak: 0,
              lrcPath: nil, playCount: 0, lastPlayedAt: nil, importedAt: nil, updatedAt: nil)
    }

    func testMatchNormalizationAndSimilarity() {
        XCTAssertEqual(MetadataFetchService.normalizeForMatch("  新视野3中的CC! "), "新视野3中的cc")
        XCTAssertEqual(MetadataFetchService.similarity("Life Goes On", "life-goes-on"), 1)
        XCTAssertEqual(MetadataFetchService.similarity("Life Goes On (Deluxe)", "Life Goes On"), 0.9)
    }

    func testBestMatchRejectsWrongArtist() {
        let candidates = [
            MetadataFetchService.Candidate(title: "Sun", artist: "Wrong"),
            MetadataFetchService.Candidate(title: "Sun", artist: "A"),
        ]
        XCTAssertEqual(MetadataFetchService.bestMatchIndex(in: candidates, for: track()), 1)
    }

    func testUnknownArtistMatchesByTitle() {
        let candidates = [MetadataFetchService.Candidate(title: "Sun", artist: "Anybody")]
        XCTAssertEqual(MetadataFetchService.bestMatchIndex(in: candidates,
                                                            for: track(artist: Track.unknownArtist)), 0)
    }

    func testServiceURLs() {
        let song = track()
        let components = MetadataFetchService.lrclibGetURL(for: song)
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["artist_name"], "A")
        XCTAssertEqual(values["track_name"], "Sun")
        XCTAssertEqual(values["duration"], "65")
        XCTAssertTrue(MetadataFetchService.itunesSearchURL(for: song)?.absoluteString.contains("itunes.apple.com/search") == true)
        XCTAssertEqual(MetadataFetchService.largeArtworkURL("https://img/100x100bb.jpg"),
                       "https://img/600x600bb.jpg")
    }
}

// Helpers to build a valid 1s 16-bit PCM WAV
func makeTestWav(sampleRate: Int = 8000, seconds: Int = 1) -> Data {
    let samples = sampleRate * seconds
    var data = Data()
    data.append(Data("RIFF".utf8))
    var fileSize: Int32 = 36 + Int32(samples) * 2
    data.append(withUnsafeBytes(of: &fileSize) { Data($0) })
    data.append(Data("WAVE".utf8))
    data.append(Data("fmt ".utf8))
    var fmtChunkSize: UInt32 = 16
    data.append(withUnsafeBytes(of: &fmtChunkSize) { Data($0) })
    var audioFormat: UInt16 = 1
    data.append(withUnsafeBytes(of: &audioFormat) { Data($0) })
    var channels: UInt16 = 1
    data.append(withUnsafeBytes(of: &channels) { Data($0) })
    var rate: UInt32 = UInt32(sampleRate)
    data.append(withUnsafeBytes(of: &rate) { Data($0) })
    var byteRate: Int32 = Int32(sampleRate * 2)
    data.append(withUnsafeBytes(of: &byteRate) { Data($0) })
    var blockAlign: UInt16 = 2
    data.append(withUnsafeBytes(of: &blockAlign) { Data($0) })
    var bits: UInt16 = 16
    data.append(withUnsafeBytes(of: &bits) { Data($0) })
    data.append(Data("data".utf8))
    var dataSize: Int32 = Int32(samples) * 2
    data.append(withUnsafeBytes(of: &dataSize) { Data($0) })
    for i in 0..<samples {
        let v = Int16(sin(2 * .pi * 440 * Double(i) / Double(sampleRate)) * 20000)
        var le = v.littleEndian
        data.append(withUnsafeBytes(of: &le) { Data($0) })
    }
    return data
}

final class ImportTests: XCTestCase {
    private let db = Database.shared
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = NSTemporaryDirectory() + "/fp-import-test-\(UUID().uuidString).db"
        XCTAssertTrue(db.open(path: dbPath))
    }

    override func tearDownWithError() throws {
        db.close()
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(atPath: dbPath + "-wal")
        try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    func testImportPipeline() throws {
        let temp = NSTemporaryDirectory().hasSuffix("/") ? String(NSTemporaryDirectory().dropLast()) : NSTemporaryDirectory()
        let root = temp + "/fp-import-\(UUID().uuidString)"
        let source = root + "/source"
        let library = root + "/library"
        try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: library, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let wav = makeTestWav()
        try wav.write(to: URL(fileURLWithPath: source + "/Artist A - Song B.wav"))

        let expectation = expectation(description: "import done")
        var importedResult: ImportResult?
        ImportManager().importFiles(files: [source + "/Artist A - Song B.wav"], libraryDir: library, importMode: .copy) { result in
            importedResult = result
            expectation.fulfill()
        }
        waitForExpectations(timeout: 15)

        XCTAssertEqual(importedResult?.imported, 1)
        XCTAssertEqual(importedResult?.errors.count, 0)

        // WAV has no embedded metadata → Unknown Artist / Unknown Album folders
        let fm = FileManager.default
        let expected = library + "/Unknown Artist/Unknown Album/Artist A - Song B.wav"
        XCTAssertTrue(fm.fileExists(atPath: expected), "expected copy at \(expected)")

        // Track recorded in DB
        let tracks = Database.shared.getAllTracks()
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].title, "Artist A - Song B")
        XCTAssertEqual(tracks[0].artist, "Unknown Artist")
        XCTAssertEqual(tracks[0].album, "Unknown Album")
        XCTAssertEqual(tracks[0].duration, 1.0, accuracy: 0.2)
    }

    func testExistingFileWithoutDatabaseRowIsRecoveredThenSkipped() throws {
        let temp = NSTemporaryDirectory().hasSuffix("/") ? String(NSTemporaryDirectory().dropLast()) : NSTemporaryDirectory()
        let root = temp + "/fp-import-recovery-\(UUID().uuidString)"
        let source = root + "/source"
        let library = root + "/library"
        try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try makeTestWav().write(to: URL(fileURLWithPath: source + "/recover.wav"))

        func runImport() -> ImportResult {
            let done = expectation(description: "import done")
            var output = ImportResult()
            ImportManager().importFiles(files: [source + "/recover.wav"], libraryDir: library, importMode: .copy) {
                output = $0
                done.fulfill()
            }
            waitForExpectations(timeout: 15)
            return output
        }

        XCTAssertEqual(runImport().imported, 1)
        let inserted = try XCTUnwrap(db.getAllTracks().first)
        XCTAssertTrue(db.deleteTrack(id: inserted.id))
        XCTAssertEqual(db.trackCount(), 0)

        let recovered = runImport()
        XCTAssertEqual(recovered.imported, 1)
        XCTAssertEqual(recovered.skipped, 0)
        XCTAssertEqual(db.trackCount(), 1)

        let duplicate = runImport()
        XCTAssertEqual(duplicate.imported, 0)
        XCTAssertEqual(duplicate.skipped, 1)
        XCTAssertEqual(db.trackCount(), 1)
    }

    func testCopyFailureDoesNotCreateDatabaseTrack() throws {
        let temp = NSTemporaryDirectory().hasSuffix("/") ? String(NSTemporaryDirectory().dropLast()) : NSTemporaryDirectory()
        let root = temp + "/fp-import-failure-\(UUID().uuidString)"
        let source = root + "/source.wav"
        let invalidLibrary = root + "/not-a-directory"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try makeTestWav().write(to: URL(fileURLWithPath: source))
        try Data("file blocks directory creation".utf8).write(to: URL(fileURLWithPath: invalidLibrary))

        let done = expectation(description: "failed import done")
        var output = ImportResult()
        ImportManager().importFiles(files: [source], libraryDir: invalidLibrary, importMode: .copy) {
            output = $0
            done.fulfill()
        }
        waitForExpectations(timeout: 15)

        XCTAssertEqual(output.imported, 0)
        XCTAssertEqual(output.errors.count, 1)
        XCTAssertEqual(db.trackCount(), 0)
    }

    func testScanRecursive() throws {
        let temp = NSTemporaryDirectory().hasSuffix("/") ? String(NSTemporaryDirectory().dropLast()) : NSTemporaryDirectory()
        let root = temp + "/fp-scan-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/sub/deeper", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/.hidden", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let wav = makeTestWav()
        try wav.write(to: URL(fileURLWithPath: root + "/a.wav"))
        try wav.write(to: URL(fileURLWithPath: root + "/sub/b.flac"))
        try wav.write(to: URL(fileURLWithPath: root + "/sub/deeper/c.txt"))
        try wav.write(to: URL(fileURLWithPath: root + "/.hidden/d.mp3"))

        let found = ImportManager().scanAudioFiles(root: root)
        XCTAssertEqual(Set(found), Set([root + "/a.wav", root + "/sub/b.flac"]))
    }

    func testCoverExtensionDetection() {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let gif: [UInt8] = [0x47, 0x49, 0x46, 0x38]
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF]
        XCTAssertEqual(ImportManager.coverExtension(for: Data(png)), "png")
        XCTAssertEqual(ImportManager.coverExtension(for: Data(gif)), "gif")
        XCTAssertEqual(ImportManager.coverExtension(for: Data(jpeg)), "jpg")
    }
}

final class PlaybackSessionClockTests: XCTestCase {
    func testPausedTimeIsNotAccumulated() {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        var clock = PlaybackSessionClock()
        clock.start(at: origin)
        clock.pause(at: origin.addingTimeInterval(10))
        clock.resume(at: origin.addingTimeInterval(310))

        let elapsed = clock.finish(at: origin.addingTimeInterval(320))
        XCTAssertEqual(elapsed, 20, accuracy: 0.001)
    }

    func testRepeatedPauseAndResumeAreIdempotent() {
        let origin = Date(timeIntervalSinceReferenceDate: 2_000)
        var clock = PlaybackSessionClock()
        clock.start(at: origin)
        clock.pause(at: origin.addingTimeInterval(5))
        clock.pause(at: origin.addingTimeInterval(50))
        clock.resume(at: origin.addingTimeInterval(100))
        clock.resume(at: origin.addingTimeInterval(150))

        XCTAssertEqual(clock.finish(at: origin.addingTimeInterval(110)), 15, accuracy: 0.001)
    }
}

final class AudioEngineTests: XCTestCase {
    func testLoadAndDuration() throws {
        let path = NSTemporaryDirectory() + "/fp-ae-\(UUID().uuidString).wav"
        try makeTestWav().write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let engine = AudioEngine()
        try engine.load(url: URL(fileURLWithPath: path))
        XCTAssertEqual(engine.duration, 1.0, accuracy: 0.2)
        XCTAssertEqual(engine.currentTime, 0.0)
        engine.setGain(gainDb: -6.0)
    }

    func testSeekClamps() throws {
        let path = NSTemporaryDirectory() + "/fp-ae2-\(UUID().uuidString).wav"
        try makeTestWav(seconds: 2).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let engine = AudioEngine()
        try engine.load(url: URL(fileURLWithPath: path))
        engine.seek(to: 999) // beyond duration → clamps to file end
        XCTAssertEqual(engine.currentTime, 2.0, accuracy: 0.01)
    }

    func testPlayAdvances() throws {
        let path = NSTemporaryDirectory() + "/fp-ae3-\(UUID().uuidString).wav"
        try makeTestWav(seconds: 2).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let engine = AudioEngine()
        try engine.load(url: URL(fileURLWithPath: path))
        try engine.play()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertGreaterThan(engine.currentTime, 0.3)
        engine.pause()
        let pausedAt = engine.currentTime
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(engine.currentTime, pausedAt, accuracy: 0.02, "playhead should freeze while paused")
    }

    func testSeekWhilePausedThenResume() throws {
        let path = NSTemporaryDirectory() + "/fp-ae4-\(UUID().uuidString).wav"
        try makeTestWav(seconds: 4).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let engine = AudioEngine()
        try engine.load(url: URL(fileURLWithPath: path))
        try engine.play()
        Thread.sleep(forTimeInterval: 0.5)
        engine.pause()

        engine.seek(to: 2.0)
        XCTAssertEqual(engine.currentTime, 2.0, accuracy: 0.1, "playhead should reflect seek while paused")
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(engine.currentTime, 2.0, accuracy: 0.1, "playhead should stay put while paused")

        engine.resetSignal()
        engine.resume()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertGreaterThan(engine.currentTime, 2.0, "audio should resume from the seeked position")
        XCTAssertTrue(engine.hasSignal, "audio samples must flow after pause→seek→resume")
    }

    func testVolumeComposesWithReplayGain() {
        let engine = AudioEngine()
        engine.setGain(gainDb: -6.0) // 0.5 linear
        engine.setVolume(0.8)
        XCTAssertEqual(engine.outputVolume, 0.4, accuracy: 0.001, "volume must not clobber ReplayGain")
        engine.setVolume(0.5)
        XCTAssertEqual(engine.outputVolume, 0.25, accuracy: 0.001, "volume changes must keep gain applied")
    }
}
