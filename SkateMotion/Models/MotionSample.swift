import CoreMotion
import Foundation

/// Three-dimensional vector in sensor coordinates. User acceleration is expressed in g,
/// angular velocity in rad/s, gravity in g, and time in seconds.
struct Vector3: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var magnitude: Double { sqrt(x * x + y * y + z * z) }
    var normalized: Vector3? {
        guard magnitude > 1e-8 else { return nil }
        return self * (1 / magnitude)
    }

    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    func cross(_ other: Vector3) -> Vector3 {
        Vector3(x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x)
    }

    static func +(lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func -(lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func *(lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}

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

    init(source: MotionSource, sensorLocation: String, hostUptime: TimeInterval,
         deviceTimestamp: TimeInterval, gravity: Vector3, acceleration: Vector3,
         rotationRate: Vector3, pitch: Double = 0, roll: Double = 0, yaw: Double = 0) {
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
            yaw: motion.attitude.yaw
        )
    }

    var csvRow: String {
        let parts: [String] = [
            String(format: "%.6f", hostUptime), String(format: "%.6f", deviceTimestamp),
            source.rawValue, sensorLocation,
            String(gravity.x), String(gravity.y), String(gravity.z),
            String(acceleration.x), String(acceleration.y), String(acceleration.z),
            String(rotationRate.x), String(rotationRate.y), String(rotationRate.z),
            String(pitch), String(roll), String(yaw)
        ]
        return parts.joined(separator: ",")
    }

    static let csvHeader = "host_uptime_s,device_timestamp_s,source,sensor_location,gravity_x_g,gravity_y_g,gravity_z_g,user_accel_x_g,user_accel_y_g,user_accel_z_g,rotation_x_rad_s,rotation_y_rad_s,rotation_z_rad_s,pitch_rad,roll_rad,yaw_rad"
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
