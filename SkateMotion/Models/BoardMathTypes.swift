import Foundation
import simd

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

/// Core Motion's fused device-to-reference attitude, saved as a unit quaternion.
/// The reference heading is relative and may drift; it is NOT compass heading.
struct Quaternion4: Codable, Equatable {
    let w: Double
    let x: Double
    let y: Double
    let z: Double

    static let identity = Quaternion4(w: 1, x: 0, y: 0, z: 0)

    var isValid: Bool {
        let values = [w, x, y, z]
        return values.allSatisfy(\.isFinite) &&
            values.reduce(0) { $0 + $1 * $1 } > 1e-12
    }

    var unit: Quaternion4? {
        guard isValid else { return nil }
        let magnitude = sqrt(w * w + x * x + y * y + z * z)
        return Quaternion4(w: w / magnitude, x: x / magnitude,
                           y: y / magnitude, z: z / magnitude)
    }

    func rotate(_ vector: Vector3) -> Vector3 {
        let length = sqrt(w*w + x*x + y*y + z*z)
        guard length > 1e-10 else { return vector }
        let q = simd_quatd(real: w / length,
                           imag: SIMD3<Double>(x / length, y / length, z / length))
        let rotated = q.act(SIMD3<Double>(vector.x, vector.y, vector.z))
        return Vector3(x: rotated.x, y: rotated.y, z: rotated.z)
    }
}

