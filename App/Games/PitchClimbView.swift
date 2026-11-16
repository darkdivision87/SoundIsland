import SwiftUI
import MusicTheory
import GameKitCore
import DesignSystem

/// Pitch Climb (Pitch Peaks): hear where the climber goes on a colored C major ladder. Spec section 4.
/// Tiers: up or down, then step or skip, then the exact rung.
struct PitchClimbView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 10
    private static let ladderX: CGFloat = 330
    private static func rungY(_ r: Int) -> CGFloat { 760 - CGFloat(r) * 62 }

    @State private var flow = RoundFlow(totalRounds: PitchClimbView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var round: PitchClimbRound?
    @State private var tried: Set<ClimbAnswer> = []
    @State private var climberRung = 0
    @State private var solved = false
    @State private var sequencer: Sequencer?

    private var mode: ClimbMode {
        ClimbMode(rawValue: model.tierSpec(for: .pitchClimb).string("mode", default: "direction")) ?? .direction
    }

    var body: some View {
        GameShell(title: "Pitch Climb", rounds: Self.rounds, done: flow.round, instruction: instruction,
                  bopMood: solved ? .cheer : .listen) {
            ZStack(alignment: .topLeading) {
                ladder
                climber.position(x: Self.ladderX, y: Self.rungY(climberRung) - 34)
                if let round, round.mode != .exactRung { answers(round).position(x: 820, y: 520) }
                Button { play() } label: { Label("Hear it again", systemImage: "ear.fill") }
                    .buttonStyle(BigButtonStyle.secondary)
                    .position(x: 820, y: 760)
            }
        }
        .onAppear { sequencer = Sequencer(audio: model.audio); newRound() }
        .onDisappear { sequencer?.cancel() }
    }

    private var instruction: String {
        guard let round else { return "" }
        if solved { return "Great climbing!" }
        switch round.mode {
        case .direction: return "Listen! Does the climber go up or down?"
        case .stepOrSkip: return "Listen! A little step, or a big skip?"
        case .exactRung: return "Listen! Tap the rung where the climber lands."
        }
    }

    private func newRound() {
        let r = PitchClimbRound.make(mode: mode, using: &rng)
        round = r
        climberRung = r.start
        tried = []
        solved = false
        flow.startTrying()
        play(delay: 0.6)
    }

    private func play(delay: Double = 0) {
        guard let round else { return }
        let ladder = PitchClimbRound.ladder
        sequencer?.play([[ladder[round.start].midi], [ladder[round.target].midi]],
                        gap: flow.replaySlowerHint ? 1.2 : 0.8, delay: delay)
    }

    private func answer(_ a: ClimbAnswer) {
        guard let round, !solved, !tried.contains(a) else { return }
        if round.isCorrect(a) {
            solved = true
            model.audio.playNote(PitchClimbRound.ladder[round.target].midi)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { climberRung = round.target }
            flow.completeRound(correct: flow.missesThisRound == 0)
            after(1.6) {
                flow.next()
                if case .reward = flow.phase { model.endGame(.pitchClimb, results: flow.results) } else { newRound() }
            }
        } else {
            tried.insert(a)
            flow.miss()
            if case .rung(let r) = a { model.audio.playNote(PitchClimbRound.ladder[r].midi) }
            after(0.8) { play() }
        }
    }

    private func state(_ a: ClimbAnswer) -> AnswerState {
        guard let round else { return .normal }
        if solved && round.isCorrect(a) { return .right }
        if tried.contains(a) { return .tried }
        return flow.showGlowHint && round.isCorrect(a) ? .hint : .normal
    }

    private func answers(_ round: PitchClimbRound) -> some View {
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 24), count: 2), spacing: 28) {
            ForEach(round.options, id: \.self) { a in
                AnswerCard(state: state(a), width: 250, height: 120, action: { answer(a) }) {
                    VStack(spacing: 6) {
                        Image(systemName: icon(a)).font(.system(size: 34, weight: .heavy))
                        Text(a.label)
                    }
                }
            }
        }
        .frame(width: 560)
    }

    private func icon(_ a: ClimbAnswer) -> String {
        switch a {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .stepUp: "arrow.up.right"
        case .stepDown: "arrow.down.right"
        case .skipUp: "arrow.up.to.line"
        case .skipDown: "arrow.down.to.line"
        case .rung: "circle"
        }
    }

    /// Eight colored rungs, C at the bottom. In exact-rung mode the 4 candidate rungs are buttons.
    private var ladder: some View {
        ZStack {
            ForEach([-110.0, 110.0], id: \.self) { dx in
                Capsule().fill(Color(hex: 0x9C6B3F)).frame(width: 18, height: 500)
                    .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                    .position(x: Self.ladderX + dx, y: (Self.rungY(0) + Self.rungY(7)) / 2)
            }
            ForEach(0..<8, id: \.self) { r in
                let pc = PitchClimbRound.ladder[r].pitchClass
                let style = NoteStyle.of(pc)
                let candidate = round?.mode == .exactRung && round?.options.contains(.rung(r)) == true
                let rungState: AnswerState = candidate ? state(.rung(r)) : .normal
                Button { if candidate { answer(.rung(r)) } else { model.audio.playNote(PitchClimbRound.ladder[r].midi) } } label: {
                    HStack(spacing: 10) {
                        NoteShape(style.glyph).fill(.white).overlay(NoteShape(style.glyph).stroke(SI.Palette.ink900, lineWidth: 2))
                            .frame(width: 26, height: 26)
                            .accessibilityHidden(true)
                        Text(pc.name).font(SI.Font.label).foregroundStyle(SI.Palette.ink900)
                    }
                    .frame(width: 240, height: max(52, model.minTarget - 8))
                    .background(Capsule().fill(style.color))
                    .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                    .overlay(Capsule().strokeBorder(rungState == .tried ? SI.Palette.tryAgain : SI.Palette.star,
                                                    lineWidth: candidate ? (rungState == .hint || rungState == .tried ? 10 : 5) : 0).padding(-8))
                }
                .buttonStyle(.plain)
                .position(x: Self.ladderX, y: Self.rungY(r))
                .accessibilityLabel(candidate ? "Rung \(pc.name), choose" : "Rung \(pc.name)")
            }
        }
    }

    private var climber: some View {
        Image(systemName: "figure.climbing")
            .font(.system(size: 54, weight: .bold))
            .foregroundStyle(SI.Palette.bop)
            .frame(width: 72, height: 72)
            .background(Circle().fill(.white).overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3)))
            .offset(x: -160)
            .accessibilityLabel("Climber")
    }
}
