import Foundation
import SwiftUI

/// Configuration is fetched repeatedly while the app runs. The public development
/// dashboard may edit these numerical rules without requiring a new iOS build.
/// This is deliberately a data-only configuration, not remote code execution.
struct RemoteRules: Codable, Equatable {
    var manualPitchDegrees = 6.0
    var minimumManualSeconds = 0.45
    var impactThresholdG = 1.9
    var rotationStartRate = 2.6
    var movementThresholdG = 0.9
    var maxCandidateSeconds = 1.25
}

private struct RemoteConfigResponse: Decodable {
    let version: Int
    let rules: RemoteRules
}

struct RemoteCalibration: Codable {
    let flat: Vector3
    let tail: Vector3
    let nose: Vector3

    init?(_ board: BoardCalibration) {
        guard let flat = board.poses[.wheelsDown],
              let tail = board.poses[.tailContact],
              let nose = board.poses[.noseContact],
              board.isPhysicallyPlausible else { return nil }
        self.flat = flat
        self.tail = tail
        self.nose = nose
    }
}

private struct TelemetryBatch: Codable {
    let sessionId: String
    let batchId: String
    let device: String
    let preferredSide: String
    let samples: [MotionSample]
    let events: [TrickEvent]
    let calibration: RemoteCalibration?
}

/// Store before transmit, retry over cellular when reachable, and never delete
/// a pending batch until the HTTP server confirms it. Server batch IDs are
/// idempotent so a network timeout cannot duplicate a confirmed batch.
@MainActor
final class TelemetryUploader: ObservableObject {
    static let dashboardURL = URL(string: "https://skatefit-motion-lab.mikejshaffer.workers.dev")!

    @Published private(set) var status = "Cloud sync waiting"
    @Published private(set) var queuedBatchCount = 0
    @Published private(set) var uploadedSampleCount = 0
    @Published private(set) var rulesVersion = 0
    @Published private(set) var remoteRules = RemoteRules()

    var onRulesChanged: ((RemoteRules) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let baseURL = dashboardURL
    private var queue: [TelemetryBatch] = []
    private var isFlushing = false
    private var maintenanceTask: Task<Void, Never>?
    private var lastRulesVersion: Int = -1

    private var folder: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("SkateFitMotionPending", isDirectory: true)
    }

    init() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in urls {
                do {
                    let batch = try decoder.decode(TelemetryBatch.self, from: Data(contentsOf: url))
                    queue.append(batch)
                } catch {
                    // Do not delete unreadable batches. They may be useful for debugging.
                    status = "Saved batch unreadable: \(url.lastPathComponent)."
                }
            }
            queuedBatchCount = queue.count
            if queuedBatchCount > 0 {
                status = "Restored \(queuedBatchCount) batches saved while offline."
            }
        } catch {
            status = "Cloud queue unavailable: \(error.localizedDescription)"
        }
    }

    func startSync() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            var ticks = 0
            while !Task.isCancelled {
                if ticks % 5 == 0 { await self.fetchRules() }
                await self.flush()
                ticks += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Stop the polling loop only when the UI no longer needs a live connection.
    func stopSync() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
    }

    @discardableResult
    func enqueue(sessionId: String,
                 boardSide: HeadphoneSide,
                 samples: [MotionSample],
                 events: [TrickEvent],
                 calibration: BoardCalibration) -> Bool {
        guard !samples.isEmpty || !events.isEmpty else { return true }
        // Keep each request comfortably under the server's 240 KB JSON limit.
        // Event-only chunks are handled separately in the caller.
        let id = UUID().uuidString
        let batch = TelemetryBatch(
            sessionId: sessionId, batchId: id,
            device: "iPhone SkateFit Motion Lab",
            preferredSide: boardSide.rawValue, samples: samples,
            events: events,
            calibration: RemoteCalibration(calibration)
        )
        do {
            let file = folder.appendingPathComponent("\(id).json")
            try encoder.encode(batch).write(to: file, options: .atomic)
            queue.append(batch)
            queuedBatchCount = queue.count
            status = "Queued \(samples.count) readings for cellular sync."
            startSync()
            return true
        } catch {
            status = "Couldn't persist cloud batch: \(error.localizedDescription). Local CSV remains available."
            return false
        }
    }

    func refreshRules() async { await fetchRules() }

    private func fetchRules() async {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/config"))
            request.timeoutInterval = 9
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return
            }
            let config = try decoder.decode(RemoteConfigResponse.self, from: data)
            if config.version != lastRulesVersion {
                remoteRules = config.rules
                rulesVersion = config.version
                lastRulesVersion = config.version
                onRulesChanged?(config.rules)
            }
        } catch {
            // An offline phone keeps the most recent parameters and continues
            // recording. The queue sync will resume over cellular.
        }
    }

    private func flush() async {
        guard !isFlushing, !queue.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        while !queue.isEmpty && !Task.isCancelled {
            let batch = queue[0]
            do {
                var request = URLRequest(url: baseURL.appendingPathComponent("api/ingest"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 12
                request.httpBody = try encoder.encode(batch)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    status = "Upload postponed. Cloud returned \((response as? HTTPURLResponse)?.statusCode ?? -1)."
                    return
                }
                // The server accepted this ID or recognized an earlier retry.
                queue.removeFirst()
                queuedBatchCount = queue.count
                uploadedSampleCount += batch.samples.count
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(batch.batchId).json"))
                status = queuedBatchCount == 0
                    ? "Cloud connected. All available readings uploaded."
                    : "Cloud connected. \(queuedBatchCount) pending batches."
            } catch {
                status = "Cellular unavailable or cloud unreachable. \(queue.count) batches safely queued."
                return
            }
        }
    }
}
