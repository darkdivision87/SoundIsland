// What the Studio plays: a section or a whole song flattened to sixteenth-note hits.
// Pure value logic so it is unit-tested; the app turns hits into AudioCore slots.

import Foundation
import MusicTheory

public let ticksPerStep = ticksPerQuarter / 4

public struct PlaybackHit: Hashable, Sendable {
    public enum Sound: Hashable, Sendable {
        case drum(DrumRow)
        case note(midi: Int, instrumentID: String)
    }
    public let step: Int
    public let track: TrackKind
    public let sound: Sound
    public let velocity: Float

    public init(step: Int, track: TrackKind, sound: Sound, velocity: Float) {
        self.step = step
        self.track = track
        self.sound = sound
        self.velocity = velocity
    }
}

public struct PlaybackLoop: Hashable, Sendable {
    public let hits: [PlaybackHit]
    public let steps: Int

    public init(hits: [PlaybackHit], steps: Int) {
        self.hits = hits
        self.steps = steps
    }
}

extension TrackKind {
    /// Gain/mute index used by the audio engine.
    public var index: Int {
        switch self {
        case .beats: 0
        case .bass: 1
        case .chords: 2
        case .melody: 3
        }
    }
}

extension Section {
    public var steps: Int { bars * 16 }

    /// The section as a loop. The beat grid repeats every bar; a note track whose content is shorter than
    /// the section repeats too (1, 2 or 4 bars), so an 8-note melody fills a 4-bar section.
    public func playback(includeBeats: Bool = true) -> PlaybackLoop {
        var hits: [PlaybackHit] = []
        for track in tracks where !track.muted {
            switch track.kind {
            case .beats:
                guard includeBeats else { continue }
                for bar in 0..<bars {
                    for row in DrumRow.allCases {
                        for s in 0..<16 where track.beatGrid.isOn(row, step: s) {
                            hits.append(PlaybackHit(step: bar * 16 + s, track: .beats, sound: .drum(row),
                                                    velocity: row == .hat ? (s % 4 == 0 ? 0.55 : 0.4) : 0.85))
                        }
                    }
                }
            case .bass, .chords, .melody:
                guard !track.notes.isEmpty else { continue }
                let lastStep = track.notes.map { $0.tick / ticksPerStep }.max() ?? 0
                let length = Self.repeatLength(lastStep: lastStep, sectionSteps: steps)
                for offset in stride(from: 0, to: steps, by: length) {
                    for n in track.notes {
                        let s = n.tick / ticksPerStep
                        guard s < length, offset + s < steps else { continue }
                        hits.append(PlaybackHit(step: offset + s, track: track.kind,
                                                sound: .note(midi: n.pitch.midi, instrumentID: track.instrumentID),
                                                velocity: n.velocity))
                    }
                }
            }
        }
        return PlaybackLoop(hits: hits.sorted { ($0.step, $0.track.index) < ($1.step, $1.track.index) }, steps: steps)
    }

    /// Smallest of 1, 2, 4, 8 bars that holds the content, capped at the section length.
    static func repeatLength(lastStep: Int, sectionSteps: Int) -> Int {
        var bars = 1
        while bars * 16 <= lastStep && bars * 16 < sectionSteps { bars *= 2 }
        return min(bars * 16, sectionSteps)
    }
}

extension Song {
    /// Concert mode: every part of the arrangement, one after another.
    public func concert() -> PlaybackLoop {
        var hits: [PlaybackHit] = []
        var offset = 0
        for index in arrangement where sections.indices.contains(index) {
            let loop = sections[index].playback()
            hits += loop.hits.map { PlaybackHit(step: $0.step + offset, track: $0.track, sound: $0.sound, velocity: $0.velocity) }
            offset += loop.steps
        }
        return PlaybackLoop(hits: hits, steps: offset)
    }

    // MARK: Sections and arrangement (spec section 5: up to 4 sections, snap at bar lines)

    /// Copies a section into a new one (next free letter) and adds it to the arrangement.
    @discardableResult
    public mutating func duplicateSection(at index: Int) -> Bool {
        guard sections.indices.contains(index), sections.count < Self.maxSectionsMVP else { return false }
        var copy = sections[index]
        copy.id = UUID()
        for i in copy.tracks.indices { copy.tracks[i].id = UUID() }
        copy.name = String(UnicodeScalar(UInt8(65 + sections.count)))
        sections.append(copy)
        arrangement.append(sections.count - 1)
        updatedAt = Date()
        return true
    }

    /// Kids build the song order by tapping a part to cycle it through A, B, C, D.
    public mutating func cycleArrangementSlot(_ slot: Int) {
        guard arrangement.indices.contains(slot), !sections.isEmpty else { return }
        arrangement[slot] = (arrangement[slot] + 1) % sections.count
        updatedAt = Date()
    }

    /// Adds another part playing the given section. At most 8 parts.
    @discardableResult
    public mutating func appendPart(section: Int) -> Bool {
        guard sections.indices.contains(section), arrangement.count < 8 else { return false }
        arrangement.append(section)
        updatedAt = Date()
        return true
    }

    /// Removes a part; the song always keeps at least one.
    @discardableResult
    public mutating func removePart(_ slot: Int) -> Bool {
        guard arrangement.indices.contains(slot), arrangement.count > 1 else { return false }
        arrangement.remove(at: slot)
        updatedAt = Date()
        return true
    }
}

// MARK: - Chord Pads

public enum ChordVoicing {
    /// Auto voice-leading (spec section 5): picks the inversion of `triad` whose notes move least from
    /// `previous`, staying between E3 and G4 so chords never jump around. First chord: root position on octave 3.
    public static func voiceLead(_ triad: Triad, from previous: [Int]?) -> [Int] {
        let root = Pitch(triad.root, octave: 3).midi
        let base = triad.quality.intervals.map { root + $0 }
        guard let previous, !previous.isEmpty else { return base }
        var candidates: [[Int]] = []
        for inversion in 0..<3 {
            var v = base
            for i in 0..<inversion { v[i] += 12 }
            v.sort()
            for shift in [-12, 0, 12] {
                let c = v.map { $0 + shift }
                if c.first! >= 52, c.last! <= 67 { candidates.append(c) }
            }
        }
        if candidates.isEmpty { return base }
        let prevCenter = Double(previous.reduce(0, +)) / Double(previous.count)
        func cost(_ c: [Int]) -> Double {
            let center = Double(c.reduce(0, +)) / Double(c.count)
            return abs(center - prevCenter)
        }
        return candidates.min { cost($0) < cost($1) }!
    }
}

// MARK: - Keys recording

public struct RecordQuantizer: Sendable {
    public let secondsPerStep: Double
    public let loopSteps: Int
    /// Grid in steps: 2 = eighth notes (spec: quantize on record).
    public let grid: Int

    public init(secondsPerStep: Double, loopSteps: Int, grid: Int = 2) {
        self.secondsPerStep = secondsPerStep
        self.loopSteps = loopSteps
        self.grid = grid
    }

    /// Step in the loop for a tap at `seconds` on the transport clock (0 = loop start), snapped to the grid.
    public func step(at seconds: Double) -> Int {
        let raw = seconds / secondsPerStep
        let snapped = Int((raw / Double(grid)).rounded()) * grid
        return ((snapped % loopSteps) + loopSteps) % loopSteps
    }

    /// Adds a recorded note, replacing a note of the same pitch on the same step.
    public static func record(_ pitch: Pitch, step: Int, into notes: [NoteEvent], lengthSteps: Int = 2) -> [NoteEvent] {
        var out = notes.filter { !($0.tick == step * ticksPerStep && $0.pitch == pitch) }
        out.append(NoteEvent(tick: step * ticksPerStep, pitch: pitch, lengthTicks: lengthSteps * ticksPerStep))
        return out.sorted { ($0.tick, $0.pitch.midi) < ($1.tick, $1.pitch.midi) }
    }
}

// MARK: - Melody Maker (8 x 16 piano-roll lite)

public struct MelodyGrid: Hashable, Sendable {
    public static let columns = 16
    /// Eighth-note columns: 16 columns = 2 bars.
    public static let ticksPerColumn = ticksPerQuarter / 2

    public let scale: Scale
    /// In-key rows only, low to high: one octave of the key plus the top home note.
    public var rows: [Pitch] { scale.pitches(fromOctave: 4, count: 8) }
    public private(set) var cells: [Set<Int>]

    public init(scale: Scale, notes: [NoteEvent] = []) {
        self.scale = scale
        cells = Array(repeating: [], count: Self.columns)
        let rows = self.rows
        for n in notes {
            let c = n.tick / Self.ticksPerColumn
            guard cells.indices.contains(c), let r = rows.firstIndex(of: n.pitch) else { continue }
            cells[c].insert(r)
        }
    }

    public func isOn(column: Int, row: Int) -> Bool { cells.indices.contains(column) && cells[column].contains(row) }

    public mutating func toggle(column: Int, row: Int) {
        guard cells.indices.contains(column), (0..<8).contains(row) else { return }
        if cells[column].contains(row) { cells[column].remove(row) } else { cells[column].insert(row) }
    }

    public var notes: [NoteEvent] {
        let rows = self.rows
        return cells.enumerated().flatMap { c, set in
            set.sorted().map { NoteEvent(tick: c * Self.ticksPerColumn, pitch: rows[$0], lengthTicks: Self.ticksPerColumn) }
        }
    }
}

// MARK: - Chord lane (Chord Pads writes one chord per bar)

public enum ChordStyle: String, CaseIterable, Sendable, Codable {
    case block, strum, arp

    public var displayName: String {
        switch self {
        case .block: "Together"
        case .strum: "Strum"
        case .arp: "Sparkle"
        }
    }
}

public enum ChordLane {
    /// The 8 Chord Pads: the 7 diatonic triads plus home an octave up.
    public static let padDegrees = [1, 2, 3, 4, 5, 6, 7, 8]

    public static func triad(degree: Int, in key: Key) -> Triad { key.diatonicTriad(degree: (degree - 1) % 7 + 1) }

    /// Notes for one chord per bar, voice-led from bar to bar. Degree 8 is home voiced higher.
    public static func events(degrees: [Int?], key: Key, style: ChordStyle) -> [NoteEvent] {
        var previous: [Int]?
        var out: [NoteEvent] = []
        let bar = 16 * ticksPerStep
        for (b, degree) in degrees.enumerated() {
            guard let degree else { continue }
            var voicing = ChordVoicing.voiceLead(triad(degree: degree, in: key), from: previous)
            if degree == 8 { voicing = voicing.map { $0 + 12 } }
            previous = degree == 8 ? voicing.map { $0 - 12 } : voicing
            let start = b * bar
            switch style {
            case .block:
                out += voicing.map { NoteEvent(tick: start, pitch: Pitch(midi: $0), lengthTicks: bar) }
            case .strum:
                out += voicing.enumerated().map { i, m in NoteEvent(tick: start + i * ticksPerStep / 2, pitch: Pitch(midi: m), lengthTicks: bar) }
            case .arp:
                // Up and down on eighth notes: 1 3 5 3 1 3 5 3
                let order = [0, 1, 2, 1, 0, 1, 2, 1]
                out += order.enumerated().map { i, n in
                    NoteEvent(tick: start + i * 2 * ticksPerStep, pitch: Pitch(midi: voicing[n]), lengthTicks: 2 * ticksPerStep, velocity: 0.6)
                }
            }
        }
        return out
    }

    /// Reads chords back from a chords track (the lowest note at each bar start identifies the triad).
    public static func degrees(from notes: [NoteEvent], key: Key, bars: Int) -> [Int?] {
        let bar = 16 * ticksPerStep
        return (0..<bars).map { b in
            let pcs = Set(notes.filter { $0.tick >= b * bar && $0.tick < (b + 1) * bar }.map(\.pitch.pitchClass))
            guard let t = Triad.identify(pcs) else { return nil }
            return (1...7).first { key.diatonicTriad(degree: $0) == t }
        }
    }
}
