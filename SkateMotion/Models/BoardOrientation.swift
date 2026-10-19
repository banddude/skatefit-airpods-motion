import Foundation

/// 3-axis board orientation. Pitch and roll are gravity-referenced, while yaw
/// uses the AirPod's fused attitude relative to the four-wheels-flat pose.
/// Neither is absolute heading or proof of road/ground contact.
struct BoardOrientation: Codable, Equatable {
    let pitchDegrees: Double
    let rollDegrees: Double
    let yawDegrees: Double
    let headingAvailable: Bool
    /// Quaternion in calibrated board coordinates, including complete flips.
    /// This is orientation only, not a 3D position or absolute compass heading.
    let relativeQuaternion: Quaternion4?
    /// +1 is wheels-down, -1 is grip-side-down, 0 is deck on its edge.
    let upAlignment: Double
    /// True when original fused attitude remains available.
    let fullAttitudeAvailable: Bool

    var isInverted: Bool { upAlignment < -0.55 }
    var isOnEdge: Bool { abs(upAlignment) < 0.45 }
    var deckFace: String {
        if isInverted { return "Grip facing down" }
        if isOnEdge { return "On edge" }
        return "Wheels facing down"
    }

    static let zero = BoardOrientation(
        pitchDegrees: 0, rollDegrees: 0, yawDegrees: 0, headingAvailable: false,
        relativeQuaternion: .identity, upAlignment: 1, fullAttitudeAvailable: false)
}

