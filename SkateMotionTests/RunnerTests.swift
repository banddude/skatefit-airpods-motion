import XCTest
@testable import SkateMotion

final class RunnerTests: XCTestCase {
    func testJumpOnManualRisingEdge() {
        let game = RunnerEngine()
        game.advance(dt: 1.0 / 30, pitch: 0)
        game.advance(dt: 1.0 / 30, pitch: 16)
        XCTAssertGreaterThan(game.height, 0)
        XCTAssertGreaterThan(game.velocity, 0)
    }

    func testNoseManualDucks() {
        let game = RunnerEngine()
        game.advance(dt: 1.0 / 30, pitch: -16)
        XCTAssertTrue(game.crouching)
        game.advance(dt: 1.0 / 30, pitch: 0)
        XCTAssertFalse(game.crouching)
    }

    func testFixedStepIndependentOfFrameRate() {
        let slow = RunnerEngine()
        let fast = RunnerEngine()
        for _ in 0..<30 { slow.advance(dt: 1.0 / 30, pitch: 0) }
        for _ in 0..<120 { fast.advance(dt: 1.0 / 120, pitch: 0) }
        XCTAssertEqual(slow.distance, fast.distance, accuracy: 0.00001)
    }

    func testFiveCoursesHaveFinishLines() {
        for course in 1...5 {
            let game = RunnerEngine()
            game.reset(course: course)
            XCTAssertEqual(game.level, course)
            XCTAssertGreaterThan(game.courseLength, 100)
            XCTAssertFalse(game.gameOver)
        }
    }

    func testResetClearsRunState() {
        let game = RunnerEngine()
        game.advance(dt: 0.05, pitch: 16)
        game.reset(course: 2)
        XCTAssertEqual(game.height, 0)
        XCTAssertEqual(game.distance, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.level, 2)
    }
}
