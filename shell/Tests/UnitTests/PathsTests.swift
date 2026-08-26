// FreePlayer — XCTest unit tests for Paths utility (audio detection, containment).

import XCTest
@testable import FreePlayer

final class PathsTests: XCTestCase {

    // MARK: - isAudioFile

    func testCommonAudioFormats() {
        XCTAssertTrue(Paths.isAudioFile("/music/song.mp3"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.flac"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.wav"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.ogg"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.m4a"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.aac"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.opus"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.wma"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.aiff"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.aif"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.ape"))
        // mp4 is also in audioExtensions (video container but can hold audio)
        XCTAssertTrue(Paths.isAudioFile("/music/song.mp4"))
    }

    func testNonAudioFormats() {
        XCTAssertFalse(Paths.isAudioFile("/music/song.txt"))
        XCTAssertFalse(Paths.isAudioFile("/music/song.pdf"))
        XCTAssertFalse(Paths.isAudioFile("/music/song.jpg"))
        XCTAssertFalse(Paths.isAudioFile("/music/song.mkv"))
        XCTAssertFalse(Paths.isAudioFile("/music/song.zip"))
        XCTAssertFalse(Paths.isAudioFile("/music/song.png"))
    }

    func testExoticAudioFormats() {
        XCTAssertTrue(Paths.isAudioFile("/music/song.m4b"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.wv"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.tak"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.ac3"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.dts"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.amr"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(Paths.isAudioFile("/music/song.MP3"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.FLAC"))
        XCTAssertTrue(Paths.isAudioFile("/music/song.Flac"))
    }

    func testEmptyExtension() {
        XCTAssertFalse(Paths.isAudioFile("/music/song"))
        XCTAssertFalse(Paths.isAudioFile("/music/."))
    }

    func testEmptyPath() {
        XCTAssertFalse(Paths.isAudioFile(""))
    }

    func testHiddenAudioFile() {
        XCTAssertTrue(Paths.isAudioFile("/music/.hidden.mp3"))
    }

    func testDeepNestedPath() {
        XCTAssertTrue(Paths.isAudioFile("/a/b/c/d/e/f/g/song.flac"))
    }

    // MARK: - isPathInLibrary

    func testPathInLibrary() {
        Database.open(NSTemporaryDirectory() + "paths_test_\(UUID().uuidString).db")
        let libDir = NSTemporaryDirectory() + "fp_paths_lib_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: libDir, withIntermediateDirectories: true)
        Database.setSetting("library_dir", libDir)

        let testFile = (libDir as NSString).appendingPathComponent("song.mp3")
        XCTAssertTrue(Paths.isPathInLibrary(testFile))
        XCTAssertTrue(Paths.isPathInLibrary(libDir)) // root itself

        Database.close()
        try? FileManager.default.removeItem(atPath: libDir)
    }

    func testPathOutsideLibrary() {
        Database.open(NSTemporaryDirectory() + "paths_test2_\(UUID().uuidString).db")
        let libDir = NSTemporaryDirectory() + "fp_paths_lib2_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: libDir, withIntermediateDirectories: true)
        Database.setSetting("library_dir", libDir)

        XCTAssertFalse(Paths.isPathInLibrary("/etc/passwd"))
        XCTAssertFalse(Paths.isPathInLibrary("/tmp/evil.mp3"))

        Database.close()
        try? FileManager.default.removeItem(atPath: libDir)
    }

    func testPathTraversalAttack() {
        Database.open(NSTemporaryDirectory() + "paths_test3_\(UUID().uuidString).db")
        let libDir = NSTemporaryDirectory() + "fp_paths_lib3_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: libDir, withIntermediateDirectories: true)
        Database.setSetting("library_dir", libDir)

        let evilPath = (libDir as NSString).appendingPathComponent("../../etc/passwd")
        XCTAssertFalse(Paths.isPathInLibrary(evilPath))

        Database.close()
        try? FileManager.default.removeItem(atPath: libDir)
    }

    func testNoLibraryDirSet() {
        Database.open(NSTemporaryDirectory() + "paths_test4_\(UUID().uuidString).db")
        XCTAssertFalse(Paths.isPathInLibrary("/anything/at/all.mp3"))
        Database.close()
    }
}
