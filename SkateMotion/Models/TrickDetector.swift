import Foundation

/// Experimental rules, not a trained classifier. All events are labeled "possible";
/// motion alone cannot prove the rider landed with both feet on the board.
struct TrickDetector {
    var rules = RemoteRules()

    private var manualCandidateStart: TimeInterval?
    private var manualDirection: Int = 0

    private var flightStart: TimeInterval?
    private var lastFlightUptime: TimeInterval?
    private var integratedRoll = 0.0
    private var integratedYaw = 0.0
    private var integratedPitch = 0.0
    private var peakAcceleration = 0.0

    mutating func reset() { let previousRules = rules; self = TrickDetector(); rules = previousRules }

    mutating func accept(_ sample: MotionSample,
                         calibration: BoardCalibration) -> [TrickEvent] {
        guard sample.source != .phone, calibration.isPhysicallyPlausible,
              let pitch = calibration.pitchDegrees(gravity: sample.gravity),
              let longAxis = calibration.lengthAxis,
              let flat = calibration.flatGravity,
              let widthAxis = calibration.widthAxis else { return [] }
        var events: [TrickEvent] = []
        let t = sample.hostUptime
        let direction = pitch > rules.manualPitchDegrees ? 1 :
            (pitch < -rules.manualPitchDegrees ? -1 : 0)
        let inManualRange = direction != 0 && abs(pitch) < calibration.manualUpperLimit &&
            sample.rotationRate.magnitude < 2.0

        if inManualRange {
            if manualDirection != direction {
                manualCandidateStart = t
                manualDirection = direction
            }
        } else {
            if let start = manualCandidateStart, t - start >= rules.minimumManualSeconds,
               manualDirection != 0 {
                events.append(TrickEvent(
                    kind: manualDirection > 0 ? "Possible manual" : "Possible nose manual",
                    start: start, end: t, confidence: 0.55,
                    detail: "Held calibrated board pitch for \(String(format: "%.2f", t - start)) s. Wheel contact is inferred, not measured."
                ))
            }
            manualCandidateStart = nil
            manualDirection = 0
        }

        let impact = sample.acceleration.magnitude
        let rate = sample.rotationRate.magnitude
        // Segment a candidate around high angular velocity or board acceleration.
        if flightStart == nil && (rate > rules.rotationStartRate || impact > rules.movementThresholdG) {
            flightStart = t
            lastFlightUptime = t
            integratedRoll = 0
            integratedYaw = 0
            integratedPitch = 0
            peakAcceleration = impact
        }
        if let start = flightStart {
            if let previous = lastFlightUptime {
                let dt = max(0, min(0.08, t - previous))
                integratedRoll += sample.rotationRate.dot(longAxis) * dt
                integratedYaw += sample.rotationRate.dot(flat) * dt
                integratedPitch += sample.rotationRate.dot(widthAxis) * dt
            }
            lastFlightUptime = t
            peakAcceleration = max(peakAcceleration, impact)
            let elapsed = t - start
            let landingCandidate = impact > rules.impactThresholdG && elapsed > 0.12
            if landingCandidate || elapsed > rules.maxCandidateSeconds {
                if elapsed > 0.12 {
                    let flipAngle = abs(integratedRoll)
                    let shoveAngle = abs(integratedYaw)
                    let name: String
                    let confidence: Double
                    if flipAngle > 4.3 && shoveAngle > 3.0 {
                        name = "Possible flip + shove combination"; confidence = 0.35
                    } else if flipAngle > 4.3 {
                        name = "Possible flip trick"; confidence = 0.4
                    } else if shoveAngle > 2.3 {
                        name = "Possible shove-it"; confidence = 0.4
                    } else if landingCandidate {
                        name = "Possible ollie / pop"; confidence = 0.25
                    } else {
                        name = "Unclassified board movement"; confidence = 0.2
                    }
                    let detail = String(format:
                        "Integrated flip %.0f°, yaw %.0f°, pitch %.0f°; peak %.1fg; %.2fs. Needs video/foot-contact validation.",
                        flipAngle * 180 / .pi, shoveAngle * 180 / .pi,
                        abs(integratedPitch) * 180 / .pi, peakAcceleration, elapsed)
                    events.append(TrickEvent(kind: name, start: start, end: t,
                                             confidence: confidence, detail: detail))
                }
                flightStart = nil
                lastFlightUptime = nil
            }
        }
        return events
    }
}
