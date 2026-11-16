import SwiftUI
import MusicTheory
import StudioModel
import GameKitCore
import DesignSystem

/// Melody Paint (Melody Jungle): paint scale-snapped notes on a grid, then hear it and keep it in your
/// song (it goes to the melody track of the current Studio section). Spec section 4. No wrong answers:
/// Bop only nudges (more notes, or end on home when the tier asks).
struct MelodyPaintView: View {
    @Environment(AppModel.self) private var model

    @State private var canvas = MelodyCanvas(scale: Scale(tonic: .c, type: .major), columns: 8)
    @State private var playhead: Int?
    @State private var nudge: String?
    @State private var finished = false
    @State private var sequencer: Sequencer?

    private var requireHome: Bool {
        let t = model.tierSpec(for: .melodyPaint)
        return t.bool("endOnHome", default: false) || t.int("phrases", default: 1) > 1
    }

    private var instruction: String {
        if finished { return "What a melody! It's in your song now." }
        if let nudge { return nudge }
        return requireHome ? "Paint a melody that ends on home, the red circle!" : "Paint a melody! Tap the squares to add notes."
    }

    var body: some View {
        GameShell(title: "Melody Paint", rounds: 1, done: 0, instruction: instruction,
                  background: Color(hex: 0xE3F6DA), bopMood: finished ? .cheer : .idle) {
            ZStack(alignment: .topLeading) {
                grid.position(x: 597, y: 472)
                HStack(spacing: 24) {
                    Button { canvas = MelodyCanvas(scale: canvas.scale, columns: canvas.columns, phraseLength: canvas.phraseLength) } label: {
                        Label("Clear", systemImage: "eraser.fill")
                    }
                    .buttonStyle(BigButtonStyle.secondary)
                    Button { play() } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(BigButtonStyle.primary)
                    Button { done() } label: { Label("Done", systemImage: "checkmark") }
                        .buttonStyle(BigButtonStyle.go)
                }
                .disabled(finished)
                .position(x: 597, y: 780)
            }
        }
        .onAppear {
            sequencer = Sequencer(audio: model.audio)
            let t = model.tierSpec(for: .melodyPaint)
            let phrases = t.int("phrases", default: 1)
            let columns = phrases > 1 ? 16 : t.int("maxNotes", default: 5)
            canvas = MelodyCanvas(scale: Scale(tonic: .c, type: .major), columns: columns, phraseLength: phrases > 1 ? 8 : nil)
        }
        .onDisappear { sequencer?.cancel() }
    }

    private var cellSize: CGFloat {
        let byWidth = min(120, 1080 / CGFloat(canvas.columns))
        return max(model.minTarget, min(byWidth, 66))
    }

    private var grid: some View {
        let rows = canvas.rows
        let s = cellSize
        return HStack(spacing: 0) {
            // Row key: each row's note glyph, so kids can read the grid by shape and color.
            VStack(spacing: 0) {
                ForEach((0..<rows.count).reversed(), id: \.self) { r in
                    NoteBadge(rows[r].pitchClass, size: 30).frame(height: model.minTarget)
                }
            }
            .padding(.trailing, 12)
            ForEach(0..<canvas.columns, id: \.self) { c in
                VStack(spacing: 0) {
                    ForEach((0..<rows.count).reversed(), id: \.self) { r in
                        let pc = rows[r].pitchClass
                        let on = canvas.cells[c] == r
                        let style = NoteStyle.of(pc)
                        Button {
                            canvas.toggle(column: c, row: r)
                            if canvas.cells[c] == r { model.audio.playNote(rows[r].midi) }
                            nudge = nil
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(on ? style.color : style.color.opacity(0.32))
                                RoundedRectangle(cornerRadius: 10).strokeBorder(SI.Palette.ink900.opacity(on ? 1 : 0.25), lineWidth: on ? 3 : 1.5)
                                if on {
                                    NoteShape(style.glyph).fill(.white).overlay(NoteShape(style.glyph).stroke(SI.Palette.ink900, lineWidth: 2))
                                        .frame(width: s * 0.45, height: s * 0.45)
                                }
                            }
                            .padding(2)
                            .frame(width: s - 2, height: model.minTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pc.name), beat \(c + 1)\(on ? ", on" : "")")
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 12).fill(playhead == c ? SI.Palette.star.opacity(0.5) : .clear))
                .padding(.leading, c > 0 && c % canvas.phraseLength == 0 ? 24 : 0)
            }
        }
    }

    private func play(done: (@MainActor () -> Void)? = nil) {
        let rows = canvas.rows
        sequencer?.play(canvas.cells.map { $0.map { [rows[$0].midi] } ?? [] }, gap: 0.42,
                        onStep: { i in playhead = i >= 0 ? i : nil }, done: done)
    }

    private func done() {
        switch canvas.readiness(requireHomeEnding: requireHome) {
        case .needMoreNotes: nudge = "Add a few more notes first!"
        case .needHomeEnding: nudge = "Almost! Make the last note home, the red circle C."
        case .ready:
            finished = true
            let events = canvas.noteEvents().map { NoteEvent(tick: $0.tick, pitch: $0.pitch, lengthTicks: $0.length) }
            model.setTrackNotes(.melody, events)
            play { after(0.6) { model.endGame(.melodyPaint, results: [true]) } }
        }
    }
}
