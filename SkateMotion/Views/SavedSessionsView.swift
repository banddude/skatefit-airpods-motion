import SwiftUI

struct SessionStatisticsCard: View {
    let stats: SessionStatistics
    let recording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(recording ? "Current session" : "Session statistics")
                    .font(.headline)
                Spacer()
                if recording {
                    Label("REC", systemImage: "circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 10) {
                metric("Duration", SessionFormat.duration(stats.durationSeconds))
                metric("Board data", "\(stats.boardSamples)", note: "samples")
                metric("Possible events", "\(stats.possibleEvents)", note: "unverified")
            }
            HStack(spacing: 10) {
                metric("Peak acceleration",
                       String(format: "%.1f g", stats.peakBoardAccelerationG))
                metric("Impact spikes", "\(stats.impactSpikes)", note: "estimated")
                metric("Manual angle",
                       SessionFormat.duration(stats.manualAngleSeconds +
                                              stats.noseManualAngleSeconds),
                       note: "not landings")
            }

            Text("Rotation, impacts and manual-angle time are motion estimates, not confirmed tricks. Full measurements and session history are below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private func metric(_ title: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(value)
                .font(.headline.monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 67, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

enum SessionFormat {
    static func duration(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds))
        if rounded >= 3600 {
            return String(format: "%d:%02d:%02d",
                          rounded / 3600, (rounded / 60) % 60, rounded % 60)
        }
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

struct SavedSessionsView: View {
    @ObservedObject var store: MotionStore

    var body: some View {
        List {
            if store.savedSessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "figure.skating",
                    description: Text("Start a session, record your board, and stop to save statistics and a raw motion CSV."))
            } else {
                ForEach(store.savedSessions) { session in
                    NavigationLink {
                        SavedSessionDetailView(
                            session: session,
                            csvURL: store.savedCSV(for: session))
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.headline)
                                Spacer()
                                if session.isSynthetic {
                                    Text("DEMO")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("\(SessionFormat.duration(session.stats.durationSeconds)) · \(session.stats.boardSamples) board samples · \(session.stats.possibleEvents) possible events")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(session.endedAt == nil ?
                                 "Interrupted session (partial data saved)" :
                                 (session.calibrated ? "Calibrated" : "Not calibrated"))
                                .font(.caption)
                                .foregroundStyle(session.endedAt == nil ? .orange : .secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Saved sessions")
    }
}

struct SavedSessionDetailView: View {
    let session: SavedSkateSession
    let csvURL: URL

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Started", value: session.startedAt.formatted())
                LabeledContent("Duration", value: SessionFormat.duration(
                    session.stats.durationSeconds))
                LabeledContent("Board AirPod", value: session.boardSide.capitalized)
                LabeledContent("Calibrated", value: session.calibrated ? "Yes" : "No")
                if session.isSynthetic {
                    Text("SYNTHETIC DEMO DATA. Not actual skateboarding.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if session.endedAt == nil {
                    Text("Recording ended unexpectedly. Partial readings were kept.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Sensor recordings") {
                LabeledContent("Board samples", value: "\(session.stats.boardSamples)")
                LabeledContent("Phone samples", value: "\(session.stats.phoneSamples)")
                LabeledContent("Other earbud samples", value: "\(session.stats.otherEarbudSamples)")
                LabeledContent("Peak user acceleration",
                               value: String(format: "%.2f g", session.stats.peakBoardAccelerationG))
                LabeledContent("Peak angular velocity",
                               value: String(format: "%.2f rad/s",
                                             session.stats.peakBoardRotationRateRadS))
                LabeledContent("Impact spikes (estimated)",
                               value: "\(session.stats.impactSpikes)")
            }

            Section("3-axis motion") {
                LabeledContent("Maximum nose-up pitch",
                               value: String(format: "%.1f°", session.stats.peakNoseUpDegrees))
                LabeledContent("Maximum tail-up pitch",
                               value: String(format: "%.1f°", session.stats.peakTailUpDegrees))
                LabeledContent("Maximum absolute roll",
                               value: String(format: "%.1f°", session.stats.peakRollDegrees))
                LabeledContent("Maximum relative yaw",
                               value: String(format: "%.1f°", session.stats.peakRelativeYawDegrees))
                LabeledContent("Total pitch angular travel",
                               value: String(format: "%.0f°",
                                             session.stats.cumulativePitchRotationDegrees))
                LabeledContent("Total roll angular travel",
                               value: String(format: "%.0f°",
                                             session.stats.cumulativeRollRotationDegrees))
                LabeledContent("Total yaw angular travel",
                               value: String(format: "%.0f°",
                                             session.stats.cumulativeYawRotationDegrees))
                Text("Angular travel adds up movement in either direction. A value over 360° does not prove a completed 360 trick.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Estimated maneuvers") {
                LabeledContent("Possible events", value: "\(session.stats.possibleEvents)")
                LabeledContent("Possible manuals", value: "\(session.stats.possibleManuals)")
                LabeledContent("Possible nose manuals",
                               value: "\(session.stats.possibleNoseManuals)")
                LabeledContent("Possible flip/shove movements",
                               value: "\(session.stats.possibleFlipOrShoveEvents)")
                LabeledContent("Manual-angle hold",
                               value: SessionFormat.duration(session.stats.manualAngleSeconds))
                LabeledContent("Nose-manual-angle hold",
                               value: SessionFormat.duration(session.stats.noseManualAngleSeconds))
                ForEach(session.eventKinds.keys.sorted(), id: \.self) { name in
                    LabeledContent(name, value: "\(session.eventKinds[name] ?? 0)")
                }
                Text("Foot contact, bail versus landing, and board translation distance cannot be determined conclusively from AirPods motion alone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Export") {
                if FileManager.default.fileExists(atPath: csvURL.path) {
                    ShareLink(item: csvURL) {
                        Label("Share complete raw motion CSV",
                              systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text("Raw CSV file is missing on this device.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Session details")
    }
}
