Implementation plan · v2 · 2026-09-03 · Golden Hour direction, rally cars, one sprite pipeline, gauntlet restart

# Turbo Tables Solo — Implementation Plan v2

The build plan for the plugin alone, from where the first gauntlet run left it to a verified listing under Kids on plugins.omarchy.org. It supersedes plan v1 (2026-09-02). The engine, rivals, save file, package gates and shell integration from v1 stand; the visual direction, the cars, and the art pipeline do not, and this document replaces them.

**Repository:** `omarchy-kids-game-turbo-tables` · **Plugin id:** `io.github.dmcchesney.turbo-tables-solo` · **Language:** TypeScript for all game logic, QML for screens, GLSL for the road · **License:** MIT, assets original or CC0 · **Branches:** `gauntlet/turbo-tables-build` (the loop's branch, 27 commits past `main`), `proto/golden-hour` (the prototype this plan adopts)

## What changed from plan v1, and why

| Plan v1 | Plan v2 | Reason |
| --- | --- | --- |
| Garage at night, amber work lights, teal shadows; art placeholder until the maintainer's M6 pass | **"Golden Hour at the Pit"**: the palette and light of Omarchy Quattro's own wallpaper — a retrowave sunset — applied to every game screen; art generated in-loop | The v1 build was judged "retro but cheap" by the maintainer. A pixel-art post-process was tried and rejected; relighting the existing low-poly to the wallpaper was prototyped on `proto/golden-hour` and accepted as the direction. It also makes the plugin belong to its shell visually. |
| Six voxel-styled open go-karts | **Six low-poly rally cars**, one model each, closed bodies, livery, lit lamps | The reference is a Group B rally car. A go-kart cannot be made to read like one, and the v1 karts failed silhouette, identity and grounding against it. |
| Kart drawn live by `KartSprite` in the garage and separately by `TrackSprite` on the track | **One car renderer, one model, baked to sprite sheets** at eight angles and three scales, used by garage, countdown and track | v1 shipped two different karts for one child. The design always specified sprite sheets; v1 never built them. |
| Bars: the garage mock, the omarchy-racer plugin | Bars: `docs/golden-hour-reference.png` for every scene, `docs/golden-hour-car.png` for the cars, the racer plugin only for race-view structure | The mock depicts a multiplayer lobby and was the reason `preview.png` had to be deleted; it stays in `docs/` as history, not as a bar. |
| GPU frame rate measured on the Mac | GPU frame rate measured **only on the device**; the Mac is headless, software-rendered | `-platform offscreen` reports `api=1` on this Mac, so every GPU figure taken here was unverifiable, and opening a Qt window steals the maintainer's focus. |
| Pieces 1–7, all open | Pieces 1, 2 and 6 **frozen won**; 7 won and awaiting a VM re-check; 3, 4, 5 re-run under the new direction; a new piece **C, Cars**, runs first | Recorded state of the first run, below. |

## Done means

- The plugin installs with `omarchy plugin add … --enable` on a stock Omarchy 4.0.2 and opens from the bar button or a keybinding.
- Practice, Time trial, Ghost, and Grand Prix all work keyboard-only, with three seeded rivals, twelve-lap tables, the twelve-streak hand, all eight cards, the pit crew, the pit lane, records, and the garage.
- Every rule in the design has a test, every seed has a vector, and the compiled bundle reproduces the TypeScript source's vectors byte for byte, under Node and under Qt's QML engine.
- The six cars are one model each, baked to committed sprite sheets by a reproducible script, and every screen that shows a car shows the same car.
- Every game screen is lit and coloured to `docs/golden-hour-reference.png`, and a blind critic picks ours against it on composition, palette and light.
- The marketplace scanner, run locally against the working tree, reports `passed` with no capabilities, and every repository gate is green.
- Frame rate: 60 fps on a GPU machine at 1080p, measured on the device; 30 fps in the software-rendered VM at the internal resolution.
- Listed under Kids with tags kids, education, games; announced in the hub.

## State at the start of v2

The first gauntlet run (2026-09-02 to 03) is on `gauntlet/turbo-tables-build`. Every critic verdict is quoted in the run's evidence; the short version:

| Piece | Verdict | Where it stands |
| --- | --- | --- |
| 1 Rules | *"Is this engine correct against the design? Yes."* Independent reference reproduces our 347-step transcript byte for byte; one authorised divergence from the bellringer. | **Frozen.** 653 tests, every spec run against source and bundle, vectors replayed under the QML engine. |
| 2 Rivals, ghost, save | Rival numbers exact over 400,000 draws per cell; mercy rules survived an independent attacker; `save.ts` YES after 54 checks and 21 mutations. The save *path* took four rounds — the same bug, "there is no file" inferred from "I could not find out", appeared independently in the engine, the shell and the UI. | **Frozen**, with one open VM check: whether an atomic write over a `chmod 000` file leaves a readable one. The M2 clause "2nd or 3rd at Pro more often than not" measures ~50% and is **recorded, not fixed**, by the maintainer's decision (`docs/open-questions.md`). |
| 3 Garage | Picked over the mock five rounds running, on content and interface; never on the picture. Final craft residue judged art direction, not defect. | **Re-run under v3** with the new bar. Tab did nothing until round 6 — the harness advanced focus by API and only the test pressed the key. |
| 4 Race view | Picked over omarchy-racer, partly on craft; road turns, minimap honest, fallback grid now actually draws. | **Re-run under v3.** |
| 5 Flow | Key count 1 (was 7); all screens reachable; card key rewritten so a deliberate choice costs nothing in 16 shapes; ladder deleted for breaking the Fairness rule. | **Re-run under v3** for the countdown only; the flow itself holds. |
| 6 Package | Picked over the listed, verified Lode Runner plugin five rounds running. `npm run scan` now scans the working tree; the boundary check reads glued strings and verifies binary content; a README gate pairs claims with tokens and states what it cannot check. | **Frozen**; re-run once at M6 for the new images and the wallpaper's attribution. |
| 7 Shell | *"As good as the first-party overlay? YES. Safe on a child's machine? YES."* 0 of 205 keys leaked over 41 cold starts against `omarchy.emojis` leaking 50 of 50. | **Won**; needs the VM back to re-verify the save-path fix. |

The prototype on `proto/golden-hour` (commit `11555f9`) is the starting point for pieces 3, 4 and 5. Its known defects are listed under each piece below. The VM was unreachable at the end of the run (`utmctl start` → `OSStatus -609`); bringing it back is a prerequisite.

## Four layers

Unchanged from v1 in intent: layer 1 engine (`src/engine/**`, Node), layer 2 screens (`ui/**`, the `qml` harness), layer 3 shell (`TurboTables.qml`, `BarWidget.qml`, `shell/**`, the VM), layer 4 the device. The boundary is enforced by `npm run check:boundary`, which now greps every file except a printed allow-list, reads glued strings, and verifies binary content against real signatures rather than extensions.

One addition: **the sprite bake is a layer-2 tool.** `dev/Harness.qml`'s `--kart` mode renders a car alone on transparency; `npm run sprites` drives it to produce the committed sheets. Baked sheets are build output like `engine/engine.mjs` and are rebuilt in the same commit as any model change; `npm run check:sprites` rebuilds to a temp path and diffs.

## Repository layout

```
omarchy-kids-game-turbo-tables/
├── manifest.json  TurboTables.qml  BarWidget.qml  qmldir
├── shell/                       ThemeBridge.qml, FileStore.qml, AudioLoader.qml (layer 3)
├── ui/
│   ├── Theme.qml  Store.qml  Game.qml (the router)
│   ├── Garage.qml  Countdown.qml  Race.qml  TrackView.qml  CanvasRoad.qml  Minimap.qml  Picker.qml  Results.qml  Settings.qml
│   └── parts/
│       ├── CarSprite.qml        ONE car renderer: model table, camera, culling, depth sort, one light, livery, lamps
│       ├── SunsetSky.qml        sky gradient, banded sun, cloud streaks, parallax hills -- used by Garage, Countdown, TrackView
│       ├── GarageStall.qml      the bay, lit from the open door
│       └── ChargeBar.qml  LapLamps.qml  HudReadout.qml  Confirm.qml  StatRow.qml  HandCard.qml  ...
├── engine/engine.mjs            COMMITTED build of src/engine
├── src/engine/                  TypeScript (layer 1) -- frozen
├── src/tools/                   vectors.ts, check-*.ts, scope.ts, scan.ts, verify-bundle.ts, bake-sprites.ts
├── vectors/                     decks, hands, races, rivals, parity-15
├── shaders/                     road.frag + baked road.frag.qsb
├── assets/
│   ├── karts/<body>.png         COMMITTED baked sheets: 8 angles x 3 scales per body, paint via mask channel
│   ├── props/                   roadside sprites (banners, tyre walls, gantry, timing board)
│   └── sfx/                     WAV, M6
├── dev/                         Harness.qml (--screen, --kart, --shot, all headless), MemoryStore.qml, mock qs.Commons
├── tests/                       engine specs (source + bundle), vectors, bundle-qml, qml/, qml-shell/, entrypoint/
├── docs/
│   ├── design.md  plan.md  environment.md  open-questions.md
│   ├── golden-hour-reference.png   THE BAR for every scene: Omarchy Quattro's wallpaper at 1920x1080
│   ├── golden-hour-car.png         THE BAR for the cars: the wallpaper's car, cropped
│   └── garage-room-mock.png        v1's mock; history, not a bar
├── LICENSE  NOTICE  README.md  HANDOFF.md
└── package.json  tsconfig.json  esbuild.config.mjs  .github/workflows/ci.yml
```

`KartSprite.qml`, `TrackSprite.qml` and `CountdownKart.qml` are deleted by piece C. No `scripts/`, `bin/`, `install*`, `setup*`, no symlinks, no executables. Binaries only PNG, WAV and `.qsb`, only under `assets/`, `shaders/`, `docs/`, and the root preview.

## Visual direction v3: Golden Hour at the Pit

The bar is `docs/golden-hour-reference.png` — the wallpaper Omarchy Quattro ships as `themes/tokyo-night/backgrounds/1-quattro.webp`: an 80s rally car mid-jump against a retrowave sunset. The bar is its **palette, light and composition**, not its brushwork. Nothing in this plugin is painted; it is gradients, silhouettes and flat-shaded low-poly geometry rendered at the 480×270 layer, which is where the design already puts it.

**Palette**, sampled from the image, not chosen:

| element | colour |
| --- | --- |
| sky, top → mid → horizon glow | `#5e1a50` → `#a4337b` → `#c24073` → `#d75d6b` |
| sun | `#efcb72` core, `#f0956e` edge, wide `#d75d6b` glow; horizontal cut lines through the lower half |
| hills, far → near | `#bc405f` → `#8e2c50` → `#5e1a50` |
| ground | `#3c1228`; grid lines `#ff4fa3` at ~0.35 alpha fading into the glow |
| shadow | `#5f255e` purple, never grey |
| rim light | `#f0b07a` |
| kept from v1 | amber `#f5a524` for work lights and the charge bar; cream `#f2e6c4` for the fact, plates and road paint; hazard `#d8a12a`; the shell's `accent` for focus |

**The light rule:** one key, the sun, low and behind-right of the subject. Every object has a warm rim on its sun side and a cool purple body; shadows run long toward the camera. The garage's amber work lights are the only other light and are the warm counterpoint to a cool-pink room. **Paint is a flat tone that stays its own hue** — a red car reads red under this sky; the warmth lives in the rim and the lamps, never in the paint. This is the rule the prototype broke.

**Composition:** horizon at 55–60% of frame height; the sun straddles it, off-centre right; the sky is 40% of the frame and is never black; the hero sits low-centre, large, silhouetted against the glow.

Per screen, what the prototype established and what it left:

- **Race view** — `SunsetSky` above a neon grid floor drawn identically by `road.frag` and `CanvasRoad`; rim-lit cars with long shadows; sponsor banners, tyre walls, a timing board and a checkered gantry as props; dust on a surge. Left: road-spanning arches cross the fixed answer field for a moment; `Race.qml`'s 0.55 vignette darkens the sky top to ~`#2a0c24`; the far road has no surface past z ≈ 20.
- **Garage** — the roller door open onto the sunset; magenta bounce on floor and far wall; purple shadows; amber lights kept. Left: paint-hue drift (red → orange; roster thumbnails to tan/olive) — the light rule above is the fix; the left wall and shelves still flat.
- **Countdown** — the car on the start line seen from behind-right, sun behind it, hills, grid, gantry, the number huge in cream over the sky, the first fact readable behind GO. Left: the numeral covers the gantry's board on beats 3–1; the car is a dark lump (piece C fixes that, not piece 5).
- **Results, Settings, Picker, HUD chrome** — unchanged. The chrome stays native and theme-bound; only the game layer takes the light.

### Design amendments this plan requires

`docs/design.md` is the settled specification and the loop's rules forbid a build agent from changing it. The following amendments are therefore applied by the maintainer **before kickoff** (or by the coordinator on the maintainer's explicit instruction), each a replacement of the named passage:

1. **"Visual style", first paragraph** — replace with: *Ground: near-black purple `#3c1228`. Light: one low sun, warm rim `#f0b07a`, with amber `#f5a524` work lights as the local counterpoint in the garage. Shadow: purple `#5f255e`. Sky: the retrowave gradient of Omarchy Quattro's wallpaper, `docs/golden-hour-reference.png`, which is the visual bar for every game screen. Chrome: the theme's `accent` for focus rings and the selected control. Paint stays its own hue under this light.*
2. **"Visual style", the "Karts" paragraph** — replace with: *Cars: six original low-poly rally-car bodies — a boxy coupe, a hot hatch, a wedge, a saloon, a buggy, a pickup — one model each, rendered to sprite sheets at eight angles and three scales. Eight paints as a flat base colour; a cream livery panel with a stripe; the number on a roundel on the door and a plate at the rear; lit headlights and a wide tail-light bar. "Kart" remains the game's word for them in copy.*
3. **"Garage Room", first sentence** — append: *The roller door stands open onto the sunset and the bay is lit from it.*
4. **"The view", the bullet on the fact** — unchanged; **add a bullet**: *Above the horizon is the sky, never black: the sun, its glow, and three silhouette hill layers that parallax with the curve.*
5. **"Decisions, settled"** — add a row: *Visual direction | **Golden Hour at the Pit** (v3, 2026-09-03). The garage-at-night palette of v2 is superseded; its amber and cream survive as accents.*

No mechanic, number, mode, rule or fairness guarantee changes. If the maintainer declines any amendment, the corresponding piece's bar reverts to v1's.

## The cars: piece C

Six low-poly rally cars, one model each, in `ui/parts/CarSprite.qml`, baked to `assets/karts/<body>.png`.

**The bar** is `docs/golden-hour-car.png`, judged on three things, in this order:

1. **Silhouette.** Recognisable as a car — and as *that* car — as a black cut-out at 40 px and at 400 px. Low, wide, flared arches, a roof line, a spoiler that belongs to the body. From behind (the race view), a rear that reads: wide tail-light bar, rear window band, bumper, big rear tyres.
2. **Identity.** A cream livery panel with a stripe; the number on a door roundel and a rear plate; two lit headlights (warm, with a small glow) and a red tail-light bar that is the single most legible cue for a rival ahead; the eight paints as flat base tones that stay their hue.
3. **Grounding and light.** A flat purple contact shadow the shape of the car; a long soft shadow toward the camera; the warm rim on the sun side, caught by **chamfered edges** — flat boxes give a rim nothing to land on, which the prototype proved.

**Model rules:** 40–80 faces per body, authored as a geometry table in model space; chamfers on every silhouette edge; a dark window band; wheels as short cylinders with a two-tone rim, partly inside the arches. Six bodies must differ **below the beltline**, not as six tops on one chassis. Proportions exaggerated toward the toy end — big wheels, short overhangs — as Art of Rally and Horizon Chase Turbo do, which are the two shipped games the maintainer should look at beside the crop (neither is bundled; the crop is the critic's bar).

**Normals:** the v1 sprites' face winding produced inward normals, self-consistent for their cull and wrong-sided for any added light. `CarSprite` uses outward normals and a test that a face's normal points away from the model's centroid.

**One renderer, and it is Blender, offline.** The three v1 sprites — `KartSprite`, `TrackSprite`, `CountdownKart` — are deleted, and no QML draws a car live. The garage turntable, the roster thumbnails, the countdown and the track all draw from committed sheets. The sheets are baked by **Blender running headless from a `bpy` script**, `src/tools/bake-cars.py`, which *is* the model: every body is built from primitives with bevel modifiers, flat-shaded, lit by one warm sun from behind-right and a cool purple fill, and rendered on transparent film with EEVEE. **No `.blend` file exists anywhere** — the scene is generated from the script on every bake, so the model is text, reviewable, and passes the boundary check; a `.blend` is a binary and would fail it.

Why Blender and not the v1 Canvas rasteriser: chamfers that catch a rim, real cast shadows, contact occlusion and a consistent eight-angle turnaround are the four things every v1 critic said the kart lacked, and a renderer gives all four for free where a hand rasteriser made us pay for them line by line — 2,200 lines for one kart that still read as boxes. The first Blender coupe took three passes of a 150-line script (prototype evidence in the run's scratchpad: v1 boxes, v2 grounding and lamps, v3 the cabin as one form). Blender never ships and never runs on a child's machine; runtime is a blit.

**The bake.** `npm run sprites` runs `blender -b --python src/tools/bake-cars.py -- --body <name> --paint <hex> --out assets/karts/` for each body, then `src/tools/pxart.py` (pure Python, no Pillow) applies the pixel grid, the paint-locked palette, ordered dither, despeckle, a one-pixel outline and a flat half-alpha contact shadow. Paint: one sheet per body per paint is acceptable at the sizes involved (budget below), and simpler than a mask channel; revisit if the budget is broken. Sheets are committed. **`npm run check:sprites`** verifies the committed sheets against a recorded SHA-256 manifest written by the bake, so a model change cannot land without its sheets; CI checks the manifest and does not rebake, because Blender lives only on the Mac. **Headless throughout:** `-b` never opens a window; nothing in the bake may.

**Never drive Blender's GUI by computer use.** It is non-reproducible, slow, and opens windows on the maintainer's screen; `bpy` is a Python API and needs no clicking.

**Gate:** an 8-angle turnaround of body 1 beside the crop; the six bodies as one contact sheet, each judged individually; the four cars from behind on the road; the car on the turntable; one car in all eight paints. A blind critic picks ours against the crop on the three criteria above, confirms paint fidelity (each paint measured against its swatch), confirms the same car appears on all three screens, and confirms the bake reproduces.

## Screens and views (layer 2)

As v1, with these changes: `SunsetSky.qml` is a shared part used by `TrackView`, `Garage` (through the door) and `Countdown`; `TrackView` keeps the 480×270 layer on in both shader and canvas modes (measured: 48 fps with it off, 61–63 with it on, software renderer); `CanvasRoad` draws the same picture as `road.frag` and a CPU-rasterised reference of the shader is part of piece 4's evidence; `Countdown` is a scene, not a box; the race HUD band left empty by the ladder's deletion stays empty — a running last-place label breaks the Fairness rule and does not come back.

## Shell integration (layer 3) — done

`TurboTables.qml` hosts `ui/Game.qml`; the surface outlives the summon and the first full-size frame is paid at plugin load, so no keystroke reaches the desktop cold or warm; `FileStore` proves absence with a `<dir>/.` traversability probe and re-reads before every write. `tests/entrypoint/` is Omarchy's real fixture, 51 assertions, proved to be a real gate. Re-verify in the VM once it is back; nothing here changes in v2 unless the VM says so.

## Toolchain

**Mac (layers 1 and 2):** `brew install qt node`. No `npm install` in the checkout, ever. Scripts as v1, plus:

| Script | Does |
| --- | --- |
| `npm run sprites` | bakes `assets/karts/*.png` with Blender headless (`blender -b --python src/tools/bake-cars.py`) and post-processes with `src/tools/pxart.py`; writes `assets/karts/manifest.json` of SHA-256s. Mac only — Blender is `brew install --cask blender` and never ships |
| `npm run check:sprites` | verifies every committed sheet against the manifest; CI runs this and never rebakes |
| `npm run check` | test, types, boundary, bundle, sprites, readme, scan — the whole gate |
| `npm run harness -- --screen Race --shot out.png --exit` | a headless frame at exact size |

**Every Qt process on the Mac is headless.** `QT_QPA_PLATFORM=offscreen` and `QT_QUICK_BACKEND=software` are set for the project in `/Users/don/Developer/.claude/settings.local.json`, and every `qml`/`qmltestrunner` call also passes `-platform offscreen`. No `cocoa` runs, no GPU numbers from the Mac, no `screencapture`, nothing that raises a window. The maintainer works on this machine while the loop runs.

`npm run scan` needs the marketplace checkout beside the repository or `TURBO_TABLES_MARKETPLACE` pointing at it; a worktree elsewhere needs the variable.

**VM (layer 3):** as `docs/environment.md`. Two additions learned the hard way: never run `omarchy plugin remove` — its script `rm -rf`s the target, and the target is the host checkout over 9p; and the reload is `omarchy-restart-shell`, because Omarchy starts the shell with `QS_DISABLE_FILE_WATCHER=1`.

**Device (layer 4):** the only place a GPU frame rate is measured.

## Milestones

M0, M1, M2 and M5 are met. The remaining milestones:

### MC — Cars (layer 2, one week)

Piece C in full: `CarSprite`, six bodies, livery, lamps, outward normals, the bake and its parity check, the three old sprites deleted, every screen on the sheets.

**Gate:** the piece C critic picks ours against the crop; `check:sprites` green; the same car on all three screens.

### M3′ — Garage and countdown under v3 (layer 2, one week)

Pieces 3 and 5 re-run from `proto/golden-hour`: the paint-hue fix, the left wall lit, the numeral clear of the gantry board, the roster on the baked sheets.

**Gate:** critics pick ours against the reference on composition, palette and light — not on content alone; keyboard run intact; contrast floor holds; Tab works.

### M4′ — Race view under v3 (layer 2, one week)

Piece 4 re-run from `proto/golden-hour`: arches clear of the answer field, the vignette off the sky, a surface on the far road, cars from the sheets, props as sprites.

**Gate:** critic picks ours against the reference; 60 fps software at 1080p with four cars and twelve props; fallback matches the shader; reduced motion still.

### M6′ — Package, sound, device (layers 1, 2, 4, one week)

Piece 6 re-run: `NOTICE` attributes the wallpaper (basecamp/omarchy, its licence, the theme path); `README` and the gate's canonical sentences describe `golden-hour-reference.png` and `golden-hour-car.png` identically; a real `preview.png` from the countdown or race frame; the eight card sounds and engine loop behind `AudioLoader`, with the README's audio sentences moved to present tense **in the same commit** as the `SoundEffect` lands, or the gate fails; the device run at 1080p with the fps counter.

**Gate:** scanner `passed`, every gate green, 60 fps on the device.

### M7 — Submission (layer 1, two days)

As v1. Never done by the loop.

## Test matrix

As v1, with: sprite parity (`check:sprites`) on every push; the CPU-rasterised shader reference vs `CanvasRoad` in piece 4's evidence; no GPU frame rate anywhere but the device; `tests/qml` and `tests/qml-shell` as two runners, neither needing a VM.

## Risks and their spikes

| Risk | When it is retired |
| --- | --- |
| The VM stays down (`utmctl start` → `OSStatus -609`) | prerequisite; piece 7's re-verify and the seam's `chmod 000` check wait on it, and the handoff says so if it never returns |
| Warm light pulls paint hue | MC: paint fidelity is a gate criterion, measured per swatch |
| A rim needs chamfers, and 80 faces × 6 bodies × 8 angles is slow to bake | MC: the bake is offline; runtime is a blit |
| Sheets balloon the repository | MC: 8 × 3 per body at 480-layer scale; budget 2 MB total, checked in evidence |
| Arches vs. the fixed answer field | M4′: props that span the road cross under the field's line or the field yields for the frame |
| The wallpaper's licence | M6′: attributed in NOTICE from the omarchy repository's licence file; if it forbids redistribution, the reference stays out of the repository and the bar is fetched into the scratchpad at kickoff |
| A flaky QML test contaminates mutation scores again | every mutation claim carries ≥3 solo re-runs; `tst_race_keys` has a focus guard |

## Running it as a gauntlet loop

Same skill, same shape as v1: pieces judged on their own, a builder and a fresh harsh critic per piece, blind comparison against a fetchable bar, `/loop` until the critic picks ours. What v2 adds is a recorded starting state, a new piece that runs first because every other piece shows its output, and rules learned from the first run.

### Prerequisites

1. **The design amendments above are applied** to `docs/design.md`. Without them every critic judges against the night garage and the loop cannot win.
2. `proto/golden-hour` is merged into `gauntlet/turbo-tables-build` (or the loop starts on it). Its commit `11555f9` carries all three prototype screens with gates green.
3. The Omarchy VM is running and `ssh omarchy-turbo-tables` answers. If it does not, the loop runs C, 3, 4, 5 and 6, and stops at 7 with a handoff that says so.
4. `docs/golden-hour-reference.png` and `docs/golden-hour-car.png` are committed (they are).
5. Headless Qt is enforced (it is, in the project settings) and every agent brief says so.
6. The marketplace checkout is beside the repository, or `TURBO_TABLES_MARKETPLACE` is set.

### Pieces and bars

| Piece | Builds | Bar | What the critic compares | Milestone |
| --- | --- | --- | --- | --- |
| **C Cars** | `ui/parts/CarSprite.qml`, six model tables, `src/tools/bake-sprites.ts`, `assets/karts/*.png`, the three old sprites deleted | `docs/golden-hour-car.png` | an 8-angle turnaround and the six-body sheet beside the crop, blind: silhouette at 40 and 400 px, identity (livery, roundel, lit lamps, tail bar), grounding (shadow, rim on the sun side, chamfers catching it); each paint measured against its swatch; the same car on garage, countdown and track; `check:sprites` green | MC |
| **3 Garage** | `Garage.qml`, `GarageStall.qml`, `Theme.qml`, roster on the sheets | `docs/golden-hour-reference.png` | a 1920×1080 frame beside the reference, blind: composition, palette, light rule, the door, the bay, the car on the turntable; paint fidelity in the roster; the chrome unchanged; keyboard run and Tab intact; contrast floor | M3′ |
| **4 Race view** | `TrackView.qml`, `road.frag`, `CanvasRoad.qml`, `SunsetSky.qml`, props, `Race.qml` HUD colours and vignette | `docs/golden-hour-reference.png`; omarchy-racer for structure only | frames and a 10-second motion sheet beside the reference: sky, sun, hills, grid, rim-lit cars, banners; shader vs canvas identical; 60 fps software at 1080p; arches clear of the answer field; reduced motion still | M4′ |
| **5 Countdown** | `Countdown.qml`, `CountdownScene.qml` on `SunsetSky` and the sheets | `docs/golden-hour-reference.png`; Lode Runner for the flow, which holds | the GO frame beside the reference; numeral clear of the gantry; fact readable behind GO; four beats unchanged; the flow's key count still 1 | M3′ |
| **6 Package** | NOTICE attribution, README image sentences, `preview.png`, sound | the Lode Runner repository as listed | as v1, plus: the two reference images described identically in README and NOTICE; the wallpaper's licence recorded; scanner `passed` with the new PNGs | M6′ |
| **7 Shell** | nothing new; re-verify | `omarchy.emojis` in the VM | as v1: keys cold and warm, the save path's `chmod 000` case, hot reload, theme retint, 30 fps at the internal resolution | — |

Pieces 1 and 2 are frozen and are not re-run; CI proves later pieces do not regress them.

### Rules the builder may not break

All of v1's, unchanged: the design is settled (as amended above, and only as amended), no new mechanics or numbers, no free text, no name field, no network code, no dates in the save file; the boundary holds; never `npm install`; the scanner passes on every commit; the bundle — and now the sprite sheets — are rebuilt in the same commit as their source; no kid testing; the critic is fresh and blind; a won piece is frozen.

Learned in the first run, and now rules:

- **Headless only.** No Qt window on the Mac, ever. No GPU number from the Mac.
- **Never `git checkout --`, `git restore`, `git stash` or `git clean` in the tree.** Several agents write to it at once and it is 9p-shared into the VM; a revert that way destroyed an hour of finished work. Back up by file copy, verify by hash, commit each piece as it is won.
- **Measure the thing being shipped, in the frame being shipped, in one stated colour space.** Three rounds of garage reports quoted a favourable neighbouring number or mixed gamma-encoded and linear luminance; each was caught and each cost more than the defect it hid.
- **A test's name is a claim.** A test that passes under mutation of the rule it names is a defect, and a report's "what is not covered" section must list those.
- **One renderer for the car.** No screen draws its own.
- **The chrome stays native.** Results, Settings, the picker and HUD panels keep the theme's colours and the shell's font; only the game layer takes the light.

### Order and parallelism

**C first, alone**, because the garage, countdown and race all show its output and a critic cannot judge them fairly around a dark lump. Then **3, 4 and 5 in parallel**, each from `proto/golden-hour` with the sheets. Then **6**. Then **7**, which needs the VM.

### Stop condition and handoff

The run ends when every open piece's critic has picked ours and CI is green, or when piece 7 is blocked on the VM. Either way the coordinator writes `HANDOFF.md` at the repository root and stops, as v1: verdicts quoted; install and keybinding; what to play in order (Practice on 2–5, a Time trial, the Ghost, a Grand Prix at Pro); frame rates measured on the Mac (software) and in the VM; what is placeholder; what was accepted with a reservation; and, new in v2, a before/after of each screen beside the reference.

### The kickoff prompt

Paste into a fresh Claude Code session on `gauntlet/turbo-tables-build` after the prerequisites are done.

> Continue the Turbo Tables Solo build under `docs/plan.md` v2 and the design as amended for Visual Direction v3. Pieces 1, 2 and 6 are frozen won; do not re-run them. Start from the prototype on `proto/golden-hour`. The bars are `docs/golden-hour-reference.png` for every game screen and `docs/golden-hour-car.png` for the cars, with omarchy-racer for race-view structure, Lode Runner for flow and packaging, and the emojis overlay in the VM for the shell. Run piece C — one low-poly rally car per body, one renderer, baked sprite sheets, outward normals, paint that keeps its hue — first and alone, then pieces 3, 4 and 5 in parallel from the prototype, then 6, then 7. For each piece fan out a builder and a fresh critic; the critic compares ours against the bar blind, labels stripped, on that piece's rubric, and is harsh — a win on content or interface alone does not count, the picture has to win. Every Qt process is headless; never open a window on this Mac. Never revert with git in this tree. Never break the rules under "Rules the builder may not break." `/loop` on each piece until the critic picks ours. When every open piece is won and CI is green, or when the VM is unreachable at piece 7, write `HANDOFF.md` as the plan describes and stop.
