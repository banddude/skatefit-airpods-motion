import SwiftUI
import Combine
import GameController

/// TV-first layout and focus controls, not a scaled-up portrait iPhone screen.
/// All live board evidence originates in the explicitly paired iPhone.
struct SkateTVRootView: View {
    enum Page: String, CaseIterable { case manuals = "Manuals", play = "Play", courses = "Courses", progress = "Progress", pair = "Pair iPhone" }
    @StateObject private var receiver = TVBoardReceiver()
    @State private var game = TVGameSession()
    @State private var page: Page = .manuals
    @State private var inGame = false
    @State private var selectedCourse = 1
    @State private var lastTick = ProcessInfo.processInfo.systemUptime
    @State private var remoteManualUntil = 0.0
    @State private var remoteNoseUntil = 0.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ticker = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private let background = Color(red: 0.025, green: 0.045, blue: 0.095)
    private let panel = Color(red: 0.07, green: 0.105, blue: 0.17)
    private let accent = Color.mint
    private var frame: TVBoardFrame? { receiver.frame }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if !inGame {
                HStack(spacing: 25) {
                    Label("SKATEFIT", systemImage: "figure.skating")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                    Spacer()
                    ForEach(Page.allCases, id: \.self) { item in
                        Button(item.rawValue) { page = item }
                            .tint(page == item ? accent : .white)
                            .accessibilityIdentifier("tvPage\(item.rawValue)")
                    }
                }
                HStack {
                    Label(frame != nil ? "LIVE BOARD VIA IPHONE" : receiver.isPaired ? "IPHONE PAIRED · WAITING FOR BOARD" : "BOARD SENSOR NOT CONNECTED",
                          systemImage: frame != nil ? "airpodspro" : "iphone.gen3.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(frame != nil ? accent : .orange)
                    Spacer()
                    Text("AIRPOD + SENSORS ONLY").font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            if inGame { gameScreen }
            else {
                switch page {
                case .manuals: practiceScreen
                case .play: playScreen
                case .courses: courseScreen
                case .progress: progressScreen
                case .pair: pairingScreen
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 42)
        .preferredColorScheme(.dark)
        .background(background.ignoresSafeArea())
        .onReceive(ticker) { _ in tick() }
        .onPlayPauseCommand {
            guard inGame else { return }
            if game.phase == .paused { game.resume(frame: frame) }
            else { game.pause() }
        }
        .onExitCommand {
            if inGame && (game.phase == .playing || game.phase == .armed) { game.pause() }
            else if inGame { game.leave(); inGame = false }
            else { page = .manuals }
        }
        .onChange(of: scenePhase) { _, next in
            if next != .active {
                game.pause()
                receiver.stop()
                remoteManualUntil = 0; remoteNoseUntil = 0
            }
        }
    }

    private var practiceScreen: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 16) {
                Text("MANUAL BALANCE").font(.system(size: 50, weight: .black, design: .rounded))
                Text("Small corrections. Longer holds.").font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Board3DView(orientation: frame?.orientation)
                    .frame(height: 365)
                    .background(panel, in: RoundedRectangle(cornerRadius: 24))
                Text(frame?.orientation?.deckFace ?? "Pair an iPhone and calibrate the mounted AirPod")
                    .font(.headline).foregroundStyle(accent)
                Text("Sensor orientation only. Absolute position, wheel contact and landed tricks are not measured.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    metric("CURRENT HOLD", frame.map { String(format: "%.2fs", $0.holdSeconds) } ?? "—")
                    metric("NOSE / TAIL", frame?.orientation.map { String(format: "%+.1f°", $0.pitchDegrees) } ?? "—")
                }
                HStack(spacing: 20) {
                    metric("SIDE TILT", frame?.orientation.map { String(format: "%+.1f°", $0.rollDegrees) } ?? "—")
                    metric("WOBBLE RMS", frame.map { String(format: "%.1f°", $0.wobbleDegrees) } ?? "—")
                }
                HStack(spacing: 20) {
                    metric("SESSION MANUAL BEST", frame.map { String(format: "%.2fs", $0.bestManualSeconds) } ?? "—")
                    metric("SESSION NOSE BEST", frame.map { String(format: "%.2fs", $0.bestNoseSeconds) } ?? "—")
                }
                if let frame {
                    ProgressView(value: min(frame.holdSeconds, frame.goalSeconds), total: frame.goalSeconds)
                        .tint(accent)
                    Text(String(format: "Goal %.0fs · Stability %.0f%% · Sensor %.0f Hz", frame.goalSeconds, frame.stability, frame.sampleRate))
                        .font(.callout)
                    Text(receiver.roundTripMilliseconds.map { String(format: "Local network round trip: %.0f ms", $0) } ?? "")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(receiver.status).font(.callout)
                    Button("Pair iPhone") { page = .pair }
                        .accessibilityIdentifier("tvPairFromPractice")
                }
                Text("Calibrate and set practice goals on your iPhone. Keep SkateFit open there; it saves the raw motion and detailed practice history.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var pairingScreen: some View {
        HStack(alignment: .top, spacing: 55) {
            VStack(alignment: .leading, spacing: 24) {
                Text("BRING YOUR BOARD\nTO THE BIG SCREEN")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                Text("AirPod → iPhone → Apple TV")
                    .font(.title2.weight(.bold)).foregroundStyle(accent)
                Text("Keep the board AirPod connected to the iPhone, not directly to the TV. Both devices need the new SkateFit builds and the same local network.")
                    .font(.title3).fixedSize(horizontal: false, vertical: true)
                Text("On iPhone, tap the Apple TV icon. Choose Find Apple TV, select the matching TV name and enter the code shown here. Then start your motion session and calibrate flat, tail, and nose.")
                    .font(.callout).foregroundStyle(.white.opacity(0.75))
                Text("Session-only encrypted pairing. No camera, account, internet server, or GPS sharing. The code expires after two minutes if unused.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 25) {
                Image(systemName: "appletv.fill").font(.system(size: 76)).foregroundStyle(accent)
                Text(receiver.serviceName.isEmpty ? "SkateFit Apple TV" : receiver.serviceName).font(.title2.weight(.bold))
                if !receiver.pairingCode.isEmpty && !receiver.isPaired {
                    let code = receiver.pairingCode
                    Text(String(code.prefix(5)) + " " + String(code.suffix(5)))
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .privacySensitive()
                        .accessibilityIdentifier("tvPairingCode")
                }
                Text(receiver.status).font(.callout)
                    .multilineTextAlignment(.center)
                if receiver.isHosting {
                    Button("Disconnect / Cancel pairing") { receiver.stop() }
                } else {
                    Button("Pair iPhone") { receiver.startHosting() }
                        .accessibilityIdentifier("tvStartPairing")
                }
                if receiver.isPaired {
                    Button("Manual practice") { page = .manuals }
                }
            }
            .padding(34)
            .frame(maxWidth: .infinity)
            .background(panel, in: RoundedRectangle(cornerRadius: 28))
        }
    }

    private var playScreen: some View {
        HStack(alignment: .top, spacing: 36) {
            RunnerSceneView(engine: game.engine, deckColor: accent,
                            reduceMotion: reduceMotion, highContrast: false)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 24) {
                Text("MANUAL RUNNER").font(.system(size: 44, weight: .black, design: .rounded))
                Text(RunnerCourse.get(selectedCourse).name).font(.title2)
                Text("15 courses. Pop gaps with a nose-up manual; duck by lifting the tail. Board-controlled runs wait for a real tilt before moving.")
                    .font(.title3).foregroundStyle(.white.opacity(0.75))
                Button("Ride with board AirPod") { begin(.motion) }
                    .disabled(frame == nil)
                    .accessibilityIdentifier("tvRideWithBoard")
                if frame == nil { Button("Connect iPhone first") { page = .pair } }
                Button("Play with remote / controller") { begin(.touch) }
                    .accessibilityIdentifier("tvPlayController")
                Text("Siri Remote: up to pop, down to duck, Play/Pause to pause. Gamepad: hold A for manual, B for nose manual. Controller play is separate from sensor-based training.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var courseScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("FIVE WORLDS · FIFTEEN STAGES").font(.title.weight(.black))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                    ForEach(RunnerCourse.catalog) { course in
                        let unlocked = game.progress.career.isUnlocked(course)
                        Button {
                            selectedCourse = course.id
                            game.engine.reset(course: course.id)
                            page = .play
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("WORLD \(course.worldNumber) · STAGE \(course.stageNumber)").font(.caption)
                                Text(course.name).font(.headline)
                                Text(unlocked ? "\(game.progress.career.records[course.id]?.bestStars ?? 0) / 3 stars" : "Locked")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(!unlocked)
                    }
                }.padding(20)
            }
        }
    }

    private var progressScreen: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("YOUR TV RUNS").font(.largeTitle.weight(.black))
            HStack(spacing: 24) {
                metric("STARS", "\(game.progress.career.totalStars) / 45")
                metric("BOARD FINISHES", "\(game.progress.career.motionControlledRuns)")
                metric("CONTROLLER FINISHES", "\(game.progress.career.touchRuns)")
            }
            Text("TV game progress is stored on this Apple TV, separately from iPhone game progress. Sensor practice records and raw CSV remain on the iPhone. No cloud sync is implemented for TV progress.")
                .font(.title3).foregroundStyle(.white.opacity(0.75))
            if let error = game.progress.saveError { Text(error).foregroundStyle(.orange) }
        }
    }

    private var gameScreen: some View {
        VStack(spacing: 16) {
            HStack {
                Text(game.engine.course.name).font(.title2.weight(.black))
                Spacer()
                Text(game.source == .motion ? "BOARD AIRPOD VIA IPHONE" : "REMOTE / CONTROLLER")
                    .font(.headline).foregroundStyle(accent)
                Text("\(game.engine.score) PTS · \(game.engine.lives) LIVES")
                    .font(.headline.monospacedDigit())
            }
            HStack(alignment: .top, spacing: 32) {
                RunnerSceneView(engine: game.engine, deckColor: accent,
                    reduceMotion: reduceMotion, highContrast: false,
                    livePitchDegrees: game.source == .motion ? frame?.orientation?.pitchDegrees : nil)
                    .frame(maxWidth: .infinity)
                    .focusable(game.phase == .playing || game.phase == .armed)
                    .onMoveCommand { direction in
                        guard game.source == .touch else { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        if direction == .up { remoteManualUntil = now + 0.18 }
                        if direction == .down { remoteNoseUntil = now + 0.9 }
                    }
                    .accessibilityIdentifier("tvGameSurface")
                VStack(alignment: .leading, spacing: 20) {
                    Text(game.engine.nextCue).font(.title2.weight(.black))
                    Text(game.engine.message).font(.title3).foregroundStyle(accent)
                    Text(game.currentInput.label).font(.headline)
                    if game.source == .motion {
                        Board3DView(orientation: frame?.orientation)
                            .frame(height: 200)
                        Text(frame?.orientation.map { String(format: "Pitch %+.1f° · Roll %+.1f°", $0.pitchDegrees, $0.rollDegrees) } ?? "No fresh board signal")
                            .font(.callout.monospacedDigit())
                    }
                    if game.phase == .armed {
                        Text("TILT YOUR BOARD TO START").font(.headline).foregroundStyle(.yellow)
                    }
                    if game.phase == .paused {
                        Text(game.message).font(.callout).foregroundStyle(.orange)
                        Button("Resume") { game.resume(frame: frame) }
                    } else if game.phase == .finished {
                        Text(game.engine.won ? "COURSE COMPLETE · \(game.engine.stars) STARS" : "WIPEOUT")
                            .font(.headline).foregroundStyle(.yellow)
                        Button("Retry") { begin(game.source) }
                    } else {
                        Button("Pause") { game.pause() }
                    }
                    Button("Back to menu") { game.leave(); inGame = false }
                        .accessibilityIdentifier("tvBackToMenu")
                }
                .frame(width: 480)
                .padding(24)
                .background(panel, in: RoundedRectangle(cornerRadius: 24))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.65))
            Text(value).font(.system(size: 35, weight: .black, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private func begin(_ source: RunnerControlSource) {
        if game.start(course: selectedCourse, source: source, frame: frame) {
            inGame = true
            remoteManualUntil = 0; remoteNoseUntil = 0
            lastTick = ProcessInfo.processInfo.systemUptime
        }
    }

    private func tick() {
        guard inGame else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.08, max(0, now - lastTick))
        lastTick = now
        let pad = GCController.controllers().compactMap(\.extendedGamepad).first
        let controller = RunnerInput(
            manual: now < remoteManualUntil || pad?.buttonA.isPressed == true || pad?.rightTrigger.isPressed == true,
            noseManual: now < remoteNoseUntil || pad?.buttonB.isPressed == true || pad?.leftTrigger.isPressed == true)
        game.advance(dt: dt, frame: frame, controller: controller)
    }
}
