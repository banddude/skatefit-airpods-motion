import XCTest

final class RunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testManualCoachOpensBeforeGameplayAndOffersCalibration() throws {
        let app = XCUIApplication()
        app.launch()
        let coach = app.buttons["openManualBalanceCoach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 15),
                      "Manual Balance Coach should be featured above the game")
        coach.tap()
        XCTAssertTrue(app.staticTexts["MANUAL BALANCE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["START PRACTICE"].exists)
        XCTAssertTrue(app.buttons["OPEN BOARD CALIBRATION"].exists)
        XCTAssertTrue(app.staticTexts["TRAINING GOAL"].exists)
        let back = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Back to SkateFit")).firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(app.buttons["openManualBalanceCoach"].waitForExistence(timeout: 5))
    }

    func testManualCoachUsesSensorsAndNoCameraActions() throws {
        let app = XCUIApplication()
        app.launch()
        let coach = app.buttons["openManualBalanceCoach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 15))
        coach.tap()
        XCTAssertTrue(app.staticTexts["MANUAL BALANCE"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["openBoardSpaceLab"].exists)
        XCTAssertTrue(app.staticTexts["TRAINING GOAL"].exists)
    }

    func testGameClearlyShowsMissingBoardAndProvidesCalibrationRoute() throws {
        let app = XCUIApplication()
        app.launch()

        let setup = app.buttons["connectBoardAirPod"]
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["BOARD INPUT NOT ACTIVE"].exists)
        if !setup.isHittable { app.swipeUp() }
        XCTAssertTrue(setup.isHittable)
        setup.tap()
        XCTAssertTrue(app.staticTexts["Motion Lab"].waitForExistence(timeout: 7))
        let back = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Back to game")).firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(app.buttons["openManualBalanceCoach"].waitForExistence(timeout: 7))
    }

    func testAppleTVCompanionDoesNotDiscoverUntilAsked() throws {
        let app = XCUIApplication()
        app.launch()
        let tv = app.buttons["connectAppleTV"]
        XCTAssertTrue(tv.waitForExistence(timeout: 15))
        tv.tap()
        XCTAssertTrue(app.staticTexts["SKATEFIT ON APPLE TV"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["findAppleTV"].exists)
        XCTAssertTrue(app.staticTexts["TV sharing off"].exists)
        XCTAssertFalse(app.buttons["disconnectTV"].exists)
    }

    func testDropInPauseResumeAndExit() throws {
        let app = XCUIApplication()
        app.launch()

        let dropIn = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "DROP IN")).firstMatch
        XCTAssertTrue(dropIn.waitForExistence(timeout: 15), "Home screen must show Drop In")
        dropIn.tap()

        XCTAssertTrue(app.staticTexts["UP NEXT"].waitForExistence(timeout: 7))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Flow meter")).firstMatch.exists)

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.exists)
        pause.tap()
        XCTAssertTrue(app.staticTexts["PAUSED"].waitForExistence(timeout: 5))

        let resume = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "RESUME")).firstMatch
        XCTAssertTrue(resume.exists)
        resume.tap()
        XCTAssertTrue(app.staticTexts["UP NEXT"].waitForExistence(timeout: 5))

        let exit = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Exit")).firstMatch
        XCTAssertTrue(exit.exists)
        exit.tap()
        XCTAssertTrue(dropIn.waitForExistence(timeout: 5))
    }

    func testWorldSelectionShowsFifteenStagesAndLocks() throws {
        let app = XCUIApplication()
        app.launch()
        let worlds = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Worlds")).firstMatch
        XCTAssertTrue(worlds.waitForExistence(timeout: 15))
        worlds.tap()

        XCTAssertTrue(app.staticTexts["15 stages. Five worlds."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "First Light")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Back Alley Balance")).firstMatch.exists)

        let locked = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Back Alley Balance")).firstMatch
        XCTAssertTrue(locked.exists)
        XCTAssertFalse(locked.isEnabled, "Subsequent stages should start locked")

        let first = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "First Light")).firstMatch
        first.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "DROP IN")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSettingsAndMotionLabRemainReachable() throws {
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["Game settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        XCTAssertTrue(app.staticTexts["Your ride, your rules."].waitForExistence(timeout: 5))
        let lab = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Open recorder and 3D calibration")).firstMatch
        XCTAssertTrue(lab.exists)
        lab.tap()

        XCTAssertTrue(app.staticTexts["Motion Lab"].waitForExistence(timeout: 5))
        let back = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Back to game")).firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "DROP IN")).firstMatch.waitForExistence(timeout: 5))
    }
}
