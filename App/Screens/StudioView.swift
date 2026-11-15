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
            VStack(alignment: .leading, spacing: 24) {
                topBar
                HStack(alignment: .top, spacing: 24) {
                    trackRail
                    VStack(alignment: .leading, spacing: 16) {
                        beatBox
                        kitRow
                        songStrip
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
        }
        .onReceive(ticker) { _ in playhead = model.audio.currentStep }
        .onAppear { model.pushSongToAudio() }
        .onDisappear { model.audio.send(.stop) }
        .sheet(isPresented: $showConcert) { ConcertPlaceholder() }
    }

    private func togglePlay() {
        if playing {
            model.audio.send(.stop)
        } else {
            model.pushSongToAudio()
            model.audio.send(.play(metronome: false, playPattern: true))
        }
        playing.toggle()
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
            Button { showConcert = true } label: { Label("Concert", systemImage: "star.fill") }
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
                let locked = kind != .beats // Phase 1: only Beat Box is built
                VStack(spacing: 4) {
                    Circle()
                        .fill(trackColor(kind))
                        .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3.5))
                        .overlay(Image(systemName: locked ? "lock.fill" : "face.smiling").font(.system(size: 22, weight: .bold)))
                        .frame(width: 52, height: 52)
                    Text(kind.displayName).font(SI.Font.label)
                }
                .frame(width: 120, height: 120)
                .background(RoundedRectangle(cornerRadius: 32).fill(kind == .beats ? .white : SI.Palette.sky))
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(kind == .beats ? SI.Palette.bop : SI.Palette.ink900, lineWidth: 4))
                .background(RoundedRectangle(cornerRadius: 32).fill(SI.Palette.ink900).offset(y: 6))
                .opacity(locked ? 0.6 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(kind.displayName) track\(locked ? ", locked" : ", selected")")
            }
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
                    HStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { group in
                            HStack(spacing: 4) {
                                ForEach(0..<4, id: \.self) { k in cell(row: row, step: group * 4 + k, on: on, off: off) }
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

    private func cell(row: DrumRow, step: Int, on: Color, off: Color) -> some View {
        let isOn = model.beatGrid.isOn(row, step: step)
        let isHead = playing && playhead == step
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
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.displayName) step \(step + 1)")
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

    private var songStrip: some View {
        HStack(spacing: 12) {
            Text("My song").font(SI.Font.body)
            ForEach(Array(model.profile.song.arrangement.enumerated()), id: \.offset) { i, sectionIndex in
                let name = model.profile.song.sections[sectionIndex].name
                let active = sectionIndex == model.selectedSection
                HStack(spacing: 8) {
                    Text(name).font(SI.Font.body)
                    Text("\(model.profile.song.sections[sectionIndex].bars) bars").font(SI.Font.caption)
                }
                .foregroundStyle(active ? .white : SI.Palette.ink900)
                .padding(.horizontal, 14).frame(width: 180, height: 64, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(active ? SI.Palette.bop : .white))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                .accessibilityLabel("Part \(i + 1): section \(name)")
            }
            Button {
                if model.profile.song.addSection() { model.save() }
            } label: {
                Image(systemName: "plus").font(.system(size: 26, weight: .heavy))
                    .frame(width: 64, height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(SI.Palette.ink900, style: StrokeStyle(lineWidth: 4, dash: [8, 6])))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a section")
            .disabled(model.profile.song.sections.count >= Song.maxSectionsMVP)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 30).fill(SI.Palette.bopTint))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(SI.Palette.ink900, lineWidth: 4))
    }
}

struct ConcertPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            BopView(mood: .cheer, size: 180)
            Text("Concert mode is coming soon!").font(SI.Font.title)
            Button("Back to my song") { dismiss() }.buttonStyle(BigButtonStyle.primary)
        }
        .padding(60)
    }
}
