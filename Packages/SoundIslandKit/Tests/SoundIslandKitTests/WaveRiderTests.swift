import XCTest
import Curriculum
@testable import GameKitCore

final class WaveRiderTests: XCTestCase {
    private let tiers: [[RhythmValue]] = [[.quarter], [.quarter, .quarterRest], [.quarter, .eighth],
                                          [.quarter, .eighth, .quarterRest], [.quarter, .eighth, .quarterRest, .eighthRest]]

    func testGeneratedPatternsFollowTheReadabilityRules() {
        var rng = SplitMix64(seed: 42)
        for values in tiers {
            for bars in 1...2 {
                for _ in 0..<200 {
                    let p = RhythmPattern.generate(values: values, bars: bars, using: &rng)
                    XCTAssertEqual(p.beats, bars * 4)
                    XCTAssertEqual(p.events.first?.beat, 0)
                    XCTAssertFalse(p.events.first!.value.isRest, "starts with a note on beat 1")
                    XCTAssertTrue(Set(p.events.map(\.value)).isSubset(of: Set(values)))
                    XCTAssertTrue(p.events.contains { $0.value == values.last }, "practises the tier's newest value")
                    // Durations fill the bars exactly.
                    XCTAssertEqual(p.events.map(\.value.beats).reduce(0, +), Double(bars * 4))
                    // No two quarter rests in a row.
                    let rests = p.events.filter { $0.value == .quarterRest }.map(\.beat)
                    for r in rests { XCTAssertFalse(rests.contains(r + 1)) }
                    // Eighths only ever sit in beat-long pairs.
                    for e in p.events where e.value.beats == 0.5 {
                        let partner = e.beat.truncatingRemainder(dividingBy: 1) == 0 ? e.beat + 0.5 : e.beat - 0.5
                        XCTAssertTrue(p.events.contains { $0.beat == partner && $0.value.beats == 0.5 })
                    }
                }
            }
        }
    }

    func testSameSeedSamePattern() {
        var a = SplitMix64(seed: 7), b = SplitMix64(seed: 7)
        XCTAssertEqual(RhythmPattern.generate(values: [.quarter, .eighth], bars: 2, using: &a),
                       RhythmPattern.generate(values: [.quarter, .eighth], bars: 2, using: &b))
    }

    private var sample: RhythmPattern {
        // | q  8 8  qr  q |
        RhythmPattern(events: [
            RhythmEvent(value: .quarter, beat: 0), RhythmEvent(value: .eighth, beat: 1), RhythmEvent(value: .eighth, beat: 1.5),
            RhythmEvent(value: .quarterRest, beat: 2), RhythmEvent(value: .quarter, beat: 3),
        ], beats: 4)
    }

    func testCleanPatternOnTime() {
        let judge = TimingJudge(band: .explorers)
        let start = 2.4, spb = 0.6
        let taps = [0, 1, 1.5, 3].map { start + $0 * spb + 0.03 }
        let r = PatternResult.judge(taps: taps, pattern: sample, start: start, secondsPerBeat: spb, judge: judge)
        XCTAssertEqual(sample.onsets, [0, 1, 1.5, 3])
        XCTAssertTrue(r.isClean)
    }

    func testTapOnRestOrMissedNoteIsNotClean() {
        let judge = TimingJudge(band: .makers)
        let start = 0.0, spb = 0.6
        let onTime = [0, 1, 1.5, 3].map { start + $0 * spb }
        let tapOnRest = PatternResult.judge(taps: onTime + [2 * spb], pattern: sample, start: start, secondsPerBeat: spb, judge: judge)
        XCTAssertEqual(tapOnRest.extraTaps, 1)
        XCTAssertFalse(tapOnRest.isClean)

        let missed = PatternResult.judge(taps: Array(onTime.dropLast()), pattern: sample, start: start, secondsPerBeat: spb, judge: judge)
        XCTAssertEqual(missed.extraTaps, 0)
        XCTAssertFalse(missed.isClean)
    }

    func testAttemptsRetryThenSlowThenMoveOn() {
        var a = WaveRiderAttempts()
        XCTAssertEqual(a.record(clean: false), .retry(slower: false))
        XCTAssertEqual(a.record(clean: false), .retry(slower: true))
        XCTAssertEqual(a.record(clean: false), .done(correct: false))

        var b = WaveRiderAttempts()
        XCTAssertEqual(b.record(clean: false), .retry(slower: false))
        XCTAssertEqual(b.record(clean: true), .done(correct: true), "clean on the second try still counts")

        var c = WaveRiderAttempts()
        _ = c.record(clean: false); _ = c.record(clean: false)
        XCTAssertEqual(c.record(clean: true), .done(correct: false), "cleaned only after the slow replay")
    }
}
