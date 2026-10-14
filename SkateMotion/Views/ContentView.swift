import SwiftUI
import AVKit

/// Daily-use screen: see the board angle, calibrate in three guided holds,
/// and start/stop a session. The former debug console lives under Advanced.
struct ContentView: View {
    @StateObject private var store = MotionStore()
    @State private var showAdvanced = false
    @State private var gameMode = true
    @State private var showConnectionHelp = false

    private let calibrationOrder: [CalibrationPose] = [.wheelsDown, .tailContact, .noseContact]

    private var nextPose: CalibrationPose? {
        calibrationOrder.first { store.calibration.poses[$0] == nil }
    }

    private var calibrationCount: Int {
        calibrationOrder.filter { store.calibration.poses[$0] != nil }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Screen", selection: $gameMode) {
                        Text("Skate").tag(true)
                        Text("Setup & Lab").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if gameMode {
                        gameHome
                    } else {
                    connectionBanner

                    if !store.hasCalibration {
                        recordingControls
                        calibrationCard
                    }

                    BoardAngleCard(
                        pitch: store.hasCalibration ? store.latestPitch : nil,
                        calibrated: store.hasCalibration,
                        recording: store.isRecording,
                        manualLimit: store.calibration.manualUpperLimit
                    )

                    if store.hasCalibration {
                        Board3DCard(orientation: store.latestOrientation,
                                    recording: store.isRecording)
                        recordingControls
                        readyCard
                    }

                    if store.isRecording || store.exportedFile != nil {
                        SessionStatisticsCard(stats: store.liveStatistics,
                                              recording: store.isRecording)
                    }
                    savedSessionsButton

                    if let latest = store.events.last {
                        latestEventCard(latest)
                    }

                    advancedCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("SkateFit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var gameHome: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SKATE SESSION")
                    .font(.caption.weight(.bold)).foregroundStyle(.teal)
                Text(store.isRecording ? "You're skating" : "Ready to skate?")
                    .font(.largeTitle.weight(.bold))
                Text(store.hasCalibration ? "Track your moves, build your stats." :
                     "Set up your board once, then start skating.")
                    .foregroundStyle(.secondary)
            }
            if store.hasCalibration {
                Board3DCard(orientation: store.latestOrientation, recording: store.isRecording)
                SessionStatisticsCard(stats: store.liveStatistics, recording: store.isRecording)
            } else {
                Label("Board calibration needed", systemImage: "airpodspro")
                    .foregroundStyle(.orange)
                    .padding()
            }
            if store.hasCalibration {
                recordingControls
            } else {
                Button("Set up my board") { gameMode = false }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Label("Possible tricks", systemImage: "bolt.fill")
                Spacer()
                Text("\(store.liveStatistics.possibleEvents)")
                    .font(.title2.bold()).monospacedDigit()
            }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            savedSessionsButton
            Button("Board settings & calibration") { gameMode = false }
                .font(.subheadline)
        }
    }

    private var savedSessionsButton: some View {
        NavigationLink {
            SavedSessionsView(store: store)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved sessions")
                        .font(.headline)
                    Text("\(store.savedSessions.count) recordings and saved statistics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .tint(.primary)
    }

    private var connectionBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: store.boardSensorReady ? "checkmark.circle.fill" : "waveform.path")
                .font(.title2)
                .foregroundStyle(store.boardSensorReady ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.boardSensorReady ? "\(store.boardSide.title) AirPod connected" :
                        (store.isRecording ? "Waiting for board sensor" : "Board sensor"))
                    .font(.headline)
                Text(store.boardSensorReady ?
                     "AirPod motion is coming through" :
                     (store.isRecording ? "Connect your AirPod to begin" :
                      "Start a session to connect"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if store.isRecording && !store.boardSensorReady {
                Button("Fix") { showConnectionHelp = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 17))
        .sheet(isPresented: $showConnectionHelp) {
            NavigationStack {
                connectionHelpContent
                    .padding()
                    .navigationTitle("Connect your AirPod")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showConnectionHelp = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 9) {
            Button {
                if store.isRecording {
                    store.stopRecording()
                } else {
                    store.startRecording()
                }
            } label: {
                Label(store.isRecording ? "Stop session" : "Start session",
                      systemImage: store.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.isRecording ? .red : .teal)

            if store.isRecording {
                Label("Recording on your iPhone · syncs over cellular",
                      systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let file = store.exportedFile {
                ShareLink(item: file) {
                    Label("Share your recorded session", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Start a session, then hold the board in three positions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set your board angle")
                        .font(.title3.weight(.semibold))
                    Text("Three quick holds. Do this once per session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(calibrationCount)/3")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.teal)
            }

            HStack(spacing: 8) {
                ForEach(calibrationOrder, id: \.self) { pose in
                    let complete = store.calibration.poses[pose] != nil
                    let active = store.calibrationPose == pose
                    VStack(spacing: 7) {
                        Image(systemName: complete ? "checkmark.circle.fill" :
                              (active ? "circle.dotted.circle.fill" : icon(for: pose)))
                            .font(.title2)
                            .foregroundStyle(complete ? Color.green :
                                            active ? Color.teal : Color.secondary)
                        Text(shortName(for: pose))
                            .font(.caption2.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(complete ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(complete ? Color.green.opacity(0.09) :
                                active ? Color.teal.opacity(0.10) :
                                Color(uiColor: .tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if let active = store.calibrationPose {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Hold \(instruction(for: active)) still")
                        .font(.headline)
                    ProgressView(value: store.calibrationProgress)
                        .tint(.teal)
                    Text("Capturing… \(Int(store.calibrationProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if let nextPose {
                Button {
                    store.calibrate(nextPose)
                } label: {
                    Label("Capture \(shortName(for: nextPose).lowercased())",
                          systemImage: "viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(!store.isRecording || !store.boardSensorReady)
                Text(instruction(for: nextPose))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Those positions didn't match. Let's try again.",
                      systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Button("Reset calibration") { store.resetCalibration() }
                    .buttonStyle(.bordered)
            }

            if store.isRecording && !store.boardSensorReady {
                Button {
                    showConnectionHelp = true
                } label: {
                    Label("AirPod not responding? Fix connection",
                          systemImage: "airpodspro")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.teal)
            }
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private var readyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Calibrated. Ready to skate.")
                    .font(.headline)
                Text("Move the board to see the angle change live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button("Redo") { store.resetCalibration() }
                .font(.caption.weight(.medium))
                .disabled(!store.isRecording)
        }
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func latestEventCard(_ event: TrickEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Latest activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.kind)
                    .font(.headline)
                Text("Experimental detection · verify with video")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.events.count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var advancedCard: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Developer diagnostics")
                    .font(.headline)
                Picker("Board-mounted AirPod", selection: $store.boardSide) {
                    ForEach(HeadphoneSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .disabled(store.isRecording)

                if let acceleration = store.latestBoardAcceleration {
                    LabeledContent("Acceleration X / Y / Z (g)", value:
                        String(format: "%.2f / %.2f / %.2f",
                               acceleration.x, acceleration.y, acceleration.z))
                }
                if let rate = store.latestBoardRotationRate {
                    LabeledContent("Gyro X / Y / Z (rad/s)", value:
                        String(format: "%.2f / %.2f / %.2f",
                               rate.x, rate.y, rate.z))
                }
                LabeledContent("AirPod readings", value: "\(store.headphoneTotalSamples)")
                LabeledContent("Board readings", value: "\(store.boardSampleCount)")
                LabeledContent("Phone readings", value: "\(store.phoneSampleCount)")
                LabeledContent("Other AirPod", value: "\(store.rejectedHeadphoneCount)")
                LabeledContent("Motion permission", value: store.headphonePermission)
                LabeledContent("Sensor available", value: store.headphoneAvailable ? "Yes" : "No")
                LabeledContent("Sensor stream active", value: store.headphoneStreamActive ? "Yes" : "No")
                LabeledContent("Detected side", value: store.headphoneDetectedSide)
                Text(store.headphoneStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                LabeledContent("Audio output", value: store.audioOutput)
                HStack {
                    Text("AirPods audio route")
                    Spacer()
                    AirPodsAudioRoutePicker()
                        .frame(width: 44, height: 44)
                }
                Button("Wake AirPod") { store.wakeAirPods() }
                Button("Retry sensor") { store.retryHeadphones() }
                    .disabled(!store.isRecording)
                Text(store.audioWakeStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Sync sessions over cellular", isOn: $store.cloudSyncEnabled)
                LabeledContent("Cloud status", value: store.cloudStatus)
                LabeledContent("Queued packets", value: "\(store.pendingCloudBatches)")
                LabeledContent("Rules version", value: "\(store.remoteRulesVersion)")
                if !store.sessionId.isEmpty {
                    Text("Session \(store.sessionId)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button("Refresh cloud") { store.forceCloudSync() }
                Link("Open live dashboard", destination: store.liveDashboardURL)
                if let file = store.exportedFile {
                    ShareLink("Export recording as CSV", item: file)
                }
                Button("Run synthetic manual demo") { store.runSyntheticManualDemo() }
                    .disabled(store.isRecording)
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
            .font(.subheadline)
        } label: {
            HStack {
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text("Sensors · cloud · CSV")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.teal)
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectionHelpContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(store.boardSensorReady ? "Board sensor is ready" : "Waiting for AirPod motion",
                      systemImage: store.boardSensorReady ? "checkmark.circle.fill" : "airpodspro")
                    .font(.headline)
                    .foregroundStyle(store.boardSensorReady ? Color.green : Color.orange)
                Text("Tape one AirPod securely to the board. Keep the other in its case. Turn off Automatic Ear Detection and choose the mounted AirPod as the microphone in your iPhone's Bluetooth settings.")
                    .font(.subheadline)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio output")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.audioOutput)
                            .font(.subheadline)
                    }
                    Spacer()
                    AirPodsAudioRoutePicker()
                        .frame(width: 54, height: 50)
                }

                Button {
                    store.wakeAirPods()
                } label: {
                    Label("Wake AirPod", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Button("Retry connection") { store.retryHeadphones() }
                    .buttonStyle(.bordered)
                Text(store.audioWakeStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(store.headphoneStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("AirPod readings", value: "\(store.headphoneTotalSamples)")
            }
        }
    }

    private func shortName(for pose: CalibrationPose) -> String {
        switch pose {
        case .wheelsDown: return "Flat"
        case .tailContact: return "Tail down"
        case .noseContact: return "Nose down"
        }
    }

    private func instruction(for pose: CalibrationPose) -> String {
        switch pose {
        case .wheelsDown: return "all four wheels on the ground"
        case .tailContact: return "the tail on the ground"
        case .noseContact: return "the nose on the ground"
        }
    }

    private func icon(for pose: CalibrationPose) -> String {
        switch pose {
        case .wheelsDown: return "minus"
        case .tailContact: return "arrow.up.right"
        case .noseContact: return "arrow.up.left"
        }
    }
}

/// A live side-profile skateboard. It is drawn with native SwiftUI shapes,
/// not a static image, and follows the calibrated AirPod pitch.
struct BoardAngleCard: View {
    let pitch: Double?
    let calibrated: Bool
    let recording: Bool
    let manualLimit: Double

    private var angle: Double { pitch ?? 0 }
    private var isManualRange: Bool {
        calibrated && abs(angle) >= 6 && abs(angle) < manualLimit
    }

    private var angleLabel: String {
        guard calibrated, let pitch else { return "Awaiting calibration" }
        if abs(pitch) < 3 { return "Level" }
        if pitch > 0 { return isManualRange ? "Manual range" : "Nose up" }
        return isManualRange ? "Nose manual range" : "Tail up"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Board angle")
                    .font(.headline)
                Spacer()
                if recording {
                    Label("LIVE", systemImage: "circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
            Text(calibrated && pitch != nil ? String(format: "%+.1f°", angle) : "—")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel(calibrated && pitch != nil ?
                                    String(format: "Board angle %.1f degrees", angle) :
                                    "Board angle requires calibration")

            BoardProfile(angle: angle, active: calibrated && pitch != nil)
                .frame(height: 172)
                .animation(.easeOut(duration: 0.13), value: angle)

            HStack(spacing: 8) {
                Image(systemName: isManualRange ? "circle.inset.filled" : "arrow.up.right")
                    .foregroundStyle(isManualRange ? Color.teal : Color.secondary)
                Text(angleLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Tail ←      → Nose")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct BoardProfile: View {
    let angle: Double
    let active: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let deckWidth = min(width * 0.77, 295)
            let displayedAngle = min(40, max(-40, angle))

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: height * 0.83))
                    path.addLine(to: CGPoint(x: width - 10, y: height * 0.83))
                }
                .stroke(Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))

                ZStack {
                    // Raised, rounded deck with a thin griptape surface.
                    Capsule()
                        .fill(Color.primary.opacity(active ? 0.86 : 0.46))
                        .frame(width: deckWidth, height: 13)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(Color(uiColor: .systemBackground).opacity(0.65))
                                .frame(width: deckWidth * 0.93, height: 2.5)
                                .offset(y: 1)
                        }
                        .offset(y: -17)

                    // Truck axles and all four wheels shown as two profiles.
                    ForEach([-1.0, 1.0], id: \.self) { side in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary)
                            .frame(width: 7, height: 17)
                            .offset(x: side * deckWidth * 0.29, y: -3)

                        Circle()
                            .fill(Color(uiColor: .systemBackground))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().stroke(Color.primary.opacity(0.8), lineWidth: 3)
                            }
                            .overlay {
                                Circle().fill(Color.secondary).frame(width: 5, height: 5)
                            }
                            .offset(x: side * deckWidth * 0.29, y: 13)
                    }
                }
                .rotationEffect(.degrees(-displayedAngle))
                .position(x: width / 2, y: height * 0.45)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The stock iOS audio route selector. Nothing forces a specific earbud.
struct AirPodsAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .systemTeal
        view.activeTintColor = .systemGreen
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
