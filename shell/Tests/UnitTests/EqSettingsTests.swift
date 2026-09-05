// FreePlayer — XCTest round-trip tests for the EQ settings bridge helpers.
// The enable toggle once snapped back off because saveEq wrote "1"/"0"
// while eqStateDict compared against "true" — these tests pin the writer
// and reader to each other.

import XCTest
@testable import FreePlayer

final class EqSettingsTests: XCTestCase {

    private var tempDbPath: String!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fp_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: tmp.path, withIntermediateDirectories: true)
        tempDbPath = tmp.appendingPathComponent("config.db").path
        Database.open(tempDbPath)
    }

    override func tearDown() {
        Database.close()
        try? FileManager.default.removeItem(
            atPath: (tempDbPath as NSString).deletingLastPathComponent)
        super.tearDown()
    }

    private func eqState(afterSaving state: [String: Any]) -> [String: Any] {
        FPBridge.saveEq(state)
        return FPBridge.eqStateDict()
    }

    func testSaveThenReadBackRoundTrip() {
        let s = eqState(afterSaving: [
            "enabled": NSNumber(value: true),
            "preset": "Bass Boost",
            "gains": [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0].map { NSNumber(value: $0) },
        ])
        XCTAssertEqual(s["enabled"] as? Bool, true)
        XCTAssertEqual(s["preset"] as? String, "Bass Boost")
        XCTAssertEqual(
            (s["gains"] as? [NSNumber])?.map { $0.doubleValue },
            [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0])
    }

    func testDisabledRoundTrip() {
        let s = eqState(afterSaving: [
            "enabled": NSNumber(value: false),
            "preset": "Flat",
            "gains": [Double](repeating: 0, count: 10).map { NSNumber(value: $0) },
        ])
        XCTAssertEqual(s["enabled"] as? Bool, false)
    }

    func testLegacyTrueStillReadsAsEnabled() {
        // Older builds may have left "true" in the DB; the reader accepts it.
        Database.setSetting("eq.enabled", "true")
        XCTAssertEqual(FPBridge.eqStateDict()["enabled"] as? Bool, true)
    }

    func testDefaultsWhenUnset() {
        let s = FPBridge.eqStateDict()
        XCTAssertEqual(s["enabled"] as? Bool, false)
        XCTAssertEqual(s["preset"] as? String, "Flat")
        XCTAssertEqual((s["gains"] as? [NSNumber])?.count, 10)
    }
}
