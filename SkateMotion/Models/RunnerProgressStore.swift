import Foundation
import Observation

struct RunnerResult: Codable, Equatable {
    var bestScore: Int
    var bestTime: Double
    var bestStars: Int
    var mostPickups: Int
}

struct RunnerCareer: Codable, Equatable {
    var version = 1
    var records: [Int: RunnerResult] = [:]
    var completedRuns = 0
    var touchRuns = 0
    var motionControlledRuns = 0
    var totalPickups = 0
    var totalManualLines = 0
    var totalNoseLines = 0
    var cleanRuns = 0
    var selectedDeck = "Mint"

    var totalStars: Int { records.values.reduce(0) { $0 + $1.bestStars } }
    var highestUnlocked: Int {
        min(5, max(1, (records.keys.max() ?? 0) + 1))
    }
    var totalXP: Int {
        records.values.reduce(0) { $0 + $1.bestScore } / 10 +
            completedRuns * 100 + totalManualLines * 20 + totalNoseLines * 20
    }
    var playerLevel: Int { 1 + totalXP / 500 }
}

struct RunnerDeck: Identifiable {
    let id: String
    let requiredStars: Int
    let tint: String

    static let all: [RunnerDeck] = [
        RunnerDeck(id: "Mint", requiredStars: 0, tint: "mint"),
        RunnerDeck(id: "Sunset", requiredStars: 3, tint: "orange"),
        RunnerDeck(id: "Electric", requiredStars: 6, tint: "cyan"),
        RunnerDeck(id: "Gold", requiredStars: 10, tint: "yellow"),
        RunnerDeck(id: "Midnight", requiredStars: 14, tint: "purple")
    ]
}

struct RunnerCompletion {
    let course: Int
    let score: Int
    let seconds: Double
    let stars: Int
    let pickups: Int
    let manualLines: Int
    let noseLines: Int
    let clean: Bool
}

/// Offline-first career save. Existing valid data is backed up before writes.
/// A corrupt primary never overwrites a valid backup.
@Observable final class RunnerProgressStore {
    private(set) var career: RunnerCareer
    private(set) var recoveredFromBackup = false
    private(set) var saveError: String?
    let saveURL: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directory ?? fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("SkateFitRunner", isDirectory: true)
        saveURL = base.appendingPathComponent("career-v1.json")
        let backup = base.appendingPathComponent("career-v1.backup.json")
        func load(_ url: URL) -> RunnerCareer? {
            guard let bytes = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(RunnerCareer.self, from: bytes),
                  decoded.version == 1,
                  decoded.completedRuns >= 0,
                  decoded.records.values.allSatisfy({
                      $0.bestStars >= 0 && $0.bestStars <= 3 &&
                      $0.bestTime.isFinite && $0.bestTime > 0
                  }) else { return nil }
            return decoded
        }
        let primary = load(saveURL)
        let backupData = load(backup)
        career = primary ?? backupData ?? RunnerCareer()
        recoveredFromBackup = primary == nil && backupData != nil
    }

    func recordCompletion(_ engine: RunnerEngine, mode: RunnerControlMode) {
        guard engine.won else { return }
        record(RunnerCompletion(course: engine.level, score: engine.score,
                                seconds: engine.elapsed, stars: engine.stars,
                                pickups: engine.pickups, manualLines: engine.manualLines,
                                noseLines: engine.noseLines, clean: engine.noHit), mode: mode)
    }

    func record(_ completion: RunnerCompletion, mode: RunnerControlMode) {
        guard (1...5).contains(completion.course),
              (1...3).contains(completion.stars),
              completion.seconds.isFinite && completion.seconds > 0,
              completion.score >= 0, completion.pickups >= 0,
              completion.manualLines >= 0, completion.noseLines >= 0 else { return }
        let prior = career.records[completion.course]
        career.records[completion.course] = RunnerResult(
            bestScore: max(prior?.bestScore ?? 0, completion.score),
            bestTime: min(prior?.bestTime ?? completion.seconds, completion.seconds),
            bestStars: max(prior?.bestStars ?? 0, completion.stars),
            mostPickups: max(prior?.mostPickups ?? 0, completion.pickups)
        )
        career.completedRuns += 1
        if mode == .touch { career.touchRuns += 1 }
        else { career.motionControlledRuns += 1 }
        career.totalPickups += completion.pickups
        career.totalManualLines += completion.manualLines
        career.totalNoseLines += completion.noseLines
        if completion.clean { career.cleanRuns += 1 }
        persist()
    }

    func chooseDeck(_ name: String) {
        guard let deck = RunnerDeck.all.first(where: { $0.id == name }),
              career.totalStars >= deck.requiredStars else { return }
        career.selectedDeck = name
        persist()
    }

    private func persist() {
        let backupURL = saveURL.deletingLastPathComponent()
            .appendingPathComponent("career-v1.backup.json")
        do {
            try fileManager.createDirectory(at: saveURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let encoded = try encoder.encode(career)
            // Keep last known-good save. Never back up a corrupt primary.
            if fileManager.fileExists(atPath: saveURL.path),
               let raw = try? Data(contentsOf: saveURL),
               (try? JSONDecoder().decode(RunnerCareer.self, from: raw)) != nil {
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: saveURL, to: backupURL)
            }
            try encoded.write(to: saveURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Progress couldn't be saved: \(error.localizedDescription)"
        }
    }
}
