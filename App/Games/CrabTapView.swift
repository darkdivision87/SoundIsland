import SwiftUI
import Combine
import AudioCore
import Curriculum
import GameKitCore
import DesignSystem

/// Crab Tap (Beat Beach): steady pulse and tempo. Spec section 4.
/// Each round = 4 count-in beats (listen) + 16 judged beats. Round passes at 80% on-beat.
/// Taps are timestamped by UIKit and judged on the audio clock, never the frame clock.
struct CrabTapView: View {
    @Environment(AppModel.self) private var model

    private static let countIn = 4
    private static let judgedBeats = 16
    private static let passAccuracy = 0.8
    private static let rounds = 5

    @State private var flow = RoundFlow(totalRounds: CrabTapView.rounds)
    @State private var beatTimes: [Int: Double] = [:]
    @State private var taps: [Double] = []
    @State private var lastBeatIndex = -1
    @State private var lastGrade: TimingGrade?
    @State private var lastOffset: Double = 0
    @State private var crabHop = false
    @State private var dance = false
    @State private var roundActive = false
    @State private var tempoChanged = false

    private let ticker = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect()

    private var tierSpec: TierSpec { model.skill(for: .crabTap)?.tier(model.tier(for: .crabTap)) ?? TierSpec(tier: 1, params: [:]) }
    private var bpm: Double { tierSpec.double("bpm", default: 96) }
    private var changeToBPM: Double? { tierSpec.params["changeToBpm"] == nil ? nil : tierSpec.double("changeToBpm", default: bpm) }
    private var judge: TimingJudge { TimingJudge(band: model.profile.ageBand) }

    var body: some View {
        DesignCanvas(background: SI.Palette.sky) {
            ZStack(alignment: .top) {
                beach
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    crabs.padding(.bottom, 40)
                    tapZone
                }
            }
        }
        .onAppear(perform: startRound)
        .onDisappear {
            model.audio.send(.stop)
            model.pushSongToAudio()
        }
        .onReceive(ticker) { _ in poll() }
    }

    // MARK: Game loop

    private func startRound() {
        beatTimes = [:]
        taps = []
        lastBeatIndex = -1
        lastGrade = nil
        tempoChanged = false
        roundActive = true
        model.audio.send(.setTempo(bpm))
        model.audio.send(.play(metronome: true, playPattern: false))
    }

    private func poll() {
        guard roundActive, let beat = model.audio.latestBeat(), beat.index != lastBeatIndex else { return }
        lastBeatIndex = beat.index
        beatTimes[beat.index] = beat.seconds
        withAnimation(.easeOut(duration: 0.12)) { crabHop.toggle() }

        if beat.index == Self.countIn { flow.startTrying() }
        if let target = changeToBPM, !tempoChanged, beat.index == Self.countIn + Self.judgedBeats / 2 {
            tempoChanged = true
            model.audio.send(.setTempo(target))
        }
        if beat.index >= Self.countIn + Self.judgedBeats { endRound() }
    }

    private func onTap(hostSeconds: Double) {
        guard roundActive, flow.phase == .tryIt else { return }
        let t = model.audio.transportSeconds(forHostSeconds: hostSeconds)
        taps.append(t)
        model.audio.playDrum(.snare, velocity: 0.5)

        // Live feedback against known beats plus the predicted next beat.
        var targets = Array(beatTimes.filter { $0.key >= Self.countIn }.values)
        if let last = beatTimes[lastBeatIndex] { targets.append(last + 60 / (tempoChanged ? (changeToBPM ?? bpm) : bpm)) }
        let j = judge.judge(tap: t, targets: targets)
        lastGrade = j.grade
        lastOffset = j.offset
        if j.grade == .great { withAnimation(SI.spring) { dance.toggle() } }
        if j.grade == .miss { flow.miss() }
    }

    private func endRound() {
        roundActive = false
        model.audio.send(.stop)
        let targets = (Self.countIn..<(Self.countIn + Self.judgedBeats)).compactMap { beatTimes[$0] }
        let result = judge.judgeStream(taps: taps, targets: targets)
        flow.completeRound(correct: result.accuracy >= Self.passAccuracy)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            flow.next()
            if case .reward = flow.phase {
                let info = model.finishGame(.crabTap, results: flow.results)
                model.path.removeLast()
                model.path.append(.reward(info))
            } else {
                startRound()
            }
        }
    }

    // MARK: Views

    private var instruction: String {
        switch flow.phase {
        case .listen: "Listen to the beat..."
        case .tryIt: flow.showGlowHint ? "Tap when the crabs step!" : "Tap on every beat!"
        case .feedback(let ok): ok ? "You kept the beat!" : "Let's try that again!"
        default: "Great job!"
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            RoundIconButton(systemName: "pause.fill", label: "Pause") { model.path.removeLast() }
            Spacer()
            VStack(spacing: 8) {
                Text("Crab Tap").font(.system(size: 30, weight: .heavy, design: .rounded))
                RoundDots(total: Self.rounds, done: flow.round)
            }
            Spacer()
            HStack(alignment: .center, spacing: 8) {
                SpeechBubble(instruction).frame(maxWidth: 300)
                ReplayButton(line: instruction)
                BopView(mood: bopMood, size: 84)
            }
            .narrates(instruction)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    private var bopMood: BopMood {
        switch flow.phase {
        case .listen: .listen
        case .feedback(let ok): ok ? .cheer : .wobble
        default: lastGrade == .great ? .cheer : .idle
        }
    }

    private var beach: some View {
        VStack(spacing: 0) {
            SI.Palette.sky.frame(height: 360)
            SI.Palette.ocean.frame(height: 80)
            SI.Palette.sand
        }
        .accessibilityHidden(true)
    }

    private var crabs: some View {
        HStack(spacing: 60) {
            ForEach(0..<4, id: \.self) { i in
                CrabShape()
                    .frame(width: 140, height: 100)
                    .offset(y: crabHop == (i % 2 == 0) ? -14 : 0)
                    .rotationEffect(.degrees(dance ? (i % 2 == 0 ? 10 : -10) : 0))
            }
        }
        .overlay(alignment: .top) {
            if let g = lastGrade, flow.phase == .tryIt {
                FeedbackChip(correct: g != .miss)
                    .offset(x: lastOffset < 0 ? -40 : 40, y: -90) // leans early/late
                    .transition(.scale)
            }
        }
        .accessibilityHidden(true)
    }

    private var tapZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48)
                .fill(SI.Palette.bopTint)
                .overlay(RoundedRectangle(cornerRadius: 48).strokeBorder(SI.Palette.bop, style: StrokeStyle(lineWidth: 5, dash: [14, 10])))
            VStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").font(.system(size: 56)).foregroundStyle(SI.Palette.bop)
                Text("Tap here on the beat!").font(.system(size: 40, weight: .heavy, design: .rounded))
            }
            .allowsHitTesting(false)
            TapCaptureView { host, _ in onTap(hostSeconds: host) }
        }
        .frame(height: 228)
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
}

struct RoundDots: View {
    let total: Int
    let done: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < done ? SI.Palette.success : (i == done ? SI.Palette.bop : .white))
                    .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                    .frame(width: 20, height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round \(min(done + 1, total)) of \(total)")
    }
}

/// Simple vector crab placeholder; final art comes from the illustrator (Rive).
struct CrabShape: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let ink = SI.Palette.ink900
            let body = Path(ellipseIn: CGRect(x: w * 0.15, y: h * 0.35, width: w * 0.7, height: h * 0.5))
            ctx.fill(body, with: .color(Color(hex: 0xFF5A5F)))
            ctx.stroke(body, with: .color(ink), lineWidth: 4)
            for x in [0.38, 0.62] {
                var stalk = Path(); stalk.move(to: CGPoint(x: w * x, y: h * 0.4)); stalk.addLine(to: CGPoint(x: w * x, y: h * 0.15))
                ctx.stroke(stalk, with: .color(ink), lineWidth: 4)
                let eye = Path(ellipseIn: CGRect(x: w * x - 9, y: h * 0.06, width: 18, height: 18))
                ctx.fill(eye, with: .color(.white)); ctx.stroke(eye, with: .color(ink), lineWidth: 3)
                ctx.fill(Path(ellipseIn: CGRect(x: w * x - 4, y: h * 0.06 + 5, width: 8, height: 8)), with: .color(ink))
            }
            for x in [0.02, 0.84] {
                let claw = Path(ellipseIn: CGRect(x: w * x, y: h * 0.28, width: w * 0.14, height: h * 0.26))
                ctx.fill(claw, with: .color(Color(hex: 0xFF5A5F))); ctx.stroke(claw, with: .color(ink), lineWidth: 4)
            }
        }
    }
}
