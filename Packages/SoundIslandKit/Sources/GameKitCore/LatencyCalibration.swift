// Latency rig math (spec section 13). Pure logic so the rig screen stays thin and this stays tested.

import Foundation

/// Result of one latency-rig run: how far the player's taps landed from the clicks they heard.
public struct LatencyMeasurement: Sendable, Equatable {
    /// Taps that paired with a click (within `LatencyCalibration.pairingWindow`).
    public let pairedTaps: Int
    /// Paired taps close enough to the median to count (stray double-taps and lapses dropped).
    public let inlierTaps: Int
    /// Mean signed offset of the inliers in seconds. Positive = taps measured late.
    public let meanOffset: Double
    /// Median signed offset of all paired taps in seconds.
    public let medianOffset: Double
    /// Standard deviation of the inliers in seconds (how steady the tapper was).
    public let spread: Double

    /// Enough steady taps to trust the number.
    public var isReliable: Bool {
        inlierTaps >= LatencyCalibration.minimumTaps && spread <= LatencyCalibration.maximumSpread
    }
}

public enum LatencyCalibration {
    /// A tap further than this from every click is ignored (it was not an attempt at that click).
    public static let pairingWindow = 0.25
    /// Taps further than this from the median are treated as outliers.
    public static let inlierWindow = 0.06
    public static let minimumTaps = 8
    /// Above this the tapper was too unsteady for the mean to mean anything.
    public static let maximumSpread = 0.04
    /// Saved offsets are clamped to a plausible range so one bad run can't wreck judging.
    public static let offsetRange: ClosedRange<Double> = -0.05...0.25

    /// Pairs each tap with its nearest click (each click used at most once, closest tap wins)
    /// and summarises the signed offsets. Returns nil when no tap paired.
    public static func measure(taps: [Double], clicks: [Double]) -> LatencyMeasurement? {
        guard !taps.isEmpty, !clicks.isEmpty else { return nil }
        var best: [Int: Double] = [:] // click index -> offset of the closest tap
        for tap in taps {
            var nearest = 0
            for i in clicks.indices where abs(tap - clicks[i]) < abs(tap - clicks[nearest]) { nearest = i }
            let offset = tap - clicks[nearest]
            guard abs(offset) <= pairingWindow else { continue }
            if let existing = best[nearest], abs(existing) <= abs(offset) { continue }
            best[nearest] = offset
        }
        let offsets = best.values.sorted()
        guard !offsets.isEmpty else { return nil }

        let median = offsets.count.isMultiple(of: 2)
            ? (offsets[offsets.count / 2 - 1] + offsets[offsets.count / 2]) / 2
            : offsets[offsets.count / 2]
        let inliers = offsets.filter { abs($0 - median) <= inlierWindow }
        let mean = inliers.reduce(0, +) / Double(inliers.count)
        let variance = inliers.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(inliers.count)
        return LatencyMeasurement(
            pairedTaps: offsets.count,
            inlierTaps: inliers.count,
            meanOffset: mean,
            medianOffset: median,
            spread: variance.squareRoot()
        )
    }

    /// New `AudioEngine.calibrationOffset` after a run measured with `current` in effect.
    /// Taps measuring late by `m` mean the real path is `m` longer than assumed, so add it.
    public static func suggestedOffset(current: Double, measurement: LatencyMeasurement) -> Double {
        min(max(current + measurement.meanOffset, offsetRange.lowerBound), offsetRange.upperBound)
    }

    /// Tap-to-sound estimate: median touch-to-render time (touch timestamp to the host time of the
    /// buffer that rendered the tap's sound) plus the session's output latency. Budget: under 20 ms.
    public static func tapToSound(touchToRender: [Double], outputLatency: Double) -> Double? {
        let valid = touchToRender.filter { $0 >= 0 && $0 < 0.5 }.sorted()
        guard !valid.isEmpty else { return nil }
        let mid = valid.count / 2
        let median = valid.count.isMultiple(of: 2) ? (valid[mid - 1] + valid[mid]) / 2 : valid[mid]
        return median + outputLatency
    }

    public static let tapToSoundBudget = 0.020
}
