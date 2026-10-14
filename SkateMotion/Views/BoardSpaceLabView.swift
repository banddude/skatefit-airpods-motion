import ARKit
import SceneKit
import SwiftUI

/// Native AR camera preview owned by the tracker. Camera permission and
/// tracking are started only by the explicit Start Camera action.
struct BoardOpticalCameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.allowsCameraControl = false
        view.backgroundColor = UIColor.black
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}

/// Experimental camera-observed marker position in metres, NOT AirPod-only
/// position. The iPhone must remain on a tripod; marker visibility is required.
struct BoardSpaceLabView: View {
    @ObservedObject var store: MotionStore
    @StateObject private var tracker = BoardCameraTracker()
    @StateObject private var recorder = BoardOpticalSessionRecorder()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(red: 0.45, green: 0.96, blue: 0.78)
    private let dark = Color(red: 0.035, green: 0.065, blue: 0.13)
    private let panel = Color(red: 0.09, green: 0.13, blue: 0.21)

    private var sample: BoardOpticalSample? { tracker.latestSample }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        Label("Back to manual coach", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    Spacer()
                    Label("OPTICAL BETA", systemImage: "camera.viewfinder")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.orange)
                }
                .frame(minHeight: 44)

                Text("BOARD SPACE LAB")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("Try real 3D marker tracking in metres with a fixed iPhone camera. This does not claim AirPods can measure board position.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))

                markerSetup
                cameraPanel
                measurements
                sensorComparison
                localCapture

                Text("Privacy: camera runs only when enabled here. No video frames, GPS coordinates, or microphone audio are recorded or uploaded. The optional CSV saves local optical positions and available recent AirPod angles only when you choose Record.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.bottom, 20)
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .background(dark.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(tracker.$latestSample) { update in
            guard let update else { return }
            recorder.append(update, airPodHostUptime: store.lastBoardPoseUptime,
                            airPodOrientation: store.latestOrientation)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopAll() }
        }
        .onDisappear { stopAll() }
    }

    private var markerSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("BoardOpticalMarker")
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 91, height: 91)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("SkateFit 120 millimeter printable optical marker")
                VStack(alignment: .leading, spacing: 4) {
                    Text("ONE PRINTED MARKER")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(accent)
                    Text("Print at exactly 120 mm wide. Tape it rigidly to the visible nose of the deck, where shoes will not cover it.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                }
            }

            if let pdf = Bundle.main.url(
                forResource: "SkateFit_Board_Tracking_Marker_120mm",
                withExtension: "pdf") {
                ShareLink(item: pdf, preview: SharePreview("SkateFit 120 mm Marker")) {
                    Label("SHARE OR PRINT THE FULL-SIZE MARKER",
                          systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 45)
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .accessibilityIdentifier("shareOpticalMarker")
            } else {
                Text("The marker PDF is unavailable. Camera tracking cannot be calibrated reliably.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("For accurate relative movement: fix this iPhone to a tripod, keep the whole marker visible, and print the PDF at 100% (not Fit to Page). Check its 50 mm scale bar.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var cameraPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if tracker.isRunning {
                    BoardOpticalCameraView(session: tracker.session)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                } else {
                    Rectangle()
                        .fill(dark)
                        .frame(height: 265)
                        .overlay {
                            VStack(spacing: 11) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 58))
                                    .foregroundStyle(accent)
                                Text("CAMERA OFF")
                                    .font(.subheadline.weight(.black))
                                Text("Only starts when you choose Start Camera")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                if tracker.isRunning {
                    VStack {
                        HStack {
                            Image(systemName: sample == nil
                                  ? "viewfinder" : "checkmark.viewfinder")
                            Text(sample == nil ? "SEARCHING" : "MARKER LOCK")
                            Spacer()
                        }
                        .font(.caption2.weight(.black))
                        .foregroundStyle(sample == nil ? .yellow : accent)
                        .padding(10)
                        .background(.black.opacity(0.75),
                                    in: RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }.padding(9)
                }
            }

            Text(tracker.status)
                .font(.caption.weight(.bold))
                .foregroundStyle(sample == nil ? .orange : accent)

            Button {
                if tracker.isRunning { stopAll() }
                else { tracker.start() }
            } label: {
                Label(tracker.isRunning ? "STOP CAMERA" : "START CAMERA TRACKING",
                      systemImage: tracker.isRunning ? "stop.fill" : "camera.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(dark)
            .background(tracker.isRunning ? Color.orange : accent,
                        in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("toggleOpticalCamera")
            if !BoardCameraTracker.isAvailable {
                Text("This device does not support ARKit image tracking. Tracking requires a compatible physical iPhone.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(13)
        .background(panel, in: RoundedRectangle(cornerRadius: 19))
    }

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEASURED MARKER POSITION")
                .font(.caption.weight(.black)).tracking(1.5)
                .foregroundStyle(accent)

            HStack(spacing: 9) {
                spatialTile("RIGHT / LEFT", sample.map {
                    String(format: "%+.2f", $0.pose.xMeters) } ?? "—", "m")
                spatialTile("UP / DOWN", sample.map {
                    String(format: "%+.2f", $0.pose.yMeters) } ?? "—", "m")
                spatialTile("CAMERA DEPTH", sample.map {
                    String(format: "%+.2f", $0.pose.zMeters) } ?? "—", "m")
            }

            HStack {
                Text("Distance from phone camera")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                Spacer()
                Text(sample.map { String(format: "%.2f m", $0.pose.distanceMeters) } ?? "—")
                    .font(.subheadline.monospacedDigit().bold())
            }

            Button {
                tracker.setFlatReference()
            } label: {
                Label(tracker.hasZeroReference ? "RESET FLAT ZERO" : "SET FLAT-BOARD ZERO",
                      systemImage: "scope")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .disabled(sample == nil)
            .accessibilityIdentifier("setOpticalZero")

            if tracker.hasZeroReference {
                HStack(spacing: 9) {
                    spatialTile("ΔX RIGHT", sample?.displacement.map {
                        String(format: "%+.1f", $0.x * 100) } ?? "—", "cm")
                    spatialTile("ΔY UP", sample?.displacement.map {
                        String(format: "%+.1f", $0.y * 100) } ?? "—", "cm")
                    spatialTile("ΔZ DEPTH", sample?.displacement.map {
                        String(format: "%+.1f", $0.z * 100) } ?? "—", "cm")
                }
                HStack {
                    Text("Marker rotation since flat zero")
                        .font(.caption)
                    Spacer()
                    Text(sample?.orientationChangeDegrees.map {
                        String(format: "%.0f°", $0) } ?? "—")
                        .font(.subheadline.monospacedDigit().bold())
                }
            }
            Text("X, Y, Z are from the CAMERA, not GPS or a surveyed world origin. Δ values compare with your flat-board zero while the phone remains stationary. ΔY is marker movement, not proven board jump height.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.64))
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 17))
    }

    private var sensorComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("CAMERA + AIRPOD TIMING", systemImage: "waveform.path")
                .font(.subheadline.weight(.black))
                .foregroundStyle(accent)

            let paired = sample.map {
                BoardOpticalMath.canPair(airPodUptime: store.lastBoardPoseUptime,
                                         cameraUptime: $0.hostReceiptUptime)
            } ?? false

            Text(paired ? "Fresh board-mounted AirPod pose nearby in time" :
                         "No recent paired AirPod reading")
                .font(.caption.weight(.semibold))
                .foregroundStyle(paired ? accent : .orange)
            if paired, let orientation = store.latestOrientation {
                HStack(spacing: 8) {
                    spatialTile("AIRPOD PITCH",
                                String(format: "%+.1f", orientation.pitchDegrees), "°")
                    spatialTile("AIRPOD ROLL",
                                String(format: "%+.1f", orientation.rollDegrees), "°")
                    spatialTile("AIRPOD YAW",
                                orientation.headingAvailable
                                ? String(format: "%+.1f", orientation.yawDegrees) : "—", "°")
                }
            }
            Text("Only timestamp-nearby readings are associated. They are not hardware synchronized. Start a separate AirPod recording in Manual Coach if you want paired readings in your local CSV.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.66))
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 17))
    }

    private var localCapture: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("LOCAL OPTICAL DATA")
                .font(.subheadline.weight(.black))
                .foregroundStyle(accent)
            Text("Optional CSV of tracked 3D marker poses, camera frame timestamps, local arrival times, and nearby AirPod angles. Camera frames and video are never saved.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
            Button {
                if recorder.isRecording { recorder.stop() }
                else { recorder.start() }
            } label: {
                Label(recorder.isRecording ? "STOP & SAVE LOCAL CSV" :
                        "RECORD LOCAL MARKER CSV",
                      systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity, minHeight: 45)
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .disabled(!tracker.isRunning && !recorder.isRecording)

            Text("\(recorder.sampleCount) valid marker frames written")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))

            if !recorder.isRecording, let file = recorder.lastSavedURL {
                ShareLink(item: file) {
                    Label("SHARE SAVED CAMERA CSV", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(accent)
            }
            if let error = recorder.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 17))
    }

    private func spatialTile(_ name: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.63))
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .monospacedDigit()
                Text(unit).font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(dark, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stopAll() {
        recorder.stop()
        tracker.stop()
    }
}
