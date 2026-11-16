// ProfileStore: up to 4 child profiles in SwiftData (spec section 9).
// Everything stays on the device. AppModel works on a `ProfileSnapshot` value and writes it back here,
// so views never touch SwiftData objects directly.

import Foundation
import SwiftData
import Curriculum
import StudioModel

// MARK: - Snapshot (working copy + phase 1 JSON format, kept as the migration source)

/// Everything persisted for one child. Also the exact shape of phase 1's `profile.json`,
/// so `ProfileStore.migrateLegacyJSON` can decode old installs.
public struct ProfileSnapshot: Codable, Sendable, Equatable {
    public var nickname: String = "Player 1"
    public var avatar: String = "fox"
    public var ageBand: AgeBand = .explorers
    public var sessionIndex: Int = 0
    public var progress: [String: SkillProgress] = [:]
    public var bestStars: [String: Int] = [:]
    public var unlockedTools: Set<StudioTool> = []
    public var song = Song()
    public var quietMode = false
    public var unlockAll = false

    public init(nickname: String = "Player 1", avatar: String = "fox", ageBand: AgeBand = .explorers) {
        self.nickname = nickname
        self.avatar = avatar
        self.ageBand = ageBand
    }
}

// MARK: - SwiftData models

@Model
public final class ChildProfile {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var nickname: String
    public var avatar: String
    public var ageBandRaw: String
    public var sessionIndex: Int
    public var quietMode: Bool
    public var unlockAll: Bool
    public var unlockedToolsRaw: [String]
    /// [gameID: best stars], JSON. Small and only ever read whole.
    public var bestStarsData: Data
    /// The child's song (StudioModel.Song), JSON. Songs are edited as one value.
    public var songData: Data
    @Relationship(deleteRule: .cascade, inverse: \SkillProgressRecord.profile)
    public var skills: [SkillProgressRecord] = []

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        nickname = ""
        avatar = "fox"
        ageBandRaw = AgeBand.explorers.rawValue
        sessionIndex = 0
        quietMode = false
        unlockAll = false
        unlockedToolsRaw = []
        bestStarsData = Data()
        songData = Data()
    }
}

/// One row per skill node per child, so progress is queryable (parent area, future reports).
@Model
public final class SkillProgressRecord {
    public var skillID: String
    public var currentTier: Int
    public var recentResults: [Bool]
    public var consecutiveLowRounds: Int
    public var attempts: Int
    public var correct: Int
    public var masteredSessions: Int
    public var firstMasteredSession: Int?
    public var reviewsDone: Int
    public var profile: ChildProfile?

    init(_ p: SkillProgress) {
        skillID = p.skillID
        currentTier = p.currentTier
        recentResults = p.recentResults
        consecutiveLowRounds = p.consecutiveLowRounds
        attempts = p.attempts
        correct = p.correct
        masteredSessions = p.masteredSessions
        firstMasteredSession = p.firstMasteredSession
        reviewsDone = p.reviewsDone
    }

    func update(from p: SkillProgress) {
        currentTier = p.currentTier
        recentResults = p.recentResults
        consecutiveLowRounds = p.consecutiveLowRounds
        attempts = p.attempts
        correct = p.correct
        masteredSessions = p.masteredSessions
        firstMasteredSession = p.firstMasteredSession
        reviewsDone = p.reviewsDone
    }

    var value: SkillProgress {
        var p = SkillProgress(skillID: skillID)
        p.currentTier = currentTier
        p.recentResults = recentResults
        p.consecutiveLowRounds = consecutiveLowRounds
        p.attempts = attempts
        p.correct = correct
        p.masteredSessions = masteredSessions
        p.firstMasteredSession = firstMasteredSession
        p.reviewsDone = reviewsDone
        return p
    }
}

// MARK: - Store

public enum ProfileStoreError: Error, Equatable {
    case tooManyProfiles
    case lastProfile
}

@MainActor
public final class ProfileStore {
    public static let maxProfiles = 4
    public let context: ModelContext

    public init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public static func makeContainer(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([ChildProfile.self, SkillProgressRecord.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL {
            config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Oldest first, so the picker order never shuffles.
    public func allProfiles() throws -> [ChildProfile] {
        try context.fetch(FetchDescriptor<ChildProfile>(sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.nickname)]))
    }

    public func profile(id: UUID) throws -> ChildProfile? {
        var d = FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    public func canAddProfile() throws -> Bool { try context.fetchCount(FetchDescriptor<ChildProfile>()) < Self.maxProfiles }

    @discardableResult
    public func addProfile(_ snapshot: ProfileSnapshot, createdAt: Date = Date()) throws -> ChildProfile {
        guard try canAddProfile() else { throw ProfileStoreError.tooManyProfiles }
        let p = ChildProfile(createdAt: createdAt)
        context.insert(p)
        try write(snapshot, to: p)
        return p
    }

    /// Deletes a child and all their progress. The last profile can't be deleted (the app always has a player).
    public func delete(_ profile: ChildProfile) throws {
        guard try context.fetchCount(FetchDescriptor<ChildProfile>()) > 1 else { throw ProfileStoreError.lastProfile }
        context.delete(profile)
        try context.save()
    }

    public func snapshot(of p: ChildProfile) -> ProfileSnapshot {
        var s = ProfileSnapshot(nickname: p.nickname, avatar: p.avatar, ageBand: AgeBand(rawValue: p.ageBandRaw) ?? .explorers)
        s.sessionIndex = p.sessionIndex
        s.quietMode = p.quietMode
        s.unlockAll = p.unlockAll
        s.unlockedTools = Set(p.unlockedToolsRaw.compactMap(StudioTool.init(rawValue:)))
        s.bestStars = (try? JSONDecoder().decode([String: Int].self, from: p.bestStarsData)) ?? [:]
        s.song = (try? JSONDecoder().decode(Song.self, from: p.songData)) ?? Song()
        s.progress = Dictionary(p.skills.map { ($0.skillID, $0.value) }, uniquingKeysWith: { a, _ in a })
        return s
    }

    /// Writes the working copy back and saves.
    public func write(_ s: ProfileSnapshot, to p: ChildProfile) throws {
        p.nickname = s.nickname
        p.avatar = s.avatar
        p.ageBandRaw = s.ageBand.rawValue
        p.sessionIndex = s.sessionIndex
        p.quietMode = s.quietMode
        p.unlockAll = s.unlockAll
        p.unlockedToolsRaw = s.unlockedTools.map(\.rawValue).sorted()
        p.bestStarsData = try JSONEncoder().encode(s.bestStars)
        p.songData = try JSONEncoder().encode(s.song)

        var existing = Dictionary(p.skills.map { ($0.skillID, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, progress) in s.progress {
            if let record = existing.removeValue(forKey: id) {
                record.update(from: progress)
            } else {
                let record = SkillProgressRecord(progress)
                context.insert(record)
                record.profile = p
            }
        }
        for stale in existing.values { context.delete(stale) }
        try context.save()
    }

    /// One-time import of phase 1's `profile.json`. Only runs into an empty store; the file is renamed
    /// (kept as a backup) so it is never imported twice. Returns the imported profile, if any.
    @discardableResult
    public func migrateLegacyJSON(at url: URL) throws -> ChildProfile? {
        guard try context.fetchCount(FetchDescriptor<ChildProfile>()) == 0,
              let data = try? Data(contentsOf: url) else { return nil }
        let snapshot = try JSONDecoder().decode(ProfileSnapshot.self, from: data)
        let profile = try addProfile(snapshot)
        let backup = url.deletingPathExtension().appendingPathExtension("migrated.json")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.moveItem(at: url, to: backup)
        return profile
    }

    /// The app always has at least one player.
    public func ensureProfile() throws -> ChildProfile {
        if let first = try allProfiles().first { return first }
        return try addProfile(ProfileSnapshot())
    }
}
