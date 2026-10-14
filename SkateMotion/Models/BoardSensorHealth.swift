import Foundation

/// Diagnoses ONLY the selected board-mounted earbud. The phone sensor and an
/// additional ear-worn AirPod must never qualify a manual.
enum BoardSensorRejection: String {
    case wrongSource = "Not a board-mounted AirPod"
    case wrongSide = "Unexpected AirPod side"
    case nonFinite = "Invalid sensor values"
    case invalidGravity = "Implausible gravity magnitude"
    case impossibleAcceleration = "Out-of-range acceleration"
    case duplicate = "Duplicate or out-of-order sample"
}

struct BoardSensorHealthSnapshot: Equatable {
    var accepted = 0
    var rejected = 0
    var interruptions = 0
    var sampleRateHz = 0.0
    var lastBoardUptime: TimeInterval?
    var fusedAttitudeAvailable = false
    var latestRejection: String?
    var usesDeviceTimestamps = false

    func isFresh(now: TimeInterval) -> Bool {
        guard let lastBoardUptime, now.isFinite, now >= lastBoardUptime else {
            return false
        }
        return now - lastBoardUptime <= 0.75
    }

    func state(now: TimeInterval) -> String {
        guard accepted > 0 else { return "WAITING FOR BOARD AIRPOD" }
        guard isFresh(now: now) else { return "SENSOR STREAM LOST" }
        guard sampleRateHz >= 12 else { return "LOW SENSOR SAMPLE RATE" }
        return fusedAttitudeAvailable ? "BOARD MOTION LIVE" : "GRAVITY TILT ONLY"
    }

    func freshnessSeconds(now: TimeInterval) -> Double? {
        guard let lastBoardUptime, now >= lastBoardUptime else { return nil }
        return now - lastBoardUptime
    }
}

/// Quality gate for motion from the intended AirPod. Retains diagnostics
/// without ever interpreting invalid or duplicated frames as skill progress.
struct BoardSensorHealth {
    private(set) var snapshot = BoardSensorHealthSnapshot()
    private var lastDeviceTimestamp: TimeInterval?

    mutating func reset() {
        self = BoardSensorHealth()
    }

    @discardableResult
    mutating func accept(_ sample: MotionSample, expectedSide: String,
                         allowSimulation: Bool = false) -> Bool {
        let sourceValid = sample.source == .headphone ||
            (allowSimulation && sample.source == .simulation)
        guard sourceValid else { return reject(.wrongSource) }
        if sample.source == .headphone && sample.sensorLocation != expectedSide {
            return reject(.wrongSide)
        }

        let values = [
            sample.hostUptime, sample.deviceTimestamp,
            sample.gravity.x, sample.gravity.y, sample.gravity.z,
            sample.acceleration.x, sample.acceleration.y, sample.acceleration.z,
            sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z
        ]
        guard values.allSatisfy(\.isFinite),
              sample.hostUptime >= 0, sample.deviceTimestamp >= 0 else {
            return reject(.nonFinite)
        }
        let gravityMagnitude = sample.gravity.magnitude
        guard gravityMagnitude.isFinite &&
              (0.50...1.50).contains(gravityMagnitude) else {
            return reject(.invalidGravity)
        }
        let accel = sample.acceleration.magnitude
        let gyro = sample.rotationRate.magnitude
        guard accel.isFinite, gyro.isFinite, accel < 32, gyro < 200 else {
            return reject(.impossibleAcceleration)
        }

        if let previousHost = snapshot.lastBoardUptime {
            let hostDelta = sample.hostUptime - previousHost
            guard hostDelta > 0 else { return reject(.duplicate) }

            var interval = hostDelta
            let validDeviceClock = sample.deviceTimestamp > 0 &&
                (lastDeviceTimestamp ?? 0) > 0
            if validDeviceClock, let previousDevice = lastDeviceTimestamp {
                let sourceDelta = sample.deviceTimestamp - previousDevice
                if sourceDelta <= 0 {
                    // Core Motion may reset its timestamp on reconnection.
                    // A large backward jump is a NEW sensor epoch; a tiny
                    // negative/duplicate jump is invalid and must be rejected.
                    if sourceDelta < -2.0 {
                        snapshot.interruptions += 1
                    } else {
                        return reject(.duplicate)
                    }
                } else if sourceDelta <= 1.0 {
                    interval = sourceDelta
                    snapshot.usesDeviceTimestamps = true
                } else {
                    snapshot.interruptions += 1
                }
            }

            if hostDelta >= 0.25 { snapshot.interruptions += 1 }
            if interval > 0 && interval <= 0.20 && hostDelta <= 0.25 {
                let hz = min(240.0, 1.0 / interval)
                snapshot.sampleRateHz = snapshot.sampleRateHz == 0
                    ? hz : snapshot.sampleRateHz * 0.88 + hz * 0.12
            }
        }
        snapshot.accepted += 1
        snapshot.lastBoardUptime = sample.hostUptime
        snapshot.fusedAttitudeAvailable = sample.quaternion?.isValid ?? false
        lastDeviceTimestamp = sample.deviceTimestamp > 0 ? sample.deviceTimestamp : nil
        return true
    }

    @discardableResult
    private mutating func reject(_ reason: BoardSensorRejection) -> Bool {
        snapshot.rejected += 1
        snapshot.latestRejection = reason.rawValue
        return false
    }
}
