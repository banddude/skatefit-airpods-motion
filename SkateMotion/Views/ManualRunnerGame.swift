import SwiftUI
import SpriteKit
import UIKit

/// Platform runner controlled by calibrated board pitch. Positive pitch is
/// nose-up/manual; negative pitch is nose-manual. Phone-only demo controls
/// are explicitly labeled and do not count as real skating.
struct ManualRunnerGame: View {
    @ObservedObject var store: MotionStore
    @State private var engine = RunnerEngine()
    @State private var lastTick = Date()
    @State private var demoPitch = 0.0
    @State private var demoMode = false
    @State private var playing = false
    @AppStorage("runner.bestScore") private var bestScore = 0
    @AppStorage("runner.unlockedLevel") private var unlockedLevel = 1
    @State private var selectedLevel = 1
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("MANUAL RUNNER").font(.title2.bold())
                    Text("Nose up = jump · Nose down = duck")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("LEVEL \(engine.level)").font(.headline.monospacedDigit())
            }
            Picker("Course", selection: $selectedLevel) {
                ForEach(1...5, id: \.self) { n in
                    Text("Course \(n)").tag(n)
                }
            }
            .pickerStyle(.segmented)
            .disabled(playing)
            .onChange(of: selectedLevel) { _, value in
                if value > unlockedLevel { selectedLevel = unlockedLevel }
                engine.reset(course: selectedLevel)
            }
            RunnerSceneView(engine: engine)
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .top) {
                    HStack {
                        Label("\(engine.score)", systemImage: "star.fill")
                        Spacer()
                        Label("\(engine.lives)", systemImage: "heart.fill")
                    }
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding()
                }
            HStack {
                Text(engine.message)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%+.0f°", demoMode ? demoPitch :
                            (store.latestOrientation?.pitchDegrees ?? 0)))
                    .monospacedDigit()
            }
            Toggle("Practice with screen controls", isOn: $demoMode)
                .font(.subheadline)
            Text(demoMode ? "PRACTICE MODE · Scores do not count as sensor-verified." :
                 (store.hasCalibration ? "AIRPOD CONTROLS" : "Calibrate in Setup & Lab or use practice controls."))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if demoMode {
                HStack {
                    Button("NOSE MANUAL / DUCK") { demoPitch = -16 }
                    Button("FLAT") { demoPitch = 0 }
                    Button("MANUAL / JUMP") { demoPitch = 16 }
                }
                .buttonStyle(.bordered)
                .font(.caption2)
            }
            Button(playing ? "Pause runner" : (engine.gameOver ? "Retry level" : "Play runner")) {
                if engine.gameOver { engine.reset(course: selectedLevel) }
                if !playing && !demoMode && !store.hasCalibration { return }
                playing.toggle()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!playing && !demoMode && !store.hasCalibration)
            HStack {
                Label("BEST \(bestScore)", systemImage: "crown.fill")
                Spacer()
                Text("UNLOCKED \(unlockedLevel)/5")
            }
            .font(.caption.weight(.bold))
            Text("Hold a manual to jump over gaps. Hold a nose manual to duck under obstacles. Collect stars, avoid hazards, reach the finish.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(ticker) { now in
            guard playing else { lastTick = now; return }
            let dt = min(0.08, max(0, now.timeIntervalSince(lastTick)))
            lastTick = now
            let pitch = demoMode ? demoPitch : (store.latestOrientation?.pitchDegrees ?? 0)
            engine.advance(dt: dt, pitch: pitch)
            if engine.gameOver {
                playing = false
                if engine.won && !demoMode {
                    bestScore = max(bestScore, engine.score)
                    unlockedLevel = min(5, max(unlockedLevel, selectedLevel + 1))
                }
            }
        }
    }
}

@Observable final class RunnerEngine {
    var score = 0
    var lives = 3
    var level = 1
    var distance = 0.0
    var height = 0.0
    var velocity = 0.0
    var crouching = false
    var message = "Ready to roll"
    var gameOver = false
    var won = false
    var obstacles: [RunnerObstacle] = []
    var combo = 0
    var progress: Double { min(1, distance / courseLength) }
    var courseLength: Double { 95 + Double(level) * 20 }
    private var nextSpawn = 10.0
    private var lastPitch = 0.0
    private var spawnIndex = 0
    private var invulnerable = 0.0
    private var jumpBuffer = 0.0

    func reset(course: Int = 1) {
        score = 0; lives = 3; level = max(1, min(5, course)); distance = 0
        height = 0; velocity = 0; crouching = false; gameOver = false
        won = false; nextSpawn = 10; obstacles = []; lastPitch = 0
        spawnIndex = 0; combo = 0; invulnerable = 0; jumpBuffer = 0
        message = "Ready to roll"
    }

    func advance(dt rawDt: Double, pitch: Double) {
        guard !gameOver else { return }
        let dt = min(0.05, max(0, rawDt))
        guard dt > 0 else { return }
        let speed = 4.0 + Double(level) * 0.35
        distance += speed * dt
        invulnerable = max(0, invulnerable - dt)
        jumpBuffer = max(0, jumpBuffer - dt)
        crouching = pitch < -9 && height < 0.12
        // A buffered rising edge supports timing a jump shortly before a gap.
        if pitch > 9 && lastPitch <= 9 { jumpBuffer = 0.22 }
        lastPitch = pitch
        if jumpBuffer > 0 && height <= 0.01 && !crouching {
            velocity = 6.5
            jumpBuffer = 0
            message = "MANUAL JUMP!"
        }
        if height > 0 || velocity > 0 {
            height = max(0, height + velocity * dt)
            velocity -= 15 * dt
            if height == 0 { velocity = 0 }
        }
        nextSpawn -= speed * dt
        if nextSpawn <= 0 && distance < courseLength - 18 {
            let pattern = [0, 1, 2, 1, 0, 2, 0, 1, 2]
            let kind = pattern[(spawnIndex + level - 1) % pattern.count]
            obstacles.append(RunnerObstacle(x: 16,
                kind: kind == 0 ? .gap : kind == 1 ? .barrier : .overhead))
            spawnIndex += 1
            nextSpawn += 13 + Double(spawnIndex % 2) * 2
        }
        for i in obstacles.indices { obstacles[i].x -= speed * dt }
        for i in obstacles.indices where !obstacles[i].resolved && obstacles[i].x < 3.5 {
            // Player is at x≈3.7 on the 16-unit playfield.
            obstacles[i].resolved = true
            let obstacle = obstacles[i]
            let passed: Bool
            switch obstacle.kind {
            case .gap: passed = height > 0.48
            case .barrier: passed = height > 0.65
            case .overhead: passed = crouching
            }
            if passed {
                combo += 1
                score += 100 * min(5, combo)
                message = combo > 1 ? "COMBO x\(combo)!" :
                    (obstacle.kind == .overhead ? "NOSE MANUAL!" : "CLEAN!")
            } else if invulnerable == 0 {
                lives -= 1
                combo = 0
                invulnerable = 1.0
                message = "OUCH!"
                if lives <= 0 { gameOver = true; message = "GAME OVER" }
            }
        }
        obstacles.removeAll { $0.x < -3 }
        if distance >= courseLength && !gameOver {
            gameOver = true
            won = true
            score += lives * 250
            message = "COURSE CLEARED!"
        }
    }
}

struct RunnerObstacle: Identifiable {
    enum Kind { case gap, barrier, overhead }
    let id = UUID()
    var x: Double
    let kind: Kind
    var resolved = false
}

struct RunnerSceneView: View {
    let engine: RunnerEngine

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(colors: [.cyan.opacity(0.7), .blue.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(.yellow.opacity(0.8))
                    .frame(width: 70, height: 70)
                    .position(x: w * 0.82, y: 55)
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.18))
                        .frame(width: 95, height: 34)
                        .position(x: CGFloat(i) * 95 -
                                  CGFloat(engine.distance.truncatingRemainder(dividingBy: 95)),
                                  y: h * 0.42 + CGFloat(i % 2) * 16)
                }
                Rectangle().fill(.indigo)
                    .frame(height: h * 0.24)
                    .position(x: w / 2, y: h * 0.88)
                Rectangle().fill(.mint)
                    .frame(height: 5)
                    .position(x: w / 2, y: h * 0.76)
                Rectangle().fill(.yellow)
                    .frame(width: w * CGFloat(engine.progress), height: 5)
                    .position(x: w * CGFloat(engine.progress) / 2, y: 5)
                ForEach(engine.obstacles) { obstacle in
                    let x = w * CGFloat(obstacle.x / 16)
                    Group {
                        switch obstacle.kind {
                        case .gap:
                            Rectangle().fill(.black).frame(width: 44, height: 17)
                        case .barrier:
                            RoundedRectangle(cornerRadius: 5).fill(.orange)
                                .frame(width: 29, height: 47)
                        case .overhead:
                            RoundedRectangle(cornerRadius: 5).fill(.purple)
                                .frame(width: 55, height: 17)
                        }
                    }
                    .position(x: x, y: obstacle.kind == .overhead ? h * 0.57 : h * 0.75)
                }
                ZStack {
                    Capsule().fill(.black).frame(width: 63, height: 9)
                    HStack(spacing: 28) {
                        Circle().fill(.white).frame(width: 13, height: 13)
                        Circle().fill(.white).frame(width: 13, height: 13)
                    }.offset(y: 8)
                }
                .rotationEffect(.degrees(engine.crouching ? -13 : 0))
                .position(x: w * 0.23, y: h * 0.72 - CGFloat(engine.height) * 50)
            }
            .clipped()
        }
    }
}
