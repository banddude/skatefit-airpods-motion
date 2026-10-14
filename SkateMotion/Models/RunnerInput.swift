import Foundation

/// Auto uses the selected, calibrated board-mounted AirPod when its stream is
/// fresh. Touch is explicitly available for phones without a board sensor.
enum RunnerControlMode: String, Codable, CaseIterable {
    case automatic = "Auto"
    case touch = "Touch"
    case motion = "AirPods"

    func resolvedSource(sensorReady: Bool) -> RunnerControlSource? {
        switch self {
        case .automatic: return sensorReady ? .motion : .touch
        case .touch: return .touch
        case .motion: return sensorReady ? .motion : nil
        }
    }
}

enum RunnerControlSource: String {
    case touch = "TOUCH / GAMEPAD"
    case motion = "LIVE AIRPODS"

    var savedRunMode: RunnerControlMode {
        self == .motion ? .motion : .touch
    }
}

struct RunnerInput: Equatable, Codable {
    var manual = false
    var noseManual = false

    static func from(pitch: Double) -> RunnerInput {
        RunnerInput(manual: pitch > 9, noseManual: pitch < -9)
    }

    var isActive: Bool { manual || noseManual }
    var label: String {
        if manual { return "MANUAL / POP" }
        if noseManual { return "NOSE MANUAL / DUCK" }
        return "BOARD LEVEL"
    }
}

/// The same calibrated pitch readout that drives manual practice powers the
/// runner's controls. Training's lower angular threshold is configurable,
/// while hysteresis prevents a noisy AirPod from rapidly switching actions.
struct RunnerMotionAdapter {
    private(set) var direction = 0

    mutating func accept(pitch: Double?, engagementDegrees: Double = 11,
                         allowed: Bool = true) -> RunnerInput {
        guard allowed, let pitch, pitch.isFinite else {
            direction = 0
            return RunnerInput()
        }
        let engage = min(25.0, max(5.0, engagementDegrees.isFinite
                                  ? engagementDegrees : 11))
        let release = max(2.0, engage - 3)
        if direction == 1 && pitch < release { direction = 0 }
        if direction == -1 && pitch > -release { direction = 0 }
        if direction == 0 {
            if pitch >= engage { direction = 1 }
            else if pitch <= -engage { direction = -1 }
        }
        return RunnerInput(manual: direction == 1, noseManual: direction == -1)
    }

    mutating func reset() { direction = 0 }
}

/// Prevent the AirPod runner from auto-moving, spending lives, or awarding
/// points before the real board provides its first tilt. Touch is always
/// playable without an AirPod.
enum RunnerStartGate {
    static func canBegin(source: RunnerControlSource,
                         input: RunnerInput) -> Bool {
        source == .touch || input.isActive
    }
}

enum RunnerMotionFreshness {
    static func isReady(lastSample: TimeInterval?, now: TimeInterval) -> Bool {
        guard let lastSample, now.isFinite, lastSample.isFinite else { return false }
        return now >= lastSample && now - lastSample <= 0.75
    }
}
