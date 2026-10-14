import ARKit
import AVFoundation
import Foundation
import SwiftUI

/// Opt-in camera marker tracker. This uses ARKit image detection instead of
/// double-integrating acceleration. Coordinates are relative to the live
/// PHONE CAMERA. A stationary tripod camera is required to compare movement
/// against the user's manually set flat-board reference.
@MainActor
final class BoardCameraTracker: NSObject, ObservableObject,
                                @preconcurrency ARSessionDelegate {
    let session = ARSession()

    @Published private(set) var isRunning = false
    @Published private(set) var status = "CAMERA OFF"
    @Published private(set) var latestSample: BoardOpticalSample?
    @Published private(set) var hasZeroReference = false

    private var referencePose: CameraMarkerPose?
    private var lastPublicationUptime = 0.0
    private var lastOpticalUptime: TimeInterval?
    private var lastProcessedFrameUptime = 0.0
    private let publishingInterval = 1.0 / 12.0

    static var isAvailable: Bool { ARImageTrackingConfiguration.isSupported }

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard Self.isAvailable else {
            status = "AR IMAGE TRACKING IS NOT SUPPORTED ON THIS DEVICE"
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            launchSession()
        case .notDetermined:
            status = "WAITING FOR CAMERA PERMISSION"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if allowed { self.launchSession() }
                    else { self.status = "CAMERA PERMISSION DENIED" }
                }
            }
        case .restricted, .denied:
            status = "CAMERA PERMISSION DENIED IN SETTINGS"
        @unknown default:
            status = "CAMERA AUTHORIZATION UNAVAILABLE"
        }
    }

    private func launchSession() {
        guard let marker = UIImage(named: "BoardOpticalMarker")?.cgImage else {
            status = "PRINTABLE BOARD MARKER RESOURCE MISSING"
            return
        }
        let reference = ARReferenceImage(marker, orientation: .up,
                                         physicalWidth: CGFloat(BoardOpticalMath.markerWidthMeters))
        reference.name = "SkateFit-Board-120mm-v1"
        let config = ARImageTrackingConfiguration()
        config.trackingImages = [reference]
        config.maximumNumberOfTrackedImages = 1
        config.isAutoFocusEnabled = true
        status = "POINT THE CAMERA AT THE PRINTED 120 MM MARKER"
        referencePose = nil
        hasZeroReference = false
        lastOpticalUptime = nil
        lastPublicationUptime = 0
        lastProcessedFrameUptime = 0
        latestSample = nil
        isRunning = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        guard isRunning else { return }
        session.pause()
        isRunning = false
        latestSample = nil
        lastOpticalUptime = nil
        lastPublicationUptime = 0
        lastProcessedFrameUptime = 0
        referencePose = nil
        hasZeroReference = false
        status = "CAMERA OFF"
    }

    func setFlatReference() {
        guard let reading = latestSample,
              BoardOpticalMath.isFresh(sampleUptime: reading.hostReceiptUptime,
                                        now: ProcessInfo.processInfo.systemUptime) else {
            status = "MARKER MUST BE VISIBLE TO SET THE FLAT REFERENCE"
            return
        }
        referencePose = reading.pose
        hasZeroReference = true
        latestSample = BoardOpticalSample(
            pose: reading.pose, frameTimestamp: reading.frameTimestamp,
            hostReceiptUptime: reading.hostReceiptUptime,
            displacement: .zero, orientationChangeDegrees: 0)
        status = "RELATIVE ZERO SET: KEEP THE CAMERA STATIONARY"
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard let image = frame.anchors.compactMap({ $0 as? ARImageAnchor })
            .first(where: { $0.referenceImage.name == "SkateFit-Board-120mm-v1" }),
              image.isTracked,
              let pose = BoardOpticalMath.cameraPose(
                worldFromCamera: frame.camera.transform,
                worldFromMarker: image.transform) else {
            Task { @MainActor [weak self] in self?.markTrackingLost(at: uptime) }
            return
        }
        let timestamp = frame.timestamp
        Task { @MainActor [weak self] in
            self?.accept(pose: pose, timestamp: timestamp, uptime: uptime)
        }
    }

    private func accept(pose: CameraMarkerPose, timestamp: TimeInterval,
                        uptime: TimeInterval) {
        guard isRunning, uptime >= lastProcessedFrameUptime else { return }
        lastProcessedFrameUptime = uptime
        lastOpticalUptime = uptime
        guard uptime >= lastPublicationUptime + publishingInterval else { return }
        lastPublicationUptime = uptime
        var delta: Vector3?
        var angular: Double?
        if let referencePose {
            delta = BoardOpticalMath.displacement(from: referencePose, to: pose)
            angular = BoardOpticalMath.angularChangeDegrees(
                from: referencePose.orientation, to: pose.orientation)
        }
        latestSample = BoardOpticalSample(
            pose: pose, frameTimestamp: timestamp, hostReceiptUptime: uptime,
            displacement: delta, orientationChangeDegrees: angular)
        status = referencePose != nil
            ? "MARKER TRACKED: CAMERA-RELATIVE POSITION"
            : "MARKER FOUND: PLACE BOARD FLAT AND SET ZERO"
    }

    private func markTrackingLost(at uptime: TimeInterval) {
        guard isRunning, uptime >= lastProcessedFrameUptime else { return }
        lastProcessedFrameUptime = uptime
        // Do not show an old XYZ even briefly after ARKit reports that the
        // image is no longer tracked. We never extrapolate marker position.
        if latestSample != nil { latestSample = nil }
        let label = hasZeroReference
            ? "MARKER LOST: POSITION UNAVAILABLE UNTIL VISIBLE"
            : "SEARCHING FOR BOARD MARKER"
        if status != label { status = label }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stop()
            self.status = "CAMERA TRACKING FAILED: \(error.localizedDescription)"
        }
    }
}
