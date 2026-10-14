import Foundation

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

/// A deadband avoids rapid flickering when calibrated AirPod pitch hovers
/// around the +/- 9 degree action thresholds.
struct RunnerMotionAdapter {
    private(set) var direction = 0

    mutating func accept(pitch: Double?) -> RunnerInput {
        guard let pitch, pitch.isFinite else {
            direction = 0
            return RunnerInput()
        }

        if direction == 1 && pitch < 7 { direction = 0 }
        if direction == -1 && pitch > -7 { direction = 0 }
        if direction == 0 {
            if pitch >= 11 { direction = 1 }
            else if pitch <= -11 { direction = -1 }
        }
        return RunnerInput(manual: direction == 1, noseManual: direction == -1)
    }

    mutating func reset() { direction = 0 }
}

enum RunnerMotionFreshness {
    static func isReady(lastSample: TimeInterval?, now: TimeInterval) -> Bool {
        guard let lastSample, now.isFinite, lastSample.isFinite else { return false }
        return now >= lastSample && now - lastSample <= 0.75
    }
}
