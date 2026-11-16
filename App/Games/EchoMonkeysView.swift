import SwiftUI
import MusicTheory
import GameKitCore
import DesignSystem

/// Echo Monkeys (Melody Jungle): the monkey plays a short phrase on scale pads; the child echoes it.
/// Spec section 4. A wrong pad plays its note, and the monkey plays the phrase again (errorless).
struct EchoMonkeysView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 5

    @State private var flow = RoundFlow(totalRounds: EchoMonkeysView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var input: EchoInput?
    @State private var lit: Int?
    @State private var listening = true
    @State private var lastWrong: Int?
    @State private var solved = false
    @State private var sequencer: Sequencer?

    private var spec: TierSpecShim { TierSpecShim(model: model) }
    private var scale: Scale { Scale(tonic: .c, type: ScaleType(content: spec.scaleName)) }
    private var pads: [Pitch] { scale.pitches(fromOctave: 4, count: scale.type.steps.count) }

    var body: some View {
        GameShell(title: "Echo Monkeys", rounds: Self.rounds, done: flow.round, instruction: instruction,
                  background: Color(hex: 0xE3F6DA), bopMood: solved ? .cheer : (listening ? .sing : .listen)) {
            ZStack(alignment: .topLeading) {
                monkey.position(x: 900, y: 330)
                padRow.position(x: 597, y: 640)
                Button { playPhrase() } label: { Label("Hear it again", systemImage: "ear.fill") }
                    .buttonStyle(BigButtonStyle.secondary)
                    .disabled(listening)
                    .position(x: 597, y: 780)
            }
        }
        .onAppear { sequencer = Sequencer(audio: model.audio); newRound() }
        .onDisappear { sequencer?.cancel() }
    }

    private var instruction: String {
        if solved { return "You sound just like the monkey!" }
        if listening { return "Listen to the monkey..." }
        return flow.showGlowHint ? "Follow the glowing pads!" : "Your turn! Play it back."
    }

    private func newRound() {
        let phrase = EchoPhrase.make(length: spec.length, padCount: pads.count, rhythm: spec.rhythm, using: &rng)
        input = EchoInput(phrase: phrase)
        solved = false
        flow.startTrying()
        playPhrase(delay: 0.7)
    }

    private func playPhrase(delay: Double = 0) {
        guard let phrase = input?.phrase else { return }
        listening = true
        let unit = flow.replaySlowerHint ? 0.75 : 0.55
        // Rhythm tiers: step durations vary; the Sequencer uses one gap, so play note by note.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            for (i, pad) in phrase.pads.enumerated() {
                withAnimation(.easeOut(duration: 0.1)) { lit = pad }
                model.audio.playNote(pads[pad].midi, instrument: .marimba)
                try? await Task.sleep(for: .seconds(unit * phrase.beats[i]))
            }
            lit = nil
            listening = false
        }
    }

    private func tap(_ pad: Int) {
        model.audio.playNote(pads[pad].midi, instrument: .marimba)
        guard !listening, !solved, var current = input else { return }
        let step = current.tap(pad)
        input = current
        switch step {
        case .good: lastWrong = nil
        case .complete:
            solved = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            after(1.5) {
                flow.next()
                if case .reward = flow.phase { model.endGame(.echoMonkeys, results: flow.results) } else { newRound() }
            }
        case .wrong:
            lastWrong = pad
            flow.miss()
            after(0.9) { lastWrong = nil; playPhrase() }
        }
    }

    private var nextExpected: Int? {
        guard let input, !listening, !solved, flow.showGlowHint, input.played.count < input.phrase.pads.count else { return nil }
        return input.phrase.pads[input.played.count]
    }

    private var padRow: some View {
        HStack(spacing: pads.count > 5 ? 18 : 30) {
            ForEach(pads.indices, id: \.self) { i in
                Button { tap(i) } label: {
                    NotePad(pads[i].pitchClass, size: pads.count > 5 ? 128 : 150, highlighted: lit == i || nextExpected == i)
                        .overlay(RoundedRectangle(cornerRadius: 36).fill(SI.Palette.tryAgain.opacity(lastWrong == i ? 0.6 : 0)))
                        .scaleEffect(lit == i ? 1.08 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monkey: some View {
        ZStack {
            Circle().fill(Color(hex: 0x9C6B3F)).frame(width: 190, height: 190)
                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 5))
            Circle().fill(Color(hex: 0xF4D7A1)).frame(width: 120, height: 100).offset(y: 22)
            HStack(spacing: 40) { Circle().fill(SI.Palette.ink900).frame(width: 16); Circle().fill(SI.Palette.ink900).frame(width: 16) }
                .offset(y: -18)
            Capsule().fill(SI.Palette.ink900).frame(width: lit == nil ? 40 : 30, height: lit == nil ? 8 : 26).offset(y: 40)
        }
        .rotationEffect(.degrees(lit.map { Double($0 % 3 - 1) * 6 } ?? 0))
        .accessibilityLabel("Monkey")
    }
}

/// Reads the Echo Monkeys tier fields from skills.json.
private struct TierSpecShim {
    let length: Int, scaleName: String, rhythm: Bool
    @MainActor init(model: AppModel) {
        let t = model.tierSpec(for: .echoMonkeys)
        length = t.int("length", default: 3)
        scaleName = t.string("scale", default: "majorPentatonic")
        rhythm = t.bool("rhythm", default: false)
    }
}
