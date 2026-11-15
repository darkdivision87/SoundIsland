// GameKitCore: game-agnostic rules shared by every mini-game.
// Pure logic only, so it can be tested with synthetic input streams.

import Foundation
import MusicTheory
import Curriculum

// MARK: - Timing judgment

public enum TimingGrade: String, Sendable, Equatable {
    case great, good, miss
}

public struct TapJudgment: Sendable, Equatable {
    public let grade: TimingGrade
    /// Index of the target the tap was matched to, nil for a miss with no target in reach.
    public let targetIndex: Int?
    /// Signed offset in seconds: negative = early (Bop leans left), positive = late (leans right).
    public let offset: Double
}

/// Scores taps against target times on the AUDIO clock (seconds since transport start).
/// Windows per spec: Sprouts +/-150 ms "great", Explorers +/-100 ms, Makers +/-60 ms.
/// "Good" is double the great window; anything further is a miss.
public struct TimingJudge: Sendable {
    public let greatWindow: Double
    public var goodWindow: Double { greatWindow * 2 }

    public init(greatWindow: Double) { self.greatWindow = greatWindow }

    public init(band: AgeBand) {
        switch band {
        case .sprouts: greatWindow = 0.150
        case .explorers: greatWindow = 0.100
        case .makers: greatWindow = 0.060
        }
    }

    public func judge(tap: Double, targets: [Double], alreadyHit: Set<Int> = []) -> TapJudgment {
        var best: (index: Int, offset: Double)?
        for (i, t) in targets.enumerated() where !alreadyHit.contains(i) {
            let off = tap - t
            if abs(off) <= goodWindow, best == nil || abs(off) < abs(best!.offset) {
                best = (i, off)
            }
        }
        guard let match = best else { return TapJudgment(grade: .miss, targetIndex: nil, offset: 0) }
        let grade: TimingGrade = abs(match.offset) <= greatWindow ? .great : .good
        return TapJudgment(grade: grade, targetIndex: match.index, offset: match.offset)
    }

    /// Judge a whole tap stream. Each target can be hit at most once; extra taps are misses.
    public func judgeStream(taps: [Double], targets: [Double]) -> StreamResult {
        var hit = Set<Int>()
        var judgments: [TapJudgment] = []
        for tap in taps.sorted() {
            let j = judge(tap: tap, targets: targets, alreadyHit: hit)
            if let i = j.targetIndex { hit.insert(i) }
            judgments.append(j)
        }
        return StreamResult(judgments: judgments, targetCount: targets.count, hitTargets: hit)
    }

    public struct StreamResult: Sendable, Equatable {
        public let judgments: [TapJudgment]
        public let targetCount: Int
        public let hitTargets: Set<Int>

        /// Share of targets hit on time (great or good). Extra taps do not lower it for Sprouts-friendliness.
        public var accuracy: Double {
            targetCount == 0 ? 0 : Double(hitTargets.count) / Double(targetCount)
        }

        public var meanAbsOffsetMs: Double {
            let hits = judgments.filter { $0.targetIndex != nil }
            guard !hits.isEmpty else { return 0 }
            return hits.map { abs($0.offset) }.reduce(0, +) / Double(hits.count) * 1000
        }
    }
}

// MARK: - Beat schedules

public enum BeatSchedule {
    /// Beat times in seconds for `count` beats at `bpm`, optionally changing tempo halfway (Crab Tap tier 3).
    public static func beats(count: Int, bpm: Double, changeTo secondBPM: Double? = nil, startAt start: Double = 0) -> [Double] {
        var t = start
        var times: [Double] = []
        for i in 0..<count {
            times.append(t)
            let current = (secondBPM != nil && i >= count / 2) ? secondBPM! : bpm
            t += 60.0 / current
        }
        return times
    }
}

// MARK: - Stars

/// Spec section 10: 1 star for finishing, 2 at 70% accuracy, 3 at 90%.
public enum Stars {
    public static func forAccuracy(_ accuracy: Double) -> Int {
        if accuracy >= 0.90 { return 3 }
        if accuracy >= 0.70 { return 2 }
        return 1
    }
}

// MARK: - Round flow

public enum RoundPhase: Equatable, Sendable {
    case listen, tryIt, feedback(correct: Bool), reward(stars: Int), finished
}

/// Shared Listen > Try > Feedback > Reward state machine with the hint rules.
public struct RoundFlow: Sendable {
    public let totalRounds: Int
    public private(set) var round = 0
    public private(set) var phase: RoundPhase = .listen
    public private(set) var results: [Bool] = []
    public private(set) var missesThisRound = 0

    public init(totalRounds: Int) {
        precondition(totalRounds > 0)
        self.totalRounds = totalRounds
    }

    /// After 2 misses the target glows; after 3 Bop replays it slower. Hints never cost anything.
    public var showGlowHint: Bool { missesThisRound >= 2 }
    public var replaySlowerHint: Bool { missesThisRound >= 3 }

    public var accuracy: Double {
        results.isEmpty ? 0 : Double(results.filter { $0 }.count) / Double(results.count)
    }

    public mutating func startTrying() { if phase == .listen { phase = .tryIt } }

    /// A wrong attempt inside a round. The round continues (errorless learning).
    public mutating func miss() {
        guard phase == .tryIt else { return }
        missesThisRound += 1
    }

    /// The round is over. `correct` is first-try-or-with-hints success as each game defines it.
    public mutating func completeRound(correct: Bool) {
        guard phase == .tryIt else { return }
        results.append(correct)
        phase = .feedback(correct: correct)
    }

    public mutating func next() {
        switch phase {
        case .feedback:
            round += 1
            missesThisRound = 0
            phase = round >= totalRounds ? .reward(stars: Stars.forAccuracy(accuracy)) : .listen
        case .reward:
            phase = .finished
        default:
            break
        }
    }
}

// MARK: - Chord Chef rules

/// Builds Chord Chef orders and checks the pot. Tier 1: pick the missing note.
/// Tier 2: build from the root. Tier 3: build major or minor on a given root.
public struct ChordChefRules: Sendable {
    public let key: Key
    public let tier: Int

    public init(key: Key = .sunnyC, tier: Int) {
        self.key = key
        self.tier = tier
    }

    public struct Order: Sendable, Equatable {
        public let target: Triad
        /// Notes already in the pot when the order starts.
        public let given: [ChordTone]
        public var needed: [ChordTone] { ChordTone.allCases.filter { !given.contains($0) } }
    }

    /// Deterministic for a given seed so rounds are testable and replayable.
    public func order(round: Int, seed: UInt64 = 0) -> Order {
        var rng = SplitMix64(seed: seed &+ UInt64(round) &* 0x9E37_79B9)
        switch tier {
        case 1:
            // Major triads on I, IV, V; the fifth is missing.
            let degree = [1, 4, 5][Int(rng.next() % 3)]
            return Order(target: key.diatonicTriad(degree: degree), given: [.root, .third])
        case 2:
            // Any diatonic major or minor triad; only the root is given.
            let degrees = (1...7).filter { key.diatonicTriad(degree: $0).quality != .diminished }
            let degree = degrees[Int(rng.next() % UInt64(degrees.count))]
            return Order(target: key.diatonicTriad(degree: degree), given: [.root])
        default:
            // Root given; Bop asks for a specific quality, which may need a non-diatonic third.
            let roots: [PitchClass] = [.c, .d, .e, .f, .g, .a]
            let root = roots[Int(rng.next() % UInt64(roots.count))]
            let quality: ChordQuality = rng.next() % 2 == 0 ? .major : .minor
            return Order(target: Triad(root: root, quality: quality), given: [.root])
        }
    }

    public enum PotResult: Equatable, Sendable {
        case needMore(Int)
        case correct
        /// Wrong note: report which tone slot it was offered for, so Bop can play the difference.
        case wrongNote(offered: PitchClass, expected: PitchClass, tone: ChordTone)
    }

    /// Check the notes the child put in the pot for the missing tones. Order does not matter;
    /// the first note that is not one of the missing tones is reported against the first unfilled slot.
    public func check(order: Order, added: [PitchClass]) -> PotResult {
        var unfilled = order.needed
        for pc in added {
            if let idx = unfilled.firstIndex(where: { order.target.pitchClass(for: $0) == pc }) {
                unfilled.remove(at: idx)
            } else if let slot = unfilled.first {
                return .wrongNote(offered: pc, expected: order.target.pitchClass(for: slot), tone: slot)
            }
        }
        return unfilled.isEmpty ? .correct : .needMore(unfilled.count)
    }
}

/// Small deterministic RNG (no Foundation randomness) for replayable rounds.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
