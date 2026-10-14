import Foundation
import simd

/// The marker's pose in the camera's local frame, in metres.
/// This is NOT a surveyed world position or a wheel-contact measurement.
struct CameraMarkerPose: Equatable {
    let xMeters: Double
    let yMeters: Double
    let zMeters: Double
    let orientation: Quaternion4
    let distanceMeters: Double

    var xyz: Vector3 {
        Vector3(x: xMeters, y: yMeters, z: zMeters)
    }
}

/// A successfully tracked AR reference frame. Optics are valid only while
/// ARKit is tracking the 120 mm printed square and the phone remains still.
struct BoardOpticalSample: Equatable {
    let pose: CameraMarkerPose
    let frameTimestamp: TimeInterval
    let hostReceiptUptime: TimeInterval
    let displacement: Vector3?
    let orientationChangeDegrees: Double?
}

/// Relative camera-space 6-DoF geometry. No inertial double integration.
/// ARKit needs a visibly tracked reference image of correctly printed size.
enum BoardOpticalMath {
    static let markerWidthMeters = 0.12
    static let freshnessSeconds = 0.45
    static let pairingToleranceSeconds = 0.20

    static func cameraPose(worldFromCamera camera: simd_float4x4,
                           worldFromMarker marker: simd_float4x4) -> CameraMarkerPose? {
        let cameraComponents: [Float] = [
            camera.columns.0.x, camera.columns.0.y, camera.columns.0.z, camera.columns.0.w,
            camera.columns.1.x, camera.columns.1.y, camera.columns.1.z, camera.columns.1.w,
            camera.columns.2.x, camera.columns.2.y, camera.columns.2.z, camera.columns.2.w,
            camera.columns.3.x, camera.columns.3.y, camera.columns.3.z, camera.columns.3.w]
        let markerComponents: [Float] = [
            marker.columns.0.x, marker.columns.0.y, marker.columns.0.z, marker.columns.0.w,
            marker.columns.1.x, marker.columns.1.y, marker.columns.1.z, marker.columns.1.w,
            marker.columns.2.x, marker.columns.2.y, marker.columns.2.z, marker.columns.2.w,
            marker.columns.3.x, marker.columns.3.y, marker.columns.3.z, marker.columns.3.w]
        guard cameraComponents.allSatisfy(\.isFinite),
              markerComponents.allSatisfy(\.isFinite),
              abs(simd_determinant(camera)) > 1e-6 else { return nil }

        let cameraFromMarker = simd_inverse(camera) * marker
        let translation = cameraFromMarker.columns.3
        let position = SIMD3<Double>(
            Double(translation.x), Double(translation.y), Double(translation.z))
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
        // Three orientation axes in the camera coordinate frame.
        let rotation = simd_float3x3(columns: (
            SIMD3(cameraFromMarker.columns.0.x, cameraFromMarker.columns.0.y,
                  cameraFromMarker.columns.0.z),
            SIMD3(cameraFromMarker.columns.1.x, cameraFromMarker.columns.1.y,
                  cameraFromMarker.columns.1.z),
            SIMD3(cameraFromMarker.columns.2.x, cameraFromMarker.columns.2.y,
                  cameraFromMarker.columns.2.z)))
        guard abs(simd_determinant(rotation) - 1) < 0.10 else { return nil }
        let q = simd_quatf(rotation)
        let orientation = Quaternion4(w: Double(q.real),
            x: Double(q.imag.x), y: Double(q.imag.y), z: Double(q.imag.z))
        guard let unit = orientation.unit else { return nil }

        return CameraMarkerPose(xMeters: position.x, yMeters: position.y,
                                zMeters: position.z, orientation: unit,
                                distanceMeters: simd_length(position))
    }

    static func displacement(from baseline: CameraMarkerPose,
                             to current: CameraMarkerPose) -> Vector3 {
        current.xyz - baseline.xyz
    }

    static func angularChangeDegrees(from baseline: Quaternion4,
                                     to current: Quaternion4) -> Double? {
        guard let a = baseline.unit, let b = current.unit else { return nil }
        let inner = abs(a.w*b.w + a.x*b.x + a.y*b.y + a.z*b.z)
        return 2 * acos(min(1, max(0, inner))) * 180 / .pi
    }

    static func isFresh(sampleUptime: TimeInterval?, now: TimeInterval) -> Bool {
        guard let sampleUptime, sampleUptime.isFinite, now.isFinite else { return false }
        return now >= sampleUptime &&
            now - sampleUptime <= freshnessSeconds
    }

    static func canPair(airPodUptime: TimeInterval?, cameraUptime: TimeInterval) -> Bool {
        guard let airPodUptime, airPodUptime.isFinite,
              cameraUptime.isFinite else { return false }
        return abs(cameraUptime - airPodUptime) <= pairingToleranceSeconds
    }
}
