import SwiftUI
import AudioCore
import MusicTheory
import GameKitCore
import DesignSystem

/// Chord Chef (Harmony Harbor): build the triad Bop orders. Spec section 4; design/screens/ChordChef.dc.html.
/// Kids drag a note pad into the pot, or tap it (tap-to-place is the accessible alternative to drag).
struct ChordChefView: View {
    @Environment(AppModel.self) private var model

    private static let orders = 8

    @State private var flow = RoundFlow(totalRounds: ChordChefView.orders)
    @State private var order: ChordChefRules.Order?
    @State private var added: [PitchClass] = []
    @State private var feedback: Bool?
    @State private var dragging: PitchClass?
    @State private var dragOffset: CGSize = .zero
    @State private var potFrame: CGRect = .zero
    @State private var seed = UInt64.random(in: 0...UInt64.max)

    private var rules: ChordChefRules { ChordChefRules(key: .sunnyC, tier: model.tier(for: .chordChef)) }
    private var pads: [PitchClass] { rules.tier >= 3 ? PitchClass.allCases : PitchClass.allCases.filter(\.isNatural) }

    var body: some View {
        DesignCanvas(background: SI.Palette.sky) {
            ZStack(alignment: .top) {
                counter
                VStack(spacing: 0) {
                    topBar
                    HStack(alignment: .top, spacing: 40) {
                        orderCard
                        potArea
                        cookColumn
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    Spacer()
                    padShelf.padding(.bottom, 40)
                }
            }
            .coordinateSpace(name: "chef")
        }
        .onAppear(perform: nextOrder)
    }

    // MARK: Logic

    private func nextOrder() {
        order = rules.order(round: flow.round, seed: seed)
        added = []
        feedback = nil
        flow.startTrying()
        playTarget(delay: 0.3)
    }

    private func playTarget(delay: Double = 0) {
        guard let order else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            let midis = order.target.pitches(rootOctave: 4).map(\.midi)
            if flow.replaySlowerHint {
                // Hint: arpeggiate slowly so each ingredient can be heard.
                for m in midis { model.audio.playNote(m, instrument: .softPiano); try? await Task.sleep(for: .seconds(0.45)) }
            } else {
                model.audio.playChord(midis)
            }
        }
    }

    private func add(_ pc: PitchClass) {
        guard let order, flow.phase == .tryIt, added.count < order.needed.count else { return }
        model.audio.playNote(Pitch(pc, octave: 4).midi, instrument: .marimba)
        added.append(pc)
    }

    private func cook() {
        guard let order else { return }
        switch rules.check(order: order, added: added) {
        case .correct:
            model.audio.playChord(order.target.pitches().map(\.midi), velocity: 0.75)
            feedback = true
            flow.completeRound(correct: flow.missesThisRound == 0)
            advance()
        case .wrongNote(let offered, _, _):
            // Errorless: play what they made, then the real chord, remove the wrong note and keep going.
            let made = (order.given.map { order.target.pitchClass(for: $0) } + added).map { Pitch($0, octave: 4).midi }
            model.audio.playChord(made, velocity: 0.5)
            feedback = false
            flow.miss()
            if let i = added.lastIndex(of: offered) { added.remove(at: i) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                playTarget()
                try? await Task.sleep(for: .seconds(0.8))
                feedback = nil
            }
        case .needMore:
            break
        }
    }

    private func advance() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            flow.next()
            if case .reward = flow.phase {
                let info = model.finishGame(.chordChef, results: flow.results)
                model.path.removeLast()
                model.path.append(.reward(info))
            } else {
                nextOrder()
            }
        }
    }

    /// Pitch class that would complete the next empty slot. Used for the glow hint after 2 misses.
    private var hintNote: PitchClass? {
        guard flow.showGlowHint, let order else { return nil }
        var remaining = order.needed.map { order.target.pitchClass(for: $0) }
        for pc in added { if let i = remaining.firstIndex(of: pc) { remaining.remove(at: i) } }
        return remaining.first
    }

    // MARK: Views

    private var counter: some View {
        VStack(spacing: 0) {
            Spacer()
            Color(hex: 0xE8C285).frame(height: 14)
            SI.Palette.sand.frame(height: 236)
                .overlay(alignment: .top) { SI.Palette.ink900.frame(height: 5) }
        }
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(systemName: "pause.fill", label: "Pause") { model.path.removeLast() }
            Spacer()
            VStack(spacing: 6) {
                Text("Chord Chef").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Order \(min(flow.round + 1, Self.orders)) of \(Self.orders)").font(SI.Font.label).foregroundStyle(SI.Palette.ink500)
            }
            Spacer()
            Color.clear.frame(width: 76, height: 76)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    /// What Bop says for the current order, e.g. "Order up! Cook me G major, a sunny chord."
    private var orderLine: String {
        guard let t = order?.target else { return "Order up!" }
        return "Order up! Cook me \(t.kidName), \(t.quality.mood == .sunny ? "a sunny chord" : "a moonlight chord")."
    }

    private var orderCard: some View {
        VStack(spacing: 8) {
            BopView(mood: feedback == true ? .cheer : (feedback == false ? .wobble : .sing), size: 130)
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Text("Order up! Cook me...").font(SI.Font.body)
                    ReplayButton(line: orderLine)
                }
                if let t = order?.target {
                    HStack(spacing: 14) {
                        ChordBlock(triad: t)
                        VStack(alignment: .leading) {
                            Text(t.kidName).font(.system(size: 30, weight: .heavy, design: .rounded))
                            Text(t.quality.mood == .sunny ? "a sunny chord" : "a moonlight chord")
                                .font(SI.Font.label).foregroundStyle(SI.Palette.ink500)
                        }
                    }
                }
                Button { playTarget() } label: { Label("Hear it", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(BigButtonStyle(height: 64))
            }
            .padding(20)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 32).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(SI.Palette.ink900, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 32).fill(SI.Palette.ink900).offset(y: 7))
        }
        .narrates(orderLine)
    }

    private var potArea: some View {
        VStack(spacing: 24) {
            HStack(spacing: 36) {
                ForEach(ChordTone.allCases, id: \.self) { tone in slot(tone) }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 60)
                    .fill(Color(hex: 0x4D8DFF))
                    .overlay(RoundedRectangle(cornerRadius: 60).strokeBorder(SI.Palette.ink900, lineWidth: 5))
                    .frame(width: 340, height: 160)
                    .offset(y: 30)
                Ellipse()
                    .fill(Color(hex: 0xFFF0C7))
                    .overlay(Ellipse().strokeBorder(SI.Palette.ink900, lineWidth: 5))
                    .frame(width: 348, height: 46)
                    .offset(y: -50)
                if feedback == true {
                    FeedbackChip(correct: true).offset(y: -110)
                } else if feedback == false {
                    FeedbackChip(correct: false).offset(y: -110)
                }
            }
            .frame(width: 360, height: 220)
            .background(GeometryReader { g in Color.clear.onAppear { potFrame = g.frame(in: .named("chef")) } })
            .accessibilityElement()
            .accessibilityLabel("Cooking pot")
        }
    }

    /// Filled slots show the note; the next empty slot is dashed.
    private func slot(_ tone: ChordTone) -> some View {
        let pc = filled(tone)
        return VStack(spacing: 6) {
            ZStack {
                if let pc {
                    let s = NoteStyle.of(pc)
                    RoundedRectangle(cornerRadius: 26).fill(s.color)
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                    NoteShape(s.glyph).fill(.white.opacity(0.9)).frame(width: 50, height: 50)
                } else {
                    RoundedRectangle(cornerRadius: 26).fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(SI.Palette.ink900, style: StrokeStyle(lineWidth: 4, dash: [10, 8])))
                    Text("?").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(SI.Palette.ink500)
                }
            }
            .frame(width: 96, height: 96)
            Text(pc?.name ?? "?").font(SI.Font.body)
            Text(tone.rawValue).font(SI.Font.caption).foregroundStyle(SI.Palette.ink500)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tone.rawValue): \(pc?.name ?? "empty")")
    }

    private func filled(_ tone: ChordTone) -> PitchClass? {
        guard let order else { return nil }
        if order.given.contains(tone) { return order.target.pitchClass(for: tone) }
        guard let idx = order.needed.firstIndex(of: tone), idx < added.count else { return nil }
        return added[idx]
    }

    private var cookColumn: some View {
        let full = order.map { added.count >= $0.needed.count } ?? false
        let remaining = order.map { $0.needed.count - added.count } ?? 0
        return VStack(spacing: 12) {
            Spacer().frame(height: 250)
            Button("Cook!", action: cook)
                .buttonStyle(full ? BigButtonStyle.go : BigButtonStyle(fill: Color(hex: 0xE2DDF5), lip: SI.Palette.ink500, foreground: SI.Palette.ink900))
                .frame(width: 220)
                .disabled(!full)
            Text(full ? "Ready to cook!" : "Add \(remaining) more note\(remaining == 1 ? "" : "s")").font(SI.Font.label)
        }
    }

    private var padShelf: some View {
        let size: CGFloat = pads.count > 7 ? 78 : 120
        return HStack(spacing: pads.count > 7 ? 10 : 16) {
            ForEach(pads, id: \.self) { pc in
                NotePad(pc, showName: true, size: size, highlighted: hintNote == pc)
                    .offset(dragging == pc ? dragOffset : .zero)
                    .zIndex(dragging == pc ? 1 : 0)
                    .onTapGesture { add(pc) }
                    .gesture(
                        DragGesture(coordinateSpace: .named("chef"))
                            .onChanged { v in dragging = pc; dragOffset = v.translation }
                            .onEnded { v in
                                if potFrame.insetBy(dx: -40, dy: -40).contains(v.location) { add(pc) }
                                withAnimation(SI.spring) { dragging = nil; dragOffset = .zero }
                            }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Adds this note to the pot")
            }
        }
    }
}

/// Chord block: root color, sun face for major, moon face for minor.
struct ChordBlock: View {
    let triad: Triad
    var body: some View {
        let s = NoteStyle.of(triad.root)
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(s.color)
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(SI.Palette.ink900, lineWidth: 4))
            Image(systemName: triad.quality.mood == .sunny ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(triad.quality.mood == .sunny ? SI.Palette.star : .white)
                .shadow(color: SI.Palette.ink900, radius: 0, x: 0, y: 2)
        }
        .frame(width: 120, height: 90)
        .background(RoundedRectangle(cornerRadius: 24).fill(s.lip).offset(y: 5))
        .accessibilityLabel("\(triad.kidName) chord")
    }
}
