# CLAUDE.md - Sound Island (kids music theory iPad app, ages 6 to 10)

You are continuing a handoff. Read this file, then `docs/SPEC.md`, then look at `design/screens/*.dc.html`
(open them in a browser; they are the hi-fi target). The live spec and design canvas are:
- Spec doc: https://claude.ai/artifact/BC2NkpqRH4fMhDPMbWxmDe
- Hi-fi UI canvas: https://claude.ai/artifact/9B5bRwsrXnRaCeRtCDezYU

## Build state (2026-11-15)

The code now compiles cleanly (no warnings) with Xcode 27.2 / Swift 6.4 in Swift 6 mode, `swift test` passes
(44 tests), and the app runs in the iPad Pro 11-inch (M5) simulator. The first pass needed no concurrency fixes.

## Build

Requirements: macOS with Xcode 16+, XcodeGen (`brew install xcodegen`).

```bash
# 1. Unit tests for the pure packages (no simulator needed)
cd Packages/SoundIslandKit && swift test

# 2. Generate and open the app project
cd ../.. && xcodegen generate && open SoundIsland.xcodeproj

# 3. Build for an iPad simulator from the CLI (use `xcrun simctl list devices available` for names)
xcodebuild -project SoundIsland.xcodeproj -scheme SoundIsland \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -derivedDataPath build/DD build
```

Set your Apple Developer Team in the target's Signing settings (DEVELOPMENT_TEAM in project.yml is blank).
Latency and timing must be verified on a REAL iPad; the simulator's audio latency is not representative.

## Layout

```
project.yml                       XcodeGen spec (iPad only, iPadOS 17+, landscape, Swift 6)
App/                              SwiftUI app target
  SoundIslandApp.swift            entry, RootView navigation, DesignCanvas (scales 1194x834 design to any iPad)
  AppModel.swift                  @Observable app state, progress, rewards, unlocks, JSON persistence
  Screens/                        WorldMap, Island, Studio (Beat Box), Reward, ParentGate + ParentArea,
                                  ProfilePicker ("Who's playing?"), LatencyRig (parent area, behind the gate)
  Games/                          CrabTapView, WaveRiderView, ChordChefView
  Support/TapCaptureView.swift    UIKit touch capture with hardware timestamps for rhythm judging
  Support/Narrator.swift          Bop's voice (AVSpeechSynthesizer stand-in), `.narrates(_:)`, ReplayButton
  Support/Avatars.swift           placeholder SF Symbol avatars for child profiles
  Support/TapZone.swift           shared "Tap here on the beat!" pad for rhythm games
  Resources/Content/skills.json   curriculum skill nodes for islands 1-4 (schemaVersion 1)
Packages/SoundIslandKit/          local Swift package, one library per module from spec section 8
  MusicTheory                     Pitch, PitchClass, Interval, Scale, Key, Triad, Roman numerals
  AudioCore                       AVAudioEngine + AVAudioSourceNode renderer, SPSC command queue, synth voices,
                                  16-step sequencer, metronome, audio clock, latency-compensated tap timing
  GameKitCore                     TimingJudge, BeatSchedule, Stars, RoundFlow (hints), ChordChefRules,
                                  LatencyCalibration (rig math), NarrationPolicy (when Bop speaks),
                                  RhythmPattern / PatternResult / WaveRiderAttempts (Wave Rider)
  Curriculum                      AgeBand, SkillNode/TierSpec JSON, AdaptiveDifficulty, Mastery, SpacedRepetition, IslandUnlock
  StudioModel                     Song, Section, Track, BeatGrid (bitmask), DrumKit, NoteEvent (96 PPQN), StudioTool
  ProfileStore                    SwiftData ChildProfile + SkillProgressRecord, ProfileSnapshot (working copy and
                                  phase 1 JSON migration source), 4-child cap, one-time profile.json import
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
- [x] Task 1: builds clean, tests green, runs in the simulator. Checked end to end there: World Map, Crab Tap (beats
      arrive from the audio clock, taps judged "Great!"), Chord Chef (correct and orange "Try again!" paths), Studio,
      parent gate. Layout fixes against design/screens: dock width, Bop bubble placement, Beat Beach emblem
      (no "drum" SF Symbol, uses "cylinder"), crab claw clipping, Explorer Beat Box cell width.
- [x] Task 2: latency rig (Parent area > Check audio latency). Saves `calibrationOffset` per device in UserDefaults.
      Shows tap-to-sound estimate = touch-to-render buffer + reported output latency. Simulator says ~25 ms;
      NOT yet measured on a real iPad.
- [x] Task 4: SwiftData profiles, up to 4 children, kid-facing picker (shown at launch when >1 child, and from the map
      avatar), add/delete in the parent area. Migration from profile.json verified in the simulator.
      Not yet modeled as entities: GameSession, RoundResult, ParentSettings; Song is a JSON blob on ChildProfile.
- [x] Task 6: every instruction voiced (map, picker, Crab Tap, Chord Chef orders, Studio hint, Reward) with a replay
      button at the age band's touch-target size. Recorded VO still to do.
- [x] Task 7 (part): Wave Rider, matching design/screens/WaveRider.dc.html. 5 patterns per session; a pattern that
      isn't clean is retried (glow after 2 misses, 15% slower after 3) and counts as correct only if cleaned before
      the slow replay. Teaches rhythm.quarter_notes, then rhythm.eighth_notes once mastered (`AppModel.skill(for:)`
      now picks the first unmastered node of a game). Verified in the simulator: scrolling, retries, round advance.
      Not verified: hit timing feel on a device, notation glyphs (tier 3), eighth-note tiers on screen.
- [x] Fixed: restarting the transport could let a game read the previous round's last beat and end the new round
      at once (Crab Tap and Wave Rider). `AudioEngine.latestBeat()` now returns nil until the transport is running.

Known issues / open questions:
- Task 3 (mHostTime semantics) and the 20 ms tap-to-sound gate need a real iPad; the simulator can't answer them.
- Task 5 conflicts with rule 3: the Rive runtime is a third-party SDK. Decide whether it is acceptable (no data
  collection, but still third-party code) or animate Bop natively; either way it needs illustrator art.
- Crab Tap speaks "Tap on every beat!" as judging starts, over the clicks. Playtest it; consider speaking during
  the count-in instead.
- Parent-area buttons inherit the app's ink foreground, so they don't look tappable and destructive actions aren't
  tinted. Cosmetic, parent-only.
- Simulator driving tip: zero-length injected taps don't trigger SwiftUI Buttons or TapCaptureView reliably; use
  ~0.15 s taps. Screenshots can lag one frame behind.

## Next tasks, in order

1. DONE. Make it compile; `swift test` green; app runs in the iPad simulator. Fix Swift 6 concurrency errors properly
   (prefer `@MainActor` on UI types and `Sendable` value types over `@unchecked` / `nonisolated(unsafe)`).
2. DONE (device run pending). Latency rig (spec section 13): a debug screen that plays clicks and records taps, reports mean tap offset, and
   writes `AudioEngine.calibrationOffset`. Target tap-to-sound under 20 ms on iPad 9th gen.
3. NEEDS A REAL iPAD. Verify `AudioEngine.transportSeconds` latency math on device: confirm whether `mHostTime` in the render callback is
   buffer-start or output time on iPadOS, and adjust the compensation so a perfectly timed tap measures ~0 ms.
4. DONE. Move persistence from `profile.json` to SwiftData (spec section 9 entities), keeping `ProfileSnapshot` as the migration source.
   Support up to 4 child profiles + a profile picker screen.
5. BLOCKED (third-party SDK rule, needs art; see Known issues). Bop as a Rive state machine (idle, listen, sing, cheer, wobble, sleep) replacing `BopView`; crabs and islands as real art.
6. DONE (recorded VO pending). Spoken instructions: every on-screen instruction voiced (record VO later; use AVSpeechSynthesizer as a stand-in), replay icon next to it.
7. NEXT: Drum Circle (Wave Rider done) to finish Beat Beach.
8. Remaining MVP games in curriculum order: Bird Song, Pitch Climb, Key Hunt, Echo Monkeys, Vine Swing, Melody Paint, Mood Boats, Stack Attack.
9. Studio tools: Keys, Melody Maker, Chord Pads (track rail unlocks), Mixer + FX stickers (pulled forward for 8-10), section copy/arrangement, Concert mode.
10. Accessibility pass: VoiceOver on every control, Switch Control, Reduce Motion, Calm theme, left-handed Studio.
11. Snapshot tests for DesignSystem components; playtest build to TestFlight.

## Conventions

- Swift 6 language mode, strict concurrency complete. SwiftUI + Observation; no Combine except `Timer.publish` for polling.
- One feature per PR, with tests for any new package logic. Commit messages: imperative, short subject.
- Content changes go in `skills.json`; bump `schemaVersion` and update `CurriculumContent.supportedSchemaVersion` if the shape changes.
