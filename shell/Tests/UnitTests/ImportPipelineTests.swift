// FreePlayer — XCTest unit tests for ImportPipeline (scan, path safety).

import XCTest
@testable import FreePlayer

final class ImportPipelineTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "fp_import_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - scanAudioFiles

    func testScanFindsAudioFiles() throws {
        // Create some audio files
        for name in ["song1.mp3", "song2.flac", "song3.wav"] {
            try "dummy".write(toFile: (tmpDir as NSString).appendingPathComponent(name),
                              atomically: true, encoding: .utf8)
        }
        // Create a non-audio file (should be skipped)
        try "text".write(toFile: (tmpDir as NSString).appendingPathComponent("readme.txt"),
                         atomically: true, encoding: .utf8)

        let result = ImportPipeline.scanAudioFiles(tmpDir)
        XCTAssertEqual(result.files.count, 3)
        XCTAssertFalse(result.truncated)
    }

    func testScanSkipsHiddenDirectories() throws {
        // Create a hidden directory with audio files
        let hiddenDir = (tmpDir as NSString).appendingPathComponent(".hidden_cache")
        try FileManager.default.createDirectory(atPath: hiddenDir, withIntermediateDirectories: true)
        try "dummy".write(toFile: (hiddenDir as NSString).appendingPathComponent("cached.mp3"),
                          atomically: true, encoding: .utf8)

        // Create a visible directory with audio
        let visibleDir = (tmpDir as NSString).appendingPathComponent("music")
        try FileManager.default.createDirectory(atPath: visibleDir, withIntermediateDirectories: true)
        try "dummy".write(toFile: (visibleDir as NSString).appendingPathComponent("real.mp3"),
                          atomically: true, encoding: .utf8)

        let result = ImportPipeline.scanAudioFiles(tmpDir)
        XCTAssertEqual(result.files.count, 1) // only the visible one
    }

    func testScanSkipsHiddenFiles() throws {
        try "dummy".write(toFile: (tmpDir as NSString).appendingPathComponent(".hidden.mp3"),
                          atomically: true, encoding: .utf8)
        try "dummy".write(toFile: (tmpDir as NSString).appendingPathComponent("visible.mp3"),
                          atomically: true, encoding: .utf8)

        let result = ImportPipeline.scanAudioFiles(tmpDir)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(result.files[0].hasSuffix("visible.mp3"))
    }

    func testScanEmptyDirectory() {
        let result = ImportPipeline.scanAudioFiles(tmpDir)
        XCTAssertEqual(result.files.count, 0)
        XCTAssertFalse(result.truncated)
    }

    func testScanNonexistentDirectory() {
        let result = ImportPipeline.scanAudioFiles("/nonexistent/dir")
        XCTAssertEqual(result.files.count, 0)
    }

    func testScanDeepNested() throws {
        let deep = (tmpDir as NSString).appendingPathComponent("a/b/c/d")
        try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)
        try "dummy".write(toFile: (deep as NSString).appendingPathComponent("deep.flac"),
                          atomically: true, encoding: .utf8)

        let result = ImportPipeline.scanAudioFiles(tmpDir)
        XCTAssertEqual(result.files.count, 1)
    }

    func testScanMultipleFormats() throws {
        let formats = ["mp3", "flac", "wav", "ogg", "m4a", "aac", "opus", "wma", "aiff", "ape"]
        for ext in formats {
            try "dummy".write(toFile: (tmpDir as NSString).appendingPathComponent("song.\(ext)"),
                              atomically: true, encoding: .utf8)
        }
        let result = ImportPipeline.scanAudioFiles(tmpDir)
        XCTAssertEqual(result.files.count, formats.count)
    }
}
