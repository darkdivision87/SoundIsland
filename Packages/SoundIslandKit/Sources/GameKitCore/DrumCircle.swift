// Drum Circle (Beat Beach): Bop plays a short pattern on up to 3 drum pads, the child copies it in the
// next bar, then makes one up for Bop to copy. Spec section 4. Tiers from skills.json: "beats" and "drums".

import Foundation

public struct DrumHit: Sendable, Equatable, Hashable {
    /// Beat position from the start of the bar, on an eighth-note grid.
    public let beat: Double
    /// Pad index, 0 ..< drums.
    public let drum: Int

    public init(beat: Double, drum: Int) {
        self.beat = beat
        self.drum = drum
    }
}

public struct DrumPattern: Sendable, Equatable {
    public let hits: [DrumHit]
    public let beats: Int
    public let drums: Int

    public init(hits: [DrumHit], beats: Int, drums: Int) {
        self.hits = hits.sorted { ($0.beat, $0.drum) < ($1.beat, $1.drum) }
        self.beats = beats
        self.drums = drums
    }

    /// 16-step (sixteenth note) bitmask per pad, for the audio sequencer.
    public var stepMasks: [UInt16] {
        var masks = Array(repeating: UInt16(0), count: max(drums, 1))
        for h in hits {
            let step = Int((h.beat * 4).rounded())
            guard (0..<16).contains(step), masks.indices.contains(h.drum) else { continue }
            masks[h.drum] |= 1 << UInt16(step)
        }
        return masks
    }

    /// Random pattern. Rules that keep it copyable for 6 to 10 year olds: a hit on the first downbeat,
    /// eighths only as a beat-long pair, at most one silent beat (never the first, never in 2-beat
    /// patterns), every pad used at least once, and eighth pairs only once there are 2+ beats to hold them.
    public static func generate(beats: Int, drums: Int, allowEighths: Bool,
                                using rng: inout some RandomNumberGenerator) -> DrumPattern {
        let beats = min(max(beats, 1), 4), drums = min(max(drums, 1), 3)
        for _ in 0..<64 {
            var hits: [DrumHit] = []
            var rests = 0
            for b in 0..<beats {
                let roll = Int.random(in: 0..<10, using: &rng)
                let canRest = b > 0 && beats > 2 && rests == 0
                if canRest && roll == 0 { rests += 1; continue }
                let d = Int.random(in: 0..<drums, using: &rng)
                hits.append(DrumHit(beat: Double(b), drum: d))
                if allowEighths && roll >= 7 {
                    let d2 = Int.random(in: 0..<drums, using: &rng)
                    hits.append(DrumHit(beat: Double(b) + 0.5, drum: d2))
                }
            }
            if Set(hits.map(\.drum)).count == drums { return DrumPattern(hits: hits, beats: beats, drums: drums) }
        }
        // Fallback: walk the pads in order on each beat.
        let hits = (0..<beats).map { DrumHit(beat: Double($0), drum: $0 % drums) }
        return DrumPattern(hits: hits, beats: beats, drums: drums)
    }

    /// The child's own pattern: taps (seconds on the audio clock, with pad index) snapped to the
    /// eighth-note grid of a bar starting at `start`. Taps outside the bar are dropped; one hit per pad per slot.
    public static func quantize(taps: [(seconds: Double, drum: Int)], start: Double, secondsPerBeat: Double,
                                beats: Int, drums: Int) -> DrumPattern {
        var seen = Set<DrumHit>()
        var hits: [DrumHit] = []
        for t in taps {
            let slot = ((t.seconds - start) / secondsPerBeat * 2).rounded()
            guard slot >= 0, slot < Double(beats * 2), (0..<drums).contains(t.drum) else { continue }
            let hit = DrumHit(beat: slot / 2, drum: t.drum)
            if seen.insert(hit).inserted { hits.append(hit) }
        }
        return DrumPattern(hits: hits, beats: beats, drums: drums)
    }
}

/// How one copy attempt went. Each pad is judged on its own, so a tap on the wrong pad counts as an
/// extra tap and leaves Bop's hit unmatched.
public struct CopyResult: Sendable, Equatable {
    public let targetCount: Int
    public let hitCount: Int
    /// Taps that matched no hit on their pad.
    public let extraTaps: Int

    public var isClean: Bool { hitCount == targetCount && extraTaps == 0 }
    public var accuracy: Double { targetCount == 0 ? 0 : Double(hitCount) / Double(targetCount) }

    /// Copying is harder than tapping along, so the timing windows are 1.5x the age band's.
    public static let windowScale = 1.5

    /// Judges taps against `pattern` with its first beat at `start` (seconds on the audio clock).
    public static func judge(taps: [(seconds: Double, drum: Int)], pattern: DrumPattern, start: Double,
                             secondsPerBeat: Double, judge: TimingJudge) -> CopyResult {
        let loose = TimingJudge(greatWindow: judge.greatWindow * windowScale)
        var hits = 0, extras = 0
        let drums = Set(pattern.hits.map(\.drum)).union(taps.map(\.drum))
        for d in drums {
            let targets = pattern.hits.filter { $0.drum == d }.map { start + $0.beat * secondsPerBeat }
            let r = loose.judgeStream(taps: taps.filter { $0.drum == d }.map(\.seconds), targets: targets)
            hits += r.hitTargets.count
            extras += r.judgments.filter { $0.targetIndex == nil }.count
        }
        return CopyResult(targetCount: pattern.hits.count, hitCount: hits, extraTaps: extras)
    }
}
