import SwiftUI

struct ContentView: View {
    @StateObject private var store = MotionStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    Text(store.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Board-mounted AirPod", selection: $store.boardSide) {
                        ForEach(HeadphoneSide.allCases) { side in
                            Text(side.title).tag(side)
                        }
                    }
                    .disabled(store.isRecording)
                    Button(store.isRecording ? "Stop and export CSV" : "Start motion recording") {
                        if store.isRecording { store.stopRecording() }
                        else { store.startRecording() }
                    }
                    .font(.headline)
                    Text("Leave the other earbud in its case at first. Disable Automatic Ear Detection if needed. Keep the iPhone in your pocket.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("AirPods motion connection") {
                    Text(store.headphoneStatus)
                        .font(.subheadline)
                        .foregroundStyle(store.headphoneTotalSamples == 0 ? .orange : .green)
                    LabeledContent("Headphone sensor available", value: store.headphoneAvailable ? "Yes" : "No")
                    LabeledContent("Motion permission", value: store.headphonePermission)
                    LabeledContent("Stream active", value: store.headphoneStreamActive ? "Yes" : "No")
                    LabeledContent("Detected AirPod", value: store.headphoneDetectedSide.capitalized)
                    LabeledContent("AirPod sensor readings", value: "\(store.headphoneTotalSamples)")
                    Button("Retry AirPods connection") { store.retryHeadphones() }
                    Text("If only phone readings appear, open Settings → Bluetooth → your AirPods Pro. Verify Connected, turn Automatic Ear Detection OFF, and return here. You can temporarily wear one AirPod to confirm its motion sensors are working.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Live cloud development console") {
                    Toggle("Send motion data over cellular", isOn: $store.cloudSyncEnabled)
                    Text(store.cloudStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LabeledContent("Queued offline batches", value: "\(store.pendingCloudBatches)")
                    LabeledContent("Remote detection rules", value: "Version \(store.remoteRulesVersion)")
                    if store.isRecording {
                        Text("Session: \(store.sessionId)")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    Link(destination: store.liveDashboardURL) {
                        Label("Open remote dashboard", systemImage: "globe")
                    }
                    Button("Reconnect and refresh rules") { store.forceCloudSync() }
                    Text("Threshold changes made in the dashboard are fetched every 15 seconds. The same recordings can be reprocessed remotely without reinstalling the app. Live recording requires keeping the app active; iOS may suspend sensors in the background.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Board calibration") {
                    Text("Rigidly mount the selected AirPod. Hold each position still for 1.5 seconds while recording. No skating during calibration.")
                        .font(.footnote)
                    ForEach(CalibrationPose.allCases) { pose in
                        Button {
                            store.calibrate(pose)
                        } label: {
                            HStack {
                                Text(pose.rawValue)
                                Spacer()
                                if store.calibration.poses[pose] != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                if store.calibrationPose == pose {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(!store.isRecording || store.calibrationPose != nil)
                    }
                    if store.calibrationPose != nil {
                        ProgressView("Capturing board AirPod motion", value: store.calibrationProgress)
                    }
                    if store.isRecording && store.boardSampleCount == 0 {
                        Text("Calibration needs real AirPod samples. Phone-only uploads cannot complete it.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Text(store.hasCalibration
                         ? "Calibration accepted. Detection is enabled."
                         : "Recognition requires all three valid poses.")
                        .font(.footnote)
                        .foregroundStyle(store.hasCalibration ? .green : .secondary)
                }

                Section("Live telemetry") {
                    LabeledContent("Accepted AirPod samples", value: "\(store.boardSampleCount)")
                    LabeledContent("Phone samples", value: "\(store.phoneSampleCount)")
                    LabeledContent("Other AirPod samples", value: "\(store.rejectedHeadphoneCount)")
                    if let pitch = store.latestPitch {
                        LabeledContent("Board pitch", value: String(format: "%.1f°", pitch))
                    }
                    Text("Both streams include host arrival time and the sensor's timestamp. Arrival time is not precise hardware synchronization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Experimental event detection (\(store.events.count))") {
                    if store.events.isEmpty {
                        Text("Calibrate and record motion to find candidate manuals, board rotations, and impact sequences.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.events.suffix(15).reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.kind).font(.headline)
                            Text(String(format: "%.2f–%.2fs · heuristic confidence %.0f%%",
                                        event.start, event.end, event.confidence * 100))
                                .font(.caption)
                            Text(event.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Export and offline demo") {
                    if let url = store.exportedFile {
                        ShareLink(item: url) {
                            Label("Share session CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Run synthetic manual demo") { store.runSyntheticManualDemo() }
                        .disabled(store.isRecording)
                    Text("The demo uses generated readings, not AirPods or iPhone sensors. Impact/landing and named trick predictions are unvalidated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("SkateFit Motion Lab")
        }
    }
}
