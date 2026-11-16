// Curriculum: skill graph content, mastery, adaptive tiers and spaced repetition.
// Content is authored as JSON (App/Resources/Content/skills.json) and decoded into these types.

import Foundation

// MARK: - Age bands

/// Target audience is ages 6 to 10 (App Store Kids band: 6-8).
public enum AgeBand: String, CaseIterable, Sendable, Codable {
    case explorers, makers

    public var ages: ClosedRange<Int> {
        switch self {
        case .explorers: 6...7
        case .makers: 8...10
        }
    }

    /// Minimum touch target in points (spec section 6).
    public var minTouchTarget: Double { self == .explorers ? 64 : 52 }

    /// Max interactive elements on screen (spec section 6). A Studio grid counts as one.
    public var maxInteractiveElements: Int { self == .explorers ? 7 : 9 }

    /// Max answer choices per round (spec section 2).
    public var maxChoices: Int { self == .explorers ? 4 : 7 }

    /// Explorers get the 8-step Studio grid, Makers the 16-step grid.
    public var studioSteps: Int { self == .explorers ? 8 : 16 }

    public static func forAge(_ age: Int) -> AgeBand { age <= 7 ? .explorers : .makers }
}

// MARK: - Content

public enum IslandID: String, CaseIterable, Sendable, Codable {
    case beatBeach = "beat_beach"
    case pitchPeaks = "pitch_peaks"
    case melodyJungle = "melody_jungle"
    case harmonyHarbor = "harmony_harbor"
    case bassCaves = "bass_caves"
    case songVolcano = "song_volcano"
    case mixLab = "mix_lab"

    public var displayName: String {
        switch self {
        case .beatBeach: "Beat Beach"
        case .pitchPeaks: "Pitch Peaks"
        case .melodyJungle: "Melody Jungle"
        case .harmonyHarbor: "Harmony Harbor"
        case .bassCaves: "Bass Caves"
        case .songVolcano: "Song Volcano"
        case .mixLab: "Mix Lab"
        }
    }

    /// Islands 1 to 4 ship in the MVP.
    public var isMVP: Bool { [.beatBeach, .pitchPeaks, .melodyJungle, .harmonyHarbor].contains(self) }

    public var order: Int { IslandID.allCases.firstIndex(of: self)! }
}

/// Tier parameters are game-specific, so they are kept as a loose dictionary and read by each game.
public struct TierSpec: Sendable, Codable, Hashable {
    public let tier: Int
    public let params: [String: TierValue]

    public init(tier: Int, params: [String: TierValue]) {
        self.tier = tier
        self.params = params
    }

    public func int(_ key: String, default value: Int) -> Int {
        if case .int(let v)? = params[key] { return v }
        if case .double(let v)? = params[key] { return Int(v) }
        return value
    }

    public func double(_ key: String, default value: Double) -> Double {
        if case .double(let v)? = params[key] { return v }
        if case .int(let v)? = params[key] { return Double(v) }
        return value
    }

    public func bool(_ key: String, default value: Bool) -> Bool {
        if case .bool(let v)? = params[key] { return v }
        return value
    }

    public func string(_ key: String, default value: String) -> String {
        if case .string(let v)? = params[key] { return v }
        return value
    }

    public func strings(_ key: String) -> [String] {
        if case .strings(let v)? = params[key] { return v }
        return []
    }

    // JSON shape: {"tier": 1, "bpm": 72, "bars": 1, "values": ["q","8"], "notation": false}
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var tier = 1
        var params: [String: TierValue] = [:]
        for key in c.allKeys {
            if key.stringValue == "tier" { tier = try c.decode(Int.self, forKey: key); continue }
            params[key.stringValue] = try c.decode(TierValue.self, forKey: key)
        }
        self.tier = tier
        self.params = params
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(tier, forKey: AnyKey(stringValue: "tier"))
        for (k, v) in params { try c.encode(v, forKey: AnyKey(stringValue: k)) }
    }
}

public enum TierValue: Sendable, Codable, Hashable {
    case int(Int), double(Double), bool(Bool), string(String), strings([String])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        self = .strings(try c.decode([String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .strings(let v): try c.encode(v)
        }
    }
}

public struct MasteryRule: Sendable, Codable, Hashable {
    /// e.g. [4, 5] = 4 correct of the last 5 rounds.
    public let correctOf: [Int]
    /// Must be met in this many separate sessions.
    public let sessions: Int

    public var required: Int { correctOf.first ?? 4 }
    public var window: Int { correctOf.count > 1 ? correctOf[1] : 5 }
}

public struct SkillNode: Sendable, Codable, Hashable, Identifiable {
    public let skillNode: String
    public let island: IslandID
    public let concept: String
    public let ageBands: [AgeBand]
    public let prereqs: [String]
    public let game: String
    public let tiers: [TierSpec]
    public let mastery: MasteryRule
    public let studioContribution: String?

    public var id: String { skillNode }

    public func tier(_ n: Int) -> TierSpec {
        tiers.first { $0.tier == n } ?? tiers.first ?? TierSpec(tier: 1, params: [:])
    }
}

public struct CurriculumContent: Sendable, Codable {
    public let schemaVersion: Int
    public let skills: [SkillNode]

    public static let supportedSchemaVersion = 1

    public static func decode(_ data: Data) throws -> CurriculumContent {
        let content = try JSONDecoder().decode(CurriculumContent.self, from: data)
        guard content.schemaVersion == supportedSchemaVersion else {
            throw CurriculumError.unsupportedSchema(content.schemaVersion)
        }
        try content.validate()
        return content
    }

    public func skills(on island: IslandID) -> [SkillNode] { skills.filter { $0.island == island } }
    public func skill(_ id: String) -> SkillNode? { skills.first { $0.skillNode == id } }
    public func skills(forGame game: String) -> [SkillNode] { skills.filter { $0.game == game } }

    /// Every prereq must exist and the graph must have no cycles.
    public func validate() throws {
        let ids = Set(skills.map(\.skillNode))
        for s in skills {
            for p in s.prereqs where !ids.contains(p) { throw CurriculumError.missingPrereq(s.skillNode, p) }
            if s.tiers.isEmpty { throw CurriculumError.noTiers(s.skillNode) }
        }
        var visiting = Set<String>(), done = Set<String>()
        let byID = Dictionary(uniqueKeysWithValues: skills.map { ($0.skillNode, $0) })
        func visit(_ id: String) throws {
            if done.contains(id) { return }
            if visiting.contains(id) { throw CurriculumError.cycle(id) }
            visiting.insert(id)
            for p in byID[id]?.prereqs ?? [] { try visit(p) }
            visiting.remove(id)
            done.insert(id)
        }
        for id in ids { try visit(id) }
    }
}

public enum CurriculumError: Error, Equatable {
    case unsupportedSchema(Int)
    case missingPrereq(String, String)
    case noTiers(String)
    case cycle(String)
}

// MARK: - Progress, adaptive tiers, spaced repetition

/// Per-child, per-skill progress. Persisted by the app (SwiftData), computed here.
public struct SkillProgress: Sendable, Codable, Hashable {
    public var skillID: String
    public var currentTier: Int = 1
    /// Most recent round outcomes, newest last, capped at `AdaptiveDifficulty.window`.
    public var recentResults: [Bool] = []
    public var consecutiveLowRounds: Int = 0
    public var attempts: Int = 0
    public var correct: Int = 0
    /// Sessions in which the mastery rule was met.
    public var masteredSessions: Int = 0
    /// Session index of first mastery, nil until mastered.
    public var firstMasteredSession: Int?
    public var reviewsDone: Int = 0

    public init(skillID: String) { self.skillID = skillID }

    public var masteryScore: Double {
        recentResults.isEmpty ? 0 : Double(recentResults.filter { $0 }.count) / Double(recentResults.count)
    }

    public var isMastered: Bool { firstMasteredSession != nil }
}

public enum TierChange: Equatable, Sendable { case up, down, stay }

/// Spec section 10: rolling accuracy over the last 10 rounds.
/// Above 85% step up. Below 55% for 3 rounds step down and add a hint. Tier 1 is the floor.
public struct AdaptiveDifficulty: Sendable {
    public static let window = 10
    public static let upThreshold = 0.85
    public static let downThreshold = 0.55
    public static let roundsBelowToStepDown = 3
    public static let minRoundsBeforeStepUp = 5
    public let maxTier: Int

    public init(maxTier: Int = 3) { self.maxTier = maxTier }

    /// Record one round and return the tier decision for the next round.
    @discardableResult
    public func record(correct: Bool, into p: inout SkillProgress) -> (change: TierChange, addHint: Bool) {
        p.attempts += 1
        if correct { p.correct += 1 }
        p.recentResults.append(correct)
        if p.recentResults.count > Self.window { p.recentResults.removeFirst(p.recentResults.count - Self.window) }

        let accuracy = p.masteryScore
        if accuracy < Self.downThreshold { p.consecutiveLowRounds += 1 } else { p.consecutiveLowRounds = 0 }

        if p.recentResults.count >= Self.minRoundsBeforeStepUp, accuracy > Self.upThreshold, p.currentTier < maxTier {
            p.currentTier += 1
            p.recentResults.removeAll()
            p.consecutiveLowRounds = 0
            return (.up, false)
        }
        if p.consecutiveLowRounds >= Self.roundsBelowToStepDown {
            p.consecutiveLowRounds = 0
            if p.currentTier > 1 {
                p.currentTier -= 1
                p.recentResults.removeAll()
                return (.down, true)
            }
            return (.stay, true)
        }
        return (.stay, false)
    }
}

/// Mastery: the node's rule must be met in `rule.sessions` separate sessions.
public enum MasteryEvaluator {
    /// Call once at the end of a session with that session's results for the skill.
    public static func endSession(_ results: [Bool], rule: MasteryRule, sessionIndex: Int, progress p: inout SkillProgress) {
        let window = results.suffix(rule.window)
        if window.count >= rule.window, window.filter({ $0 }).count >= rule.required {
            p.masteredSessions += 1
            if p.masteredSessions >= rule.sessions, p.firstMasteredSession == nil {
                p.firstMasteredSession = sessionIndex
            }
        }
    }
}

/// Spec: resurface a mastered skill 1, 3 and 7 sessions after first mastery.
public enum SpacedRepetition {
    public static let offsets = [1, 3, 7]

    public static func isDueForReview(_ p: SkillProgress, currentSession: Int) -> Bool {
        guard let first = p.firstMasteredSession, p.reviewsDone < offsets.count else { return false }
        return currentSession >= first + offsets[p.reviewsDone]
    }

    /// Pick one review skill for this game session: the most overdue one, if any.
    public static func pickReview(from all: [SkillProgress], currentSession: Int) -> SkillProgress? {
        all.filter { isDueForReview($0, currentSession: currentSession) }
            .min { lhs, rhs in
                (lhs.firstMasteredSession! + offsets[lhs.reviewsDone]) < (rhs.firstMasteredSession! + offsets[rhs.reviewsDone])
            }
    }
}

/// Spec: an island unlocks at 70% average mastery of the previous island's skills.
public enum IslandUnlock {
    public static let threshold = 0.70

    public static func isUnlocked(_ island: IslandID, content: CurriculumContent, progress: [String: SkillProgress], unlockAll: Bool = false) -> Bool {
        if unlockAll || island.order == 0 { return true }
        let previous = IslandID.allCases[island.order - 1]
        let skills = content.skills(on: previous)
        guard !skills.isEmpty else { return true }
        let avg = skills.map { s -> Double in
            guard let p = progress[s.skillNode] else { return 0 }
            return p.isMastered ? 1 : p.masteryScore
        }.reduce(0, +) / Double(skills.count)
        return avg >= threshold
    }
}
