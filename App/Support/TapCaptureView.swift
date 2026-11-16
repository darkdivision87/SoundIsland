import SwiftUI
import UIKit
import QuartzCore

/// Captures touches with their hardware timestamps (UITouch.timestamp, same clock as CACurrentMediaTime).
/// SwiftUI gestures don't expose timestamps, and rhythm games must judge against when the finger landed,
/// not when the frame ran. Every touch-down fires immediately; there is no gesture disambiguation delay.
struct TapCaptureView: UIViewRepresentable {
    var label = "Tap zone"
    var onTap: (_ hostSeconds: Double, _ location: CGPoint) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let v = CaptureView()
        v.onTap = onTap
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        v.isAccessibilityElement = true
        v.accessibilityLabel = label
        // Direct interaction passes VoiceOver touches straight through (keeps timing); activation
        // (VoiceOver double tap, Switch Control select) counts as a tap at that moment.
        v.accessibilityTraits = [.allowsDirectInteraction, .button]
        return v
    }

    func updateUIView(_ uiView: CaptureView, context: Context) {
        uiView.onTap = onTap
        uiView.accessibilityLabel = label
    }

    final class CaptureView: UIView {
        var onTap: ((Double, CGPoint) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { onTap?(t.timestamp, t.location(in: self)) }
        }

        override func accessibilityActivate() -> Bool {
            onTap?(CACurrentMediaTime(), CGPoint(x: bounds.midX, y: bounds.midY))
            return true
        }
    }
}
