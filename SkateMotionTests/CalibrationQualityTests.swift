import XCTest
@testable import SkateMotion


final class CalibrationQualityTests: XCTestCase {
    private func sample(gravity: Vector3 = Vector3(x: 0, y: 0, z: -1),
                        acceleration: Vector3 = .zero,
                        rotation: Vector3 = .zero) -> MotionSample {
        MotionSample(source: .headphone, sensorLocation: "left",
                     hostUptime: 1, deviceTimestamp: 1,
                     gravity: gravity, acceleration: acceleration,
                     rotationRate: rotation)
    }

    func testStationarySamplingAcceptsRestAndRejectsShaking() {
        XCTAssertTrue(CalibrationCaptureQuality.accepts(sample()))
        XCTAssertFalse(CalibrationCaptureQuality.accepts(sample(
            rotation: Vector3(x: 0.35, y: 0, z: 0))))
        XCTAssertFalse(CalibrationCaptureQuality.accepts(sample(
            acceleration: Vector3(x: 0, y: 0.5, z: 0))))
        XCTAssertFalse(CalibrationCaptureQuality.accepts(sample(
            gravity: Vector3(x: 0, y: 0, z: -1.4))))
        XCTAssertFalse(CalibrationCaptureQuality.accepts(sample(
            gravity: Vector3(x: .nan, y: 0, z: -1))))
    }

    func testStableMeanRejectsAngularWobbleThatCancelsToZero() throws {
        let quiet = (0..<80).map { n in
            Vector3(x: Double(n % 3 - 1) * 0.008,
                    y: Double(n % 5 - 2) * 0.005,
                    z: -1)
        }
        let mean = try XCTUnwrap(CalibrationCaptureQuality.stableMean(quiet))
        XCTAssertEqual(mean.z, -1, accuracy: 0.005)
        let wobbling = (0..<80).map { n in
            Vector3(x: n.isMultiple(of: 2) ? 0.22 : -0.22,
                    y: 0, z: -sqrt(1 - 0.22 * 0.22))
        }
        XCTAssertNil(CalibrationCaptureQuality.stableMean(wobbling))
        XCTAssertNil(CalibrationCaptureQuality.stableMean(Array(quiet.prefix(4))))
    }

    func testCalibratingTailAndNoseRequiresSeparateOpposingPoses() {
        var calibration = BoardCalibration()
        let flat = Vector3(x: 0, y: 0, z: -1)
        calibration.set(.wheelsDown, gravity: flat)
        calibration.set(.tailContact, gravity:
                        Vector3(x: 0.28, y: 0, z: -0.96))
        calibration.set(.noseContact, gravity:
                        Vector3(x: -0.28, y: 0, z: -0.96))
        XCTAssertTrue(calibration.isPhysicallyPlausible)
    }
    func testFakeSidewaysContactPoseIsRejected() {
        var calibration = BoardCalibration()
        calibration.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1))
        calibration.set(.tailContact,
                        gravity: Vector3(x: 0.30, y: 0, z: -0.954))
        calibration.set(.noseContact,
                        gravity: Vector3(x: -0.10, y: 0.30, z: -0.948))
        XCTAssertFalse(calibration.isPhysicallyPlausible)
    }

}
