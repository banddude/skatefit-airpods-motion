import XCTest

final class SkateTVUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testManualDashboardStartsWithoutNetworkOrCamera() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.staticTexts["MANUAL BALANCE"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["BOARD SENSOR NOT CONNECTED"].exists)
        XCTAssertFalse(app.staticTexts["tvPairingCode"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "SkateFit TV manual dashboard"; image.lifetime = .keepAlways
        add(image)
    }

    func testRemoteNavigatesToGameAndPauses() {
        let app = XCUIApplication(); app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.staticTexts["MANUAL BALANCE"].waitForExistence(timeout: 15))
        // Establish the top navigation row, then locate Play by visible focus.
        for _ in 0..<3 { remote.press(.up) }
        for _ in 0..<6 { remote.press(.left) }
        let play = app.buttons["tvPagePlay"]
        for _ in 0..<6 {
            if play.hasFocus { break }
            remote.press(.right)
        }
        XCTAssertTrue(play.hasFocus)
        remote.press(.select)
        let controller = app.buttons["tvPlayController"]
        XCTAssertTrue(controller.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if controller.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(controller.hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["REMOTE / CONTROLLER"].waitForExistence(timeout: 5))
        remote.press(.playPause)
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["tvPlayController"].waitForExistence(timeout: 5))
    }
}
