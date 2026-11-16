import SwiftUI
import Combine
import QuartzCore
import AudioCore
import Curriculum
import GameKitCore
import DesignSystem

/// Drum Circle (Beat Beach): call and response on up to 3 giant drum pads. Spec section 4.
/// The transport runs in bars: bar 0 is a count-in, then Bop plays on odd bars (the sequencer plays the
/// pattern sample-accurately) and the child copies on even bars. A copy that isn't clean just loops
/// into another listen bar (errorless). After 4 copies the child makes up a bar and Bop plays it back.
/// Taps are judged on the audio clock.
struct DrumCircleView: View {
    @Environment(AppModel.self) private var model

    private static let copies = 4
    private static let bpm: Double = 90
    private static let pads: [Pad] = [
        Pad(name: "Boom", sound: .kick, fill: Color(hex: 0xFF9A3C)),
        Pad(name: "Tak", sound: .snare, fill: Color(hex: 0x4FC3F7)),
        Pad(name: "Clap", sound: .clap, fill: Color(hex: 0x2ECC8F)),
    ]
    private static let padSize: CGFloat = 240
    private static let padY: CGFloat = 560

    struct Pad { let name: String; let sound: DrumSound; let fill: Color }

    private enum Stage: Equatable { case copying, between(String), creating, playback, done }

    @State private var flow = RoundFlow(totalRounds: DrumCircleView.copies)
    @State private var attempts = PatternAttempts()
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var pattern = DrumPattern(hits: [], beats: 2, drums: 1)
    @State private var stage = Stage.copying
    @State private var running = false
    @State private var lastBeatIndex = -1
    /// First bar the child copies in (2, 4, 6, ...).
    @State private var childBar = 2
    @State private var taps: [(seconds: Double, drum: Int)] = []
    @State private var created: [(seconds: Double, drum: Int)] = []
    @State private var tapLit: [Double] = [-1, -1, -1]
    @State private var lastResultClean: Bool?

    private let ticker = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect()

    private var tierSpec: TierSpec { model.skill(for: .drumCircle)?.tier(model.tier(for: .drumCircle)) ?? TierSpec(tier: 1, params: [:]) }
    private var drumCount: Int { min(max(tierSpec.int("drums", default: 1), 1), 3) }
    private var spb: Double { 60 / Self.bpm }
    private var barSeconds: Double { 4 * spb }
    private var judge: TimingJudge { TimingJudge(band: model.profile.ageBand) }

    var body: some View {
        DesignCanvas(background: SI.Palette.sand) {
            ZStack(alignment: .topLeading) {
                topBar
                HStack(alignment: .top, spacing: 12) {
                    BopView(mood: bopMood, size: 120)
                    VStack(alignment: .leading, spacing: 12) {
                        SpeechBubble(instruction).frame(maxWidth: 360).fixedSize(horizontal: false, vertical: true)
                        ReplayButton(line: instruction)
                    }
                }
                .narrates(instruction)
                .offset(x: 120, y: 150)
                TimelineView(.animation) { _ in
                    let now = running ? model.audio.transportSeconds(forHostSeconds: CACurrentMediaTime()) : -10
                    ZStack(alignment: .topLeading) {
                        turnBanner(now: now).position(x: 860, y: 230)
                        padRow(now: now)
                    }
                    .frame(width: 1194, height: 834)
                }
            }
            .frame(width: 1194, height: 834)
        }
        .onAppear { model.audio.send(.setKit(0)); newPattern(); startCopying() }
        .onDisappear { model.audio.send(.stop); model.pushSongToAudio() }
        .onReceive(ticker) { _ in poll() }
    }

    // MARK: Game loop

    private func newPattern() {
        pattern = DrumPattern.generate(beats: tierSpec.int("beats", default: 2), drums: drumCount,
                                       allowEighths: drumCount >= 3, using: &rng)
        attempts = PatternAttempts()
    }

    private func masks(_ p: DrumPattern) -> DrumMasks {
        let m = p.stepMasks + [0, 0, 0]
        return DrumMasks(kick: m[0], snare: m[1], clap: m[2])
    }

    /// Starts the transport: count-in bar, then Bop on odd bars and the child on even bars.
    private func startCopying() {
        taps = []
        lastBeatIndex = -1
        childBar = 2
        lastResultClean = nil
        stage = .copying
        model.audio.send(.setTempo(Self.bpm))
        model.audio.send(.setDrumPattern(masks(pattern)))
        model.audio.send(.play(metronome: true, playPattern: true))
        model.audio.send(.setPatternBars(period: 2, phase: 1))
        running = true
    }

    private func poll() {
        guard running, let beat = model.audio.latestBeat(), beat.index != lastBeatIndex else { return }
        lastBeatIndex = beat.index
        switch stage {
        case .copying:
            if beat.index == childBar * 4 { flow.startTrying() }
            if beat.index >= (childBar + 1) * 4 { endCopy() }
        case .creating:
            // Bar 0 count-in, bar 1 the child plays, bar 2 Bop plays it back.
            if beat.index == 8 { finishCreating() }
        case .playback:
            if beat.index >= 12 { finishSession() }
        case .between, .done:
            break
        }
    }

    private func endCopy() {
        let start = Double(childBar) * barSeconds
        let result = CopyResult.judge(taps: taps.filter { $0.seconds >= start - 0.3 && $0.seconds < start + barSeconds - 0.2 },
                                      pattern: pattern, start: start, secondsPerBeat: spb, judge: judge)
        lastResultClean = result.isClean
        taps = []
        switch attempts.record(clean: result.isClean) {
        case .retry:
            // Keep the loop going: the bar that starts now is Bop's next turn.
            flow.miss()
            childBar += 2
        case .done(let correct):
            running = false
            model.audio.send(.stop)
            flow.completeRound(correct: correct)
            stage = .between(result.isClean ? "You copied Bop!" : "Good drumming! Here's a new one.")
            after(1.8) {
                flow.next()
                if case .reward = flow.phase { startCreating() } else { newPattern(); startCopying() }
            }
        }
    }

    private func startCreating() {
        created = []
        lastBeatIndex = -1
        stage = .creating
        // Empty pattern on even bars until the child's bar is filled in; it plays back on bar 2.
        model.audio.send(.setDrumPattern(DrumMasks()))
        model.audio.send(.play(metronome: true, playPattern: true))
        model.audio.send(.setPatternBars(period: 2, phase: 0))
        running = true
    }

    private func createdPattern() -> DrumPattern {
        DrumPattern.quantize(taps: created, start: barSeconds, secondsPerBeat: spb, beats: 4, drums: drumCount)
    }

    private func finishCreating() {
        if createdPattern().hits.isEmpty {
            // Nothing played: Bop shares an idea instead. No fail state.
            let idea = DrumPattern.generate(beats: 4, drums: drumCount, allowEighths: false, using: &rng)
            created = idea.hits.map { (seconds: barSeconds + $0.beat * spb, drum: $0.drum) }
            model.audio.send(.setDrumPattern(masks(idea)))
        }
        stage = .playback
    }

    private func finishSession() {
        running = false
        stage = .done
        model.audio.send(.stop)
        after(1.2) {
            let info = model.finishGame(.drumCircle, results: flow.results)
            model.path.removeLast()
            model.path.append(.reward(info))
        }
    }

    private func onTap(hostSeconds: Double, location: CGPoint) {
        guard let pad = padIndex(at: location) else { return }
        model.audio.playDrum(Self.pads[pad].sound, velocity: 0.9)
        guard running else { return }
        let t = model.audio.transportSeconds(forHostSeconds: hostSeconds)
        tapLit[pad] = t
        switch stage {
        case .copying:
            if t >= Double(childBar) * barSeconds - 0.3 { taps.append((t, pad)) }
        case .creating:
            created.append((t, pad))
            // Update the playback bar as the child plays; the sequencer only plays it on bar 2.
            model.audio.send(.setDrumPattern(masks(createdPattern())))
        default:
            break
        }
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }

    // MARK: Layout

    private func padCenter(_ i: Int) -> CGPoint {
        let gap: CGFloat = 60
        let total = CGFloat(drumCount) * Self.padSize + CGFloat(drumCount - 1) * gap
        let x0 = (1194 - total) / 2 + Self.padSize / 2
        return CGPoint(x: x0 + CGFloat(i) * (Self.padSize + gap), y: Self.padY)
    }

    private func padIndex(at p: CGPoint) -> Int? {
        (0..<drumCount).first { i in
            let c = padCenter(i)
            return hypot(p.x - c.x, p.y - c.y) <= Self.padSize / 2 + 12
        }
    }

    /// Which bar the music is in, and whether it's Bop's or the child's.
    private enum Turn { case countIn, bop, child, none }

    private func turn(now: Double) -> Turn {
        guard running, now >= 0 else { return .none }
        let bar = Int(now / barSeconds)
        switch stage {
        case .copying: return bar == 0 ? .countIn : (bar % 2 == 1 ? .bop : .child)
        case .creating: return bar == 0 ? .countIn : .child
        case .playback: return .bop
        default: return .none
        }
    }

    /// Pad brightness 0...1 at `now`: Bop's hits during his bars, the child's own taps, and the hint glow.
    private func padLight(_ i: Int, now: Double) -> (lit: Double, hint: Bool) {
        var lit = max(0, 1 - (now - tapLit[i]) / 0.25)
        let bar = Int(floor(now / barSeconds))
        let barStart = Double(bar) * barSeconds
        let current = stage == .playback ? createdPattern() : pattern
        if turn(now: now) == .bop {
            for h in current.hits where h.drum == i {
                let dt = now - (barStart + h.beat * spb)
                if dt >= 0 && dt < 0.3 { lit = max(lit, 1 - dt / 0.3) }
            }
        }
        var hint = false
        if stage == .copying, flow.showGlowHint, turn(now: now) == .child {
            hint = pattern.hits.contains { h in
                let dt = (barStart + h.beat * spb) - now
                return h.drum == i && dt > -0.1 && dt < 0.35
            }
        }
        return (lit, hint)
    }

    private func padRow(now: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<drumCount, id: \.self) { i in
                let light = padLight(i, now: now)
                let pad = Self.pads[i]
                ZStack {
                    Circle().fill(SI.Palette.ink900).offset(y: 10)
                    Circle().fill(pad.fill)
                        .overlay(Circle().fill(.white.opacity(0.45 * light.lit)))
                        .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 5))
                    Circle().strokeBorder(SI.Palette.ink900.opacity(0.25), lineWidth: 4).padding(36)
                    Text(pad.name).font(SI.Font.title).foregroundStyle(SI.Palette.ink900)
                }
                .frame(width: Self.padSize, height: Self.padSize)
                .scaleEffect(1 + 0.06 * light.lit)
                .overlay(Circle().strokeBorder(SI.Palette.star, lineWidth: light.hint ? 14 : 0).padding(-14))
                .position(padCenter(i))
                .accessibilityElement()
                .accessibilityLabel("\(pad.name) drum")
                .accessibilityAddTraits([.isButton, .allowsDirectInteraction])
                .accessibilityAction { onTap(hostSeconds: CACurrentMediaTime(), location: padCenter(i)) }
            }
            TapCaptureView { host, location in onTap(hostSeconds: host, location: location) }
                .frame(width: 1194, height: 380)
                .offset(y: Self.padY - 190)
                .accessibilityHidden(true)
        }
        .frame(width: 1194, height: 834, alignment: .topLeading)
    }

    @ViewBuilder
    private func turnBanner(now: Double) -> some View {
        let t = turn(now: now)
        let (icon, text): (String, String) = switch t {
        case .countIn: ("metronome.fill", "Get ready...")
        case .bop: ("ear.fill", "Listen")
        case .child: ("hand.tap.fill", "Your turn!")
        case .none: ("star.fill", lastResultClean == true ? "Yes!" : "Drum Circle")
        }
        Label(text, systemImage: icon)
            .font(SI.Font.headline)
            .foregroundStyle(SI.Palette.ink900)
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(Capsule().fill(t == .child ? SI.Palette.star : .white))
            .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
            .accessibilityHidden(true)
    }

    private var bopMood: BopMood {
        switch stage {
        case .between: lastResultClean == true ? .cheer : .idle
        case .playback, .done: .cheer
        case .copying, .creating: .listen
        }
    }

    private var instruction: String {
        switch stage {
        case .between(let message): return message
        case .creating: return "Make up your own beat! Bop will copy you."
        case .playback, .done: return "Here's your beat!"
        case .copying:
            return flow.showGlowHint ? "Watch the glowing drum, then copy Bop!" : "Listen to Bop, then copy the drums!"
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            RoundIconButton(systemName: "pause.fill", label: "Pause") { model.path.removeLast() }
            Spacer()
            VStack(spacing: 8) {
                Text("Drum Circle").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(SI.Palette.ink900)
                RoundDots(total: Self.copies, done: flow.round)
            }
            Spacer()
            Color.clear.frame(width: 76, height: 76)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(width: 1194)
    }
}
