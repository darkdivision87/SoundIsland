// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundIslandKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MusicTheory", targets: ["MusicTheory"]),
        .library(name: "AudioCore", targets: ["AudioCore"]),
        .library(name: "GameKitCore", targets: ["GameKitCore"]),
        .library(name: "Curriculum", targets: ["Curriculum"]),
        .library(name: "StudioModel", targets: ["StudioModel"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "ProfileStore", targets: ["ProfileStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        // Pure Swift, no UI or audio dependencies. Must stay 100% unit tested.
        .target(name: "MusicTheory"),
        // Real-time audio. Nothing on the render thread may allocate, lock or touch ARC objects.
        .target(
            name: "AudioCore",
            dependencies: ["MusicTheory", .product(name: "Atomics", package: "swift-atomics")]
        ),
        // Round state machine, timing and pitch judging, stars.
        .target(name: "GameKitCore", dependencies: ["MusicTheory", "Curriculum"]),
        // Skill graph, adaptive tiers, spaced repetition.
        .target(name: "Curriculum"),
        // Song / section / track / pattern model shared by Studio and games.
        .target(name: "StudioModel", dependencies: ["MusicTheory"]),
        // Child profiles in SwiftData (spec section 9). On-device only; no CloudKit unless a parent opts in later.
        .target(name: "ProfileStore", dependencies: ["Curriculum", "StudioModel"]),
        // Tokens, note color + shape map, components, Bop.
        .target(name: "DesignSystem", dependencies: ["MusicTheory"]),
        .testTarget(
            name: "SoundIslandKitTests",
            dependencies: ["MusicTheory", "GameKitCore", "Curriculum", "StudioModel", "ProfileStore", "DesignSystem"],
            resources: [.copy("__Snapshots__")]
        ),
    ]
)
