import CoreMotion
import Foundation
import simd

enum MotionSource: String, Codable {
    case headphone
    case phone
    case simulation
}

enum HeadphoneSide: String, CaseIterable, Identifiable {
    case left
    case right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Host uptime is recorded when the handler receives each reading. Device timestamps
/// are retained separately; we do not assume headphone and phone timestamps share a
/// perfectly synchronized clock.
struct MotionSample: Codable {
    let source: MotionSource
    let sensorLocation: String
    let hostUptime: TimeInterval
    let deviceTimestamp: TimeInterval
    let gravity: Vector3
    let acceleration: Vector3
    let rotationRate: Vector3
    let pitch: Double
    let roll: Double
    let yaw: Double
    /// Optional to decode already queued pre-v6 sessions across app upgrades.
    let quaternion: Quaternion4?

    init(source: MotionSource, sensorLocation: String, hostUptime: TimeInterval,
         deviceTimestamp: TimeInterval, gravity: Vector3, acceleration: Vector3,
         rotationRate: Vector3, pitch: Double = 0, roll: Double = 0,
         yaw: Double = 0, quaternion: Quaternion4? = nil) {
        self.source = source
        self.sensorLocation = sensorLocation
        self.hostUptime = hostUptime
        self.deviceTimestamp = deviceTimestamp
        self.gravity = gravity
        self.acceleration = acceleration
        self.rotationRate = rotationRate
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.quaternion = quaternion
    }

    init(motion: CMDeviceMotion, source: MotionSource, receivedAt: TimeInterval) {
        let sensorLocation: String
        switch motion.sensorLocation {
        case .headphoneLeft: sensorLocation = "left"
        case .headphoneRight: sensorLocation = "right"
        default: sensorLocation = "default"
        }
        self.init(
            source: source,
            sensorLocation: sensorLocation,
            hostUptime: receivedAt,
            deviceTimestamp: motion.timestamp,
            gravity: Vector3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
            acceleration: Vector3(x: motion.userAcceleration.x,
                                  y: motion.userAcceleration.y, z: motion.userAcceleration.z),
            rotationRate: Vector3(x: motion.rotationRate.x,
                                  y: motion.rotationRate.y, z: motion.rotationRate.z),
            pitch: motion.attitude.pitch,
            roll: motion.attitude.roll,
            yaw: motion.attitude.yaw,
            quaternion: Quaternion4(
                w: motion.attitude.quaternion.w,
                x: motion.attitude.quaternion.x,
                y: motion.attitude.quaternion.y,
                z: motion.attitude.quaternion.z)
        )
    }

    var csvRow: String {
        let parts: [String] = [
            String(format: "%.6f", hostUptime), String(format: "%.6f", deviceTimestamp),
            source.rawValue, sensorLocation,
            String(gravity.x), String(gravity.y), String(gravity.z),
            String(acceleration.x), String(acceleration.y), String(acceleration.z),
            String(rotationRate.x), String(rotationRate.y), String(rotationRate.z),
            String(pitch), String(roll), String(yaw),
            quaternion.map { String($0.w) } ?? "",
            quaternion.map { String($0.x) } ?? "",
            quaternion.map { String($0.y) } ?? "",
            quaternion.map { String($0.z) } ?? ""
        ]
        return parts.joined(separator: ",")
    }

    static let csvHeader = "host_uptime_s,device_timestamp_s,source,sensor_location,gravity_x_g,gravity_y_g,gravity_z_g,user_accel_x_g,user_accel_y_g,user_accel_z_g,rotation_x_rad_s,rotation_y_rad_s,rotation_z_rad_s,pitch_rad,roll_rad,yaw_rad,quaternion_w,quaternion_x,quaternion_y,quaternion_z"
}

struct TrickEvent: Identifiable, Codable {
    let id: UUID
    let kind: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
    let detail: String

    init(kind: String, start: TimeInterval, end: TimeInterval,
         confidence: Double, detail: String) {
        self.id = UUID()
        self.kind = kind
        self.start = start
        self.end = end
        self.confidence = min(1, max(0, confidence))
        self.detail = detail
    }
}
