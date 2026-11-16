import SwiftUI
import DesignSystem

/// The big dashed "Tap here on the beat!" pad shared by rhythm games (Crab Tap, Wave Rider).
/// Touches are captured with hardware timestamps so games can judge them on the audio clock.
struct TapZone: View {
    var label = "Tap here on the beat!"
    let onTap: (_ hostSeconds: Double) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48)
                .fill(SI.Palette.bopTint)
                .overlay(RoundedRectangle(cornerRadius: 48).strokeBorder(SI.Palette.bop, style: StrokeStyle(lineWidth: 5, dash: [14, 10])))
            VStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").accessibilityHidden(true).font(.system(size: 56)).foregroundStyle(SI.Palette.bop)
                Text(label).font(.system(size: 40, weight: .heavy, design: .rounded))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            TapCaptureView(label: label) { host, _ in onTap(host) }
        }
        .frame(height: 228)
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
}
