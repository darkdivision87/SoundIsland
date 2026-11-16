import SwiftUI
import DesignSystem

/// "Who's playing?" Kids pick themselves by picture. No typing, no deleting: adding and removing
/// children happens in the parent area behind the gate.
struct ProfilePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DesignCanvas(background: SI.Palette.ocean) {
            VStack(spacing: 48) {
                HStack(alignment: .bottom, spacing: 12) {
                    BopView(mood: .cheer, size: 110)
                    SpeechBubble("Who's playing?").padding(.bottom, 60)
                }
                HStack(spacing: 40) {
                    ForEach(model.profiles) { child in
                        Button { model.switchProfile(to: child.id) } label: { tile(child) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play as \(child.nickname)")
                            .accessibilityAddTraits(child.id == model.activeProfileID ? .isSelected : [])
                    }
                }
            }
            .frame(width: 1194, height: 834)
        }
    }

    private func tile(_ child: ProfileSummary) -> some View {
        let avatar = Avatar.named(child.avatar)
        return VStack(spacing: 16) {
            Image(systemName: avatar.symbol)
                .font(.system(size: 76, weight: .bold))
                .foregroundStyle(avatar.color)
                .frame(width: 180, height: 180)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 5))
                .background(Circle().fill(SI.Palette.ink900).offset(y: 8))
            Text(child.nickname)
                .font(SI.Font.headline)
                .foregroundStyle(SI.Palette.ink900)
                .lineLimit(1)
                .frame(maxWidth: 220)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: 3))
        }
        .contentShape(Rectangle())
    }
}
