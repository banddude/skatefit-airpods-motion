import SwiftUI

/// Progression rewards actual recorded activity, not unverified landings.
struct SkateProgress {
    let sessions: Int
    let minutes: Int
    let xp: Int
    let level: Int
    let nextLevelXP: Int
    let impactSpikes: Int
    let possibleTricks: Int
    let manualSeconds: Int

    init(_ saved: [SavedSkateSession]) {
        let real = saved.filter { !$0.isSynthetic && $0.endedAt != nil }
        sessions = real.count
        minutes = Int(real.reduce(0.0) { $0 + $1.stats.durationSeconds } / 60)
        impactSpikes = real.reduce(0) { $0 + $1.stats.impactSpikes }
        possibleTricks = real.reduce(0) { $0 + $1.stats.possibleEvents }
        manualSeconds = Int(real.reduce(0.0) {
            $0 + $1.stats.manualAngleSeconds + $1.stats.noseManualAngleSeconds
        })
        // No XP for unverified tricks; rewards recording and practice only.
        xp = sessions * 50 + minutes * 5
        level = xp / 250 + 1
        nextLevelXP = level * 250
    }
}

struct SkateGameCard: View {
    let sessions: [SavedSkateSession]
    let current: SessionStatistics
    let recording: Bool

    private var progress: SkateProgress { SkateProgress(sessions) }
    private var xpInLevel: Int { progress.xp % 250 }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEVEL \(progress.level)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.teal)
                    Text("\(progress.xp) XP")
                        .font(.title.bold().monospacedDigit())
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
            }
            ProgressView(value: Double(xpInLevel), total: 250)
                .tint(.teal)
            Text("\(250 - xpInLevel) XP to next level")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("CHALLENGES")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            challenge("First Push", subtitle: "Save your first session",
                      value: progress.sessions, goal: 1, icon: "figure.skating")
            challenge("Keep Rolling", subtitle: "Record 10 minutes total",
                      value: progress.minutes, goal: 10, icon: "timer")
            challenge("Session Streak", subtitle: "Complete 5 sessions",
                      value: progress.sessions, goal: 5, icon: "flame")
            challenge("Practice Pays", subtitle: "Record 60 minutes total",
                      value: progress.minutes, goal: 60, icon: "star.fill")

            if recording {
                Label("Current session: \(current.boardSamples) board samples",
                      systemImage: "waveform.path")
                    .font(.caption)
                    .foregroundStyle(.teal)
            }
            Text("XP is awarded for saved practice time and sessions. Motion detections are possible tricks, not verified landings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private func challenge(_ name: String, subtitle: String,
                           value: Int, goal: Int, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: value >= goal ? "checkmark.seal.fill" : icon)
                .foregroundStyle(value >= goal ? Color.green : Color.teal)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(min(value, goal)), total: Double(goal))
                    .tint(value >= goal ? .green : .teal)
            }
            Spacer()
            Text("\(min(value, goal))/\(goal)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
