import SwiftUI
import MusicTheory
import GameKitCore
import DesignSystem

/// Vine Swing (Melody Jungle): one vine of the scale is missing. Choose the note that fills the gap
/// so Bop can swing across to the home note. Spec section 4.
struct VineSwingView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 5

    @State private var flow = RoundFlow(totalRounds: VineSwingView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var round: VineSwingRound?
    @State private var tried: Set<Pitch> = []
    @State private var solved = false
    @State private var lit: Int?
    @State private var swingerIndex = 0
    @State private var sequencer: Sequencer?

    private var scale: Scale {
        let t = model.tierSpec(for: .vineSwing)
        let tonics = t.strings("tonics").compactMap(PitchClass.init(name:))
        let tonic = tonics.isEmpty ? (PitchClass(name: t.string("tonic", default: "C")) ?? .c)
                                   : tonics[flow.round % tonics.count]
        return Scale(tonic: tonic, type: ScaleType(content: t.string("scale", default: "majorPentatonic")))
    }

    var body: some View {
        GameShell(title: "Vine Swing", rounds: Self.rounds, done: flow.round, instruction: instruction,
                  background: Color(hex: 0xE3F6DA), bopMood: solved ? .cheer : .listen) {
            ZStack(alignment: .topLeading) {
                if let round {
                    vines(round)
                    choices(round).position(x: 597, y: 720)
                }
            }
        }
        .onAppear { sequencer = Sequencer(audio: model.audio); newRound() }
        .onDisappear { sequencer?.cancel() }
    }

    private var instruction: String {
        if solved { return "Wheee! Home again!" }
        return flow.showGlowHint ? "Try the glowing note in the gap!" : "Which note is missing? Fill the gap!"
    }

    private func vineX(_ i: Int, count: Int) -> CGFloat { 597 + (CGFloat(i) - CGFloat(count - 1) / 2) * min(130, 1000 / CGFloat(count)) }

    private func newRound() {
        round = VineSwingRound.make(scale: scale, using: &rng)
        tried = []
        solved = false
        swingerIndex = 0
        flow.startTrying()
        playScale(fill: nil, delay: 0.6)
    }

    /// Plays the scale up; the gap is silent unless `fill` is given.
    private func playScale(fill: Pitch?, delay: Double = 0, done: (@MainActor () -> Void)? = nil) {
        guard let round else { return }
        let steps = round.notes.indices.map { i -> [Int] in
            i == round.missing ? (fill.map { [$0.midi] } ?? []) : [round.notes[i].midi]
        }
        sequencer?.play(steps, gap: flow.replaySlowerHint ? 0.65 : 0.45, delay: delay,
                        onStep: { i in withAnimation(.easeOut(duration: 0.12)) { lit = i >= 0 ? i : nil } }, done: done)
    }

    private func choose(_ p: Pitch) {
        guard let round, !solved, !tried.contains(p) else { return }
        if p == round.answer {
            solved = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            playScale(fill: p) {
                after(0.3) {
                    flow.next()
                    if case .reward = flow.phase { model.endGame(.vineSwing, results: flow.results) } else { newRound() }
                }
            }
            for i in round.notes.indices {
                after(Double(i) * (flow.replaySlowerHint ? 0.65 : 0.45)) { withAnimation(.spring(response: 0.35)) { swingerIndex = i } }
            }
        } else {
            tried.insert(p)
            flow.miss()
            playScale(fill: p) { after(0.4) { playScale(fill: nil) } }
        }
    }

    private func state(_ p: Pitch) -> AnswerState {
        guard let round else { return .normal }
        if solved && p == round.answer { return .right }
        if tried.contains(p) { return .tried }
        return flow.showGlowHint && p == round.answer ? .hint : .normal
    }

    private func vines(_ round: VineSwingRound) -> some View {
        let n = round.notes.count
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(hex: 0x3DA35D)).frame(width: 1194, height: 30).position(x: 597, y: 262)
            ForEach(0..<n, id: \.self) { i in
                let missing = i == round.missing && !solved
                let pc = round.notes[i].pitchClass
                VStack(spacing: 0) {
                    Rectangle().fill(missing ? .clear : Color(hex: 0x3DA35D)).frame(width: 10, height: 140 + CGFloat(i) * 14)
                    if missing {
                        Text("?").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(SI.Palette.ink900)
                            .frame(width: 96, height: 104)
                            .background(RoundedRectangle(cornerRadius: 24).strokeBorder(SI.Palette.ink900, style: StrokeStyle(lineWidth: 4, dash: [8, 8])))
                    } else {
                        NotePad(pc, showName: true, size: 96, highlighted: lit == i)
                    }
                }
                .position(x: vineX(i, count: n), y: 280 + (140 + CGFloat(i) * 14) / 2 + 52)
                .accessibilityLabel(missing ? "Missing note" : "Vine \(pc.name)")
            }
            Image(systemName: "figure.wave")
                .font(.system(size: 46, weight: .bold)).foregroundStyle(SI.Palette.bop)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.white).overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3)))
                .position(x: vineX(swingerIndex, count: n), y: 300)
                .accessibilityHidden(true)
        }
    }

    private func choices(_ round: VineSwingRound) -> some View {
        HStack(spacing: 40) {
            ForEach(round.options, id: \.self) { p in
                AnswerCard(state: state(p), width: 170, height: 130, action: { choose(p) }) {
                    NotePad(p.pitchClass, size: 92).allowsHitTesting(false)
                }
                .accessibilityLabel("Note \(p.pitchClass.name)")
            }
        }
    }
}
