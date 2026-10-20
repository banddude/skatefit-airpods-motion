import Foundation
import Observation

/// The game does not infer that an AirPod movement proves a landed trick.
/// Both input methods control the same deterministic simulation.
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
    private(set) var manualing = false
    private(set) var message = "Find your flow"
    private(set) var gameOver = false
    private(set) var won = false
    private(set) var combo = 0
    private(set) var pickups = 0
    private(set) var damageCount = 0
    private(set) var manualLines = 0
    private(set) var noseLines = 0
    private(set) var elapsed = 0.0
    private(set) var flowEnergy = 0.0
    private(set) var checkpointRetries = 0
    private(set) var invulnerabilityTime = 0.0
    private(set) var checkpointDistance = 0.0
    private(set) var features: [RunnerFeature] = []
    private(set) var eventRevision = 0
    private(set) var eventKind = "ready"

    private var simulationRemainder = 0.0
    private var lastManual = false
    /// Visual/game altitude only, not the real skateboard's measured height.
    static let manualHoldHeight = 1.2
    private static let riseSpeed = 6.6
    private static let noseDropSpeed = 9.0
    private static let gravity = 15.0
    private var checkpointScore = 0
    private var checkpointPickups = 0
    private var checkpointDamage = 0
    private var checkpointManualLines = 0
    private var checkpointNoseLines = 0
    private var checkpointElapsed = 0.0
    private var checkpointFlowEnergy = 0.0
    private var checkpointCombo = 0

    var course: RunnerCourse { RunnerCourse.get(level) }
    var flowMultiplier: Int { flowEnergy >= 0.78 ? 2 : 1 }
    var nextAction: RunnerFeature? {
        features.first { !$0.resolved && $0.kind != .pickup &&
                         $0.kind != .checkpoint && $0.at >= distance - 0.4 }
    }
    var nextCue: String {
        guard let action = nextAction else { return "FINISH STRONG" }
        switch action.kind {
        case .gap, .barrier: return "HOLD MANUAL · STAY UP"
        case .overhead, .pulseGate: return "HOLD NOSE MANUAL · STAY LOW"
        case .manualLine: return "HOLD MANUAL"
        case .noseLine: return "HOLD NOSE MANUAL"
        case .springPad: return "LAUNCH RAMP"
        case .longGap: return "CLEAR THE CHASM"
        case .checkpoint: return "CHECKPOINT"
        case .pickup: return "COLLECT"
        }
    }
    var cueSeconds: Double {
        guard let action = nextAction else { return 0 }
        return max(0, (action.at - distance) / course.speed)
    }
    func pulseGateActive(_ feature: RunnerFeature) -> Bool {
        sin(elapsed * (.pi * 2 / 1.9) + feature.at * 0.07) >= -0.1
    }

    var courseLength: Double { course.length }
    var progress: Double { min(1, distance / courseLength) }
    var noHit: Bool { damageCount == 0 && checkpointRetries == 0 }
    var stars: Int {
        guard won else { return 0 }
        return 1 + (noHit ? 1 : 0) +
            (pickups >= course.starTarget &&
             manualLines + noseLines >= course.lineTarget ? 1 : 0)
    }

    init() { reset(course: 1) }

    func reset(course selected: Int = 1) {
        level = RunnerCourse.get(selected).id
        score = 0
        lives = 3
        distance = 0
        height = 0
        velocity = 0
        crouching = false
        manualing = false
        message = "Find your flow"
        gameOver = false
        won = false
        combo = 0
        pickups = 0
        damageCount = 0
        manualLines = 0
        noseLines = 0
        elapsed = 0
        flowEnergy = 0
        checkpointRetries = 0
        invulnerabilityTime = 0
        checkpointDistance = 0
        features = course.features
        simulationRemainder = 0
        lastManual = false
        checkpointScore = 0
        checkpointPickups = 0
        checkpointDamage = 0
        checkpointManualLines = 0
        checkpointNoseLines = 0
        checkpointElapsed = 0
        checkpointFlowEnergy = 0
        checkpointCombo = 0
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
        flowEnergy = checkpointFlowEnergy
        checkpointRetries += 1
        lives = 2
        height = 0
        velocity = 0
        crouching = false
        manualing = false
        combo = checkpointCombo
        lastManual = false
        simulationRemainder = 0
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
        elapsed += dt
        distance += course.speed * dt
        invulnerabilityTime = max(0, invulnerabilityTime - dt)
        flowEnergy = max(0, flowEnergy - dt * 0.025)

        // Continuous balance control, identical on iPhone and Apple TV:
        // manual holds the character UP; nose manual holds it LOW; neutral
        // releases the action. Conflicting buttons are neutral, never a cheat.
        let holdingManual = input.manual && !input.noseManual
        let holdingNose = input.noseManual && !input.manual
        let wasManual = lastManual
        let wasAirborne = height > 0
        manualing = holdingManual
        crouching = holdingNose

        if holdingManual {
            if !wasManual { announce("MANUAL · HOLD TO STAY UP", kind: "jump") }
            // No repeated jumps and no timeout. Lift to the clearance height,
            // then remain there for exactly as long as input stays manual.
            if height < Self.manualHoldHeight {
                height = min(Self.manualHoldHeight, height + Self.riseSpeed * dt)
                velocity = height < Self.manualHoldHeight ? Self.riseSpeed : 0
            } else if height > Self.manualHoldHeight {
                // A launch ramp can put us above the normal hold height.
                height = max(Self.manualHoldHeight, height - Self.riseSpeed * dt)
                velocity = height > Self.manualHoldHeight ? -Self.riseSpeed : 0
            } else { velocity = 0 }
        } else if holdingNose {
            // Duck takes effect immediately, even during a manual/jump.
            // Descend quickly rather than waiting through a ballistic arc.
            height = max(0, height - Self.noseDropSpeed * dt)
            velocity = height > 0 ? -Self.noseDropSpeed : 0
        } else if height > 0 || velocity > 0 {
            // Releasing a manual cancels upward motion immediately. An
            // independently triggered spring ramp retains its normal arc.
            if wasManual { velocity = min(0, velocity) }
            velocity -= Self.gravity * dt
            height = max(0, height + velocity * dt)
            if height == 0 { velocity = 0 }
        }
        lastManual = holdingManual
        if wasAirborne && height == 0 { announce("Landed", kind: "land") }
        let grounded = height <= 0.001 && velocity <= 0

        let playerRear = distance - 0.31
        let playerFront = distance + 0.31

        for index in features.indices where !features[index].resolved {
            let feature = features[index]
            if feature.at > playerFront || feature.end < playerRear {
                if feature.end < playerRear { resolve(index) }
                continue
            }

            switch feature.kind {
            case .gap, .longGap:
                if height < 0.34 { damage(index) }
            case .barrier:
                if height < 0.68 { damage(index) }
            case .overhead:
                if !crouching || height > 0.12 { damage(index) }
            case .pulseGate:
                if pulseGateActive(feature) && (!crouching || height > 0.12) {
                    damage(index)
                }
            case .springPad:
                // A held nose manual always stays low; a ramp must not
                // override its input. Neutral ramp behavior is preserved.
                if grounded && !holdingNose && !holdingManual {
                    features[index].resolved = true
                    velocity = 11.7
                    height = 0.02
                    crouching = false
                    announce("BOOST LAUNCH!", kind: "boost")
                }
            case .manualLine, .noseLine:
                features[index].exposure += dt
                let matches = feature.kind == .manualLine
                    ? holdingManual && height >= 0.68
                    : holdingNose && height <= 0.12
                // Manual lines reward sustained balance while elevated.
                // Requiring ground contact here would make them unwinnable.
                if matches {
                    features[index].heldTime += dt
                    flowEnergy = min(1, flowEnergy + dt * 0.80)
                }
            case .pickup:
                if height < 1.7 {
                    features[index].resolved = true
                    pickups += 1
                    combo += 1
                    score += (50 + min(combo, 10) * 10) * flowMultiplier
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
                checkpointFlowEnergy = flowEnergy
                checkpointCombo = combo
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
        case .gap, .longGap, .barrier, .overhead, .pulseGate:
            if !feature.failed {
                combo += 1
                score += min(combo, 10) * 75 * flowMultiplier
                announce(combo > 1 ? "FLOW x\(combo)" : "CLEAN!", kind: "clear")
            }
        case .manualLine, .noseLine:
            if feature.exposure >= 0.10 &&
                feature.heldTime >= feature.exposure * 0.65 {
                combo += 1
                score += (180 + min(combo, 10) * 20) * flowMultiplier
                if feature.kind == .manualLine { manualLines += 1 }
                else { noseLines += 1 }
                announce(feature.kind == .manualLine ?
                         "MANUAL LINE!" : "NOSE MANUAL!", kind: "line")
            } else {
                combo = 0
                flowEnergy = max(0, flowEnergy - 0.35)
                announce("Balance line missed", kind: "miss")
            }
        case .checkpoint, .pickup, .springPad:
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
        flowEnergy = 0
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
