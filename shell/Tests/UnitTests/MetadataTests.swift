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

    // MARK: - Embedded lyrics (file baseline)

    func testLyricsFromVorbisTagsPrefersLyricsKey() {
        // LYRICS wins over UNSYNCEDLYRICS; the parser lowercases every key.
        XCTAssertEqual(
            Metadata.lyricsFromVorbisTags(["lyrics": "A", "unsyncedlyrics": "B"]), "A")
        XCTAssertEqual(
            Metadata.lyricsFromVorbisTags(["unsyncedlyrics": "B"]), "B")
        XCTAssertEqual(
            Metadata.lyricsFromVorbisTags(["unsynced lyrics": "C"]), "C")
        // Blank values are not lyrics, and an unrelated tag block is not either.
        XCTAssertNil(Metadata.lyricsFromVorbisTags(["lyrics": "   "]))
        XCTAssertNil(Metadata.lyricsFromVorbisTags(["artist": "Someone"]))
    }

    func testReadEmbeddedLyricsFromFlacVorbisComment() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_flac_lrc_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let path = (tmpDir as NSString).appendingPathComponent("Song.flac")
        let lrc = "[00:01.00]第一行\n[00:02.50]second line"
        try flacFile(comments: ["ARTIST=Someone", "LYRICS=\(lrc)"]).write(to: URL(fileURLWithPath: path))

        XCTAssertEqual(Metadata.readEmbeddedLyrics(atPath: path), lrc)
    }

    func testReadEmbeddedLyricsFromId3USLT() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_id3_lrc_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let path = (tmpDir as NSString).appendingPathComponent("Song.mp3")
        // encoding(UTF-8) | language | empty descriptor (terminated) | lyrics
        let uslt: [UInt8] = [0x03] + Array("eng".utf8) + [0x00] + Array("第一行\nsecond line".utf8)
        let data = id3v2File(frames: [
            ("TIT2", [0x03] + Array("A Title".utf8)),
            ("USLT", uslt),
        ])
        try data.write(to: URL(fileURLWithPath: path))

        XCTAssertEqual(Metadata.readEmbeddedLyrics(atPath: path), "第一行\nsecond line")
    }

    func testReadEmbeddedLyricsFromId3SYLTBecomesLRC() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_sylt_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let path = (tmpDir as NSString).appendingPathComponent("Song.mp3")
        // encoding(UTF-8) | language | timestamp format(2=ms) | content type(1)
        // | empty descriptor | (text + NUL + u32 BE timestamp)*
        var sylt: [UInt8] = [0x03] + Array("eng".utf8) + [0x02, 0x01, 0x00]
        sylt += Array("Hello".utf8) + [0x00, 0x00, 0x00, 0x30, 0xD4] // 12500 ms
        sylt += Array("World".utf8) + [0x00, 0x00, 0x00, 0x4E, 0x20] // 20000 ms
        try id3v2File(frames: [("SYLT", sylt)]).write(to: URL(fileURLWithPath: path))

        XCTAssertEqual(Metadata.readEmbeddedLyrics(atPath: path), "[00:12.50]Hello\n[00:20.00]World")
    }

    func testReadEmbeddedLyricsWithoutTagsIsNil() throws {
        let tmpDir = NSTemporaryDirectory() + "fp_nolrc_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        let path = (tmpDir as NSString).appendingPathComponent("Song.mp3")
        // Tag with a title but no lyrics frame.
        try id3v2File(frames: [("TIT2", [0x03] + Array("A Title".utf8))])
            .write(to: URL(fileURLWithPath: path))
        XCTAssertNil(Metadata.readEmbeddedLyrics(atPath: path))
        // And a format whose tags live elsewhere entirely.
        XCTAssertNil(Metadata.readEmbeddedLyrics(atPath: (tmpDir as NSString).appendingPathComponent("Song.m4a")))
    }

    // MARK: - Embedded cover (file baseline)

    func testReadEmbeddedCoverPrefersTheFrontCoverPicture() throws {
        let dir = try tempDir("fp_flac_cover")
        let icon = [UInt8](repeating: 0x11, count: 8)
        let front = [UInt8](repeating: 0xAB, count: 64)
        // An icon picture (type 1) before the front cover (type 3) — the front
        // cover is what a player is meant to show.
        let path = (dir as NSString).appendingPathComponent("Cover.flac")
        try flacBlocks([
            (type: 4, body: vorbisBody(["ARTIST=Someone", "LYRICS=[00:01.00]hi"])),
            (type: 6, body: pictureBody(type: 1, mime: "image/png", data: icon)),
            (type: 6, body: pictureBody(type: 3, mime: "image/jpeg", data: front)),
        ]).write(to: URL(fileURLWithPath: path))

        XCTAssertEqual(Metadata.readEmbeddedCover(atPath: path), Data(front))
        // The same file's Vorbis comments still parse: one pass reads both.
        XCTAssertEqual(Metadata.readEmbeddedLyrics(atPath: path), "[00:01.00]hi")
    }

    func testReadEmbeddedCoverFallsBackToTheOnlyPicture() throws {
        let dir = try tempDir("fp_flac_cover2")
        let only = [UInt8](repeating: 0x7F, count: 32)
        let path = (dir as NSString).appendingPathComponent("Other.flac")
        try flacBlocks([(type: 6, body: pictureBody(type: 4, mime: "image/jpeg", data: only))])
            .write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(Metadata.readEmbeddedCover(atPath: path), Data(only))
    }

    func testReadEmbeddedCoverRejectsMalformedAndWrongFormats() throws {
        let dir = try tempDir("fp_flac_cover3")
        // A picture whose declared data length runs past the block.
        let oversized: [UInt8] = be32(3) + be32(0) + be32(0)
            + be32(0) + be32(0) + be32(0) + be32(0) + be32(999) + [0x01, 0x02]
        let badPath = (dir as NSString).appendingPathComponent("Bad.flac")
        try flacBlocks([(type: 6, body: oversized)]).write(to: URL(fileURLWithPath: badPath))
        XCTAssertNil(Metadata.readEmbeddedCover(atPath: badPath))

        // The same bytes under a non-FLAC extension (MP3/M4A artwork comes from
        // AVFoundation, not from this parser).
        let mp3Path = (dir as NSString).appendingPathComponent("Cover.mp3")
        try flacBlocks([(type: 6, body: pictureBody(type: 3, mime: "image/jpeg", data: [0xAA]))])
            .write(to: URL(fileURLWithPath: mp3Path))
        XCTAssertNil(Metadata.readEmbeddedCover(atPath: mp3Path))

        // Not a FLAC at all.
        let junkPath = (dir as NSString).appendingPathComponent("Junk.flac")
        try Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]).write(to: URL(fileURLWithPath: junkPath))
        XCTAssertNil(Metadata.readEmbeddedCover(atPath: junkPath))
    }

    // MARK: - Fixture builders

    private func tempDir(_ tag: String) throws -> String {
        let dir = NSTemporaryDirectory() + "\(tag)_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }

    /// A FLAC stream header followed by the given metadata blocks; only the
    /// last block carries the last-block flag.
    private func flacBlocks(_ blocks: [(type: Int, body: [UInt8])]) -> Data {
        var out: [UInt8] = Array("fLaC".utf8)
        for (i, block) in blocks.enumerated() {
            let last = i == blocks.count - 1
            let len = block.body.count
            out += [UInt8(block.type | (last ? 0x80 : 0x00)),
                    UInt8((len >> 16) & 0xff), UInt8((len >> 8) & 0xff), UInt8(len & 0xff)]
            out += block.body
        }
        return Data(out)
    }

    /// VORBIS_COMMENT body: vendor string + length-prefixed KEY=value entries.
    private func vorbisBody(_ comments: [String]) -> [UInt8] {
        var block: [UInt8] = []
        let vendor = Array("test".utf8)
        block += le32(UInt32(vendor.count)); block += vendor
        block += le32(UInt32(comments.count))
        for c in comments {
            let bytes = Array(c.utf8)
            block += le32(UInt32(bytes.count)); block += bytes
        }
        return block
    }

    /// PICTURE body: type | MIME | (empty) description | w/h/depth/colors |
    /// data length | data.
    private func pictureBody(type: Int, mime: String, data: [UInt8]) -> [UInt8] {
        var body: [UInt8] = be32(UInt32(type))
        let mimeBytes = Array(mime.utf8)
        body += be32(UInt32(mimeBytes.count)); body += mimeBytes
        body += be32(0) // empty description
        body += be32(16) + be32(16) + be32(24) + be32(0) // w, h, depth, colors
        body += be32(UInt32(data.count)); body += data
        return body
    }

    /// Minimal FLAC with one VORBIS_COMMENT block.
    private func flacFile(comments: [String]) -> Data {
        flacBlocks([(type: 4, body: vorbisBody(comments))])
    }

    /// Minimal ID3v2.3 file: header + the given (id, payload) frames.
    private func id3v2File(frames: [(String, [UInt8])]) -> Data {
        var body: [UInt8] = []
        for (id, payload) in frames {
            body += Array(id.utf8)
            let n = UInt32(payload.count)
            body += [UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff),
                     UInt8((n >> 8) & 0xff), UInt8(n & 0xff)]
            body += [0x00, 0x00] // frame flags
            body += payload
        }
        let size = body.count
        let header: [UInt8] = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, // "ID3" 2.3.0
            UInt8((size >> 21) & 0x7f), UInt8((size >> 14) & 0x7f),
            UInt8((size >> 7) & 0x7f), UInt8(size & 0x7f)] // synchsafe size
        return Data(header + body)
    }
}
