import Foundation

// Phase-1 sound source: everything is synthesized, so the vertical slice needs no sample assets.
// Phase 2 swaps ToneVoice for a sample-playback voice (SFZ-style mapping) behind the same Instrument IDs.

/// Melodic instruments available before real samples land.
public enum Instrument: UInt8, Sendable, CaseIterable, BitwiseCopyable {
    case marimba = 0, musicBox, softPiano, synthLead, bass
}

public enum DrumSound: UInt8, Sendable, CaseIterable, BitwiseCopyable {
    case kick = 0, snare, hat, clap, click, accentClick
}

/// Per-kit drum tuning. Index = DrumKit order in StudioModel (pop, hipHop, electronic, rock, silly, world).
struct KitTuning {
    var kickStartHz: Float
    var kickEndHz: Float
    var kickDecay: Float     // seconds
    var snareToneHz: Float
    var snareNoiseMix: Float
    var hatDecay: Float
    var clapDecay: Float

    static let table: [KitTuning] = [
        KitTuning(kickStartHz: 150, kickEndHz: 50, kickDecay: 0.35, snareToneHz: 190, snareNoiseMix: 0.7, hatDecay: 0.05, clapDecay: 0.18), // pop
        KitTuning(kickStartHz: 120, kickEndHz: 42, kickDecay: 0.55, snareToneHz: 170, snareNoiseMix: 0.8, hatDecay: 0.04, clapDecay: 0.22), // hip-hop
        KitTuning(kickStartHz: 180, kickEndHz: 48, kickDecay: 0.45, snareToneHz: 220, snareNoiseMix: 0.9, hatDecay: 0.03, clapDecay: 0.15), // electronic
        KitTuning(kickStartHz: 110, kickEndHz: 60, kickDecay: 0.28, snareToneHz: 200, snareNoiseMix: 0.6, hatDecay: 0.09, clapDecay: 0.2),  // rock
        KitTuning(kickStartHz: 400, kickEndHz: 90, kickDecay: 0.25, snareToneHz: 520, snareNoiseMix: 0.4, hatDecay: 0.06, clapDecay: 0.12), // silly
        KitTuning(kickStartHz: 95, kickEndHz: 70, kickDecay: 0.4, snareToneHz: 330, snareNoiseMix: 0.3, hatDecay: 0.07, clapDecay: 0.25),  // world
    ]
}

/// One synth voice. A plain struct living in a preallocated pool; no allocation when triggered.
struct Voice {
    enum Kind: UInt8 { case off, tone, kick, snare, hat, clap, click }

    var kind: Kind = .off
    var instrument: Instrument = .marimba
    var frequency: Float = 440
    var phase: Float = 0
    var phase2: Float = 0
    var amp: Float = 0
    var velocity: Float = 1
    var decay: Float = 0.9995        // per-sample multiplier
    var attackSamples: Int = 0
    var age: Int = 0
    var releasing = false
    var noiseState: UInt32 = 0x1234_5678
    var lpState: Float = 0
    var pitchEnv: Float = 0
    var kickEndHz: Float = 50
    var noiseMix: Float = 0.5
    var midi: UInt8 = 0

    @inline(__always)
    mutating func noise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    @inline(__always)
    mutating func nextSample(sampleRate: Float) -> Float {
        if kind == .off { return 0 }
        let twoPi: Float = 2 * .pi
        var out: Float = 0
        switch kind {
        case .tone:
            let inc = twoPi * frequency / sampleRate
            phase += inc; if phase > twoPi { phase -= twoPi }
            switch instrument {
            case .marimba:
                phase2 += inc * 4; if phase2 > twoPi { phase2 -= twoPi }
                out = sin(phase) + 0.25 * sin(phase2) * amp
            case .musicBox:
                phase2 += inc * 3; if phase2 > twoPi { phase2 -= twoPi }
                out = 0.7 * sin(phase) + 0.3 * sin(phase2)
            case .softPiano:
                phase2 += inc * 2; if phase2 > twoPi { phase2 -= twoPi }
                out = 0.75 * sin(phase) + 0.2 * sin(phase2) + 0.05 * sin(phase * 3)
            case .synthLead:
                // Band-limited-ish saw via a few harmonics.
                out = sin(phase) + 0.5 * sin(2 * phase) + 0.33 * sin(3 * phase) + 0.25 * sin(4 * phase)
                out *= 0.45
            case .bass:
                out = sin(phase) + 0.3 * sin(2 * phase)
                out *= 0.8
            }
        case .kick:
            // Exponential pitch sweep from start to end frequency.
            pitchEnv *= 0.9992
            let f = kickEndHz + (frequency - kickEndHz) * pitchEnv
            phase += twoPi * f / sampleRate; if phase > twoPi { phase -= twoPi }
            out = sin(phase)
        case .snare:
            phase += twoPi * frequency / sampleRate; if phase > twoPi { phase -= twoPi }
            out = (1 - noiseMix) * sin(phase) + noiseMix * noise()
        case .hat:
            // High-passed noise: noise minus its own one-pole low-pass.
            let n = noise()
            lpState += 0.25 * (n - lpState)
            out = (n - lpState) * 0.8
        case .clap:
            // Three quick bursts then a tail.
            let t = age
            let burst = (t < 300) || (t > 500 && t < 800) || (t > 1000)
            out = burst ? noise() * 0.9 : 0
        case .click:
            phase += twoPi * frequency / sampleRate; if phase > twoPi { phase -= twoPi }
            out = sin(phase)
        case .off:
            return 0
        }

        // Envelope: short linear attack, exponential decay, faster decay when released.
        let attack: Float = attackSamples > 0 && age < attackSamples ? Float(age) / Float(attackSamples) : 1
        amp *= releasing ? 0.9985 : decay
        age += 1
        if amp < 0.0001 { kind = .off; return 0 }
        return out * amp * attack * velocity
    }
}

/// Transparent safety limiter: ceiling -1 dBFS (spec), fast attack, 80 ms release.
struct Limiter {
    let ceiling: Float = 0.891
    var gain: Float = 1
    var releaseCoeff: Float = 0.9997

    mutating func configure(sampleRate: Float) {
        releaseCoeff = expf(-1 / (0.080 * sampleRate))
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let peak = abs(x) * gain
        if peak > ceiling {
            gain = ceiling / max(abs(x), 1e-9)
        } else {
            gain = 1 - (1 - gain) * releaseCoeff
        }
        return x * gain
    }
}
