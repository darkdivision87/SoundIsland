import SwiftUI
import AudioCore
import Curriculum
import GameKitCore
import DesignSystem

/// Shared frame for the island games: pause button, title with round dots, and Bop with the spoken
/// instruction and its replay button. The game draws everything else in the 1194 x 834 design space.
struct GameShell<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let rounds: Int
    let done: Int
    let instruction: String
    var background: Color = SI.Palette.sky
    var bopMood: BopMood = .idle
    @ViewBuilder var content: () -> Content

    var body: some View {
        DesignCanvas(background: background) {
            ZStack(alignment: .topLeading) {
                content().frame(width: 1194, height: 834, alignment: .topLeading)
                HStack(alignment: .top) {
                    RoundIconButton(systemName: "pause.fill", label: "Pause") {
                        model.audio.send(.allNotesOff)
                        model.path.removeLast()
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(SI.Palette.ink900)
                        if rounds > 1 { RoundDots(total: rounds, done: done) }
                    }
                    Spacer()
                    Color.clear.frame(width: 76, height: 76)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(width: 1194)
                HStack(alignment: .top, spacing: 14) {
                    BopView(mood: bopMood, size: 96)
                    SpeechBubble(instruction).frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
                    ReplayButton(line: instruction)
                }
                .narrates(instruction)
                .offset(x: 40, y: 118)
            }
            .frame(width: 1194, height: 834)
        }
    }
}

/// How an answer looks right now: plain, glowing (hint after 2 misses), or tried and not it.
enum AnswerState { case normal, hint, tried, right }

/// Big tappable answer card. Never red: a tried answer turns the try-again orange.
struct AnswerCard<Label: View>: View {
    @Environment(AppModel.self) private var model
    let state: AnswerState
    var width: CGFloat = 220
    var height: CGFloat = 120
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        let fill: Color = switch state {
        case .tried: SI.Palette.tryAgain
        case .right: SI.Palette.success
        default: .white
        }
        Button(action: action) {
            label()
                .font(SI.Font.headline)
                .foregroundStyle(SI.Palette.ink900)
                .frame(width: width, height: max(height, CGFloat(model.profile.ageBand.minTouchTarget)))
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(SI.Palette.ink900, lineWidth: 4))
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SI.Palette.ink900).offset(y: 6))
                .overlay(RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .strokeBorder(SI.Palette.star, lineWidth: state == .hint ? 8 : 0).padding(-12))
        }
        .buttonStyle(.plain)
    }
}

/// Plays a sequence of steps (each a chord or single note) with a gap, cancelling any earlier sequence.
@MainActor
final class Sequencer {
    private var task: Task<Void, Never>?
    private let audio: AudioEngine

    init(audio: AudioEngine) { self.audio = audio }

    func play(_ steps: [[Int]], gap: Double, instrument: Instrument = .marimba, velocity: Float = 0.75,
              delay: Double = 0, onStep: (@MainActor (Int) -> Void)? = nil, done: (@MainActor () -> Void)? = nil) {
        task?.cancel()
        task = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            for (i, step) in steps.enumerated() {
                if Task.isCancelled { return }
                onStep?(i)
                for m in step { audio.playNote(m, velocity: velocity, instrument: instrument) }
                try? await Task.sleep(for: .seconds(gap))
            }
            if !Task.isCancelled { onStep?(-1); done?() }
        }
    }

    func cancel() { task?.cancel() }
}

@MainActor
func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        work()
    }
}

extension AppModel {
    /// Current tier spec for a game, or an empty tier 1.
    func tierSpec(for game: GameID) -> TierSpec {
        skill(for: game)?.tier(tier(for: game)) ?? TierSpec(tier: 1, params: [:])
    }

    var minTarget: CGFloat { CGFloat(profile.ageBand.minTouchTarget) }
}
