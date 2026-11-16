import SwiftUI
import Combine
import QuartzCore
import AudioCore
import MusicTheory
import StudioModel
import GameKitCore
import DesignSystem

/// Shared card look for Studio tool panels (Studio.dc.html panel style).
struct StudioPanel<Content: View>: View {
    let title: String
    let hint: String
    @ViewBuilder var trailing: () -> AnyView
    @ViewBuilder var content: () -> Content

    init(title: String, hint: String, trailing: @escaping () -> AnyView = { AnyView(EmptyView()) },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.hint = hint
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(title).font(SI.Font.headline).foregroundStyle(SI.Palette.ink900)
                trailing()
                Spacer()
                Text(hint).font(SI.Font.label).foregroundStyle(SI.Palette.ink500).lineLimit(1).minimumScaleFactor(0.7)
                ReplayButton(line: hint).narrates(hint)
            }
            content()
        }
        .padding(18)
        .frame(width: 986, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 36).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(SI.Palette.ink900, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 36).fill(SI.Palette.ink900).offset(y: 7))
    }
}

// MARK: - Keys (Pitch Peaks): scale-locked keyboard with quantized recording

struct KeysPanel: View {
    @Environment(AppModel.self) private var model
    var toolSwitch: AnyView = AnyView(EmptyView())
    let recording: Bool
    let toggleRecording: () -> Void
    @State private var pressed: Int?

    private var keys: [Pitch] {
        let scale = model.profile.song.key.scale
        // Explorers: one octave + home (8 big keys). Makers: two octaves + home (15 keys).
        return scale.pitches(fromOctave: 4, count: model.profile.ageBand == .explorers ? 8 : 15)
    }

    var body: some View {
        StudioPanel(title: "Keys", hint: recording ? "Play along! Bop keeps your notes." : "Play the keys, or press Record",
                    trailing: { AnyView(controls) }) {
            let w = (950 - CGFloat(keys.count - 1) * 4) / CGFloat(keys.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 4) {
                    ForEach(keys.indices, id: \.self) { i in
                        let pc = keys[i].pitchClass
                        let style = NoteStyle.of(pc)
                        VStack(spacing: 8) {
                            Spacer()
                            NoteBadge(pc, size: min(44, w * 0.6))
                            Text(pc.name).font(SI.Font.label).foregroundStyle(SI.Palette.ink900)
                        }
                        .padding(.bottom, 14)
                        .frame(width: w, height: 250)
                        .background(RoundedRectangle(cornerRadius: 16).fill(style.color.opacity(pressed == i ? 1 : 0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SI.Palette.ink900, lineWidth: 3))
                        .offset(y: pressed == i ? 4 : 0)
                        .accessibilityElement()
                        .accessibilityLabel("Key \(pc.name)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { press(i, hostSeconds: CACurrentMediaTime()) }
                    }
                }
                // Hardware touch timestamps so recorded notes land where the finger did (audio clock).
                TapCaptureView { host, location in
                    let i = Int(location.x / (w + 4))
                    guard keys.indices.contains(i) else { return }
                    press(i, hostSeconds: host)
                }
                .frame(width: 950, height: 250)
                .accessibilityHidden(true)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            toolSwitch
            Button(action: toggleRecording) {
                Label(recording ? "Stop" : "Record", systemImage: recording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(BigButtonStyle(fill: recording ? SI.Palette.tryAgain : .white, lip: SI.Palette.ink900,
                                        foreground: SI.Palette.ink900, height: model.minTarget, cornerRadius: 24, horizontalPadding: 16))
            Button { model.setTrackNotes(.melody, []) } label: { Label("Clear", systemImage: "eraser.fill") }
                .buttonStyle(BigButtonStyle(fill: .white, lip: SI.Palette.ink900, foreground: SI.Palette.ink900,
                                            height: model.minTarget, cornerRadius: 24, horizontalPadding: 16))
        }
    }

    private func press(_ i: Int, hostSeconds: Double) {
        let pitch = keys[i]
        model.audio.playNote(pitch.midi, instrument: .marimba)
        withAnimation(.easeOut(duration: 0.08)) { pressed = i }
        after(0.15) { if pressed == i { pressed = nil } }
        guard recording, model.audio.isPlaying else { return }
        let t = model.audio.transportSeconds(forHostSeconds: hostSeconds)
        let q = RecordQuantizer(secondsPerStep: 60 / model.profile.song.tempo / 4, loopSteps: 32)
        let step = q.step(at: t)
        model.setTrackNotes(.melody, RecordQuantizer.record(pitch, step: step, into: model.track(.melody)?.notes ?? []))
    }
}

// MARK: - Melody Maker (Melody Jungle): 8 in-key rows x 16 eighth notes

struct MelodyMakerPanel: View {
    @Environment(AppModel.self) private var model
    var toolSwitch: AnyView = AnyView(EmptyView())
    let playhead: Int?
    @State private var page = 0

    private var grid: MelodyGrid { MelodyGrid(scale: model.profile.song.key.scale, notes: model.track(.melody)?.notes ?? []) }
    private var explorers: Bool { model.profile.ageBand == .explorers }
    /// Explorers see one bar (8 columns at 64 pt) at a time; Makers see both bars.
    private var columns: Range<Int> { explorers ? (page * 8)..<(page * 8 + 8) : 0..<16 }

    var body: some View {
        StudioPanel(title: "Melody Maker", hint: "Tap the squares to make a tune", trailing: { AnyView(pager) }) {
            let g = grid
            let cellW: CGFloat = explorers ? 104 : 54
            // Hit area is the full touch target (64 pt Explorers, 52 pt Makers); the drawing is inset.
            let cellH: CGFloat = model.minTarget
            HStack(spacing: 6) {
                VStack(spacing: 0) {
                    ForEach((0..<8).reversed(), id: \.self) { r in
                        NoteBadge(g.rows[r].pitchClass, size: 28).frame(width: 40, height: cellH)
                    }
                }
                ForEach(columns, id: \.self) { c in
                    VStack(spacing: 0) {
                        ForEach((0..<8).reversed(), id: \.self) { r in
                            cell(g, column: c, row: r, width: cellW, height: cellH)
                        }
                    }
                    .padding(.leading, c % 8 == 0 && c > columns.lowerBound ? 10 : 0)
                }
            }
        }
    }

    private var pager: some View {
        HStack(spacing: 8) {
            toolSwitch
            if explorers {
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { p in
                        Button("Bar \(p + 1)") { page = p }
                            .font(SI.Font.label)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14).frame(height: model.minTarget)
                            .foregroundStyle(page == p ? .white : SI.Palette.ink900)
                            .background(Capsule().fill(page == p ? SI.Palette.ink900 : .white))
                            .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                            .accessibilityAddTraits(page == p ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func cell(_ g: MelodyGrid, column c: Int, row r: Int, width: CGFloat, height: CGFloat) -> some View {
        let on = g.isOn(column: c, row: r)
        let pitch = g.rows[r]
        let style = NoteStyle.of(pitch.pitchClass)
        // Playhead in eighth-note columns; the melody repeats every 2 bars (32 steps).
        let head = playhead.map { ($0 % 32) / 2 == c } ?? false
        return Button {
            var next = g
            next.toggle(column: c, row: r)
            if !on { model.audio.playNote(pitch.midi) }
            model.setTrackNotes(.melody, next.notes)
        } label: {
            RoundedRectangle(cornerRadius: 10)
                .fill(on ? style.color : style.color.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SI.Palette.ink900.opacity(on ? 1 : 0.2), lineWidth: on ? 3 : 1.5))
                .overlay { if on { NoteShape(style.glyph).fill(.white).frame(width: 18, height: 18) } }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SI.Palette.bop, lineWidth: head ? 3 : 0).padding(-3))
                .padding(3)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pitch.pitchClass.name), beat \(c / 2 + 1)")
        .accessibilityValue(on ? "on" : "off")
    }
}

// MARK: - Chord Pads (Harmony Harbor): 8 diatonic pads, one chord per bar

struct ChordPadsPanel: View {
    @Environment(AppModel.self) private var model
    let playhead: Int?
    @State private var selectedBar = 0
    @State private var lastVoicing: [Int]?

    private var key: Key { model.profile.song.key }
    private var bars: Int { model.profile.song.sections[model.selectedSection].bars }
    private var style: ChordStyle { ChordStyle(rawValue: model.profile.song.chordStyle ?? "") ?? .block }
    private var degrees: [Int?] { ChordLane.degrees(from: model.track(.chords)?.notes ?? [], key: key, bars: bars) }

    var body: some View {
        StudioPanel(title: "Chord Pads", hint: "Pick a bar, then tap a chord", trailing: { AnyView(stylePicker) }) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ForEach(0..<bars, id: \.self) { b in barSlot(b) }
                    Button { write(Array(repeating: nil, count: bars)) } label: { Label("Clear", systemImage: "eraser.fill") }
                        .buttonStyle(BigButtonStyle(fill: .white, lip: SI.Palette.ink900, foreground: SI.Palette.ink900,
                                                    height: model.minTarget, cornerRadius: 24, horizontalPadding: 16))
                }
                HStack(spacing: 10) {
                    ForEach(ChordLane.padDegrees, id: \.self) { d in pad(d) }
                }
            }
        }
    }

    private var stylePicker: some View {
        HStack(spacing: 6) {
            ForEach(ChordStyle.allCases, id: \.self) { s in
                Button(s.displayName) {
                    model.editSong { $0.chordStyle = s.rawValue }
                    write(degrees, style: s)
                }
                .font(SI.Font.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12).frame(height: model.minTarget)
                .foregroundStyle(style == s ? .white : SI.Palette.ink900)
                .background(Capsule().fill(style == s ? SI.Palette.ink900 : .white))
                .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                .accessibilityAddTraits(style == s ? .isSelected : [])
            }
        }
    }

    private func barSlot(_ b: Int) -> some View {
        let d = degrees.indices.contains(b) ? degrees[b] : nil
        let playing = playhead.map { ($0 % (bars * 16)) / 16 == b } ?? false
        return Button { selectedBar = b } label: {
            Group {
                if let d { chordFace(d, size: 120) } else {
                    Text("\(b + 1)").font(SI.Font.title).foregroundStyle(SI.Palette.ink500)
                        .frame(width: 120, height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(SI.Palette.ink900, style: StrokeStyle(lineWidth: 4, dash: [9, 8])))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(SI.Palette.bop, lineWidth: selectedBar == b ? 6 : 0).padding(-8))
            .scaleEffect(playing ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bar \(b + 1)\(d.map { ", \(ChordLane.triad(degree: $0, in: key).kidName)" } ?? ", empty")")
        .accessibilityAddTraits(selectedBar == b ? .isSelected : [])
    }

    private func pad(_ d: Int) -> some View {
        Button {
            var voicing = ChordVoicing.voiceLead(ChordLane.triad(degree: d, in: key), from: lastVoicing)
            if d == 8 { voicing = voicing.map { $0 + 12 } }
            model.audio.playChord(voicing, velocity: 0.55)
            lastVoicing = voicing
            var next = degrees
            if next.indices.contains(selectedBar) { next[selectedBar] = d }
            write(next)
            selectedBar = (selectedBar + 1) % bars
        } label: { chordFace(d, size: 106) }
        .buttonStyle(.plain)
        .accessibilityLabel("\(key.romanNumeral(degree: (d - 1) % 7 + 1)) chord, \(ChordLane.triad(degree: d, in: key).kidName)")
    }

    private func chordFace(_ d: Int, size: CGFloat) -> some View {
        let triad = ChordLane.triad(degree: d, in: key)
        let s = NoteStyle.of(triad.root)
        return VStack(spacing: 4) {
            NoteBadge(triad.root, size: size * 0.24, outline: SI.Palette.ink900)
            Text(key.romanNumeral(degree: (d - 1) % 7 + 1)).font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
            NoteColorChip(d == 8 ? "\(triad.root.name) high" : triad.kidName, size: size * 0.12)
        }
        .foregroundStyle(SI.Palette.ink900)
        .padding(.horizontal, 6)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 24).fill(s.color))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(SI.Palette.ink900, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 24).fill(s.lip).offset(y: 6))
    }

    private func write(_ degrees: [Int?], style: ChordStyle? = nil) {
        model.setTrackNotes(.chords, ChordLane.events(degrees: degrees, key: key, style: style ?? self.style))
    }
}

// MARK: - Mixer (8-10): track volumes, mute and FX stickers

struct MixerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Mixer").font(SI.Font.title)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(BigButtonStyle.primary)
            }
            ForEach(TrackKind.allCases.filter { model.isTrackUnlocked($0) }, id: \.self) { kind in
                if let track = model.track(kind) {
                    HStack(spacing: 16) {
                        Text(kind.displayName).font(SI.Font.headline).frame(width: 120, alignment: .leading)
                        Button { model.updateTrack(kind) { $0.muted.toggle() } } label: {
                            Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 26, weight: .bold))
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(track.muted ? SI.Palette.tryAgain : .white))
                                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(track.muted ? "Unmute \(kind.displayName)" : "Mute \(kind.displayName)")
                        Slider(value: Binding(get: { Double(track.volume) },
                                              set: { v in model.updateTrack(kind) { $0.volume = Float(v) } }),
                               in: 0...0.8)
                            .tint(SI.Palette.bop)
                            .accessibilityLabel("\(kind.displayName) volume")
                    }
                }
            }
            Text("Effect stickers").font(SI.Font.headline)
            HStack(spacing: 16) {
                ForEach(FXSticker.allCases) { fx in
                    let on = (model.profile.song.fxStickers ?? []).contains(fx.rawValue)
                    Button { model.toggleFX(fx) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: fx.icon).font(.system(size: 34, weight: .bold))
                            Text(fx.displayName).font(SI.Font.label)
                        }
                        .foregroundStyle(SI.Palette.ink900)
                        .frame(width: 140, height: 120)
                        .background(RoundedRectangle(cornerRadius: 28).fill(on ? SI.Palette.star : .white))
                        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                        .rotationEffect(.degrees(on ? -3 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(fx.displayName) effect")
                    .accessibilityValue(on ? "on" : "off")
                }
            }
            Spacer()
        }
        .padding(40)
        .foregroundStyle(SI.Palette.ink900)
        .background(SI.Palette.sky)
    }
}

// MARK: - Concert mode: the whole song, part after part

struct ConcertView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var loop = PlaybackLoop(hits: [], steps: 0)
    @State private var step = -1
    @State private var finished = false
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var partStarts: [Int] {
        var starts: [Int] = []
        var offset = 0
        for i in model.profile.song.arrangement { starts.append(offset); offset += model.profile.song.sections[i].steps }
        return starts
    }

    private var currentPart: Int? {
        guard step >= 0, !finished else { return nil }
        return partStarts.lastIndex { $0 <= step }
    }

    var body: some View {
        DesignCanvas(background: SI.Palette.bop) {
            VStack(spacing: 36) {
                Text(model.profile.song.title).font(SI.Font.display).foregroundStyle(.white)
                BopView(mood: finished ? .cheer : .sing, size: 200)
                    .scaleEffect(step >= 0 && step % 4 == 0 && !finished ? 1.06 : 1)
                    .animation(.easeOut(duration: 0.12), value: step / 4)
                HStack(spacing: 14) {
                    ForEach(Array(model.profile.song.arrangement.enumerated()), id: \.offset) { i, s in
                        Text(model.profile.song.sections[s].name)
                            .font(SI.Font.title)
                            .frame(width: 90, height: 90)
                            .foregroundStyle(SI.Palette.ink900)
                            .background(RoundedRectangle(cornerRadius: 24).fill(currentPart == i ? SI.Palette.star : .white))
                            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                            .scaleEffect(currentPart == i ? 1.12 : 1)
                    }
                }
                HStack(spacing: 20) {
                    if finished {
                        Button { start() } label: { Label("Play again", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(BigButtonStyle.go)
                    }
                    Button { stop(); dismiss() } label: { Label(finished ? "Back to my song" : "Stop", systemImage: finished ? "music.note" : "stop.fill") }
                        .buttonStyle(BigButtonStyle.secondary)
                }
            }
            .frame(width: 1194, height: 834)
            .narrates(finished ? "What a concert! Bravo!" : "Here comes your song!")
        }
        .statusBarHidden()
        .onAppear(perform: start)
        .onDisappear { stop(); model.pushSongToAudio() }
        .onReceive(ticker) { _ in
            guard !finished else { return }
            let s = model.audio.stepCount
            if s >= 0 { step = s }
            if loop.steps > 0, s >= loop.steps { finished = true; stop() }
        }
    }

    private func start() {
        finished = false
        step = -1
        loop = model.profile.song.concert()
        model.audio.send(.stop)
        model.audio.send(.setTempo(model.profile.song.tempo))
        // One silent bar of tail so the loop never wraps back to the start before we stop it.
        model.audio.loadLoop(AppModel.slots(loop), steps: loop.steps + 16)
        model.pushMixToAudio()
        model.audio.send(.play(metronome: false, playPattern: false))
    }

    private func stop() { model.audio.send(.stop) }
}
