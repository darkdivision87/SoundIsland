import XCTest
@testable import GameKitCore

final class NarrationTests: XCTestCase {
    func testSpeaksNewLinesAndSkipsQuickRepeats() {
        var p = NarrationPolicy(repeatCooldown: 8)
        XCTAssertEqual(p.lineToSpeak("Tap on every beat!", at: 0), "Tap on every beat!")
        XCTAssertNil(p.lineToSpeak("Tap on every beat!", at: 3), "re-render of the same line stays quiet")
        XCTAssertEqual(p.lineToSpeak("Tap on every beat!", at: 9), "Tap on every beat!", "after the cooldown it repeats")
        XCTAssertEqual(p.lineToSpeak("You kept the beat!", at: 10), "You kept the beat!")
        XCTAssertEqual(p.lineToSpeak("Tap on every beat!", at: 11), "Tap on every beat!", "a different line resets")
    }

    func testReplayAlwaysSpeaks() {
        var p = NarrationPolicy()
        _ = p.lineToSpeak("Who's playing?", at: 0)
        XCTAssertEqual(p.lineToSpeak("Who's playing?", at: 0.5, replay: true), "Who's playing?")
    }

    func testSpokenTextTidiesCopy() {
        XCTAssertEqual(NarrationPolicy.spokenText("Listen to the beat..."), "Listen to the beat")
        XCTAssertEqual(NarrationPolicy.spokenText("Tap an island\nto play!"), "Tap an island to play!")
        XCTAssertNil({ var p = NarrationPolicy(); return p.lineToSpeak("  ...  ", at: 0) }())
    }
}
