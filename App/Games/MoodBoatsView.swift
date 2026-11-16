import SwiftUI
import MusicTheory
import GameKitCore
import DesignSystem

/// Mood Boats (Harmony Harbor): hear music and sail to Sunny Island (major) or Moon Island (minor).
/// Spec section 4. Tiers: single triads, then progressions, then melodies.
struct MoodBoatsView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 10

    @State private var flow = RoundFlow(totalRounds: MoodBoatsView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var round: MoodBoatsRound?
    @State private var tried: Set<ChordMood> = []
    @State private var solved = false
    @State private var boatX: CGFloat = 597
    @State private var sequencer: Sequencer?

    private var material: MoodMaterial {
        MoodMaterial(rawValue: model.tierSpec(for: .moodBoats).string("material", default: "triads")) ?? .triads
    }

    var body: some View {
        GameShell(title: "Mood Boats", rounds: Self.rounds, done: flow.round, instruction: instruction,
                  background: SI.Palette.ocean, bopMood: solved ? .cheer : .listen) {
            ZStack(alignment: .topLeading) {
                island(.sunny).position(x: 220, y: 520)
                island(.moon).position(x: 974, y: 520)
                boat.position(x: boatX, y: 560)
                Button { play() } label: { Label("Hear it again", systemImage: "ear.fill") }
                    .buttonStyle(BigButtonStyle.secondary)
                    .position(x: 597, y: 760)
            }
        }
        .onAppear { sequencer = Sequencer(audio: model.audio); newRound() }
        .onDisappear { sequencer?.cancel() }
    }

    private var instruction: String {
        if solved { return round?.mood == .sunny ? "Sunny and bright! That was major." : "Moony and soft! That was minor." }
        return flow.showGlowHint ? "Listen again. Does it sound sunny or moony?" : "Sunny or moony? Sail the boat!"
    }

    private func newRound() {
        round = MoodBoatsRound.make(material: material, using: &rng)
        tried = []
        solved = false
        withAnimation(SI.spring) { boatX = 597 }
        flow.startTrying()
        play(delay: 0.6)
    }

    private func play(delay: Double = 0) {
        guard let round else { return }
        let chordal = round.steps.first.map { $0.count > 1 } ?? false
        let gap = (chordal ? 0.9 : 0.42) * (flow.replaySlowerHint ? 1.35 : 1)
        sequencer?.play(round.steps, gap: gap, instrument: chordal ? .softPiano : .marimba, velocity: chordal ? 0.55 : 0.75, delay: delay)
    }

    private func sail(_ mood: ChordMood) {
        guard let round, !solved, !tried.contains(mood) else { return }
        withAnimation(.easeInOut(duration: 0.7)) { boatX = mood == .sunny ? 380 : 814 }
        if mood == round.mood {
            solved = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            after(1.8) {
                flow.next()
                if case .reward = flow.phase { model.endGame(.moodBoats, results: flow.results) } else { newRound() }
            }
        } else {
            tried.insert(mood)
            flow.miss()
            after(0.9) { withAnimation(SI.spring) { boatX = 597 }; play() }
        }
    }

    private func island(_ mood: ChordMood) -> some View {
        let sunny = mood == .sunny
        let state: AnswerState = solved && round?.mood == mood ? .right
            : tried.contains(mood) ? .tried
            : (flow.showGlowHint && round?.mood == mood ? .hint : .normal)
        return AnswerCard(state: state, width: 280, height: 260, action: { sail(mood) }) {
            VStack(spacing: 12) {
                Image(systemName: sunny ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 90, weight: .bold))
                    .foregroundStyle(sunny ? SI.Palette.star : SI.Palette.bop)
                Text(sunny ? "Sunny Island" : "Moon Island")
            }
        }
        .accessibilityLabel(sunny ? "Sunny Island, major" : "Moon Island, minor")
    }

    private var boat: some View {
        VStack(spacing: 0) {
            Image(systemName: "sailboat.fill").font(.system(size: 80, weight: .bold)).foregroundStyle(.white)
                .shadow(color: SI.Palette.ink900, radius: 0, x: 0, y: 3)
            Capsule().fill(SI.Palette.ink900.opacity(0.2)).frame(width: 120, height: 10)
        }
        .accessibilityHidden(true)
    }
}
