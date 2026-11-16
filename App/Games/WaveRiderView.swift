import SwiftUI
import Combine
import QuartzCore
import AudioCore
import Curriculum
import GameKitCore
import DesignSystem

/// Wave Rider (Beat Beach): quarter notes, eighth notes and rests. Matches design/screens/WaveRider.dc.html.
/// Each round: 4 count-in clicks, then shells scroll into the ring at 180 pt per beat; tap as each arrives.
/// Shell positions come from the audio clock (latency compensated), and taps are judged on it too.
struct WaveRiderView: View {
    @Environment(AppModel.self) private var model

    private static let countIn = 4
    private static let rounds = 5
    private static let ringX: CGFloat = 358
    private static let laneY: CGFloat = 420
    private static let pointsPerBeat: CGFloat = 180
    private static let line = "Tap when a shell reaches the ring!"

    private enum Stage: Equatable { case playing, between(String) }

    @State private var flow = RoundFlow(totalRounds: WaveRiderView.rounds)
    @State private var attempts = WaveRiderAttempts()
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var pattern = RhythmPattern(events: [], beats: 4)
    @State private var bpm: Double = 72
    @State private var stage = Stage.playing
    @State private var roundActive = false
    @State private var lastBeatIndex = -1
    @State private var taps: [Double] = []
    @State private var hitOnsets: Set<Int> = []
    @State private var frozenBeat: Double = 0
    @State private var lastGrade: TimingGrade?
    @State private var bob = false

    private let ticker = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect()

    private var tierSpec: TierSpec { model.skill(for: .waveRider)?.tier(model.tier(for: .waveRider)) ?? TierSpec(tier: 1, params: [:]) }
    private var tierBPM: Double { tierSpec.double("bpm", default: 72) }
    private var showNotation: Bool { tierSpec.bool("notation", default: false) }
    private var judge: TimingJudge { TimingJudge(band: model.profile.ageBand) }
    private var secondsPerBeat: Double { 60 / bpm }
    private var patternStart: Double { Double(Self.countIn) * secondsPerBeat }

    var body: some View {
        DesignCanvas(background: SI.Palette.sky) {
            ZStack(alignment: .topLeading) {
                Circle().fill(SI.Palette.star.opacity(0.55)).frame(width: 112, height: 112)
                    .position(x: 1040, y: 210).accessibilityHidden(true)
                TimelineView(.animation) { _ in lane(nowBeat: currentPatternBeat()) }
                    .accessibilityHidden(true)
                surfer.position(x: 358, y: 256)
                if let g = lastGrade, stage == .playing {
                    FeedbackChip(correct: g != .miss).position(x: 190, y: 250).transition(.scale)
                }
                topBar
                HStack(spacing: 12) {
                    SpeechBubble(instruction).frame(maxWidth: 300).fixedSize(horizontal: false, vertical: true)
                    ReplayButton(line: instruction)
                }
                .narrates(instruction)
                .offset(x: 690, y: 130)
                VStack { Spacer(); TapZone { onTap(hostSeconds: $0) } }
            }
            .frame(width: 1194, height: 834)
        }
        .onAppear { newPattern(); startAttempt() }
        .onDisappear { model.audio.send(.stop); model.pushSongToAudio() }
        .onReceive(ticker) { _ in poll() }
    }

    // MARK: Game loop

    private func newPattern() {
        let values = tierSpec.strings("values").compactMap(RhythmValue.init(rawValue:))
        pattern = RhythmPattern.generate(values: values, bars: tierSpec.int("bars", default: 1), using: &rng)
        attempts = WaveRiderAttempts()
        bpm = tierBPM
    }

    private func startAttempt() {
        taps = []
        hitOnsets = []
        lastGrade = nil
        lastBeatIndex = -1
        frozenBeat = -Double(Self.countIn)
        stage = .playing
        roundActive = true
        model.audio.send(.setTempo(bpm))
        model.audio.send(.play(metronome: true, playPattern: false))
    }

    /// Position of the music right now, in beats from the pattern's first downbeat (negative during count-in).
    private func currentPatternBeat() -> Double {
        guard roundActive, model.audio.isPlaying else { return frozenBeat }
        let t = model.audio.transportSeconds(forHostSeconds: CACurrentMediaTime())
        return t / secondsPerBeat - Double(Self.countIn)
    }

    private func poll() {
        guard roundActive, let beat = model.audio.latestBeat(), beat.index != lastBeatIndex else { return }
        lastBeatIndex = beat.index
        withAnimation(.easeOut(duration: 0.15)) { bob.toggle() }
        if beat.index == Self.countIn { flow.startTrying() }
        if beat.index >= Self.countIn + pattern.beats { endAttempt() }
    }

    private func onTap(hostSeconds: Double) {
        guard roundActive, lastBeatIndex >= Self.countIn - 1 else { return }
        let t = model.audio.transportSeconds(forHostSeconds: hostSeconds)
        taps.append(t)
        model.audio.playDrum(.clap, velocity: 0.5)

        let targets = pattern.onsets.map { patternStart + $0 * secondsPerBeat }
        let j = judge.judge(tap: t, targets: targets, alreadyHit: hitOnsets)
        if let i = j.targetIndex { hitOnsets.insert(i) }
        withAnimation(SI.spring) { lastGrade = j.grade }
    }

    private func endAttempt() {
        roundActive = false
        frozenBeat = Double(pattern.beats)
        model.audio.send(.stop)
        let result = PatternResult.judge(taps: taps, pattern: pattern, start: patternStart,
                                         secondsPerBeat: secondsPerBeat, judge: judge)
        switch attempts.record(clean: result.isClean) {
        case .retry(let slower):
            flow.miss()
            if slower { bpm = tierBPM * WaveRiderAttempts.slowTempoFactor }
            stage = .between(slower ? "Let's ride it again, a little slower!" : "Let's ride that wave again!")
            after(1.6) { startAttempt() }
        case .done(let correct):
            flow.completeRound(correct: correct)
            stage = .between(result.isClean ? "You rode the wave!" : "Nice riding! Here comes a new wave.")
            after(1.6) {
                flow.next()
                if case .reward = flow.phase {
                    let info = model.finishGame(.waveRider, results: flow.results)
                    model.path.removeLast()
                    model.path.append(.reward(info))
                } else {
                    newPattern()
                    startAttempt()
                }
            }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }

    // MARK: Views

    private var instruction: String {
        if case .between(let message) = stage { return message }
        return flow.showGlowHint ? "Tap when a shell lands in the glowing ring!" : Self.line
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            RoundIconButton(systemName: "pause.fill", label: "Pause") { model.path.removeLast() }
            Spacer()
            VStack(spacing: 8) {
                Text("Wave Rider").font(.system(size: 30, weight: .heavy, design: .rounded))
                RoundDots(total: Self.rounds, done: flow.round)
            }
            Spacer()
            Color.clear.frame(width: 76, height: 76)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(width: 1194)
    }

    private var surfer: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(Color(hex: 0xFF5A5F)).overlay(Ellipse().strokeBorder(SI.Palette.ink900, lineWidth: 4))
                .frame(width: 112, height: 20)
            BopView(mood: lastGrade == .great ? .cheer : .idle, size: 72).padding(.bottom, 12)
        }
        .frame(width: 116, height: 104)
        .offset(y: bob ? -4 : 0)
        .accessibilityLabel("Bop surfing")
    }

    /// Water, ring, beat numbers and shells. Drawn in design space; `nowBeat` slides everything left.
    private func lane(nowBeat: Double) -> some View {
        let events = pattern.events
        let onsetIndex = Dictionary(uniqueKeysWithValues: pattern.onsets.enumerated().map { ($1, $0) })
        let hits = hitOnsets
        let glow = flow.showGlowHint
        let notation = showNotation
        let beats = pattern.beats
        let ringX = Self.ringX, laneY = Self.laneY, ppb = Self.pointsPerBeat
        let ink = SI.Palette.ink900

        return Canvas { ctx, size in
            // Water with a gentle moving crest.
            var water = Path()
            let crest = { (x: CGFloat) in 308 + 6 * sin((x / 90) + nowBeat * .pi) }
            water.move(to: CGPoint(x: 0, y: crest(0)))
            for x in stride(from: 12.0, to: size.width, by: 12) { water.addLine(to: CGPoint(x: x, y: crest(x))) }
            water.addLine(to: CGPoint(x: size.width, y: crest(size.width)))
            water.addLine(to: CGPoint(x: size.width, y: 550))
            water.addLine(to: CGPoint(x: 0, y: 550))
            water.closeSubpath()
            ctx.fill(water, with: .color(SI.Palette.ocean))
            ctx.fill(Path(CGRect(x: 0, y: 400, width: size.width, height: 40)), with: .color(Color(hex: 0x6CC9D9)))

            // Hit line and ring.
            var hitLine = Path()
            hitLine.move(to: CGPoint(x: ringX, y: 320))
            hitLine.addLine(to: CGPoint(x: ringX, y: 536))
            ctx.stroke(hitLine, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [4, 10]))
            let ring = Path(ellipseIn: CGRect(x: ringX - 58, y: laneY - 58, width: 116, height: 116))
            ctx.stroke(ring, with: .color(SI.Palette.star), lineWidth: glow ? 16 : 10)
            ctx.stroke(ring, with: .color(ink), lineWidth: 3)
            ctx.stroke(Path(ellipseIn: CGRect(x: ringX - 74, y: laneY - 74, width: 148, height: 148)),
                       with: .color(SI.Palette.star.opacity(glow ? 1 : 0.6)), lineWidth: glow ? 8 : 4)

            // Beat numbers: count-in in grey, pattern beats in ink.
            for b in -Self.countIn...beats {
                let x = ringX + (CGFloat(b) - nowBeat) * ppb
                guard x > -40, x < size.width + 40 else { continue }
                let n = ((b % 4) + 4) % 4 + 1
                let text = Text("\(n)").font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(b < 0 ? SI.Palette.ink500.opacity(0.5) : SI.Palette.ink500)
                ctx.draw(text, at: CGPoint(x: x, y: 282))
            }

            // Shells.
            for e in events {
                let x = ringX + (CGFloat(e.beat) - nowBeat) * ppb
                guard x > -80, x < size.width + 80 else { continue }
                let hit = onsetIndex[e.beat].map { hits.contains($0) } ?? false
                let near = abs(CGFloat(e.beat) - nowBeat) < 0.3
                let scale: CGFloat = (glow && near && !e.value.isRest) ? 1.15 : 1
                var shell = ctx
                shell.opacity = hit ? 0.35 : 1
                switch e.value {
                case .quarter:
                    let r = CGRect(x: x - 55 * scale, y: laneY - 34 * scale, width: 110 * scale, height: 68 * scale)
                    let p = Path(roundedRect: r, cornerRadius: 34 * scale)
                    shell.fill(p, with: .color(Color(hex: 0xFF9A3C)))
                    shell.stroke(p, with: .color(ink), lineWidth: 4)
                    if notation { shell.draw(Text("\u{2669}").font(.system(size: 40, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: x, y: laneY)) }
                case .eighth:
                    let p = Path(ellipseIn: CGRect(x: x - 32 * scale, y: laneY - 32 * scale, width: 64 * scale, height: 64 * scale))
                    shell.fill(p, with: .color(Color(hex: 0xFFD23F)))
                    shell.stroke(p, with: .color(ink), lineWidth: 4)
                    if notation { shell.draw(Text("\u{266A}").font(.system(size: 32, weight: .bold)).foregroundStyle(ink), at: CGPoint(x: x, y: laneY)) }
                case .quarterRest, .eighthRest:
                    let radius: CGFloat = e.value == .quarterRest ? 32 : 26
                    let p = Path(ellipseIn: CGRect(x: x - radius, y: laneY - radius, width: radius * 2, height: radius * 2))
                    shell.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 4, dash: [6, 8]))
                    shell.draw(Text("shh").font(.system(size: e.value == .quarterRest ? 22 : 18, weight: .black, design: .rounded))
                        .foregroundStyle(ink), at: CGPoint(x: x, y: laneY))
                }
            }
        }
        .frame(width: 1194, height: 834)
    }
}
