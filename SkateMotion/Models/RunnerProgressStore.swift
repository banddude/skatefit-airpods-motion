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
    /// Original beta-11 course IDs 1...5 continue to unlock the next world.
    /// New optional courses have IDs 6...15 and must not corrupt that logic.
    var highestUnlocked: Int {
        min(5, max(1, (records.keys.filter { (1...5).contains($0) }.max() ?? 0) + 1))
    }
    func isUnlocked(_ course: RunnerCourse) -> Bool {
        if course.stageNumber == 1 { return course.worldNumber <= highestUnlocked }
        let previousID = RunnerCourse.id(world: course.worldNumber,
                                         stage: course.stageNumber - 1)
        return records[previousID] != nil
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
        RunnerDeck(id: "Midnight", requiredStars: 14, tint: "purple"),
        RunnerDeck(id: "Streetlight", requiredStars: 21, tint: "pink"),
        RunnerDeck(id: "Ice", requiredStars: 32, tint: "white"),
        RunnerDeck(id: "Legend", requiredStars: 42, tint: "red")
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
    #if os(tvOS)
    private let tvPreferences: UserDefaults?
    private static let tvSaveKey = "SkateFitTV.runner.career.v1"
    #endif

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        #if os(tvOS)
        tvPreferences = directory == nil ? UserDefaults.standard : nil
        let base = directory ?? fileManager.urls(for: .cachesDirectory,
            in: .userDomainMask).first!.appendingPathComponent("SkateFitRunner", isDirectory: true)
        #else
        let base = directory ?? fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("SkateFitRunner", isDirectory: true)
        #endif
        saveURL = base.appendingPathComponent("career-v1.json")
        let backup = base.appendingPathComponent("career-v1.backup.json")
        func decode(_ bytes: Data?) -> RunnerCareer? {
            guard let bytes,
                  let decoded = try? JSONDecoder().decode(RunnerCareer.self, from: bytes),
                  decoded.version == 1,
                  decoded.completedRuns >= 0,
                  decoded.records.values.allSatisfy({
                      $0.bestStars >= 0 && $0.bestStars <= 3 &&
                      $0.bestTime.isFinite && $0.bestTime > 0
                  }) else { return nil }
            return decoded
        }
        #if os(tvOS)
        let primary = decode(tvPreferences?.data(forKey: Self.tvSaveKey)) ??
            decode(try? Data(contentsOf: saveURL))
        let backupData = decode(tvPreferences?.data(forKey: Self.tvSaveKey + ".backup")) ??
            decode(try? Data(contentsOf: backup))
        #else
        let primary = decode(try? Data(contentsOf: saveURL))
        let backupData = decode(try? Data(contentsOf: backup))
        #endif
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
        guard RunnerCourse.catalog.contains(where: { $0.id == completion.course }),
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
            #if os(tvOS)
            // tvOS permits only cache files; keep the small career record in
            // app preferences instead of relying on purgeable file storage.
            if let tvPreferences {
                let encoded = try JSONEncoder().encode(career)
                if let old = tvPreferences.data(forKey: Self.tvSaveKey),
                   (try? JSONDecoder().decode(RunnerCareer.self, from: old)) != nil {
                    tvPreferences.set(old, forKey: Self.tvSaveKey + ".backup")
                }
                tvPreferences.set(encoded, forKey: Self.tvSaveKey)
                saveError = nil
                return
            }
            #endif
            try fileManager.createDirectory(at: saveURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let encoded = try encoder.encode(career)
            // Keep last known-good save. Never back up a corrupt primary.
            if fileManager.fileExists(atPath: saveURL.path),
               let raw = try? Data(contentsOf: saveURL),
               (try? JSONDecoder().decode(RunnerCareer.self, from: raw)) != nil {
                // Atomic replacement retains the old backup if an interrupted
                // filesystem write occurs; never delete the backup first.
                try raw.write(to: backupURL, options: .atomic)
            }
            try encoded.write(to: saveURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Progress couldn't be saved: \(error.localizedDescription)"
        }
    }
}
