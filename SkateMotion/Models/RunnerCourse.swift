import Foundation

/// Immutable authored course data. IDs 1...5 intentionally keep the five
/// original world-opening courses so existing beta-11 saves remain valid.
enum RunnerFeatureKind: String, Codable {
    case gap, barrier, overhead, manualLine, noseLine, pickup, checkpoint
    case pulseGate, springPad, longGap

    var isHazard: Bool {
        switch self {
        case .gap, .barrier, .overhead, .pulseGate, .longGap: return true
        default: return false
        }
    }
}

struct RunnerFeature: Identifiable, Codable, Equatable {
    let id: String
    let kind: RunnerFeatureKind
    let at: Double
    let length: Double
    var resolved = false
    var failed = false
    var exposure = 0.0
    var heldTime = 0.0
    var end: Double { at + length }
}

struct RunnerCourse: Identifiable {
    let id: Int
    let worldNumber: Int
    let stageNumber: Int
    let name: String
    let world: String
    let description: String
    let speed: Double
    let length: Double
    let starTarget: Int
    let lineTarget: Int
    let features: [RunnerFeature]

    static let worldNames = ["NEIGHBORHOOD", "CONCRETE", "NEON", "CLOUDS", "IMPOSSIBLE LINE"]

    static let playOrder: [Int] = (1...5).flatMap { world in
        [id(world: world, stage: 1), id(world: world, stage: 2),
         id(world: world, stage: 3)]
    }

    /// First-stage IDs were published in beta 11. Expansion stages start at 6.
    static func id(world: Int, stage: Int) -> Int {
        stage == 1 ? world : 6 + (world - 1) * 2 + (stage - 2)
    }

    static let catalog = (1...5).flatMap { world in
        (1...3).map { stage in make(world: world, stage: stage) }
    }

    static func get(_ id: Int) -> RunnerCourse {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    static func next(after id: Int) -> RunnerCourse? {
        guard let at = playOrder.firstIndex(of: id),
              at + 1 < playOrder.count else { return nil }
        return get(playOrder[at + 1])
    }

    private static func make(world: Int, stage: Int) -> RunnerCourse {
        let names: [[String]] = [
            ["First Light", "Back Alley Balance", "Neighborhood Jam"],
            ["Concrete Dreams", "Ledge Control", "Parking Garage"],
            ["Neon Transit", "Pulse Check", "Last Train"],
            ["Skyline Transfer", "Cloud Nine", "Above the Block"],
            ["The Impossible Line", "Perfect Timing", "Endless Lights"]
        ]
        let descriptions: [[String]] = [
            ["Find your feet. Pop, duck, and roll.", "Longer manuals, tighter lines.", "Put every move together."],
            ["Learn the rhythm of the city.", "Balance is everything.", "Obstacles come fast in concrete."],
            ["Dodge your first neon pulse gates.", "Ride to the flashing rhythm.", "Time the final transit line."],
            ["Use launch ramps to fly over chasms.", "Connect jumps high above the city.", "Perfect the long-distance transfer."],
            ["The full street-skating vocabulary.", "Nail every switch in the sequence.", "Your ultimate no-bail run."]
        ]
        let rounds = stage == 1 ? (world == 1 ? 5 : 7) : (stage == 2 ? 8 : (world == 5 ? 12 : 10))
        let speed = 4.35 + Double(world - 1) * 0.22 + Double(stage - 1) * 0.10
        let courseID = id(world: world, stage: stage)
        var features: [RunnerFeature] = []

        func add(_ kind: RunnerFeatureKind, at: Double, length: Double,
                 section: Int, slot: Int) {
            features.append(RunnerFeature(id: "c\(courseID)s\(section)i\(slot)",
                                          kind: kind, at: at, length: length))
        }

        // Four handcrafted motifs with optional world-specific variations.
        // No random obstacle placement: patterns have measurable input windows.
        // Each 64-unit section has at least 10 units between timed actions.
        let motifs: [[(Double, RunnerFeatureKind, Double)]] = [
            [(5, .gap, 1.5), (18, .barrier, 1), (32, .overhead, 1.7),
             (46, .manualLine, 4.0)],
            [(5, .noseLine, 4.2), (20, .overhead, 1.7),
             (35, .gap, 1.8), (49, .barrier, 1)],
            [(6, .barrier, 1), (20, .manualLine, 4.0),
             (34, .gap, 1.7), (49, .overhead, 1.7)],
            [(5, .gap, 1.7), (19, .noseLine, 4.0),
             (34, .overhead, 1.5), (49, .barrier, 1)]
        ]

        for section in 0..<rounds {
            let origin = 27.0 + Double(section) * 64
            var motif = motifs[(section + stage + world - 2) % motifs.count]
            if world >= 3 {
                // Pulse gates open on the beat; ducking works regardless.
                motif = motif.map { offset, kind, length in
                    (offset, kind == .overhead ? .pulseGate : kind, length)
                }
            }
            if world >= 4 && section.isMultiple(of: 2) {
                // Two new linked mechanics. A launch pad automatically throws
                // you over a chasm too long for a standard manual pop.
                motif = [(5, .noseLine, 4.2), (20.5, .springPad, 1.2),
                         (23.2, .longGap, 3.4), (49, .manualLine, 4)]
            }

            for (slot, pattern) in motif.enumerated() {
                add(pattern.1, at: origin + pattern.0,
                    length: pattern.2, section: section, slot: slot)
            }
            add(.pickup, at: origin + 12, length: 0.85, section: section, slot: 4)
            add(.pickup, at: origin + 29, length: 0.85, section: section, slot: 5)
            add(.pickup, at: origin + 57, length: 0.85, section: section, slot: 6)
            if section == rounds / 2 - 1 {
                add(.checkpoint, at: origin + 61, length: 0.3, section: section, slot: 7)
            }
        }
        features.sort { $0.at < $1.at }
        return RunnerCourse(id: courseID, worldNumber: world, stageNumber: stage,
                            name: names[world - 1][stage - 1],
                            world: worldNames[world - 1],
                            description: descriptions[world - 1][stage - 1],
                            speed: speed,
                            length: 27 + Double(rounds) * 64 + 15,
                            starTarget: rounds * 2,
                            lineTarget: max(2, rounds / 3),
                            features: features)
    }
}
