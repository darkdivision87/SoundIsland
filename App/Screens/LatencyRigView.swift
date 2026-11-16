import SwiftUI
import Combine
import AudioCore
import GameKitCore

/// Latency rig (spec section 13). Grown-ups only: reached from the parent area, behind the gate.
/// Plays 4 count-in clicks then 16 clicks to tap along with. Taps are timestamped by UIKit and placed on
/// the audio clock exactly like Crab Tap, so the mean offset is the correction Crab Tap needs.
/// Also measures touch-to-render time for the 20 ms tap-to-sound budget.
struct LatencyRigView: View {
    @Environment(AppModel.self) private var model

    private static let bpm = 100.0
    private static let countIn = 4
    private static let measuredClicks = 16

    private enum Phase: Equatable { case idle, running, done }

    @State private var phase = Phase.idle
    @State private var beatTimes: [Int: Double] = [:]
    @State private var lastBeatIndex = -1
    @State private var taps: [Double] = []
    @State private var pending: [(serial: Int, touch: Double)] = []
    @State private var touchToRender: [Double] = []
    @State private var measurement: LatencyMeasurement?
    @State private var offsetWhenMeasured: Double = 0

    private let ticker = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Audio latency check").font(.largeTitle.bold())
                Spacer()
                Button("Done") { model.path.removeLast() }.font(.title3.bold())
            }
            .padding(24)
            HStack(alignment: .top, spacing: 24) {
                results.frame(width: 420)
                tapPad
            }
            .padding([.horizontal, .bottom], 24)
        }
        .background(Color(.systemGroupedBackground))
        .onReceive(ticker) { _ in poll() }
        .onDisappear { if phase == .running { model.audio.send(.stop) } }
    }

    // MARK: Views

    private var tapPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(phase == .running ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            VStack(spacing: 12) {
                Image(systemName: "hand.tap.fill").font(.system(size: 56))
                Text(statusText).font(.title2.bold()).multilineTextAlignment(.center)
            }
            .allowsHitTesting(false)
            if phase == .running { TapCaptureView { host, _ in onTap(host) } }
        }
    }

    private var statusText: String {
        switch phase {
        case .idle: "Use the speaker or headphones you play with.\nPress Start, listen to 4 clicks, then tap here on the next 16."
        case .running: lastBeatIndex < Self.countIn ? "Listen..." : "Tap with the clicks (\(taps.count))"
        case .done: "Finished. See the results."
        }
    }

    private var results: some View {
        Form {
            Section("Run") {
                Button(phase == .done ? "Run again" : "Start", action: start).disabled(phase == .running)
                LabeledContent("Current offset", value: ms(model.audio.calibrationOffset))
                LabeledContent("Reported output latency", value: ms(model.audio.reportedOutputLatency))
            }
            if let m = measurement {
                Section("Tap timing") {
                    LabeledContent("Taps used", value: "\(m.inlierTaps) of \(m.pairedTaps)")
                    LabeledContent("Mean tap offset", value: ms(m.meanOffset))
                    LabeledContent("Median tap offset", value: ms(m.medianOffset))
                    LabeledContent("Spread", value: ms(m.spread))
                    let suggested = LatencyCalibration.suggestedOffset(current: offsetWhenMeasured, measurement: m)
                    Button("Save offset \(ms(suggested))") { model.setCalibrationOffset(suggested) }
                        .disabled(!m.isReliable)
                    if !m.isReliable { Text("Not steady enough to save. Try again with \(LatencyCalibration.minimumTaps)+ steady taps.").foregroundStyle(.secondary) }
                }
            } else if phase == .done {
                Section("Tap timing") { Text("No taps lined up with the clicks.").foregroundStyle(.secondary) }
            }
            if let est = LatencyCalibration.tapToSound(touchToRender: touchToRender, outputLatency: model.audio.reportedOutputLatency) {
                Section("Tap to sound (budget \(ms(LatencyCalibration.tapToSoundBudget)))") {
                    LabeledContent("Estimate", value: ms(est))
                    Text(est < LatencyCalibration.tapToSoundBudget ? "Within budget." : "Over budget.")
                        .foregroundStyle(.secondary)
                    Text("Touch to audio buffer plus reported output latency. Simulator numbers are not representative; measure on a real iPad.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Reset offset to 0", role: .destructive) { model.setCalibrationOffset(0) }
            }
        }
    }

    private func ms(_ seconds: Double) -> String { String(format: "%+.1f ms", seconds * 1000) }

    // MARK: Run

    private func start() {
        beatTimes = [:]
        lastBeatIndex = -1
        taps = []
        pending = []
        touchToRender = []
        measurement = nil
        offsetWhenMeasured = model.audio.calibrationOffset
        phase = .running
        model.audio.send(.setTempo(Self.bpm))
        model.audio.send(.play(metronome: true, playPattern: false))
    }

    private func onTap(_ hostSeconds: Double) {
        guard phase == .running, lastBeatIndex >= Self.countIn - 1 else { return }
        taps.append(model.audio.transportSeconds(forHostSeconds: hostSeconds))
        pending.append((model.audio.lastDrumRender().serial + 1, hostSeconds))
        model.audio.playDrum(.hat, velocity: 0.35)
    }

    private func poll() {
        guard phase == .running else { return }
        let rendered = model.audio.lastDrumRender()
        while let first = pending.first, rendered.serial >= first.serial {
            // Exact for the newest tap; earlier ones in the same buffer share its host time.
            touchToRender.append(rendered.hostSeconds - first.touch)
            pending.removeFirst()
        }
        guard let beat = model.audio.latestBeat(), beat.index != lastBeatIndex else { return }
        lastBeatIndex = beat.index
        beatTimes[beat.index] = beat.seconds
        // Stop half a beat after the last measured click so late taps on it still count.
        if beat.index >= Self.countIn + Self.measuredClicks { finish() }
    }

    private func finish() {
        model.audio.send(.stop)
        let clicks = (Self.countIn..<(Self.countIn + Self.measuredClicks)).compactMap { beatTimes[$0] }
        measurement = LatencyCalibration.measure(taps: taps, clicks: clicks)
        phase = .done
    }
}
