import Foundation

enum CalibrationPose: String, CaseIterable, Identifiable {
    case tailContact = "Tail on ground"
    case noseContact = "Nose on ground"
    case wheelsDown = "Four wheels down"
    var id: String { rawValue }
}

/// Gravity references define board longitudinal axis despite arbitrary AirPod orientation.
/// Only collect these poses with the AirPod rigidly attached and the board held still.
struct BoardCalibration {
    private(set) var poses: [CalibrationPose: Vector3] = [:]

    mutating func set(_ pose: CalibrationPose, gravity: Vector3) {
        poses[pose] = gravity
    }

    var isComplete: Bool { CalibrationPose.allCases.allSatisfy { poses[$0] != nil } }

    var flatGravity: Vector3? { poses[.wheelsDown]?.normalized }

    /// Unit vector parallel to board length, determined by tail-vs-flat gravity.
    var lengthAxis: Vector3? {
        guard let flat = flatGravity, let tail = poses[.tailContact] else { return nil }
        let projected = tail - flat * tail.dot(flat)
        return projected.normalized
    }

    var widthAxis: Vector3? {
        guard let flat = flatGravity, let length = lengthAxis else { return nil }
        return flat.cross(length).normalized
    }

    var isPhysicallyPlausible: Bool {
        guard isComplete, let flat = flatGravity, let tail = poses[.tailContact]?.normalized,
              let nose = poses[.noseContact]?.normalized,
              let length = lengthAxis else { return false }
        let tailTilt = acos(max(-1, min(1, flat.dot(tail)))) * 180 / .pi
        let noseTilt = acos(max(-1, min(1, flat.dot(nose)))) * 180 / .pi
        return tailTilt > 5 && noseTilt > 5 &&
            (tail - flat).dot(length) > 0 && (nose - flat).dot(length) < 0
    }

    /// Positive tilt is toward the tail; negative toward the nose.
    func pitchDegrees(gravity: Vector3) -> Double? {
        guard let flat = flatGravity, let length = lengthAxis,
              let measured = gravity.normalized else { return nil }
        // Project onto the board's longitudinal plane. Side-to-side tilt must
        // not be mistaken for lifting the nose or tail into a manual.
        return atan2(measured.dot(length), measured.dot(flat)) * 180 / .pi
    }

    var contactTiltDegrees: Double? {
        guard let tail = poses[.tailContact], let nose = poses[.noseContact],
              let tailPitch = pitchDegrees(gravity: tail),
              let nosePitch = pitchDegrees(gravity: nose) else { return nil }
        return min(abs(tailPitch), abs(nosePitch))
    }

    /// Leave a gap beneath the tail/nose contact limit so dragging the deck isn't a manual.
    var manualUpperLimit: Double {
        max(8, (contactTiltDegrees ?? 28) - 3)
    }
}
