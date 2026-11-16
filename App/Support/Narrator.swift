import AVFoundation
import QuartzCore
import SwiftUI
import Curriculum
import GameKitCore
import DesignSystem

/// Bop's voice. AVSpeechSynthesizer is a stand-in until recorded VO lands (CLAUDE.md task 6).
/// Speech runs on the app's audio session so it mixes with the engine and follows quiet mode. On-device only.
@MainActor
final class Narrator {
    private let synth = AVSpeechSynthesizer()
    private var policy = NarrationPolicy()
    var quiet = false

    init() { synth.usesApplicationAudioSession = true }

    func say(_ line: String, replay: Bool = false) {
        guard let text = policy.lineToSpeak(line, at: CACurrentMediaTime(), replay: replay) else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        u.pitchMultiplier = 1.15
        u.volume = quiet ? 0.316 : 1
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

extension View {
    /// Bop says `line` out loud when this view appears and whenever the line changes.
    func narrates(_ line: String?) -> some View { modifier(Narrates(line: line)) }
}

private struct Narrates: ViewModifier {
    @Environment(AppModel.self) private var model
    let line: String?
    func body(content: Content) -> some View {
        content.task(id: line) { if let line { model.narrator.say(line) } }
    }
}

/// "Say it again" button next to every spoken instruction. Sized to the age band's minimum touch target.
struct ReplayButton: View {
    @Environment(AppModel.self) private var model
    let line: String

    var body: some View {
        let size = CGFloat(model.profile.ageBand.minTouchTarget)
        Button { model.narrator.say(line, replay: true) } label: {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(SI.Palette.bop)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: 3))
                .background(Circle().fill(SI.Palette.ink900).offset(y: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hear it again")
    }
}
