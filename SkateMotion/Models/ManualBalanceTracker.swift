import Foundation

enum ManualSide: String, Codable, CaseIterable, Identifiable {
    case manual = "Manual"
    case noseManual = "Nose manual"
    var id: String { rawValue }
}

struct ManualBalanceSettings: Codable, Equatable {
    var targetAngleDegrees = 12.0
    var toleranceDegrees = 5.0
    var goalSeconds = 3.0

    var validated: ManualBalanceSettings {
        ManualBalanceSettings(
            targetAngleDegrees: targetAngleDegrees.isFinite
                ? min(22, max(7, targetAngleDegrees)) : 12,
            toleranceDegrees: toleranceDegrees.isFinite
                ? min(8, max(2, toleranceDegrees)) : 5,
            goalSeconds: goalSeconds.isFinite
                ? min(60, max(1, goalSeconds)) : 3)
    }
}

/// A *pose* hold. No foot-contact or wheel-contact sensor exists in AirPods.
/// Never label one of these observations as a verified landed manual.
struct ManualBalanceSnapshot: Equatable {
    var status = "Connect and calibrate your board"
    var coach = "Start a session, then calibrate flat, tail and nose."
    var side: ManualSide?
    var pitchDegrees = 0.0
    var rollDegrees = 0.0
    var angularSpeedDegreesPerSecond = 0.0
    var pitchRateDegreesPerSecond = 0.0
    var rollRateDegreesPerSecond = 0.0
    var yawRateDegreesPerSecond = 0.0
    var userAccelerationG = 0.0
    var relativeYawDegrees = 0.0
    var sampleRateHz = 0.0
    var stability = 0.0
    var currentHoldSeconds = 0.0
    var longestManualSeconds = 0.0
    var longestNoseManualSeconds = 0.0
    var manualAttempts = 0
    var noseManualAttempts = 0
    var completedGoals = 0
    var measuredSamples = 0
    var inversionObservations = 0
    var averageHoldStability = 0.0
    var wobbleRMSE = 0.0
    var currentGoalAchieved = false
    var isInverted = false
    var hasPose = false
}

struct SavedManualPractice: Codable, Identifiable, Equatable {
    let id: String
    let finishedAt: Date
    let settings: ManualBalanceSettings
    let bestManualSeconds: Double
    let bestNoseSeconds: Double
    let manualAttempts: Int
    let noseManualAttempts: Int
    let goalsReached: Int
    let averageStability: Double
    let upsideDownSamples: Int
}

struct ManualBalanceTracker {
    private(set) var snapshot = ManualBalanceSnapshot()
    private(set) var settings: ManualBalanceSettings = .init()

    private var activeSide: ManualSide?
    private var lastUptime: TimeInterval?
    private var lastGoodUptime: TimeInterval?
    private var currentQualitySum = 0.0
    private var currentQualityCount = 0
    private var currentMeanTilt = 0.0
    private var currentTiltM2 = 0.0
    private var countedAttempt = false
    private var goalRecorded = false
    private var completedQualitySum = 0.0
    private var completedQualityCount = 0
    private var wasInverted = false

    mutating func configure(_ newSettings: ManualBalanceSettings) {
        settings = newSettings.validated
    }

    mutating func reset() {
        let oldSettings = settings
        self = ManualBalanceTracker()
        settings = oldSettings
    }

    mutating func finish() {
        settle()
        snapshot.currentHoldSeconds = 0
        snapshot.side = nil
    }

    mutating func accept(_ sample: MotionSample,
                         orientation: BoardOrientation?,
                         calibration: BoardCalibration) {
        // Reject iPhone and nonmounted earbud motion here even if a caller
        // accidentally routes them to this training algorithm.
        guard sample.source == .headphone || sample.source == .simulation,
              sample.hostUptime.isFinite, calibration.isPhysicallyPlausible,
              let orientation,
              orientation.pitchDegrees.isFinite,
              orientation.rollDegrees.isFinite else { return }

        let t = sample.hostUptime
        let dt = lastUptime.map { t - $0 }
        guard dt == nil || (dt! > 0 && dt! < 0.50) else {
            settle()
            lastUptime = t
            snapshot.status = "Sensor gap"
            snapshot.coach = "Keep the AirPod connected. The last hold was ended."
            return
        }
        lastUptime = t
        if let interval = dt, interval > 0 && interval < 0.2 {
            let instantHz = min(120, 1 / interval)
            snapshot.sampleRateHz = snapshot.sampleRateHz == 0
                ? instantHz : snapshot.sampleRateHz * 0.9 + instantHz * 0.1
        }

        snapshot.hasPose = true
        snapshot.measuredSamples += 1
        snapshot.pitchDegrees = orientation.pitchDegrees
        snapshot.rollDegrees = orientation.rollDegrees
        snapshot.relativeYawDegrees = orientation.yawDegrees
        snapshot.isInverted = orientation.isInverted
        if orientation.isInverted && !wasInverted {
            snapshot.inversionObservations += 1
        }
        wasInverted = orientation.isInverted

        guard !orientation.isInverted && !orientation.isOnEdge else {
            settle()
            snapshot.status = orientation.isInverted ? "BOARD UPSIDE DOWN" : "BOARD ON EDGE"
            snapshot.coach = "Re-level the deck before working on manuals."
            return
        }
        let rotation = sample.rotationRate
        let rate = rotation.magnitude * 180 / Double.pi
        let longitudinal = calibration.lengthAxis ?? .zero
        let transverse = calibration.widthAxis ?? .zero
        let normal = calibration.flatGravity ?? .zero
        let pitchRate = abs(rotation.dot(transverse)) * 180 / Double.pi
        let rollRate = abs(rotation.dot(longitudinal)) * 180 / Double.pi
        let yawRate = abs(rotation.dot(normal)) * 180 / Double.pi
        let userAcceleration = sample.acceleration.magnitude
        snapshot.angularSpeedDegreesPerSecond = rate
        snapshot.pitchRateDegreesPerSecond = pitchRate
        snapshot.rollRateDegreesPerSecond = rollRate
        snapshot.yawRateDegreesPerSecond = yawRate
        snapshot.userAccelerationG = userAcceleration
        let pitch = orientation.pitchDegrees
        let tilt = abs(pitch)
        let sideways = abs(orientation.rollDegrees)
        let side: ManualSide = pitch > 0 ? .manual : .noseManual
        let target = settings.targetAngleDegrees
        let minimum = max(5, target - settings.toleranceDegrees)
        let maximum = min(calibration.manualUpperLimit, target + settings.toleranceDegrees)
        let stable = sideways <= 12 && pitchRate <= 125 && rollRate <= 125 &&
            userAcceleration <= 2.5
        let inRange = tilt >= minimum && tilt <= maximum && stable
        // Pitch error is separate from actual wobble. Roll and pitch gyros
        // penalize balance corrections more strongly than intentional yaw.
        let quality = max(0, min(100,
            100 - abs(tilt - target) * 5.8 - sideways * 2.8 -
            pitchRate * 0.12 - rollRate * 0.17 - yawRate * 0.035 -
            max(0, userAcceleration - 0.15) * 6))
        snapshot.stability = snapshot.stability == 0
            ? quality : snapshot.stability * 0.78 + quality * 0.22

        if !inRange {
            if activeSide != nil && t - (lastGoodUptime ?? t) > 0.12 { settle() }
            if sideways > 12 {
                snapshot.status = "SIDEWAYS TILT"
                snapshot.coach = "Keep the deck level left-to-right."
            } else if pitchRate > 125 || rollRate > 125 ||
                      userAcceleration > 2.5 {
                snapshot.status = "TOO MUCH MOVEMENT"
                snapshot.coach = "Settle your balance before measuring a hold."
            } else if tilt < minimum {
                snapshot.status = "TOO FLAT"
                snapshot.coach = "Raise the nose for a manual or the tail for a nose manual."
            } else {
                snapshot.status = "TOO HIGH"
                snapshot.coach = "Lower the lifted end slightly toward the target angle."
            }
            return
        }

        if activeSide != side {
            settle()
            activeSide = side
            snapshot.side = side
            snapshot.currentHoldSeconds = 0
            currentQualitySum = 0
            currentQualityCount = 0
            currentMeanTilt = 0
            currentTiltM2 = 0
            countedAttempt = false
            goalRecorded = false
        }
        // Only count adjacent qualified samples, never time spent flat,
        // inverted, in a different balance direction, or sensor-disconnected.
        let acceptedDt: Double
        if let lastGood = lastGoodUptime, t - lastGood > 0,
           t - lastGood <= 0.12 {
            acceptedDt = t - lastGood
        } else {
            acceptedDt = 0
            snapshot.currentHoldSeconds = 0
            currentQualitySum = 0
            currentQualityCount = 0
            currentMeanTilt = 0
            currentTiltM2 = 0
            countedAttempt = false
            goalRecorded = false
        }
        lastGoodUptime = t
        snapshot.currentHoldSeconds += acceptedDt
        currentQualitySum += quality
        currentQualityCount += 1
        let difference = tilt - currentMeanTilt
        currentMeanTilt += difference / Double(currentQualityCount)
        currentTiltM2 += difference * (tilt - currentMeanTilt)
        snapshot.wobbleRMSE = sqrt(max(0, currentTiltM2) / Double(currentQualityCount))
        snapshot.averageHoldStability = currentQualitySum / Double(currentQualityCount)
        snapshot.status = side.rawValue.uppercased()
        snapshot.coach = quality >= 78 ? "Smooth balance. Keep holding!" :
            "Small, controlled corrections. Aim for \(Int(target))°."

        if !countedAttempt && snapshot.currentHoldSeconds >= 0.35 {
            countedAttempt = true
            if side == .manual { snapshot.manualAttempts += 1 }
            else { snapshot.noseManualAttempts += 1 }
        }
        if side == .manual {
            snapshot.longestManualSeconds = max(
                snapshot.longestManualSeconds, snapshot.currentHoldSeconds)
        } else {
            snapshot.longestNoseManualSeconds = max(
                snapshot.longestNoseManualSeconds, snapshot.currentHoldSeconds)
        }
        if !goalRecorded && snapshot.currentHoldSeconds >= settings.goalSeconds {
            snapshot.completedGoals += 1
            goalRecorded = true
        }
        snapshot.currentGoalAchieved = goalRecorded
    }

    private mutating func settle() {
        guard activeSide != nil else { return }
        if countedAttempt && currentQualityCount > 0 {
            completedQualitySum += currentQualitySum / Double(currentQualityCount)
            completedQualityCount += 1
        }
        activeSide = nil
        lastGoodUptime = nil
        snapshot.side = nil
        snapshot.currentHoldSeconds = 0
        snapshot.currentGoalAchieved = false
        countedAttempt = false
        goalRecorded = false
    }

    func savedRecord(sessionID: String, timestamp: Date = Date()) -> SavedManualPractice {
        SavedManualPractice(
            id: sessionID, finishedAt: timestamp, settings: settings,
            bestManualSeconds: snapshot.longestManualSeconds,
            bestNoseSeconds: snapshot.longestNoseManualSeconds,
            manualAttempts: snapshot.manualAttempts,
            noseManualAttempts: snapshot.noseManualAttempts,
            goalsReached: snapshot.completedGoals,
            averageStability: completedQualityCount > 0
                ? completedQualitySum / Double(completedQualityCount)
                : snapshot.averageHoldStability,
            upsideDownSamples: snapshot.inversionObservations)
    }
}

/// Append-only local practice results. Raw CSV remains in SessionArchive.
final class ManualPracticeHistory {
    let directory: URL
    private(set) var sessions: [SavedManualPractice] = []
    private(set) var errorMessage: String?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkateFitManualPractice", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory,
                                                    withIntermediateDirectories: true)
            for url in try FileManager.default.contentsOfDirectory(
                at: self.directory, includingPropertiesForKeys: nil
            ).filter({ $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("balance-") }) {
                if let record = try? JSONDecoder().decode(SavedManualPractice.self,
                                  from: Data(contentsOf: url)) {
                    sessions.append(record)
                }
            }
            sessions.sort { $0.finishedAt > $1.finishedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func append(_ record: SavedManualPractice) {
        guard !record.id.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("balance-\(record.id).json")
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            sessions.removeAll { $0.id == record.id }
            sessions.insert(record, at: 0)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
