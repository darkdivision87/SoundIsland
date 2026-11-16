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
    @State private var showAddChild = false
    @State private var pendingDelete: ProfileSummary?

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
                Section("Children (up to 4)") {
                    ForEach(model.profiles) { child in
                        HStack {
                            Image(systemName: Avatar.named(child.avatar).symbol).foregroundStyle(Avatar.named(child.avatar).color)
                            Text(child.nickname)
                            Spacer()
                            if child.id == model.activeProfileID {
                                Text("Playing now").foregroundStyle(.secondary)
                            } else {
                                Button("Switch") { model.switchProfile(to: child.id) }
                            }
                        }
                        .deleteDisabled(model.profiles.count <= 1)
                    }
                    .onDelete { offsets in pendingDelete = offsets.first.map { model.profiles[$0] } }
                    Button("Add a child") { showAddChild = true }.disabled(!model.canAddProfile)
                }
                Section("Child profile (playing now)") {
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
                    Toggle("Calm colors", isOn: Binding(get: { model.preferences.calmColors },
                                                        set: { v in model.setPreferences { $0.calmColors = v } }))
                    Toggle("Left-handed Studio (tracks on the right)", isOn: Binding(get: { model.preferences.leftHanded },
                                                                                     set: { v in model.setPreferences { $0.leftHanded = v } }))
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
        .sheet(isPresented: $showAddChild) { AddChildView() }
        .alert("Delete \(pendingDelete?.nickname ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete?.id { model.deleteProfile(id: id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Their progress and song are removed from this iPad. This can't be undone.")
        }
    }
}

/// Parent-only: name (optional), picture and age band for a new child.
struct AddChildView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var avatar = Avatar.all[1].id
    @State private var ageBand = AgeBand.explorers

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nickname (optional, no real names needed)", text: $nickname)
                Picker("Picture", selection: $avatar) {
                    ForEach(Avatar.all) { a in Label(a.name.capitalized, systemImage: a.symbol).tag(a.id) }
                }
                Picker("Age band", selection: $ageBand) {
                    Text("Explorers (6-7)").tag(AgeBand.explorers)
                    Text("Makers (8-10)").tag(AgeBand.makers)
                }
            }
            .navigationTitle("Add a child")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.addProfile(nickname: nickname, avatar: avatar, ageBand: ageBand)
                        dismiss()
                    }
                }
            }
        }
    }
}
