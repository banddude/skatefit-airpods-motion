import Foundation
import Observation

/// The game does not infer that an AirPod movement proves a landed trick.
/// Both input methods control the same deterministic simulation.
enum RunnerControlMode: String, Codable, CaseIterable {
    case touch = "Touch"
    case motion = "AirPods"
}

struct RunnerInput: Equatable, Codable {
    var manual = false
    var noseManual = false

    static func from(pitch: Double) -> RunnerInput {
        RunnerInput(manual: pitch > 9, noseManual: pitch < -9)
    }
}

enum RunnerFeatureKind: String, Codable {
    case gap, barrier, overhead, manualLine, noseLine, pickup, checkpoint

    var isHazard: Bool {
        switch self {
        case .gap, .barrier, .overhead: return true
        default: return false
        }
    }
}

struct RunnerFeature: Identifiable, Codable, Equatable {
    let id: String
    let kind: RunnerFeatureKind
    let at: Double
    let length: Double
    var resolved = false
    var failed = false
    var exposure = 0.0
    var heldTime = 0.0

    var end: Double { at + length }
}

struct RunnerCourse: Identifiable {
    let id: Int
    let name: String
    let world: String
    let description: String
    let speed: Double
    let length: Double
    let starTarget: Int
    let features: [RunnerFeature]

    static let catalog: [RunnerCourse] = (1...5).map(make)

    private static func make(_ world: Int) -> RunnerCourse {
        let names = ["First Light", "Concrete Dreams", "Neon Transit",
                     "Skyline Transfer", "The Impossible Line"]
        let worlds = ["NEIGHBORHOOD", "CONCRETE", "NEON", "SKYLINE", "FINALE"]
        let descriptions = [
            "Learn the language of manuals, gaps, and low rails.",
            "Chain nose manuals between bigger pop challenges.",
            "Flow through neon barriers and chase perfect combos.",
            "Master alternating balance lines above the city.",
            "One final run through everything you've learned."
        ]
        let rounds = world == 1 ? 12 : 7 + world
        let speed = 4.35 + Double(world - 1) * 0.22
        var features: [RunnerFeature] = []

        func add(_ kind: RunnerFeatureKind, _ at: Double,
                 _ length: Double = 1.0, _ section: Int, _ slot: Int) {
            features.append(RunnerFeature(id: "w\(world)s\(section)i\(slot)",
                                          kind: kind, at: at, length: length))
        }

        // Each 64-unit section is hand-patterned with generous separation.
        // A full jump occupies about four horizontal units, so consecutive
        // hazards are always separated by at least ten world units.
        let motifs: [[(Double, RunnerFeatureKind, Double)]] = [
            [(5, .gap, 1.5), (18, .barrier, 1), (32, .overhead, 1.7),
             (46, .manualLine, 4.0)],
            [(5, .noseLine, 4.2), (20, .overhead, 1.7),
             (35, .gap, 1.8), (49, .barrier, 1)],
            [(6, .barrier, 1), (20, .manualLine, 4.0),
             (34, .gap, 1.7), (49, .overhead, 1.7)],
            [(5, .gap, 1.7), (19, .noseLine, 4.0),
             (34, .overhead, 1.5), (49, .barrier, 1)]
        ]
        for section in 0..<rounds {
            let origin = 27.0 + Double(section) * 64.0
            let motif = motifs[(section + world - 1) % motifs.count]
            for (slot, pattern) in motif.enumerated() {
                add(pattern.1, origin + pattern.0, pattern.2, section, slot)
            }
            add(.pickup, origin + 12, 0.85, section, 4)
            add(.pickup, origin + 27, 0.85, section, 5)
            add(.pickup, origin + 57, 0.85, section, 6)
            if section == rounds / 2 - 1 {
                add(.checkpoint, origin + 61, 0.3, section, 7)
            }
        }
        features.sort { $0.at < $1.at }
        return RunnerCourse(id: world, name: names[world - 1],
                            world: worlds[world - 1],
                            description: descriptions[world - 1],
                            speed: speed,
                            length: 27 + Double(rounds) * 64 + 15,
                            starTarget: rounds * 2, features: features)
    }
}

/// A fixed 120 Hz, zero-randomness platform simulation. Presentation frame
/// rate and the physical sensor sampling rate do not determine its physics.
@Observable final class RunnerEngine {
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var level = 1
    private(set) var distance = 0.0
    private(set) var height = 0.0
    private(set) var velocity = 0.0
    private(set) var crouching = false
    private(set) var message = "Find your flow"
    private(set) var gameOver = false
    private(set) var won = false
    private(set) var combo = 0
    private(set) var pickups = 0
    private(set) var damageCount = 0
    private(set) var manualLines = 0
    private(set) var noseLines = 0
    private(set) var elapsed = 0.0
    private(set) var invulnerabilityTime = 0.0
    private(set) var checkpointDistance = 0.0
    private(set) var features: [RunnerFeature] = []
    private(set) var eventRevision = 0
    private(set) var eventKind = "ready"

    private var simulationRemainder = 0.0
    private var lastManual = false
    private var jumpBuffer = 0.0
    private var coyote = 0.0
    private var checkpointScore = 0
    private var checkpointPickups = 0
    private var checkpointDamage = 0
    private var checkpointManualLines = 0
    private var checkpointNoseLines = 0
    private var checkpointElapsed = 0.0

    var course: RunnerCourse { RunnerCourse.catalog[level - 1] }
    var courseLength: Double { course.length }
    var progress: Double { min(1, distance / courseLength) }
    var noHit: Bool { damageCount == 0 }
    var stars: Int {
        guard won else { return 0 }
        return 1 + (noHit ? 1 : 0) + (pickups >= course.starTarget ? 1 : 0)
    }

    init() { reset(course: 1) }

    func reset(course selected: Int = 1) {
        level = max(1, min(5, selected))
        score = 0
        lives = 3
        distance = 0
        height = 0
        velocity = 0
        crouching = false
        message = "Find your flow"
        gameOver = false
        won = false
        combo = 0
        pickups = 0
        damageCount = 0
        manualLines = 0
        noseLines = 0
        elapsed = 0
        invulnerabilityTime = 0
        checkpointDistance = 0
        features = course.features
        simulationRemainder = 0
        lastManual = false
        jumpBuffer = 0
        coyote = 0
        checkpointScore = 0
        checkpointPickups = 0
        checkpointDamage = 0
        checkpointManualLines = 0
        checkpointNoseLines = 0
        checkpointElapsed = 0
        eventRevision = 0
        eventKind = "ready"
    }

    func retryCheckpoint() {
        guard checkpointDistance > 0 else { reset(course: level); return }
        distance = checkpointDistance
        score = checkpointScore
        pickups = checkpointPickups
        damageCount = checkpointDamage
        manualLines = checkpointManualLines
        noseLines = checkpointNoseLines
        elapsed = checkpointElapsed
        lives = 2
        height = 0
        velocity = 0
        crouching = false
        combo = 0
        lastManual = false
        jumpBuffer = 0
        simulationRemainder = 0
        coyote = 0
        invulnerabilityTime = 1.0
        gameOver = false
        won = false
        features = course.features.map { feature in
            var feature = feature
            if feature.end < distance - 0.5 { feature.resolved = true }
            return feature
        }
        announce("Back on your board", kind: "checkpoint")
    }

    func advance(dt: Double, pitch: Double) {
        guard pitch.isFinite else { return }
        advance(dt: dt, input: .from(pitch: pitch))
    }

    func advance(dt: Double, input: RunnerInput) {
        guard !gameOver, dt.isFinite, dt >= 0 else { return }
        // Clamp tab-resume stalls; no simulated jumps through hidden obstacles.
        simulationRemainder += min(dt, 0.15)
        let step = 1.0 / 120.0
        var iterations = 0
        while simulationRemainder + 1e-12 >= step && iterations < 18 && !gameOver {
            advanceStep(dt: step, input: input)
            simulationRemainder -= step
            iterations += 1
        }
        simulationRemainder = max(0, simulationRemainder)
    }

    private func advanceStep(dt: Double, input: RunnerInput) {
        let grounded = height <= 0.001 && velocity <= 0
        elapsed += dt
        let speed = course.speed
        distance += speed * dt
        invulnerabilityTime = max(0, invulnerabilityTime - dt)
        jumpBuffer = max(0, jumpBuffer - dt)
        coyote = grounded ? 0.085 : max(0, coyote - dt)

        let holdingManual = input.manual && !input.noseManual
        crouching = input.noseManual && !holdingManual && grounded
        if holdingManual && !lastManual { jumpBuffer = 0.16 }
        lastManual = holdingManual

        // Ground jumps are triggered on an edge, not every frame of a hold.
        // A small buffer and coyote interval keep touchscreen timing forgiving.
        if jumpBuffer > 0 && coyote > 0 && !crouching {
            velocity = 6.6
            jumpBuffer = 0
            coyote = 0
            announce("POP!", kind: "jump")
        }

        if height > 0 || velocity > 0 {
            height = max(0, height + velocity * dt)
            velocity -= 15.0 * dt
            if height == 0 {
                velocity = 0
                announce("Landed", kind: "land")
            }
        }

        let playerRear = distance - 0.31
        let playerFront = distance + 0.31

        for index in features.indices where !features[index].resolved {
            let feature = features[index]
            if feature.at > playerFront || feature.end < playerRear {
                if feature.end < playerRear { resolve(index) }
                continue
            }

            switch feature.kind {
            case .gap:
                if height < 0.34 { damage(index) }
            case .barrier:
                if height < 0.68 { damage(index) }
            case .overhead:
                if !crouching || height > 0.12 { damage(index) }
            case .manualLine, .noseLine:
                features[index].exposure += dt
                let matches = feature.kind == .manualLine ? holdingManual : input.noseManual
                if grounded && matches { features[index].heldTime += dt }
            case .pickup:
                if height < 1.7 {
                    features[index].resolved = true
                    pickups += 1
                    combo += 1
                    score += 50 + min(combo, 10) * 10
                    announce("+ STAR", kind: "pickup")
                }
            case .checkpoint:
                features[index].resolved = true
                checkpointDistance = feature.end + 0.65
                checkpointScore = score
                checkpointPickups = pickups
                checkpointDamage = damageCount
                checkpointManualLines = manualLines
                checkpointNoseLines = noseLines
                checkpointElapsed = elapsed
                announce("CHECKPOINT", kind: "checkpoint")
            }
        }

        if distance >= courseLength {
            gameOver = true
            won = lives > 0
            if won {
                score += lives * 200
                announce("COURSE COMPLETE", kind: "finish")
            }
        }
    }

    private func resolve(_ index: Int) {
        let feature = features[index]
        features[index].resolved = true
        switch feature.kind {
        case .gap, .barrier, .overhead:
            if !feature.failed {
                combo += 1
                score += min(combo, 10) * 75
                announce(combo > 1 ? "FLOW x\(combo)" : "CLEAN!", kind: "clear")
            }
        case .manualLine, .noseLine:
            if feature.exposure >= 0.10 &&
                feature.heldTime >= feature.exposure * 0.65 {
                combo += 1
                score += 180 + min(combo, 10) * 20
                if feature.kind == .manualLine { manualLines += 1 }
                else { noseLines += 1 }
                announce(feature.kind == .manualLine ?
                         "MANUAL LINE!" : "NOSE MANUAL!", kind: "line")
            } else {
                combo = 0
                announce("Balance line missed", kind: "miss")
            }
        case .checkpoint, .pickup:
            break
        }
    }

    private func damage(_ index: Int) {
        // Mark a hazard failed even if temporary invulnerability absorbs it:
        // repeat overlap cannot award a clean clear.
        features[index].failed = true
        if invulnerabilityTime > 0 { return }
        lives -= 1
        damageCount += 1
        combo = 0
        invulnerabilityTime = 1.0
        announce(lives == 0 ? "WIPEOUT" : "BAIL! KEEP MOVING", kind: "damage")
        if lives <= 0 { gameOver = true }
    }

    private func announce(_ title: String, kind: String) {
        message = title
        eventKind = kind
        eventRevision += 1
    }
}
