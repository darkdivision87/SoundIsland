# Sound Island

An iPad app where kids ages 5 to 11 learn real music theory through short games, then use what they learn
in a kid-sized music studio. Every game unlocks a Studio tool: learn rhythm, get the drum machine; learn chords,
get the chord pads.

- Spec: [docs/SPEC.md](docs/SPEC.md) (live doc: https://claude.ai/artifact/BC2NkpqRH4fMhDPMbWxmDe)
- Hi-fi UI: [design/screens](design/screens) (live canvas: https://claude.ai/artifact/9B5bRwsrXnRaCeRtCDezYU)
- Developer guide and task list: [CLAUDE.md](CLAUDE.md)

## Quick start

```bash
brew install xcodegen
cd Packages/SoundIslandKit && swift test && cd ../..
xcodegen generate
open SoundIsland.xcodeproj
```

Stack: Swift 6, SwiftUI, AVAudioEngine, iPadOS 17+. No third-party SDKs except apple/swift-atomics.
