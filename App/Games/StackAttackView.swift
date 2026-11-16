import SwiftUI
import MusicTheory
import StudioModel
import GameKitCore
import DesignSystem

/// Stack Attack (Harmony Harbor): stack I, IV, V and vi blocks to match the progression Bop plays,
/// in Sunny C. Spec section 4. Tier 3 is "create and save": the child stacks their own and it goes to
/// the chords track of the current Studio section.
struct StackAttackView: View {
    @Environment(AppModel.self) private var model
    private static let rounds = 4
    private static let key = Key.sunnyC

    @State private var flow = RoundFlow(totalRounds: StackAttackView.rounds)
    @State private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    @State private var target: [Int] = []
    @State private var placed: [Int?] = []
    @State private var wrongSlots: Set<Int> = []
    @State private var solved = false
    @State private var lit: Int?
    @State private var sequencer: Sequencer?

    private var create: Bool { model.tierSpec(for: .stackAttack).bool("create", default: false) }
    private var length: Int { model.tierSpec(for: .stackAttack).int("length", default: 2) }

    var body: some View {
        GameShell(title: "Stack Attack", rounds: create ? 1 : Self.rounds, done: flow.round, instruction: instruction,
                  background: SI.Palette.sky, bopMood: solved ? .cheer : .listen) {
            ZStack(alignment: .topLeading) {
                slots.position(x: 597, y: 400)
                blockShelf.position(x: 597, y: 610)
                HStack(spacing: 24) {
                    if !create {
                        Button { playTarget() } label: { Label("Hear Bop's", systemImage: "ear.fill") }
                            .buttonStyle(BigButtonStyle.secondary)
                    }
                    Button { playPlaced() } label: { Label("Play mine", systemImage: "play.fill") }
                        .buttonStyle(BigButtonStyle.primary)
                        .disabled(placed.allSatisfy { $0 == nil })
                    Button { check() } label: { Label(create ? "Save" : "Check", systemImage: "checkmark") }
                        .buttonStyle(BigButtonStyle.go)
                        .disabled(placed.contains { $0 == nil })
                }
                .disabled(solved)
                .position(x: 597, y: 770)
            }
        }
        .onAppear { sequencer = Sequencer(audio: model.audio); newRound() }
        .onDisappear { sequencer?.cancel() }
    }

    private var instruction: String {
        if create { return solved ? "Your chords are in your song!" : "Stack 4 chords to make your own song part!" }
        if solved { return "A perfect match!" }
        if !wrongSlots.isEmpty { return "So close! Listen and fix the orange blocks." }
        return flow.showGlowHint ? "The glowing block goes next!" : "Listen to Bop's chords, then stack the same ones!"
    }

    private func newRound() {
        let n = create ? 4 : length
        target = create ? [] : StackAttack.progression(length: n, using: &rng)
        placed = Array(repeating: nil, count: n)
        placed[0] = create ? nil : 1 // matching starts on I, already placed, so kids hear where home is
        wrongSlots = []
        solved = false
        flow.startTrying()
        if !create { playTarget(delay: 0.6) }
    }

    private func chord(_ degree: Int) -> Triad { Self.key.diatonicTriad(degree: degree) }

    private func play(_ degrees: [Int?], delay: Double = 0, done: (@MainActor () -> Void)? = nil) {
        let steps = degrees.map { d in d.map { chord($0).pitches(rootOctave: 3).map(\.midi) } ?? [] }
        sequencer?.play(steps, gap: flow.replaySlowerHint ? 1.2 : 0.9, instrument: .softPiano, velocity: 0.55, delay: delay,
                        onStep: { i in lit = i >= 0 ? i : nil }, done: done)
    }

    private func playTarget(delay: Double = 0) { play(target.map { $0 }, delay: delay) }
    private func playPlaced() { play(placed) }

    private func place(_ degree: Int) {
        model.audio.playChord(chord(degree).pitches(rootOctave: 3).map(\.midi), velocity: 0.55)
        guard !solved, let i = placed.firstIndex(where: { $0 == nil }) else { return }
        placed[i] = degree
        wrongSlots.remove(i)
    }

    private func clear(_ slot: Int) {
        guard !solved, !(slot == 0 && !create) else { return }
        placed[slot] = nil
    }

    private func check() {
        if create {
            solved = true
            let events = placed.enumerated().flatMap { bar, d -> [NoteEvent] in
                guard let d else { return [] }
                return chord(d).pitches(rootOctave: 3).map { NoteEvent(tick: bar * 4 * ticksPerQuarter, pitch: $0, lengthTicks: 4 * ticksPerQuarter) }
            }
            model.setTrackNotes(.chords, events)
            play(placed) { after(0.5) { model.endGame(.stackAttack, results: [true]) } }
            return
        }
        let wrong = StackAttack.mismatches(placed: placed, target: target)
        if wrong.isEmpty {
            solved = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            play(placed) {
                after(0.6) {
                    flow.next()
                    if case .reward = flow.phase { model.endGame(.stackAttack, results: flow.results) } else { newRound() }
                }
            }
        } else {
            wrongSlots = Set(wrong)
            flow.miss()
            play(placed) { after(0.5) { playTarget() } }
        }
    }

    private var hintDegree: Int? {
        guard flow.showGlowHint, !create, let i = placed.firstIndex(where: { $0 == nil }) ?? wrongSlots.min() else { return nil }
        return target[i]
    }

    private var slots: some View {
        HStack(spacing: 22) {
            ForEach(placed.indices, id: \.self) { i in
                Button { clear(i) } label: {
                    Group {
                        if let d = placed[i] { block(d, size: 170, tried: wrongSlots.contains(i)) }
                        else {
                            RoundedRectangle(cornerRadius: 26).strokeBorder(SI.Palette.ink900, style: StrokeStyle(lineWidth: 4, dash: [10, 10]))
                                .frame(width: 170, height: 170)
                                .overlay(Text("\(i + 1)").font(SI.Font.title).foregroundStyle(SI.Palette.ink500))
                        }
                    }
                    .scaleEffect(lit == i ? 1.08 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(placed[i].map { "Slot \(i + 1), \(Self.key.romanNumeral(degree: $0)) chord, tap to remove" } ?? "Empty slot \(i + 1)")
            }
        }
    }

    private var blockShelf: some View {
        HStack(spacing: 28) {
            ForEach(StackAttack.blocks, id: \.self) { d in
                Button { place(d) } label: {
                    block(d, size: 150, tried: false)
                        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(SI.Palette.star, lineWidth: hintDegree == d ? 10 : 0).padding(-12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Self.key.romanNumeral(degree: d)) chord, \(chord(d).kidName)")
            }
        }
    }

    /// A chord block: the root's note color and shape, its Roman numeral and its kid name.
    /// A tried block keeps its note color (fixed per pitch class) and gets a try-again ring instead.
    private func block(_ degree: Int, size: CGFloat, tried: Bool) -> some View {
        let c = chord(degree)
        let style = NoteStyle.of(c.root)
        return VStack(spacing: 6) {
            NoteShape(style.glyph).fill(.white).overlay(NoteShape(style.glyph).stroke(SI.Palette.ink900, lineWidth: 2.5))
                .frame(width: size * 0.26, height: size * 0.26)
            Text(Self.key.romanNumeral(degree: degree)).font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
            NoteColorChip(c.kidName, size: size * 0.11)
        }
        .foregroundStyle(SI.Palette.ink900)
        .padding(.horizontal, 8)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 26).fill(style.color))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(SI.Palette.ink900, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 26).fill(style.lip).offset(y: 7))
        .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(SI.Palette.tryAgain, lineWidth: tried ? 10 : 0).padding(-10))
    }
}
