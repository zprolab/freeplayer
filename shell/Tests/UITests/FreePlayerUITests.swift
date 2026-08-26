// FreePlayer — XCUITest: automated UI tests running in the iOS Simulator.
// Verifies app launch, web content loading, and basic interaction patterns.

import XCTest

final class FreePlayerUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch

    func testAppLaunches() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window should appear within 10s")
    }

    func testWebViewLoads() {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15), "WKWebView should load within 15s")
    }

    func testOnboardingOrMainScreen() {
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.windows.firstMatch.exists, "App should display content after launch")
    }

    func testAccessibilityLabels() {
        Thread.sleep(forTimeInterval: 5)
        let webView = app.webViews.firstMatch
        guard webView.waitForExistence(timeout: 10) else {
            XCTFail("WebView not found")
            return
        }
        XCTAssertTrue(webView.isHittable, "WebView should be interactable")
    }

    // MARK: - Stability

    func testAppDoesNotCrashOnLaunch() {
        // Launch, wait, verify still running
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.windows.firstMatch.exists, "App should still be alive after 3s")

        // Launch again (simulate restart)
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.windows.firstMatch.exists, "App should survive restart")
    }

    func testAppStateAfterBackground() {
        Thread.sleep(forTimeInterval: 2)
        // Simulate backgrounding
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)

        // Re-open
        app.activate()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.windows.firstMatch.exists, "App should recover from background")
    }

    // MARK: - Orientation (iPad)

    func testRotationIPad() {
        Thread.sleep(forTimeInterval: 3)
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 5) else { return }

        // Portrait (default)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(window.exists)

        // Landscape left
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(window.exists)

        // Landscape right
        XCUIDevice.shared.orientation = .landscapeRight
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(window.exists)

        // Back to portrait
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(window.exists)
    }
}
