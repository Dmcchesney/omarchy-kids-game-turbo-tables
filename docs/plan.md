Implementation plan · 2026-09-02 · TypeScript engine, QML screens, four layers, eight milestones, gauntlet-loop kickoff

# Turbo Tables Solo — Implementation Plan

The build plan for the plugin alone, from an empty repository to a verified listing under Kids on plugins.omarchy.org. It implements the settled design v2 and nothing else. Development runs in four layers on a Mac, an Omarchy VM, and one real Omarchy device, with a strict boundary so that most of the work never needs Linux.

**Repository:** `omarchy-kids-game-turbo-tables` · **Plugin id:** `io.github.<owner>.turbo-tables-solo` · **Language:** TypeScript for all game logic, QML for screens, GLSL for the road · **License:** MIT, assets CC0 or original

## Done means

- The plugin installs with `omarchy plugin add … --enable` on a stock Omarchy 4.0.2 and opens from the bar button or a keybinding.
- Practice, Time trial, Ghost, and Grand Prix all work keyboard-only, with three seeded rivals, twelve-lap tables, the twelve-streak hand, all eight cards, the pit crew, the pit lane, records, and the garage.
- Every rule in the design has a test, every seed has a vector, and the compiled bundle reproduces the TypeScript source's vectors byte for byte.
- The marketplace scanner, run locally, reports `passed` with no capabilities.
- Frame rate: 60 fps on a GPU machine at 1080p; 30 fps in the software-rendered VM at the internal resolution.
- Listed under Kids with tags kids, education, games; announced in the hub.

## Four layers

| Layer | What lives here | Runs on | Imports allowed | What it proves |
| --- | --- | --- | --- | --- |
| **1 Engine** | `src/engine/**` (TypeScript): decks, laps, answer loop, streaks, hands, cards, effective progress, rivals, ranking, ghost timeline, save-file schema, seeded RNG | Mac, Node | nothing but the standard library | the rules, deterministically, in milliseconds |
| **2 Screens** | `ui/**` (QML): Garage, Countdown, Race, TrackView, Minimap, Picker, Results, Settings, gauges, `Theme` and `Store` adapters | Mac, Qt 6 `qml` runner with `dev/harness` | `QtQuick*` modules and the engine bundle; never `Quickshell`, never `qs.*` | look, feel, keyboard flow, frame budget |
| **3 Shell** | `TurboTables.qml`, `BarWidget.qml`, `manifest.json`, `shell/**` adapters that bind the real theme singletons, `FileView` persistence, the audio loader | Omarchy VM (UTM aarch64 build) | `Quickshell*`, `qs.Commons`, `qs.Ui` | the plugin contract, focus under Hyprland, hot reload, validation |
| **4 Device** | nothing new; the assembled plugin | one real Omarchy x86 machine | — | GPU frame rate, sound, the final recording, the submission commit |

**The boundary is enforced, not hoped for.** `npm run check:boundary` greps `ui/` and `src/` for `Quickshell`, `qs.`, `Process`, `FileView`, `XMLHttpRequest`, and `Qt.labs` and fails the build on a hit. Only `TurboTables.qml`, `BarWidget.qml`, and `shell/` may touch the shell.

## Repository layout

```
omarchy-kids-game-turbo-tables/
├── manifest.json
├── TurboTables.qml              overlay entry (layer 3)
├── BarWidget.qml                bar launcher (layer 3)
├── qmldir
├── shell/                       ThemeBridge.qml, FileStore.qml, AudioLoader.qml (layer 3)
├── ui/                          screens and views (layer 2)
│   ├── Theme.qml                singleton of colors and sizes; bound by shell/ThemeBridge or dev/harness
│   ├── Store.qml                load/save interface; implemented by shell/FileStore or dev/MemoryStore
│   ├── Garage.qml  Countdown.qml  Race.qml  TrackView.qml  Minimap.qml  Picker.qml  Results.qml  Settings.qml
│   └── parts/                   ChargeBar.qml, LapLamps.qml, KartSprite.qml, Callout.qml, Readout.qml
├── engine/
│   └── engine.mjs               COMMITTED build output of src/engine; the only JS QML imports
├── src/
│   ├── engine/                  TypeScript source (layer 1)
│   │   ├── rng.ts  deck.ts  race.ts  streak.ts  cards.ts  rivals.ts  rank.ts  ghost.ts  save.ts  events.ts  index.ts
│   └── tools/                   vectors.ts (generate), verify-bundle.ts, scan.ts (marketplace baseline runner)
├── vectors/                     decks.json  hands.json  races.json  rivals.json  parity-15.json
├── shaders/                     road.frag (source), road.frag.qsb (baked, committed)
├── assets/                      karts/ props/ cards/ sfx/ (PNG, WAV)
├── dev/                         harness (layer 2 only)
│   ├── Harness.qml              a Window that loads any ui/ screen with mock theme and store
│   ├── imports/qs/Commons/      mock Color.qml, Style.qml + qmldir, values from a real Omarchy theme
│   ├── MemoryStore.qml
│   └── run.sh                   qml -I dev/imports dev/Harness.qml --screen Race --seed 42
├── tests/
│   ├── engine/                  vitest specs per module
│   ├── vectors.spec.ts          replays every vector through src and through engine.mjs
│   ├── qml/                     qmltestrunner specs for ui/ parts
│   └── entrypoint/              copy of Omarchy's manifest-entrypoints fixture (VM)
├── preview.png
├── LICENSE  NOTICE  README.md
└── package.json  tsconfig.json  esbuild.config.mjs  .github/workflows/ci.yml
```

No `scripts/`, `bin/`, `install*`, or `setup*` anywhere. No symlinks. The only non-text files are PNG, WAV, and the baked `.qsb`.

## TypeScript into QML

QML imports ECMAScript modules directly: `import "../engine/engine.mjs" as Engine`. So the engine is written in TypeScript, bundled to one ES module, and that bundle is committed, because a listed plugin must run from the repository as cloned with no build step.

- **Target:** `es2016`, ES module output, no Node built-ins, no dependencies in the bundle. esbuild downlevels optional chaining and nullish coalescing; the engine avoids async, generators, and `BigInt`.
- **Purity:** the engine is a reducer. `step(state, input, now) -> { state, events }`. No timers, no randomness except the seeded generator inside `state`, no I/O. QML owns the clock and calls `step` with elapsed milliseconds; rivals are advanced by the same call.
- **Determinism:** `rng.ts` is a small xoshiro128** seeded from the race seed; every draw goes through it, including rival think times and rival decisions. Same seed, same history, same race, on Node and in QML.
- **Bundle parity:** `tests/vectors.spec.ts` replays every vector through the TypeScript source and, separately, through `engine/engine.mjs` loaded as a module, and requires identical output. CI fails if `engine.mjs` is stale relative to `src/`.
- **Types the UI sees:** `RaceState`, `Racer`, `Lap`, `Hand`, `Card`, `Signal`, `RaceEvent` (a discriminated union: `correct`, `wrong`, `reveal`, `pitCrew`, `lapComplete`, `handDealt`, `cardUsed`, `hit`, `blocked`, `swap`, `passed`, `passedBy`, `finished`, `signal`), and `SaveFile`. Events drive every animation and sound so the UI never re-derives rules.

## Engine specification (layer 1)

| Module | Responsibilities | Key tests |
| --- | --- | --- |
| `rng.ts` | xoshiro128**, `fork(label)` for independent streams per racer | known-answer vectors |
| `deck.ts` | preset → ordered tables → per-lap shuffled facts; pit-lane insertion; extra questions from missed facts first, then the lap's table | every fact correct; each lap holds its table exactly once before extras; `2–5` is 48 questions |
| `race.ts` | racer state (`lapsComplete`, `correctInLap`, `questionsNeededThisLap`, `finished`, `finishTimeMs`), answer handling, reveal-and-advance, pit crew, lap advancement loop, finish | wrong never moves; second wrong reveals and advances; lap rollover resets need to 12; surplus carries |
| `streak.ts` | consecutive-correct counter; threshold 12; pit-crew neither builds nor resets; deal when ≥ threshold and hand empty | the quirk from the bellringer: streak keeps climbing while a hand is held |
| `cards.ts` | eight cards with scope and delta; shared round-robin cursor over the fixed schedule; hand of three; using any card clears the hand; floor 1; Roll Cage stack and single consumption; Oil Slick skips attacker and finished; Tow Hook swaps the position triple; finished racers cannot attack or be attacked; stall durations | one spec per rule, plus `parity-15.json` reproducing the bellringer's expected first three hands |
| `progress.ts` | effective progress = laps × 12 + correctInLap − (need − 12); position order | a Pile-Up moves a racer back 15 on landing and forward as they answer |
| `rivals.ts` | three personalities × three levels; think-time draws; accuracy; rubber band ±15% toward the child's rolling pace, never under 1.5 s; play policy; mercy rules; signal moments | over 10,000 seeded races: no rival ever targets the child with consecutive hands or targets last place; rivals answer their own lap deck |
| `rank.ts` | finished first, then finish time, then effective progress, then correct, then fewer pit-crew answers | deterministic ties |
| `ghost.ts` | answer timeline recording and playback for records; record update rules; per preset | a tie keeps the old record |
| `save.ts` | `SaveFile` schema, versioned; settings, records, facts; migration stub; validation that rejects unknown keys | round-trip; no dates anywhere |
| `events.ts` | event union and the ordering guarantee within one step | every state change emits exactly one event |

Vectors are generated by `src/tools/vectors.ts` from a fixed seed list and committed. A vector is `{ seed, preset, level, inputs[], expected: { events[], finalState } }` where `inputs` are timestamped keystrokes and card choices. The multiplayer engine that comes later must reproduce `decks.json` and `hands.json` exactly.

## Screens and views (layer 2)

Screens are plain Qt Quick. They read `Theme` for colors, fonts, and spacing, `Store` for load and save, and hold a `RaceState` from the engine. Keyboard handling is in one place per screen with `Keys.onPressed` on a focus item, and every screen exposes `focusTarget` so the overlay can hand focus down.

- **Garage:** kart stall (six bodies, eight paints, number 1 to 99), roster with rivals and level badges, settings rows, the signal catalog, `READY UP`, `RACE A FRIEND` disabled with its message.
- **Countdown:** four beats, first fact visible behind `GO`.
- **Race:** HUD (lap and table, place, clock), fact and field, charge bar, hand panel, callouts; hosts `TrackView` and `Minimap`; runs a 100 ms `Timer` for the race clock and rival deadlines and a `FrameAnimation` for the view.
- **TrackView:** `ShaderEffect` road in a `layer` at 480×270 with `layer.smooth: false`; kart, ghost, prop sprites as `Image { smooth: false }` positioned from the projection each frame; `onStatusChanged` fallback to `CanvasRoad.qml`; reduced-motion static plane.
- **Minimap:** `Shape` loop with twelve sector ticks and numbered dots.
- **Picker:** lower-right panel; `1` `2` `3`; target selection with arrows and Enter; Escape backs out.
- **Results:** headline by place, stats, facts to look at, tables lit, `RACE AGAIN`, `GARAGE`.
- **Settings:** sound, reduced motion, scanlines, timer, rival level, resets with one confirmation each.

**Frame budget instrument:** `dev/Harness.qml` shows an fps counter from `FrameAnimation.smoothFrameTime` and a toggle for `QSG_VISUALIZE=overdraw`; the budget is measured before art is finished.

## Shell integration (layer 3)

- `TurboTables.qml`: the overlay contract from the design's approval section verbatim: `shell`, `manifest`, `opened`, `open(payloadJson)`, `close()`, `dismiss()`, a fullscreen `PanelWindow` on the Overlay layer with `keyboardFocus` bound to `opened`, a focus item with `Keys.priority: Keys.BeforeItem` and defensive re-focus, `keepLoaded: true`. It instantiates `ui/Race.qml` and friends and passes `focusTarget` down.
- `BarWidget.qml`: a kart button; click runs the toggle through the shell's IPC.
- `shell/ThemeBridge.qml`: binds `ui/Theme` properties from `Color.menu.*`, `Color.accent`, `Style.font.*`, `Style.space`, `Style.cornerRadius`.
- `shell/FileStore.qml`: `FileView { atomicWrites: true }` at `${XDG_DATA_HOME:-~/.local/share}/turbo-tables-solo/garage.json`, 400 ms debounced save, `loaded` guard so a hot reload cannot overwrite live state with an empty file.
- `shell/AudioLoader.qml`: a `Loader` around a `QtMultimedia` component; on error, a silent stub with the same interface.
- Every `Text` sets `textFormat: Text.PlainText`.

## Toolchain

**Mac (layers 1 and 2):**

```bash
brew install qt node
```

```bash
npm install
```

Dev dependencies only: `typescript`, `esbuild`, `vitest`, `tsx`. Scripts:

| Script | Does |
| --- | --- |
| `npm run build` | esbuild `src/engine/index.ts` → `engine/engine.mjs` (es2016, ESM, minify off so the scanner and reviewers can read it) |
| `npm test` | vitest over `tests/engine` and `tests/vectors.spec.ts` |
| `npm run vectors` | regenerate `vectors/` from the seed list |
| `npm run check:boundary` | the import grep |
| `npm run check:bundle` | rebuild to a temp path and diff against the committed bundle |
| `npm run scan` | runs the marketplace's security-baseline scripts against the repo and prints the outcome |
| `npm run harness -- Race --seed 42` | `qml -I dev/imports dev/Harness.qml` with arguments |
| `npm run shader` | `qsb --qt6 -o shaders/road.frag.qsb shaders/road.frag` |

CI (`ci.yml`) runs build, test, both checks, and scan on every push, and fails if `engine.mjs` is stale.

**VM (layer 3):** the UTM aarch64 Omarchy build. Mount the repo as a UTM shared folder at `~/.config/omarchy/plugins/io.github.<owner>.turbo-tables-solo` inside the VM (a mount, not a symlink). Then:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.<owner>.turbo-tables-solo
```

```bash
qmllint -I /usr/share/omarchy/shell TurboTables.qml BarWidget.qml shell/*.qml
```

```bash
qs log -p /usr/share/omarchy/shell --tail 100
```

Saves hot-reload in the running shell. `omarchy-shell shell toggle <id>` opens it from a terminal.

**Device (layer 4):** a stock Omarchy 4.0.2 x86 machine, the same commands, plus the fps counter at 1080p and a screen recording.

## Milestones

Each milestone ends with its gate met and CI green. Layers are noted so it is clear where you sit that week.

### M0 — Repository, toolchain, boundary, CI (layer 1, two days)

- Create the repo with the layout above, `manifest.json`, `LICENSE`, a README skeleton with the eight required sections, `package.json`, `tsconfig.json`, esbuild config, CI.
- Write `rng.ts` and one trivial engine function; build the bundle; write the first vector; prove `import "../engine/engine.mjs"` works from a throwaway QML file in the `qml` runner.
- Wire `check:boundary`, `check:bundle`, and `scan` (vendor the marketplace's baseline scripts under `tests/` so they are outside the scan scope themselves, or run them from a sibling checkout).
- **Spike, half a day:** confirm the esbuild output loads as an ES module in Qt's QML engine on the Mac and, in the VM, in Quickshell. If `.mjs` fails in Quickshell for any reason, fall back to a classic `.js` with `.pragma library` and record it.

**Gate:** CI green on an empty engine; the scanner reports `passed`; the bundle imports in both QML engines.

### M1 — Engine core (layer 1, one week)

`deck.ts`, `race.ts`, `streak.ts`, `cards.ts`, `progress.ts`, `rank.ts`, `events.ts`; vectors `decks.json`, `hands.json`, `races.json`, `parity-15.json`. Every rule in the design's powerup section has a named test. The parity vector reproduces the bellringer's first three hands from its own test suite: Nitro Oil Slick Wrench, Pothole Roll Cage Pile-Up, Turbo Tow Hook Nitro.

**Gate:** a headless four-racer Grand Prix with scripted inputs replays identically 10,000 times; bundle parity holds.

### M2 — Rivals, ghost, save file (layer 1, one week)

`rivals.ts`, `ghost.ts`, `save.ts`; vectors `rivals.json`. Rival personalities and levels, rubber band, policy, mercy rules, signals; ghost timelines and record rules; the save schema with validation.

**Gate:** over 10,000 seeded Grand Prix races the mercy rules never break, rival finish-time distributions per level match the design's intent (Rookie slower than Pro slower than Champion, with overlap), and a child scripted at 4 s per answer and 90% accuracy finishes second or third at Pro more often than not.

### M3 — Harness and screens (layer 2, two weeks)

`dev/Harness.qml`, mock singletons with a real theme's values, `MemoryStore`; Garage, Countdown, Results, Settings, Picker, gauges; keyboard flow end to end using the engine bundle with a stub track view.

**Gate:** a keyboard-only run through Practice, Time trial, and Grand Prix in the harness with no mouse; every screen readable at 1366×768 and 2560×1440; screen-reader names on garage and settings controls.

### M4 — Track view and minimap (layer 2, two weeks)

`road.frag` and its baked `.qsb`; `TrackView.qml` with sprite projection, ghost, callouts, Turbo lurch, hit pull-back; `CanvasRoad.qml` fallback; reduced-motion plane; `Minimap.qml`; sprite sheets for six karts at eight angles and three scales, placeholder art acceptable.

**Gate:** 60 fps in the harness on the Mac at 1080p with four karts and twelve props; the fallback renders the same scene; reduced motion shows no shake or lurch; the fps counter and overdraw view are in the harness.

### M5 — Shell integration (layer 3, one week)

`TurboTables.qml`, `BarWidget.qml`, `ThemeBridge`, `FileStore`, `AudioLoader`; the entry-point fixture copied from Omarchy's test suite; validation and lint clean; hot reload confirmed.

- **Spike, one day, first thing:** enable the plugin with both kinds and confirm the overlay entry is written to `shell.json`. If only the bar entry appears, switch to the bar-widget-hosts-panel structure and record it.
- Focus: typing digits the moment the overlay opens, Escape closes and returns keys to the desktop, theme change retints the garage live.

**Gate:** `omarchy plugin validate` and `qmllint` clean; the entry-point fixture loads the overlay with mocks; a full Grand Prix played in the VM at 30 fps or better at the internal resolution; the save file survives a hot reload.

### M6 — Device pass, art, sound, accessibility (layers 2 and 4, one week)

Final kart and prop art, card art, the eight card sounds and engine loop, `preview.png`; the device run at 1080p with the fps counter; the keyboard-only recording; scanline and reduced-motion checks; README complete.

**Gate:** 60 fps on the device; sound plays; every README section present; the scanner still reports `passed` after assets landed.

### M7 — Submission and announcement (layer 1, two days)

- Tag `v0.1.0`. Submit the exact commit through the marketplace form: category Kids; tags kids, education, games; the maintainer note from the design.
- Post the hub Ideas discussion and the Spoke row.
- After listing, open the verify form for any later commit rather than pushing to `main` unannounced, so the verified badge holds.

**Gate:** listed under Kids as `Snapshot verified`; hub post up.

## Test matrix

| What | Where | How |
| --- | --- | --- |
| Rules | Mac, Node | vitest per module, vectors, bundle parity |
| Rival fairness | Mac, Node | 10,000-race property tests |
| Screens | Mac, Qt | qmltestrunner on parts; harness walkthrough recorded |
| Frame budget | Mac, VM, device | fps counter in harness; VM at internal resolution; device at 1080p |
| Shell contract | VM | validate, qmllint, entry-point fixture, hot reload, focus |
| Marketplace outcome | Mac | `npm run scan` on every push |
| Accessibility | Mac, device | keyboard-only recording; contrast check on both themes; reduced motion |

## Risks and their spikes

| Risk | When it is retired |
| --- | --- |
| ES-module bundle does not load in Quickshell | M0 spike; fallback is a `.pragma library` classic script |
| Dual-kind plugin only enables the bar entry | M5 spike; fallback is bar-widget-hosts-panel |
| Baked shader differs between Metal on the Mac and OpenGL on Omarchy | M4 bakes with `--qt6` for all targets; M5 checks in the VM; the Canvas fallback covers a failure |
| Qt Multimedia missing on some installs | `AudioLoader` degrades to silence; README lists it as optional |
| Software-rendered VM under 30 fps | internal resolution is a single constant; drop to 400×225 before touching the design |
| Marketplace scan flags something unexpected | `npm run scan` runs on every push from M0 |

## Order of the first week

1. `brew install qt node`, confirm `qsb` and `qml` exist.
2. Create the repo from the layout, commit the manifest and README skeleton.
3. `rng.ts`, first vector, bundle, the M0 spike in the `qml` runner.
4. UTM VM up with the shared folder mounted at the plugin path; run `omarchy plugin validate` on the skeleton; run the M0 spike in Quickshell.
5. Start `deck.ts` with the `2–5` preset and its 48-question vector.

## Running it as a gauntlet loop

The gauntlet-loop skill turns a goal and a bar into a loop: split the work into pieces that can be judged on their own, fan out a builder and a separate harsh critic per piece, have the critic compare ours against the bar blind with labels stripped, and `/loop` until the critic picks ours. No round counts, no scores. This plan is already split into pieces; what it adds here is a named, fetchable, comparable bar for each piece, the critic's rubric, the rules the builder may not break, and the handoff that ends the run.

### Prerequisites before kicking it off

Things only you can do, once, so the loop never stalls on them.

1. Mac toolchain: `brew install qt node`, and confirm `qsb` and `qml` exist under the Homebrew Qt prefix.
2. The Omarchy VM from the UTM build is running, with SSH enabled inside it and the repository mounted as a UTM shared folder at the plugin path. The agent needs to run `omarchy plugin validate`, `qs log`, `omarchy-shell shell toggle`, and `grim` for screenshots over SSH. Record the SSH host and the mount path in `docs/environment.md`.
3. The repository exists on GitHub with the layout from this plan, and these files are committed under `docs/`: `design.md` (design v2, settled), `plan.md` (this document), `garage-room-mock.png` (Sol's Garage Room image), `environment.md`.
4. The gauntlet-loop skill is copied into the repository at `.claude/skills/gauntlet-loop/`.
5. A local checkout of the marketplace repository exists beside this one so `npm run scan` can call its baseline scripts.
6. The bellringer source is reachable at its paths on this Mac, since it is a bar: `/Users/don/Developer/LiveClassBackend/internal/bellringerruntime/` and `/Users/don/Developer/StudentApp3.0-powerups-testing/src/features/bellringer/`.

If the VM is not reachable, the loop must run pieces 1 through 6 and stop at piece 7 with a handoff that says so. It must not fake the VM results.

### Pieces and bars

Every bar is named, fetchable from this Mac, and comparable side by side. The critic gets both sides with labels stripped and answers one question: which is better against the rubric.

| Piece | Builds | Bar | What the critic compares | Milestone |
| --- | --- | --- | --- | --- |
| **1 Rules** | `src/engine` minus rivals; `engine/engine.mjs`; vectors | the bellringer runtime in `LiveClassBackend/internal/bellringerruntime/` and its `service_test.go`; the design's powerup and streak sections | the same scripted race inputs run through ours and through the bellringer's rules, event by event: deltas, floor, lap reset, hand dealing order, shield consumption, swap, finished-racer immunity, effective progress. Then threshold 12 and reveal-and-advance against the design text. Ours must match the bellringer where the design keeps a rule and match the design where it changes one. | M1 |
| **2 Rivals** | `src/engine/rivals.ts` and its vectors | the design's rival table and fairness list; a scripted child at 4 s per answer and 90% accuracy | a 10,000-race statistics report from ours against the numbers the design states: level ordering, rubber-band bounds, mercy rules never broken, the scripted child's finishing distribution at Pro | M2 |
| **3 Garage** | `ui/Garage.qml` and parts, in the harness | `docs/garage-room-mock.png` | a harness screenshot at 1920×1080 against the mock: composition, the kart stall, the roster, the settings rows, the signal tiles, the ready control, the policy rail, type hierarchy, palette, and that nothing text-entry exists | M3 |
| **4 Race view** | `ui/Race.qml`, `TrackView.qml`, `Minimap.qml`, shader, fallback, sprites | the `oppenheimer-rick/omarchy-racer` plugin running in the harness at the same size; the design's race wireframe | side-by-side screenshots and 10-second recordings: reads as looking down the track, the fact is unmistakably primary, minimap legible, callouts and hit pull-back visible, fps counter at or above 60 on the Mac; reduced motion shows no shake | M4 |
| **5 Flow** | Countdown, Picker, Results, Settings; keyboard flow across all screens | the keyboard flow of `com.columbiafoundry.loderunner` and the results copy rules in the design | a keyboard-only recording of Practice, Time trial, Ghost, and Grand Prix with no mouse; picker on keys 1 2 3; every settings reset asks once; results headline by place; facts to look at present | M3 |
| **6 Package** | manifest, README, LICENSE, NOTICE, preview, layout, CI, `npm run scan` | the `com.columbiafoundry.loderunner` repository as listed and verified on plugins.omarchy.org | validate clean, scanner `passed` with no capabilities, README has all eight sections, no forbidden file names, no symlinks, bundle parity check green, boundary check green | M0, M6 |
| **7 Shell** | `TurboTables.qml`, `BarWidget.qml`, `shell/` | the `omarchy.emojis` first-party overlay in the VM | in the VM over SSH: open from the bar button and from the toggle command, digits accepted immediately, Escape closes and the desktop gets keys back, hot reload keeps the save file, theme change retints live, a Grand Prix at or above 30 fps at the internal resolution, screenshots via `grim` | M5 |

Pieces 1, 2, and 6 are judged largely by evidence the builder cannot argue with: parity output, statistics, scanner output. Pieces 3, 4, 5, and 7 are judged on screenshots and recordings, which is where a harsh critic earns its keep.

### Rules the builder may not break

The skill says to specify minimally and let the agent decide architecture. That holds for internals. These are not internals.

- The design is settled. No new mechanics, no changed numbers, no fourth question form, no free text anywhere, no name field, no network code, no dates in the save file.
- The boundary holds: nothing under `ui/` or `src/` imports Quickshell or `qs.*`; only the three shell files may.
- The scanner outcome is `passed` on every commit. No `scripts/`, `bin/`, `install*`, `setup*`, no executables, no `sudo` in prose except negated.
- The committed bundle is rebuilt in the same commit as any engine change.
- Kid testing is not something the agent does. It does not write anything about a real child anywhere.
- The critic is a fresh session with no access to the builder's reasoning, given both sides unlabeled.
- When a piece's critic picks ours, the piece is frozen; later pieces may not regress it, and CI proves it.

### Order and parallelism

Pieces 1 and 6 first, in parallel, because everything else builds on the engine and the package skeleton. Then 2 and 3 in parallel. Then 4 and 5 in parallel. Then 7, which needs the VM. Within a piece, the builder and critic alternate under `/loop` until the critic picks ours; the loop for one piece may run while another piece's builder works.

### Stop condition and handoff

The run ends when every piece's critic has picked ours and CI is green, or when piece 7 is blocked on the VM. Either way the agent writes `HANDOFF.md` at the repository root and stops:

- Which pieces the critic accepted, with the final comparison verdicts quoted.
- How to install in the VM and on a device, and the exact keybinding line.
- What to play, in order: Practice on 2–5, a Time trial, the Ghost, then a Grand Prix at Pro.
- Measured frame rates on the Mac and in the VM.
- What is placeholder: art and sound that need your eye before piece 6 is re-run for M6.
- Anything the critic accepted with a stated reservation.

That file is the definition of "ready for me to test." After your test, your notes become the next goal and the loop runs again from the pieces they touch. Submission to the marketplace (M7) is never done by the loop; it is your commit and your form.

### The kickoff prompt

Paste this into a fresh Claude Code session in the repository, with the skill installed and the prerequisites done.

> Build the Turbo Tables Solo plugin exactly as specified in `docs/design.md` and `docs/plan.md`, using the four-layer structure and TypeScript engine the plan describes. The bar is the set of references in the plan's "Pieces and bars" table: the Zipline bellringer runtime for the rules, `docs/garage-room-mock.png` for the garage, the omarchy-racer plugin for the race view, the Lode Runner plugin for keyboard flow and packaging, and the emojis overlay for shell behavior in the VM described in `docs/environment.md`. Break the work into the seven pieces in that table, in the order the plan gives, and for each piece fan out a builder and a separate critic in a fresh context. The critic compares ours against the bar blind, labels stripped, using that piece's rubric, and is a harsh critic; praise is not useful. Never break the rules under "Rules the builder may not break." `/loop` on each piece until the critic picks ours. When every piece is won and CI is green, or when the VM is unreachable at piece 7, write `HANDOFF.md` as the plan describes and stop.

That is about 190 words, a little over the skill's usual size, because the bars are plural and the stop condition matters.
