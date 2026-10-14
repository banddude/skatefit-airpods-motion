import Combine
import AVFoundation
import CoreMotion
import Foundation
import SwiftUI

/// Calibration must never silently fall back to phone data. Keeping this
/// check pure allows tests without pairing physical AirPods in the simulator.
enum BoardSensorReadiness {
    static func canCalibrate(boardReadings: Int, detectedSide: String,
                             expectedSide: String, lastReading: TimeInterval?,
                             now: TimeInterval) -> Bool {
        guard boardReadings > 0, detectedSide == expectedSide,
              let lastReading else { return false }
        return now >= lastReading && now - lastReading < 4
    }
}

/// Only adopt a newly observed earbud when we have no board readings or
/// calibration. Otherwise a source switch might silently corrupt a run.
enum BoardSensorSelection {
    static func shouldAutoSelect(detectedSide: String, selectedSide: String,
                                 boardReadings: Int, calibrationStarted: Bool,
                                 hasSavedPose: Bool) -> Bool {
        guard ["left", "right"].contains(detectedSide),
              detectedSide != selectedSide,
              boardReadings == 0,
              !calibrationStarted,
              !hasSavedPose else { return false }
        return true
    }
}

/// Main-actor state owned by the UI. Core Motion delivers on a private operation queue.
/// Raw samples are also sent to the independent cloud collector over cellular.
@MainActor
final class MotionStore: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published private(set) var isRecording = false
    private static let boardSideKey = "skatefitMotionLab.boardMountedAirPodSide"
    @Published var boardSide: HeadphoneSide = .left {
        didSet {
            UserDefaults.standard.set(boardSide.rawValue, forKey: Self.boardSideKey)
        }
    }
    @Published var cloudSyncEnabled = true
    @Published private(set) var sessionId = ""
    @Published private(set) var status = "Ready. Pair AirPods Pro and mount one securely."
    @Published private(set) var cloudStatus = "Connecting to cloud..."
    @Published private(set) var pendingCloudBatches = 0
    @Published private(set) var remoteRulesVersion = 0
    @Published private(set) var boardSampleCount = 0
    @Published private(set) var phoneSampleCount = 0
    @Published private(set) var rejectedHeadphoneCount = 0
    @Published private(set) var headphoneStatus = "AirPods motion has not been checked."
    @Published private(set) var headphonePermission = "Unknown"
    @Published private(set) var headphoneStreamActive = false
    @Published private(set) var headphoneDetectedSide = "none"
    @Published private(set) var headphoneTotalSamples = 0
    @Published private(set) var audioOutput = "Not checked"
    @Published private(set) var audioWakeStatus = "Not yet played."
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var latestPitch: Double?
    @Published private(set) var latestOrientation: BoardOrientation?
    @Published private(set) var latestBoardAcceleration: Vector3?
    @Published private(set) var latestBoardRotationRate: Vector3?
    @Published private(set) var liveStatistics = SessionStatistics()
    @Published private(set) var savedSessions: [SavedSkateSession] = []
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var calibration = BoardCalibration()
    @Published private(set) var calibrationPose: CalibrationPose?
    @Published private(set) var events: [TrickEvent] = []
    @Published private(set) var exportedFile: URL?

    private let headphone = CMHeadphoneMotionManager()
    private let phone = CMMotionManager()
    private let cloud = TelemetryUploader()
    private let archive = SessionArchive()
    private let audioWake = AirPodAudioWake()
    private var subscriptions = Set<AnyCancellable>()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.banddude.skatefit.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var pendingCloudSamples: [MotionSample] = []
    private var pendingCloudEvents: [TrickEvent] = []
    private var detector = TrickDetector()
    private var calibrationGravities: [Vector3] = []
    private var calibrationLastAttitude: Quaternion4?
    private var calibrationStart: TimeInterval?
    private var calibrationRequestedAt: TimeInterval?
    private var lastHeadphoneReadingAt: TimeInterval?
    private var monitorTask: Task<Void, Never>?
    private var lastHeadphoneStreamStart: TimeInterval?
    private var lastUIUpdate = 0.0
    private var lastStatisticsUpdate = 0.0
    private var isSyntheticDemo = false

    var hasCalibration: Bool { calibration.isPhysicallyPlausible }
    var headphoneAvailable: Bool { headphone.isDeviceMotionAvailable }
    var phoneAvailable: Bool { phone.isDeviceMotionAvailable }
    var liveDashboardURL: URL { TelemetryUploader.dashboardURL }

    func savedCSV(for session: SavedSkateSession) -> URL {
        archive.fileURL(for: session)
    }
    /// True only when the selected board AirPod has delivered a recent reading.
    /// Do not confuse an active Core Motion manager with actual sensor data.
    var boardSensorReady: Bool {
        BoardSensorReadiness.canCalibrate(
            boardReadings: boardSampleCount,
            detectedSide: headphoneDetectedSide,
            expectedSide: boardSide.rawValue,
            lastReading: lastHeadphoneReadingAt,
            now: ProcessInfo.processInfo.systemUptime
        )
    }


    override init() {
        super.init()
        savedSessions = archive.history
        if let saved = UserDefaults.standard.string(forKey: Self.boardSideKey),
           let savedSide = HeadphoneSide(rawValue: saved) {
            boardSide = savedSide
        }
        headphone.delegate = self
        updateHeadphonePermission()
        refreshAudioOutput()
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAudioOutput() }
            }
            .store(in: &subscriptions)
        cloud.$status.sink { [weak self] in self?.cloudStatus = $0 }
            .store(in: &subscriptions)
        cloud.$queuedBatchCount.sink { [weak self] in self?.pendingCloudBatches = $0 }
            .store(in: &subscriptions)
        cloud.$rulesVersion.sink { [weak self] in self?.remoteRulesVersion = $0 }
            .store(in: &subscriptions)
        cloud.onRulesChanged = { [weak self] rules in
            guard let self else { return }
            self.detector.rules = rules
            self.detector.reset()
        }
        cloud.startSync()
    }

    func startRecording() {
        guard !isRecording else { return }
        resetSession()
        calibration = BoardCalibration()
        let newSessionId = UUID().uuidString
        do {
            try archive.begin(id: newSessionId, boardSide: boardSide.rawValue, synthetic: false)
        } catch {
            status = "Could not save session locally: \(error.localizedDescription)"
            return
        }
        sessionId = newSessionId
        sessionStartedAt = archive.current?.startedAt
        isRecording = true
        UIApplication.shared.isIdleTimerDisabled = true
        phone.deviceMotionUpdateInterval = 1.0 / 100.0

        if phone.isDeviceMotionAvailable {
            phone.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
                let uptime = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [weak self] in
                    guard let self, let motion else {
                        if let error { self?.status = "Phone motion: \(error.localizedDescription)" }
                        return
                    }
                    self.receive(MotionSample(motion: motion, source: .phone, receivedAt: uptime))
                }
            }
        }
        headphone.startConnectionStatusUpdates()
        ensureHeadphoneStream()
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isRecording else { return }
                self.ensureHeadphoneStream()
                self.checkCalibrationTimeout()
            }
        }
        status = headphone.isDeviceMotionAvailable
            ? "Recording. Waiting for AirPod sensor readings; board side: \(boardSide.title)."
            : "Phone is recording, but AirPods motion is unavailable. Open Bluetooth settings and turn Automatic Ear Detection off."
    }

    func stopRecording() {
        guard isRecording else { return }
        monitorTask?.cancel()
        monitorTask = nil
        headphone.stopDeviceMotionUpdates()
        headphone.stopConnectionStatusUpdates()
        phone.stopDeviceMotionUpdates()
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        calibrationPose = nil
        calibrationStart = nil
        calibrationRequestedAt = nil
        calibrationProgress = 0
        calibrationGravities.removeAll()
        stagePendingTelemetry()
        do {
            if let summary = try archive.finish(calibrated: calibration.isPhysicallyPlausible) {
                exportedFile = archive.fileURL(for: summary)
                liveStatistics = summary.stats
                savedSessions = archive.history
                if cloudSyncEnabled && !isSyntheticDemo {
                    _ = cloud.enqueueSummary(summary)
                }
                status = "Saved \(summary.stats.boardSamples) board and \(summary.stats.phoneSamples) phone readings, \(summary.stats.possibleEvents) possible events."
            } else {
                status = "Recording stopped. No active archive to save."
            }
        } catch {
            status = "Stopped, but saving the session failed: \(error.localizedDescription)"
        }
        isSyntheticDemo = false
    }

    /// Allows a new guided calibration without ending the current session.
    func resetCalibration() {
        calibration = BoardCalibration()
        calibrationPose = nil
        calibrationStart = nil
        calibrationRequestedAt = nil
        calibrationGravities = []
        calibrationLastAttitude = nil
        calibrationProgress = 0
        latestPitch = nil
        latestOrientation = nil
        detector.reset()
        status = "Hold the board in each reference position to recalibrate."
    }

    func calibrate(_ pose: CalibrationPose) {
        guard isRecording else {
            status = "Start recording before calibrating."
            return
        }
        guard BoardSensorReadiness.canCalibrate(
            boardReadings: boardSampleCount,
            detectedSide: headphoneDetectedSide,
            expectedSide: boardSide.rawValue,
            lastReading: lastHeadphoneReadingAt,
            now: ProcessInfo.processInfo.systemUptime) else {
            if headphoneTotalSamples > 0 && headphoneDetectedSide != boardSide.rawValue {
                status = "AirPod \(headphoneDetectedSide) is streaming, but \(boardSide.rawValue) is selected. Stop recording and select the AirPod attached to the board."
            } else {
                status = "Cannot calibrate: no recent board AirPod samples. Only phone motion is uploading. Check AirPods Bluetooth connection and Automatic Ear Detection, then tap Retry AirPods."
            }
            ensureHeadphoneStream()
            return
        }
        calibrationPose = pose
        calibrationStart = nil
        calibrationRequestedAt = ProcessInfo.processInfo.systemUptime
        calibrationProgress = 0
        calibrationGravities = []
        calibrationLastAttitude = nil
        status = "Hold \(pose.rawValue.lowercased()) steady for about 1.5 seconds."
    }

    func refreshAudioOutput() {
        audioOutput = AirPodAudioWake.audioOutputDescription()
    }

    func wakeAirPods() {
        refreshAudioOutput()
        do {
            audioWakeStatus = try audioWake.wake()
        } catch {
            audioWakeStatus = "Audio wake failed: \(error.localizedDescription)"
        }
        refreshAudioOutput()
        // Only restart the stream if no active board data has arrived.
        if isRecording, headphoneTotalSamples == 0 { ensureHeadphoneStream() }
    }

    func retryHeadphones() {
        updateHeadphonePermission()
        headphone.stopDeviceMotionUpdates()
        headphoneStreamActive = false
        lastHeadphoneStreamStart = nil
        headphone.startConnectionStatusUpdates()
        ensureHeadphoneStream()
        status = "Retrying AirPods motion. Open the AirPods Bluetooth settings if the sensor stays unavailable."
    }

    private func updateHeadphonePermission() {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized: headphonePermission = "Authorized"
        case .denied: headphonePermission = "Denied. Enable Motion & Fitness access in Settings."
        case .restricted: headphonePermission = "Restricted"
        case .notDetermined: headphonePermission = "Not yet requested"
        @unknown default: headphonePermission = "Unknown authorization"
        }
    }

    private func ensureHeadphoneStream() {
        guard isRecording, !isSyntheticDemo else { return }
        updateHeadphonePermission()
        let now = ProcessInfo.processInfo.systemUptime
        if !headphone.isDeviceMotionAvailable {
            headphoneStreamActive = false
            headphoneStatus = "AirPods motion unavailable. Your phone can upload data, but calibration needs the board AirPod."
            return
        }
        let stale = lastHeadphoneReadingAt.map { now - $0 > 8 }
            ?? (lastHeadphoneStreamStart.map { now - $0 > 8 } ?? false)
        if headphone.isDeviceMotionActive && !stale {
            headphoneStreamActive = true
            if lastHeadphoneReadingAt == nil {
                headphoneStatus = "AirPods sensor opened, but no readings. Set the mounted AirPod as Microphone, turn off Automatic Ear Detection, and play a brief wake tone through AirPods."
            }
            return
        }
        if headphone.isDeviceMotionActive { headphone.stopDeviceMotionUpdates() }
        lastHeadphoneStreamStart = now
        headphoneStreamActive = false
        headphoneStatus = "Connecting to AirPods motion stream..."
        headphone.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            let uptime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.headphoneStatus = "AirPods sensor error: \(error.localizedDescription)"
                    self.updateHeadphonePermission()
                    return
                }
                guard let motion else { return }
                self.receive(MotionSample(motion: motion, source: .headphone, receivedAt: uptime))
            }
        }
    }

    private func checkCalibrationTimeout() {
        guard calibrationPose != nil, let requested = calibrationRequestedAt else { return }
        if ProcessInfo.processInfo.systemUptime - requested > 6,
           (calibrationStart == nil || calibrationProgress < 1) {
            calibrationPose = nil
            calibrationStart = nil
            calibrationRequestedAt = nil
            calibrationGravities = []
            calibrationProgress = 0
            status = "Calibration timed out: no continuous board AirPod motion. Check the AirPod source and tap Retry AirPods."
        }
    }

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.headphoneStatus = "Headphones connected; checking motion..."
            self?.ensureHeadphoneStream()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.headphoneStreamActive = false
            self?.headphoneStatus = "AirPods disconnected. Check Automatic Ear Detection and Bluetooth audio connection."
        }
    }

    func forceCloudSync() {
        cloud.startSync()
        Task { await cloud.refreshRules() }
    }

    private func stagePendingTelemetry() {
        guard !isSyntheticDemo else {
            pendingCloudSamples.removeAll()
            pendingCloudEvents.removeAll()
            return
        }
        // Opting out of cellular upload still permits local CSV capture.
        guard cloudSyncEnabled, !sessionId.isEmpty else { return }
        while !pendingCloudSamples.isEmpty || !pendingCloudEvents.isEmpty {
            let sampleCount = min(120, pendingCloudSamples.count)
            let eventCount = min(25, pendingCloudEvents.count)
            let chunk = Array(pendingCloudSamples.prefix(sampleCount))
            let taggedEvents = Array(pendingCloudEvents.prefix(eventCount))
            let diagnostic = MotionDiagnostics(
                headphoneAvailable: headphone.isDeviceMotionAvailable,
                headphoneActive: headphone.isDeviceMotionActive,
                permission: headphonePermission,
                detectedSide: headphoneDetectedSide,
                boardReadings: boardSampleCount,
                headphoneReadings: headphoneTotalSamples,
                phoneReadings: phoneSampleCount,
                message: headphoneStatus,
                audioOutput: audioOutput,
                audioWakeStatus: audioWakeStatus
            )
            let saved = cloud.enqueue(sessionId: sessionId, boardSide: boardSide,
                                      samples: chunk, events: taggedEvents,
                                      calibration: calibration, diagnostics: diagnostic)
            if !saved { return }
            pendingCloudSamples.removeFirst(sampleCount)
            pendingCloudEvents.removeFirst(eventCount)
        }
    }

    private func receive(_ sample: MotionSample) {
        guard isRecording else { return }
        if !isSyntheticDemo && cloudSyncEnabled {
            pendingCloudSamples.append(sample)
            if pendingCloudSamples.count >= 120 { stagePendingTelemetry() }
        }

        if sample.source == .phone {
            phoneSampleCount += 1
            saveSample(sample, isBoard: false, orientation: nil)
            return
        }
        // Record all sources for diagnostics, but never classify the ear-worn
        // or incorrectly selected AirPod as movement from the skateboard.
        if sample.source == .headphone {
            headphoneTotalSamples += 1
            lastHeadphoneReadingAt = sample.hostUptime
            headphoneDetectedSide = sample.sensorLocation
            headphoneStreamActive = true
            if headphoneTotalSamples == 1 || headphoneTotalSamples % 10 == 0 {
                headphoneStatus = "Receiving AirPod \(sample.sensorLocation) motion. \(headphoneTotalSamples) readings."
            }
        }
        if sample.source == .headphone && BoardSensorSelection.shouldAutoSelect(
            detectedSide: sample.sensorLocation,
            selectedSide: boardSide.rawValue,
            boardReadings: boardSampleCount,
            calibrationStarted: calibrationPose != nil,
            hasSavedPose: !calibration.poses.isEmpty) {
            // With one AirPod mounted and the other in its case, the active
            // headphone is the board sensor. Match the actual earbud, not
            // the hard-coded Left default, and remember it next session.
            if let detected = HeadphoneSide(rawValue: sample.sensorLocation) {
                boardSide = detected
                archive.setBoardSide(detected.rawValue)
                status = "Detected \(detected.title) AirPod motion. Ready to calibrate."
            }
        }
        if sample.source == .headphone && sample.sensorLocation != boardSide.rawValue {
            rejectedHeadphoneCount += 1
            saveSample(sample, isBoard: false, orientation: nil)
            if sample.hostUptime - lastUIUpdate > 0.5 {
                status = "Motion source is \(sample.sensorLocation), but \(boardSide.rawValue) is mounted. Ignoring for classification."
                lastUIUpdate = sample.hostUptime
            }
            return
        }
        boardSampleCount += 1
        let motionOrientation = calibration.orientation(for: sample)

        if let pose = calibrationPose {
            if calibrationStart == nil { calibrationStart = sample.hostUptime }
            calibrationGravities.append(sample.gravity)
            calibrationLastAttitude = sample.quaternion
            if let start = calibrationStart {
                calibrationProgress = min(1, max(0, (sample.hostUptime - start) / 1.5))
            }
            if let start = calibrationStart, sample.hostUptime - start >= 1.5 {
                let total = calibrationGravities.reduce(Vector3.zero, +)
                let mean = total * (1.0 / Double(calibrationGravities.count))
                calibration.set(pose, gravity: mean,
                                attitude: calibrationLastAttitude)
                calibrationLastAttitude = nil
                calibrationPose = nil
                calibrationStart = nil
                calibrationRequestedAt = nil
                calibrationProgress = 0
                calibrationGravities = []
                detector.reset()
                status = calibration.isComplete && !calibration.isPhysicallyPlausible
                    ? "Pose references conflict. Recalibrate all three with a rigid mount."
                    : "Saved \(pose.rawValue). \(calibration.poses.count)/3 positions captured."
            }
        } else if calibration.isPhysicallyPlausible {
            let detected = detector.accept(sample, calibration: calibration)
            events.append(contentsOf: detected)
            pendingCloudEvents.append(contentsOf: detected)
            archive.noteEvents(detected)
        }

        saveSample(sample, isBoard: true, orientation: motionOrientation)

        if sample.hostUptime - lastUIUpdate > 0.15 {
            latestOrientation = motionOrientation
            latestBoardAcceleration = sample.acceleration
            latestBoardRotationRate = sample.rotationRate
            latestPitch = motionOrientation?.pitchDegrees
            lastUIUpdate = sample.hostUptime
        }
    }

    private func saveSample(_ sample: MotionSample, isBoard: Bool,
                            orientation: BoardOrientation?) {
        do {
            try archive.observe(sample, acceptedBoard: isBoard,
                                calibration: calibration, orientation: orientation)
            // Avoid triggering SwiftUI re-renders for every sensor callback.
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastStatisticsUpdate >= 0.35 {
                liveStatistics = archive.current?.stats ?? liveStatistics
                lastStatisticsUpdate = now
            }
        } catch {
            status = "Session storage issue: \(error.localizedDescription)"
        }
    }

    private func resetSession() {
        pendingCloudSamples.removeAll(keepingCapacity: true)
        pendingCloudEvents.removeAll(keepingCapacity: true)
        events = []
        detector.reset()
        boardSampleCount = 0
        headphoneTotalSamples = 0
        lastHeadphoneReadingAt = nil
        headphoneDetectedSide = "none"
        calibrationRequestedAt = nil
        calibrationProgress = 0
        phoneSampleCount = 0
        rejectedHeadphoneCount = 0
        latestPitch = nil
        latestOrientation = nil
        latestBoardAcceleration = nil
        latestBoardRotationRate = nil
        liveStatistics = SessionStatistics()
        sessionStartedAt = nil
        lastStatisticsUpdate = 0
        exportedFile = nil
        lastUIUpdate = 0
        isSyntheticDemo = false
    }

    /// Tests UI and classification with generated values. Never uploads demo readings.
    func runSyntheticManualDemo() {
        guard !isRecording else { return }
        resetSession()
        sessionId = "SYNTHETIC-OFFLINE"
        isSyntheticDemo = true
        calibration = BoardCalibration()
        let tilt = 0.46
        calibration.set(.wheelsDown, gravity: Vector3(x: 0, y: 0, z: -1))
        calibration.set(.tailContact,
                        gravity: Vector3(x: sin(tilt), y: 0, z: -cos(tilt)))
        calibration.set(.noseContact,
                        gravity: Vector3(x: -sin(tilt), y: 0, z: -cos(tilt)))
        do {
            try archive.begin(id: UUID().uuidString, boardSide: boardSide.rawValue,
                              synthetic: true)
        } catch {
            status = "Could not save demo session: \(error.localizedDescription)"
            return
        }
        sessionStartedAt = archive.current?.startedAt
        isRecording = true
        let uptime = ProcessInfo.processInfo.systemUptime
        for index in 0..<140 {
            let t = Double(index) * 0.025
            let angle = (index >= 20 && index < 100) ? 0.2 : 0.0
            let g = Vector3(x: sin(angle), y: 0, z: -cos(angle))
            let sample = MotionSample(
                source: .simulation, sensorLocation: boardSide.rawValue,
                hostUptime: uptime + t, deviceTimestamp: t,
                gravity: g, acceleration: .zero, rotationRate: .zero)
            receive(sample)
        }
        stopRecording()
        status = "SYNTHETIC DATA ONLY. No cloud upload. Real sensor testing still required."
    }
}
