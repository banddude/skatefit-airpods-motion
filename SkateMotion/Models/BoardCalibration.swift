import Foundation

enum CalibrationPose: String, CaseIterable, Identifiable {
    case tailContact = "Tail on ground"
    case noseContact = "Nose on ground"
    case wheelsDown = "Four wheels down"
    var id: String { rawValue }
}

/// 3-axis board orientation. Pitch and roll are gravity-referenced, while yaw
/// uses the AirPod's fused attitude relative to the four-wheels-flat pose.
/// Neither is absolute heading or proof of road/ground contact.
struct BoardOrientation: Codable, Equatable {
    let pitchDegrees: Double
    let rollDegrees: Double
    let yawDegrees: Double
    let headingAvailable: Bool

    static let zero = BoardOrientation(
        pitchDegrees: 0, rollDegrees: 0, yawDegrees: 0, headingAvailable: false)
}

/// Gravity references define board longitudinal axis despite arbitrary AirPod orientation.
/// Only collect these poses with the AirPod rigidly attached and the board held still.
struct BoardCalibration {
    private(set) var poses: [CalibrationPose: Vector3] = [:]
    private(set) var flatAttitude: Quaternion4?

    mutating func set(_ pose: CalibrationPose, gravity: Vector3,
                      attitude: Quaternion4? = nil) {
        poses[pose] = gravity
        if pose == .wheelsDown { flatAttitude = attitude }
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

    /// Valid after three-pose calibration. +pitch raises the nose;
    /// +/-roll measures deck lateral inclination. Yaw is RELATIVE to
    /// the level-pose attitude and can drift because AirPods lack a
    /// magnetically anchored skateboard heading.
    func orientation(for sample: MotionSample) -> BoardOrientation? {
        guard isPhysicallyPlausible,
              let pitch = pitchDegrees(gravity: sample.gravity),
              let flat = flatGravity,
              let width = widthAxis,
              let measured = sample.gravity.normalized,
              let length = lengthAxis else { return nil }

        let roll = atan2(measured.dot(width), measured.dot(flat)) * 180 / .pi
        var yaw = 0.0
        var headingAvailable = false

        if let reference = flatAttitude, let current = sample.quaternion {
            let initialLongitudinal = reference.rotate(length)
            let initialLateral = reference.rotate(width)
            let currentLongitudinal = current.rotate(length)
            let x = currentLongitudinal.dot(initialLongitudinal)
            let y = currentLongitudinal.dot(initialLateral)
            if hypot(x, y) > 0.08 {
                yaw = atan2(y, x) * 180 / .pi
                headingAvailable = true
            }
        }
        return BoardOrientation(pitchDegrees: pitch, rollDegrees: roll,
                                yawDegrees: yaw, headingAvailable: headingAvailable)
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
