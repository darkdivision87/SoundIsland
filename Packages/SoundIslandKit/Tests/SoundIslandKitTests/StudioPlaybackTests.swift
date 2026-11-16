import XCTest
import MusicTheory
@testable import StudioModel

final class StudioPlaybackTests: XCTestCase {
    private func section(melody: [NoteEvent] = [], bars: Int = 4) -> Section {
        var s = Section.blank(named: "A")
        s.bars = bars
        s.tracks[0].beatGrid = BeatGrid(kick: BeatGrid.mask([0, 8]))
        if let i = s.tracks.firstIndex(where: { $0.kind == .melody }) { s.tracks[i].notes = melody }
        return s
    }

    func testBeatsRepeatEveryBarAndShortMelodyRepeats() {
        let melody = [NoteEvent(tick: 0, pitch: Pitch(midi: 60), lengthTicks: 48),
                      NoteEvent(tick: 6 * ticksPerStep, pitch: Pitch(midi: 64), lengthTicks: 48)]
        let loop = section(melody: melody).playback()
        XCTAssertEqual(loop.steps, 64)
        XCTAssertEqual(loop.hits.filter { $0.track == .beats }.map(\.step), [0, 8, 16, 24, 32, 40, 48, 56])
        // 1-bar melody fills all 4 bars.
        XCTAssertEqual(loop.hits.filter { $0.track == .melody }.map(\.step), [0, 6, 16, 22, 32, 38, 48, 54])
    }

    func testTwoBarMelodyRepeatsTwiceAndMutedTracksAreSilent() {
        var s = section(melody: [NoteEvent(tick: 20 * ticksPerStep, pitch: Pitch(midi: 67), lengthTicks: 48)])
        XCTAssertEqual(s.playback().hits.filter { $0.track == .melody }.map(\.step), [20, 52])
        s.tracks[0].muted = true
        XCTAssertTrue(s.playback().hits.allSatisfy { $0.track != .beats })
        XCTAssertTrue(s.playback(includeBeats: false).hits.allSatisfy { $0.track != .beats })
    }

    func testRepeatLength() {
        XCTAssertEqual(Section.repeatLength(lastStep: 0, sectionSteps: 64), 16)
        XCTAssertEqual(Section.repeatLength(lastStep: 16, sectionSteps: 64), 32)
        XCTAssertEqual(Section.repeatLength(lastStep: 40, sectionSteps: 64), 64)
        XCTAssertEqual(Section.repeatLength(lastStep: 100, sectionSteps: 64), 64)
    }

    func testConcertPlaysTheArrangementInOrder() {
        var song = Song()
        song.sections[0] = section()
        XCTAssertTrue(song.duplicateSection(at: 0))
        song.sections[1].tracks[0].beatGrid = BeatGrid(snare: BeatGrid.mask([4]))
        song.appendPart(section: 0)
        XCTAssertEqual(song.arrangement, [0, 1, 0])
        let loop = song.concert()
        XCTAssertEqual(loop.steps, 192)
        XCTAssertEqual(loop.hits.first { $0.step >= 64 && $0.track == .beats }?.sound, .drum(.snare))
        XCTAssertEqual(loop.hits.first { $0.step >= 128 && $0.track == .beats }?.sound, .drum(.kick))
    }

    func testArrangementEdits() {
        var song = Song()
        XCTAssertFalse(song.removePart(0), "always keeps one part")
        song.duplicateSection(at: 0)
        XCTAssertEqual(song.sections.map(\.name), ["A", "B"])
        XCTAssertNotEqual(song.sections[0].id, song.sections[1].id)
        song.cycleArrangementSlot(1)
        XCTAssertEqual(song.arrangement, [0, 0])
        XCTAssertTrue(song.removePart(1))
        XCTAssertEqual(song.arrangement, [0])
        for _ in 0..<3 { song.duplicateSection(at: 0) }
        XCTAssertFalse(song.duplicateSection(at: 0), "4 sections max")
    }

    func testVoiceLeadingMovesLittle() {
        let key = Key.sunnyC
        let c = ChordVoicing.voiceLead(key.diatonicTriad(degree: 1), from: nil)
        XCTAssertEqual(c, [48, 52, 55])
        let f = ChordVoicing.voiceLead(key.diatonicTriad(degree: 4), from: [55, 60, 64])
        XCTAssertEqual(Set(f.map { $0 % 12 }), [5, 9, 0])
        XCTAssertTrue(f.allSatisfy { (52...67).contains($0) })
        let center = { (v: [Int]) in Double(v.reduce(0, +)) / 3 }
        XCTAssertLessThan(abs(center(f) - center([55, 60, 64])), 4)
    }

    func testRecordQuantizeSnapsToEighthsAndWraps() {
        let q = RecordQuantizer(secondsPerStep: 0.125, loopSteps: 32)
        XCTAssertEqual(q.step(at: 0.02), 0)
        XCTAssertEqual(q.step(at: 0.2), 2)
        XCTAssertEqual(q.step(at: 0.37), 2)
        XCTAssertEqual(q.step(at: 0.4), 4)
        XCTAssertEqual(q.step(at: 4.0), 0, "wraps at the loop end")
        var notes = RecordQuantizer.record(Pitch(midi: 60), step: 2, into: [])
        notes = RecordQuantizer.record(Pitch(midi: 60), step: 2, into: notes)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].tick, 2 * ticksPerStep)
    }

    func testMelodyGridRoundTrip() {
        var g = MelodyGrid(scale: Key.brightG.scale)
        XCTAssertEqual(g.rows.first?.name, "G4")
        g.toggle(column: 0, row: 0)
        g.toggle(column: 0, row: 2)
        g.toggle(column: 15, row: 7)
        g.toggle(column: 3, row: 1); g.toggle(column: 3, row: 1)
        let loaded = MelodyGrid(scale: Key.brightG.scale, notes: g.notes)
        XCTAssertEqual(loaded, g)
        XCTAssertEqual(g.notes.map(\.tick), [0, 0, 15 * 48])
    }
}

final class ChordLaneTests: XCTestCase {
    func testStylesAndRoundTrip() {
        let key = Key.sunnyC
        let block = ChordLane.events(degrees: [1, nil, 4, 5], key: key, style: .block)
        XCTAssertEqual(block.count, 9)
        XCTAssertEqual(Set(block.map(\.tick)), [0, 2 * 16 * ticksPerStep, 3 * 16 * ticksPerStep])
        XCTAssertEqual(ChordLane.degrees(from: block, key: key, bars: 4), [1, nil, 4, 5])

        let strum = ChordLane.events(degrees: [1], key: key, style: .strum)
        XCTAssertEqual(strum.map(\.tick), [0, 12, 24])
        let arp = ChordLane.events(degrees: [6], key: key, style: .arp)
        XCTAssertEqual(arp.count, 8)
        XCTAssertEqual(Set(arp.map(\.pitch.pitchClass)), [.a, .c, .e])
        XCTAssertEqual(ChordLane.degrees(from: arp, key: key, bars: 1), [6])
    }
}
