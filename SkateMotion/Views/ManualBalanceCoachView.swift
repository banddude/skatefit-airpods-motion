import SwiftUI
import UIKit

/// Manual practice, based on the rigidly mounted AirPod's deck orientation.
/// Hold times are orientation-qualified estimates, not measured wheel contact.
struct ManualBalanceCoachView: View {
    @ObservedObject var store: MotionStore
    var openCalibration: () -> Void = {}

    @StateObject private var gps = PhoneRideSpeedMonitor()
    @AppStorage("runner.haptics") private var hapticsEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    private let dark = Color(red: 0.035, green: 0.065, blue: 0.13)
    private let panel = Color(red: 0.09, green: 0.13, blue: 0.21)
    private let accent = Color(red: 0.46, green: 0.96, blue: 0.78)

    private var practice: ManualBalanceSnapshot { store.balance }
    private var config: ManualBalanceSettings { store.balanceSettings }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                header
                sessionControls
                if store.isRecording { sensorQualityCard }
                if store.hasCalibration && store.isRecording && store.boardSensorReady {
                    liveCoach
                } else {
                    setupInstructions
                }
                nextTrainingGoals
                trainingGoals
                lastAttemptCard
                rawSensorDetails
                locationPanel
                recentPractice
                Text("SENSORS ONLY. AirPod gravity, gyro, acceleration and attitude determine board pose. Optional iPhone GPS only gives travel speed. No camera, no verified wheel contact, no absolute board XYZ, and no claim that a real manual was landed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
        }
        .background(dark.ignoresSafeArea())
        .foregroundStyle(.white)
        .onChange(of: store.balance.completedGoals) { old, new in
            if hapticsEnabled && new > old {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { gps.stop() }
        }
        .onDisappear { gps.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AIRPOD SENSORS · MANUAL PRACTICE", systemImage: "airpodspro")
                .font(.caption.weight(.black))
                .tracking(2)
                .foregroundStyle(accent)
            Text("MANUAL BALANCE")
                .font(.system(size: 31, weight: .black, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Train manuals and nose manuals with an AirPod mounted to your deck. See what ended each hold, correct your balance, and build consistency.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.73))
        }
    }

    private var sessionControls: some View {
        HStack(spacing: 10) {
            Button {
                if store.isRecording { store.stopRecording() }
                else { store.startRecording() }
            } label: {
                Label(store.isRecording ? "SAVE SESSION" : "START PRACTICE",
                      systemImage: store.isRecording ? "stop.fill" : "play.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(dark)
            .background(store.isRecording ? Color.orange : accent,
                        in: RoundedRectangle(cornerRadius: 14))
            Button { openCalibration() } label: {
                Label("CALIBRATE", systemImage: "scope")
                    .font(.caption.weight(.bold))
                    .frame(minHeight: 48)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("SET UP YOUR BOARD", systemImage: "airpodspro")
                .font(.headline.weight(.black))
                .foregroundStyle(.orange)
            Text(!store.isRecording
                 ? "Start Practice, attach one AirPod securely to the skateboard, and follow the flat / tail / nose calibration."
                 : (!store.hasCalibration
                    ? "Capture all three calibration positions in Motion Lab. Keep the board still during each hold."
                    : "Waiting for fresh motion readings from the board-mounted AirPod."))
                .font(.subheadline)
            Label("Sensor data must come from the AirPod on your deck, not the phone or an ear-worn AirPod.",
                  systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button("OPEN BOARD CALIBRATION") { openCalibration() }
                .buttonStyle(.borderedProminent).tint(accent)
                .foregroundStyle(dark)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var sensorQualityCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: store.boardSensorReady
                      ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.boardSensorReady ? accent : .orange)
                Text("SENSOR QUALITY")
                    .font(.caption.weight(.black))
                    .tracking(1.3)
                Spacer()
                Text(store.boardStreamState)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(store.boardSensorReady ? accent : .orange)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 9) {
                metric("SAMPLES", "\(store.boardHealth.accepted)", "waveform.path")
                metric("RATE",
                       String(format: "%.0f Hz", store.boardHealth.sampleRateHz),
                       "speedometer")
                metric("GAPS", "\(store.boardHealth.interruptions)", "wifi.exclamationmark")
            }
            if store.boardHealth.rejected > 0 {
                Text("\(store.boardHealth.rejected) rejected frames. Latest: \(store.boardHealth.latestRejection ?? "unknown")")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text("Only data from the selected board AirPod counts. Invalid, duplicate and disconnected samples never improve a training score.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.64))
        }
        .padding(14)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("airpodSensorHealth")
    }

    private var nextTrainingGoals: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(accent)
                Text("YOUR NEXT MILESTONES")
                    .font(.subheadline.weight(.black))
            }
            HStack(spacing: 10) {
                nextGoalButton(for: .manual)
                nextGoalButton(for: .noseManual)
            }
            Text("Milestones use your saved personal bests. They measure board orientation holds, not confirmed wheel contact.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(15)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func nextGoalButton(for side: ManualSide) -> some View {
        let best = ManualPracticeInsights.personalBest(
            for: side, sessions: store.savedManualPractices)
        let next = ManualPracticeInsights.recommendedGoal(
            for: side, sessions: store.savedManualPractices)
        return Button {
            store.balanceSettings.goalSeconds = next
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(side == .manual ? "MANUAL" : "NOSE MANUAL")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.75))
                Text(String(format: "%.0f SEC", next))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                Text(String(format: "Best %.1fs · Set goal", best))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(dark, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(side == .manual ? "nextManualGoal" : "nextNoseGoal")
    }

    @ViewBuilder private var lastAttemptCard: some View {
        if let last = practice.lastCompletedHold {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("LAST QUALIFIED HOLD")
                        .font(.subheadline.weight(.black))
                    Spacer()
                    Text(last.reachedGoal ? "GOAL REACHED" : "KEEP PRACTICING")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(last.reachedGoal ? accent : .yellow)
                }
                HStack(spacing: 9) {
                    metric(last.side.rawValue.uppercased(),
                           String(format: "%.2fs", last.seconds),
                           "timer")
                    metric("ANGLE", String(format: "%.1f°", last.averageAngleDegrees),
                           "angle")
                    metric("WOBBLE", String(format: "%.1f°", last.wobbleRMSDegrees),
                           "waveform.path")
                }
                Label("Ended: \(last.endedBy.rawValue)", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text("Stability \(Int(last.averageStability))% · Mean sideways tilt " +
                     String(format: "%.1f°", last.averageSideTiltDegrees))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(15)
            .background(panel, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var liveCoach: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(practice.status)
                    .font(.subheadline.weight(.black))
                    .tracking(1)
                    .foregroundStyle(practice.isInverted ? .orange : accent)
                Spacer()
                Text(store.latestOrientation?.fullAttitudeAvailable == true
                     ? "FULL 3D ROTATION" : "GRAVITY TILT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Board3DView(orientation: store.latestOrientation)
                .frame(height: 235)
                .background(dark, in: RoundedRectangle(cornerRadius: 17))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%+.1f°", practice.pitchDegrees))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    Text(practice.isInverted ? "DECK INVERTED" :
                         practice.pitchDegrees >= 0 ? "NOSE UP" : "TAIL UP")
                        .font(.caption2.weight(.bold)).tracking(1.4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2fs", practice.currentHoldSeconds))
                        .font(.system(size: 35, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("CURRENT HOLD")
                        .font(.caption2.weight(.bold)).tracking(1.4)
                }
            }

            Text(practice.coach)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(practice.isInverted ? .orange : .white)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("BALANCE ANGLE")
                        .font(.caption2.weight(.heavy))
                    Spacer()
                    Text("TARGET \(Int(config.targetAngleDegrees))° ±\(Int(config.toleranceDegrees))°")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(accent)
                }
                GeometryReader { geometry in
                    let w = geometry.size.width
                    let maximum: Double = 36
                    let low = max(0, config.targetAngleDegrees - config.toleranceDegrees)
                    let high = config.targetAngleDegrees + config.toleranceDegrees
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.13))
                        Capsule().fill(accent.opacity(0.55))
                            .frame(width: w * (high - low) / maximum)
                            .offset(x: w * low / maximum)
                        Capsule().fill(.white)
                            .frame(width: 4)
                            .offset(x: w * min(1, abs(practice.pitchDegrees) / maximum))
                    }
                }
                .frame(height: 13)
                .accessibilityLabel("Angle \(Int(abs(practice.pitchDegrees))) degrees, target \(Int(config.targetAngleDegrees)) degrees")
            }

            HStack(spacing: 10) {
                metric("STABILITY", "\(Int(practice.stability))%", "waveform.path")
                metric("SIDE TILT", String(format: "%.1f°", abs(practice.rollDegrees)), "arrow.left.and.right")
                metric("WOBBLE", String(format: "%.1f°", practice.wobbleRMSE), "waveform")
            }
            if practice.currentGoalAchieved {
                Label("HOLD GOAL COMPLETE", systemImage: "star.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.yellow)
            }
            Label(store.latestOrientation?.deckFace ?? "Unknown deck face",
                  systemImage: practice.isInverted ? "arrow.down.circle.fill" : "rotate.3d")
                .font(.caption.weight(.semibold))
                .foregroundStyle(practice.isInverted ? .orange : accent)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 19))
    }

    private var trainingGoals: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAINING GOAL").font(.headline.weight(.black))
            HStack {
                Text("Target nose/tail angle")
                Spacer()
                Text("\(Int(config.targetAngleDegrees))°").monospacedDigit().bold()
            }
            Slider(value: Binding(
                get: { store.balanceSettings.targetAngleDegrees },
                set: { store.balanceSettings.targetAngleDegrees = $0 }),
                in: 7...20, step: 1).tint(accent)
            HStack {
                Text("Angle tolerance")
                Spacer()
                Text("±\(Int(config.toleranceDegrees))°").monospacedDigit().bold()
            }
            Slider(value: Binding(
                get: { store.balanceSettings.toleranceDegrees },
                set: { store.balanceSettings.toleranceDegrees = $0 }),
                in: 2...8, step: 1).tint(accent)
            HStack {
                Text("Hold goal")
                Spacer()
                Text("\(Int(config.goalSeconds)) seconds").monospacedDigit().bold()
            }
            Slider(value: Binding(
                get: { store.balanceSettings.goalSeconds },
                set: { store.balanceSettings.goalSeconds = $0 }),
                in: 1...60, step: 1).tint(accent)

            HStack(spacing: 9) {
                metric("BEST MANUAL",
                       String(format: "%.1fs", practice.longestManualSeconds),
                       "arrow.up.forward")
                metric("BEST NOSE",
                       String(format: "%.1fs", practice.longestNoseManualSeconds),
                       "arrow.down.forward")
            }
            HStack {
                Label("\(practice.manualAttempts + practice.noseManualAttempts) measured holds",
                      systemImage: "chart.bar")
                Spacer()
                Label("\(practice.completedGoals) goals", systemImage: "star")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(17)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var rawSensorDetails: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                sensorRow("Accepted sensor rate",
                          String(format: "%.1f Hz", practice.sampleRateHz))
                sensorRow("Relative yaw (not compass)",
                          String(format: "%+.1f°", practice.relativeYawDegrees))
                sensorRow("Pitch angular rate",
                          String(format: "%.1f°/s", practice.pitchRateDegreesPerSecond))
                sensorRow("Roll angular rate",
                          String(format: "%.1f°/s", practice.rollRateDegreesPerSecond))
                sensorRow("Yaw angular rate",
                          String(format: "%.1f°/s", practice.yawRateDegreesPerSecond))
                sensorRow("User acceleration",
                          String(format: "%.2f g", practice.userAccelerationG))
                if let acceleration = store.latestBoardAcceleration {
                    sensorRow("Acceleration x/y/z",
                        String(format: "%.2f / %.2f / %.2f g",
                               acceleration.x, acceleration.y, acceleration.z))
                }
                if let rotation = store.latestBoardRotationRate {
                    sensorRow("Gyro x/y/z",
                        String(format: "%.2f / %.2f / %.2f rad/s",
                               rotation.x, rotation.y, rotation.z))
                }
                Text("Recorded CSV also includes gravity x/y/z, attitude quaternion w/x/y/z, sensor timestamps and raw fused yaw/pitch/roll. Angles are relative to calibration.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.top, 11)
        } label: {
            Label("ALL-AXIS SENSOR DETAILS", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.black))
                .foregroundStyle(accent)
        }
        .tint(accent)
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func sensorRow(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 7)
            Text(value).monospacedDigit()
                .multilineTextAlignment(.trailing)
        }.font(.caption)
    }

    private var locationPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("OUTDOOR SPEED", systemImage: "location.circle")
                    .font(.subheadline.weight(.black))
                Spacer()
                Button(gps.tracking ? "Stop GPS" : "Use iPhone GPS") {
                    if gps.tracking { gps.stop() }
                    else { gps.start() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(accent)
            }
            if let mph = gps.milesPerHour {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", mph))
                        .font(.system(size: 29, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("mph · from the iPhone, not the board")
                        .font(.caption)
                }
                if let uncertainty = gps.horizontalAccuracyMeters {
                    Text(String(format: "Horizontal location uncertainty radius: %.0f m", uncertainty))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let speedAccuracy = gps.speedAccuracyMetersPerSecond {
                    Text(String(format: "Speed accuracy estimate: ±%.1f mph", speedAccuracy * 2.2369362921))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Text(gps.status)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text("Optional, while app is open. No route or coordinates stored or uploaded. GPS cannot identify manual balance, individual tricks, board height, or exact board X/Y/Z.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var recentPractice: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("SAVED PRACTICE").font(.headline.weight(.black))
            if !store.savedManualPractices.isEmpty {
                let best = store.savedManualPractices.map(\.bestManualSeconds).max() ?? 0
                let noseBest = store.savedManualPractices.map(\.bestNoseSeconds).max() ?? 0
                HStack(spacing: 9) {
                    metric("ALL-TIME MANUAL", String(format: "%.1fs", best), "trophy")
                    metric("ALL-TIME NOSE", String(format: "%.1fs", noseBest), "trophy")
                }
            }
            if store.savedManualPractices.isEmpty {
                Text("Complete a motion-recording session to save your best manual and nose-manual holds locally.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let delta = ManualPracticeInsights.improvement(
                for: .manual, sessions: store.savedManualPractices) {
                Text(String(format: "Latest manual best vs previous session: %+.1f seconds", delta))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delta >= 0 ? accent : .orange)
            }
            ForEach(Array(store.savedManualPractices.prefix(6))) { session in
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.finishedAt, style: .date)
                            .font(.caption.weight(.semibold))
                        Text("\(session.manualAttempts + session.noseManualAttempts) qualified holds · \(session.goalsReached) goals")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(format: "%.1f / %.1fs",
                                    session.bestManualSeconds, session.bestNoseSeconds))
                            .font(.caption.monospacedDigit().bold())
                        if let attempts = session.attempts {
                            Text("\(attempts.count) detailed holds")
                                .font(.caption2)
                                .foregroundStyle(accent)
                        }
                    }
                }
                if let last = session.qualifiedHolds.last {
                    Text(String(format: "Last hold: %.1fs · %.1f° wobble · %@",
                                last.seconds, last.wobbleRMSDegrees,
                                last.endedBy.rawValue))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Divider().overlay(.white.opacity(0.12))
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ name: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).foregroundStyle(accent)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(dark.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }
}
