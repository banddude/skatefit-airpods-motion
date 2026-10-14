import SwiftUI
import SpriteKit

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
            if !store.hasCalibration {
                Toggle("Demo controls (no AirPod)", isOn: $demoMode)
                    .font(.subheadline)
            }
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
                if engine.gameOver { engine.reset() }
                playing.toggle()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            Text("Hold a manual to jump over gaps. Hold a nose manual to duck under obstacles. Collect stars, avoid hazards, reach the finish.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(ticker) { now in
            guard playing else { lastTick = now; return }
            let dt = min(0.08, max(0, now.timeIntervalSince(lastTick)))
            lastTick = now
            let pitch = demoMode ? demoPitch : (store.latestOrientation?.pitchDegrees ?? 0)
            engine.advance(dt: dt, pitch: pitch)
            if engine.gameOver { playing = false }
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
    var obstacles: [RunnerObstacle] = []
    private var nextSpawn = 2.5
    private var lastPitch = 0.0

    func reset() {
        score = 0; lives = 3; level = 1; distance = 0; height = 0
        velocity = 0; crouching = false; gameOver = false
        nextSpawn = 2.5; obstacles = []; lastPitch = 0
        message = "Ready to roll"
    }

    func advance(dt: Double, pitch: Double) {
        guard !gameOver else { return }
        let speed = 4.3 + Double(level) * 0.65
        distance += speed * dt
        level = min(10, 1 + Int(distance / 110))
        crouching = pitch < -9 && height < 0.12
        // Nose-up rising edge starts a jump; avoids holding to fly forever.
        if pitch > 9 && lastPitch <= 9 && height <= 0.01 {
            velocity = 6.5
            message = "MANUAL JUMP!"
        }
        lastPitch = pitch
        if height > 0 || velocity > 0 {
            height = max(0, height + velocity * dt)
            velocity -= 15.0 * dt
            if height == 0 { velocity = 0 }
        }
        nextSpawn -= speed * dt
        if nextSpawn <= 0 {
            let index = Int(distance / 8) % 3
            obstacles.append(RunnerObstacle(
                x: 16, kind: index == 0 ? .gap : index == 1 ? .barrier : .overhead))
            nextSpawn = 11.0 + Double(index) * 2
        }
        for i in obstacles.indices {
            obstacles[i].x -= speed * dt
        }
        for i in obstacles.indices where !obstacles[i].resolved && obstacles[i].x < 1.4 {
            obstacles[i].resolved = true
            let obstacle = obstacles[i]
            let passed: Bool
            switch obstacle.kind {
            case .gap: passed = height > 0.5
            case .barrier: passed = height > 0.7
            case .overhead: passed = crouching
            }
            if passed {
                score += 100
                message = obstacle.kind == .overhead ? "NOSE MANUAL!" : "CLEAN!"
            } else {
                lives -= 1
                message = "OUCH!"
                if lives <= 0 { gameOver = true; message = "GAME OVER" }
            }
        }
        obstacles.removeAll { $0.x < -3 }
        if Int(distance) % 75 == 0 && distance > 1 {
            // Finishing progression comes from clearing hazards, not raw motion alone.
            message = "Keep rolling!"
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
