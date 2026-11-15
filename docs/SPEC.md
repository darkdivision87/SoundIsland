# Kids Music Theory iPad App - Dev Spec

Source of truth: the live Claude Doc "Kids Music Theory iPad App - Dev Spec" (https://claude.ai/artifact/BC2NkpqRH4fMhDPMbWxmDe). This file is a markdown export as of 2026-11-15. Hi-fi screens: https://claude.ai/artifact/9B5bRwsrXnRaCeRtCDezYU (HTML copies in `design/screens/`).

## 1. Product overview

**Working name: Sound Island.** An iPad-first app where kids ages 5 to 11 learn real music theory by playing short games, then immediately use what they learned to make their own songs in a kid-sized studio. Every game unlocks a tool in the studio, so theory is never abstract: learn rhythm, get the drum machine; learn chords, get the chord pads.

**Core loop (3 to 8 minutes):** Play a game on an island, earn a new sound or instrument, use it in the Studio, share the song with family.

**Mascot:** Bop, a round, squishy speaker creature whose face is a woofer. Bop sings the target notes, reacts to every tap, and never says "wrong", only "try again!" with a wobble.

### Goals

1. Teach a real, ordered curriculum: pulse, rhythm, pitch, melody, scales, intervals, chords, form, and basic production (loops, layers, mixing, effects).
2. Make every concept playable and audible within 10 seconds of opening a game.
3. Turn learning into creation: by the end of World 6 a child can build a 16-bar song with drums, bass, chords, melody and an effect.
4. Be safe by design: no ads, no open chat, no third-party tracking, COPPA and Apple Kids Category compliant.

### Success metrics (first 90 days post-launch)

| Metric | Target |
| --- | --- |
| Day-7 retention (child profiles) | 35%+ |
| Avg. session length | 8 to 14 min |
| Games completed per session | 3+ |
| Kids who save at least one Studio song in week 1 | 50%+ |
| Concept mastery (pre/post quiz in-game, per world) | +40% correct |
| Parent trial-to-paid conversion | 8 to 12% |
| Crash-free sessions | 99.8%+ |
| Audio latency, tap to sound | under 20 ms |

### Business model

Free download with World 1 and a limited Studio. One-time unlock or family subscription (up to 4 child profiles) behind a parental gate. A school/classroom license is a phase-2 option.

## 2. Audience and learning principles

| Band | Ages | Reading | Interaction profile | Theory ceiling |
| --- | --- | --- | --- | --- |
| Sprouts | 5 to 6 | Pre-reader | Big drag and tap, voice prompts for everything, 3 choices max | Pulse, high/low, loud/soft, simple rhythms, C major pentatonic |
| Explorers | 7 to 8 | Early reader | Short labels, 4 choices, simple sequences | Note names, quarter/eighth notes, major scale, intervals by ear, I-IV-V |
| Makers | 9 to 11 | Reader | Full labels, staff notation toggle, multi-step tasks | Minor keys, triads and inversions, 16-bar form, mixing and effects |

### Learning principles (every game must pass these)

1. **Sound first, symbol second.** Notation fades in only after 3 successful rounds.
2. **Color and shape coding is consistent app-wide** (see section 6).
3. **Errorless learning for Sprouts.** Wrong answers play their own sound, Bop shows the difference, the round continues. No lives, no fail screens.
4. **Spaced repetition.** Skill nodes resurface at 1, 3 and 7 sessions after first mastery.
5. **Mastery gating, not time gating.** A world unlocks at 70% mastery of its prior world's nodes.
6. **Make something every session.** Each game ends with "Add to my song".
7. **Short and finishable.** Rounds are 30 to 90 seconds; a game is 5 to 8 rounds.
8. **Real musical output.** Tempos 70 to 120 BPM; keys C, G, F, A minor, D minor in V1.

## 3. Curriculum map

| # | Island | Theory concepts (skill nodes) | Games | Studio unlock |
| --- | --- | --- | --- | --- |
| 1 | Beat Beach | Steady pulse, tempo, quarter and eighth notes, rests, 4/4 bar, simple patterns | Crab Tap, Wave Rider, Drum Circle | Beat Box (16-step drum machine) |
| 2 | Pitch Peaks | High/low, steps vs. skips, note names C to B, octave, keyboard layout | Bird Song, Pitch Climb, Key Hunt | Keys (2-octave color keyboard) |
| 3 | Melody Jungle | Pentatonic and major scales, contour, call and response, phrase endings on "home" | Echo Monkeys, Vine Swing, Melody Paint | Melody Maker (piano roll lite) |
| 4 | Harmony Harbor | Intervals, major vs. minor mood, triads, I-IV-V-vi, chord roots | Chord Chef, Mood Boats, Stack Attack | Chord Pads (8 diatonic pads per key) |
| 5 | Bass Caves | Root notes, bass following chords, octave jumps, syncopation | Root Rover, Bounce Bass | Bass Buddy (mono bass synth) |
| 6 | Song Volcano | Song form, repetition and contrast, loops, 8 and 16 bar phrases | Song Builder, Build and Drop | Arranger |
| 7 | Mix Lab | Volume, panning, filters, reverb, delay, 3-knob sound design | Mix Detective, Sound Potion | Mixer and FX Rack |

Islands 1 to 4 ship in the MVP. Skill nodes are authored as JSON (see `App/Resources/Content/skills.json`).

## 4. Game specs

### Shared game framework

- **Round structure:** Listen > Try > Feedback (within 100 ms) > Reward (1 to 3 stars) > "Add to my song".
- **Timing judgment:** scored against the audio clock. Windows: Sprouts +/-150 ms, Explorers +/-100 ms, Makers +/-60 ms.
- **Pitch judgment:** tap/drag in V1; mic singing (on-device YIN) in phase 2.
- **Hints:** after 2 misses the target glows; after 3, Bop replays it slower.
- **Difficulty tiers:** Tier 1 to 3 per game, chosen by the adaptive engine (section 10).
- **Pause/exit:** one tap top-left; progress saved per round.

### MVP games (Islands 1 to 4)

| Game | Concept | Mechanic | Tier ladder (1 > 3) | Mastery rule |
| --- | --- | --- | --- | --- |
| Crab Tap | Steady pulse, tempo | Crabs march to a beat; tap on each beat to make them dance | 70 BPM steady > 90 BPM > tempo changes, then stops | 80% on-beat over 16 beats |
| Wave Rider | Quarter, eighth notes, rests | Note "shells" scroll to a hit ring; tap as they arrive | 1 bar quarters > + rests > 2 bars with eighths | 4 of 5 patterns clean |
| Drum Circle | Rhythm patterns | Copy Bop's pattern on 3 giant drum pads, then make your own | 2 beats 1 drum > 4 beats 2 drums > 1 bar 3 drums | 3 copies correct |
| Bird Song | High vs. low | Drag the worm to the higher (or lower) bird | Octave > 5th > 2nd | 8 of 10 |
| Pitch Climb | Steps vs. skips | Predict climber direction and size on a colored ladder | Up/down > step vs. skip > exact rung | 8 of 10 |
| Key Hunt | Note names, keyboard | Bop names a note, child taps that key | C D E > white keys > all 12 | 10 in a row in under 40 s |
| Echo Monkeys | Call and response | Echo a 3 to 6 note phrase on pentatonic pads | 3 notes > 4 notes major > 6 notes with rhythm | 4 of 5 |
| Vine Swing | Scales, home note | Choose the missing scale step to cross | C pentatonic > C major > G and F major | 5 clean |
| Melody Paint | Composing | Paint scale-snapped dots on a grid | 5 notes > 8 notes ending home > 2 phrases | Completion |
| Chord Chef | Triads | Drag root, third, fifth into the pot to cook the ordered chord | Missing note > build from root > major vs. minor | 8 of 10 |
| Mood Boats | Major vs. minor | Sail to Sunny (major) or Moon (minor) island | Triads > progressions > melodies | 8 of 10 |
| Stack Attack | I-IV-V-vi | Place chord blocks to match a heard progression | Match 2 > match 4 > create and save | 3 matches |

### Phase 2 games

Root Rover, Bounce Bass, Song Builder, Build and Drop, Mix Detective, Sound Potion.

## 5. Studio mode

4-track, loop-based kid DAW; everything snaps to key and grid.

- 1 song = up to 4 sections (MVP), each 4 or 8 bars, 70 to 130 BPM.
- Settings: tempo (turtle to rabbit), key mood (Sunny C, Bright G, Warm F, Moonlight A minor, Mystery D minor), swing.
- Tracks: Beats, Bass, Chords, Melody.

| Tool | Unlocked by | What kids do | Constraints |
| --- | --- | --- | --- |
| Beat Box | Beat Beach | 4 x 16 grid (kick, snare, hat, clap); 6 kits | Velocity presets, auto-swing, "Surprise me" |
| Keys | Pitch Peaks | 2-octave keyboard, record | Scale lock on, quantize on record |
| Melody Maker | Melody Jungle | 8 x 16 piano-roll lite | In-key rows only |
| Chord Pads | Harmony Harbor | 8 diatonic pads, strum/arp | Diatonic only, auto voice-leading |
| Bass Buddy | Bass Caves | Auto bass following chords | Root follows chord track |
| Arranger | Song Volcano | Section timeline | Snap at bar lines |
| Mixer and FX | Mix Lab | Faders, pan, 4 FX stickers | Master limiter at -1 dBFS |

Save: auto-save, 50 songs per profile. Concert mode playback. Export (M4A, 15 s video) only via the parent area.

## 6. Hi-fi UI design system

Visual direction: **"toy-box tactile"**. Chunky rounded shapes, thick lips under buttons, saturated warm colors on a cream sky.

### Layout and touch

- Landscape primary. Design at 1194 x 834 pt; scale to 1376 x 1032 (13") and 1133 x 744 (mini).
- 8 pt grid, 32 pt outer margins.
- Touch targets: 88 pt min for Sprouts, 64 pt for Explorers/Makers; 16 pt min gap.
- Top-left = Back/Home. Top-right = parental gate (hold 2 s).

### Color tokens

| Token | Hex | Use |
| --- | --- | --- |
| bg.sky | #FFF6E9 | App background |
| bg.card | #FFFFFF | Cards, panels |
| ink.900 | #2A2550 | Primary text, outlines |
| ink.500 | #6E6A93 | Secondary text |
| brand.bop | #7B5CFF | Bop, primary buttons |
| brand.bopDeep | #5A3FD9 | Button lip, pressed |
| ui.success | #2ECC8F | Correct, progress |
| ui.tryAgain | #FFB23F | Gentle "try again" (never red) |
| ui.star | #FFD447 | Stars |

### Note color and shape system

| Note | Color | Hex | Shape | Solfege |
| --- | --- | --- | --- | --- |
| C | Red | #FF5A5F | Circle | Do |
| D | Orange | #FF9A3C | Triangle | Re |
| E | Yellow | #FFD23F | Square | Mi |
| F | Green | #3DD68C | Diamond | Fa |
| G | Teal | #22C3C9 | Hexagon | Sol |
| A | Blue | #4D8DFF | Star | La |
| B | Purple | #A66BFF | Heart | Ti |

Sharps/flats: lower note's color with stripes. Chords use the root color; major = sun face, minor = moon face.

### Typography

SF Pro Rounded. Display 48/52 Heavy, Title 34/40 Bold, Headline 26/32 Bold, Body 22/28 Semibold, Label 18/22 Bold, Caption 16/20 Semibold. Nothing below 16 pt.

### Components

| Component | Spec |
| --- | --- |
| Big Button | 88 pt tall, radius 32, 6 pt bottom lip; press = lip to 1 pt + 0.94 scale + pitched click |
| Icon Button | 72 pt circle, 36 pt glyph |
| Island Card | Illustrated island, label pill with 3 stars |
| Note Pad | 96 to 120 pt rounded square in note color, shape glyph |
| Chord Block | 140 x 96 pt, root color, sun/moon face |
| Step Cell | 52 pt on 11" (56 on 13"), radius 14, off = tint, on = full color |
| Star Burst | 1 to 3 stars, 120 ms stagger |
| Bop | Rive state machine: idle, listen, sing, cheer, wobble, sleep |

### Motion, sound UI

- Springs (response 0.35, damping 0.6). Visuals locked to the audio clock. Reduce Motion swaps bounces for fades.
- Every tap is a pitched sound in the current key. UI sounds ducked -12 dB under game audio.

### Contrast

ink.900 on bg.sky about 13:1. White on brand.bop 4.4:1: only 22 pt+ bold labels. On ui.success and light note colors, labels use ink.900.

## 7. Screens

Profile picker, World Map*, Island screen, Wave Rider*, Chord Chef*, Reward, Studio*, Concert, Parent area. (* = hi-fi in `design/screens/`.) Every screen within 2 taps of the map; every instruction spoken by Bop; every drag has a tap-to-select, tap-to-place alternative.

## 8. Technical architecture

| Layer | Choice |
| --- | --- |
| Platform | iPadOS 17+ (A13+), landscape-first |
| Language | Swift 6, strict concurrency |
| UI | SwiftUI |
| Games | SpriteKit via SpriteView, or SwiftUI Canvas + TimelineView |
| Character animation | Rive (rive-ios), later |
| Audio | AVAudioEngine + AVAudioSourceNode sequencer |
| Persistence | SwiftData, local-first |
| Sync | CloudKit private DB (parent opt-in) |
| Payments | StoreKit 2 |
| Analytics | On-device only; no third-party SDKs |

Modules: AudioCore, MusicTheory, GameKitCore, Games, Studio, Curriculum, DesignSystem, ParentArea.

### Audio engine

- 48 kHz, 128-frame IO buffer; tap-to-sound under 20 ms.
- Sequencer on the render thread with sample-accurate scheduling; UI sends commands through a lock-free SPSC ring buffer; no locks or allocation on the audio thread.
- Audio clock published to UI as sample time + beat position.
- Touch judging converts touch host time to sample time and compensates outputLatency + ioBufferDuration.
- 32-voice sampler (phase 1: synthesized voices), master limiter at -1 dBFS, parent quiet mode -10 dB.
- Handle interruptions and route changes by pausing transport and saving state.

## 9. Data model

ChildProfile, SkillProgress, GameSession, RoundResult, Unlock, Song, Section, Track, Pattern (96 PPQN), ParentSettings. Content is read-only JSON; user data in SwiftData; nothing leaves the device unless the parent enables CloudKit.

## 10. Progression and adaptive difficulty

- Stars: 1 finish, 2 at 70%, 3 at 90%.
- Rolling accuracy over last 10 rounds: above 85% step up; below 55% for 3 rounds step down + hint.
- One spaced-review round per game. Island unlock at 70% average mastery.
- No streak punishment, loot boxes, wait timers, push to kids, fake scarcity or leaderboards.

## 11. Parent area

Parental gate (hold 2 s + adult task), progress in plain language, song playback/export, time limits, quiet mode, mic/notation toggles, unlock-all, sync toggle. Teacher mode in phase 2.

## 12. Privacy and accessibility

No kid accounts, real names, photos, location, ads or third-party SDKs. Privacy label target "Data Not Collected". Mic audio on-device only. Color + shape for all notes, VoiceOver labels, Switch Control and tap-to-place, Reduce Motion and Calm theme, left-handed Studio layout.

## 13. Performance budgets

Cold launch under 2.5 s (iPad 9th gen), game load under 1 s, tap to sound under 20 ms, zero dropouts in 30 min soak, 60/120 fps, under 600 MB memory, install under 300 MB.

## 14. Roadmap

1. **Prototype (weeks 1 to 6):** AudioCore + MusicTheory, latency rig, Crab Tap + Chord Chef vertical slice, first playtest. Gate: tap-to-sound under 20 ms, 5 of 8 kids start a game unaided.
2. **Alpha (weeks 7 to 18):** Game framework, all 12 MVP games, World Map, Studio 4 tools, SwiftData, design system.
3. **Beta (weeks 19 to 26):** Parent area, StoreKit 2, adaptive difficulty, accessibility, TestFlight.
4. **Launch (week 28).**
5. **Phase 2 (months 8 to 12):** Islands 5 to 7, Arranger, Mixer/FX, mic mode, MIDI export, teacher mode.

Open questions: final name/trademark, pricing model, staff notation in MVP, Android later.
