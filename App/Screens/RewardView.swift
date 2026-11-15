import SwiftUI
import Curriculum
import DesignSystem

/// Reward + unlock. Matches design/screens/Reward.dc.html.
struct RewardView: View {
    @Environment(AppModel.self) private var model
    let info: RewardInfo
    @State private var shown = 0

    var body: some View {
        DesignCanvas(background: Color(hex: 0x6A4CF0)) {
            ZStack {
                Circle().fill(.white.opacity(0.16)).frame(width: 840).offset(y: -60).accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(0..<3, id: \.self) { i in
                            NoteShape(.star)
                                .fill(i < info.stars ? SI.Palette.star : .white.opacity(0.35))
                                .overlay(NoteShape(.star).stroke(SI.Palette.ink900, lineWidth: 4))
                                .frame(width: i == 1 ? 132 : 104, height: i == 1 ? 132 : 104)
                                .rotationEffect(.degrees(i == 0 ? -12 : (i == 2 ? 12 : 0)))
                                .scaleEffect(shown > i ? 1 : 0.2)
                                .opacity(shown > i ? 1 : 0)
                        }
                    }
                    .frame(height: 140)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(info.stars) of 3 stars")

                    Text(headline)
                        .font(SI.Font.display).foregroundStyle(.white)
                        .padding(.top, 18)
                    Text(subline)
                        .font(SI.Font.body).foregroundStyle(.white)
                        .padding(.top, 8)

                    if let tool = info.unlockedTool {
                        HStack(spacing: 12) {
                            Text("New!").font(SI.Font.label)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 14).fill(SI.Palette.star))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SI.Palette.ink900, lineWidth: 3))
                            Text("\(tool.displayName) is in your Studio").font(SI.Font.headline)
                        }
                        .padding(26)
                        .frame(width: 620)
                        .background(RoundedRectangle(cornerRadius: 40).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(SI.Palette.ink900, lineWidth: 5))
                        .background(RoundedRectangle(cornerRadius: 40).fill(SI.Palette.ink900).offset(y: 10))
                        .padding(.top, 28)
                    }

                    HStack(spacing: 20) {
                        Button {
                            model.path = [.studio]
                        } label: { Label("Add to my song", systemImage: "music.note") }
                            .buttonStyle(BigButtonStyle.go)
                        Button {
                            model.path.removeLast()
                            model.path.append(.game(info.game))
                        } label: { Label("Play again", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(BigButtonStyle.secondary)
                        Button {
                            model.path = []
                        } label: { Label("Map", systemImage: "map") }
                            .buttonStyle(BigButtonStyle.secondary)
                    }
                    .padding(.top, 30)
                }
                BopView(mood: .cheer, size: 190)
                    .position(x: 165, y: 834 - 155)
            }
        }
        .onAppear {
            // Star burst: 120 ms stagger (spec section 6), each star plays a rising note.
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.12) {
                    withAnimation(SI.spring) { shown = i + 1 }
                    if i < info.stars { model.audio.playNote(72 + [0, 4, 7][i], instrument: .musicBox) }
                }
            }
        }
    }

    private var headline: String {
        switch info.game {
        case .chordChef: "You're a Chord Chef!"
        case .crabTap: "You kept the beat!"
        default: "Amazing!"
        }
    }

    private var subline: String {
        info.stars == 3 ? "Perfect! Every round was spot on." : (info.stars == 2 ? "So good! Play again for 3 stars." : "You finished! Let's practice more.")
    }
}
