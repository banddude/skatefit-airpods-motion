import XCTest
import simd
import UIKit
@testable import SkateMotion

final class BoardOpticalMathTests: XCTestCase {
    private func matrix(x: Float = 0, y: Float = 0, z: Float = 0,
                        radians: Float = 0) -> simd_float4x4 {
        let quaternion = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
        var transform = simd_float4x4(quaternion)
        transform.columns.3 = SIMD4(x, y, z, 1)
        return transform
    }

    func testStationaryCameraSeesKnownMarkerInMeters() throws {
        let pose = try XCTUnwrap(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(), worldFromMarker: matrix(x: 0.4,y: 0.1,z: -2)))
        XCTAssertEqual(pose.xMeters, 0.4, accuracy: 0.0001)
        XCTAssertEqual(pose.yMeters, 0.1, accuracy: 0.0001)
        XCTAssertEqual(pose.zMeters, -2, accuracy: 0.0001)
        XCTAssertEqual(pose.distanceMeters, sqrt(4.17), accuracy: 0.0001)
        XCTAssertTrue(pose.orientation.isValid)
    }

    func testMovingThePhoneChangesCameraRelativePosition() throws {
        let marker = matrix(x: 0, y: 0.5, z: -2)
        let poseA = try XCTUnwrap(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(), worldFromMarker: marker))
        let poseB = try XCTUnwrap(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(x: 1), worldFromMarker: marker))
        XCTAssertEqual(poseA.xMeters, 0, accuracy: 0.0001)
        XCTAssertEqual(poseB.xMeters, -1, accuracy: 0.0001)
        // Tripod is mandatory. The app must never label this as board movement.
    }

    func testZeroReferenceAndRelativeRotation() throws {
        let base = try XCTUnwrap(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(), worldFromMarker: matrix(z: -1.5)))
        let moved = try XCTUnwrap(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(), worldFromMarker: matrix(x: 0.12,y: 0.18,z: -1.35,
                                                                radians: .pi)))
        let delta = BoardOpticalMath.displacement(from: base, to: moved)
        XCTAssertEqual(delta.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(delta.y, 0.18, accuracy: 0.0001)
        XCTAssertEqual(delta.z, 0.15, accuracy: 0.0001)
        let rotation = try XCTUnwrap(BoardOpticalMath.angularChangeDegrees(
            from: base.orientation, to: moved.orientation))
        XCTAssertEqual(rotation, 180, accuracy: 0.01)
    }

    func testStalenessAndAirPodTimePairingNeverInventMeasurements() {
        XCTAssertFalse(BoardOpticalMath.isFresh(sampleUptime: nil, now: 10))
        XCTAssertTrue(BoardOpticalMath.isFresh(sampleUptime: 9.6, now: 10))
        XCTAssertFalse(BoardOpticalMath.isFresh(sampleUptime: 9.4, now: 10))
        XCTAssertFalse(BoardOpticalMath.isFresh(sampleUptime: 11, now: 10))
        XCTAssertTrue(BoardOpticalMath.canPair(airPodUptime: 10.09, cameraUptime: 10))
        XCTAssertFalse(BoardOpticalMath.canPair(airPodUptime: 9.65, cameraUptime: 10))
        XCTAssertFalse(BoardOpticalMath.canPair(airPodUptime: nil, cameraUptime: 10))
    }

    func testMalformedMatricesAndImpossibleDistancesAreRejected() {
        var nan = matrix()
        nan.columns.3.x = .nan
        XCTAssertNil(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(), worldFromMarker: nan))
        var zero = simd_float4x4()
        zero.columns.3.w = 0
        XCTAssertNil(BoardOpticalMath.cameraPose(
            worldFromCamera: zero, worldFromMarker: matrix()))
    }

    func testPrintableMarkerAndAssetsAreBundled() {
        XCTAssertEqual(BoardOpticalMath.markerWidthMeters, 0.12, accuracy: 0.00001)
        XCTAssertNotNil(UIImage(named: "BoardOpticalMarker")?.cgImage)
        let pdf = Bundle.main.url(
            forResource: "SkateFit_Board_Tracking_Marker_120mm",
            withExtension: "pdf")
        XCTAssertNotNil(pdf, "Printable 120 mm PDF must travel with the signed IPA")
    }

    @MainActor
    func testOpticalLoggerWritesOnlyExplicitlyRecordedLocalData() throws {
        let recorder = BoardOpticalSessionRecorder()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.lastSavedURL)
        XCTAssertFalse(BoardOpticalSessionRecorder.csvHeader.contains("latitude"))
        XCTAssertFalse(BoardOpticalSessionRecorder.csvHeader.contains("longitude"))
        XCTAssertFalse(BoardOpticalSessionRecorder.csvHeader.contains("video"))
        recorder.start()
        XCTAssertTrue(recorder.isRecording)
        let pose = try XCTUnwrap(BoardOpticalMath.cameraPose(
            worldFromCamera: matrix(), worldFromMarker: matrix(y: 0.08,z: -1.7)))
        let sample = BoardOpticalSample(
            pose: pose, frameTimestamp: 42.3, hostReceiptUptime: 44.2,
            displacement: Vector3(x: 0, y: 0.08, z: 0),
            orientationChangeDegrees: 7)
        recorder.append(sample,airPodHostUptime: 44.22,airPodOrientation: .zero)
        recorder.stop()
        let file = try XCTUnwrap(recorder.lastSavedURL)
        let csv = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(csv.components(separatedBy:"\n").count, 3)
        XCTAssertTrue(csv.contains("44.200000"))
        XCTAssertTrue(csv.contains("44.220000"))
        XCTAssertEqual(recorder.sampleCount,1)
        XCTAssertNil(recorder.errorMessage)
        try FileManager.default.removeItem(at: file)
    }
}
