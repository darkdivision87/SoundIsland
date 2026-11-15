import SwiftUI
import Curriculum
import DesignSystem

/// Hub screen. Matches design/screens/Main.dc.html.
struct WorldMapView: View {
    @Environment(AppModel.self) private var model
    @State private var showGate = false

    private struct Spot { let island: IslandID; let x: CGFloat; let y: CGFloat; let color: Color; let emblem: String }

    private let spots: [Spot] = [
        Spot(island: .beatBeach, x: 40, y: 440, color: Color(hex: 0xFF9A3C), emblem: "drum"),
        Spot(island: .pitchPeaks, x: 230, y: 180, color: Color(hex: 0x22C3C9), emblem: "mountain.2"),
        Spot(island: .melodyJungle, x: 430, y: 430, color: Color(hex: 0x3DD68C), emblem: "leaf"),
        Spot(island: .harmonyHarbor, x: 620, y: 160, color: Color(hex: 0x4D8DFF), emblem: "sailboat"),
        Spot(island: .bassCaves, x: 810, y: 430, color: Color(hex: 0xA66BFF), emblem: "waveform"),
        Spot(island: .songVolcano, x: 990, y: 170, color: Color(hex: 0xFF5A5F), emblem: "mountain.2.fill"),
        Spot(island: .mixLab, x: 1110, y: 470, color: Color(hex: 0xFFD23F), emblem: "slider.vertical.3"),
    ]

    var body: some View {
        DesignCanvas(background: SI.Palette.ocean) {
            ZStack(alignment: .topLeading) {
                SI.Palette.ocean
                pathTrail
                ForEach(spots, id: \.island) { spot in
                    islandButton(spot).position(x: spot.x + 95, y: spot.y + 95)
                }
                bop
                topBar
                dock
            }
        }
        .sheet(isPresented: $showGate) { ParentGateView { model.path.append(.parentArea) } }
    }

    private var pathTrail: some View {
        Path { p in
            p.move(to: CGPoint(x: 135, y: 530))
            p.addCurve(to: CGPoint(x: 325, y: 270), control1: CGPoint(x: 200, y: 410), control2: CGPoint(x: 260, y: 330))
            p.addCurve(to: CGPoint(x: 525, y: 520), control1: CGPoint(x: 390, y: 210), control2: CGPoint(x: 470, y: 480))
            p.addCurve(to: CGPoint(x: 715, y: 250), control1: CGPoint(x: 580, y: 560), control2: CGPoint(x: 660, y: 270))
            p.addCurve(to: CGPoint(x: 905, y: 520), control1: CGPoint(x: 770, y: 230), control2: CGPoint(x: 850, y: 480))
            p.addCurve(to: CGPoint(x: 1085, y: 260), control1: CGPoint(x: 960, y: 560), control2: CGPoint(x: 1040, y: 270))
        }
        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [2, 18]))
        .accessibilityHidden(true)
    }

    private func islandButton(_ spot: Spot) -> some View {
        let unlocked = model.isUnlocked(spot.island)
        let stars = model.stars(on: spot.island)
        return Button {
            guard unlocked else { return }
            model.path.append(.island(spot.island))
        } label: {
            VStack(spacing: -10) {
                ZStack {
                    Ellipse().fill(SI.Palette.ink900.opacity(0.12)).frame(width: 164, height: 24).offset(y: 58)
                    Ellipse().fill(SI.Palette.sand).overlay(Ellipse().stroke(SI.Palette.ink900, lineWidth: 4))
                        .frame(width: 170, height: 62).offset(y: 30)
                    Ellipse().fill(unlocked ? spot.color : SI.Palette.locked).overlay(Ellipse().stroke(SI.Palette.ink900, lineWidth: 4))
                        .frame(width: 140, height: 80)
                    Image(systemName: unlocked ? spot.emblem : "lock.fill")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(unlocked ? .white : SI.Palette.ink900)
                }
                .frame(width: 190, height: 140)
                VStack(spacing: 4) {
                    Text(spot.island.displayName).font(SI.Font.label).lineLimit(1)
                    StarRow(earned: stars, size: 20)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 22).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(SI.Palette.ink900, lineWidth: 3))
                .background(RoundedRectangle(cornerRadius: 22).fill(SI.Palette.ink900).offset(y: 5))
            }
            .opacity(unlocked ? 1 : 0.8)
        }
        .buttonStyle(.plain)
        .frame(width: 190)
        .accessibilityLabel(unlocked ? "\(spot.island.displayName), \(stars) of 3 stars" : "\(spot.island.displayName), locked")
    }

    private var bop: some View {
        let current = spots.last { model.isUnlocked($0.island) } ?? spots[0]
        return HStack(alignment: .bottom, spacing: 6) {
            BopView(mood: .idle, size: 96)
            SpeechBubble(current.island == .harmonyHarbor ? "Let's cook some chords!" : "Tap an island to play!")
                .padding(.bottom, 52)
        }
        .position(x: min(current.x + 210, 1000), y: max(current.y - 30, 110))
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "pawprint.fill") // placeholder until avatar art lands
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(hex: 0xFF9A3C))
                .frame(width: 76, height: 76)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 4))
                .accessibilityLabel("Player: \(model.profile.nickname)")
            Spacer()
            Text("Sound Island")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .padding(.horizontal, 28).padding(.vertical, 8)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
                .background(Capsule().fill(SI.Palette.ink900).offset(y: 6))
            Spacer()
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    NoteShape(.star).fill(SI.Palette.star).overlay(NoteShape(.star).stroke(SI.Palette.ink900, lineWidth: 2.5)).frame(width: 30, height: 30)
                    Text("\(model.totalStars)").font(.system(size: 26, weight: .heavy, design: .rounded))
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 4))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(model.totalStars) stars")
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white.opacity(0.55)))
                    .onLongPressGesture(minimumDuration: 2) { showGate = true } // parental gate step 1: hold 2 s
                    .accessibilityLabel("Grown-ups: press and hold for settings")
            }
        }
        .padding(.horizontal, 32)
        .frame(width: 1194)
        .position(x: 597, y: 62)
    }

    private var dock: some View {
        HStack(spacing: 16) {
            dockButton("Map", icon: "map", active: true) {}
            dockButton("Studio", icon: "music.note", active: false) { model.path.append(.studio) }
            dockButton("Stickers", icon: "star.square", active: false) {}
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 40).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(SI.Palette.ink900, lineWidth: 4))
        .background(RoundedRectangle(cornerRadius: 40).fill(SI.Palette.ink900).offset(y: 8))
        .position(x: 597, y: 834 - 24 - 60)
    }

    private func dockButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon).frame(width: 120)
        }
        .buttonStyle(active ? BigButtonStyle.primary : BigButtonStyle.secondary)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Island screen: three game stations.
struct IslandView: View {
    @Environment(AppModel.self) private var model
    let island: IslandID

    var body: some View {
        DesignCanvas(background: SI.Palette.sky) {
            VStack(spacing: 40) {
                HStack {
                    RoundIconButton(systemName: "chevron.left", label: "Back to map") { model.path.removeLast() }
                    Spacer()
                    Text(island.displayName).font(SI.Font.display)
                    Spacer()
                    Color.clear.frame(width: 76, height: 76)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                HStack(spacing: 32) {
                    ForEach(GameID.games(on: island), id: \.self) { game in
                        Button {
                            model.path.append(.game(game))
                        } label: {
                            VStack(spacing: 16) {
                                BopView(mood: game.isPlayable ? .cheer : .sleep, size: 110)
                                Text(game.displayName).font(SI.Font.headline)
                                if game.isPlayable {
                                    StarRow(earned: model.profile.bestStars[game.rawValue] ?? 0)
                                } else {
                                    Text("Coming soon").font(SI.Font.caption).foregroundStyle(SI.Palette.ink500)
                                }
                            }
                            .frame(width: 300, height: 340)
                            .background(RoundedRectangle(cornerRadius: 40).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                            .background(RoundedRectangle(cornerRadius: 40).fill(SI.Palette.ink900).offset(y: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(!game.isPlayable)
                        .opacity(game.isPlayable ? 1 : 0.6)
                    }
                }
                Spacer()
            }
        }
    }
}

struct ComingSoonView: View {
    @Environment(AppModel.self) private var model
    let title: String

    var body: some View {
        DesignCanvas(background: SI.Palette.sky) {
            VStack(spacing: 24) {
                BopView(mood: .sleep, size: 160)
                Text("\(title) is still being built!").font(SI.Font.title)
                Button("Back") { model.path.removeLast() }.buttonStyle(BigButtonStyle.primary)
            }
        }
    }
}
