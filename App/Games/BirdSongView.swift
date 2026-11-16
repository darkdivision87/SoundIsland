import SwiftUI
import MusicTheory
import GameKitCore
import DesignSystem

/// Bird Song (Pitch Peaks): two birds sing; give the worm to the higher (or lower) one. Spec section 4.
/// Tap a bird to hear it again; drag the worm onto a bird, or tap "Feed me" (the accessible alternative).
struct BirdSongView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 10
    private static let birdX: [CGFloat] = [380, 814]
    private static let birdY: CGFloat = 470

    @State private var flow = RoundFlow(totalRounds: BirdSongView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var round: BirdSongRound?
    @State private var tried: Set<Int> = []
    @State private var singing: Int?
    @State private var solved = false
    @State private var wormOffset: CGSize = .zero
    @State private var sequencer: Sequencer?

    private var interval: Int { model.tierSpec(for: .birdSong).int("intervalSemitones", default: 12) }

    var body: some View {
        GameShell(title: "Bird Song", rounds: Self.rounds, done: flow.round, instruction: instruction,
                  bopMood: solved ? .cheer : .listen) {
            ZStack(alignment: .topLeading) {
                branch
                if let round {
                    ForEach(0..<2, id: \.self) { i in bird(i, round: round).position(x: Self.birdX[i], y: Self.birdY) }
                }
                worm.position(x: 597, y: 740)
            }
        }
        .onAppear { sequencer = Sequencer(audio: model.audio); newRound() }
        .onDisappear { sequencer?.cancel() }
    }

    private var instruction: String {
        guard let round else { return "" }
        if solved { return "Yum! Thank you!" }
        let which = round.askHigher ? "higher" : "lower"
        return flow.showGlowHint ? "Listen again. Which bird sang \(which)?" : "Which bird sang \(which)? Give it the worm!"
    }

    private func newRound() {
        round = BirdSongRound.make(intervalSemitones: interval, using: &rng)
        tried = []
        solved = false
        flow.startTrying()
        sing(delay: 0.6)
    }

    private func sing(delay: Double = 0) {
        guard let round else { return }
        let gap = flow.replaySlowerHint ? 1.3 : 0.9
        sequencer?.play(round.birds.map { [$0.midi] }, gap: gap, instrument: .musicBox, delay: delay,
                        onStep: { i in withAnimation(SI.spring) { singing = i >= 0 ? i : nil } })
    }

    private func choose(_ i: Int) {
        guard let round, !solved, !tried.contains(i) else { return }
        model.audio.playNote(round.birds[i].midi, instrument: .musicBox)
        if i == round.answer {
            solved = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            after(1.4) {
                flow.next()
                if case .reward = flow.phase { model.endGame(.birdSong, results: flow.results) } else { newRound() }
            }
        } else {
            tried.insert(i)
            flow.miss()
            after(0.8) { sing() }
        }
    }

    private func state(_ i: Int) -> AnswerState {
        guard let round else { return .normal }
        if solved && i == round.answer { return .right }
        if tried.contains(i) { return .tried }
        return flow.showGlowHint && i == round.answer ? .hint : .normal
    }

    private var branch: some View {
        Capsule().fill(Color(hex: 0x9C6B3F)).overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
            .frame(width: 900, height: 26).position(x: 597, y: Self.birdY + 30)
            .accessibilityHidden(true)
    }

    private func bird(_ i: Int, round: BirdSongRound) -> some View {
        let colors = [Color(hex: 0x22C3C9), Color(hex: 0xFF8FB1)]
        return VStack(spacing: 18) {
            Button { model.audio.playNote(round.birds[i].midi, instrument: .musicBox); flash(i) } label: {
                Image(systemName: "bird.fill")
                    .font(.system(size: 92, weight: .bold))
                    .foregroundStyle(colors[i])
                    .frame(width: 180, height: 160)
                    .background(Circle().fill(.white).overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 4)))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "music.note").font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(SI.Palette.ink900).opacity(singing == i ? 1 : 0)
                    }
                    .scaleEffect(singing == i ? 1.12 : 1)
                    .offset(y: singing == i ? -12 : 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(i == 0 ? "Left bird, tap to hear it" : "Right bird, tap to hear it")
            AnswerCard(state: state(i), width: 220, height: 84, action: { choose(i) }) {
                Label("Feed me", systemImage: "fork.knife")
            }
            .accessibilityLabel(i == 0 ? "Give the worm to the left bird" : "Give the worm to the right bird")
        }
    }

    private func flash(_ i: Int) {
        withAnimation(SI.spring) { singing = i }
        after(0.4) { withAnimation(SI.spring) { if singing == i { singing = nil } } }
    }

    private var worm: some View {
        Capsule().fill(Color(hex: 0xFF8FB1))
            .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
            .overlay(alignment: .trailing) { Circle().fill(SI.Palette.ink900).frame(width: 10).padding(.trailing, 18) }
            .frame(width: 120, height: 44)
            .offset(wormOffset)
            .gesture(DragGesture()
                .onChanged { wormOffset = $0.translation }
                .onEnded { value in
                    let end = CGPoint(x: 597 + value.translation.width, y: 740 + value.translation.height)
                    if let i = (0..<2).first(where: { hypot(end.x - Self.birdX[$0], end.y - Self.birdY) < 140 }) { choose(i) }
                    withAnimation(SI.spring) { wormOffset = .zero }
                })
            .accessibilityHidden(true)
    }
}
