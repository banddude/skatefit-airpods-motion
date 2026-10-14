import XCTest
@testable import SkateMotion

final class RunnerEnhancementTests: XCTestCase {
    func testFifteenStageIdentifiersPreserveLegacyWorlds() {
        XCTAssertEqual(RunnerCourse.catalog.count, 15)
        XCTAssertEqual(RunnerCourse.get(1).name, "First Light")
        XCTAssertEqual(RunnerCourse.get(2).name, "Concrete Dreams")
        XCTAssertEqual(RunnerCourse.get(3).name, "Neon Transit")
        XCTAssertEqual(RunnerCourse.get(4).name, "Skyline Transfer")
        XCTAssertEqual(RunnerCourse.get(5).name, "The Impossible Line")
        XCTAssertEqual(RunnerCourse.playOrder, [1,6,7,2,8,9,3,10,11,4,12,13,5,14,15])
        XCTAssertEqual(RunnerCourse.next(after: 7)?.id, 2)
        XCTAssertNil(RunnerCourse.next(after: 15))
        let found = Set(RunnerCourse.catalog.map(\.id))
        XCTAssertEqual(found, Set(1...15))
    }

    func testDistinctWorldMechanicsAppearInAuthoredCourses() {
        let neon = RunnerCourse.catalog.filter { $0.worldNumber == 3 }
        XCTAssertTrue(neon.allSatisfy { $0.features.contains { $0.kind == .pulseGate } })
        let clouds = RunnerCourse.catalog.filter { $0.worldNumber >= 4 }
        XCTAssertTrue(clouds.allSatisfy { course in
            course.features.contains { $0.kind == .springPad } &&
            course.features.contains { $0.kind == .longGap }
        })
        for course in RunnerCourse.catalog {
            let hazards = course.features.filter { $0.kind.isHazard }
            for pair in zip(hazards, hazards.dropFirst()) {
                // Chasms following spring pads are isolated from all other
                // obstacles by a large safe landing space.
                XCTAssertGreaterThan(pair.1.at - pair.0.end, 10,
                                     "Bad hazard separation in \(course.name)")
            }
            XCTAssertEqual(course.features.filter { $0.kind == .checkpoint }.count, 1)
        }
    }

    func testAirPodsPitchUsesHysteresisAndReturnsNeutralAfterDropout() {
        var filter = RunnerMotionAdapter()
        XCTAssertEqual(filter.accept(pitch: 10.0), RunnerInput())
        XCTAssertEqual(filter.accept(pitch: 11.5), RunnerInput(manual: true))
        XCTAssertEqual(filter.accept(pitch: 9.0), RunnerInput(manual: true))
        XCTAssertEqual(filter.accept(pitch: 6.9), RunnerInput())
        XCTAssertEqual(filter.accept(pitch: -11.5), RunnerInput(noseManual: true))
        XCTAssertEqual(filter.accept(pitch: -9.0), RunnerInput(noseManual: true))
        XCTAssertEqual(filter.accept(pitch: -6.9), RunnerInput())
        XCTAssertEqual(filter.accept(pitch: .nan), RunnerInput())
        XCTAssertEqual(filter.accept(pitch: -13), RunnerInput(noseManual: true))
        XCTAssertEqual(filter.accept(pitch: nil), RunnerInput())
    }

    func testAirPodGameMotionRejectsStaleSamples() {
        XCTAssertFalse(RunnerMotionFreshness.isReady(lastSample: nil, now: 100))
        XCTAssertFalse(RunnerMotionFreshness.isReady(lastSample: 101, now: 100))
        XCTAssertTrue(RunnerMotionFreshness.isReady(lastSample: 99.40, now: 100))
        XCTAssertFalse(RunnerMotionFreshness.isReady(lastSample: 99.20, now: 100))
        XCTAssertFalse(RunnerMotionFreshness.isReady(lastSample: .nan, now: 100))
    }

    func testLaunchPadAutomaticallyLaunchesOverLongGap() {
        let game = RunnerEngine()
        game.reset(course: 4)
        guard let pad = game.course.features.first(where: { $0.kind == .springPad }) else {
            XCTFail("Missing pad")
            return
        }
        while game.distance < pad.at + 0.4 && !game.gameOver {
            game.advance(dt: 1.0 / 120, input: RunnerInput())
        }
        XCTAssertTrue(game.features.contains { $0.id == pad.id && $0.resolved })
        XCTAssertGreaterThan(game.height, 0.0)
        XCTAssertGreaterThan(game.velocity, 5.0)
    }

    func testNeonGateCyclesBetweenOpenAndClosed() {
        let game = RunnerEngine()
        game.reset(course: 3)
        guard let gate = game.course.features.first(where: { $0.kind == .pulseGate }) else {
            XCTFail("Missing pulse gate")
            return
        }
        let before = game.pulseGateActive(gate)
        for _ in 0..<114 { game.advance(dt: 1.0 / 120, input: RunnerInput()) }
        XCTAssertNotEqual(before, game.pulseGateActive(gate))
    }

    func testCheckpointRewindCannotFakePerfectNoHitResult() {
        let game = RunnerEngine()
        // The engine permits a checkpoint retry only after reaching one.
        // Simulate sufficient time while avoiding the most dangerous hazards.
        var steps = 0
        while game.checkpointDistance == 0 && !game.gameOver && steps < 15000 {
            let d = game.distance
            let obstacle = game.course.features.first {
                $0.kind.isHazard && $0.at > d - 0.3 && $0.at < d + 7
            }
            let manual = obstacle?.kind == .gap || obstacle?.kind == .barrier
            let nose = obstacle?.kind == .overhead || obstacle?.kind == .pulseGate
            game.advance(dt: 1.0 / 120, input: RunnerInput(
                manual: manual && d >= (obstacle?.at ?? 0) - 1.3,
                noseManual: nose && d >= (obstacle?.at ?? 0) - 0.9))
            steps += 1
        }
        XCTAssertGreaterThan(game.checkpointDistance, 0)
        game.retryCheckpoint()
        XCTAssertEqual(game.checkpointRetries, 1)
        XCTAssertFalse(game.noHit)
    }

    func testBeta11SavedProgressUnlocksOldAndNewCourses() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skatefit-expansion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunnerProgressStore(directory: directory)
        func finish(_ id: Int) {
            store.record(RunnerCompletion(course: id, score: 1000, seconds: 90,
                                          stars: 2, pickups: 7, manualLines: 2,
                                          noseLines: 1, clean: true), mode: .touch)
        }
        finish(1)
        XCTAssertTrue(store.career.isUnlocked(RunnerCourse.get(2)))
        XCTAssertTrue(store.career.isUnlocked(RunnerCourse.get(6)))
        XCTAssertFalse(store.career.isUnlocked(RunnerCourse.get(7)))
        finish(6)
        XCTAssertTrue(store.career.isUnlocked(RunnerCourse.get(7)))
        XCTAssertEqual(store.career.highestUnlocked, 2)
        let restored = RunnerProgressStore(directory: directory)
        XCTAssertEqual(restored.career.records[1]?.bestStars, 2)
        XCTAssertTrue(restored.career.isUnlocked(RunnerCourse.get(7)))
        XCTAssertNil(restored.saveError)
    }
}
