// StudioModel: the song a child builds. Value types only; the app persists them with SwiftData
// (as encoded JSON) and AudioCore plays snapshots of them.

import Foundation
import MusicTheory

public let ticksPerQuarter = 96

// MARK: - Beat Box

public enum DrumRow: Int, CaseIterable, Sendable, Codable {
    case kick = 0, snare, hat, clap

    public var displayName: String {
        switch self {
        case .kick: "Kick"
        case .snare: "Snare"
        case .hat: "Hi-hat"
        case .clap: "Clap"
        }
    }
}

public enum DrumKit: String, CaseIterable, Sendable, Codable {
    case pop, hipHop, electronic, rock, silly, world

    public var displayName: String {
        switch self {
        case .pop: "Pop"
        case .hipHop: "Hip-hop"
        case .electronic: "Electronic"
        case .rock: "Rock"
        case .silly: "Silly"
        case .world: "World"
        }
    }
}

/// 4 rows x 16 sixteenth-note steps, stored as one bitmask per row.
/// A trivial (POD) type on purpose: it can be sent to the audio thread without ARC or allocation.
public struct BeatGrid: Hashable, Sendable, Codable {
    public static let steps = 16
    public var kick: UInt16
    public var snare: UInt16
    public var hat: UInt16
    public var clap: UInt16

    public init(kick: UInt16 = 0, snare: UInt16 = 0, hat: UInt16 = 0, clap: UInt16 = 0) {
        self.kick = kick
        self.snare = snare
        self.hat = hat
        self.clap = clap
    }

    public static let empty = BeatGrid()

    /// The default groove shown on the Studio design: four-on-the-floor-ish pop beat.
    public static let starter = BeatGrid(
        kick: mask([0, 6, 8, 10]),
        snare: mask([4, 12]),
        hat: mask([0, 2, 4, 6, 8, 10, 12, 14]),
        clap: mask([12, 14])
    )

    public static func mask(_ steps: [Int]) -> UInt16 {
        steps.reduce(UInt16(0)) { $0 | (1 << UInt16($1)) }
    }

    public func row(_ r: DrumRow) -> UInt16 {
        switch r {
        case .kick: kick
        case .snare: snare
        case .hat: hat
        case .clap: clap
        }
    }

    public func isOn(_ r: DrumRow, step: Int) -> Bool { row(r) & (1 << UInt16(step)) != 0 }

    public mutating func toggle(_ r: DrumRow, step: Int) {
        let bit: UInt16 = 1 << UInt16(step)
        switch r {
        case .kick: kick ^= bit
        case .snare: snare ^= bit
        case .hat: hat ^= bit
        case .clap: clap ^= bit
        }
    }

    public var isEmpty: Bool { kick | snare | hat | clap == 0 }

    /// "Surprise me": always musical. Kick on 1 and 3 plus extras, backbeat snare, steady hats.
    public static func surprise<G: RandomNumberGenerator>(using rng: inout G) -> BeatGrid {
        var g = BeatGrid()
        for step in 0..<steps {
            let r1 = Double(rng.next() % 1000) / 1000
            let r2 = Double(rng.next() % 1000) / 1000
            let r3 = Double(rng.next() % 1000) / 1000
            if step % 8 == 0 || r1 < 0.15 { g.toggle(.kick, step: step) }
            if step == 4 || step == 12 { g.toggle(.snare, step: step) }
            if step % 2 == 0 || r2 < 0.2 { g.toggle(.hat, step: step) }
            if step == 12 || (step > 12 && r3 < 0.25) { g.toggle(.clap, step: step) }
        }
        return g
    }
}

// MARK: - Notes and patterns

public struct NoteEvent: Hashable, Sendable, Codable {
    public var tick: Int
    public var pitch: Pitch
    public var lengthTicks: Int
    public var velocity: Float

    public init(tick: Int, pitch: Pitch, lengthTicks: Int, velocity: Float = 0.8) {
        self.tick = tick
        self.pitch = pitch
        self.lengthTicks = lengthTicks
        self.velocity = velocity
    }
}

public enum TrackKind: String, CaseIterable, Sendable, Codable {
    case beats, bass, chords, melody

    public var displayName: String { rawValue.capitalized }
}

public struct Track: Hashable, Sendable, Codable, Identifiable {
    public var id = UUID()
    public var kind: TrackKind
    public var instrumentID: String
    public var volume: Float = 0.8
    public var pan: Float = 0
    public var muted = false
    /// Used when kind == .beats.
    public var beatGrid: BeatGrid = .empty
    /// Used by bass, chords and melody tracks.
    public var notes: [NoteEvent] = []

    public init(kind: TrackKind, instrumentID: String) {
        self.kind = kind
        self.instrumentID = instrumentID
    }
}

public struct Section: Hashable, Sendable, Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var bars: Int
    public var tracks: [Track]

    public init(name: String, bars: Int = 4, tracks: [Track]) {
        self.name = name
        self.bars = bars
        self.tracks = tracks
    }

    public static func blank(named name: String) -> Section {
        var beats = Track(kind: .beats, instrumentID: DrumKit.pop.rawValue)
        beats.beatGrid = .starter
        return Section(name: name, tracks: [
            beats,
            Track(kind: .bass, instrumentID: "bass_buddy"),
            Track(kind: .chords, instrumentID: "piano"),
            Track(kind: .melody, instrumentID: "marimba"),
        ])
    }
}

public struct Song: Hashable, Sendable, Codable, Identifiable {
    public static let maxSectionsMVP = 4
    public static let tempoRange: ClosedRange<Double> = 70...130

    public var id = UUID()
    public var title: String
    public var tempo: Double
    public var key: Key
    public var swing: Bool
    public var kit: DrumKit
    public var sections: [Section]
    /// Arrangement as indices into `sections` ("A B A").
    public var arrangement: [Int]
    public var updatedAt: Date

    public init(title: String = "My Song", tempo: Double = 96, key: Key = .sunnyC) {
        self.title = title
        self.tempo = tempo
        self.key = key
        self.swing = false
        self.kit = .pop
        self.sections = [.blank(named: "A")]
        self.arrangement = [0]
        self.updatedAt = Date()
    }

    public mutating func setTempo(_ bpm: Double) {
        tempo = min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
    }

    @discardableResult
    public mutating func addSection() -> Bool {
        guard sections.count < Self.maxSectionsMVP else { return false }
        let name = String(UnicodeScalar(UInt8(65 + sections.count)))
        sections.append(.blank(named: name))
        arrangement.append(sections.count - 1)
        return true
    }

    /// Word-bank titles so kids never type free text (privacy + pre-readers).
    public static let titleWordBank = (
        first: ["Happy", "Sleepy", "Bouncy", "Sparkly", "Stompy", "Wiggly", "Sunny", "Moonlit"],
        second: ["Crab", "Volcano", "Rocket", "Dragon", "Banana", "Robot", "Monkey", "Wave"],
        third: ["Dance", "Song", "Party", "Groove", "Parade", "Jam", "March", "Lullaby"]
    )
}
