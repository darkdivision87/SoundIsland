import SwiftUI
import UIKit

/// Captures touches with their hardware timestamps (UITouch.timestamp, same clock as CACurrentMediaTime).
/// SwiftUI gestures don't expose timestamps, and rhythm games must judge against when the finger landed,
/// not when the frame ran. Every touch-down fires immediately; there is no gesture disambiguation delay.
struct TapCaptureView: UIViewRepresentable {
    var onTap: (_ hostSeconds: Double, _ location: CGPoint) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let v = CaptureView()
        v.onTap = onTap
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        v.isAccessibilityElement = true
        v.accessibilityLabel = "Tap zone"
        v.accessibilityTraits = .allowsDirectInteraction
        return v
    }

    func updateUIView(_ uiView: CaptureView, context: Context) {
        uiView.onTap = onTap
    }

    final class CaptureView: UIView {
        var onTap: ((Double, CGPoint) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { onTap?(t.timestamp, t.location(in: self)) }
        }
    }
}
