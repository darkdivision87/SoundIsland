import Foundation
import Observation
import AudioCore
import Curriculum
import GameKitCore
import StudioModel

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

    /// Phase 1 vertical slice: Crab Tap + Chord Chef (spec section 14).
    var isPlayable: Bool { self == .crabTap || self == .chordChef }

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

enum StudioTool: String, Codable, CaseIterable {
    case beatBox, keys, melodyMaker, chordPads

    var displayName: String {
        switch self {
        case .beatBox: "Beat Box"
        case .keys: "Keys"
        case .melodyMaker: "Melody Maker"
        case .chordPads: "Chord Pads"
        }
    }

    /// studioContribution ids in skills.json that unlock each tool.
    static func unlockedBy(_ contribution: String?) -> StudioTool? {
        switch contribution {
        case "beat_box.unlock": .beatBox
        case "keys.unlock": .keys
        case "melody_maker.unlock": .melodyMaker
        case "chord_pads.unlock": .chordPads
        default: nil
        }
    }
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
}

/// Everything persisted for one child profile. Phase 1 stores JSON in Application Support;
/// moving to SwiftData (spec section 9) is a tracked task in CLAUDE.md.
struct ProfileSnapshot: Codable {
    var nickname: String = "Player 1"
    var avatar: String = "fox"
    var ageBand: AgeBand = .explorers
    var sessionIndex: Int = 0
    var progress: [String: SkillProgress] = [:]
    var bestStars: [String: Int] = [:]
    var unlockedTools: Set<StudioTool> = []
    var song = Song()
    var quietMode = false
    var unlockAll = false
}

@MainActor
@Observable
final class AppModel {
    var path: [Route] = []
    var profile = ProfileSnapshot()
    private(set) var content: CurriculumContent?
    let audio = AudioEngine.shared

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }()

    init() {
        loadContent()
        load()
        profile.sessionIndex += 1
        save()
        do { try audio.start() } catch { print("Audio failed to start: \(error)") }
        audio.setQuietMode(profile.quietMode)
        pushSongToAudio()
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

    func skill(for game: GameID) -> SkillNode? { content?.skills(forGame: game.rawValue).first }

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
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let snap = try? JSONDecoder().decode(ProfileSnapshot.self, from: data) else { return }
        profile = snap
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: saveURL, options: [.atomic, .completeFileProtection])
    }
}
