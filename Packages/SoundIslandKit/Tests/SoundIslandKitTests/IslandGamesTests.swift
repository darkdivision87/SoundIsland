import XCTest
import MusicTheory
@testable import GameKitCore

final class PitchGamesTests: XCTestCase {
    func testBirdSongAnswerIsTheRequestedBird() {
        var rng = SplitMix64(seed: 1)
        for interval in [12, 7, 2] {
            for _ in 0..<100 {
                let r = BirdSongRound.make(intervalSemitones: interval, using: &rng)
                XCTAssertEqual(r.high.midi - r.low.midi, interval)
                let chosen = r.birds[r.answer]
                XCTAssertEqual(chosen, r.askHigher ? r.high : r.low)
                XCTAssertTrue((60...67).contains(r.low.midi))
            }
        }
    }

    func testPitchClimbRoundsStayOnTheLadder() {
        var rng = SplitMix64(seed: 2)
        for mode in [ClimbMode.direction, .stepOrSkip, .exactRung] {
            var steps = 0
            for _ in 0..<200 {
                let r = PitchClimbRound.make(mode: mode, using: &rng)
                XCTAssertTrue((0...7).contains(r.target))
                XCTAssertNotEqual(r.start, r.target)
                XCTAssertTrue(r.options.contains(r.correct))
                XCTAssertLessThanOrEqual(r.options.count, 4, "Explorers see at most 4 choices")
                XCTAssertEqual(Set(r.options).count, r.options.count)
                if abs(r.target - r.start) == 1 { steps += 1 }
            }
            if mode == .stepOrSkip { XCTAssertGreaterThan(steps, 60, "plenty of steps as well as skips") }
        }
        XCTAssertEqual(PitchClimbRound.ladder.map(\.name), ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"])
        let r = PitchClimbRound(mode: .stepOrSkip, start: 2, target: 4, options: [])
        XCTAssertEqual(r.correct, .skipUp)
    }

    func testKeyHuntNeverRepeatsWhenItCan() {
        var rng = SplitMix64(seed: 3)
        let notes = KeyHunt.pitchClasses(["C", "D", "E"])
        XCTAssertEqual(notes, [.c, .d, .e])
        var prev: PitchClass?
        for _ in 0..<100 {
            let n = KeyHunt.next(from: notes, after: prev, using: &rng)
            XCTAssertNotEqual(n, prev)
            XCTAssertTrue(notes.contains(n))
            prev = n
        }
        XCTAssertEqual(KeyHunt.pitchClasses(["C#", "X"]), [.cSharp])
    }
}

final class MelodyGamesTests: XCTestCase {
    func testEchoPhrasesAreSingableAndEndHome() {
        var rng = SplitMix64(seed: 4)
        for (length, pads) in [(3, 5), (4, 7), (6, 7)] {
            for _ in 0..<200 {
                let p = EchoPhrase.make(length: length, padCount: pads, rhythm: length == 6, using: &rng)
                XCTAssertEqual(p.pads.count, length)
                XCTAssertEqual(p.pads.last, 0)
                XCTAssertTrue(p.pads.allSatisfy { (0..<pads).contains($0) })
                for i in 1..<p.pads.count where i < p.pads.count - 1 { XCTAssertLessThanOrEqual(abs(p.pads[i] - p.pads[i - 1]), 2) }
                XCTAssertNotEqual(p.pads[p.pads.count - 2], 0)
                XCTAssertEqual(p.beats.count, length)
            }
        }
    }

    func testEchoInputResetsOnWrongPad() {
        var input = EchoInput(phrase: EchoPhrase(pads: [2, 1, 0], beats: [1, 1, 1]))
        XCTAssertEqual(input.tap(2), .good)
        XCTAssertEqual(input.tap(3), .wrong(expected: 1))
        XCTAssertEqual(input.played, [])
        XCTAssertEqual(input.tap(2), .good)
        XCTAssertEqual(input.tap(1), .good)
        XCTAssertEqual(input.tap(0), .complete)
    }

    func testVineSwingOffersTheMissingNote() {
        var rng = SplitMix64(seed: 5)
        for scale in [Scale(tonic: .c, type: .majorPentatonic), Scale(tonic: .c, type: .major),
                      Scale(tonic: .g, type: .major), Scale(tonic: .f, type: .major)] {
            for _ in 0..<100 {
                let r = VineSwingRound.make(scale: scale, using: &rng)
                XCTAssertEqual(r.notes.count, scale.type.steps.count + 1)
                XCTAssertGreaterThan(r.missing, 0)
                XCTAssertEqual(r.options.count, 3)
                XCTAssertTrue(r.options.contains(r.answer))
                XCTAssertEqual(r.options, r.options.sorted())
                XCTAssertEqual(r.options.filter { $0.pitchClass == r.answer.pitchClass }.count, 1)
            }
        }
    }

    func testMelodyCanvas() {
        var c = MelodyCanvas(scale: Scale(tonic: .c, type: .major), columns: 8)
        XCTAssertEqual(c.rows.count, 8)
        c.toggle(column: 0, row: 2)
        c.toggle(column: 1, row: 4)
        XCTAssertEqual(c.readiness(requireHomeEnding: false), .needMoreNotes)
        c.toggle(column: 3, row: 5)
        XCTAssertEqual(c.readiness(requireHomeEnding: false), .ready)
        XCTAssertEqual(c.readiness(requireHomeEnding: true), .needHomeEnding)
        c.toggle(column: 5, row: 7) // top C
        XCTAssertTrue(c.endsOnHome)
        c.toggle(column: 5, row: 7) // erase
        XCTAssertEqual(c.noteCount, 3)
        c.toggle(column: 7, row: 0)
        XCTAssertEqual(c.readiness(requireHomeEnding: true), .ready)
        let events = c.noteEvents()
        XCTAssertEqual(events.map(\.tick), [0, 48, 144, 336])
        XCTAssertEqual(events.last?.pitch.name, "C4")
    }
}

final class HarmonyGamesTests: XCTestCase {
    func testMoodBoatsMaterialMatchesTheMood() {
        var rng = SplitMix64(seed: 6)
        for _ in 0..<100 {
            let triad = MoodBoatsRound.make(material: .triads, using: &rng)
            let pcs = Set(triad.steps[0].map { PitchClass(semitones: $0) })
            XCTAssertEqual(Triad.identify(pcs)?.quality.mood, triad.mood)

            let prog = MoodBoatsRound.make(material: .progressions, using: &rng)
            XCTAssertEqual(prog.steps.count, 4)
            XCTAssertEqual(Triad.identify(Set(prog.steps[0].map { PitchClass(semitones: $0) }))?.quality.mood, prog.mood)

            let mel = MoodBoatsRound.make(material: .melodies, using: &rng)
            XCTAssertEqual(mel.steps.count, 7)
            XCTAssertEqual(mel.steps[2][0] - mel.steps[0][0], mel.mood == .sunny ? 4 : 3, "the third decides")
        }
    }

    func testStackAttackProgressions() {
        var rng = SplitMix64(seed: 7)
        for length in [2, 4] {
            for _ in 0..<100 {
                let p = StackAttack.progression(length: length, using: &rng)
                XCTAssertEqual(p.count, length)
                XCTAssertEqual(p.first, 1)
                for i in 1..<p.count { XCTAssertNotEqual(p[i], p[i - 1]) }
                XCTAssertTrue(p.allSatisfy(StackAttack.blocks.contains))
            }
        }
        XCTAssertEqual(StackAttack.mismatches(placed: [1, 5, nil, 6], target: [1, 4, 5, 6]), [1, 2])
        XCTAssertEqual(StackAttack.mismatches(placed: [1, 4], target: [1, 4]), [])
    }
}

import Curriculum

final class TierSpecAccessorTests: XCTestCase {
    func testStringAccessor() {
        let t = TierSpec(tier: 2, params: ["mode": .string("stepOrSkip"), "n": .int(3)])
        XCTAssertEqual(t.string("mode", default: "direction"), "stepOrSkip")
        XCTAssertEqual(t.string("n", default: "x"), "x")
        XCTAssertEqual(t.string("missing", default: "direction"), "direction")
    }
}
