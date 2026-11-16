import XCTest
import Curriculum
@testable import GameKitCore

final class DrumCircleTests: XCTestCase {
    func testGeneratedPatternsFollowTheRules() {
        var rng = SplitMix64(seed: 3)
        for (beats, drums) in [(2, 1), (4, 2), (4, 3)] {
            for _ in 0..<300 {
                let p = DrumPattern.generate(beats: beats, drums: drums, allowEighths: drums == 3, using: &rng)
                XCTAssertEqual(p.hits.first?.beat, 0, "hit on the first downbeat")
                XCTAssertEqual(Set(p.hits.map(\.drum)), Set(0..<drums), "every pad used")
                XCTAssertTrue(p.hits.allSatisfy { $0.beat >= 0 && $0.beat < Double(beats) })
                let downbeats = Set(p.hits.map { $0.beat.rounded(.down) })
                XCTAssertGreaterThanOrEqual(downbeats.count, beats - 1, "at most one silent beat")
                if beats == 2 { XCTAssertEqual(downbeats.count, 2) }
                for h in p.hits where h.beat.truncatingRemainder(dividingBy: 1) != 0 {
                    XCTAssertTrue(p.hits.contains { $0.beat == h.beat - 0.5 }, "off-beat eighth has its pair")
                }
                if drums < 3 { XCTAssertTrue(p.hits.allSatisfy { $0.beat == $0.beat.rounded() }) }
            }
        }
    }

    func testStepMasks() {
        let p = DrumPattern(hits: [DrumHit(beat: 0, drum: 0), DrumHit(beat: 1.5, drum: 1), DrumHit(beat: 3, drum: 0)], beats: 4, drums: 2)
        XCTAssertEqual(p.stepMasks, [1 << 0 | 1 << 12, 1 << 6])
    }

    private let pattern = DrumPattern(hits: [DrumHit(beat: 0, drum: 0), DrumHit(beat: 1, drum: 1),
                                             DrumHit(beat: 1.5, drum: 1), DrumHit(beat: 3, drum: 2)], beats: 4, drums: 3)

    func testCleanCopy() {
        let start = 4.8, spb = 0.6
        let taps = pattern.hits.map { (seconds: start + $0.beat * spb + 0.05, drum: $0.drum) }
        let r = CopyResult.judge(taps: taps, pattern: pattern, start: start, secondsPerBeat: spb, judge: TimingJudge(band: .makers))
        XCTAssertTrue(r.isClean)
        XCTAssertEqual(r.accuracy, 1)
    }

    func testWrongPadOrExtraTapIsNotClean() {
        let start = 0.0, spb = 0.6, judge = TimingJudge(band: .explorers)
        var taps = pattern.hits.map { (seconds: start + $0.beat * spb, drum: $0.drum) }
        taps[3].drum = 0
        let wrongPad = CopyResult.judge(taps: taps, pattern: pattern, start: start, secondsPerBeat: spb, judge: judge)
        XCTAssertEqual(wrongPad.hitCount, 3)
        XCTAssertEqual(wrongPad.extraTaps, 1)
        XCTAssertFalse(wrongPad.isClean)

        let onTime = pattern.hits.map { (seconds: start + $0.beat * spb, drum: $0.drum) }
        let extra = CopyResult.judge(taps: onTime + [(seconds: 2 * spb, drum: 0)], pattern: pattern, start: start,
                                     secondsPerBeat: spb, judge: judge)
        XCTAssertFalse(extra.isClean)
    }

    func testQuantizeSnapsToEighthsAndDropsOutsideBar() {
        let start = 10.0, spb = 0.5
        let taps: [(seconds: Double, drum: Int)] = [
            (10.02, 0), (10.27, 1), (10.26, 1), (11.48, 2), (9.0, 0), (12.3, 0), (10.5, 7),
        ]
        let p = DrumPattern.quantize(taps: taps, start: start, secondsPerBeat: spb, beats: 4, drums: 3)
        XCTAssertEqual(p.hits, [DrumHit(beat: 0, drum: 0), DrumHit(beat: 0.5, drum: 1), DrumHit(beat: 3, drum: 2)])
    }
}
