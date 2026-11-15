// MusicTheory: pure value types for pitch, intervals, scales, keys and chords.
// No UI, no audio. Everything here is deterministic and unit tested.

import Foundation

// MARK: - Pitch class

/// One of the 12 pitch classes. Raw value = semitones above C.
public enum PitchClass: Int, CaseIterable, Sendable, Codable, Hashable {
    case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b

    /// Sharp spelling, used by default in kid-facing UI.
    public var name: String {
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][rawValue]
    }

    /// Flat spelling, used when a key is spelled with flats (F major, D minor).
    public var flatName: String {
        ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"][rawValue]
    }

    public var solfege: String {
        ["Do", "Di", "Re", "Ri", "Mi", "Fa", "Fi", "Sol", "Si", "La", "Li", "Ti"][rawValue]
    }

    public var isNatural: Bool { [0, 2, 4, 5, 7, 9, 11].contains(rawValue) }

    /// The natural note this pitch class takes its color from (sharps use the lower natural).
    public var colorParent: PitchClass {
        isNatural ? self : PitchClass(semitones: rawValue - 1)
    }

    public init(semitones: Int) {
        self = PitchClass(rawValue: ((semitones % 12) + 12) % 12)!
    }

    public func transposed(by semitones: Int) -> PitchClass {
        PitchClass(semitones: rawValue + semitones)
    }

    /// Smallest upward distance in semitones from `self` to `other` (0...11).
    public func semitones(upTo other: PitchClass) -> Int {
        ((other.rawValue - rawValue) % 12 + 12) % 12
    }
}

// MARK: - Pitch

/// An absolute pitch as a MIDI note number. Middle C (C4) = 60.
public struct Pitch: Hashable, Comparable, Sendable, Codable {
    public let midi: Int

    public init(midi: Int) {
        precondition((0...127).contains(midi), "MIDI note out of range")
        self.midi = midi
    }

    public init(_ pitchClass: PitchClass, octave: Int) {
        self.init(midi: (octave + 1) * 12 + pitchClass.rawValue)
    }

    public var pitchClass: PitchClass { PitchClass(semitones: midi) }
    public var octave: Int { midi / 12 - 1 }
    public var name: String { "\(pitchClass.name)\(octave)" }

    /// Equal temperament, A4 = 440 Hz.
    public var frequency: Double { 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0) }

    public func transposed(by semitones: Int) -> Pitch { Pitch(midi: midi + semitones) }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }
}

// MARK: - Interval

public struct Interval: Hashable, Sendable, Codable {
    public let semitones: Int
    public init(semitones: Int) { self.semitones = semitones }

    public static let unison = Interval(semitones: 0)
    public static let minorSecond = Interval(semitones: 1)
    public static let majorSecond = Interval(semitones: 2)
    public static let minorThird = Interval(semitones: 3)
    public static let majorThird = Interval(semitones: 4)
    public static let perfectFourth = Interval(semitones: 5)
    public static let tritone = Interval(semitones: 6)
    public static let perfectFifth = Interval(semitones: 7)
    public static let minorSixth = Interval(semitones: 8)
    public static let majorSixth = Interval(semitones: 9)
    public static let minorSeventh = Interval(semitones: 10)
    public static let majorSeventh = Interval(semitones: 11)
    public static let octave = Interval(semitones: 12)

    /// Kid-friendly name used by games ("3rd", "5th", "octave").
    public var shortName: String {
        switch semitones {
        case 0: "same"
        case 1, 2: "2nd"
        case 3, 4: "3rd"
        case 5: "4th"
        case 6: "tritone"
        case 7: "5th"
        case 8, 9: "6th"
        case 10, 11: "7th"
        case 12: "octave"
        default: "\(semitones) steps"
        }
    }

    /// A step moves to a neighboring scale note (1 or 2 semitones); anything larger is a skip.
    public var isStep: Bool { (1...2).contains(abs(semitones)) }

    public static func between(_ a: Pitch, _ b: Pitch) -> Interval {
        Interval(semitones: b.midi - a.midi)
    }
}

// MARK: - Scale

public enum ScaleType: String, CaseIterable, Sendable, Codable {
    case major, naturalMinor, majorPentatonic, minorPentatonic

    public var steps: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        }
    }
}

public struct Scale: Hashable, Sendable, Codable {
    public let tonic: PitchClass
    public let type: ScaleType

    public init(tonic: PitchClass, type: ScaleType) {
        self.tonic = tonic
        self.type = type
    }

    public var pitchClasses: [PitchClass] { type.steps.map { tonic.transposed(by: $0) } }

    public func contains(_ pc: PitchClass) -> Bool { pitchClasses.contains(pc) }

    /// Scale degree (1-based) of a pitch class, nil if not in the scale.
    public func degree(of pc: PitchClass) -> Int? {
        pitchClasses.firstIndex(of: pc).map { $0 + 1 }
    }

    /// Ascending pitches of the scale starting at `tonic` in `octave`, `count` notes long.
    public func pitches(fromOctave octave: Int, count: Int) -> [Pitch] {
        let base = Pitch(tonic, octave: octave).midi
        let steps = type.steps
        return (0..<count).map { i in
            Pitch(midi: base + steps[i % steps.count] + 12 * (i / steps.count))
        }
    }

    /// Snap any MIDI note to the nearest scale note (ties go down). Used by Melody Paint and Keys scale-lock.
    public func snap(_ pitch: Pitch) -> Pitch {
        if contains(pitch.pitchClass) { return pitch }
        for distance in 1...6 {
            let down = pitch.midi - distance
            if down >= 0, contains(PitchClass(semitones: down)) { return Pitch(midi: down) }
            let up = pitch.midi + distance
            if up <= 127, contains(PitchClass(semitones: up)) { return Pitch(midi: up) }
        }
        return pitch
    }
}

// MARK: - Chords

public enum ChordQuality: String, CaseIterable, Sendable, Codable {
    case major, minor, diminished, augmented

    public var intervals: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .diminished: [0, 3, 6]
        case .augmented: [0, 4, 8]
        }
    }

    /// UI mood: major = sun face, minor = moon face.
    public var mood: ChordMood {
        switch self {
        case .major, .augmented: .sunny
        case .minor, .diminished: .moon
        }
    }

    public var suffix: String {
        switch self {
        case .major: ""
        case .minor: "m"
        case .diminished: "dim"
        case .augmented: "aug"
        }
    }

    public var kidName: String {
        switch self {
        case .major: "major"
        case .minor: "minor"
        case .diminished: "diminished"
        case .augmented: "augmented"
        }
    }
}

public enum ChordMood: String, Sendable, Codable { case sunny, moon }

/// Which job a note does inside a triad. Chord Chef uses these as the "ingredients".
public enum ChordTone: String, CaseIterable, Sendable, Codable { case root, third, fifth }

public struct Triad: Hashable, Sendable, Codable {
    public let root: PitchClass
    public let quality: ChordQuality

    public init(root: PitchClass, quality: ChordQuality) {
        self.root = root
        self.quality = quality
    }

    public var pitchClasses: [PitchClass] { quality.intervals.map { root.transposed(by: $0) } }

    public func pitchClass(for tone: ChordTone) -> PitchClass {
        switch tone {
        case .root: pitchClasses[0]
        case .third: pitchClasses[1]
        case .fifth: pitchClasses[2]
        }
    }

    public var symbol: String { root.name + quality.suffix }
    public var kidName: String { "\(root.name) \(quality.kidName)" }

    /// Close-position voicing with the root in `octave`.
    public func pitches(rootOctave octave: Int = 4) -> [Pitch] {
        let base = Pitch(root, octave: octave).midi
        return quality.intervals.map { Pitch(midi: base + $0) }
    }

    /// Identify a triad from exactly three pitch classes in any order. Returns nil when they don't form one.
    public static func identify(_ pcs: Set<PitchClass>) -> Triad? {
        guard pcs.count == 3 else { return nil }
        for root in pcs {
            for quality in ChordQuality.allCases {
                let candidate = Triad(root: root, quality: quality)
                if Set(candidate.pitchClasses) == pcs { return candidate }
            }
        }
        return nil
    }
}

// MARK: - Key and Roman numerals

public enum KeyMode: String, Sendable, Codable { case major, minor }

public struct Key: Hashable, Sendable, Codable {
    public let tonic: PitchClass
    public let mode: KeyMode

    public init(tonic: PitchClass, mode: KeyMode) {
        self.tonic = tonic
        self.mode = mode
    }

    /// The five V1 "color moods" from the spec.
    public static let sunnyC = Key(tonic: .c, mode: .major)
    public static let brightG = Key(tonic: .g, mode: .major)
    public static let warmF = Key(tonic: .f, mode: .major)
    public static let moonlightAMinor = Key(tonic: .a, mode: .minor)
    public static let mysteryDMinor = Key(tonic: .d, mode: .minor)
    public static let v1Moods: [Key] = [.sunnyC, .brightG, .warmF, .moonlightAMinor, .mysteryDMinor]

    public var scale: Scale { Scale(tonic: tonic, type: mode == .major ? .major : .naturalMinor) }

    public var moodName: String {
        switch self {
        case .sunnyC: "Sunny C"
        case .brightG: "Bright G"
        case .warmF: "Warm F"
        case .moonlightAMinor: "Moonlight A minor"
        case .mysteryDMinor: "Mystery D minor"
        default: "\(tonic.name) \(mode.rawValue)"
        }
    }

    /// Triad built on each scale degree (1...7) using only scale notes.
    public func diatonicTriad(degree: Int) -> Triad {
        precondition((1...7).contains(degree))
        let pcs = scale.pitchClasses
        let root = pcs[degree - 1]
        let third = pcs[(degree + 1) % 7]
        let fifth = pcs[(degree + 3) % 7]
        let set: Set<PitchClass> = [root, third, fifth]
        // identify() can't fail for stacked diatonic thirds, but fall back to root major defensively.
        if let triad = Triad.identify(set), triad.root == root { return triad }
        let quality: ChordQuality = {
            let t = root.semitones(upTo: third), f = root.semitones(upTo: fifth)
            switch (t, f) {
            case (4, 7): return .major
            case (3, 7): return .minor
            case (3, 6): return .diminished
            default: return .augmented
            }
        }()
        return Triad(root: root, quality: quality)
    }

    public var diatonicTriads: [Triad] { (1...7).map(diatonicTriad(degree:)) }

    /// Roman numeral for a diatonic degree: upper case = major, lower = minor, "°" = diminished.
    public func romanNumeral(degree: Int) -> String {
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let base = numerals[degree - 1]
        switch diatonicTriad(degree: degree).quality {
        case .major: return base
        case .augmented: return base + "+"
        case .minor: return base.lowercased()
        case .diminished: return base.lowercased() + "°"
        }
    }
}
