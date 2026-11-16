// Pitch Peaks games (spec section 4): Bird Song, Pitch Climb, Key Hunt.

import Foundation
import MusicTheory

// MARK: - Bird Song: which bird sang higher (or lower)?

public struct BirdSongRound: Sendable, Equatable {
    public let low: Pitch
    public let high: Pitch
    public let askHigher: Bool
    public let highOnLeft: Bool

    public init(low: Pitch, high: Pitch, askHigher: Bool, highOnLeft: Bool) {
        self.low = low
        self.high = high
        self.askHigher = askHigher
        self.highOnLeft = highOnLeft
    }

    /// Birds left to right.
    public var birds: [Pitch] { highOnLeft ? [high, low] : [low, high] }
    /// Index into `birds` of the bird that gets the worm.
    public var answer: Int { askHigher == highOnLeft ? 0 : 1 }

    /// Lower note between C4 and G4 so both stay in a comfortable, clear range.
    public static func make(intervalSemitones: Int, using rng: inout some RandomNumberGenerator) -> BirdSongRound {
        let low = Pitch(midi: Int.random(in: 60...67, using: &rng))
        return BirdSongRound(low: low, high: low.transposed(by: max(1, intervalSemitones)),
                             askHigher: Bool.random(using: &rng), highOnLeft: Bool.random(using: &rng))
    }
}

// MARK: - Pitch Climb: where does the climber go on the C major ladder?

public enum ClimbMode: String, Sendable { case direction, stepOrSkip, exactRung }

public enum ClimbAnswer: Hashable, Sendable {
    case up, down, stepUp, stepDown, skipUp, skipDown
    case rung(Int)

    public var label: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .stepUp: "Step up"
        case .stepDown: "Step down"
        case .skipUp: "Skip up"
        case .skipDown: "Skip down"
        case .rung(let r): "Rung \(r + 1)"
        }
    }
}

public struct PitchClimbRound: Sendable, Equatable {
    /// The ladder: C major from C4 to C5, rung 0 at the bottom.
    public static let ladder = Scale(tonic: .c, type: .major).pitches(fromOctave: 4, count: 8)

    public let mode: ClimbMode
    public let start: Int
    public let target: Int
    public let options: [ClimbAnswer]

    public var correct: ClimbAnswer {
        let up = target > start
        switch mode {
        case .direction: return up ? .up : .down
        case .stepOrSkip: return abs(target - start) == 1 ? (up ? .stepUp : .stepDown) : (up ? .skipUp : .skipDown)
        case .exactRung: return .rung(target)
        }
    }

    public func isCorrect(_ answer: ClimbAnswer) -> Bool { answer == correct }

    public static func make(mode: ClimbMode, using rng: inout some RandomNumberGenerator) -> PitchClimbRound {
        let maxMove = mode == .direction ? 3 : 4
        var start = 0, target = 0
        repeat {
            start = Int.random(in: 0...7, using: &rng)
            var move = Int.random(in: 1...maxMove, using: &rng)
            if mode == .stepOrSkip, Bool.random(using: &rng) { move = 1 } // half the rounds are steps
            target = start + (Bool.random(using: &rng) ? move : -move)
        } while !(0...7).contains(target)

        let options: [ClimbAnswer]
        switch mode {
        case .direction: options = [.up, .down]
        case .stepOrSkip: options = [.stepUp, .skipUp, .stepDown, .skipDown]
        case .exactRung:
            // Four candidate rungs (Explorers see at most 4 choices): the target plus 3 others, not the start.
            var pool = Array(0...7).filter { $0 != start && $0 != target }
            pool.shuffle(using: &rng)
            options = ([target] + pool.prefix(3)).sorted().map { .rung($0) }
        }
        return PitchClimbRound(mode: mode, start: start, target: target, options: options)
    }

    public init(mode: ClimbMode, start: Int, target: Int, options: [ClimbAnswer]) {
        self.mode = mode
        self.start = start
        self.target = target
        self.options = options
    }
}

// MARK: - Key Hunt: Bop names a note, the child taps that key.

public enum KeyHunt {
    /// Parses tier note names ("C", "C#") into pitch classes.
    public static func pitchClasses(_ names: [String]) -> [PitchClass] {
        names.compactMap { name in PitchClass.allCases.first { $0.name == name } }
    }

    /// Next note to find: never the same as the previous one when there's a choice.
    public static func next(from notes: [PitchClass], after previous: PitchClass?,
                            using rng: inout some RandomNumberGenerator) -> PitchClass {
        let pool = notes.count > 1 ? notes.filter { $0 != previous } : notes
        return pool.randomElement(using: &rng) ?? .c
    }
}
