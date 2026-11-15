import AVFoundation
import Atomics
import Foundation

/// 4 rows x 16 steps of drum triggers as bitmasks. Bitwise-copyable on purpose.
public struct DrumMasks: BitwiseCopyable, Sendable, Equatable {
    public var kick: UInt16, snare: UInt16, hat: UInt16, clap: UInt16
    public init(kick: UInt16 = 0, snare: UInt16 = 0, hat: UInt16 = 0, clap: UInt16 = 0) {
        self.kick = kick; self.snare = snare; self.hat = hat; self.clap = clap
    }
}

/// Commands from the UI to the render thread. Trivial enum: no payload needs ARC.
public enum AudioCommand: BitwiseCopyable, Sendable {
    case noteOn(midi: UInt8, velocity: Float, instrument: Instrument)
    case noteOff(midi: UInt8)
    case drum(DrumSound, velocity: Float)
    case setDrumPattern(DrumMasks)
    case setTempo(Double)
    case setKit(UInt8)
    case setMasterGain(Float)
    /// Start the transport. `metronome` adds a click on every quarter note (Crab Tap, Wave Rider).
    case play(metronome: Bool, playPattern: Bool)
    case stop
    case allNotesOff
}

/// Owns AVAudioEngine and the real-time renderer.
/// All public methods are called from the main thread; they only enqueue commands.
public final class AudioEngine: @unchecked Sendable {
    public static let shared = AudioEngine()

    public let sampleRate: Double = 48_000
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let commands = SPSCQueue<AudioCommand>(capacity: 512)
    private let renderer: Renderer
    private var observers: [NSObjectProtocol] = []

    /// Extra latency compensation in seconds, measured with the latency rig (spec section 13).
    /// Added on top of the session's reported output latency when judging taps.
    public var calibrationOffset: Double = 0

    public private(set) var isRunning = false

    private init() {
        renderer = Renderer(sampleRate: Float(sampleRate))
    }

    // MARK: Lifecycle

    public func start() throws {
        guard !isRunning else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(128.0 / sampleRate) // about 2.7 ms
        try session.setActive(true)
        observeSession()
        #endif

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let renderer = self.renderer
        let commands = self.commands
        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, ablPointer -> OSStatus in
            renderer.render(
                frames: Int(frameCount),
                hostTime: timestamp.pointee.mHostTime,
                abl: UnsafeMutableAudioBufferListPointer(ablPointer),
                commands: commands
            )
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func shutdown() {
        engine.stop()
        isRunning = false
    }

    #if os(iOS)
    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.send(.stop)
                self.send(.allNotesOff)
            case .ended:
                try? AVAudioSession.sharedInstance().setActive(true)
                try? self.engine.start()
            @unknown default:
                break
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            if reason == .oldDeviceUnavailable { self.send(.stop) } // headphones unplugged: stop, kid-safe
        })
    }
    #endif

    // MARK: Commands

    public func send(_ command: AudioCommand) { commands.push(command) }

    public func playNote(_ midi: Int, velocity: Float = 0.8, instrument: Instrument = .marimba) {
        send(.noteOn(midi: UInt8(clamping: midi), velocity: velocity, instrument: instrument))
    }

    public func playChord(_ midis: [Int], velocity: Float = 0.6, instrument: Instrument = .softPiano) {
        for m in midis { playNote(m, velocity: velocity, instrument: instrument) }
    }

    public func playDrum(_ sound: DrumSound, velocity: Float = 0.9) { send(.drum(sound, velocity: velocity)) }

    /// Quiet mode (parent setting) = -10 dB.
    public func setQuietMode(_ on: Bool) { send(.setMasterGain(on ? 0.316 : 1)) }

    // MARK: Clock (read from the UI)

    /// Total 16th-note steps played since the transport started, or -1 when stopped.
    public var stepCount: Int { renderer.stepCount.load(ordering: .relaxed) }
    public var currentStep: Int? { let s = stepCount; return s < 0 ? nil : s % 16 }
    public var isPlaying: Bool { renderer.playing.load(ordering: .relaxed) }

    /// Beat (quarter-note) times since transport start, in seconds on the audio timeline.
    /// Games poll this each frame and append new beats; robust to tempo changes mid-round.
    public func latestBeat() -> (index: Int, seconds: Double)? {
        let (index, sample) = renderer.lastBeat.read()
        guard index >= 0 else { return nil }
        let start = renderer.transportStartSample.load(ordering: .relaxed)
        return (index, Double(sample - start) / sampleRate)
    }

    /// Converts a touch's host time (UITouch.timestamp / CACurrentMediaTime, seconds) to the audio
    /// timeline the beats live on, compensating output latency so taps are judged against what was HEARD.
    public func transportSeconds(forHostSeconds hostSeconds: Double) -> Double {
        let (renderSample, renderHostTicks) = renderer.renderClock.read()
        let renderHostSeconds = AudioEngine.seconds(fromHostTicks: UInt64(renderHostTicks))
        var latency = calibrationOffset
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        latency += s.outputLatency + s.ioBufferDuration
        #endif
        let sampleAtTouch = Double(renderSample) + (hostSeconds - renderHostSeconds) * sampleRate - latency * sampleRate
        let start = Double(renderer.transportStartSample.load(ordering: .relaxed))
        return (sampleAtTouch - start) / sampleRate
    }

    nonisolated(unsafe) private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func seconds(fromHostTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}

/// Everything touched on the render thread. Preallocated; never allocates after init.
final class Renderer: @unchecked Sendable {
    static let maxVoices = 32

    let sampleRate: Float
    private let voices: UnsafeMutablePointer<Voice>
    private var limiter = Limiter()
    private var masterGain: Float = 1
    private var smoothedGain: Float = 1

    // Transport (render thread state)
    private var sampleTime: Int = 0
    private var isTransportRunning = false
    private var metronome = false
    private var playPattern = true
    private var tempo: Double = 96
    private var nextStepSample: Double = 0
    private var stepIndex = 0
    private var pattern = DrumMasks()
    private var kit = KitTuning.table[0]

    // Published to the UI
    let stepCount = ManagedAtomic<Int>(-1)
    let playing = ManagedAtomic<Bool>(false)
    let transportStartSample = ManagedAtomic<Int>(0)
    let lastBeat = SeqLockPair()      // (beat index, sample time)
    let renderClock = SeqLockPair()   // (sample time at buffer start, host ticks at buffer start)

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        voices = .allocate(capacity: Self.maxVoices)
        voices.initialize(repeating: Voice(), count: Self.maxVoices)
        limiter.configure(sampleRate: sampleRate)
        lastBeat.write(-1, 0)
    }

    deinit { voices.deallocate() }

    private var samplesPerStep: Double { Double(sampleRate) * 60 / (tempo * 4) }

    // MARK: Render

    func render(frames: Int, hostTime: UInt64, abl: UnsafeMutableAudioBufferListPointer, commands: SPSCQueue<AudioCommand>) {
        renderClock.write(sampleTime, Int(truncatingIfNeeded: hostTime))
        while let cmd = commands.pop() { apply(cmd) }

        guard abl.count > 0, let left = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil

        for i in 0..<frames {
            if isTransportRunning, Double(sampleTime) >= nextStepSample { fireStep() }

            var mix: Float = 0
            for v in 0..<Self.maxVoices where voices[v].kind != .off {
                mix += voices[v].nextSample(sampleRate: sampleRate)
            }
            smoothedGain += (masterGain - smoothedGain) * 0.001
            let out = limiter.process(mix * 0.5 * smoothedGain)
            left[i] = out
            right?[i] = out
            sampleTime += 1
        }
    }

    private func fireStep() {
        let step = stepIndex % 16
        if playPattern {
            if pattern.kick & (1 << UInt16(step)) != 0 { trigger(.kick, velocity: 0.95) }
            if pattern.snare & (1 << UInt16(step)) != 0 { trigger(.snare, velocity: 0.8) }
            if pattern.hat & (1 << UInt16(step)) != 0 { trigger(.hat, velocity: step % 4 == 0 ? 0.55 : 0.4) }
            if pattern.clap & (1 << UInt16(step)) != 0 { trigger(.clap, velocity: 0.75) }
        }
        if step % 4 == 0 {
            let beat = stepIndex / 4
            if metronome { trigger(beat % 4 == 0 ? .accentClick : .click, velocity: 0.7) }
            lastBeat.write(beat, Int(nextStepSample.rounded()))
        }
        stepCount.store(stepIndex, ordering: .relaxed)
        stepIndex += 1
        nextStepSample += samplesPerStep
    }

    private func apply(_ cmd: AudioCommand) {
        switch cmd {
        case let .noteOn(midi, velocity, instrument):
            startTone(midi: midi, velocity: velocity, instrument: instrument)
        case let .noteOff(midi):
            for v in 0..<Self.maxVoices where voices[v].kind == .tone && voices[v].midi == midi { voices[v].releasing = true }
        case let .drum(sound, velocity):
            trigger(sound, velocity: velocity)
        case let .setDrumPattern(masks):
            pattern = masks
        case let .setTempo(bpm):
            // Keep phase: rescale time to the next step.
            let oldSPS = samplesPerStep
            tempo = min(max(bpm, 40), 200)
            if isTransportRunning {
                let remaining = (nextStepSample - Double(sampleTime)) / oldSPS
                nextStepSample = Double(sampleTime) + remaining * samplesPerStep
            }
        case let .setKit(index):
            kit = KitTuning.table[Int(index) % KitTuning.table.count]
        case let .setMasterGain(g):
            masterGain = g
        case let .play(metro, pat):
            metronome = metro
            playPattern = pat
            isTransportRunning = true
            stepIndex = 0
            nextStepSample = Double(sampleTime)
            transportStartSample.store(sampleTime, ordering: .relaxed)
            lastBeat.write(-1, sampleTime)
            playing.store(true, ordering: .relaxed)
        case .stop:
            isTransportRunning = false
            stepCount.store(-1, ordering: .relaxed)
            playing.store(false, ordering: .relaxed)
        case .allNotesOff:
            for v in 0..<Self.maxVoices { voices[v].releasing = true }
        }
    }

    /// Find a free voice, else steal the quietest one.
    private func allocateVoice() -> Int {
        var quietest = 0
        var quietestAmp = Float.greatestFiniteMagnitude
        for v in 0..<Self.maxVoices {
            if voices[v].kind == .off { return v }
            if voices[v].amp < quietestAmp { quietestAmp = voices[v].amp; quietest = v }
        }
        return quietest
    }

    private func startTone(midi: UInt8, velocity: Float, instrument: Instrument) {
        let i = allocateVoice()
        var v = Voice()
        v.kind = .tone
        v.instrument = instrument
        v.midi = midi
        v.frequency = 440 * powf(2, (Float(midi) - 69) / 12)
        v.velocity = velocity
        v.amp = 1
        v.attackSamples = Int(sampleRate * 0.003)
        let decaySeconds: Float
        switch instrument {
        case .marimba: decaySeconds = 0.6
        case .musicBox: decaySeconds = 1.2
        case .softPiano: decaySeconds = 1.6
        case .synthLead: decaySeconds = 0.9
        case .bass: decaySeconds = 0.7
        }
        v.decay = decayMultiplier(seconds: decaySeconds)
        v.noiseState = UInt32(truncatingIfNeeded: sampleTime) | 1
        voices[i] = v
    }

    private func trigger(_ sound: DrumSound, velocity: Float) {
        let i = allocateVoice()
        var v = Voice()
        v.velocity = velocity
        v.amp = 1
        v.attackSamples = Int(sampleRate * 0.001)
        v.noiseState = UInt32(truncatingIfNeeded: sampleTime &* 2_654_435_761) | 1
        switch sound {
        case .kick:
            v.kind = .kick
            v.frequency = kit.kickStartHz
            v.kickEndHz = kit.kickEndHz
            v.pitchEnv = 1
            v.decay = decayMultiplier(seconds: kit.kickDecay)
        case .snare:
            v.kind = .snare
            v.frequency = kit.snareToneHz
            v.noiseMix = kit.snareNoiseMix
            v.decay = decayMultiplier(seconds: 0.18)
        case .hat:
            v.kind = .hat
            v.decay = decayMultiplier(seconds: kit.hatDecay)
        case .clap:
            v.kind = .clap
            v.decay = decayMultiplier(seconds: kit.clapDecay)
        case .click:
            v.kind = .click
            v.frequency = 1_500
            v.decay = decayMultiplier(seconds: 0.03)
        case .accentClick:
            v.kind = .click
            v.frequency = 2_000
            v.decay = decayMultiplier(seconds: 0.04)
        }
        voices[i] = v
    }

    /// Per-sample multiplier that decays to -60 dB in `seconds`.
    private func decayMultiplier(seconds: Float) -> Float {
        powf(0.001, 1 / max(seconds * sampleRate, 1))
    }
}
