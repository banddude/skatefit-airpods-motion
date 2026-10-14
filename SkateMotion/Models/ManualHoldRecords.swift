import Foundation

/// End of a qualified board-orientation hold, not proof that a real manual
/// touched the ground or was landed.
enum ManualHoldEndReason: String, Codable, CaseIterable {
    case returnedFlat = "Deck flattened"
    case angleTooHigh = "Lifted too high"
    case sideways = "Excessive sideways tilt"
    case tooFast = "Unstable board movement"
    case inverted = "Board inverted or on edge"
    case changedDirection = "Changed manual direction"
    case sensorGap = "Sensor interruption"
    case invalidSensor = "Invalid sensor measurement"
    case settingsChanged = "Training target changed"
    case sessionEnded = "Session ended"
}

struct ManualHoldAttempt: Identifiable, Codable, Equatable {
    let id: UUID
    let side: ManualSide
    let seconds: Double
    let averageAngleDegrees: Double
    let wobbleRMSDegrees: Double
    let averageSideTiltDegrees: Double
    let averageStability: Double
    let targetAngleDegrees: Double
    let targetSeconds: Double
    let reachedGoal: Bool
    let endedBy: ManualHoldEndReason
}

/// Practical objective ladder based on actual locally saved pose-hold bests.
/// New goals never claim to be externally validated trick performance.
enum ManualPracticeInsights {
    static let ladder: [Double] = [1, 2, 3, 5, 8, 10, 15, 20, 30, 45, 60]

    static func personalBest(for side: ManualSide,
                             sessions: [SavedManualPractice]) -> Double {
        sessions.reduce(0) { previous, session in
            max(previous, side == .manual
                ? session.bestManualSeconds : session.bestNoseSeconds)
        }
    }

    static func recommendedGoal(for side: ManualSide,
                                sessions: [SavedManualPractice]) -> Double {
        let best = personalBest(for: side, sessions: sessions)
        return ladder.first(where: { $0 > best + 0.001 }) ?? 60
    }

    static func improvement(for side: ManualSide,
                            sessions: [SavedManualPractice]) -> Double? {
        guard sessions.count >= 2 else { return nil }
        let latest = side == .manual
            ? sessions[0].bestManualSeconds : sessions[0].bestNoseSeconds
        let prior = side == .manual
            ? sessions[1].bestManualSeconds : sessions[1].bestNoseSeconds
        return latest - prior
    }
}
