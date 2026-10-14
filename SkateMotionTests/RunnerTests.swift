import XCTest
@testable import SkateMotion

final class RunnerTests: XCTestCase {
    func testManualRisingEdgeJumpsOnlyOnceWhileHeld() {
        let game = RunnerEngine()
        game.advance(dt: 1.0 / 30, pitch: 0)
        game.advance(dt: 1.0 / 30, pitch: 16)
        XCTAssertGreaterThan(game.height, 0)
        XCTAssertGreaterThan(game.velocity, 0)

        for _ in 0..<180 { game.advance(dt: 1.0 / 120, pitch: 16) }
        XCTAssertEqual(game.height, 0, accuracy: 0.0001)
        XCTAssertEqual(game.velocity, 0, accuracy: 0.0001)
    }

    func testNoseManualDucksAndReleases() {
        let game = RunnerEngine()
        game.advance(dt: 1.0 / 30, pitch: -16)
        XCTAssertTrue(game.crouching)
        game.advance(dt: 1.0 / 30, pitch: 0)
        XCTAssertFalse(game.crouching)
    }

    func testFixedStepIndependentOfFrameRate() {
        let engines = [RunnerEngine(), RunnerEngine(), RunnerEngine()]
        for _ in 0..<90 { engines[0].advance(dt: 1.0 / 30, pitch: 0) }
        for _ in 0..<180 { engines[1].advance(dt: 1.0 / 60, pitch: 0) }
        for _ in 0..<360 { engines[2].advance(dt: 1.0 / 120, pitch: 0) }
        for engine in engines.dropFirst() {
            XCTAssertEqual(engines[0].distance, engine.distance, accuracy: 0.000001)
            XCTAssertEqual(engines[0].elapsed, engine.elapsed, accuracy: 0.000001)
            XCTAssertEqual(engines[0].score, engine.score)
            XCTAssertEqual(engines[0].damageCount, engine.damageCount)
        }
    }

    func testFiveCoursesHaveUniqueLayoutsAndFinishLines() {
        XCTAssertEqual(RunnerCourse.catalog.count, 5)
        for course in RunnerCourse.catalog {
            let game = RunnerEngine()
            game.reset(course: course.id)
            XCTAssertEqual(game.level, course.id)
            XCTAssertGreaterThan(game.courseLength, 100)
            XCTAssertTrue(Set(course.features.map(\.id)).count == course.features.count)
            XCTAssertTrue(course.features.contains { $0.kind == .manualLine })
            XCTAssertTrue(course.features.contains { $0.kind == .noseLine })
            XCTAssertTrue(course.features.contains { $0.kind == .checkpoint })
            XCTAssertFalse(game.gameOver)
        }
        XCTAssertGreaterThan(RunnerCourse.catalog[0].length /
                             RunnerCourse.catalog[0].speed, 150)
    }

    func testJumpClearsFirstGapWhenTimedCorrectly() {
        let game = RunnerEngine()
        while game.distance < 36 && !game.gameOver {
            let d = game.distance
            game.advance(dt: 1.0 / 120,
                         input: RunnerInput(manual: d >= 30.8 && d < 34.5))
        }
        XCTAssertEqual(game.damageCount, 0)
        XCTAssertGreaterThan(game.score, 0)
        XCTAssertGreaterThan(game.lives, 0)
    }

    func testMissedGapDamagesOnlyOnceAndResetsCombo() {
        let game = RunnerEngine()
        while game.distance < 37 && !game.gameOver {
            game.advance(dt: 1.0 / 120, pitch: 0)
        }
        XCTAssertEqual(game.damageCount, 1)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.combo, 0)
    }

    func testTouchControlsCollectStarsAndTrackBothManualTypes() {
        let game = RunnerEngine()
        while game.distance < 82 && !game.gameOver {
            let d = game.distance
            let manual = (d >= 30.8 && d < 34.5) ||
                         (d >= 43.8 && d < 47.8) ||
                         (d >= 67.5 && d < 78)
            let nose = d >= 58.3 && d < 62
            game.advance(dt: 1.0 / 120,
                         input: RunnerInput(manual: manual, noseManual: nose))
        }
        XCTAssertFalse(game.gameOver)
        XCTAssertEqual(game.damageCount, 0)
        XCTAssertGreaterThanOrEqual(game.pickups, 2)
        XCTAssertGreaterThanOrEqual(game.manualLines, 1)
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
        XCTAssertEqual(game.pickups, 0)
        XCTAssertEqual(game.damageCount, 0)
    }

    func testEveryCourseHasACompletePerfectRunTrace() {
        // A deterministic trace proves that all obstacles are beatable with
        // a real input window. This does not claim that human timing is easy.
        for course in RunnerCourse.catalog {
            let game = RunnerEngine()
            game.reset(course: course.id)
            var steps = 0
            while !game.gameOver && steps < 100_000 {
                let d = game.distance
                var manual = false
                var nose = false
                for item in course.features where item.at < d + 7 &&
                            item.end > d - 1 {
                    switch item.kind {
                    case .gap, .barrier:
                        manual = manual ||
                            (d >= item.at - 1.3 && d <= item.end + 0.4)
                    case .overhead:
                        nose = nose ||
                            (d >= item.at - 0.9 && d <= item.end + 0.4)
                    case .manualLine:
                        manual = manual ||
                            (d >= item.at - 5.5 && d <= item.end + 0.4)
                    case .noseLine:
                        nose = nose ||
                            (d >= item.at - 0.9 && d <= item.end + 0.4)
                    default: break
                    }
                }
                game.advance(dt: 1.0 / 120,
                             input: RunnerInput(manual: manual, noseManual: nose))
                steps += 1
            }
            XCTAssertTrue(game.won, "World \(course.id) cannot be completed. \(game.message) at \(game.distance)")
            XCTAssertEqual(game.damageCount, 0, "World \(course.id) has an unfair hazard")
            XCTAssertEqual(game.stars, 3, "World \(course.id) cannot earn all three stars")
            XCTAssertGreaterThan(game.manualLines, 0)
            XCTAssertGreaterThan(game.noseLines, 0)
        }
    }

    func testLargeFrameStallCannotSkipWholeCourse() {
        let game = RunnerEngine()
        game.advance(dt: 500, pitch: 0)
        XCTAssertLessThan(game.distance, 1)
    }
}

final class RunnerProgressTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skatefit-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func completion(course: Int = 1, score: Int = 1500,
                            stars: Int = 3, seconds: Double = 86) -> RunnerCompletion {
        RunnerCompletion(course: course, score: score, seconds: seconds,
                         stars: stars, pickups: 9, manualLines: 2,
                         noseLines: 1, clean: true)
    }

    func testOfflineCareerPersistsAndUnlocksWorldAndDeck() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let progress = RunnerProgressStore(directory: folder)
        XCTAssertEqual(progress.career.highestUnlocked, 1)
        progress.record(completion(), mode: .touch)
        XCTAssertNil(progress.saveError)
        XCTAssertEqual(progress.career.totalStars, 3)
        XCTAssertEqual(progress.career.highestUnlocked, 2)
        progress.chooseDeck("Sunset")
        let restored = RunnerProgressStore(directory: folder)
        XCTAssertEqual(restored.career.selectedDeck, "Sunset")
        XCTAssertEqual(restored.career.touchRuns, 1)
        XCTAssertEqual(restored.career.records[1]?.bestScore, 1500)
    }

    func testBestRecordsNeverRegress() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let progress = RunnerProgressStore(directory: folder)
        progress.record(completion(score: 2300, stars: 3, seconds: 70), mode: .touch)
        progress.record(completion(score: 800, stars: 1, seconds: 100), mode: .motion)
        XCTAssertEqual(progress.career.records[1]?.bestScore, 2300)
        XCTAssertEqual(progress.career.records[1]?.bestTime, 70)
        XCTAssertEqual(progress.career.records[1]?.bestStars, 3)
        XCTAssertEqual(progress.career.motionControlledRuns, 1)
        XCTAssertEqual(progress.career.completedRuns, 2)
    }

    func testRecoversValidBackupAfterCorruptPrimary() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let progress = RunnerProgressStore(directory: folder)
        progress.record(completion(), mode: .touch)
        progress.record(completion(course: 2), mode: .touch)
        try Data("corrupted".utf8).write(to: progress.saveURL)
        let restored = RunnerProgressStore(directory: folder)
        XCTAssertTrue(restored.recoveredFromBackup)
        XCTAssertEqual(restored.career.records[1]?.bestStars, 3)
        XCTAssertNil(restored.career.records[2])
    }

    func testRejectsInvalidCompletionAndLockedCosmetic() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let progress = RunnerProgressStore(directory: folder)
        progress.record(completion(course: 7), mode: .touch)
        progress.chooseDeck("Gold")
        XCTAssertEqual(progress.career.completedRuns, 0)
        XCTAssertEqual(progress.career.selectedDeck, "Mint")
    }
}
