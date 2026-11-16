// Melody Jungle games (spec section 4): Echo Monkeys, Vine Swing, Melody Paint.

import Foundation
import MusicTheory

extension ScaleType {
    /// skills.json names: "majorPentatonic", "major".
    public init(content: String) { self = ScaleType(rawValue: content) ?? .majorPentatonic }
}

extension PitchClass {
    /// Parses a name like "C", "F#".
    public init?(name: String) {
        guard let pc = PitchClass.allCases.first(where: { $0.name == name }) else { return nil }
        self = pc
    }
}

// MARK: - Echo Monkeys: copy the monkey's phrase on the scale pads.

public struct EchoPhrase: Sendable, Equatable {
    /// Indices into the pad row (scale degrees from the tonic, 0-based).
    public let pads: [Int]
    /// Length of each note in beats (all 1 unless the tier has rhythm).
    public let beats: [Double]

    public init(pads: [Int], beats: [Double]) {
        self.pads = pads
        self.beats = beats
    }

    /// Singable phrase: moves by at most 2 pads at a time, and ends on the home pad (0) or its octave.
    public static func make(length: Int, padCount: Int, rhythm: Bool,
                            using rng: inout some RandomNumberGenerator) -> EchoPhrase {
        let length = max(2, length)
        var pads = [Int.random(in: 0..<min(3, padCount), using: &rng)]
        for _ in 1..<(length - 1) {
            let last = pads.last!
            var next = last
            while next == last { next = min(max(last + Int.random(in: -2...2, using: &rng), 0), padCount - 1) }
            pads.append(next)
        }
        pads.append(0)
        if pads[pads.count - 2] == 0 { pads[pads.count - 2] = 1 } // don't repeat home right before ending on it
        let beats: [Double] = rhythm
            ? pads.indices.map { $0 == pads.count - 1 ? 1 : (Bool.random(using: &rng) ? 0.5 : 1) }
            : Array(repeating: 1, count: pads.count)
        return EchoPhrase(pads: pads, beats: beats)
    }
}

/// Tracks the child's echo as they tap pads.
public struct EchoInput: Sendable, Equatable {
    public let phrase: EchoPhrase
    public private(set) var played: [Int] = []

    public init(phrase: EchoPhrase) { self.phrase = phrase }

    public enum Step: Sendable, Equatable { case good, complete, wrong(expected: Int) }

    /// A wrong pad resets the echo (the round continues; Bop plays the phrase again).
    public mutating func tap(_ pad: Int) -> Step {
        let expected = phrase.pads[played.count]
        guard pad == expected else {
            played = []
            return .wrong(expected: expected)
        }
        played.append(pad)
        return played.count == phrase.pads.count ? .complete : .good
    }
}

// MARK: - Vine Swing: which note is missing from the scale?

public struct VineSwingRound: Sendable, Equatable {
    /// The scale going up one octave, home to home.
    public let notes: [Pitch]
    public let missing: Int
    /// Three choices, low to high.
    public let options: [Pitch]

    public var answer: Pitch { notes[missing] }

    public init(notes: [Pitch], missing: Int, options: [Pitch]) {
        self.notes = notes
        self.missing = missing
        self.options = options
    }

    /// The missing note is never the first (the child needs to hear home first). Distractors are the
    /// notes a half step either side when they are not in the scale, otherwise other scale notes.
    public static func make(scale: Scale, using rng: inout some RandomNumberGenerator) -> VineSwingRound {
        let notes = scale.pitches(fromOctave: 4, count: scale.type.steps.count + 1)
        let missing = Int.random(in: 1..<notes.count, using: &rng)
        let answer = notes[missing]
        var distractors: [Pitch] = [answer.transposed(by: -1), answer.transposed(by: 1)]
            .filter { !scale.contains($0.pitchClass) }
        var others = notes.filter { $0 != answer && $0.pitchClass != answer.pitchClass }
        others.shuffle(using: &rng)
        while distractors.count < 2, let o = others.popLast() { distractors.append(o) }
        distractors.shuffle(using: &rng)
        let options = ([answer] + distractors.prefix(2)).sorted()
        return VineSwingRound(notes: notes, missing: missing, options: options)
    }
}

// MARK: - Melody Paint: paint scale-snapped notes on a grid.

public struct MelodyCanvas: Sendable, Equatable {
    public let scale: Scale
    public let columns: Int
    /// Rows from low to high: one octave of the scale plus the top home note.
    public var rows: [Pitch] { scale.pitches(fromOctave: 4, count: scale.type.steps.count + 1) }
    /// One note (row index) per column, nil = rest.
    public private(set) var cells: [Int?]
    /// Phrase length in columns; tier 3 has two phrases.
    public let phraseLength: Int

    public init(scale: Scale, columns: Int, phraseLength: Int? = nil) {
        self.scale = scale
        self.columns = columns
        self.phraseLength = phraseLength ?? columns
        cells = Array(repeating: nil, count: columns)
    }

    /// Paint or erase: tapping the note that's already there erases it.
    public mutating func toggle(column: Int, row: Int) {
        guard cells.indices.contains(column) else { return }
        cells[column] = cells[column] == row ? nil : row
    }

    public var noteCount: Int { cells.compactMap { $0 }.count }

    /// Last painted note of the whole melody is home (bottom or top row).
    public var endsOnHome: Bool {
        guard let last = cells.last(where: { $0 != nil }) ?? nil else { return false }
        return rows[last].pitchClass == scale.tonic
    }

    public enum Readiness: Sendable, Equatable { case needMoreNotes, needHomeEnding, ready }

    /// Finishing needs at least 3 notes, and a home ending when the tier asks for it.
    public func readiness(requireHomeEnding: Bool) -> Readiness {
        if noteCount < min(3, columns) { return .needMoreNotes }
        if requireHomeEnding && !endsOnHome { return .needHomeEnding }
        return .ready
    }

    /// Notes for the Studio melody track: one column per eighth note.
    public func noteEvents(ticksPerColumn: Int = 48) -> [(tick: Int, pitch: Pitch, length: Int)] {
        cells.enumerated().compactMap { c, row in
            row.map { (tick: c * ticksPerColumn, pitch: rows[$0], length: ticksPerColumn) }
        }
    }
}
