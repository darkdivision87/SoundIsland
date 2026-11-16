import Foundation
import Observation
import AudioCore
import Curriculum
import GameKitCore
import StudioModel
import ProfileStore
import SwiftData

/// Games that exist as code. Everything else on an island shows as "coming soon".
enum GameID: String, Hashable, CaseIterable {
    case crabTap = "crab_tap"
    case waveRider = "wave_rider"
    case drumCircle = "drum_circle"
    case birdSong = "bird_song"
    case pitchClimb = "pitch_climb"
    case keyHunt = "key_hunt"
    case echoMonkeys = "echo_monkeys"
    case vineSwing = "vine_swing"
    case melodyPaint = "melody_paint"
    case chordChef = "chord_chef"
    case moodBoats = "mood_boats"
    case stackAttack = "stack_attack"

    var displayName: String {
        switch self {
        case .crabTap: "Crab Tap"
        case .waveRider: "Wave Rider"
        case .drumCircle: "Drum Circle"
        case .birdSong: "Bird Song"
        case .pitchClimb: "Pitch Climb"
        case .keyHunt: "Key Hunt"
        case .echoMonkeys: "Echo Monkeys"
        case .vineSwing: "Vine Swing"
        case .melodyPaint: "Melody Paint"
        case .chordChef: "Chord Chef"
        case .moodBoats: "Mood Boats"
        case .stackAttack: "Stack Attack"
        }
    }

    /// Playable so far: Crab Tap, Wave Rider, Chord Chef.
    var isPlayable: Bool { self == .crabTap || self == .waveRider || self == .chordChef }

    var island: IslandID {
        switch self {
        case .crabTap, .waveRider, .drumCircle: .beatBeach
        case .birdSong, .pitchClimb, .keyHunt: .pitchPeaks
        case .echoMonkeys, .vineSwing, .melodyPaint: .melodyJungle
        case .chordChef, .moodBoats, .stackAttack: .harmonyHarbor
        }
    }

    static func games(on island: IslandID) -> [GameID] { allCases.filter { $0.island == island } }
}

struct RewardInfo: Hashable {
    let game: GameID
    let stars: Int
    let accuracy: Double
    let unlockedTool: StudioTool?
}

enum Route: Hashable {
    case island(IslandID)
    case game(GameID)
    case studio
    case reward(RewardInfo)
    case parentArea
    case latencyRig
}

/// What the profile picker and parent area need to show a child, without touching SwiftData objects.
struct ProfileSummary: Identifiable, Hashable {
    let id: UUID
    let nickname: String
    let avatar: String
    let ageBand: AgeBand
}

@MainActor
@Observable
final class AppModel {
    var path: [Route] = []
    var profile = ProfileSnapshot()
    private(set) var content: CurriculumContent?
    let audio = AudioEngine.shared
    let narrator = Narrator()

    /// Up to 4 children (spec section 9). `profile` is the active child's working copy; `save()` writes it back.
    private let store: ProfileStore
    private var activeRecord: ChildProfile
    private(set) var profiles: [ProfileSummary] = []
    var activeProfileID: UUID { activeRecord.id }
    /// Kid-facing "Who's playing?" screen. Shown at launch when more than one child shares the iPad.
    var showProfilePicker = false

    private static let activeProfileKey = "activeProfileID"

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let container: ModelContainer
        do {
            container = try ProfileStore.makeContainer(storeURL: dir.appendingPathComponent("Profiles.store"))
        } catch {
            // Never strand a child on a launch error: run with an in-memory store and say so in debug builds.
            assertionFailure("Profile store failed to open: \(error)")
            container = try! ProfileStore.makeContainer(inMemory: true)
        }
        let store = ProfileStore(container: container)
        let record: ChildProfile
        do {
            try store.migrateLegacyJSON(at: dir.appendingPathComponent("profile.json"))
            let saved = UserDefaults.standard.string(forKey: Self.activeProfileKey).flatMap(UUID.init(uuidString:))
            record = try saved.flatMap { try store.profile(id: $0) } ?? store.ensureProfile()
        } catch {
            fatalError("Profile store unusable: \(error)")
        }
        self.store = store
        activeRecord = record
        profile = store.snapshot(of: record)

        loadContent()
        refreshProfiles()
        showProfilePicker = profiles.count > 1
        profile.sessionIndex += 1
        save()
        audio.calibrationOffset = UserDefaults.standard.double(forKey: Self.calibrationKey)
        do { try audio.start() } catch { print("Audio failed to start: \(error)") }
        audio.setQuietMode(profile.quietMode)
        narrator.quiet = profile.quietMode
        pushSongToAudio()
    }

    // MARK: Audio calibration

    /// Per device, not per child: the latency belongs to this iPad and its speaker, so it lives in
    /// UserDefaults rather than the child profile. Never leaves the device.
    private static let calibrationKey = "audioCalibrationOffset"

    func setCalibrationOffset(_ seconds: Double) {
        audio.calibrationOffset = seconds
        UserDefaults.standard.set(seconds, forKey: Self.calibrationKey)
    }

    // MARK: Content and progress

    private func loadContent() {
        guard let url = Bundle.main.url(forResource: "skills", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("skills.json missing from bundle")
            return
        }
        do { content = try CurriculumContent.decode(data) } catch { assertionFailure("Bad curriculum: \(error)") }
    }

    /// A game can teach several skill nodes in order (Wave Rider: quarter notes, then eighth notes).
    /// The current one is the first the child hasn't mastered; once all are mastered, keep the last.
    func skill(for game: GameID) -> SkillNode? {
        let nodes = content?.skills(forGame: game.rawValue) ?? []
        return nodes.first { profile.progress[$0.skillNode]?.isMastered != true } ?? nodes.last
    }

    func tier(for game: GameID) -> Int {
        guard let s = skill(for: game) else { return 1 }
        return profile.progress[s.skillNode]?.currentTier ?? 1
    }

    func isUnlocked(_ island: IslandID) -> Bool {
        guard island.isMVP else { return false }
        guard let content else { return island == .beatBeach }
        return IslandUnlock.isUnlocked(island, content: content, progress: profile.progress, unlockAll: profile.unlockAll)
    }

    func stars(on island: IslandID) -> Int {
        let games = GameID.games(on: island)
        guard !games.isEmpty else { return 0 }
        let total = games.map { profile.bestStars[$0.rawValue] ?? 0 }.reduce(0, +)
        return Int((Double(total) / Double(games.count)).rounded())
    }

    var totalStars: Int { profile.bestStars.values.reduce(0, +) }

    /// Called by a game when its last round ends. Updates adaptive tier, mastery, stars and unlocks.
    func finishGame(_ game: GameID, results: [Bool]) -> RewardInfo {
        let accuracy = results.isEmpty ? 0 : Double(results.filter { $0 }.count) / Double(results.count)
        let stars = Stars.forAccuracy(accuracy)
        profile.bestStars[game.rawValue] = max(profile.bestStars[game.rawValue] ?? 0, stars)

        var unlocked: StudioTool?
        if let s = skill(for: game) {
            var p = profile.progress[s.skillNode] ?? SkillProgress(skillID: s.skillNode)
            let adaptive = AdaptiveDifficulty(maxTier: s.tiers.count)
            for r in results { adaptive.record(correct: r, into: &p) }
            MasteryEvaluator.endSession(results, rule: s.mastery, sessionIndex: profile.sessionIndex, progress: &p)
            profile.progress[s.skillNode] = p
            // Finishing a tool's game with 2+ stars unlocks the tool right away, so every session makes something.
            if let tool = StudioTool.unlockedBy(s.studioContribution), stars >= 2, !profile.unlockedTools.contains(tool) {
                profile.unlockedTools.insert(tool)
                unlocked = tool
            }
        }
        save()
        return RewardInfo(game: game, stars: stars, accuracy: accuracy, unlockedTool: unlocked)
    }

    // MARK: Studio

    var beatGrid: BeatGrid {
        get { profile.song.sections[selectedSection].tracks.first { $0.kind == .beats }?.beatGrid ?? .empty }
        set {
            guard let i = profile.song.sections[selectedSection].tracks.firstIndex(where: { $0.kind == .beats }) else { return }
            profile.song.sections[selectedSection].tracks[i].beatGrid = newValue
            profile.song.updatedAt = Date()
            pushSongToAudio()
            save()
        }
    }

    private(set) var selectedSection = 0

    func selectSection(_ index: Int) {
        guard profile.song.sections.indices.contains(index) else { return }
        selectedSection = index
        pushSongToAudio()
    }

    func pushSongToAudio() {
        let g = beatGrid
        audio.send(.setDrumPattern(DrumMasks(kick: g.kick, snare: g.snare, hat: g.hat, clap: g.clap)))
        audio.send(.setTempo(profile.song.tempo))
        audio.send(.setKit(UInt8(DrumKit.allCases.firstIndex(of: profile.song.kit) ?? 0)))
    }

    func setKit(_ kit: DrumKit) {
        profile.song.kit = kit
        pushSongToAudio()
        save()
    }

    func setTempo(_ bpm: Double) {
        profile.song.setTempo(bpm)
        audio.send(.setTempo(profile.song.tempo))
        save()
    }

    // MARK: Parent settings

    func setQuietMode(_ on: Bool) {
        profile.quietMode = on
        audio.setQuietMode(on)
        narrator.quiet = on
        save()
    }

    // MARK: Profiles

    var canAddProfile: Bool { profiles.count < ProfileStore.maxProfiles }

    func switchProfile(to id: UUID) {
        guard id != activeRecord.id else { showProfilePicker = false; return }
        save()
        guard let record = try? store.profile(id: id) else { return }
        activeRecord = record
        profile = store.snapshot(of: record)
        profile.sessionIndex += 1
        selectedSection = 0
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
        audio.send(.stop)
        audio.setQuietMode(profile.quietMode)
        narrator.quiet = profile.quietMode
        pushSongToAudio()
        save()
        showProfilePicker = false
    }

    func addProfile(nickname: String, avatar: String, ageBand: AgeBand) {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? store.addProfile(ProfileSnapshot(nickname: name.isEmpty ? "Player \(profiles.count + 1)" : name,
                                                  avatar: avatar, ageBand: ageBand))
        refreshProfiles()
    }

    /// Parent area only. Deleting the active child switches to the first remaining one.
    func deleteProfile(id: UUID) {
        guard profiles.count > 1, let record = try? store.profile(id: id) else { return }
        if id == activeRecord.id, let other = profiles.first(where: { $0.id != id }) { switchProfile(to: other.id) }
        try? store.delete(record)
        refreshProfiles()
    }

    private func refreshProfiles() {
        profiles = ((try? store.allProfiles()) ?? []).map {
            ProfileSummary(id: $0.id, nickname: $0.nickname, avatar: $0.avatar, ageBand: AgeBand(rawValue: $0.ageBandRaw) ?? .explorers)
        }
    }

    // MARK: Persistence

    func save() {
        do {
            try store.write(profile, to: activeRecord)
        } catch {
            assertionFailure("Profile save failed: \(error)")
        }
        refreshProfiles()
    }
}
