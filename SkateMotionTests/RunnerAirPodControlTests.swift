import XCTest
@testable import SkateMotion

/// Regression: the AirPod can be recording training scores while the runner
/// silently stays in legacy Touch mode. Make the selected game source explicit.
final class RunnerAirPodControlTests: XCTestCase {
    func testAutoUsesLiveBoardWheneverReady() {
        XCTAssertEqual(RunnerControlMode.automatic.resolvedSource(sensorReady: true),
                       .motion)
        XCTAssertEqual(RunnerControlMode.automatic.resolvedSource(sensorReady: false),
                       .touch)
        XCTAssertEqual(RunnerControlMode.touch.resolvedSource(sensorReady: true),
                       .touch)
        XCTAssertNil(RunnerControlMode.motion.resolvedSource(sensorReady: false))
        XCTAssertEqual(RunnerControlMode.motion.resolvedSource(sensorReady: true),
                       .motion)
    }

    func testAirPodsDoNotAutoRunOrEarnScoreUntilBoardActuallyTilts() {
        let game = RunnerEngine()
        var controller = RunnerMotionAdapter()
        for _ in 0..<120 {
            let neutral = controller.accept(pitch: 0, engagementDegrees: 7)
            XCTAssertFalse(RunnerStartGate.canBegin(source: .motion, input: neutral))
            // A sensor-armed screen must not advance the engine.
        }
        XCTAssertEqual(game.distance, 0, accuracy: 0.0001)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.pickups, 0)
        let firstTilt = controller.accept(pitch: 8.5, engagementDegrees: 7)
        XCTAssertTrue(RunnerStartGate.canBegin(source: .motion, input: firstTilt))
        XCTAssertTrue(firstTilt.manual)
        game.advance(dt: 1.0 / 30, input: firstTilt)
        XCTAssertGreaterThan(game.distance, 0)
        XCTAssertGreaterThan(game.height, 0)
    }

    func testAdaptiveTiltThresholdTracksManualPracticeSettings() {
        var filter = RunnerMotionAdapter()
        XCTAssertEqual(filter.accept(pitch: 6.5, engagementDegrees: 7),
                       RunnerInput())
        XCTAssertEqual(filter.accept(pitch: 7.5, engagementDegrees: 7),
                       RunnerInput(manual: true))
        XCTAssertEqual(filter.accept(pitch: 5.0, engagementDegrees: 7),
                       RunnerInput(manual: true))
        XCTAssertEqual(filter.accept(pitch: 3.0, engagementDegrees: 7),
                       RunnerInput())
        XCTAssertEqual(filter.accept(pitch: -7.5, engagementDegrees: 7),
                       RunnerInput(noseManual: true))
        XCTAssertEqual(filter.accept(pitch: 0.0, engagementDegrees: 7),
                       RunnerInput())
    }

    func testInvertedOrInvalidBoardCannotTriggerPopOrDuck() {
        var controller = RunnerMotionAdapter()
        XCTAssertEqual(controller.accept(pitch: 19, engagementDegrees: 7),
                       RunnerInput(manual: true))
        XCTAssertEqual(controller.accept(pitch: 21, engagementDegrees: 7,
                                         allowed: false), RunnerInput())
        XCTAssertEqual(controller.accept(pitch: -.infinity,
                                         engagementDegrees: 7), RunnerInput())
        XCTAssertEqual(controller.accept(pitch: nil, engagementDegrees: 7),
                       RunnerInput())
        XCTAssertEqual(controller.accept(pitch: -14, engagementDegrees: 7,
                                         allowed: false), RunnerInput())
    }

    func testSensorPitchControlsJumpAndDuckInSameEngine() {
        let game = RunnerEngine()
        var adapter = RunnerMotionAdapter()
        let manual = adapter.accept(pitch: 13, engagementDegrees: 7)
        game.advance(dt: 0.035, input: manual)
        XCTAssertGreaterThan(game.height, 0)
        for _ in 0..<160 {
            game.advance(dt: 1.0 / 120, input: adapter.accept(pitch: 0))
        }
        XCTAssertEqual(game.height, 0, accuracy: 0.0001)
        let noseManual = adapter.accept(pitch: -13, engagementDegrees: 7)
        XCTAssertTrue(noseManual.noseManual)
        game.advance(dt: 0.035, input: noseManual)
        XCTAssertTrue(game.crouching)
        XCTAssertFalse(game.manualing)
    }

    func testTouchCanBeginImmediatelyAndSavedSourceIsAccurate() {
        XCTAssertTrue(RunnerStartGate.canBegin(source: .touch, input: RunnerInput()))
        XCTAssertEqual(RunnerControlSource.touch.savedRunMode, .touch)
        XCTAssertEqual(RunnerControlSource.motion.savedRunMode, .motion)
        XCTAssertFalse(RunnerStartGate.canBegin(source: .motion, input: RunnerInput()))
    }
}
