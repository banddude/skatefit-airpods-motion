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
        XCTAssertEqual(row.split(separator: ",").count,
                       MotionSample.csvHeader.split(separator: ",").count)
        XCTAssertTrue(row.contains("headphone,left"))
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
