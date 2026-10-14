import SwiftUI
import Combine
import UIKit
import GameController
import AudioToolbox

private enum RunnerPage: String, CaseIterable, Identifiable {
    case play = "Play"
    case worlds = "Worlds"
    case challenges = "Goals"
    case collection = "Decks"
    case profile = "Profile"
    case settings = "Settings"
    case run = "Run"
    case coach = "Balance"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.fill"
        case .worlds: return "map.fill"
        case .challenges: return "target"
        case .collection: return "square.stack.3d.up.fill"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape"
        case .run: return "figure.skating"
        case .coach: return "scope"
        }
    }
}

private enum RunnerPhase: Equatable {
    case active, paused, finished
}

/// Offline-first platform adventure. Real board motion is an OPTIONAL controller.
/// Touch/gamepad runs can finish every course and unlock every cosmetic.
struct ManualRunnerGame: View {
    @ObservedObject var store: MotionStore
    var openMotionLab: () -> Void = {}

    @State private var engine = RunnerEngine()
    @State private var progress = RunnerProgressStore()
    @State private var page: RunnerPage = .play
    @State private var phase: RunnerPhase = .paused
    @AppStorage("runner.selectedCourseID") private var selectedLevel = 1
    @State private var manualHeld = false
    @State private var noseHeld = false
    @State private var queuedManual = false
    @State private var accessibleNoseRemaining = 0.0
    @State private var motionAdapter = RunnerMotionAdapter()
    @State private var lastTick = Date()
    @State private var lastFeedbackEvent = 0
    @State private var sensorDropped = false

    @AppStorage("runner.controlMode") private var controlModeRaw = "Touch"
    @AppStorage("runner.haptics") private var hapticsEnabled = true
    @AppStorage("runner.sound") private var soundEnabled = false
    @AppStorage("runner.lowMotion") private var reduceSceneMotion = false
    @AppStorage("runner.highContrast") private var highContrast = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let background = Color(red: 0.035, green: 0.055, blue: 0.125)
    private let soft = Color(red: 0.09, green: 0.12, blue: 0.22)
    private let accent = Color(red: 0.47, green: 0.98, blue: 0.78)

    private var mode: RunnerControlMode {
        RunnerControlMode(rawValue: controlModeRaw) ?? .touch
    }

    private var motionReady: Bool {
        store.gameMotionReady
    }

    private var course: RunnerCourse { RunnerCourse.get(selectedLevel) }

    private var deckColor: Color {
        switch progress.career.selectedDeck {
        case "Sunset": return .orange
        case "Electric": return .cyan
        case "Gold": return .yellow
        case "Midnight": return .purple
        case "Streetlight": return .pink
        case "Ice": return .white
        case "Legend": return .red
        default: return .mint
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if page == .run {
                runScreen
            } else if page == .coach {
                VStack(spacing: 0) {
                    HStack {
                        Button { page = .play } label: {
                            Label("Back to SkateFit", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(accent)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    ManualBalanceCoachView(store: store, openCalibration: openMotionLab)
                }
            } else {
                menuHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .play: playHome
                        case .worlds: worldList
                        case .challenges: challengesScreen
                        case .collection: collectionScreen
                        case .profile: profileScreen
                        case .settings: settingsScreen
                        case .run, .coach: EmptyView()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                menuBar
            }
        }
        .foregroundStyle(.white)
        .background(background.ignoresSafeArea())
        .onReceive(ticker) { now in tick(now) }
        .onAppear {
            // Old beta selections and corrupted preferences cannot navigate
            // outside the known course catalog.
            let validated = RunnerCourse.get(selectedLevel).id
            if selectedLevel != validated { selectedLevel = validated }
            if page != .run && engine.level != validated {
                engine.reset(course: validated)
            }
        }
        .onChange(of: scenePhase) { _, next in
            if next != .active && phase == .active {
                pause()
            }
        }
        .onDisappear {
            if phase == .active { pause() }
        }
    }

    private var menuHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.gradient)
                    .frame(width: 43, height: 43)
                Image(systemName: "figure.skating")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(background)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("SKATEFIT").font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(2)
                Text("MANUAL RUNNER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(3).foregroundStyle(accent)
            }
            Spacer()
            Button { page = .settings } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(soft, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Game settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var playHome: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("THIS IS YOUR LINE").font(.caption2.weight(.black))
                    .tracking(2).foregroundStyle(accent)
                Text("Ride the rhythm.")
                    .font(.system(size: 35, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("Pop gaps with a manual. Duck under beams with a nose manual. Find the perfect run.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Button { page = .coach } label: {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.17))
                            .frame(width: 62, height: 68)
                        Image(systemName: "scope")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("START HERE · REAL SKATE TRAINING")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.0).foregroundStyle(accent)
                        Text("Manual Balance Coach")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                        Text("Hold time · target angle · wobble · progress")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(accent)
                }
                .padding(13)
                .background(soft, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openManualBalanceCoach")

            ZStack(alignment: .bottomLeading) {
                RunnerSceneView(engine: engine, deckColor: deckColor,
                                reduceMotion: reduceSceneMotion || systemReduceMotion,
                                highContrast: highContrast)
                LinearGradient(colors: [.clear, background.opacity(0.76)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 23))
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WORLD \(course.worldNumber) · STAGE \(course.stageNumber)/3")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(accent)
                        Text(course.name).font(.title2.weight(.heavy))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.title2.weight(.semibold))
                }
                .padding(19)
            }
            .accessibilityElement(children: .combine)

            Button { startCourse() } label: {
                Label("DROP IN", systemImage: "play.fill")
                    .font(.headline.weight(.black)).tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.plain)
            .background(accent, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(background)
            .disabled(mode == .motion && !motionReady)
            if mode == .motion && !motionReady {
                Button("Play with touch controls instead") {
                    controlModeRaw = RunnerControlMode.touch.rawValue
                    startCourse()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                statTile(value: "\(progress.career.totalStars)/45", label: "STARS", icon: "star.fill")
                statTile(value: "\(progress.career.playerLevel)", label: "RIDER LVL", icon: "bolt.fill")
                statTile(value: "\(progress.career.completedRuns)", label: "FINISHES", icon: "flag.fill")
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR NEXT CHALLENGE").font(.caption2.bold())
                        .tracking(1.5).foregroundStyle(accent)
                    Text("Earn all three stars")
                        .font(.headline)
                    Text("Finish, stay clean, collect pickups and hold your balance lines.")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(.yellow)
            }
            .panel()
        }
    }

    private var worldList: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("15 stages. Five worlds.",
                           subtitle: "Three unique stages in each world. Beat a stage to unlock the next.")
            ForEach(1...5, id: \.self) { number in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("0\(number)")
                            .font(.system(size: 31, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("WORLD \(number)")
                                .font(.caption2.weight(.black)).tracking(1.5)
                                .foregroundStyle(accent)
                            Text(RunnerCourse.worldNames[number - 1].capitalized)
                                .font(.title3.weight(.heavy))
                        }
                        Spacer()
                        let completed = RunnerCourse.catalog.filter {
                            $0.worldNumber == number &&
                            progress.career.records[$0.id] != nil
                        }.count
                        Text("\(completed)/3")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    ForEach(RunnerCourse.catalog.filter { $0.worldNumber == number }) { stage in
                        let unlocked = progress.career.isUnlocked(stage)
                        Button {
                            if unlocked {
                                selectedLevel = stage.id
                                engine.reset(course: stage.id)
                                page = .play
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(unlocked ? accent.opacity(0.17) : background)
                                        .frame(width: 47, height: 55)
                                    Image(systemName: unlocked ? "figure.skating" : "lock.fill")
                                        .font(.title3)
                                        .foregroundStyle(unlocked ? accent : .gray)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("STAGE \(stage.stageNumber) · \(stage.name)")
                                        .font(.subheadline.weight(.bold))
                                        .multilineTextAlignment(.leading)
                                    Text(stage.description)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Text("\(progress.career.records[stage.id]?.bestStars ?? 0) ★")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(unlocked ? .yellow : .gray)
                            }
                            .padding(12)
                            .background(soft, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                        .disabled(!unlocked)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var challengesScreen: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("Chase the line.", subtitle: "Keep improving every run.")
            challenge("First drop", detail: "Finish one course",
                      value: progress.career.completedRuns, target: 1,
                      symbol: "flag.checkered")
            challenge("Star collector", detail: "Collect 24 course stars",
                      value: progress.career.totalStars, target: 24,
                      symbol: "star.fill")
            challenge("No bails", detail: "Finish 3 courses without a hit",
                      value: progress.career.cleanRuns, target: 3,
                      symbol: "shield.fill")
            challenge("Manual master", detail: "Complete 12 manual balance lines",
                      value: progress.career.totalManualLines, target: 12,
                      symbol: "arrow.up.right")
            challenge("Nose manual ninja", detail: "Complete 12 nose manual lines",
                      value: progress.career.totalNoseLines, target: 12,
                      symbol: "arrow.down.right")
            challenge("World tour", detail: "Finish all fifteen stages",
                      value: progress.career.records.count, target: 15,
                      symbol: "globe.americas.fill")
            Text("These are game accomplishments, not verified real-world skateboard tricks.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var collectionScreen: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("Make it yours.", subtitle: "Earn stars to unlock deck colors.")
            ForEach(RunnerDeck.all) { deck in
                let unlocked = progress.career.totalStars >= deck.requiredStars
                let selected = progress.career.selectedDeck == deck.id
                Button {
                    if unlocked { progress.chooseDeck(deck.id) }
                } label: {
                    HStack(spacing: 15) {
                        Capsule().fill(color(for: deck.id).gradient)
                            .frame(width: 68, height: 14)
                            .rotationEffect(.degrees(-14))
                            .padding(.horizontal, 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deck.id).font(.headline.weight(.bold))
                            Text(unlocked ? (selected ? "EQUIPPED" : "Tap to equip") :
                                   "Unlock at \(deck.requiredStars) stars")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" :
                                unlocked ? "circle" : "lock.fill")
                            .foregroundStyle(selected ? accent : .gray)
                    }
                    .padding(17)
                    .background(soft, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
            }
        }
    }

    private var profileScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Built on practice.", subtitle: "Your career saves on this device.")
            HStack(spacing: 11) {
                statTile(value: "\(progress.career.totalXP)", label: "XP", icon: "bolt.fill")
                statTile(value: "\(progress.career.completedRuns)", label: "RUNS", icon: "flag.fill")
                statTile(value: "\(progress.career.totalPickups)", label: "PICKUPS", icon: "star.fill")
            }
            infoRow("Touch finishes", value: "\(progress.career.touchRuns)")
            infoRow("Motion-controlled finishes",
                    value: "\(progress.career.motionControlledRuns)")
            infoRow("Clean finishes", value: "\(progress.career.cleanRuns)")
            infoRow("Manual lines", value: "\(progress.career.totalManualLines)")
            infoRow("Nose manual lines", value: "\(progress.career.totalNoseLines)")
            Text("BEST LINES")
                .font(.caption2.weight(.black)).tracking(2).foregroundStyle(accent)
            ForEach(RunnerCourse.catalog) { world in
                if let result = progress.career.records[world.id] {
                    HStack {
                        Text(world.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(result.bestScore) pts  ·  \(result.bestStars) ★")
                            .font(.caption.monospacedDigit())
                    }
                    .panel()
                }
            }
            if progress.recoveredFromBackup {
                Label("Previous progress recovered from backup", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(accent)
            }
            if let error = progress.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("AirPods controls measure device motion only. They cannot confirm that a trick was landed.")
                .font(.caption).foregroundStyle(.white.opacity(0.58))
        }
    }

    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionHeading("Your ride, your rules.",
                           subtitle: "AirPods are optional. Touch and supported gamepads work offline.")
            VStack(alignment: .leading, spacing: 10) {
                Text("CONTROLS").font(.caption2.bold()).tracking(1.3).foregroundStyle(accent)
                Picker("Control method", selection: $controlModeRaw) {
                    ForEach(RunnerControlMode.allCases, id: \.rawValue) {
                        Text($0.rawValue).tag($0.rawValue)
                    }
                }.pickerStyle(.segmented)
                Text(mode == .touch ?
                     "Hold MANUAL to pop and balance. Hold NOSE MANUAL to duck and balance. Gamepad A / B also work." :
                     "Hold a calibrated board-mounted AirPod at nose-up or nose-down pitch. Start a motion session first.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                if mode == .motion {
                    Label(motionReady ? "Motion controls connected" :
                            "Start recording and calibrate in the Motion Lab",
                          systemImage: motionReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(motionReady ? accent : .orange)
                    Button("Open Motion Lab") { openMotionLab() }
                        .buttonStyle(.bordered).tint(accent)
                }
            }
            .panel()
            Toggle("Vibration feedback", isOn: $hapticsEnabled).panel()
            Toggle("System sound effects", isOn: $soundEnabled).panel()
            Toggle("Reduced background motion", isOn: $reduceSceneMotion).panel()
            Toggle("High contrast", isOn: $highContrast).panel()
            VStack(alignment: .leading, spacing: 11) {
                Text("HOW TO BUILD A PERFECT LINE")
                    .font(.caption2.weight(.black)).tracking(1.4)
                    .foregroundStyle(accent)
                Text("1  MANUAL pops over street gaps and barriers.")
                Text("2  NOSE MANUAL ducks under beams and neon gates.")
                Text("3  Hold either balance pose on its matching glowing strip to charge your Flow Meter.")
                Text("4  Filled Flow doubles your score. Finish clean, grab pickups and hold balance lines to earn all three stars.")
                Text("5  Green launch ramps automatically give you extra height for the long chasms.")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .panel()
            Button("Open recorder and 3D calibration") { openMotionLab() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
            Text("The game is playable offline. Scores and cosmetic unlocks stay on this iPhone. The separate Motion Lab can upload diagnostic telemetry if sync is enabled there.")
                .font(.caption).foregroundStyle(.white.opacity(0.62))
        }
        .tint(accent)
    }

    private var menuBar: some View {
        HStack(spacing: 2) {
            ForEach([RunnerPage.play, .worlds, .challenges, .collection, .profile]) { item in
                Button {
                    page = item
                    if item == .play {
                        engine.reset(course: selectedLevel)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                        Text(item.rawValue).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(page == item ? accent : .white.opacity(0.52))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(soft)
    }

    private var runScreen: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button {
                        pause()
                        page = .play
                        engine.reset(course: selectedLevel)
                    } label: {
                        Label("Exit", systemImage: "chevron.left")
                    }
                    .font(.subheadline.weight(.bold))
                    Spacer()
                    VStack(spacing: 3) {
                        Text("WORLD \(course.worldNumber) · \(course.stageNumber)/3")
                            .font(.system(size: 10, weight: .black)).tracking(2)
                            .foregroundStyle(accent)
                        Text(course.name).font(.subheadline.weight(.bold))
                    }
                    Spacer()
                    Button {
                        if phase == .active { pause() }
                        else if phase == .paused && !sensorDropped { resume() }
                    } label: {
                        Image(systemName: phase == .active ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                            .background(soft, in: Circle())
                    }
                    .disabled(phase == .finished)
                    .accessibilityLabel(phase == .active ? "Pause" : "Resume")
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    Label("\(engine.lives)", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                    Label("\(engine.pickups)", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                    Spacer()
                    Text("\(engine.score) PTS")
                        .font(.subheadline.weight(.black).monospacedDigit())
                        .foregroundStyle(accent)
                    Text(String(format: "%.0fs", engine.elapsed))
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 5)

                HStack(spacing: 9) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundStyle(engine.cueSeconds < 2.6 ? .yellow : accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT")
                            .font(.system(size: 9, weight: .black)).tracking(1.8)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(engine.nextCue)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if engine.nextAction != nil {
                        Text(String(format: "%.1fs", engine.cueSeconds))
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(engine.cueSeconds < 2.6 ? .yellow : accent)
                    }
                }
                .padding(11)
                .background(soft, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)

                RunnerSceneView(engine: engine, deckColor: deckColor,
                                reduceMotion: reduceSceneMotion || systemReduceMotion,
                                highContrast: highContrast)


                HStack(spacing: 8) {
                    Image(systemName: engine.eventKind == "damage" ?
                          "exclamationmark.triangle.fill" : "bolt.circle.fill")
                    Text(engine.message)
                    Spacer()
                    Text("\(Int(engine.progress * 100))%")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(engine.eventKind == "damage" ? .orange : accent)
                .padding(.horizontal, 5)

                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("FLOW METER").font(.caption2.weight(.black)).tracking(1)
                            Spacer()
                            Text("x\(engine.flowMultiplier) SCORE")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(engine.flowMultiplier > 1 ? .yellow : .white.opacity(0.6))
                        }
                        ProgressView(value: engine.flowEnergy).tint(engine.flowMultiplier > 1 ? .yellow : accent)
                    }
                }
                .padding(12)
                .background(soft, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Flow meter \(Int(engine.flowEnergy * 100)) percent, multiplier \(engine.flowMultiplier)")

                if phase == .active && mode == .touch {
                    touchPads
                } else if phase == .active {
                    HStack {
                        Image(systemName: "airpodspro")
                        Text("Tilt the board: nose up = manual pop · nose down = duck")
                    }
                    .font(.caption).foregroundStyle(accent)
                    .frame(maxWidth: .infinity).padding(20).panel()
                }

                if phase != .active {
                    resultPanel
                } else {
                    HStack {
                        Label(mode == .touch ? "TOUCH / GAMEPAD" : "AIRPODS MOTION",
                              systemImage: mode == .touch ? "hand.tap.fill" : "waveform.path")
                        Spacer()
                        Text("Manual + Nose Manual")
                    }
                    .font(.caption2.bold()).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var touchPads: some View {
        HStack(spacing: 12) {
            actionPad("MANUAL", detail: "POP / BALANCE", symbol: "arrow.up.right",
                      active: manualHeld, color: accent)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !manualHeld { queuedManual = true }
                        manualHeld = true
                    }
                    .onEnded { _ in manualHeld = false })
                .accessibilityAction { queuedManual = true }
                .accessibilityLabel("Manual jump. Hold to balance.")
                .accessibilityAddTraits(.isButton)
            actionPad("NOSE MANUAL", detail: "DUCK / BALANCE", symbol: "arrow.down.right",
                      active: noseHeld, color: .cyan)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in noseHeld = true }
                    .onEnded { _ in noseHeld = false })
                .accessibilityAction { accessibleNoseRemaining = 1.1 }
                .accessibilityLabel("Nose manual. Hold to duck.")
                .accessibilityAddTraits(.isButton)
        }
        .frame(height: 106)
    }

    private func actionPad(_ name: String, detail: String, symbol: String,
                           active: Bool, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2.weight(.black))
            Text(name).font(.system(size: 12, weight: .black)).tracking(0.9)
            Text(detail).font(.system(size: 9, weight: .bold)).tracking(0.5)
        }
        .foregroundStyle(active ? background : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? color : soft, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(color.opacity(active ? 1 : 0.5), lineWidth: 1.5))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var resultPanel: some View {
        VStack(spacing: 13) {
            if phase == .finished {
                Image(systemName: engine.won ? "trophy.fill" : "heart.slash.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(engine.won ? .yellow : .pink)
                Text(engine.won ? "LINE COMPLETE" : "YOU BAILED")
                    .font(.title2.weight(.black)).tracking(1)
                if engine.won {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < engine.stars ? "star.fill" : "star")
                                .font(.system(size: 33))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text("\(engine.score) points · \(engine.pickups) pickups · " +
                         String(format: "%.1fs", engine.elapsed))
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text("Try again from your last checkpoint.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Button("RETRY COURSE") { startCourse() }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .frame(maxWidth: .infinity)
                if engine.won,
                   let next = RunnerCourse.next(after: selectedLevel),
                   progress.career.isUnlocked(next) {
                    Button("NEXT STAGE") {
                        selectedLevel = next.id
                        startCourse()
                    }
                    .buttonStyle(.bordered).tint(accent)
                }
                if !engine.won && engine.checkpointDistance > 0 {
                    Button("RESTART FROM CHECKPOINT") {
                        engine.retryCheckpoint()
                        resume()
                    }
                    .buttonStyle(.bordered).tint(accent)
                }
            } else {
                Image(systemName: sensorDropped ? "wifi.exclamationmark" : "pause.circle.fill")
                    .font(.system(size: 38)).foregroundStyle(.yellow)
                Text(sensorDropped ? "SENSOR DISCONNECTED" : "PAUSED")
                    .font(.title3.weight(.black))
                Text(sensorDropped ?
                     "The AirPod stream stopped. Switch to touch to keep your progress." :
                     "Keep your line alive when you're ready.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(sensorDropped ? "SWITCH TO TOUCH" : "RESUME") {
                    if sensorDropped {
                        controlModeRaw = RunnerControlMode.touch.rawValue
                        sensorDropped = false
                    }
                    resume()
                }
                .buttonStyle(.borderedProminent).tint(accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(soft, in: RoundedRectangle(cornerRadius: 22))
    }

    private func startCourse() {
        guard mode != .motion || motionReady else { return }
        engine.reset(course: selectedLevel)
        page = .run
        phase = .active
        sensorDropped = false
        manualHeld = false
        noseHeld = false
        queuedManual = false
        accessibleNoseRemaining = 0
        motionAdapter.reset()
        lastFeedbackEvent = 0
        lastTick = Date()
    }

    private func pause() {
        phase = .paused
        manualHeld = false
        noseHeld = false
        queuedManual = false
        accessibleNoseRemaining = 0
    }

    private func resume() {
        guard mode != .motion || motionReady else {
            sensorDropped = true
            return
        }
        lastTick = Date()
        phase = .active
    }

    private func tick(_ now: Date) {
        guard page == .run, phase == .active else { return }
        let delta = min(0.08, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        if mode == .motion && !motionReady {
            sensorDropped = true
            pause()
            return
        }
        let gamepad = GCController.controllers().first?.extendedGamepad
        let micro = GCController.controllers().first?.microGamepad
        let gamepadManual = gamepad?.buttonA.isPressed == true ||
            gamepad?.rightTrigger.isPressed == true ||
            micro?.buttonA.isPressed == true
        let gamepadNose = gamepad?.buttonB.isPressed == true ||
            gamepad?.leftTrigger.isPressed == true ||
            micro?.buttonX.isPressed == true
        let input: RunnerInput
        if mode == .motion {
            input = motionAdapter.accept(pitch: store.gamePitch)
        } else {
            input = RunnerInput(manual: manualHeld || queuedManual || gamepadManual,
                                noseManual: noseHeld || accessibleNoseRemaining > 0 || gamepadNose)
        }
        engine.advance(dt: delta, input: input)
        accessibleNoseRemaining = max(0, accessibleNoseRemaining - delta)
        queuedManual = false
        if lastFeedbackEvent != engine.eventRevision {
            lastFeedbackEvent = engine.eventRevision
            playFeedback(kind: engine.eventKind)
        }
        if engine.gameOver {
            phase = .finished
            manualHeld = false
            noseHeld = false
            if engine.won {
                progress.recordCompletion(engine, mode: mode)
            }
        }
    }

    private func playFeedback(kind: String) {
        if hapticsEnabled {
            switch kind {
            case "damage": UINotificationFeedbackGenerator().notificationOccurred(.error)
            case "finish": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "pickup", "line", "boost": UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case "jump": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            default: break
            }
        }
        if soundEnabled && mode == .touch &&
            ["damage", "finish", "pickup", "jump"].contains(kind) {
            AudioServicesPlaySystemSound(kind == "damage" ? 1053 : 1104)
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(accent)
            Text(value)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .minimumScaleFactor(0.65).lineLimit(1)
            Text(label).font(.system(size: 10, weight: .bold))
                .tracking(1.1).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(soft, in: RoundedRectangle(cornerRadius: 17))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 30, weight: .black, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.65))
        }
        .padding(.bottom, 7)
    }

    private func challenge(_ title: String, detail: String, value: Int,
                           target: Int, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: value >= target ? "checkmark.seal.fill" : symbol)
                .font(.title2).foregroundStyle(value >= target ? .green : accent)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6))
                ProgressView(value: Double(min(value, target)), total: Double(target))
                    .tint(value >= target ? .green : accent)
            }
            Spacer(minLength: 4)
            Text("\(min(value, target))/\(target)")
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
        }
        .panel()
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
        .font(.subheadline)
        .panel()
    }

    private func color(for name: String) -> Color {
        switch name {
        case "Sunset": return .orange
        case "Electric": return .cyan
        case "Gold": return .yellow
        case "Midnight": return .purple
        case "Streetlight": return .pink
        case "Ice": return .white
        case "Legend": return .red
        default: return .mint
        }
    }
}

private extension View {
    func panel() -> some View {
        self.padding(15)
            .background(Color(red: 0.09, green: 0.12, blue: 0.22),
                        in: RoundedRectangle(cornerRadius: 18))
    }
}
