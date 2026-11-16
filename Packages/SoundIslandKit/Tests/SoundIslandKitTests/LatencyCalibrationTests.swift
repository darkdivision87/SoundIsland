import XCTest
@testable import GameKitCore

final class LatencyCalibrationTests: XCTestCase {
    private let clicks = (0..<16).map { Double($0) * 0.6 } // 100 BPM

    func testSteadyLateTapperMeasuresTheirLag() throws {
        let taps = clicks.enumerated().map { i, c in c + 0.030 + (i.isMultiple(of: 2) ? 0.004 : -0.004) }
        let m = try XCTUnwrap(LatencyCalibration.measure(taps: taps, clicks: clicks))
        XCTAssertEqual(m.pairedTaps, 16)
        XCTAssertEqual(m.inlierTaps, 16)
        XCTAssertEqual(m.meanOffset, 0.030, accuracy: 1e-9)
        XCTAssertEqual(m.spread, 0.004, accuracy: 1e-9)
        XCTAssertTrue(m.isReliable)
    }

    func testOutliersAndStrayTapsAreIgnored() throws {
        var taps = clicks.map { $0 + 0.020 }
        taps[3] += 0.15          // lapse: still pairs, but far from the median
        taps.append(clicks[5] + 0.3) // halfway between clicks: no pairing
        taps.append(clicks[7] + 0.05) // double tap on one click: the closer tap wins
        let m = try XCTUnwrap(LatencyCalibration.measure(taps: taps, clicks: clicks))
        XCTAssertEqual(m.pairedTaps, 16)
        XCTAssertEqual(m.inlierTaps, 15)
        XCTAssertEqual(m.meanOffset, 0.020, accuracy: 1e-9)
        XCTAssertEqual(m.medianOffset, 0.020, accuracy: 1e-9)
    }

    func testTooFewOrUnsteadyTapsAreNotReliable() throws {
        let few = try XCTUnwrap(LatencyCalibration.measure(taps: Array(clicks.prefix(5)), clicks: clicks))
        XCTAssertFalse(few.isReliable)

        let wobbly = clicks.enumerated().map { i, c in c + (i.isMultiple(of: 2) ? 0.05 : -0.05) }
        let m = try XCTUnwrap(LatencyCalibration.measure(taps: wobbly, clicks: clicks))
        XCTAssertFalse(m.isReliable)
    }

    func testNoPairingReturnsNil() {
        XCTAssertNil(LatencyCalibration.measure(taps: [], clicks: clicks))
        XCTAssertNil(LatencyCalibration.measure(taps: [100], clicks: clicks))
    }

    func testSuggestedOffsetAccumulatesAndClamps() throws {
        let m = try XCTUnwrap(LatencyCalibration.measure(taps: clicks.map { $0 + 0.02 }, clicks: clicks))
        XCTAssertEqual(LatencyCalibration.suggestedOffset(current: 0.01, measurement: m), 0.03, accuracy: 1e-9)
        XCTAssertEqual(LatencyCalibration.suggestedOffset(current: 0.24, measurement: m), 0.25, accuracy: 1e-9)

        let early = try XCTUnwrap(LatencyCalibration.measure(taps: clicks.map { $0 - 0.04 }, clicks: clicks))
        XCTAssertEqual(LatencyCalibration.suggestedOffset(current: -0.03, measurement: early), -0.05, accuracy: 1e-9)
    }

    func testTapToSoundUsesMedianAndDropsGarbage() throws {
        let est = try XCTUnwrap(LatencyCalibration.tapToSound(touchToRender: [0.004, 0.006, 0.005, -1, 2], outputLatency: 0.008))
        XCTAssertEqual(est, 0.013, accuracy: 1e-9)
        XCTAssertLessThan(est, LatencyCalibration.tapToSoundBudget)
        XCTAssertNil(LatencyCalibration.tapToSound(touchToRender: [], outputLatency: 0.008))
    }
}
