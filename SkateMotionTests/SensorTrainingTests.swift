import XCTest
@testable import SkateMotion

final class BoardSensorHealthTests: XCTestCase {
    private func sample(source: MotionSource = .headphone, side: String = "left",
                        host: Double, device: Double,
                        gravity: Vector3 = Vector3(x: 0, y: 0, z: -1),
                        acceleration: Vector3 = .zero,
                        rotation: Vector3 = .zero) -> MotionSample {
        MotionSample(source: source, sensorLocation: side,
                     hostUptime: host, deviceTimestamp: device,
                     gravity: gravity, acceleration: acceleration,
                     rotationRate: rotation, quaternion: .identity)
    }

    func testReportsSelectedAirPodAndTrueSensorRate() {
        var quality = BoardSensorHealth()
        for step in 0..<100 {
            XCTAssertTrue(quality.accept(
                sample(host: 100 + Double(step)*0.020,
                       device: 50 + Double(step)*0.020),
                expectedSide: "left"))
        }
        let snapshot = quality.snapshot
        XCTAssertEqual(snapshot.accepted, 100)
        XCTAssertEqual(snapshot.rejected, 0)
        XCTAssertEqual(snapshot.sampleRateHz, 50, accuracy: 0.2)
        XCTAssertTrue(snapshot.usesDeviceTimestamps)
        XCTAssertEqual(snapshot.state(now: 101.99), "BOARD MOTION LIVE")
        XCTAssertEqual(snapshot.state(now: 105), "SENSOR STREAM LOST")
        XCTAssertFalse(snapshot.isFresh(now: 105))
    }

    func testRejectsPhoneOtherAirPodDuplicatesAndImpossibleReadings() {
        var quality = BoardSensorHealth()
        XCTAssertFalse(quality.accept(
            sample(source: .phone, host: 1, device: 1), expectedSide: "left"))
        XCTAssertFalse(quality.accept(
            sample(side: "right", host: 2, device: 2), expectedSide: "left"))
        XCTAssertFalse(quality.accept(
            sample(host: 3, device: 3, gravity: Vector3(x: .nan, y: 0, z: -1)),
            expectedSide: "left"))
        XCTAssertFalse(quality.accept(
            sample(host: 4, device: 4, gravity: Vector3(x: 0, y: 0, z: -2)),
            expectedSide: "left"))
        XCTAssertFalse(quality.accept(
            sample(host: 5, device: 5, acceleration: Vector3(x: 40, y: 0, z: 0)),
            expectedSide: "left"))
        XCTAssertTrue(quality.accept(sample(host: 6, device: 6), expectedSide: "left"))
        XCTAssertFalse(quality.accept(sample(host: 6.01, device: 6), expectedSide: "left"))
        XCTAssertTrue(quality.accept(sample(host: 6.03, device: 6.03), expectedSide: "left"))
        XCTAssertEqual(quality.snapshot.accepted, 2)
        XCTAssertEqual(quality.snapshot.rejected, 6)
        XCTAssertEqual(quality.snapshot.latestRejection, BoardSensorRejection.duplicate.rawValue)
    }

    func testRecordsDiscontinuitiesAndFreshnessRecovers() {
        var quality = BoardSensorHealth()
        XCTAssertTrue(quality.accept(sample(host: 100, device: 500), expectedSide: "left"))
        XCTAssertTrue(quality.accept(sample(host: 100.02, device: 500.02), expectedSide: "left"))
        XCTAssertTrue(quality.accept(sample(host: 101, device: 501), expectedSide: "left"))
        XCTAssertGreaterThan(quality.snapshot.interruptions, 0)
        XCTAssertTrue(quality.snapshot.isFresh(now: 101.2))
        XCTAssertFalse(quality.snapshot.isFresh(now: 102))
        XCTAssertTrue(quality.accept(sample(host: 102.05, device: 5), expectedSide: "left"))
        XCTAssertTrue(quality.snapshot.isFresh(now: 102.08))
        XCTAssertEqual(quality.snapshot.accepted, 4)
    }
}

final class ManualTrainingIntegrityTests: XCTestCase {
    private func calibration() -> BoardCalibration {
        var c = BoardCalibration()
        let radians = 0.46
        c.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1))
        c.set(.tailContact, gravity: Vector3(x: sin(radians), y: 0,
                                            z: -cos(radians)))
        c.set(.noseContact, gravity: Vector3(x: -sin(radians), y: 0,
                                            z: -cos(radians)))
        return c
    }

    private func feed(_ tracker: inout ManualBalanceTracker, at t: Double,
                      sensorTimestamp: Double? = nil, pitch: Double = 12,
                      roll: Double = 0, rotation: Vector3 = .zero) {
        let c = calibration()
        let x = sin(pitch * .pi / 180) * cos(roll * .pi / 180)
        let y = sin(roll * .pi / 180)
        let z = -cos(pitch * .pi / 180) * cos(roll * .pi / 180)
        let sample = MotionSample(
            source: .headphone, sensorLocation: "left",
            hostUptime: t, deviceTimestamp: sensorTimestamp ?? t,
            gravity: Vector3(x: x, y: y, z: z),
            acceleration: .zero, rotationRate: rotation)
        tracker.accept(sample, orientation: c.orientation(for: sample),
                       calibration: c)
    }

    func testFlatFrameImmediatelyEndsHoldAndDoesNotBridgeTime() {
        var tracker = ManualBalanceTracker()
        var t = 1.0
        for _ in 0..<26 {
            feed(&tracker, at: t)
            t += 0.025
        }
        XCTAssertGreaterThan(tracker.snapshot.currentHoldSeconds, 0.55)
        feed(&tracker, at: t, pitch: 0)
        let first = try? XCTUnwrap(tracker.snapshot.lastCompletedHold)
        XCTAssertEqual(first?.endedBy, .returnedFlat)
        XCTAssertEqual(tracker.snapshot.currentHoldSeconds, 0)
        XCTAssertEqual(tracker.attempts.count, 1)
        for i in 1...24 {
            feed(&tracker, at: t + Double(i) * 0.025)
        }
        XCTAssertLessThan(tracker.snapshot.currentHoldSeconds, 0.65)
        XCTAssertEqual(tracker.snapshot.manualAttempts, 2)
        XCTAssertEqual(tracker.attempts.count, 1)
        tracker.finish()
        XCTAssertEqual(tracker.attempts.count, 2)
        XCTAssertEqual(tracker.attempts[1].endedBy, .sessionEnded)
    }

    func testRapidSideTiltStopsHoldWithReasonAndPreservesBest() {
        var tracker = ManualBalanceTracker()
        for i in 0..<25 { feed(&tracker, at: 10+Double(i)*0.025) }
        let best = tracker.snapshot.longestManualSeconds
        feed(&tracker, at: 10.625, roll: 22)
        XCTAssertEqual(tracker.snapshot.currentHoldSeconds, 0)
        XCTAssertEqual(tracker.snapshot.lastCompletedHold?.endedBy, .sideways)
        XCTAssertEqual(tracker.snapshot.longestManualSeconds, best, accuracy: 0.001)
    }

    func testDeviceClockDrivesDurationDespiteCallbackJitter() {
        var tracker = ManualBalanceTracker()
        var host = 100.0
        for i in 0..<51 {
            host += i.isMultiple(of: 2) ? 0.010 : 0.037
            feed(&tracker, at: host, sensorTimestamp: 250 + Double(i)*0.025)
        }
        XCTAssertEqual(tracker.snapshot.currentHoldSeconds, 1.25, accuracy: 0.02)
        XCTAssertEqual(tracker.snapshot.manualAttempts, 1)
        tracker.interrupt()
        XCTAssertEqual(tracker.attempts.count, 1)
        XCTAssertEqual(tracker.attempts[0].endedBy, .sensorGap)
    }

    func testDuplicatedDeviceTimestampDoesNotExtendManualTime() {
        var tracker = ManualBalanceTracker()
        for i in 0..<20 {
            feed(&tracker, at: 50 + Double(i)*0.025,
                 sensorTimestamp: 90 + Double(i)*0.025)
        }
        let before = tracker.snapshot.longestManualSeconds
        feed(&tracker, at: 50.5, sensorTimestamp: 90.475)
        XCTAssertEqual(tracker.snapshot.longestManualSeconds, before,
                       accuracy: 0.0001)
        XCTAssertEqual(tracker.snapshot.currentHoldSeconds, 0)
    }

    func testNaNInputCannotContaminateStability() {
        var tracker = ManualBalanceTracker()
        for i in 0..<20 { feed(&tracker, at: 20 + Double(i)*0.025) }
        feed(&tracker, at: 20.5, rotation: Vector3(x: .nan, y: 0, z: 0))
        XCTAssertEqual(tracker.snapshot.currentHoldSeconds, 0)
        XCTAssertTrue(tracker.snapshot.stability.isFinite)
        XCTAssertEqual(tracker.snapshot.lastCompletedHold?.endedBy, .invalidSensor)
    }

    func testOldPracticeFilesDecodeAndKeepPersonalBests() throws {
        let oldRecord = SavedManualPractice(
            id: "beta13", finishedAt: Date(timeIntervalSince1970: 100),
            settings: ManualBalanceSettings(), bestManualSeconds: 3.5,
            bestNoseSeconds: 2.1, manualAttempts: 4, noseManualAttempts: 2,
            goalsReached: 1, averageStability: 88, upsideDownSamples: 0)
        let encoded = try JSONEncoder().encode(oldRecord)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self)
            .contains("\"attempts\""))
        let restored = try JSONDecoder().decode(SavedManualPractice.self, from: encoded)
        XCTAssertEqual(restored, oldRecord)
        XCTAssertEqual(restored.qualifiedHolds.count, 0)
        let goal = ManualPracticeInsights.recommendedGoal(
            for: .manual, sessions: [restored])
        XCTAssertEqual(goal, 5)
        XCTAssertEqual(ManualPracticeInsights.personalBest(
            for: .noseManual, sessions: [restored]), 2.1)
    }

    func testAttemptHistoryPersistsInNewRecord() throws {
        var tracker = ManualBalanceTracker()
        for i in 0..<45 { feed(&tracker, at: 5 + Double(i)*0.025) }
        tracker.finish()
        let saved = tracker.savedRecord(sessionID: "new")
        XCTAssertEqual(saved.qualifiedHolds.count, 1)
        XCTAssertTrue(saved.qualifiedHolds[0].averageStability.isFinite)
        XCTAssertGreaterThan(saved.qualifiedHolds[0].seconds, 1.0)
        let decoded = try JSONDecoder().decode(
            SavedManualPractice.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.qualifiedHolds, saved.qualifiedHolds)
        XCTAssertEqual(ManualPracticeInsights.recommendedGoal(
            for: .manual, sessions: [decoded]), 2)
    }
}
