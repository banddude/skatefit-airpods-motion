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
    var lastCompletedHold: ManualHoldAttempt?
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
    var attempts: [ManualHoldAttempt]? = nil

    var qualifiedHolds: [ManualHoldAttempt] { attempts ?? [] }
}

struct ManualBalanceTracker {
    private(set) var snapshot = ManualBalanceSnapshot()
    private(set) var settings: ManualBalanceSettings = .init()
    private(set) var attempts: [ManualHoldAttempt] = []

    private var activeSide: ManualSide?
    private var lastHostUptime: TimeInterval?
    private var lastDeviceTimestamp: TimeInterval?
    private var lastQualifiedHostUptime: TimeInterval?
    private var qualitySum = 0.0
    private var qualityCount = 0
    private var meanTilt = 0.0
    private var tiltM2 = 0.0
    private var sideTiltSum = 0.0
    private var currentGoal: ManualBalanceSettings = .init()
    private var countedAttempt = false
    private var goalRecorded = false
    private var completedQualitySum = 0.0
    private var completedQualityCount = 0
    private var wasInverted = false

    mutating func configure(_ value: ManualBalanceSettings) {
        let newSettings = value.validated
        if settings != newSettings { settle(.settingsChanged) }
        settings = newSettings
    }

    mutating func reset() {
        let retainedSettings = settings
        self = ManualBalanceTracker()
        settings = retainedSettings
    }

    mutating func interrupt() {
        settle(.sensorGap)
        lastHostUptime = nil
        lastDeviceTimestamp = nil
        snapshot.status = "SENSOR STREAM INTERRUPTED"
        snapshot.coach = "Reconnect the board AirPod. No disconnected time is counted."
    }

    mutating func finish() {
        settle(.sessionEnded)
    }

    mutating func accept(_ sample: MotionSample, orientation: BoardOrientation?,
                         calibration: BoardCalibration) {
        // Phone motion and any other AirPod cannot count as board practice.
        guard sample.source == .headphone || sample.source == .simulation,
              calibration.isPhysicallyPlausible else { return }

        guard let pose = orientation, [pose.pitchDegrees, pose.rollDegrees,
              pose.upAlignment, sample.hostUptime, sample.deviceTimestamp,
              sample.gravity.x, sample.gravity.y, sample.gravity.z,
              sample.acceleration.x, sample.acceleration.y, sample.acceleration.z,
              sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z]
              .allSatisfy(\.isFinite),
              sample.hostUptime >= 0, sample.deviceTimestamp >= 0 else {
            settle(.invalidSensor)
            snapshot.status = "INVALID SENSOR DATA"
            snapshot.coach = "Invalid measurements are not included in manual timing."
            return
        }

        let t = sample.hostUptime
        var interval = 0.0
        if let lastHost = lastHostUptime {
            let arrivalInterval = t - lastHost
            if arrivalInterval <= 0 || arrivalInterval > 0.30 {
                settle(.sensorGap)
            } else if sample.deviceTimestamp > 0,
                      let previous = lastDeviceTimestamp, previous > 0 {
                let deviceInterval = sample.deviceTimestamp - previous
                if deviceInterval <= 0 || deviceInterval > 0.20 {
                    settle(.sensorGap)
                } else {
                    interval = deviceInterval
                }
            } else {
                interval = arrivalInterval
            }
        }
        lastHostUptime = t
        lastDeviceTimestamp = sample.deviceTimestamp > 0
            ? sample.deviceTimestamp : nil
        if interval > 0 && interval < 0.18 {
            let newRate = min(150, 1 / interval)
            snapshot.sampleRateHz = snapshot.sampleRateHz == 0
                ? newRate : snapshot.sampleRateHz * 0.88 + newRate * 0.12
        }

        snapshot.hasPose = true
        snapshot.measuredSamples += 1
        snapshot.pitchDegrees = pose.pitchDegrees
        snapshot.rollDegrees = pose.rollDegrees
        snapshot.relativeYawDegrees = pose.yawDegrees
        snapshot.isInverted = pose.isInverted
        if pose.isInverted && !wasInverted {
            snapshot.inversionObservations += 1
        }
        wasInverted = pose.isInverted

        if pose.isInverted || pose.isOnEdge {
            settle(.inverted)
            snapshot.status = pose.isInverted ? "BOARD UPSIDE DOWN" : "BOARD ON EDGE"
            snapshot.coach = "Bring the deck back toward level before continuing."
            return
        }

        let gyro = sample.rotationRate
        let pitchRate = abs(gyro.dot(calibration.widthAxis ?? .zero)) * 180 / .pi
        let rollRate = abs(gyro.dot(calibration.lengthAxis ?? .zero)) * 180 / .pi
        let yawRate = abs(gyro.dot(calibration.flatGravity ?? .zero)) * 180 / .pi
        let acceleration = sample.acceleration.magnitude
        snapshot.pitchRateDegreesPerSecond = pitchRate
        snapshot.rollRateDegreesPerSecond = rollRate
        snapshot.yawRateDegreesPerSecond = yawRate
        snapshot.angularSpeedDegreesPerSecond = gyro.magnitude * 180 / .pi
        snapshot.userAccelerationG = acceleration

        let tilt = abs(pose.pitchDegrees)
        let lateral = abs(pose.rollDegrees)
        let side: ManualSide = pose.pitchDegrees > 0 ? .manual : .noseManual
        let target = settings.targetAngleDegrees
        let minimum = max(5, target - settings.toleranceDegrees)
        let maximum = min(calibration.manualUpperLimit,
                          target + settings.toleranceDegrees)
        let steady = lateral <= 12 && pitchRate <= 125 &&
            rollRate <= 125 && acceleration <= 2.5
        let qualifies = tilt >= minimum && tilt <= maximum && steady

        let score = max(0, min(100,
            100 - abs(tilt - target) * 5.8 - lateral * 2.8 -
            pitchRate * 0.12 - rollRate * 0.17 - yawRate * 0.035 -
            max(0, acceleration - 0.15) * 6))
        snapshot.stability = snapshot.measuredSamples <= 1
            ? score : snapshot.stability * 0.78 + score * 0.22

        guard qualifies else {
            let reason: ManualHoldEndReason
            if lateral > 12 {
                reason = .sideways
                snapshot.coach = "Keep the deck level from side to side."
            } else if !steady {
                reason = .tooFast
                snapshot.coach = "Make slower, smaller balance corrections."
            } else if tilt < minimum {
                reason = .returnedFlat
                snapshot.coach = "Lift the nose or tail into your target zone."
            } else {
                reason = .angleTooHigh
                snapshot.coach = "Lower the raised end slightly."
            }
            settle(reason) // Strict: never bridge a flat or unstable frame.
            snapshot.status = reason.rawValue.uppercased()
            return
        }

        if activeSide != side {
            settle(.changedDirection)
            activeSide = side
            currentGoal = settings
            qualitySum = 0
            qualityCount = 0
            meanTilt = 0
            tiltM2 = 0
            sideTiltSum = 0
            countedAttempt = false
            goalRecorded = false
            snapshot.side = side
        }

        // Monotonic AirPod device time is preferred over jittery Bluetooth
        // callback arrivals; a receipt gap still stops the hold above.
        let qualifiedInterval = lastQualifiedHostUptime != nil &&
            interval > 0 && interval <= 0.12 ? interval : 0
        lastQualifiedHostUptime = t
        snapshot.currentHoldSeconds += qualifiedInterval
        qualitySum += score
        qualityCount += 1
        sideTiltSum += lateral
        let difference = tilt - meanTilt
        meanTilt += difference / Double(qualityCount)
        tiltM2 += difference * (tilt - meanTilt)
        snapshot.wobbleRMSE = sqrt(max(0, tiltM2) / Double(qualityCount))
        snapshot.averageHoldStability = qualitySum / Double(qualityCount)
        snapshot.side = side
        snapshot.status = side.rawValue.uppercased()
        snapshot.coach = score >= 78
            ? "Smooth balance. Keep holding."
            : "Make small corrections toward \(Int(target))°."

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
        if !goalRecorded && snapshot.currentHoldSeconds >= currentGoal.goalSeconds {
            snapshot.completedGoals += 1
            goalRecorded = true
        }
        snapshot.currentGoalAchieved = goalRecorded
    }

    private mutating func settle(_ reason: ManualHoldEndReason) {
        guard let activeSide else {
            lastQualifiedHostUptime = nil
            return
        }
        if countedAttempt && qualityCount > 0 {
            let hold = ManualHoldAttempt(
                id: UUID(), side: activeSide,
                seconds: snapshot.currentHoldSeconds,
                averageAngleDegrees: meanTilt,
                wobbleRMSDegrees: sqrt(max(0, tiltM2) / Double(qualityCount)),
                averageSideTiltDegrees: sideTiltSum / Double(qualityCount),
                averageStability: qualitySum / Double(qualityCount),
                targetAngleDegrees: currentGoal.targetAngleDegrees,
                targetSeconds: currentGoal.goalSeconds,
                reachedGoal: goalRecorded,
                endedBy: reason)
            attempts.append(hold)
            snapshot.lastCompletedHold = hold
            completedQualitySum += hold.averageStability
            completedQualityCount += 1
            snapshot.averageHoldStability = completedQualitySum /
                Double(completedQualityCount)
        }
        self.activeSide = nil
        lastQualifiedHostUptime = nil
        snapshot.side = nil
        snapshot.currentHoldSeconds = 0
        snapshot.currentGoalAchieved = false
        snapshot.wobbleRMSE = 0
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
            upsideDownSamples: snapshot.inversionObservations,
            attempts: attempts)
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
