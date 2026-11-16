import XCTest
@testable import MusicTheory
@testable import GameKitCore
@testable import Curriculum
@testable import StudioModel

final class MusicTheoryTests: XCTestCase {
    func testPitchBasics() {
        XCTAssertEqual(Pitch(.c, octave: 4).midi, 60)
        XCTAssertEqual(Pitch(midi: 69).name, "A4")
        XCTAssertEqual(Pitch(midi: 69).frequency, 440, accuracy: 0.0001)
        XCTAssertEqual(Pitch(midi: 81).frequency, 880, accuracy: 0.001)
        XCTAssertEqual(PitchClass(semitones: -1), .b)
        XCTAssertEqual(PitchClass.cSharp.colorParent, .c)
        XCTAssertEqual(PitchClass.e.semitones(upTo: .c), 8)
    }

    func testIntervals() {
        XCTAssertTrue(Interval.majorSecond.isStep)
        XCTAssertFalse(Interval.majorThird.isStep)
        XCTAssertEqual(Interval.between(Pitch(midi: 60), Pitch(midi: 67)), .perfectFifth)
        XCTAssertEqual(Interval.octave.shortName, "octave")
    }

    func testScales() {
        XCTAssertEqual(Scale(tonic: .c, type: .major).pitchClasses, [.c, .d, .e, .f, .g, .a, .b])
        XCTAssertEqual(Scale(tonic: .g, type: .major).pitchClasses, [.g, .a, .b, .c, .d, .e, .fSharp])
        XCTAssertEqual(Scale(tonic: .a, type: .naturalMinor).pitchClasses, [.a, .b, .c, .d, .e, .f, .g])
        XCTAssertEqual(Scale(tonic: .c, type: .majorPentatonic).pitchClasses, [.c, .d, .e, .g, .a])
        XCTAssertEqual(Scale(tonic: .c, type: .major).degree(of: .g), 5)
        XCTAssertEqual(Scale(tonic: .c, type: .major).pitches(fromOctave: 4, count: 8).last?.midi, 72)
        // Scale lock: C# snaps down to C in C major; F# (tie between F and G) snaps down to F.
        XCTAssertEqual(Scale(tonic: .c, type: .major).snap(Pitch(midi: 61)).midi, 60)
        XCTAssertEqual(Scale(tonic: .c, type: .major).snap(Pitch(midi: 66)).midi, 65)
    }

    func testTriads() {
        let c = Triad(root: .c, quality: .major)
        XCTAssertEqual(c.pitchClasses, [.c, .e, .g])
        XCTAssertEqual(c.pitches().map(\.midi), [60, 64, 67])
        XCTAssertEqual(Triad(root: .a, quality: .minor).symbol, "Am")
        XCTAssertEqual(Triad.identify([.e, .g, .c]), c)
        XCTAssertEqual(Triad.identify([.a, .c, .e]), Triad(root: .a, quality: .minor))
        XCTAssertNil(Triad.identify([.c, .d, .e]))
        XCTAssertEqual(c.pitchClass(for: .fifth), .g)
        XCTAssertEqual(c.quality.mood, .sunny)
    }

    func testDiatonicTriadsAndRomanNumerals() {
        let k = Key.sunnyC
        XCTAssertEqual(k.diatonicTriads.map(\.symbol), ["C", "Dm", "Em", "F", "G", "Am", "Bdim"])
        XCTAssertEqual((1...7).map(k.romanNumeral(degree:)), ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
        XCTAssertEqual(Key.brightG.diatonicTriad(degree: 5).symbol, "D")
        XCTAssertEqual(Key.warmF.diatonicTriad(degree: 4).symbol, "A#") // spelled Bb in flat keys
        XCTAssertEqual(Key.moonlightAMinor.romanNumeral(degree: 1), "i")
        XCTAssertEqual(Key.moonlightAMinor.romanNumeral(degree: 3), "III")
    }
}

final class TimingJudgeTests: XCTestCase {
    func testWindowsByBand() {
        let beats = [0.0, 0.5, 1.0, 1.5]
        let explorers = TimingJudge(band: .explorers)
        XCTAssertEqual(explorers.judge(tap: 0.61, targets: beats).grade, .great)   // 110 ms late
        let makers = TimingJudge(band: .makers)
        XCTAssertEqual(makers.judge(tap: 0.61, targets: beats).grade, .good)
        XCTAssertEqual(makers.judge(tap: 0.25, targets: beats).grade, .miss)
    }

    func testEarlyLateSign() {
        let j = TimingJudge(band: .explorers).judge(tap: 0.96, targets: [1.0])
        XCTAssertEqual(j.offset, -0.04, accuracy: 1e-9)
    }

    func testStreamCountsEachTargetOnce() {
        let beats = BeatSchedule.beats(count: 16, bpm: 120)
        XCTAssertEqual(beats[1], 0.5, accuracy: 1e-9)
        // Double-tapping every beat must not inflate accuracy above 100% or hit a target twice.
        let taps = beats.flatMap { [$0 + 0.01, $0 + 0.03] }
        let result = TimingJudge(band: .explorers).judgeStream(taps: taps, targets: beats)
        XCTAssertEqual(result.accuracy, 1.0)
        XCTAssertEqual(result.hitTargets.count, 16)
        XCTAssertEqual(result.judgments.filter { $0.targetIndex == nil }.count, 16)
    }

    func testTempoChangeSchedule() {
        let beats = BeatSchedule.beats(count: 4, bpm: 60, changeTo: 120)
        XCTAssertEqual(beats, [0, 1, 2, 2.5])
    }

    func testStars() {
        XCTAssertEqual(Stars.forAccuracy(0.5), 1)
        XCTAssertEqual(Stars.forAccuracy(0.7), 2)
        XCTAssertEqual(Stars.forAccuracy(0.95), 3)
    }

    func testRoundFlowHintsAndReward() {
        var flow = RoundFlow(totalRounds: 2)
        flow.startTrying()
        flow.miss(); XCTAssertFalse(flow.showGlowHint)
        flow.miss(); XCTAssertTrue(flow.showGlowHint)
        flow.miss(); XCTAssertTrue(flow.replaySlowerHint)
        flow.completeRound(correct: true)
        flow.next()
        XCTAssertEqual(flow.phase, .listen)
        XCTAssertEqual(flow.missesThisRound, 0)
        flow.startTrying(); flow.completeRound(correct: true); flow.next()
        XCTAssertEqual(flow.phase, .reward(stars: 3))
    }
}

final class ChordChefTests: XCTestCase {
    func testTier1MissingFifth() {
        let rules = ChordChefRules(key: .sunnyC, tier: 1)
        for round in 0..<20 {
            let order = rules.order(round: round, seed: 42)
            XCTAssertEqual(order.needed, [.fifth])
            XCTAssertEqual(order.target.quality, .major)
            XCTAssertEqual(rules.check(order: order, added: [order.target.pitchClass(for: .fifth)]), .correct)
        }
    }

    func testOrderIndependentAndWrongNote() {
        let rules = ChordChefRules(key: .sunnyC, tier: 2)
        let order = ChordChefRules.Order(target: Triad(root: .c, quality: .major), given: [.root])
        XCTAssertEqual(rules.check(order: order, added: [.g, .e]), .correct)
        XCTAssertEqual(rules.check(order: order, added: [.g]), .needMore(1))
        XCTAssertEqual(rules.check(order: order, added: [.d]), .wrongNote(offered: .d, expected: .e, tone: .third))
    }

    func testDeterministicOrders() {
        let rules = ChordChefRules(tier: 3)
        XCTAssertEqual(rules.order(round: 3, seed: 7), rules.order(round: 3, seed: 7))
    }
}

final class CurriculumTests: XCTestCase {
    func testAdaptiveStepsUpAfterHighAccuracy() {
        var p = SkillProgress(skillID: "x")
        let ad = AdaptiveDifficulty()
        var last: TierChange = .stay
        for _ in 0..<5 { last = ad.record(correct: true, into: &p).change }
        XCTAssertEqual(last, .up)
        XCTAssertEqual(p.currentTier, 2)
    }

    func testAdaptiveStepsDownAndHintsAfterThreeLowRounds() {
        var p = SkillProgress(skillID: "x")
        p.currentTier = 2
        let ad = AdaptiveDifficulty()
        _ = ad.record(correct: false, into: &p)
        _ = ad.record(correct: false, into: &p)
        let r = ad.record(correct: false, into: &p)
        XCTAssertEqual(r.change, .down)
        XCTAssertTrue(r.addHint)
        XCTAssertEqual(p.currentTier, 1)
    }

    func testTierOneIsFloor() {
        var p = SkillProgress(skillID: "x")
        let ad = AdaptiveDifficulty()
        for _ in 0..<3 { _ = ad.record(correct: false, into: &p) }
        XCTAssertEqual(p.currentTier, 1)
    }

    func testMasteryAndSpacedRepetition() {
        var p = SkillProgress(skillID: "x")
        let rule = MasteryRule(correctOf: [4, 5], sessions: 2)
        MasteryEvaluator.endSession([true, true, true, true, false], rule: rule, sessionIndex: 1, progress: &p)
        XCTAssertFalse(p.isMastered)
        MasteryEvaluator.endSession([true, true, true, true, true], rule: rule, sessionIndex: 2, progress: &p)
        XCTAssertEqual(p.firstMasteredSession, 2)
        XCTAssertFalse(SpacedRepetition.isDueForReview(p, currentSession: 2))
        XCTAssertTrue(SpacedRepetition.isDueForReview(p, currentSession: 3))
        p.reviewsDone = 1
        XCTAssertFalse(SpacedRepetition.isDueForReview(p, currentSession: 4))
        XCTAssertTrue(SpacedRepetition.isDueForReview(p, currentSession: 5))
    }

    func testDecodesSpecJSONAndValidatesGraph() throws {
        let json = """
        {"schemaVersion": 1, "skills": [
          {"skillNode": "rhythm.quarter_notes", "island": "beat_beach", "concept": "Quarter notes", "ageBands": ["explorers"],
           "prereqs": [], "game": "wave_rider", "tiers": [{"tier": 1, "bpm": 72, "bars": 1, "values": ["q"], "notation": false}],
           "mastery": {"correctOf": [4, 5], "sessions": 2}, "studioContribution": null},
          {"skillNode": "rhythm.eighth_notes", "island": "beat_beach", "concept": "Eighth notes", "ageBands": ["explorers", "makers"],
           "prereqs": ["rhythm.quarter_notes"], "game": "wave_rider",
           "tiers": [{"tier": 1, "bpm": 72, "bars": 1, "values": ["q", "8"], "notation": false}],
           "mastery": {"correctOf": [4, 5], "sessions": 2}, "studioContribution": "beat_box.eighth_hats"}
        ]}
        """
        let content = try CurriculumContent.decode(Data(json.utf8))
        XCTAssertEqual(content.skills.count, 2)
        let tier = content.skill("rhythm.eighth_notes")!.tier(1)
        XCTAssertEqual(tier.int("bpm", default: 0), 72)
        XCTAssertEqual(tier.strings("values"), ["q", "8"])
        XCTAssertFalse(tier.bool("notation", default: true))
    }

    func testCycleDetected() {
        let a = SkillNode(skillNode: "a", island: .beatBeach, concept: "", ageBands: [], prereqs: ["b"], game: "g",
                          tiers: [TierSpec(tier: 1, params: [:])], mastery: MasteryRule(correctOf: [1, 1], sessions: 1), studioContribution: nil)
        let b = SkillNode(skillNode: "b", island: .beatBeach, concept: "", ageBands: [], prereqs: ["a"], game: "g",
                          tiers: [TierSpec(tier: 1, params: [:])], mastery: MasteryRule(correctOf: [1, 1], sessions: 1), studioContribution: nil)
        XCTAssertThrowsError(try CurriculumContent(schemaVersion: 1, skills: [a, b]).validate())
    }

    func testAgeBands() {
        XCTAssertEqual(AgeBand.forAge(6), .explorers)
        XCTAssertEqual(AgeBand.forAge(7), .explorers)
        XCTAssertEqual(AgeBand.forAge(8), .makers)
        XCTAssertEqual(AgeBand.forAge(10), .makers)
        XCTAssertEqual(AgeBand.explorers.minTouchTarget, 64)
        XCTAssertEqual(AgeBand.makers.studioSteps, 16)
    }
}

final class StudioModelTests: XCTestCase {
    func testBeatGridToggle() {
        var g = BeatGrid.empty
        g.toggle(.kick, step: 0)
        g.toggle(.kick, step: 15)
        XCTAssertTrue(g.isOn(.kick, step: 0))
        XCTAssertTrue(g.isOn(.kick, step: 15))
        g.toggle(.kick, step: 0)
        XCTAssertFalse(g.isOn(.kick, step: 0))
    }

    func testSurpriseAlwaysHasBackbeat() {
        var rng = SplitMix64(seed: 1)
        for _ in 0..<50 {
            let g = BeatGrid.surprise(using: &rng)
            XCTAssertTrue(g.isOn(.kick, step: 0))
            XCTAssertTrue(g.isOn(.snare, step: 4))
            XCTAssertTrue(g.isOn(.snare, step: 12))
        }
    }

    func testSongLimits() {
        var s = Song()
        s.setTempo(500)
        XCTAssertEqual(s.tempo, 130)
        XCTAssertTrue(s.addSection())
        XCTAssertTrue(s.addSection())
        XCTAssertTrue(s.addSection())
        XCTAssertFalse(s.addSection())
        XCTAssertEqual(s.sections.map(\.name), ["A", "B", "C", "D"])
    }
}
