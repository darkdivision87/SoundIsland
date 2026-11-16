# CLAUDE.md - Sound Island (kids music theory iPad app, ages 6 to 10)

You are continuing a handoff. Read this file, then `docs/SPEC.md`, then look at `design/screens/*.dc.html`
(open them in a browser; they are the hi-fi target). The live spec and design canvas are:
- Spec doc: https://claude.ai/artifact/BC2NkpqRH4fMhDPMbWxmDe
- Hi-fi UI canvas: https://claude.ai/artifact/9B5bRwsrXnRaCeRtCDezYU

## IMPORTANT: this code has never been compiled

The first pass was written in a Linux sandbox with no Swift toolchain or Xcode. Expect a handful of
compile errors (mostly Swift 6 strict-concurrency and SwiftUI type-checking). Your FIRST task is to make
it build and pass tests without changing behavior. Fix forward; don't rewrite modules.

## Build

Requirements: macOS with Xcode 16+, XcodeGen (`brew install xcodegen`).

```bash
# 1. Unit tests for the pure packages (no simulator needed)
cd Packages/SoundIslandKit && swift test

# 2. Generate and open the app project
cd ../.. && xcodegen generate && open SoundIsland.xcodeproj

# 3. Build for an iPad simulator from the CLI
xcodebuild -project SoundIsland.xcodeproj -scheme SoundIsland \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

Set your Apple Developer Team in the target's Signing settings (DEVELOPMENT_TEAM in project.yml is blank).
Latency and timing must be verified on a REAL iPad; the simulator's audio latency is not representative.

## Layout

```
project.yml                       XcodeGen spec (iPad only, iPadOS 17+, landscape, Swift 6)
App/                              SwiftUI app target
  SoundIslandApp.swift            entry, RootView navigation, DesignCanvas (scales 1194x834 design to any iPad)
  AppModel.swift                  @Observable app state, progress, rewards, unlocks, JSON persistence
  Screens/                        WorldMap, Island, Studio (Beat Box), Reward, ParentGate + ParentArea
  Games/                          CrabTapView, ChordChefView (phase-1 vertical slice)
  Support/TapCaptureView.swift    UIKit touch capture with hardware timestamps for rhythm judging
  Resources/Content/skills.json   curriculum skill nodes for islands 1-4 (schemaVersion 1)
Packages/SoundIslandKit/          local Swift package, one library per module from spec section 8
  MusicTheory                     Pitch, PitchClass, Interval, Scale, Key, Triad, Roman numerals
  AudioCore                       AVAudioEngine + AVAudioSourceNode renderer, SPSC command queue, synth voices,
                                  16-step sequencer, metronome, audio clock, latency-compensated tap timing
  GameKitCore                     TimingJudge, BeatSchedule, Stars, RoundFlow (hints), ChordChefRules
  Curriculum                      AgeBand, SkillNode/TierSpec JSON, AdaptiveDifficulty, Mastery, SpacedRepetition, IslandUnlock
  StudioModel                     Song, Section, Track, BeatGrid (bitmask), DrumKit, NoteEvent (96 PPQN)
  DesignSystem                    color tokens, SF Pro Rounded type scale, note color+shape map, BigButtonStyle,
                                  NotePad, StarRow, SpeechBubble, FeedbackChip, BopView (placeholder for Rive)
  Tests/SoundIslandKitTests       unit tests for everything above except AudioCore and DesignSystem
design/screens/                   hi-fi HTML screens from the design canvas (the visual target)
docs/SPEC.md                      dev spec export
```

## Non-negotiable rules

1. **Audio thread is real-time.** In `Renderer.render` and anything it calls: no allocation, no locks,
   no ARC traffic, no Swift arrays that grow, no `print`, no Objective-C messaging. UI talks to audio only
   through `AudioEngine.send(_:)` (SPSC queue of bitwise-copyable `AudioCommand`s) and reads state through atomics.
2. **Timing is judged on the audio clock.** Use `TapCaptureView` timestamps -> `AudioEngine.transportSeconds(forHostSeconds:)`
   and beats from `AudioEngine.latestBeat()`. Never judge against frame time or `Date()`.
3. **Kids' privacy (COPPA / Apple Kids Category).** No third-party SDKs, no analytics that leave the device, no ads,
   no external links or purchases outside the parental gate, no free-text entry for kids, no mic without the parent area.
4. **Design fidelity.** Colors, sizes and layout come from `DesignSystem` tokens and `design/screens/`. Every pitch class
   keeps its fixed color AND shape (`NoteStyle.of`). Touch targets >= 64 pt for Explorers (6-7), >= 52 pt for Makers (8-10).
   Never use red for "wrong"; use `SI.Palette.tryAgain`. Text contrast >= 4.5:1 (white on brand purple only at 22 pt+ bold).
5. **Errorless learning.** No lives, no fail screens. Wrong answers play their sound and the round continues.
6. **Pure logic lives in the package and gets a unit test.** Views stay thin.
7. No em-dashes in user-facing copy (owner preference).

## Audience (changed after the first pass)

Target is ages 6 to 10, App Store Kids band 6-8. Two age bands in `Curriculum.AgeBand`: Explorers (6-7) and
Makers (8-10). The old 5-and-under "Sprouts" band was removed. Explorers get every instruction spoken, 4 choices max,
an 8-step Studio grid (64 pt cells) and +/-120 ms timing windows; Makers get the 16-step grid and +/-80 ms.
Crab Tap starts at 96 BPM (young kids tap most naturally around 120-150 BPM; slow tempos are harder for them).

## Status (phase 1 = spec section 14, weeks 1-6)

Done in this first pass (unverified build):
- [x] All six package modules with tests for MusicTheory, GameKitCore, Curriculum, StudioModel
- [x] Synth-based AudioCore (marimba, music box, soft piano, lead, bass; 6 drum kits; metronome; limiter at -1 dBFS; quiet mode)
- [x] World Map, Island screen, Reward, Parent gate + area, Studio with working Beat Box
- [x] Crab Tap (5 rounds x 16 beats, adaptive tier, tempo-change tier 3)
- [x] Chord Chef (8 orders, tiers 1-3, drag or tap-to-place, glow hint after 2 misses, slow arpeggio after 3)

## Next tasks, in order

1. Make it compile; `swift test` green; app runs in the iPad simulator. Fix Swift 6 concurrency errors properly
   (prefer `@MainActor` on UI types and `Sendable` value types over `@unchecked` / `nonisolated(unsafe)`).
2. Latency rig (spec section 13): a debug screen that plays clicks and records taps, reports mean tap offset, and
   writes `AudioEngine.calibrationOffset`. Target tap-to-sound under 20 ms on iPad 9th gen.
3. Verify `AudioEngine.transportSeconds` latency math on device: confirm whether `mHostTime` in the render callback is
   buffer-start or output time on iPadOS, and adjust the compensation so a perfectly timed tap measures ~0 ms.
4. Move persistence from `profile.json` to SwiftData (spec section 9 entities), keeping `ProfileSnapshot` as the migration source.
   Support up to 4 child profiles + a profile picker screen.
5. Bop as a Rive state machine (idle, listen, sing, cheer, wobble, sleep) replacing `BopView`; crabs and islands as real art.
6. Spoken instructions: every on-screen instruction voiced (record VO later; use AVSpeechSynthesizer as a stand-in), replay icon next to it.
7. Wave Rider (design/screens/WaveRider.dc.html) and Drum Circle to finish Beat Beach.
8. Remaining MVP games in curriculum order: Bird Song, Pitch Climb, Key Hunt, Echo Monkeys, Vine Swing, Melody Paint, Mood Boats, Stack Attack.
9. Studio tools: Keys, Melody Maker, Chord Pads (track rail unlocks), Mixer + FX stickers (pulled forward for 8-10), section copy/arrangement, Concert mode.
10. Accessibility pass: VoiceOver on every control, Switch Control, Reduce Motion, Calm theme, left-handed Studio.
11. Snapshot tests for DesignSystem components; playtest build to TestFlight.

## Conventions

- Swift 6 language mode, strict concurrency complete. SwiftUI + Observation; no Combine except `Timer.publish` for polling.
- One feature per PR, with tests for any new package logic. Commit messages: imperative, short subject.
- Content changes go in `skills.json`; bump `schemaVersion` and update `CurriculumContent.supportedSchemaVersion` if the shape changes.
