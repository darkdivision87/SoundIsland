import SwiftUI
import DesignSystem

@main
struct SoundIslandApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            WorldMapView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .font(SI.Font.body)
        .foregroundStyle(SI.Palette.ink900)
        .fullScreenCover(isPresented: $model.showProfilePicker) {
            ProfilePickerView()
                .font(SI.Font.body)
                .foregroundStyle(SI.Palette.ink900)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .island(let island): IslandView(island: island)
        case .game(.crabTap): CrabTapView()
        case .game(.waveRider): WaveRiderView()
        case .game(.drumCircle): DrumCircleView()
        case .game(.chordChef): ChordChefView()
        case .game(.birdSong): BirdSongView()
        case .game(.pitchClimb): PitchClimbView()
        case .game(.keyHunt): KeyHuntView()
        case .game(.echoMonkeys): EchoMonkeysView()
        case .game(.vineSwing): VineSwingView()
        case .game(.melodyPaint): MelodyPaintView()
        case .game(.moodBoats): MoodBoatsView()
        case .game(.stackAttack): StackAttackView()
        case .studio: StudioView()
        case .reward(let info): RewardView(info: info)
        case .parentArea: ParentAreaView()
        case .latencyRig: LatencyRigView()
        }
    }
}

/// Scales a fixed 1194 x 834 pt design (iPad 11") to the current screen, letterboxed, so the
/// hi-fi layouts hold on 13" and mini (spec section 6).
struct DesignCanvas<Content: View>: View {
    static var designSize: CGSize { CGSize(width: 1194, height: 834) }
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.designSize.width, geo.size.height / Self.designSize.height)
            ZStack {
                background.ignoresSafeArea()
                content()
                    .frame(width: Self.designSize.width, height: Self.designSize.height)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }
}
