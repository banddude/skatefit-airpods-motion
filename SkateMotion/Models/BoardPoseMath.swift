import Foundation
import simd

/// Calibrated board pose. The orientation quaternion rotates the board model
/// from its flat calibration frame into the current *relative* frame.
/// It never encodes translation or world-map coordinates.
enum BoardPoseMath {
    static func relativeRotation(reference: Quaternion4, current: Quaternion4,
                                 length: Vector3, width: Vector3,
                                 down: Vector3) -> Quaternion4? {
        guard reference.isValid, current.isValid else { return nil }
        let up = down * -1

        let initialX = reference.rotate(length)
        let initialY = reference.rotate(up)
        let initialZ = reference.rotate(width)
        let currentX = current.rotate(length)
        let currentY = current.rotate(up)
        let currentZ = current.rotate(width)

        func basisCoordinates(_ vector: Vector3) -> SIMD3<Double> {
            SIMD3(initialX.dot(vector), initialY.dot(vector), initialZ.dot(vector))
        }
        let rotation = simd_double3x3(
            columns: (basisCoordinates(currentX),
                      basisCoordinates(currentY),
                      basisCoordinates(currentZ)))
        let q = simd_quatd(rotation)
        return Quaternion4(w: q.real, x: q.imag.x,
                           y: q.imag.y, z: q.imag.z).unit
    }

    /// When fused attitude is absent, gravity still gives two tilt axes.
    /// Rotation about gravity (yaw) remains unknown. The exactly inverted
    /// orientation has an ambiguous flip axis; use board-longitudinal X.
    static func gravityOnlyRotation(measuredGravity: Vector3,
                                    length: Vector3, width: Vector3,
                                    flatDown: Vector3) -> Quaternion4? {
        guard let measured = measuredGravity.normalized else { return nil }
        let up = flatDown * -1
        let gravityInBoard = SIMD3<Double>(
            measured.dot(length), measured.dot(up), measured.dot(width))
        let down = SIMD3<Double>(0, -1, 0)
        let dot = simd_dot(gravityInBoard, down)
        let quaternion: simd_quatd
        if dot < -0.9999 {
            quaternion = simd_quatd(angle: .pi, axis: SIMD3(1, 0, 0))
        } else if dot > 0.9999 {
            quaternion = simd_quatd(real: 1, imag: SIMD3(0, 0, 0))
        } else {
            quaternion = simd_quatd(from: gravityInBoard, to: down)
        }
        return Quaternion4(w: quaternion.real, x: quaternion.imag.x,
                           y: quaternion.imag.y, z: quaternion.imag.z).unit
    }
}
