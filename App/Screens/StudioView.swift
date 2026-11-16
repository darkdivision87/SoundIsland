import SwiftUI
import Combine
import AudioCore
import StudioModel
import GameKitCore
import DesignSystem

/// Studio with the Beat Box tool. Matches design/screens/Studio.dc.html.
struct StudioView: View {
    @Environment(AppModel.self) private var model
    @State private var playing = false
    @State private var playhead: Int?
    @State private var surpriseRNG = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
    @State private var showConcert = false
    @State private var showMixer = false
    @State private var selectedTrack: TrackKind = .beats
    @State private var melodyTool: StudioTool = .melodyMaker
    @State private var recording = false
    @State private var lockedNudge: String?

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private struct RowStyle { let row: DrumRow; let on: Color; let off: Color; let icon: String }

    private let rows: [RowStyle] = [
        RowStyle(row: .kick, on: Color(hex: 0xFF5A5F), off: Color(hex: 0xFFE0E1), icon: "circle.circle"),
        RowStyle(row: .snare, on: Color(hex: 0xFFD23F), off: Color(hex: 0xFFF4CC), icon: "rectangle.split.3x1"),
        RowStyle(row: .hat, on: Color(hex: 0x22C3C9), off: Color(hex: 0xD4F3F4), icon: "triangle"),
        RowStyle(row: .clap, on: Color(hex: 0xA66BFF), off: Color(hex: 0xEDE1FF), icon: "hands.clap"),
    ]

    var body: some View {
        DesignCanvas(background: SI.Palette.sky) {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                HStack(alignment: .top, spacing: 24) {
                    if !model.preferences.leftHanded { trackRail }
                    VStack(alignment: .leading, spacing: 16) {
                        toolPanel
                        songStrip
                    }
                    if model.preferences.leftHanded { trackRail }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
        }
        .onReceive(ticker) { _ in playhead = model.audio.stepCount >= 0 ? model.audio.stepCount : nil }
        .onAppear {
            model.pushSongToAudio()
            if model.isToolUnlocked(.keys) && !model.isToolUnlocked(.melodyMaker) { melodyTool = .keys }
        }
        // A full-screen cover fires onDisappear here too; Concert owns the transport while it is up.
        .onDisappear { if !showConcert { model.audio.send(.stop) } }
        .fullScreenCover(isPresented: $showConcert, onDismiss: { playing = false; recording = false }) { ConcertView() }
        .sheet(isPresented: $showMixer) { MixerView() }
    }

    private func togglePlay() {
        if playing {
            model.audio.send(.stop)
            recording = false
        } else {
            model.pushSongToAudio()
            model.audio.send(.play(metronome: false, playPattern: true))
        }
        playing.toggle()
    }

    /// Keys recording plays the song with a click so kids can play along.
    private func toggleRecording() {
        model.audio.send(.stop)
        if recording {
            recording = false
            playing = false
        } else {
            model.pushSongToAudio()
            model.audio.send(.play(metronome: true, playPattern: true))
            recording = true
            playing = true
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch selectedTrack {
        case .beats:
            VStack(alignment: .leading, spacing: 16) {
                beatBox
                kitRow
            }
        case .melody:
            if melodyTool == .keys {
                KeysPanel(toolSwitch: melodyToolSwitch, recording: recording, toggleRecording: toggleRecording)
            } else {
                MelodyMakerPanel(toolSwitch: melodyToolSwitch, playhead: playing ? playhead : nil)
            }
        case .chords:
            ChordPadsPanel(playhead: playing ? playhead : nil)
        case .bass:
            EmptyView()
        }
    }

    /// Keys and Melody Maker both write the melody track; show the switch when both are unlocked.
    private var melodyToolSwitch: AnyView {
        let tools = [StudioTool.keys, .melodyMaker].filter { model.isToolUnlocked($0) }
        guard tools.count > 1 else { return AnyView(EmptyView()) }
        return AnyView(HStack(spacing: 6) {
            ForEach(tools, id: \.self) { tool in
                Button(tool == .keys ? "Keys" : "Grid") {
                    if recording { toggleRecording() }
                    melodyTool = tool
                }
                .font(SI.Font.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12).frame(height: model.minTarget)
                .foregroundStyle(melodyTool == tool ? .white : SI.Palette.ink900)
                .background(Capsule().fill(melodyTool == tool ? SI.Palette.ink900 : .white))
                .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                .accessibilityLabel(tool.displayName)
                .accessibilityAddTraits(melodyTool == tool ? .isSelected : [])
            }
        })
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            RoundIconButton(systemName: "house.fill", label: "Back to map") { model.path.removeLast() }
            Button(action: togglePlay) {
                Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 34, weight: .heavy))
            }
            .buttonStyle(BigButtonStyle(fill: SI.Palette.success, lip: SI.Palette.successDeep, foreground: SI.Palette.ink900, height: 76, cornerRadius: 30))
            .accessibilityLabel(playing ? "Stop" : "Play")

            tempoControl

            Label(model.profile.song.key.moodName, systemImage: "sun.max.fill")
                .font(SI.Font.label)
                .padding(.horizontal, 18).frame(height: 68)
                .background(Capsule().fill(Color(hex: 0xFFD23F)))
                .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))

            sectionTabs
            Spacer()
            if model.profile.ageBand == .makers {
                Button { showMixer = true } label: { Image(systemName: "slider.vertical.3").font(.system(size: 28, weight: .heavy)) }
                    .buttonStyle(BigButtonStyle(fill: .white, lip: SI.Palette.ink900, foreground: SI.Palette.ink900, height: 76, cornerRadius: 30, horizontalPadding: 18))
                    .accessibilityLabel("Mixer")
            }
            Button { model.audio.send(.stop); playing = false; recording = false; showConcert = true } label: { Label("Concert", systemImage: "star.fill") }
                .buttonStyle(BigButtonStyle(height: 76, cornerRadius: 30))
        }
    }

    private var tempoControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "tortoise.fill").foregroundStyle(Color(hex: 0x21A867)).accessibilityLabel("Slow")
            Slider(
                value: Binding(get: { model.profile.song.tempo }, set: { model.setTempo($0) }),
                in: Song.tempoRange, step: 2
            )
            .tint(SI.Palette.bop)
            .frame(width: 140)
            .accessibilityLabel("Speed")
            Image(systemName: "hare.fill").foregroundStyle(SI.Palette.ink900).accessibilityLabel("Fast")
        }
        .font(.system(size: 26))
        .padding(.horizontal, 16).frame(height: 68)
        .background(Capsule().fill(.white))
        .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
    }

    private var sectionTabs: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.profile.song.sections.enumerated()), id: \.offset) { i, section in
                Button(section.name) { model.selectSection(i) }
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .frame(width: 60, height: 64)
                    .foregroundStyle(model.selectedSection == i ? .white : SI.Palette.ink900)
                    .background(RoundedRectangle(cornerRadius: 20).fill(model.selectedSection == i ? SI.Palette.ink900 : .white))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                    .accessibilityAddTraits(model.selectedSection == i ? .isSelected : [])
                    .accessibilityLabel("Section \(section.name)")
            }
        }
    }

    // MARK: Track rail

    private var trackRail: some View {
        VStack(spacing: 14) {
            ForEach(TrackKind.allCases, id: \.self) { kind in
                let locked = !model.isTrackUnlocked(kind)
                let selected = selectedTrack == kind
                Button {
                    if locked {
                        lockedNudge = unlockHint(kind)
                    } else {
                        if recording { toggleRecording() }
                        lockedNudge = nil
                        selectedTrack = kind
                    }
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(trackColor(kind))
                            .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3.5))
                            .overlay(Image(systemName: locked ? "lock.fill" : trackIcon(kind)).font(.system(size: 22, weight: .bold)))
                            .frame(width: 52, height: 52)
                        Text(kind.displayName).font(SI.Font.label)
                    }
                    .foregroundStyle(SI.Palette.ink900)
                    .frame(width: 120, height: 120)
                    .background(RoundedRectangle(cornerRadius: 32).fill(selected ? .white : SI.Palette.sky))
                    .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(selected ? SI.Palette.bop : SI.Palette.ink900, lineWidth: selected ? 6 : 4))
                    .background(RoundedRectangle(cornerRadius: 32).fill(SI.Palette.ink900).offset(y: 6))
                    .opacity(locked ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.displayName) track\(locked ? ", locked" : selected ? ", selected" : "")")
            }
            if let lockedNudge {
                SpeechBubble(lockedNudge).frame(width: 120).font(SI.Font.caption)
                    .narrates(lockedNudge)
            }
        }
    }

    private func unlockHint(_ kind: TrackKind) -> String {
        switch kind {
        case .melody: "Play Bird Song or Echo Monkeys to unlock!"
        case .chords: "Play Chord Chef to unlock!"
        case .bass: "Bass comes with Bass Caves, soon!"
        case .beats: ""
        }
    }

    private func trackIcon(_ kind: TrackKind) -> String {
        switch kind {
        case .beats: "circle.grid.2x2.fill"
        case .bass: "speaker.wave.2.fill"
        case .chords: "square.stack.3d.up.fill"
        case .melody: "music.note"
        }
    }

    private func trackColor(_ kind: TrackKind) -> Color {
        switch kind {
        case .beats: Color(hex: 0xFF5A5F)
        case .bass: SI.Palette.locked
        case .chords: Color(hex: 0x4D8DFF)
        case .melody: Color(hex: 0xFFD23F)
        }
    }

    // MARK: Beat Box

    private var beatBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Beat Box").font(SI.Font.headline)
                Spacer()
                Text("Tap a box to add a sound").font(SI.Font.label).foregroundStyle(SI.Palette.ink500)
                ReplayButton(line: "Tap a box to add a sound")
                    .narrates("Tap a box to add a sound")
            }
            ForEach(rows, id: \.row) { style in
                let row = style.row, on = style.on, off = style.off, icon = style.icon
                HStack(spacing: 12) {
                    Button { model.audio.playDrum(drumSound(row)) } label: {
                        Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(SI.Palette.ink900)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(on))
                            .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hear \(row.displayName)")
                    // Explorers (6-7): 8 eighth-note cells, 64 pt tall. Makers (8-10): 16 sixteenth-note cells.
                    let perBeat = coarse ? 2 : 4
                    HStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { beat in
                            HStack(spacing: 4) {
                                ForEach(0..<perBeat, id: \.self) { k in
                                    cell(row: row, step: (beat * perBeat + k) * stride, on: on, off: off)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 36).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(SI.Palette.ink900, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 36).fill(SI.Palette.ink900).offset(y: 7))
    }

    /// 8-step grid for Explorers, 16-step for Makers (spec section 6). In 8-step mode each cell owns an eighth note.
    private var coarse: Bool { model.profile.ageBand.studioSteps == 8 }
    private var stride: Int { coarse ? 2 : 1 }

    private func cell(row: DrumRow, step: Int, on: Color, off: Color) -> some View {
        let isOn = model.beatGrid.isOn(row, step: step)
        let isHead = playing && playhead.map { ($0 % 16) / stride == step / stride } == true
        let width: CGFloat = coarse ? 103 : 50 // both fill the 986 pt panel in Studio.dc.html
        let height: CGFloat = coarse ? 64 : 50
        return Button {
            var g = model.beatGrid
            g.toggle(row, step: step)
            model.beatGrid = g
            if !isOn { model.audio.playDrum(drumSound(row), velocity: 0.6) }
        } label: {
            RoundedRectangle(cornerRadius: 14)
                .fill(isOn ? on : off)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOn ? SI.Palette.ink900 : SI.Palette.ink900.opacity(0.25), lineWidth: 3))
                .background(RoundedRectangle(cornerRadius: 14).fill(isOn ? SI.Palette.ink900 : .clear).offset(y: 4))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(SI.Palette.bop, lineWidth: isHead ? 4 : 0).padding(-6))
                .scaleEffect(isHead && isOn ? 1.08 : 1)
                .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.displayName) step \(step / stride + 1)")
        .accessibilityValue(isOn ? "on" : "off")
    }

    private func drumSound(_ row: DrumRow) -> DrumSound {
        switch row {
        case .kick: .kick
        case .snare: .snare
        case .hat: .hat
        case .clap: .clap
        }
    }

    // MARK: Kits and song strip

    private var kitRow: some View {
        HStack(spacing: 10) {
            Text("Kit:").font(SI.Font.body)
            ForEach(DrumKit.allCases, id: \.self) { kit in
                let sel = model.profile.song.kit == kit
                Button(kit.displayName) { model.setKit(kit) }
                    .font(SI.Font.label)
                    .padding(.horizontal, 18).frame(height: 56)
                    .foregroundStyle(sel ? .white : SI.Palette.ink900)
                    .background(Capsule().fill(sel ? SI.Palette.ink900 : .white))
                    .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
                    .accessibilityAddTraits(sel ? .isSelected : [])
            }
            Spacer()
            Button { model.beatGrid = BeatGrid.surprise(using: &surpriseRNG) } label: {
                Label("Surprise me", systemImage: "sparkles")
            }
            .buttonStyle(BigButtonStyle(fill: SI.Palette.star, lip: Color(hex: 0xD2A515), foreground: SI.Palette.ink900, height: 64, cornerRadius: 28))
        }
    }

    /// The song order. Tap a part to change which section it plays; copy a section to start a new one.
    private var songStrip: some View {
        let song = model.profile.song
        let partWidth: CGFloat = song.arrangement.count > 4 ? 96 : 150
        return HStack(spacing: 10) {
            Text("My song").font(SI.Font.body)
            ForEach(Array(song.arrangement.enumerated()), id: \.offset) { i, sectionIndex in
                let name = song.sections[sectionIndex].name
                let active = sectionIndex == model.selectedSection
                ZStack(alignment: .topTrailing) {
                    Button {
                        if song.sections.count > 1 { model.editSong { $0.cycleArrangementSlot(i) } }
                    } label: {
                        HStack(spacing: 6) {
                            Text(name).font(SI.Font.headline)
                            if partWidth > 100 { Text("\(song.sections[sectionIndex].bars) bars").font(SI.Font.caption) }
                        }
                        .foregroundStyle(active ? .white : SI.Palette.ink900)
                        .frame(width: partWidth, height: 64)
                        .background(RoundedRectangle(cornerRadius: 20).fill(active ? SI.Palette.bop : .white))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Part \(i + 1): section \(name)")
                    .accessibilityHint(song.sections.count > 1 ? "Tap to change the section" : "")
                    if song.arrangement.count > 1 {
                        Button { model.editSong { $0.removePart(i) } } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.white))
                                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 2.5))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 14, y: -14)
                        .accessibilityLabel("Remove part \(i + 1)")
                    }
                }
            }
            Button { model.editSong { $0.appendPart(section: model.selectedSection) } } label: {
                Image(systemName: "plus").font(.system(size: 26, weight: .heavy))
                    .frame(width: 64, height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SI.Palette.ink900, style: StrokeStyle(lineWidth: 4, dash: [8, 6])))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a part")
            .disabled(song.arrangement.count >= 8)
            Spacer(minLength: 0)
            Button {
                model.editSong { $0.duplicateSection(at: model.selectedSection) }
                model.selectSection(model.profile.song.sections.count - 1)
            } label: { Label("Copy", systemImage: "doc.on.doc.fill") }
                .buttonStyle(BigButtonStyle(fill: .white, lip: SI.Palette.ink900, foreground: SI.Palette.ink900, height: 64, cornerRadius: 24, horizontalPadding: 16))
                .disabled(song.sections.count >= Song.maxSectionsMVP)
                .accessibilityLabel("Copy this section into a new one")
        }
        .padding(12)
        .frame(width: 986)
        .background(RoundedRectangle(cornerRadius: 30).fill(SI.Palette.bopTint))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(SI.Palette.ink900, lineWidth: 4))
    }
}
