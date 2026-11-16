// Harmony Harbor games (spec section 4): Mood Boats, Stack Attack. Chord Chef lives in GameKitCore.swift.

import Foundation
import MusicTheory

// MARK: - Mood Boats: sunny (major) or moon (minor)?

public enum MoodMaterial: String, Sendable { case triads, progressions, melodies }

public struct MoodBoatsRound: Sendable, Equatable {
    public let mood: ChordMood
    /// What to play, in order: each step is a chord (several MIDI notes) or a single melody note.
    public let steps: [[Int]]

    public init(mood: ChordMood, steps: [[Int]]) {
        self.mood = mood
        self.steps = steps
    }

    public static func make(material: MoodMaterial, using rng: inout some RandomNumberGenerator) -> MoodBoatsRound {
        let mood: ChordMood = Bool.random(using: &rng) ? .sunny : .moon
        let tonic = [PitchClass.c, .d, .f, .g, .a].randomElement(using: &rng)!
        switch material {
        case .triads:
            let triad = Triad(root: tonic, quality: mood == .sunny ? .major : .minor)
            return MoodBoatsRound(mood: mood, steps: [triad.pitches(rootOctave: 4).map(\.midi)])
        case .progressions:
            // I-IV-V-I in major or i-iv-v-i in natural minor.
            let key = Key(tonic: tonic, mode: mood == .sunny ? .major : .minor)
            let chords = [1, 4, 5, 1].map { key.diatonicTriad(degree: $0).pitches(rootOctave: 3).map(\.midi) }
            return MoodBoatsRound(mood: mood, steps: chords)
        case .melodies:
            // Up to the 5th and back home: 1 2 3 4 5 3 1, where the 3rd decides the mood.
            let scale = Scale(tonic: tonic, type: mood == .sunny ? .major : .naturalMinor)
            let pitches = scale.pitches(fromOctave: 4, count: 5)
            return MoodBoatsRound(mood: mood, steps: [0, 1, 2, 3, 4, 2, 0].map { [pitches[$0].midi] })
        }
    }
}

// MARK: - Stack Attack: stack chord blocks to match a heard progression in Sunny C.

public enum StackAttack {
    /// The four blocks: I, IV, V, vi (scale degrees in the key).
    public static let blocks = [1, 4, 5, 6]

    /// Starts on I; no block repeats right after itself.
    public static func progression(length: Int, using rng: inout some RandomNumberGenerator) -> [Int] {
        var result = [1]
        while result.count < max(1, length) {
            let next = blocks.filter { $0 != result.last }.randomElement(using: &rng)!
            result.append(next)
        }
        return result
    }

    /// Indices of slots that don't match yet (an empty slot counts as not matching).
    public static func mismatches(placed: [Int?], target: [Int]) -> [Int] {
        target.indices.filter { i in i >= placed.count || placed[i] != target[i] }
    }
}
