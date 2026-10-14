import Foundation

/// Descriptive measures only. Rotation measures are accumulated angular travel,
/// NOT verified trick counts, distance traveled, or foot-contact measurements.
struct SessionStatistics: Codable, Equatable {
    var durationSeconds: Double = 0
    var boardSamples = 0
    var phoneSamples = 0
    var otherEarbudSamples = 0
    var peakBoardAccelerationG = 0.0
    var peakBoardRotationRateRadS = 0.0
    var peakNoseUpDegrees = 0.0
    var peakTailUpDegrees = 0.0
    var peakRollDegrees = 0.0
    var peakRelativeYawDegrees = 0.0
    var cumulativePitchRotationDegrees = 0.0
    var cumulativeRollRotationDegrees = 0.0
    var cumulativeYawRotationDegrees = 0.0
    var impactSpikes = 0
    var manualAngleSeconds = 0.0
    var noseManualAngleSeconds = 0.0
    var possibleEvents = 0
    var possibleManuals = 0
    var possibleNoseManuals = 0
    var possibleFlipOrShoveEvents = 0
}

struct SavedSkateSession: Codable, Identifiable, Equatable {
    let id: String
    var startedAt: Date
    var endedAt: Date?
    var boardSide: String
    var calibrated = false
    var isSynthetic = false
    var csvFilename: String
    var stats = SessionStatistics()
    var eventKinds: [String: Int] = [:]
}

/// Streaming, crash-resilient local session storage. Raw samples are appended
/// incrementally to Application Support rather than held in RAM for the entire
/// skateboard session. Every few seconds a stats JSON snapshot is persisted so
/// prior recording history survives app restarts.
@MainActor
final class SessionArchive {
    private(set) var history: [SavedSkateSession] = []
    private(set) var current: SavedSkateSession?
    private(set) var errorMessage: String?

    private var output: FileHandle?
    private var bufferedRows: [String] = []
    private var lastBoardUptime: TimeInterval?
    private var lastImpactAt: TimeInterval?
    private var lastImpactAbove = false
    private var lastSnapshotAt: TimeInterval = 0

    private let snapshotsEverySeconds: TimeInterval = 6
    private let impactThresholdG = 1.9
    private let impactSeparationSeconds = 0.30

    let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("SkateFitSessions", isDirectory: true)
        self.directory = base
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try refreshHistory()
        } catch {
            errorMessage = "Couldn't load saved sessions: \(error.localizedDescription)"
        }
    }

    var currentFileURL: URL? {
        guard let current else { return nil }
        return directory.appendingPathComponent(current.csvFilename)
    }

    func fileURL(for session: SavedSkateSession) -> URL {
        directory.appendingPathComponent(session.csvFilename)
    }

    func begin(id: String, boardSide: String, synthetic: Bool) throws {
        if current != nil { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let record = SavedSkateSession(
            id: id, startedAt: Date(), endedAt: nil, boardSide: boardSide,
            calibrated: false, isSynthetic: synthetic,
            csvFilename: "session-\(id).csv"
        )
        let csv = fileURL(for: record)
        guard FileManager.default.createFile(
            atPath: csv.path,
            contents: Data((MotionSample.csvHeader + "\n").utf8)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        output = try FileHandle(forWritingTo: csv)
        try output?.seekToEnd()
        current = record
        bufferedRows.removeAll(keepingCapacity: true)
        lastBoardUptime = nil
        lastImpactAt = nil
        lastImpactAbove = false
        lastSnapshotAt = ProcessInfo.processInfo.systemUptime
        try writeSnapshot(record)
        errorMessage = nil
    }

    func setBoardSide(_ side: String) {
        guard current != nil else { return }
        current?.boardSide = side
    }

    func observe(_ sample: MotionSample, acceptedBoard: Bool,
                 calibration: BoardCalibration, orientation: BoardOrientation?) throws {
        guard var session = current else { return }
        var stats = session.stats
        stats.durationSeconds = Date().timeIntervalSince(session.startedAt)
        if sample.source == .phone {
            stats.phoneSamples += 1
        } else if acceptedBoard {
            stats.boardSamples += 1
            let accelerationG = sample.acceleration.magnitude
            stats.peakBoardAccelerationG = max(
                stats.peakBoardAccelerationG, accelerationG)
            stats.peakBoardRotationRateRadS = max(
                stats.peakBoardRotationRateRadS, sample.rotationRate.magnitude)

            if accelerationG >= impactThresholdG && !lastImpactAbove &&
                (lastImpactAt == nil ||
                 sample.hostUptime - (lastImpactAt ?? 0) >= impactSeparationSeconds) {
                stats.impactSpikes += 1
                lastImpactAt = sample.hostUptime
            }
            lastImpactAbove = accelerationG >= impactThresholdG

            if let orientation {
                stats.peakNoseUpDegrees = max(
                    stats.peakNoseUpDegrees, orientation.pitchDegrees)
                stats.peakTailUpDegrees = max(
                    stats.peakTailUpDegrees, -orientation.pitchDegrees)
                stats.peakRollDegrees = max(
                    stats.peakRollDegrees, abs(orientation.rollDegrees))
                if orientation.headingAvailable {
                    stats.peakRelativeYawDegrees = max(
                        stats.peakRelativeYawDegrees, abs(orientation.yawDegrees))
                }
            }

            if let previous = lastBoardUptime,
               calibration.isPhysicallyPlausible,
               let length = calibration.lengthAxis,
               let width = calibration.widthAxis,
               let vertical = calibration.flatGravity {
                let dt = sample.hostUptime - previous
                if dt > 0.0001 && dt <= 0.18 {
                    let scale = 180 / Double.pi * dt
                    // Fixed sensor-frame axes are calibrated from the board.
                    // Cumulative travel is not a count of completed 360 tricks.
                    let rate = sample.rotationRate
                    stats.cumulativeRollRotationDegrees += abs(rate.dot(length)) * scale
                    stats.cumulativePitchRotationDegrees += abs(rate.dot(width)) * scale
                    stats.cumulativeYawRotationDegrees += abs(rate.dot(vertical)) * scale
                    if let orientation,
                       abs(orientation.pitchDegrees) >= 6,
                       abs(orientation.pitchDegrees) < calibration.manualUpperLimit,
                       rate.magnitude < 2 {
                        if orientation.pitchDegrees > 0 {
                            stats.manualAngleSeconds += dt
                        } else {
                            stats.noseManualAngleSeconds += dt
                        }
                    }
                }
            }
            lastBoardUptime = sample.hostUptime
        } else if sample.source == .headphone {
            stats.otherEarbudSamples += 1
        }
        session.stats = stats
        current = session
        bufferedRows.append(sample.csvRow)
        if bufferedRows.count >= 120 {
            try flushRawRows()
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSnapshotAt >= snapshotsEverySeconds {
            try writeSnapshot(session)
            lastSnapshotAt = now
        }
    }

    func noteEvents(_ events: [TrickEvent]) {
        guard !events.isEmpty, var session = current else { return }
        for event in events {
            session.stats.possibleEvents += 1
            session.eventKinds[event.kind, default: 0] += 1
            switch event.kind {
            case "Possible manual": session.stats.possibleManuals += 1
            case "Possible nose manual": session.stats.possibleNoseManuals += 1
            default:
                if event.kind.contains("flip") || event.kind.contains("shove") {
                    session.stats.possibleFlipOrShoveEvents += 1
                }
            }
        }
        current = session
    }

    @discardableResult
    func finish(calibrated: Bool) throws -> SavedSkateSession? {
        guard var session = current else { return nil }
        try flushRawRows()
        try output?.close()
        output = nil
        session.endedAt = Date()
        session.calibrated = calibrated
        session.stats.durationSeconds = session.endedAt?.timeIntervalSince(
            session.startedAt) ?? session.stats.durationSeconds
        try writeSnapshot(session)
        current = nil
        history.removeAll { $0.id == session.id }
        history.insert(session, at: 0)
        return session
    }

    private func flushRawRows() throws {
        guard !bufferedRows.isEmpty else { return }
        let data = Data((bufferedRows.joined(separator: "\n") + "\n").utf8)
        try output?.write(contentsOf: data)
        bufferedRows.removeAll(keepingCapacity: true)
    }

    private func writeSnapshot(_ value: SavedSkateSession) throws {
        let url = directory.appendingPathComponent("session-\(value.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func refreshHistory() throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("session-") }
        var found: [SavedSkateSession] = []
        for file in urls {
            do {
                found.append(try JSONDecoder().decode(
                    SavedSkateSession.self, from: Data(contentsOf: file)))
            } catch {
                // Preserve corrupt files for diagnostics; do not erase old sessions.
                errorMessage = "Could not read session \(file.lastPathComponent)."
            }
        }
        history = found.sorted { $0.startedAt > $1.startedAt }
    }
}
