// Wave Rider (Beat Beach): note "shells" scroll to a hit ring; tap as they arrive. Spec section 4.
// Tier values come from skills.json: "q" quarter, "8" eighth, "qr" quarter rest, "8r" eighth rest.

import Foundation

public enum RhythmValue: String, Sendable, CaseIterable {
    case quarter = "q", eighth = "8", quarterRest = "qr", eighthRest = "8r"

    public var beats: Double { self == .quarter || self == .quarterRest ? 1 : 0.5 }
    public var isRest: Bool { self == .quarterRest || self == .eighthRest }
}

public struct RhythmEvent: Sendable, Equatable {
    public let value: RhythmValue
    /// Start position in beats from the pattern's first downbeat.
    public let beat: Double
}

public struct RhythmPattern: Sendable, Equatable {
    public let events: [RhythmEvent]
    public let beats: Int

    public init(events: [RhythmEvent], beats: Int) {
        self.events = events
        self.beats = beats
    }

    /// Beat positions the child should tap (rests excluded).
    public var onsets: [Double] { events.filter { !$0.value.isRest }.map(\.beat) }

    /// One beat of the pattern. Eighths always come in a beat-long pair so kids read them as a unit.
    enum Cell: CaseIterable {
        case quarter, quarterRest, eighths, eighthThenRest, restThenEighth

        var values: [RhythmValue] {
            switch self {
            case .quarter: [.quarter]
            case .quarterRest: [.quarterRest]
            case .eighths: [.eighth, .eighth]
            case .eighthThenRest: [.eighth, .eighthRest]
            case .restThenEighth: [.eighthRest, .eighth]
            }
        }

        var isRest: Bool { self == .quarterRest }
        var hasDownbeatNote: Bool { self == .quarter || self == .eighths || self == .eighthThenRest }

        static func allowed(by values: Set<RhythmValue>) -> [Cell] {
            allCases.filter { cell in Set(cell.values).isSubset(of: values) }
        }
    }

    /// Random pattern for a tier. Rules that keep it readable for 6 to 10 year olds:
    /// the first beat has a note on the downbeat, no two rest beats in a row, and the tier's newest
    /// value (last in `values`) appears at least once so every pattern practises what the tier teaches.
    public static func generate(values: [RhythmValue], bars: Int, using rng: inout some RandomNumberGenerator) -> RhythmPattern {
        let allowedValues = Set(values.isEmpty ? [.quarter] : values).union([.quarter])
        let cells = Cell.allowed(by: allowedValues)
        let newest = values.last ?? .quarter
        let beatCount = max(1, bars) * 4

        var chosen: [Cell] = []
        for _ in 0..<64 {
            chosen = (0..<beatCount).map { _ in cells.randomElement(using: &rng)! }
            if isValid(chosen, newest: newest) { break }
            chosen = []
        }
        if chosen.isEmpty { chosen = fallback(beatCount: beatCount, newest: newest, cells: cells) }

        var events: [RhythmEvent] = []
        for (beat, cell) in chosen.enumerated() {
            var pos = Double(beat)
            for v in cell.values {
                events.append(RhythmEvent(value: v, beat: pos))
                pos += v.beats
            }
        }
        return RhythmPattern(events: events, beats: beatCount)
    }

    static func isValid(_ cells: [Cell], newest: RhythmValue) -> Bool {
        guard let first = cells.first, first.hasDownbeatNote else { return false }
        for i in 1..<max(cells.count, 1) where cells[i].isRest && cells[i - 1].isRest { return false }
        return cells.contains { $0.values.contains(newest) }
    }

    /// Deterministic pattern if random tries all fail (only possible with odd value sets).
    static func fallback(beatCount: Int, newest: RhythmValue, cells: [Cell]) -> [Cell] {
        var result = Array(repeating: Cell.quarter, count: beatCount)
        if beatCount > 1, let teach = cells.first(where: { $0.values.contains(newest) }) { result[beatCount - 2] = teach }
        return result
    }
}

/// How one attempt at a pattern went.
public struct PatternResult: Sendable, Equatable {
    public let stream: TimingJudge.StreamResult
    /// Taps that matched no note: tapping on a rest or between notes.
    public let extraTaps: Int

    /// Every note on time (great or good) and nothing tapped on a rest.
    public var isClean: Bool { stream.hitTargets.count == stream.targetCount && extraTaps == 0 }

    /// Judges taps (seconds on the audio clock) against a pattern whose first beat is at `start`.
    public static func judge(taps: [Double], pattern: RhythmPattern, start: Double, secondsPerBeat: Double,
                             judge: TimingJudge) -> PatternResult {
        let targets = pattern.onsets.map { start + $0 * secondsPerBeat }
        let stream = judge.judgeStream(taps: taps, targets: targets)
        return PatternResult(stream: stream, extraTaps: stream.judgments.filter { $0.targetIndex == nil }.count)
    }
}

/// Attempts at one Wave Rider pattern. A pattern that isn't clean is tried again (errorless: no fail state);
/// the third try is slower. It counts as correct only if cleaned before the slow replay.
public struct WaveRiderAttempts: Sendable, Equatable {
    public static let maxAttempts = 3
    public static let slowTempoFactor = 0.85

    public private(set) var attempt = 1

    public init() {}

    public enum Next: Sendable, Equatable {
        case retry(slower: Bool)
        case done(correct: Bool)
    }

    public mutating func record(clean: Bool) -> Next {
        if clean { return .done(correct: attempt < Self.maxAttempts) }
        if attempt >= Self.maxAttempts { return .done(correct: false) }
        attempt += 1
        return .retry(slower: attempt >= Self.maxAttempts)
    }
}
