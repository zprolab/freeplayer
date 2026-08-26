// FreePlayer — XCTest unit tests for the generic bridge core (通用桥层).
// The core is WebKit-free by design, so these run headlessly in the
// simulator test host without any webview.

import XCTest
@testable import FreePlayer

final class BridgeCoreTests: XCTestCase {

    func testRegisterAndDispatch() {
        let core = BridgeCore()
        core.register("echo") { call in
            call.reply(call.args.first)
        }
        var result: Any?
        var rejected = false
        core.dispatch(method: "echo", args: ["hi"], idNum: 1,
                      reply: { _, obj in result = obj },
                      reject: { _, _ in rejected = true })
        XCTAssertFalse(rejected)
        XCTAssertEqual(result as? String, "hi")
    }

    func testUnknownMethodRejectsWithNotImplemented() {
        let core = BridgeCore()
        var rejectedWhy: String?
        core.dispatch(method: "nope", args: [], idNum: 7,
                      reply: { _, _ in XCTFail("unexpected reply") },
                      reject: { _, why in rejectedWhy = why })
        XCTAssertEqual(rejectedWhy, "not implemented: nope")
    }

    func testReplyThenRejectIsOneShot() {
        let core = BridgeCore()
        core.register("both") { call in
            call.reply("first")
            call.reject("should be ignored")
        }
        var replies: [Any] = []
        var rejected = false
        core.dispatch(method: "both", args: [], idNum: 1,
                      reply: { _, obj in replies.append(obj ?? NSNull()) },
                      reject: { _, _ in rejected = true })
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies.first as? String, "first")
        XCTAssertFalse(rejected)
    }

    func testDoubleReplyIsGuarded() {
        let core = BridgeCore()
        core.register("twice") { call in
            call.reply("a")
            call.reply("b")
        }
        var replies: [Any] = []
        core.dispatch(method: "twice", args: [], idNum: 1,
                      reply: { _, obj in replies.append(obj ?? NSNull()) },
                      reject: { _, _ in XCTFail("unexpected reject") })
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies.first as? String, "a")
    }

    func testRegisterOverwritesPreviousHandler() {
        let core = BridgeCore()
        core.register("m") { call in call.reply("old") }
        core.register("m") { call in call.reply("new") }
        var result: Any?
        core.dispatch(method: "m", args: [], idNum: 1,
                      reply: { _, obj in result = obj },
                      reject: { _, _ in XCTFail("unexpected reject") })
        XCTAssertEqual(result as? String, "new")
    }

    func testUnregisterRemovesHandler() {
        let core = BridgeCore()
        core.register("temp") { call in call.reply(true) }
        core.unregister("temp")
        XCTAssertFalse(core.registeredMethods.contains("temp"))
        var rejectedWhy: String?
        core.dispatch(method: "temp", args: [], idNum: 1,
                      reply: { _, _ in XCTFail("unexpected reply") },
                      reject: { _, why in rejectedWhy = why })
        XCTAssertNotNil(rejectedWhy)
    }

    func testAsyncReplyFromBackgroundQueue() {
        let core = BridgeCore()
        core.register("async") { call in
            DispatchQueue.global().async {
                call.reply("later")
            }
        }
        let exp = expectation(description: "async reply")
        var result: Any?
        core.dispatch(method: "async", args: [], idNum: 1,
                      reply: { _, obj in result = obj; exp.fulfill() },
                      reject: { _, _ in XCTFail("unexpected reject") })
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(result as? String, "later")
    }

    func testEmitRoutesToEmitter() {
        let core = BridgeCore()
        var gotChannel: String?
        var gotPayload: [String: Any]?
        core.emitter = { channel, payload in
            gotChannel = channel
            gotPayload = payload as? [String: Any]
        }
        core.emit("_pushEq", ["enabled": true, "preset": "平坦"])
        XCTAssertEqual(gotChannel, "_pushEq")
        XCTAssertEqual(gotPayload?["enabled"] as? Bool, true)
    }

    func testRegisteredMethodsTracksSurface() {
        let core = BridgeCore()
        core.register("a") { _ in }
        core.register("b") { _ in }
        core.register("c") { _ in }
        core.unregister("b")
        XCTAssertEqual(core.registeredMethods, ["a", "c"])
    }

    // ── fp 层注册面：与 BridgeScript.swift 的 JS API 一一对应 ──

    func testFPBridgeRegistersFullSurface() {
        let core = BridgeCore()
        FPBridge.registerAll(into: core)
        let expected: Set<String> = [
            // settings / setup
            "isSetup", "getSetting", "setSetting",
            // equalizer
            "getEqState", "setEq",
            // tracks
            "getTracks", "getTrack", "updateTrack", "deleteTrack",
            "getTrackCount", "getTotalDuration",
            // playback history
            "playStart", "playEnd",
            // stats
            "getPlayHistory", "getStats",
            // cover
            "getCover",
            // network
            "httpGetJson", "httpGetBase64",
            // playlists
            "getPlaylists", "createPlaylist", "renamePlaylist", "deletePlaylist",
            "getPlaylistTracks", "addToPlaylist", "addTracksToPlaylist",
            "setPlaylistTracks", "removeFromPlaylist",
            // lrc
            "getLrc", "setLrc", "saveLrcContent", "saveCover", "removeLrc",
            // import
            "scanDirectory", "importFiles",
            // platform-delegated from fp layer
            "uploadLrc",
        ]
        XCTAssertEqual(core.registeredMethods, expected)
    }

    func testPlatformRegisterAllAddsPlatformMethods() {
        let core = BridgeCore()
        let platform = IPadPlatformBridge()
        platform.registerAll(into: core)
        let expected: Set<String> = [
            "getPlatform", "__dragStart", "openEqWindow", "finishOnboarding",
            "setAppearance", "resetDatabase", "sendPlaybackState",
            "getLoginItemSettings", "setLoginItemSettings", "listPlugins",
            "readPluginFile", "openPluginsDir", "uninstallPlugin",
            "importDialog", "selectLibraryDir",
        ]
        XCTAssertEqual(core.registeredMethods, expected)
    }

    func testBootstrapComposesBothLayers() {
        // Full assembly: fp + platform + emitter, exactly as the app wires it.
        AppContext.shared.platformBridge = IPadPlatformBridge()
        defer { AppContext.shared.platformBridge = nil }
        AppContext.shared.bridgeCore = nil

        let core = BridgeBootstrap.install()
        XCTAssertTrue(core === BridgeBootstrap.install(), "bootstrap must be idempotent")

        // cross-platform methods present
        XCTAssertTrue(core.registeredMethods.contains("getTracks"))
        XCTAssertTrue(core.registeredMethods.contains("setEq"))
        // platform methods present (iPad registers them)
        XCTAssertTrue(core.registeredMethods.contains("getPlatform"))
        XCTAssertTrue(core.registeredMethods.contains("importDialog"))
        // emitter wired (would otherwise be nil)
        XCTAssertNotNil(core.emitter)

        // getPlatform answers through the real platform layer
        var platformName: String?
        core.dispatch(method: "getPlatform", args: [], idNum: 1,
                      reply: { _, obj in platformName = obj as? String },
                      reject: { _, _ in XCTFail("unexpected reject") })
        XCTAssertEqual(platformName, "ios")

        // iPad policy: copy-only import modes
        XCTAssertEqual(AppContext.shared.platformBridge?.allowedImportModes, ["copy"])

        AppContext.shared.bridgeCore = nil
    }
}
