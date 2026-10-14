import Foundation

/// Three-pose calibration must be based on a stationary, rigid sensor mount.
/// Motion while collecting a pose biases the inferred board axes and makes
/// subsequent manual coaching and full-rotation visualization unreliable.
enum CalibrationCaptureQuality {
    static let requiredHoldSeconds = 1.5

    static func accepts(_ sample: MotionSample) -> Bool {
        let gravity = sample.gravity.magnitude
        let rotation = sample.rotationRate.magnitude
        let acceleration = sample.acceleration.magnitude
        return gravity.isFinite && rotation.isFinite && acceleration.isFinite &&
            (0.80...1.20).contains(gravity) &&
            rotation <= 0.25 && acceleration <= 0.28
    }

    /// Reject wobbling even if its positive and negative motion cancel in
    /// the mean. Return unnormalized gravity for calibration.
    static func stableMean(_ gravitySamples: [Vector3]) -> Vector3? {
        guard gravitySamples.count >= 8 else { return nil }
        let sum = gravitySamples.reduce(Vector3.zero, +)
        let mean = sum * (1 / Double(gravitySamples.count))
        guard mean.magnitude.isFinite, (0.85...1.15).contains(mean.magnitude)
        else { return nil }
        let variance = gravitySamples.reduce(0.0) { sum, item in
            let delta = item - mean
            return sum + delta.dot(delta)
        } / Double(gravitySamples.count)
        return variance.isFinite && sqrt(variance) <= 0.070 ? mean : nil
    }
}
