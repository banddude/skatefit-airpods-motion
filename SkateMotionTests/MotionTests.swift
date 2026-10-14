import XCTest
@testable import SkateMotion

final class MotionTests: XCTestCase {
    private func calibratedBoard() -> BoardCalibration {
        var result = BoardCalibration()
        let angle = 0.45
        result.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1))
        result.set(.tailContact, gravity: Vector3(x: sin(angle), y: 0, z: -cos(angle)))
        result.set(.noseContact, gravity: Vector3(x: -sin(angle), y: 0, z: -cos(angle)))
        return result
    }

    private func sample(at time: Double, pitch: Double, source: MotionSource = .headphone,
                        acceleration: Vector3 = .zero, rotation: Vector3 = .zero) -> MotionSample {
        MotionSample(source: source, sensorLocation: "left", hostUptime: time,
                     deviceTimestamp: time,
                     gravity: Vector3(x: sin(pitch), y: 0, z: -cos(pitch)),
                     acceleration: acceleration, rotationRate: rotation)
    }

    func testCalibrationUnderArbitrarySensorMount() throws {
        let board = calibratedBoard()
        XCTAssertTrue(board.isComplete)
        XCTAssertTrue(board.isPhysicallyPlausible)
        XCTAssertEqual(try XCTUnwrap(board.pitchDegrees(gravity: sample(at: 0, pitch: 0.18).gravity)),
                       0.18 * 180 / .pi, accuracy: 0.1)
        XCTAssertLessThan(try XCTUnwrap(board.pitchDegrees(gravity: sample(at: 0, pitch: -0.20).gravity)), 0)
    }

    func testSidewaysTiltDoesNotLookLikeManual() throws {
        let board = calibratedBoard()
        let sideways = Vector3(x: 0, y: sin(0.35), z: -cos(0.35))
        let degrees = try XCTUnwrap(board.pitchDegrees(gravity: sideways))
        XCTAssertEqual(degrees, 0, accuracy: 0.05)
    }

    func testBoardSideAutomaticallyFollowsStreamingEarbudAtSetup() {
        XCTAssertTrue(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "right", selectedSide: "left",
            boardReadings: 0, calibrationStarted: false, hasSavedPose: false))
        XCTAssertTrue(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "left", selectedSide: "right",
            boardReadings: 0, calibrationStarted: false, hasSavedPose: false))
        XCTAssertFalse(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "right", selectedSide: "right",
            boardReadings: 0, calibrationStarted: false, hasSavedPose: false))
        XCTAssertFalse(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "default", selectedSide: "left",
            boardReadings: 0, calibrationStarted: false, hasSavedPose: false))
        XCTAssertFalse(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "right", selectedSide: "left",
            boardReadings: 5, calibrationStarted: false, hasSavedPose: false))
        XCTAssertFalse(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "right", selectedSide: "left",
            boardReadings: 0, calibrationStarted: true, hasSavedPose: false))
        XCTAssertFalse(BoardSensorSelection.shouldAutoSelect(
            detectedSide: "right", selectedSide: "left",
            boardReadings: 0, calibrationStarted: false, hasSavedPose: true))
    }

    func testCalibrationRequiresRealBoardAirPodSamples() {
        XCTAssertFalse(BoardSensorReadiness.canCalibrate(
            boardReadings: 0, detectedSide: "none", expectedSide: "left",
            lastReading: nil, now: 100))
        XCTAssertFalse(BoardSensorReadiness.canCalibrate(
            boardReadings: 10, detectedSide: "right", expectedSide: "left",
            lastReading: 99.5, now: 100))
        XCTAssertFalse(BoardSensorReadiness.canCalibrate(
            boardReadings: 10, detectedSide: "left", expectedSide: "left",
            lastReading: 90, now: 100))
        XCTAssertTrue(BoardSensorReadiness.canCalibrate(
            boardReadings: 10, detectedSide: "left", expectedSide: "left",
            lastReading: 99.5, now: 100))
    }

    func testMissingCalibrationDoesNotDetect() {
        var detector = TrickDetector()
        let result = detector.accept(sample(at: 2, pitch: 0.3), calibration: BoardCalibration())
        XCTAssertEqual(result.count, 0)
    }

    func testManualHoldAndRelease() {
        var detector = TrickDetector()
        let calibration = calibratedBoard()
        var found: [TrickEvent] = []
        for index in 0..<100 {
            let t = Double(index) * 0.025
            let tilt = (index >= 15 && index < 68) ? 0.20 : 0.0
            found.append(contentsOf: detector.accept(sample(at: t, pitch: tilt), calibration: calibration))
        }
        XCTAssertTrue(found.contains(where: { $0.kind == "Possible manual" }))
    }

    func testNoseManualHoldAndRelease() {
        var detector = TrickDetector()
        let calibration = calibratedBoard()
        var found: [TrickEvent] = []
        for index in 0..<100 {
            let t = Double(index) * 0.025
            let tilt = (index >= 15 && index < 68) ? -0.20 : 0.0
            found.append(contentsOf: detector.accept(sample(at: t, pitch: tilt), calibration: calibration))
        }
        XCTAssertTrue(found.contains(where: { $0.kind == "Possible nose manual" }))
    }

    func testPhoneMotionExcludedFromBoardClassifier() {
        var detector = TrickDetector()
        let result = detector.accept(sample(at: 1, pitch: 0.20, source: .phone),
                                     calibration: calibratedBoard())
        XCTAssertTrue(result.isEmpty)
    }

    func testWakeToneIsValidWAVStructure() {
        let data = AirPodAudioWake.makeToneWAV()
        XCTAssertGreaterThan(data.count, 22_000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(String(data: data.dropFirst(8).prefix(4), encoding: .utf8), "WAVE")
    }

    func testCSVSchemaIsStable() {
        let row = sample(at: 1.234, pitch: 0).csvRow
        XCTAssertEqual(row.split(separator: ",", omittingEmptySubsequences: false).count,
                       MotionSample.csvHeader.split(separator: ",").count)
        XCTAssertTrue(row.contains("headphone,left"))
    }

    func testThreeAxisBoardOrientation() throws {
        var board = calibratedBoard()
        board.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1),
                  attitude: .identity)
        let yaw90 = Quaternion4(w: cos(.pi / 4), x: 0, y: 0, z: sin(.pi / 4))
        let yawSample = MotionSample(
            source: .headphone, sensorLocation: "right",
            hostUptime: 1, deviceTimestamp: 1,
            gravity: Vector3(x: 0, y: 0, z: -1),
            acceleration: .zero, rotationRate: .zero,
            quaternion: yaw90)
        let orientation = try XCTUnwrap(board.orientation(for: yawSample))
        XCTAssertTrue(orientation.headingAvailable)
        XCTAssertEqual(abs(orientation.yawDegrees), 90, accuracy: 0.5)
        XCTAssertEqual(orientation.pitchDegrees, 0, accuracy: 0.01)
        XCTAssertEqual(orientation.rollDegrees, 0, accuracy: 0.01)

        let rollGravity = Vector3(x: 0, y: sin(0.22), z: -cos(0.22))
        let rollSample = MotionSample(
            source: .headphone, sensorLocation: "right",
            hostUptime: 2, deviceTimestamp: 2,
            gravity: rollGravity, acceleration: .zero, rotationRate: .zero,
            quaternion: .identity)
        let rollOrientation = try XCTUnwrap(board.orientation(for: rollSample))
        XCTAssertEqual(abs(rollOrientation.rollDegrees), 0.22 * 180 / .pi, accuracy: 0.15)
        XCTAssertEqual(rollOrientation.pitchDegrees, 0, accuracy: 0.15)
    }

    func testQuaternionIsWrittenToCSV() {
        let s = MotionSample(
            source: .headphone, sensorLocation: "left",
            hostUptime: 3, deviceTimestamp: 3, gravity: .zero,
            acceleration: .zero, rotationRate: .zero,
            quaternion: .identity)
        XCTAssertTrue(MotionSample.csvHeader.hasSuffix(
            "quaternion_w,quaternion_x,quaternion_y,quaternion_z"))
        XCTAssertEqual(s.csvRow.split(separator: ",").count, 20)
        XCTAssertTrue(s.csvRow.hasSuffix(",1.0,0.0,0.0,0.0"))
    }

    func testSessionArchivePersistsCompleteCSVAndStatistics() async throws {
        try await MainActor.run {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("skatefit-xctest-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let recorder = SessionArchive(directory: folder)
            var board = calibratedBoard()
            board.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1),
                      attitude: .identity)
            let sessionId = UUID().uuidString
            try recorder.begin(id: sessionId, boardSide: "right", synthetic: false)

            @MainActor func take(_ t: Double, _ acceleration: Double,
                      _ rate: Vector3 = .zero) throws {
                let sample = MotionSample(
                    source: .headphone, sensorLocation: "right",
                    hostUptime: t, deviceTimestamp: t,
                    gravity: Vector3(x: sin(0.17), y: 0, z: -cos(0.17)),
                    acceleration: Vector3(x: acceleration, y: 0, z: 0),
                    rotationRate: rate, quaternion: .identity)
                try recorder.observe(sample, acceptedBoard: true, calibration: board,
                                     orientation: board.orientation(for: sample))
            }

            try take(10.0, 0.1)
            try take(10.05, 2.3, Vector3(x: 1, y: 2, z: 3))
            try take(10.10, 0.1)
            try take(10.5, 2.5, Vector3(x: 1, y: 2, z: 3))
            let phone = MotionSample(
                source: .phone, sensorLocation: "default",
                hostUptime: 10.51, deviceTimestamp: 10.51,
                gravity: .zero, acceleration: .zero, rotationRate: .zero)
            try recorder.observe(phone, acceptedBoard: false,
                                 calibration: board, orientation: nil)
            recorder.noteEvents([TrickEvent(kind: "Possible manual",
                                             start: 10.0, end: 10.5,
                                             confidence: 0.5, detail: "synthetic")])
            let finished = try XCTUnwrap(recorder.finish(calibrated: true))
            XCTAssertEqual(finished.stats.boardSamples, 4)
            XCTAssertEqual(finished.stats.phoneSamples, 1)
            XCTAssertEqual(finished.stats.impactSpikes, 2)
            XCTAssertEqual(finished.stats.possibleManuals, 1)
            XCTAssertGreaterThan(finished.stats.cumulativeRollRotationDegrees, 0)
            XCTAssertGreaterThan(finished.stats.cumulativePitchRotationDegrees, 0)
            XCTAssertGreaterThan(finished.stats.cumulativeYawRotationDegrees, 0)

            let csv = try String(contentsOf: recorder.fileURL(for: finished),
                                 encoding: .utf8)
            XCTAssertEqual(csv.components(separatedBy: "\n").count - 1, 6)

            let reloaded = SessionArchive(directory: folder)
            let saved = try XCTUnwrap(reloaded.history.first)
            XCTAssertEqual(saved.id, sessionId)
            XCTAssertEqual(saved.stats.impactSpikes, 2)
            XCTAssertNotNil(saved.endedAt)
        }
    }

    func testShortWobbleNotManual() {
        var detector = TrickDetector()
        let calibration = calibratedBoard()
        let events = [
            sample(at: 1, pitch: 0.18),
            sample(at: 1.08, pitch: 0.19),
            sample(at: 1.14, pitch: 0.0)
        ].flatMap { detector.accept($0, calibration: calibration) }
        XCTAssertFalse(events.contains { $0.kind.contains("manual") })
    }
}
