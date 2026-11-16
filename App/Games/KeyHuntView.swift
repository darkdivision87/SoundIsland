import SwiftUI
import MusicTheory
import Curriculum
import GameKitCore
import DesignSystem

/// Key Hunt (Pitch Peaks): Bop names a note, the child taps that key. Spec section 4.
/// Keys always show their note color and shape. In tier 1 the prompt shows the shape too, as a bridge.
struct KeyHuntView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 10
    private static let whiteKeys: [PitchClass] = [.c, .d, .e, .f, .g, .a, .b]
    private static let keyWidth: CGFloat = 132
    private static let keyboardY: CGFloat = 560

    @State private var flow = RoundFlow(totalRounds: KeyHuntView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var target: PitchClass?
    @State private var tried: Set<PitchClass> = []
    @State private var solved = false
    @State private var pressed: PitchClass?

    private var tier: Int { model.tier(for: .keyHunt) }
    private var notes: [PitchClass] {
        let n = KeyHunt.pitchClasses(model.tierSpec(for: .keyHunt).strings("notes"))
        return n.isEmpty ? [.c, .d, .e] : n
    }

    var body: some View {
        GameShell(title: "Key Hunt", rounds: Self.rounds, done: flow.round, instruction: instruction,
                  bopMood: solved ? .cheer : .idle) {
            ZStack(alignment: .topLeading) {
                if let target { promptCard(target).position(x: 597, y: 330) }
                keyboard.position(x: 597, y: 640)
            }
        }
        .onAppear(perform: newRound)
    }

    private var instruction: String {
        guard let target else { return "" }
        if solved { return "You found \(target.name)!" }
        return flow.showGlowHint ? "Look for the glowing key. That's \(target.name)!" : "Find \(target.name)!"
    }

    private func newRound() {
        target = KeyHunt.next(from: notes, after: target, using: &rng)
        tried = []
        solved = false
        flow.startTrying()
    }

    private func tap(_ pc: PitchClass) {
        model.audio.playNote(Pitch(pc, octave: 4).midi, instrument: .softPiano)
        withAnimation(.easeOut(duration: 0.1)) { pressed = pc }
        after(0.18) { if pressed == pc { pressed = nil } }
        guard let target, !solved, flow.phase == .tryIt else { return }
        if pc == target {
            solved = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            after(1.1) {
                flow.next()
                if case .reward = flow.phase { model.endGame(.keyHunt, results: flow.results) } else { newRound() }
            }
        } else if !tried.contains(pc) {
            tried.insert(pc)
            flow.miss()
        }
    }

    private func promptCard(_ pc: PitchClass) -> some View {
        return HStack(spacing: 18) {
            if tier == 1 {
                NoteBadge(pc, size: 64)
            }
            Text(pc.name).font(.system(size: 80, weight: .heavy, design: .rounded)).foregroundStyle(SI.Palette.ink900)
        }
        .padding(.horizontal, 44).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 32).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(SI.Palette.ink900, lineWidth: 5))
        .accessibilityLabel("Find \(pc.name)")
    }

    private func keyState(_ pc: PitchClass) -> AnswerState {
        if solved && pc == target { return .right }
        if tried.contains(pc) { return .tried }
        return flow.showGlowHint && pc == target ? .hint : .normal
    }

    /// One octave, C to B. Black keys sit between the white keys like a real piano (2 then 3).
    private var keyboard: some View {
        let w = Self.keyWidth
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Self.whiteKeys, id: \.self) { pc in key(pc, width: w, height: 300, black: false) }
            }
            ForEach(PitchClass.allCases.filter { !$0.isNatural }, id: \.self) { pc in
                let leftWhite = Self.whiteKeys.firstIndex(of: pc.transposed(by: -1)) ?? 0
                key(pc, width: w * 0.64, height: 180, black: true)
                    .offset(x: CGFloat(leftWhite + 1) * w - w * 0.32)
            }
        }
        .frame(width: w * 7, height: 300, alignment: .topLeading)
    }

    private func key(_ pc: PitchClass, width: CGFloat, height: CGFloat, black: Bool) -> some View {
        let s = keyState(pc)
        let fill: Color = s == .tried ? SI.Palette.tryAgain : (s == .right ? SI.Palette.success : (black ? SI.Palette.ink900 : .white))
        return Button { tap(pc) } label: {
            VStack {
                Spacer()
                NoteBadge(pc, size: black ? 34 : 42, outline: black ? .white : SI.Palette.ink900)
                    .padding(.bottom, black ? 18 : 26)
            }
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 14).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SI.Palette.ink900, lineWidth: 4))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SI.Palette.star, lineWidth: s == .hint ? 10 : 0).padding(-4))
            .offset(y: pressed == pc ? 4 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Key \(pc.name)")
    }
}
