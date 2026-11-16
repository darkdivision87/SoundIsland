// Spoken instructions (spec section 7: every instruction spoken by Bop). Pure policy; the app owns the voice.

import Foundation

/// Decides when Bop should speak a line, so screens can just say "this is my instruction now"
/// and not worry about repeats when SwiftUI re-renders or a phase flips back and forth.
public struct NarrationPolicy: Sendable {
    /// The same line is not repeated automatically within this many seconds. Replay taps always speak.
    public var repeatCooldown: Double
    private var lastLine: String?
    private var lastTime = -Double.infinity

    public init(repeatCooldown: Double = 8) { self.repeatCooldown = repeatCooldown }

    /// Call when a line appears (or the replay button is tapped). Returns the text to speak, or nil to stay quiet.
    public mutating func lineToSpeak(_ line: String, at now: Double, replay: Bool = false) -> String? {
        let spoken = Self.spokenText(line)
        guard !spoken.isEmpty else { return nil }
        if !replay, spoken == lastLine, now - lastTime < repeatCooldown { return nil }
        lastLine = spoken
        lastTime = now
        return spoken
    }

    /// On-screen copy tidied for a voice: no trailing ellipses or line breaks, single spaces.
    public static func spokenText(_ line: String) -> String {
        line.replacingOccurrences(of: "...", with: " ")
            .replacingOccurrences(of: "\u{2026}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
