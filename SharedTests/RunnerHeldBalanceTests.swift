import XCTest
#if canImport(SkateMotion)
@testable import SkateMotion
#elseif canImport(SkateMotionTV)
@testable import SkateMotionTV
#else
@testable import SkateFitCore
#endif

/// The same specification is compiled into the iPhone, tvOS, and macOS
/// harness. Game altitude is a balance mechanic, never real board height.
final class RunnerHeldBalanceTests: XCTestCase {
    private func step(_ engine: RunnerEngine, seconds: Double,
                      input: RunnerInput, fps: Int = 120) {
        for _ in 0..<Int((seconds * Double(fps)).rounded()) {
            engine.advance(dt: 1.0 / Double(fps), input: input)
        }
    }

    func testTenSecondManualHoldsAltitudeWithoutRejumpOrTimeout() {
        let engine = RunnerEngine()
        step(engine, seconds: 1, input: RunnerInput(manual: true))
        let jumps = engine.eventRevision
        step(engine, seconds: 5, input: RunnerInput(manual: true))
        XCTAssertEqual(engine.eventRevision, jumps, "The hold must not repeatedly fire jumps")
        step(engine, seconds: 4, input: RunnerInput(manual: true))
        XCTAssertFalse(engine.gameOver)
        XCTAssertEqual(engine.height, RunnerEngine.manualHoldHeight, accuracy: 0.0001)
        XCTAssertEqual(engine.velocity, 0, accuracy: 0.0001)
        XCTAssertTrue(engine.manualing)
        XCTAssertFalse(engine.crouching)
    }

    func testLevelBoardReleasesElevationImmediatelyAndLands() {
        let engine = RunnerEngine()
        step(engine, seconds: 2, input: RunnerInput(manual: true))
        let height = engine.height
        engine.advance(dt: 1.0 / 120, input: RunnerInput())
        XCTAssertFalse(engine.manualing)
        XCTAssertLessThan(engine.height, height)
        XCTAssertLessThan(engine.velocity, 0)
        step(engine, seconds: 1, input: RunnerInput())
        XCTAssertEqual(engine.height, 0)
        XCTAssertEqual(engine.velocity, 0)
        XCTAssertFalse(engine.crouching)
    }

    func testNoseManualCancelsAirborneHoldAndStaysLowUntilReleased() {
        let engine = RunnerEngine()
        step(engine, seconds: 1, input: RunnerInput(manual: true))
        engine.advance(dt: 1.0 / 120, input: RunnerInput(noseManual: true))
        XCTAssertTrue(engine.crouching, "Duck is active immediately, even when initially airborne")
        XCTAssertFalse(engine.manualing)
        XCTAssertLessThan(engine.height, RunnerEngine.manualHoldHeight)
        step(engine, seconds: 0.2, input: RunnerInput(noseManual: true))
        XCTAssertEqual(engine.height, 0)
        step(engine, seconds: 4, input: RunnerInput(noseManual: true))
        XCTAssertTrue(engine.crouching)
        XCTAssertEqual(engine.height, 0)
        engine.advance(dt: 1.0 / 120, input: RunnerInput())
        XCTAssertFalse(engine.crouching)
        XCTAssertEqual(engine.height, 0)
    }

    func testConflictingButtonsAreNeutralAndDoNotHoverAndDuckTogether() {
        let engine = RunnerEngine()
        step(engine, seconds: 1, input: RunnerInput(manual: true))
        engine.advance(dt: 0.05, input: RunnerInput(manual: true, noseManual: true))
        XCTAssertFalse(engine.manualing)
        XCTAssertFalse(engine.crouching)
        XCTAssertLessThan(engine.height, RunnerEngine.manualHoldHeight)
    }

    func testContinuousControlsAreEquivalentAt30_60_120FPS() {
        let engines = [30, 60, 120].map { fps -> RunnerEngine in
            let engine = RunnerEngine()
            step(engine, seconds: 2, input: RunnerInput(manual: true), fps: fps)
            step(engine, seconds: 0.2, input: RunnerInput(), fps: fps)
            step(engine, seconds: 2, input: RunnerInput(noseManual: true), fps: fps)
            step(engine, seconds: 1, input: RunnerInput(manual: true), fps: fps)
            return engine
        }
        for engine in engines.dropFirst() {
            XCTAssertEqual(engine.height, engines[0].height, accuracy: 0.0001)
            XCTAssertEqual(engine.velocity, engines[0].velocity, accuracy: 0.0001)
            XCTAssertEqual(engine.distance, engines[0].distance, accuracy: 0.0001)
            XCTAssertEqual(engine.manualing, engines[0].manualing)
            XCTAssertEqual(engine.crouching, engines[0].crouching)
        }
    }

    func testHeldNoseManualIsNeverLaunchedByASpringRamp() throws {
        let engine = RunnerEngine()
        engine.reset(course: 4)
        let ramp = try XCTUnwrap(engine.course.features.first { $0.kind == .springPad })
        while engine.distance < ramp.end + 0.4 && !engine.gameOver {
            engine.advance(dt: 1.0 / 120, input: RunnerInput(noseManual: true))
            XCTAssertTrue(engine.crouching)
            XCTAssertEqual(engine.height, 0)
        }
        XCTAssertGreaterThan(engine.distance, ramp.end)
    }

    func testAllFifteenCoursesRemainPerfectlyCompletableWithContinuousHolds() {
        for course in RunnerCourse.catalog {
            let engine = RunnerEngine()
            engine.reset(course: course.id)
            var steps = 0
            while !engine.gameOver && steps < 100_000 {
                let position = engine.distance
                var manual = false
                var nose = false
                for item in course.features where item.at < position + 7 && item.end > position - 1 {
                    switch item.kind {
                    case .gap, .barrier:
                        manual = manual || (position >= item.at - 1.3 && position <= item.end + 0.4)
                    case .overhead, .pulseGate, .noseLine:
                        nose = nose || (position >= item.at - 0.9 && position <= item.end + 0.4)
                    case .manualLine:
                        manual = manual || (position >= item.at - 1.3 && position <= item.end + 0.4)
                    default: break
                    }
                }
                engine.advance(dt: 1.0 / 120, input: RunnerInput(manual: manual, noseManual: nose))
                steps += 1
            }
            XCTAssertTrue(engine.won, "Stage \(course.id) failed at \(engine.distance)")
            XCTAssertEqual(engine.damageCount, 0, "Stage \(course.id) damage")
            XCTAssertEqual(engine.stars, 3, "Stage \(course.id) cannot earn three stars")
            XCTAssertGreaterThan(engine.manualLines, 0)
            XCTAssertGreaterThan(engine.noseLines, 0)
        }
    }
}
