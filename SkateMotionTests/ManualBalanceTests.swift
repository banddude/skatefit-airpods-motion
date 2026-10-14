import XCTest
import simd
@testable import SkateMotion

final class BoardPoseTests: XCTestCase {
    private func calibration(withAttitude: Bool = true) -> BoardCalibration {
        var board = BoardCalibration()
        let contact = 0.46
        board.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1),
                  attitude: withAttitude ? .identity : nil)
        board.set(.tailContact, gravity: Vector3(x: sin(contact), y: 0, z: -cos(contact)))
        board.set(.noseContact, gravity: Vector3(x: -sin(contact), y: 0, z: -cos(contact)))
        XCTAssertTrue(board.isPhysicallyPlausible)
        return board
    }

    private func sample(rotation: simd_quatd, withQuaternion: Bool = true,
                        t: Double = 0) -> MotionSample {
        let g = rotation.inverse.act(SIMD3<Double>(0, 0, -1))
        return MotionSample(
            source: .headphone, sensorLocation: "left", hostUptime: t,
            deviceTimestamp: t,
            gravity: Vector3(x: g.x, y: g.y, z: g.z),
            acceleration: .zero, rotationRate: .zero,
            quaternion: withQuaternion ? Quaternion4(
                w: rotation.real, x: rotation.imag.x,
                y: rotation.imag.y, z: rotation.imag.z) : nil)
    }

    func testThreeHundredSixtyDegreeRollThroughUpsideDown() throws {
        let board = calibration()
        for degrees in stride(from: 0, through: 360, by: 45) {
            let radians = Double(degrees) * Double.pi / 180
            let q = simd_quatd(angle: radians, axis: SIMD3(1, 0, 0))
            let pose = try XCTUnwrap(board.orientation(for: sample(rotation: q)))
            let actual = try XCTUnwrap(pose.relativeQuaternion?.rotate(Vector3(x: 0, y: 1, z: 0)))
            // Original board Y corresponds to AirPod sensor +Z.
            // A true longitudinal flip is not representable as Euler pitch+roll.
            let expected = q.act(SIMD3<Double>(0, 0, 1))
            let projected = SIMD3<Double>(
                -expected.x, expected.z, expected.y)
            XCTAssertEqual(actual.x, projected.x, accuracy: 1e-5)
            XCTAssertEqual(actual.y, projected.y, accuracy: 1e-5)
            XCTAssertEqual(actual.z, projected.z, accuracy: 1e-5)
            XCTAssertEqual(pose.isInverted, degrees >= 135 && degrees <= 225)
            XCTAssertTrue(pose.fullAttitudeAvailable)
        }
    }

    func testNoseActuallyPointsUpDuringPositiveManualPose() throws {
        let angle = 0.18
        let gravity = Vector3(x: sin(angle), y: 0, z: -cos(angle))
        let board = calibration()
        let rotation = simd_quatd(angle: angle, axis: SIMD3(0, 1, 0))
        let sample = MotionSample(
            source: .headphone, sensorLocation: "left",
            hostUptime: 1, deviceTimestamp: 1,
            gravity: gravity, acceleration: .zero, rotationRate: .zero,
            quaternion: Quaternion4(w: rotation.real, x: rotation.imag.x,
                                    y: rotation.imag.y, z: rotation.imag.z))
        let pose = try XCTUnwrap(board.orientation(for: sample))
        XCTAssertGreaterThan(pose.pitchDegrees, 0)
        XCTAssertTrue(pose.fullAttitudeAvailable)
        let nose = try XCTUnwrap(pose.relativeQuaternion)
            .rotate(Vector3(x: 1, y: 0, z: 0))
        XCTAssertGreaterThan(nose.y, 0.12)

        let gravityOnlyBoard = calibration(withAttitude: false)
        let gravityPose = try XCTUnwrap(gravityOnlyBoard.orientation(for: sample))
        let estimatedNose = try XCTUnwrap(gravityPose.relativeQuaternion)
            .rotate(Vector3(x: 1, y: 0, z: 0))
        XCTAssertGreaterThan(estimatedNose.y, 0.12)
    }

    func testDeckInversionWithoutQuaternionStillLabelsUpsideDown() throws {
        let board = calibration(withAttitude: false)
        let pose = try XCTUnwrap(board.orientation(for: MotionSample(
            source: .headphone, sensorLocation: "left",
            hostUptime: 0, deviceTimestamp: 0,
            gravity: Vector3(x: 0, y: 0, z: 1),
            acceleration: .zero, rotationRate: .zero)))
        XCTAssertTrue(pose.isInverted)
        XCTAssertFalse(pose.fullAttitudeAvailable)
        XCTAssertFalse(pose.headingAvailable)
        XCTAssertNotNil(pose.relativeQuaternion)
    }

    func testYawTracksRelativeRotationWithoutClaimingWorldHeading() throws {
        let board = calibration()
        let q = simd_quatd(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let pose = try XCTUnwrap(board.orientation(for: sample(rotation: q)))
        XCTAssertEqual(pose.upAlignment, 1, accuracy: 0.0001)
        XCTAssertTrue(pose.headingAvailable)
        XCTAssertGreaterThan(abs(pose.yawDegrees), 80)
        let nose = try XCTUnwrap(pose.relativeQuaternion).rotate(Vector3(x: 1, y: 0, z: 0))
        XCTAssertEqual(abs(nose.z), 1, accuracy: 0.0001)
        XCTAssertEqual(nose.y, 0, accuracy: 0.0001)
    }

    func testRejectsInvalidQuaternionRatherThanRenderingNan() throws {
        let board = calibration()
        let corrupt = MotionSample(
            source: .headphone, sensorLocation: "left",
            hostUptime: 0, deviceTimestamp: 0,
            gravity: Vector3(x: 0, y: 0, z: -1),
            acceleration: .zero, rotationRate: .zero,
            quaternion: Quaternion4(w: .nan, x: 0, y: 0, z: 0))
        let pose = try XCTUnwrap(board.orientation(for: corrupt))
        XCTAssertFalse(pose.fullAttitudeAvailable)
        XCTAssertFalse(pose.headingAvailable)
        XCTAssertNotNil(pose.relativeQuaternion)
        XCTAssertTrue(pose.relativeQuaternion?.isValid == true)
    }

    func testDisagreeingAttitudeFallsBackToMeasuredGravity() throws {
        let board = calibration()
        let sample = MotionSample(
            source: .headphone, sensorLocation: "left",
            hostUptime: 0, deviceTimestamp: 0,
            gravity: Vector3(x: 0, y: 0, z: 1),
            acceleration: .zero, rotationRate: .zero,
            quaternion: .identity)
        let pose = try XCTUnwrap(board.orientation(for: sample))
        XCTAssertTrue(pose.isInverted)
        XCTAssertFalse(pose.fullAttitudeAvailable)
        XCTAssertFalse(pose.headingAvailable)
    }

    func testNoPositionIsFabricatedFromOrientation() {
        let properties = Mirror(reflecting: BoardOrientation.zero).children.compactMap(\.label)
        XCTAssertFalse(properties.contains("positionX"))
        XCTAssertFalse(properties.contains("heightMeters"))
    }
}

final class ManualBalanceTests: XCTestCase {
    private func board() -> BoardCalibration {
        var result = BoardCalibration()
        let contact = 0.46
        result.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1))
        result.set(.tailContact, gravity: Vector3(x: sin(contact), y: 0, z: -cos(contact)))
        result.set(.noseContact, gravity: Vector3(x: -sin(contact), y: 0, z: -cos(contact)))
        return result
    }

    private func record(_ tracker: inout ManualBalanceTracker, board: BoardCalibration,
                        from start: Double, through end: Double,
                        pitch: Double, lateral: Double = 0,
                        source: MotionSource = .headphone) {
        var t = start
        while t <= end + 1e-9 {
            let pitchRadians = pitch * .pi / 180
            let lateralRadians = lateral * .pi / 180
            let x = sin(pitchRadians) * cos(lateralRadians)
            let y = sin(lateralRadians)
            let z = -cos(pitchRadians) * cos(lateralRadians)
            let sample = MotionSample(source: source, sensorLocation: "left",
                hostUptime: t, deviceTimestamp: t,
                gravity: Vector3(x: x, y: y, z: z),
                acceleration: .zero, rotationRate: .zero)
            tracker.accept(sample, orientation: board.orientation(for: sample),
                           calibration: board)
            t += 0.025
        }
    }

    func testQualifiedManualNoseAndGoalWithTechniqueScores() {
        let calibration = board()
        var tracker = ManualBalanceTracker()
        tracker.configure(ManualBalanceSettings(targetAngleDegrees: 12,
                                                toleranceDegrees: 4, goalSeconds: 0.7))
        record(&tracker, board: calibration, from: 1, through: 2.10, pitch: 12)
        XCTAssertGreaterThan(tracker.snapshot.longestManualSeconds, 1.0)
        XCTAssertEqual(tracker.snapshot.manualAttempts, 1)
        XCTAssertEqual(tracker.snapshot.completedGoals, 1)
        XCTAssertGreaterThan(tracker.snapshot.stability, 95)
        record(&tracker, board: calibration, from: 2.125, through: 2.35, pitch: 0)
        record(&tracker, board: calibration, from: 2.375, through: 3.05, pitch: -12)
        XCTAssertGreaterThan(tracker.snapshot.longestNoseManualSeconds, 0.60)
        XCTAssertEqual(tracker.snapshot.noseManualAttempts, 1)
        XCTAssertEqual(tracker.snapshot.completedGoals, 1)
        tracker.finish()
        XCTAssertNil(tracker.snapshot.side)
        XCTAssertGreaterThan(tracker.savedRecord(sessionID: "id").averageStability, 90)
    }

    func testEdgeOnUpsideDownAndFastWobbleCannotCountAsManual() {
        let calibration = board()
        var tracker = ManualBalanceTracker()
        record(&tracker, board: calibration, from: 0, through: 0.4,
               pitch: 12, lateral: 22)
        XCTAssertEqual(tracker.snapshot.manualAttempts, 0)
        record(&tracker, board: calibration, from: 0.5, through: 0.8,
               pitch: 180)
        XCTAssertTrue(tracker.snapshot.isInverted)
        XCTAssertEqual(tracker.snapshot.manualAttempts, 0)
        XCTAssertEqual(tracker.snapshot.completedGoals, 0)
    }

    func testSensorDropoutAndPhoneSamplesDoNotInflateHoldTime() {
        let calibration = board()
        var tracker = ManualBalanceTracker()
        record(&tracker, board: calibration, from: 1, through: 1.5, pitch: 12)
        let bestBeforeGap = tracker.snapshot.longestManualSeconds
        record(&tracker, board: calibration, from: 3, through: 3.2, pitch: 12)
        XCTAssertEqual(tracker.snapshot.longestManualSeconds, bestBeforeGap,
                       accuracy: 0.001)
        record(&tracker, board: calibration, from: 4, through: 5,
               pitch: 12, source: .phone)
        XCTAssertEqual(tracker.snapshot.longestManualSeconds, bestBeforeGap,
                       accuracy: 0.001)
    }

    func testShortTiltIsNotAnAttempt() {
        let calibration = board()
        var tracker = ManualBalanceTracker()
        record(&tracker, board: calibration, from: 1, through: 1.15, pitch: 12)
        record(&tracker, board: calibration, from: 1.175, through: 1.4, pitch: 0)
        XCTAssertEqual(tracker.snapshot.manualAttempts, 0)
    }

    func testSettingsRejectOutOfRangeAndNan() {
        let settings = ManualBalanceSettings(targetAngleDegrees: .nan,
              toleranceDegrees: 99, goalSeconds: -.infinity).validated
        XCTAssertEqual(settings.targetAngleDegrees, 12)
        XCTAssertEqual(settings.toleranceDegrees, 8)
        XCTAssertEqual(settings.goalSeconds, 3)
    }

    func testPracticeHistoryPersistsWithoutRawLocation() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("skatefit-balance-test-\(UUID().uuidString)")
        // Test cleanup only touches this newly created isolated temp directory.
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ManualPracticeHistory(directory: folder)
        let record = SavedManualPractice(id: UUID().uuidString, finishedAt: Date(),
            settings: .init(), bestManualSeconds: 7.5, bestNoseSeconds: 2.3,
            manualAttempts: 3, noseManualAttempts: 2, goalsReached: 2,
            averageStability: 92, upsideDownSamples: 0)
        store.append(record)
        XCTAssertNil(store.errorMessage)
        let restored = ManualPracticeHistory(directory: folder)
        XCTAssertEqual(restored.sessions, [record])
        XCTAssertFalse(String(data: try Data(contentsOf:
            folder.appendingPathComponent("balance-\(record.id).json")),
            encoding: .utf8)?.contains("latitude") == true)
    }
}
