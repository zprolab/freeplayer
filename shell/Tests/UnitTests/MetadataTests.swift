// FreePlayer — XCTest unit tests for Metadata helpers (stem cleaning, sidecar lookup).

import XCTest
@testable import FreePlayer

final class MetadataTests: XCTestCase {

    // MARK: - cleanAudioStem

    func testCleanStemRemovesDownloaderSuffix() {
        // _EM, _L style suffixes at END of string are stripped
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_EM"), "Song Title")
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_L"), "Song Title")
        XCTAssertEqual(Metadata.cleanAudioStem("Track_ABC"), "Track")
    }

    func testCleanStemPreservesNormalNames() {
        XCTAssertEqual(Metadata.cleanAudioStem("Normal Song Title"), "Normal Song Title")
        XCTAssertEqual(Metadata.cleanAudioStem("Short"), "Short")
    }

    func testCleanStemOnlyStrips1To4CharSuffix() {
        // 5+ char suffix should NOT be stripped
        XCTAssertEqual(Metadata.cleanAudioStem("Song ABCDE"), "Song ABCDE")
        // Single char _X should be stripped
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_A"), "Song Title")
    }

    func testCleanStemPreservesOriginalWithoutUnderscore() {
        XCTAssertEqual(Metadata.cleanAudioStem("NoSuffixHere"), "NoSuffixHere")
    }

    func testCleanStemDoesNotStripMiddleSuffix() {
        // Only strips at END of string — middle suffixes are preserved
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_EM.flac"), "Song Title_EM.flac")
    }

    func testCleanStemStripsDoubleLetterSuffix() {
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_CD"), "Song Title")
    }

    func testCleanStemStripsFourLetterSuffix() {
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_ABCD"), "Song Title")
    }

    func testCleanStemDoesNotStripFiveLetterSuffix() {
        XCTAssertEqual(Metadata.cleanAudioStem("Song Title_ABCDE"), "Song Title_ABCDE")
    }

    // MARK: - findSidecarLrc (integration with filesystem)

    func testFindSidecarLrcExactMatch() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_lrc_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let audioPath = (tmpDir as NSString).appendingPathComponent("My Song.mp3")
        let lrcPath = (tmpDir as NSString).appendingPathComponent("My Song.lrc")
        try "test".write(toFile: lrcPath, atomically: true, encoding: .utf8)
        try "dummy".write(toFile: audioPath, atomically: true, encoding: .utf8)

        let found = Metadata.findSidecarLrc(audioPath)
        XCTAssertEqual(found, lrcPath)
    }

    func testFindSidecarLrcWithDownloaderSuffix() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_lrc_test2_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        // Audio: "Song Title_EM.mp3" → clean stem of filename = "Song Title_EM" (middle preserved)
        // LRC:   "Song Title.lrc"    → clean stem = "Song Title"
        // These don't match exactly, but prefix match with minLen >= 8 kicks in
        let audioPath = (tmpDir as NSString).appendingPathComponent("Song Title_EM.mp3")
        let lrcPath = (tmpDir as NSString).appendingPathComponent("Song Title.lrc")
        try "test".write(toFile: lrcPath, atomically: true, encoding: .utf8)
        try "dummy".write(toFile: audioPath, atomically: true, encoding: .utf8)

        // "Song Title" is a prefix of "Song Title_EM" (both >= 8 chars after lowercase)
        let found = Metadata.findSidecarLrc(audioPath)
        XCTAssertEqual(found, lrcPath)
    }

    func testFindSidecarLrcNoMatch() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_lrc_test3_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let audioPath = (tmpDir as NSString).appendingPathComponent("Unmatched.mp3")
        let lrcPath = (tmpDir as NSString).appendingPathComponent("Different Song.lrc")
        try "test".write(toFile: lrcPath, atomically: true, encoding: .utf8)
        try "dummy".write(toFile: audioPath, atomically: true, encoding: .utf8)

        XCTAssertNil(Metadata.findSidecarLrc(audioPath))
    }

    func testFindSidecarLrcNonexistentDir() {
        XCTAssertNil(Metadata.findSidecarLrc("/nonexistent/dir/song.mp3"))
    }

    func testFindSidecarLrcIgnoresNumericSuffixStems() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_lrc_test4_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let audioPath = (tmpDir as NSString).appendingPathComponent("Song.mp3")
        let lrcPath = (tmpDir as NSString).appendingPathComponent("Song.12345.lrc")
        try "test".write(toFile: lrcPath, atomically: true, encoding: .utf8)
        try "dummy".write(toFile: audioPath, atomically: true, encoding: .utf8)

        // ".12345" numeric suffix stems should be skipped in prefix matching
        XCTAssertNil(Metadata.findSidecarLrc(audioPath))
    }
}
