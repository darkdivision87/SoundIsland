import SwiftUI
import Curriculum
import DesignSystem

/// Parental gate step 2 (step 1 = hold the gear for 2 s): type a number written in words.
/// Required before settings, purchases, links and export (Apple Kids Category, spec section 11).
struct ParentGateView: View {
    @Environment(\.dismiss) private var dismiss
    let onPass: () -> Void

    @State private var challenge = ParentGateView.makeChallenge()
    @State private var answer = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 20) {
            Text("For grown-ups").font(.title.bold())
            Text("Type the number \(challenge.words) using digits.").font(.title3)
            TextField("Number", text: $answer)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .font(.title2)
                .frame(width: 220)
                .onSubmit(check)
            if wrong { Text("That's not it. Try again.").foregroundStyle(.secondary) }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Continue", action: check).buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .interactiveDismissDisabled(false)
    }

    private func check() {
        if Int(answer) == challenge.value {
            dismiss()
            onPass()
        } else {
            wrong = true
            answer = ""
            challenge = Self.makeChallenge()
        }
    }

    static func makeChallenge() -> (value: Int, words: String) {
        let value = Int.random(in: 101...989)
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        return (value, f.string(from: NSNumber(value: value)) ?? "\(value)")
    }
}

/// Plain iPadOS settings UI for parents (deliberately not kid-styled).
struct ParentAreaView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Text("Grown-ups").font(.largeTitle.bold())
                Spacer()
                Button("Done") {
                    model.save()
                    model.path.removeLast()
                }
                .font(.title3.bold())
            }
            .padding(24)
            Form {
                Section("Child profile") {
                    TextField("Nickname (optional)", text: $model.profile.nickname)
                    Picker("Age band", selection: $model.profile.ageBand) {
                        Text("Explorers (6-7)").tag(AgeBand.explorers)
                        Text("Makers (8-10)").tag(AgeBand.makers)
                    }
                }
                Section("Progress") {
                    if let content = model.content {
                        ForEach(content.skills) { skill in
                            let p = model.profile.progress[skill.skillNode]
                            LabeledContent(skill.concept) {
                                Text(p?.isMastered == true ? "Mastered" : (p == nil ? "Not started" : "Practicing, tier \(p!.currentTier)"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Controls") {
                    Toggle("Quiet mode (-10 dB)", isOn: Binding(get: { model.profile.quietMode }, set: { model.setQuietMode($0) }))
                    Toggle("Unlock all islands", isOn: $model.profile.unlockAll)
                    LabeledContent("Microphone", value: "Off (coming in phase 2)")
                }
                Section("Audio") {
                    Button("Check audio latency") { model.path.append(.latencyRig) }
                    LabeledContent("Timing offset", value: String(format: "%+.1f ms", model.audio.calibrationOffset * 1000))
                }
                Section("Privacy") {
                    Text("Sound Island collects no personal data. Songs and progress stay on this iPad.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
