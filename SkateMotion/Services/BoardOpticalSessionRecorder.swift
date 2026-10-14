import Foundation
import SwiftUI

/// Optional local-only optical reference log. It stores no camera images,
/// video, audio, GPS coordinates, or user identity. A frame is written only
/// while the printed marker is actually tracked, never from extrapolation.
@MainActor
final class BoardOpticalSessionRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var sampleCount = 0
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var errorMessage: String?

    private var handle: FileHandle?

    static let csvHeader = [
        "camera_frame_time_s",
        "optical_receipt_uptime_s",
        "marker_camera_x_m",
        "marker_camera_y_m",
        "marker_camera_z_m",
        "marker_camera_distance_m",
        "zero_delta_x_m",
        "zero_delta_y_m",
        "zero_delta_z_m",
        "marker_delta_angle_deg",
        "airpod_receipt_uptime_s",
        "airpod_pose_time_match",
        "airpod_pitch_deg",
        "airpod_roll_deg",
        "airpod_relative_yaw_deg",
        "airpod_inverted"
    ].joined(separator: ",")

    func start() {
        guard !isRecording else { return }
        do {
            let directory = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SkateFitOpticalCaptures", isDirectory: true)
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(
                "spatial-\(UUID().uuidString).csv")
            guard FileManager.default.createFile(
                atPath: file.path, contents: Data((Self.csvHeader + "\n").utf8)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: file)
            try handle?.seekToEnd()
            isRecording = true
            sampleCount = 0
            errorMessage = nil
            lastSavedURL = file
        } catch {
            errorMessage = "Could not begin local optical log: \(error.localizedDescription)"
        }
    }

    func append(_ sample: BoardOpticalSample,
                airPodHostUptime: TimeInterval?,
                airPodOrientation: BoardOrientation?) {
        guard isRecording else { return }
        let paired = BoardOpticalMath.canPair(
            airPodUptime: airPodHostUptime,
            cameraUptime: sample.hostReceiptUptime)
        func value(_ number: Double?) -> String {
            guard let number, number.isFinite else { return "" }
            return String(format: "%.6f", number)
        }
        let row = [
            value(sample.frameTimestamp),
            value(sample.hostReceiptUptime),
            value(sample.pose.xMeters),
            value(sample.pose.yMeters),
            value(sample.pose.zMeters),
            value(sample.pose.distanceMeters),
            value(sample.displacement?.x),
            value(sample.displacement?.y),
            value(sample.displacement?.z),
            value(sample.orientationChangeDegrees),
            paired ? value(airPodHostUptime) : "",
            paired ? "1" : "0",
            paired ? value(airPodOrientation?.pitchDegrees) : "",
            paired ? value(airPodOrientation?.rollDegrees) : "",
            paired ? value(airPodOrientation?.headingAvailable == true
                           ? airPodOrientation?.yawDegrees : nil) : "",
            paired ? (airPodOrientation?.isInverted == true ? "1" : "0") : ""
        ].joined(separator: ",") + "\n"
        do {
            try handle?.write(contentsOf: Data(row.utf8))
            sampleCount += 1
        } catch {
            errorMessage = "Optical log write stopped: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording else { return }
        do {
            try handle?.close()
        } catch {
            errorMessage = "Optical log close failed: \(error.localizedDescription)"
        }
        handle = nil
        isRecording = false
    }
}
