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

/// One note or drum hit in the song loop (Studio tracks, Concert mode). Bitwise-copyable.
public struct NoteSlot: BitwiseCopyable, Sendable, Equatable {
    /// Sixteenth-note step within the loop.
    public var step: UInt16
    /// MIDI note, or DrumSound raw value when `instrument == NoteSlot.drum`.
    public var midi: UInt8
    /// Track index for gain: 0 beats, 1 bass, 2 chords, 3 melody.
    public var track: UInt8
    /// Instrument raw value, or `NoteSlot.drum`.
    public var instrument: UInt8
    public var velocity: Float

    public static let drum: UInt8 = 255

    public init(step: UInt16, midi: UInt8, track: UInt8, instrument: UInt8, velocity: Float) {
        self.step = step
        self.midi = midi
        self.track = track
        self.instrument = instrument
        self.velocity = velocity
    }
}

/// Master effect "stickers" (Mixer). Bits of `AudioCommand.setFX`.
public struct FXStickers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let echo = FXStickers(rawValue: 1 << 0)
    public static let underwater = FXStickers(rawValue: 1 << 1)
    public static let robot = FXStickers(rawValue: 1 << 2)
    public static let wobble = FXStickers(rawValue: 1 << 3)
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
    /// Play the drum pattern only on bars where `bar % period == phase` (call and response games).
    /// `.play` resets this to every bar, so send it after `.play`.
    case setPatternBars(period: UInt8, phase: UInt8)
    /// Song loop: remove every slot, add slots, set the loop length in sixteenth steps (0 turns slots off).
    case clearSlots
    case addSlot(NoteSlot)
    case setLoopSteps(UInt16)
    /// Track volume 0...1 (0 = muted). Applies to notes triggered from then on.
    case setTrackGain(track: UInt8, gain: Float)
    case setFX(UInt8)
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
    /// Large enough for a whole Concert-mode song (4 sections x 8 bars of slots) in one go.
    private let commands = SPSCQueue<AudioCommand>(capacity: 4096)
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

    /// Replaces the song loop. Main thread only; the render thread picks it up at the next buffer.
    public func loadLoop(_ slots: [NoteSlot], steps: Int) {
        send(.setLoopSteps(0))
        send(.clearSlots)
        for slot in slots.prefix(Renderer.maxSlots) { send(.addSlot(slot)) }
        send(.setLoopSteps(UInt16(clamping: steps)))
    }

    /// Quiet mode (parent setting) = -10 dB.
    public func setQuietMode(_ on: Bool) { send(.setMasterGain(on ? 0.316 : 1)) }

    // MARK: Clock (read from the UI)

    /// Total 16th-note steps played since the transport started, or -1 when stopped.
    public var stepCount: Int { renderer.stepCount.load(ordering: .relaxed) }
    public var currentStep: Int? { let s = stepCount; return s < 0 ? nil : s % 16 }
    public var isPlaying: Bool { renderer.playing.load(ordering: .acquiring) }

    /// Beat (quarter-note) times since transport start, in seconds on the audio timeline.
    /// Games poll this each frame and append new beats; robust to tempo changes mid-round.
    /// Returns nil while stopped, and until the render thread has actually started a newly requested
    /// transport, so a game restarting a round never sees the previous round's last beat.
    public func latestBeat() -> (index: Int, seconds: Double)? {
        guard isPlaying else { return nil }
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
        let latency = calibrationOffset + reportedOutputLatency
        let sampleAtTouch = Double(renderSample) + (hostSeconds - renderHostSeconds) * sampleRate - latency * sampleRate
        let start = Double(renderer.transportStartSample.load(ordering: .relaxed))
        return (sampleAtTouch - start) / sampleRate
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Output latency the session reports (hardware + one IO buffer), in seconds. 0 off iOS.
    public var reportedOutputLatency: Double {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        return s.outputLatency + s.ioBufferDuration
        #else
        return 0
        #endif
    }

    /// The audio buffer that rendered the most recent `.drum` command: a serial that increments per
    /// drum command, and that buffer's host time in seconds. The latency rig compares it with the
    /// touch timestamp to measure touch-to-render time (spec section 13).
    public func lastDrumRender() -> (serial: Int, hostSeconds: Double) {
        let (serial, ticks) = renderer.lastTrigger.read()
        return (serial, AudioEngine.seconds(fromHostTicks: UInt64(ticks)))
    }

    public static func seconds(fromHostTicks ticks: UInt64) -> Double {
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
    private var patternPeriod = 1
    private var patternPhase = 0

    // Song loop (preallocated; never grows on the audio thread)
    static let maxSlots = 2048
    private let slots: UnsafeMutablePointer<NoteSlot>
    private var slotCount = 0
    private var loopSteps = 0
    private var trackGain: (Float, Float, Float, Float) = (1, 1, 1, 1)

    // Master FX stickers
    private var fx: UInt8 = 0
    private let echoBuffer: UnsafeMutablePointer<Float>
    private let echoLength: Int
    private var echoIndex = 0
    private var lowpassState: Float = 0
    private var holdSample: Float = 0
    private var holdCounter = 0
    private var wobblePhase: Float = 0
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
    let lastTrigger = SeqLockPair()   // (drum command serial, host ticks of the buffer that rendered it)
    private var bufferHostTicks = 0
    private var triggerSerial = 0

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        voices = .allocate(capacity: Self.maxVoices)
        voices.initialize(repeating: Voice(), count: Self.maxVoices)
        slots = .allocate(capacity: Self.maxSlots)
        slots.initialize(repeating: NoteSlot(step: 0, midi: 0, track: 0, instrument: 0, velocity: 0), count: Self.maxSlots)
        echoLength = Int(sampleRate * 0.3)
        echoBuffer = .allocate(capacity: echoLength)
        echoBuffer.initialize(repeating: 0, count: echoLength)
        limiter.configure(sampleRate: sampleRate)
        lastBeat.write(-1, 0)
        lastTrigger.write(0, 0)
    }

    deinit {
        voices.deallocate()
        slots.deallocate()
        echoBuffer.deallocate()
    }

    private var samplesPerStep: Double { Double(sampleRate) * 60 / (tempo * 4) }

    // MARK: Render

    func render(frames: Int, hostTime: UInt64, abl: UnsafeMutableAudioBufferListPointer, commands: SPSCQueue<AudioCommand>) {
        bufferHostTicks = Int(truncatingIfNeeded: hostTime)
        renderClock.write(sampleTime, bufferHostTicks)
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
            if fx != 0 { mix = applyFX(mix) }
            let out = limiter.process(mix * 0.5 * smoothedGain)
            left[i] = out
            right?[i] = out
            sampleTime += 1
        }
    }

    private func fireStep() {
        let step = stepIndex % 16
        if playPattern, (stepIndex / 16) % patternPeriod == patternPhase {
            let g = trackGain.0
            if pattern.kick & (1 << UInt16(step)) != 0 { trigger(.kick, velocity: 0.95 * g) }
            if pattern.snare & (1 << UInt16(step)) != 0 { trigger(.snare, velocity: 0.8 * g) }
            if pattern.hat & (1 << UInt16(step)) != 0 { trigger(.hat, velocity: (step % 4 == 0 ? 0.55 : 0.4) * g) }
            if pattern.clap & (1 << UInt16(step)) != 0 { trigger(.clap, velocity: 0.75 * g) }
        }
        if loopSteps > 0 {
            let loopStep = UInt16(stepIndex % loopSteps)
            for i in 0..<slotCount where slots[i].step == loopStep {
                let s = slots[i]
                let v = s.velocity * gain(forTrack: s.track)
                guard v > 0 else { continue }
                if s.instrument == NoteSlot.drum {
                    if let d = DrumSound(rawValue: s.midi) { trigger(d, velocity: v) }
                } else {
                    startTone(midi: s.midi, velocity: v, instrument: Instrument(rawValue: s.instrument) ?? .marimba)
                }
            }
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
            triggerSerial &+= 1
            lastTrigger.write(triggerSerial, bufferHostTicks)
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
            patternPeriod = 1
            patternPhase = 0
            isTransportRunning = true
            stepIndex = 0
            nextStepSample = Double(sampleTime)
            transportStartSample.store(sampleTime, ordering: .relaxed)
            lastBeat.write(-1, sampleTime)
            playing.store(true, ordering: .releasing) // publishes the lastBeat reset above
        case .clearSlots:
            slotCount = 0
        case let .addSlot(slot):
            if slotCount < Self.maxSlots { slots[slotCount] = slot; slotCount += 1 }
        case let .setLoopSteps(n):
            loopSteps = Int(n)
        case let .setTrackGain(track, g):
            let v = min(max(g, 0), 1)
            switch track {
            case 0: trackGain.0 = v
            case 1: trackGain.1 = v
            case 2: trackGain.2 = v
            default: trackGain.3 = v
            }
        case let .setFX(mask):
            fx = mask
        case let .setPatternBars(period, phase):
            patternPeriod = max(1, Int(period))
            patternPhase = Int(phase) % patternPeriod
        case .stop:
            isTransportRunning = false
            stepCount.store(-1, ordering: .relaxed)
            playing.store(false, ordering: .releasing)
        case .allNotesOff:
            for v in 0..<Self.maxVoices { voices[v].releasing = true }
        }
    }

    @inline(__always)
    private func gain(forTrack t: UInt8) -> Float {
        switch t {
        case 0: trackGain.0
        case 1: trackGain.1
        case 2: trackGain.2
        default: trackGain.3
        }
    }

    /// Master FX stickers. Cheap, allocation-free, one sample at a time.
    @inline(__always)
    private func applyFX(_ input: Float) -> Float {
        var x = input
        if fx & FXStickers.underwater.rawValue != 0 {
            lowpassState += (x - lowpassState) * 0.06
            x = lowpassState * 1.4
        }
        if fx & FXStickers.robot.rawValue != 0 {
            if holdCounter == 0 { holdSample = (x * 12).rounded() / 12 }
            holdCounter = (holdCounter + 1) % 6
            x = holdSample
        }
        if fx & FXStickers.wobble.rawValue != 0 {
            wobblePhase += 5 / sampleRate
            if wobblePhase >= 1 { wobblePhase -= 1 }
            x *= 0.65 + 0.35 * sinf(2 * .pi * wobblePhase)
        }
        if fx & FXStickers.echo.rawValue != 0 {
            let delayed = echoBuffer[echoIndex]
            echoBuffer[echoIndex] = x + delayed * 0.35
            echoIndex = (echoIndex + 1) % echoLength
            x += delayed * 0.45
        }
        return x
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
