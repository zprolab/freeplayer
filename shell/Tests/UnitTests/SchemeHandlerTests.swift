// FreePlayer — XCTest unit tests for SchemeHandler MIME type mapping.

import XCTest
@testable import FreePlayer

final class SchemeHandlerTests: XCTestCase {

    // MARK: - mimeForPath

    func testHtmlMime() {
        XCTAssertEqual(mimeForPath("/index.html"), "text/html; charset=utf-8")
        XCTAssertEqual(mimeForPath("/page.htm"), "text/html; charset=utf-8")
    }

    func testJsMime() {
        XCTAssertEqual(mimeForPath("/app.js"), "text/javascript")
        XCTAssertEqual(mimeForPath("/module.mjs"), "text/javascript")
    }

    func testCssMime() {
        XCTAssertEqual(mimeForPath("/style.css"), "text/css")
    }

    func testJsonMime() {
        XCTAssertEqual(mimeForPath("/data.json"), "application/json")
    }

    func testSvgMime() {
        XCTAssertEqual(mimeForPath("/icon.svg"), "image/svg+xml")
    }

    func testFontMimes() {
        XCTAssertEqual(mimeForPath("/font.woff2"), "font/woff2")
        XCTAssertEqual(mimeForPath("/font.woff"), "font/woff")
        XCTAssertEqual(mimeForPath("/font.ttf"), "font/ttf")
    }

    func testAudioMimes() {
        XCTAssertEqual(mimeForPath("/song.flac"), "audio/flac")
        XCTAssertEqual(mimeForPath("/song.mp3"), "audio/mpeg")
        XCTAssertEqual(mimeForPath("/song.m4a"), "audio/mp4")
        XCTAssertEqual(mimeForPath("/song.mp4"), "audio/mp4")
        XCTAssertEqual(mimeForPath("/song.ogg"), "audio/ogg")
        XCTAssertEqual(mimeForPath("/song.wav"), "audio/wav")
        XCTAssertEqual(mimeForPath("/song.aac"), "audio/aac")
        XCTAssertEqual(mimeForPath("/song.opus"), "audio/ogg")
    }

    func testImageMimes() {
        XCTAssertEqual(mimeForPath("/photo.jpg"), "image/jpeg")
        XCTAssertEqual(mimeForPath("/photo.jpeg"), "image/jpeg")
        XCTAssertEqual(mimeForPath("/photo.png"), "image/png")
        XCTAssertEqual(mimeForPath("/photo.webp"), "image/webp")
        XCTAssertEqual(mimeForPath("/photo.gif"), "image/gif")
    }

    func testLrcMime() {
        XCTAssertEqual(mimeForPath("/lyrics.lrc"), "text/plain; charset=utf-8")
        XCTAssertEqual(mimeForPath("/readme.txt"), "text/plain; charset=utf-8")
    }

    func testExoticAudioMimes() {
        XCTAssertEqual(mimeForPath("/track.ape"), "audio/x-ape")
        XCTAssertEqual(mimeForPath("/track.wv"), "audio/x-wavpack")
        XCTAssertEqual(mimeForPath("/track.tak"), "audio/x-tak")
        XCTAssertEqual(mimeForPath("/track.ac3"), "audio/ac3")
        XCTAssertEqual(mimeForPath("/track.dts"), "audio/vnd.dts")
        XCTAssertEqual(mimeForPath("/track.amr"), "audio/amr")
    }

    func testUnknownExtension() {
        XCTAssertEqual(mimeForPath("/file.xyz"), "application/octet-stream")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(mimeForPath("/FILE.MP3"), "audio/mpeg")
        XCTAssertEqual(mimeForPath("/FILE.HTML"), "text/html; charset=utf-8")
    }

    func testNoExtension() {
        XCTAssertEqual(mimeForPath("/noext"), "application/octet-stream")
    }

    func testIcoMime() {
        XCTAssertEqual(mimeForPath("/favicon.ico"), "image/x-icon")
    }
}
