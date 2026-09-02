Design v2 · decisions settled 2026-09-02 · bellringer mechanics rebranded · AI rivals · behind-the-kart view · plugin shape last

# Turbo Tables Solo — Design v2

A times-table kart race for children roughly 7 to 11, shipped as an Omarchy shell plugin. You race three AI karts down a night-lit garage circuit by answering multiplication facts. Twelve laps, one per table, from the ones to the twelves. Streaks charge powerups; powerups skip your own questions or pile questions onto a rival; rivals do the same to you and to each other. It should feel like a kart racer, and it should leave the child knowing the tables.

This is the second draft. It replaces the sprint-only first draft with the competitive mechanics of the Zipline bellringer race, rebranded, plus AI racers, a pseudo-3D behind-the-kart view, and a minimap. The last section is unchanged in intent: the shape the plugin must take to be listed under Kids on plugins.omarchy.org.

**Status:** decisions settled 2026-09-02, ready for the implementation plan · **Tier:** 1 (solo, no network, no peer) · **Plugin id:** `io.github.<owner>.turbo-tables-solo` · **Mechanics source:** the Zipline bellringer runtime, read from its Go ruleset and React client on 2026-09-02

## What changed from draft one, and why

| Draft one | Draft two | Reason |
| --- | --- | --- |
| Sprint to 20 correct, 150 s cap | 12 laps × 12 questions, no time cap; presets shorten it to fewer laps | The goal is to finish 1×1 through 12×12. A lap per table gives the race its structure. |
| Combo gauge, one small boost | Streak charge, choose one of three powerups | Streaks are the engine of the game now, as in the bellringer. |
| Solo against the clock | Three AI rivals who attack you and each other, plus ghost and practice | It has to feel like a kart race. |
| Turbo and Traction | Eight powerups with the bellringer's exact effects, garage names | Same system, new brand. |
| Side-view checkpoint rail | Behind-the-kart pseudo-3D track and a minimap | Looking down the track, positions visible at a glance. |
| Per-question 8 s timeout | No timers on questions; a pit crew hint that always works | The bellringer has no timers, and a 144-question race with timeouts would punish. |

Two of these are deliberate departures from the Kids Mode hub's pedagogy notes, which say "no streaks" and warn against mechanics that pile problems onto another child. The streak here lives inside one race and is never stored, shown across sessions, or tied to days, so it is a game mechanic rather than an attendance hook. Attacks are bounded by the lap, land on AI karts in this game, and come with the bellringer's guardrails, listed under Fairness. Whether children may attack each other in the multiplayer game is a separate decision for Kids Play, not this plugin.

## Pillars

1. **The question is the track.** The fact is the largest thing on screen at every moment of a race.
2. **Mistakes cost the streak, never the position.** A wrong answer never adds questions, never moves you backwards, never reveals a red X. Only rivals can shove you, and only for a lap.
3. **Twelve laps, twelve tables.** Lap seven is the sevens. Finishing the race means you have driven the whole table.
4. **Streaks charge, powerups spend.** A clean run of answers and you choose. Choosing one discards the other two. Nothing carries across races.
5. **A garage at night, seen from the driver's seat.** Amber work lights, teal shadows, a diagnostic grid, a track that bends away into the dark.

## Who it is for

| Band (hub) | Fit | What changes |
| --- | --- | --- |
| 5–7 | partial | Practice mode and the 2–5 preset (four laps), Rookie rivals |
| 8–10 | core | 2–10 preset (nine laps), Pro rivals, all modes |
| 11–12 | stretch | Full Grand Prix 1–12, Champion rivals |

The plugin does not know the child's age. Preset and rival level encode the bands.

## Modes

| Mode | Rivals | Powerups | Timer | Records |
| --- | --- | --- | --- | --- |
| **Practice** | none | off | none | none. The garage with the engine idling; questions one at a time; mistakes show the answer immediately. |
| **Time trial** | none | off | yes | sets the personal best per preset; produces the ghost |
| **Ghost** | your previous best | off | yes | beat the ghost and the record updates |
| **Grand Prix** | three AI karts | on | yes | places and times are shown, never stored as records |

Records are clean by construction: only powerup-free runs count, so a personal best means the tables got faster, not that a Turbo landed. Grand Prix is where the kart-race feeling lives, and its trophy is the finishing place on the results screen.

## Laps, decks, presets

A race is a sequence of laps. Each lap is one table. Within a lap the twelve facts of that table (`n × 1` through `n × 12`) are shuffled by the seed. The finish line is the last correct answer of the last lap.

| Preset | Laps (tables) | Questions | Typical Grand Prix length |
| --- | --- | --- | --- |
| `2–5` | 2, 3, 4, 5 | 48 | 3 to 5 minutes |
| `2–10` | 2 through 10 | 108 | 7 to 10 minutes |
| `1–12` Grand Prix | 1 through 12 | 144 | 9 to 13 minutes |
| `Choose tables` | any subset, in ascending order | 12 per table | varies |

**Extra questions from attacks** are drawn first from facts the child has missed in this race, then from the current lap's table, shuffled by the seed. An attack is a reason to see the missed fact again, not a random tax.

**Fact history** is kept locally per fact: attempts, correct, last three outcomes. It drives the mastery lamps in the garage and the order of pit-lane re-asks. It does not change which laps a race contains: the race is the table.

Deck generation is deterministic from the seed and the fact history. Seeds and resulting question sequences are committed as test vectors, and the multiplayer engine must reproduce them byte for byte.

## The answer loop

1. The fact appears large and centered: `7 × 8`. The numeric field already has focus. The kart is rolling.
2. The child types digits. Submit on Enter or automatically when the digit count matches the answer. Backspace edits. Other keys do nothing. Leading zeros and stray characters are simply not accepted into the field, so "07" cannot happen.
3. **Correct:** the kart surges, the lap lamp for that question lights, the streak charge ticks up, the next fact appears within 250 ms.
4. **Wrong:** 500 ms sputter. The streak resets to zero. The same fact stays and the field clears. No message, no reveal.
5. **Second wrong on the same fact:** the correct answer is shown for 1500 ms in teal, `7 × 8 = 56`, the fact is queued for the pit lane, and the race moves on. Progress advances as if answered, because the child now knows the answer and a race that stalls on one fact stops being a race. The streak is already zero.
6. **Pit crew** (the bellringer's hint): press `H` at any time and the answer is shown, the question counts for progress, and the streak neither grows nor resets. It is always available. The results screen counts pit-crew answers separately so the child and the parent can see them.
7. **Pit lane:** a fact missed twice returns once, three questions later in the same lap, or at the start of the next lap if the lap is nearly over.
8. **Stalled:** when a Wrench or Pothole or Pile-Up lands on you and is not blocked, the field is locked for two seconds (three for a Wrench) with the engine-hit banner. Oil Slick, Tow Hook, your own boosts, and blocked hits never stall you.

There are no per-question timers. The race clock runs, and that is the only clock.

## Streaks and the powerup hand

- **Streak** counts consecutive correct answers within the race. A wrong answer resets it to zero. Pit-crew answers do not reset it and do not count toward it. Nothing else touches it: not laps, not being hit, not holding a hand.
- **At 12 in a row**, one clean lap's worth, the child is dealt a hand of three powerups and the streak resets to zero. If a hand is already held, the streak keeps climbing and the next correct answer after the hand is spent deals a new one.
- **The hand is dealt round-robin** from a fixed schedule shared by every racer in the race, human and AI alike, exactly as the bellringer does it: Nitro, Oil Slick, Wrench, Pothole, Roll Cage, Pile-Up, Turbo, Tow Hook, then around again. The first hand of a race is always Nitro, Oil Slick, Wrench. Because the cursor is shared, the rarest cards reach whoever earns the fourth and fifth hands of the race. Deterministic, seed-free, testable.
- **Using a powerup costs the whole hand.** Pick one and the other two are gone. No cooldown. You may hold a hand as long as you like, including across laps.
- **Keys:** `1`, `2`, `3` choose a card; for a targeted card, left and right pick a rival, Enter confirms, Escape backs out. The picker is a small panel in the lower right, not a modal over the question, so the race stays visible.

The charge bar has twelve segments, glows from nine, and reads `POWER-UP READY` at twelve. The threshold is a single constant; the test vectors also carry the bellringer's 15 as a parity case so the engine can be checked against the original.

## Powerups

Same eight effects, same numbers, same targeting rules as the bellringer; only the names and art belong to the garage.

| Card | Bellringer name | Effect | Target | Tier |
| --- | --- | --- | --- | --- |
| **Nitro** | Fuel Boost | skip 4 questions this lap | you | common |
| **Oil Slick** | Gravity Well | add 3 questions this lap | every other racer | common |
| **Wrench** | Lightning | add 5 questions this lap | one racer | uncommon |
| **Roll Cage** | Shield | block the next attack | you | uncommon |
| **Pothole** | Black Hole | add 8 questions this lap | one racer | rare |
| **Turbo** | Turbo | skip 10 questions this lap | you | rare |
| **Pile-Up** | Supernova | add 15 questions this lap | one racer | legendary |
| **Tow Hook** | Wormhole | swap positions with one racer | one racer | legendary |

The rules underneath, verbatim from the runtime, because they are the game:

- **Attacks and boosts change only the current lap's requirement.** Each racer needs twelve correct answers per lap; a Pothole makes it twenty, a Nitro makes it eight. The floor is one; there is no ceiling. When the lap ends, the requirement resets to twelve, so every effect dies at the lap boundary. A Pile-Up is bounded by one lap.
- **Boosts can complete laps instantly.** A Turbo at the start of a lap takes ten off twelve; two more answers finish the lap, and any surplus carries into the next.
- **Tow Hook swaps position outright**: laps complete, correct in lap, and questions needed, both ways. Roll Cages stay with their owners. A Tow Hook can never finish a race for anyone.
- **Roll Cages stack** without limit and each absorbs exactly one incoming attack. A blocked attack does nothing and costs the attacker their hand anyway.
- **Oil Slick hits every racer except the attacker**, checking and consuming each victim's Roll Cage separately.
- **A finished racer cannot attack and cannot be attacked**, by anything, including Oil Slick.
- **Position is effective progress**: laps complete × 12, plus correct this lap, minus however many questions this lap's requirement exceeds twelve. That last term is why a Pile-Up visibly shoves a kart backwards on the track the instant it lands, and why the kart creeps forward again as the victim answers.

## AI rivals

The bellringer never had opponents that were not people, so the rivals are new. They are three karts with names, colors, and a simple, seeded model of a child at the keyboard.

| Rival | Personality | Accuracy | Think time (mean ± spread) |
| --- | --- | --- | --- |
| **Bolt** | fast, sloppy | 84% | 2.8 s ± 0.9 |
| **Piston** | steady | 91% | 3.4 s ± 0.7 |
| **Gasket** | careful, slow | 96% | 4.6 s ± 1.0 |

Those are the Pro numbers. **Rookie** multiplies think time by 1.5 and subtracts 8 points of accuracy; **Champion** multiplies by 0.75 and adds 3. The level is chosen in the garage and is the difficulty setting.

- **Rivals answer their own copy of the same lap deck** from the same seed, so their progress is honest: a rival on lap seven is answering sevens.
- **Rubber band, gently.** Each rival's think time scales by up to ±15% toward the child's rolling pace over the last twelve answers, so a race stays a race across ability levels without ever letting a rival answer faster than 1.5 s.
- **Rivals build streaks and earn hands** under the same rules and from the same shared card cursor, so a rival's fourth hand can hold a Pile-Up just as the child's can.
- **Rival play policy**, evaluated when a hand is dealt and re-evaluated every three answers while it is held:
  - Holding a boost while behind the leader by more than half a lap: use it.
  - Holding a Roll Cage with none active while in first or second: use it.
  - Holding an attack: target the current leader if it is not itself; otherwise the closest kart behind. Rivals attack each other as readily as the child.
  - Never attack the child twice with consecutive hands, and never attack a racer who is in last place. That is the one place the rivals are kinder than a real opponent.
- **Rivals send preset signals** occasionally: a `NICE RUN` when the child completes a lap with no mistakes, a `GOOD GAME` at the finish. From the same four-signal catalog as the multiplayer lobby, so the child sees the same vocabulary everywhere.

Everything the rivals do is derived from the race seed, so a Grand Prix is replayable and every rival decision is a test vector.

## Race format and results

- **Start:** the garage, then a countdown on the terminal readout, `3` `2` `1` `GO`, with the first fact readable behind `GO`.
- **Finish:** the child's last correct answer of the last lap. Rivals keep racing for up to fifteen seconds so the final order settles; then the race ends. In Time trial and Ghost the race ends at the finish line.
- **Ranking:** finished before unfinished; among finished, finish time; among unfinished, effective progress; then correct-answer count; then fewer pit-crew answers.
- **Results:**

```
┌──────────────────────────────────────────────────────────────┐
│  PODIUM FINISH                                  2nd of 4      │
│                                                              │
│  TIME          8:41            LAPS   12 / 12                 │
│  CORRECT       144             PIT CREW   3                   │
│  ACCURACY      91%             BEST STREAK   27               │
│  POWER-UPS     Nitro · Wrench ▸ Bolt · Roll Cage               │
│                                                              │
│  FACTS TO LOOK AT    7 × 8 = 56    6 × 9 = 54    12 × 7 = 84   │
│  TABLES LIT          ▮▮▮▮▮▮▮▮▮▯▯▯   9 of 12                    │
│                                                              │
│  [ RACE AGAIN ⏎ ]   [ GARAGE  Esc ]                            │
└──────────────────────────────────────────────────────────────┘
```

Headlines follow the bellringer's rule that every finish is positive: `VICTORY LAP` for first, `PODIUM FINISH` for second and third, `RACE COMPLETE` otherwise. Best streak is this race only. Nothing on this screen is stored except records from clean modes and the fact history.

## Fairness

The guardrails the bellringer enforces in code, kept on purpose and written down so nobody removes one by accident.

- A wrong answer costs only the streak. It never adds questions, never moves the kart back, never starts a timer.
- Attacks inflate one lap and die at its end. Magnitude is bounded by the lap, not the attacker.
- A finished racer is out of reach and out of the fight.
- Pit crew is always available and always counts for progress. A child can never be trapped on a fact.
- The results screen has no bottom: it names the child's own place and the top three, nothing else.
- The minimap shows everyone, but the callouts only ever say `PASSED BOLT` or `BOLT SLIPPED PAST`, never a running last-place label.
- Rivals never pile on: no consecutive hands at the child, never at the racer in last.
- Stalls are two to three seconds and never come from Oil Slick, Tow Hook, self-boosts, or blocked hits.

## The view

Behind the kart, looking down the track, in the manner of a 16-bit kart racer: the road narrows to a vanishing point, curves swing the horizon, roadside garage props scale up as they approach, the child's kart sits low center, rivals appear ahead as scaled sprites and disappear behind. The track is a closed circuit of twelve sectors, one per lap-table, each with its own landmark: the twos pass the tire wall, the sevens run under the roller door, the twelves cross the diagnostic grid to the finish.

```
┌──────────────────────────────────────────────────────────────┐
│ LAP 7/12  THE SEVENS        2nd          ┌─────────┐  3:12    │
│                                          │  ○ Bolt │ minimap  │
│                  7 × 8                   │ ●You    │          │
│                 ┌──────┐                 │   ○ Pis │          │
│                 │  5_  │                 │  ○ Gask │          │
│                 └──────┘                 └─────────┘          │
│        \                          /                          │
│         \    [Piston]            /        POWER-UP CHARGE     │
│          \                      /         ▮▮▮▮▮▮▮▮▮▯▯▯ 9     │
│           \      [Bolt]        /                              │
│            \                  /           HAND  1 Nitro       │
│             \     🏎 you     /                  2 Wrench      │
│              \______________/                   3 Roll Cage   │
│  ░ garage floor grid ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
└──────────────────────────────────────────────────────────────┘
```

- **The fact and the field** sit in the upper center at the largest type on screen, over the horizon, never over the karts.
- **Minimap** top right: the circuit as a loop with twelve sector ticks, every kart as a colored dot with its number, the child's dot emphasized. It is the honest picture of the race; the main view is the exciting one.
- **HUD**: lap and table name top left, place beside it, race clock top right, streak charge and the held hand lower right, Roll Cage count as small icons by the place.
- **Speed** in the view is effective progress rate: a Turbo throws the road forward, a Pile-Up landing pulls the horizon back and shows the attacker's kart sweeping past. The kart never actually reverses; the road does the telling.
- **Callouts** for 1.6 s: `PASSED BOLT`, `BOLT SLIPPED PAST`, `ROLL CAGE HELD`, `WRENCH ▸ PISTON`.

### Rendering approach

The constraint is a stock Omarchy install with no extra packages, and an acceptable frame rate in a software-rendered VM. Checked against the Quickshell source, the Arch package graph, and the Qt 6 documentation on 2026-09-02.

**True 3D is out.** Qt Quick 3D is not installed on a stock Omarchy and is not a dependency of Quickshell; a plugin that imports it fails to load with nothing but a warning in the shell log. So "3D graphics if possible" resolves to pseudo-3D, which is also what the kart racers this game remembers actually did.

**The approach: a shader ground plane plus sprite karts.**

- One full-screen `ShaderEffect` draws the road, rumble strips, lane markings, grid floor, horizon, and fog analytically per pixel by inverting the camera projection. Curves and hills are a handful of uniforms, so the road bends with no per-frame geometry work in JavaScript. The shader ships precompiled as a `.qsb` file, baked once on a developer machine with the Qt shader tools; the child's machine needs nothing extra. A listed and verified Omarchy overlay plugin already renders its whole game this way, so the pattern passes the marketplace scan.
- The plane renders into a layer at a fixed internal size, 480 by 270, scaled up with nearest-neighbor filtering. That caps the fragment work at about an eighth of 1080p, which is what keeps it viable on a CPU renderer, and it is also the pixel-art look the garage wants.
- Karts, roadside props, and the ghost are ordinary `Image` items positioned and scaled each frame from the same projection formula, drawn back to front. Kart bodies are pre-rendered sprite sheets at eight angles and three scales, so the voxel karts from the mock appear as sprites, not geometry. Small textures batch through the scene-graph atlas, so a few dozen sprites cost little.
- A `FrameAnimation` drives the camera, the sprite positions, and the HUD, and runs only while the overlay is open, so a closed game costs the shell nothing.
- The minimap is plain QML: a `Shape` loop with dots.

**Fallback and floor.** If the shader fails to compile on a machine, the view falls back to a `Canvas` port of the classic segment-based road renderer at the same internal size, which is pure CPU work plus one texture upload per frame and has its own precedent in an Omarchy racing plugin. If even that is too slow, the reduced-motion setting also switches the road to a static perspective plane with sprites, which is the cheapest picture that still reads as looking down the track.

**Target:** 60 fps on any machine with a GPU; 30 fps in the software-rendered VM at the internal resolution. The implementation plan includes a frame-rate counter and a measured budget before any art is finished.

## Garage Room

The lobby follows the Garage Room mock: title bar, policy rail, the kart stall with a big kart under a work light, the roster on the right, and the race settings, signals, and the big ready control along the bottom. In solo the roster holds the child and the three rivals; the invite code and the friend badges are simply absent rather than greyed, and a `RACE A FRIEND` tile in their place says "ask a parent to install Kids Play" until the platform exists.

- **Kart stall:** cycle six original kart bodies; pick a paint from eight swatches; pick a number 1 to 99 with arrows. "Colors and numbers are visible to all racers." There is no name field anywhere.
- **Roster:** four slots with kart preview, color, number, a ready lamp, and for rivals a level badge (`ROOKIE` `PRO` `CHAMPION`).
- **Settings rows:** Track (the circuit; one in V1), Race mode (Practice, Time trial, Ghost, Grand Prix), Math set (the preset), Rivals (level), Goal (fixed: finish all laps).
- **Preset signals:** the four-signal catalog shown so the child learns them before racing rivals who use them.
- **`READY UP`** starts the countdown. `LEAVE` returns to the garage home.

## Visual style

**Ground:** near-black from the theme's darkest background; Garage Grid stays dark under a light theme. **Light:** warm amber for work lights, lap lamps, the streak charge, boosts. **Shadow:** dark teal for the revealed answer, the ghost kart, secondary surfaces. **Chrome:** the theme's `accent` for focus rings and the selected control, so the game belongs to the child's Omarchy.

**Type:** the shell's monospace face for readouts, the clock, the minimap numbers, and the fact itself; the shell's UI face for menus. The fact is never smaller than a tenth of the screen height.

**Karts:** six original low-detail voxel-styled bodies in the spirit of the mock, rendered to sprite sheets at eight angles and three scales so the pseudo-3D view is sprite work, not geometry. Eight paints. Numbers on a white plate.

**Motifs:** checkered flag edges, diagnostic grid floor, rivets on gauge bezels, the roller door, tire walls, a `WELCOME TO THE PIT` terminal. Scanlines a toggle, off by default.

**Motion:** ease-out surges, 500 ms sputter, a road lurch on Turbo, a horizon pull-back on being hit, 1 s countdown beats, 1.6 s callouts. Reduced motion replaces shakes and lurches with gauge and lamp changes and keeps position changes as cuts.

## Audio

Engine idle in the garage and a pitch that rises with effective speed on the track; a surge on correct; a sputter on wrong; a click on the reveal; countdown beeps; a card deal when a hand arrives; distinct sounds for each of the eight cards; a clank for a blocked hit; a finish chime. Original or CC0 with attribution. Sound defaults on. Qt Multimedia behind a loader, so a machine without it gets a silent game rather than a broken one.

## Accessibility

- Every screen operates with the keyboard alone: digits, Enter, Backspace, `H`, `1` `2` `3`, arrows, Escape.
- The fact and the field are the largest text on screen; digits at least 48 px tall at 1080p.
- Every state has shape or text as well as color: lit lamps are filled, the ghost is translucent, rival dots carry numbers.
- Reduced motion removes all shake, lurch, and streak lines.
- Scanlines off by default; nothing flashes faster than 3 Hz.
- No menu ever times out. The race clock is the only clock.
- Screen-reader names on the garage and settings controls; the race view is visual by nature and is not claimed.

## Data

One JSON file in the plugin's own data directory:

| Key | Content | Reset by |
| --- | --- | --- |
| `settings` | sound, reduced motion, scanlines, kart, paint, number, rival level, streak threshold if exposed | Settings |
| `records` | per preset: best clean time, correct, attempted, answer timeline for the ghost | Reset garage records |
| `facts` | per fact: attempts, correct, last three outcomes | Reset fact history |

No dates, no session counts, no Grand Prix history, no streak history. Human-readable, so a parent can see exactly what is kept.

## Decisions, settled 2026-09-02

| Decision | Settled |
| --- | --- |
| Streak threshold | **12.** One clean lap charges a power-up. The bellringer's 15 stays in the test vectors as a parity case. |
| Hand dealing | **Shared round-robin** over the fixed schedule, one cursor for every racer in the race. |
| Second wrong answer | **Reveal and advance.** The answer is shown, progress counts, the fact goes to the pit lane. |
| Rival mercy rules | **As written.** No consecutive hands at the child; never at the racer in last. |
| Rivals send signals | **Yes**, from the four-signal catalog. |
| Records | **Clean modes only.** Time trial and ghost set records; Grand Prix never does. |
| Rival count | **Three everywhere.** Rookie level carries the 2–5 preset. |
| Powerup picker | **Side panel**, keys 1, 2, 3; the question stays visible. |
| Pile-Up in solo | **In the schedule** at every rival level. |
| Kart number range | **1 to 99.** |

Everything else in this document is as designed. The next document is the implementation plan for the plugin alone.

## Out of scope for V1

Multiplayer of any kind (that is Kids Play), division, missing-factor questions, more than one circuit, a parent view inside the plugin, kart unlocks, achievements, any stored history beyond records and fact outcomes.

## Plugin shape for approval

Everything in this section was checked against the Omarchy Quattro shell source, the plugin manual, and the marketplace's own submission, verification, and security-baseline code on 2026-09-02. The Kids category had zero plugins that morning; the Education tag had four; sixty-five plugins carry the Games tag and three of those are overlays, one of them verified. So there is precedent for an overlay game passing review, and no precedent yet under Kids.

### What a plugin is, precisely

A third-party plugin is a public git repository with `manifest.json` at its root. `omarchy plugin add <url> --enable` clones it into `~/.config/omarchy/plugins/<id>/`, validates the manifest, and enables it in `~/.config/omarchy/shell.json`. The shell loads the entry point as a QML `Item` inside the long-lived `omarchy-shell` process. Nothing is sandboxed; the plugin can do anything the logged-in user can. That is why this game has no network code at all, not merely no network features.

### Manifest

```json
{
  "schemaVersion": 1,
  "id": "io.github.<owner>.turbo-tables-solo",
  "name": "Turbo Tables",
  "version": "0.1.0",
  "author": "<owner>",
  "description": "Times-table kart sprint. Solo, offline, ages 7 to 11.",
  "license": "MIT",
  "kinds": ["overlay", "bar-widget"],
  "keepLoaded": true,
  "entryPoints": {
    "overlay": "TurboTables.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Turbo Tables",
    "description": "Opens the garage",
    "category": "Kids",
    "defaultSection": "right"
  }
}
```

Rules the validator enforces: `schemaVersion` is the number `1`; the id matches `^[A-Za-z0-9][A-Za-z0-9._-]*$`, contains no `..`, and is not `omarchy.*`; every declared kind has its entry point; entry points are relative, exist, and contain no `..`; and there are no symlinks anywhere in the repository. The marketplace additionally requires a globally unique id that has never been used or retired, and recommends exactly the `io.github.<you>.<name>` form.

Why two kinds: there is no manifest mechanism to register a keybinding or launcher entry. A child needs something to click. The bar widget is a small kart button whose only job is to toggle the overlay; the README also gives the one-line keybinding for parents who prefer that. One caveat to verify early: a community plugin reported that enabling a plugin with two kinds only wrote the bar entry; if that reproduces for overlay plus bar-widget, fall back to a bar-widget that hosts its own panel, which is how the existing kids typing plugin is built.

### Overlay contract

The host injects `shell`, `manifest`, and `omarchyPath` as properties if the root item declares them, and calls `open(payloadJson)` and `close()`. The pattern every first-party overlay follows:

```qml
Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.manifest.id)
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "turbo-tables"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { /* digits, Enter, Backspace, Space, Escape, arrows */ }
      onActiveFocusChanged: if (!activeFocus && root.opened) Qt.callLater(forceActiveFocus)
    }
  }
}
```

Points that matter for a game where a child types the whole time: keyboard focus is `Exclusive` only while open and `None` the moment it closes, so the desktop gets its keys back; the focus item re-grabs focus defensively; `dismiss()` tells the host it closed itself, otherwise the toggle command thinks it is still open; `keepLoaded: true` keeps the garage state alive between summons; and every `Text` uses `textFormat: Text.PlainText`, which the shell's own test suite enforces in-tree.

### Theme

`import qs.Commons` gives `Color` and `Style`. The game reads `Color.menu.background`, `Color.menu.text`, `Color.accent`, and `Style.font.family`, `Style.font.display`, `Style.space()`, and `Style.cornerRadius`, so it belongs to the child's theme. Garage Grid's amber and teal are the game's own constants layered on top. There is no reduced-motion token anywhere in the shell, so the game's reduced-motion switch is its own setting.

### Game loop, input, persistence

- **Loop:** a `FrameAnimation` drives the track view, sprite positions, and rival timers while the overlay is open; a 100 ms `Timer` drives the race clock and rival think-time deadlines. Both stop when the overlay closes.
- **Rules in plain JavaScript.** Deck generation, the answer loop, combo and boost, and ranking live in `game/*.js` with a guarded `module.exports`, so the same files run under Node for tests and inside QML for play. This is the pattern the verified overlay games use, and it is what makes the seed-to-deck test vectors possible.
- **Persistence:** one JSON file at `${XDG_DATA_HOME:-~/.local/share}/turbo-tables-solo/garage.json`, written with `FileView { atomicWrites: true }` and a 400 ms debounce, guarded so a hot reload cannot overwrite live state with an empty file. Data, not state, because records and fact history are earned. No `Process`, no helper script, no shell command anywhere in the plugin.
- **Audio:** Qt Multimedia `SoundEffect` behind a `Loader`, documented as an optional dependency.

### Security baseline: what the scanner looks for and how to pass clean

The marketplace runs a static scan on `.qml`, `.js`, `.sh`, `.py`, `.toml`, `.yml`, the README, and any executables. Outcomes are `passed`, `review-required`, or `needs-fixes`. Only `passed` with no detected capabilities becomes "Snapshot verified" automatically after a maintainer approves the listing; anything else needs a maintainer to attest to each capability.

| Scanner rule | Triggered by | Turbo Tables |
| --- | --- | --- |
| `curl-pipe-shell`, `remote-git-execution-unpinned`, `cargo-git-unpinned` | `curl`, `wget`, `git`, or `cargo` inside any `command:`, `exec`, `spawn`, or `execDetached` payload | no command payloads exist |
| `privileged-process-control-from-shared-temp` | PID files in `/tmp` | none |
| `sudoers-dangerous-passwordless-command` | sudoers rules | none |
| `installer` capability | any file named install, installer, setup, or uninstall | no such files; the settings screen is `Settings.qml`, not `Setup.qml` |
| `package-manager` capability | `pacman`, `yay`, `pip install`, `npm install`, `omarchy pkg add` mentions | none, including in the README |
| `privilege` capability | a non-negated mention of `sudo` or `pkexec` | the README says "needs no sudo or pkexec", which the scanner treats as negated |
| `service-management` capability | `systemctl`, `systemd-run`, unit files | none |
| `bundled-executable-binary` capability | any ELF, PE, or Mach-O file | none; sounds are WAV, art is PNG, the baked shader is a Qt `.qsb` container, which a verified plugin already ships without triggering the rule |

The scanner has no rules about network calls, file writes, or `Process` as such. Those are README-disclosure matters. The game avoids them anyway, and says so.

### Repository layout

```
omarchy-kids-game-turbo-tables/
├── manifest.json
├── TurboTables.qml          overlay entry
├── BarWidget.qml            kart button that toggles the overlay
├── qmldir                   exports local components
├── ui/                      Garage.qml, Race.qml, TrackView.qml, Minimap.qml, Picker.qml, Results.qml, Settings.qml
├── game/                    deck.js, race.js, powerups.js, rivals.js, rank.js  (plain JS, Node-testable)
├── vectors/                 decks.json, hands.json, rivals.json  (seed → sequence test vectors)
├── shaders/                 road.frag (source) and road.frag.qsb (baked; the only "binary", not an executable)
├── assets/                  karts/*.png sprite sheets, props/*.png, cards/*.png, sfx/*.wav
├── tests/                   node tests + copied manifest-entrypoints fixture
├── preview.png              one root preview, under 50 MB
├── LICENSE                  MIT
├── NOTICE                   CC0 attributions if any
└── README.md
```

No symlinks. No `scripts/`, `bin/`, `install.sh`, or `setup.sh`. Nothing executable.

### README sections the reviewers and the hub both expect

1. What it is, who owns it, and a link back to the Kids Mode hub.
2. **Install:** `omarchy plugin add https://github.com/<owner>/omarchy-kids-game-turbo-tables --enable`
3. **Open it:** the kart button in the bar, or a keybinding snippet for `~/.config/hypr/bindings.lua`: `o.bind("SUPER + SHIFT + T", "Turbo Tables", "omarchy-shell shell toggle io.github.<owner>.turbo-tables-solo")`
4. **Remove:** `omarchy plugin remove io.github.<owner>.turbo-tables-solo`, plus the one data file path if the family wants it gone.
5. **Permissions and privacy:** makes no network requests; reads and writes exactly one file it owns; runs nothing privileged; needs no sudo or pkexec; collects nothing about a child; has no name field.
6. **Dependencies:** Qt Multimedia for sound, optional.
7. **License** and asset attributions.
8. For the hub: the plugin never collects anything about a child, and the README says so in those words.

### Testing before submission

- `omarchy plugin validate .` passes.
- `qmllint -I /usr/share/omarchy/shell TurboTables.qml BarWidget.qml ui/*.qml` is clean.
- `node tests/run.js` reproduces every vector in `vectors/` and covers the answer loop, streak and hand dealing, all eight powerup effects including floor, lap reset, Roll Cage stacking, Tow Hook swap, finished-racer immunity, the effective-progress formula, rival decisions, pit lane, and ranking.
- A copy of Omarchy's `manifest-entrypoints` fixture loads the overlay with mocked `shell` and `manifest` and reports no failures.
- Hot-reload development loop: keep the repo checked out at `~/.config/omarchy/plugins/<id>/`; saves reload live; `qs log -p /usr/share/omarchy/shell --tail 100` shows QML errors.
- A recorded keyboard-only run through Practice, Time trial, and Ghost.

### Submission

- Category **Kids**; tags **kids, education, games** (three is the maximum).
- Maintainer notes: "Pure QML and JavaScript. No network, no processes, no binaries, no install scripts. Writes one JSON file under the user's data directory. Optional Qt Multimedia for sound. Built for the Omarchy Kids Mode community."
- All five checklist attestations are true by construction, including "does not overwrite user configuration without explicit consent": the plugin touches only its own file.
- Verification is bound to an exact commit. Tag a release, submit that commit, and batch later changes, because every new commit needs the verify form and a maintainer decision again to keep the verified badge.

### Two facts to carry into the multiplayer work

A plugin installs with no password, so under today's Kids Mode a child can add any plugin from any URL. That is fine for this game and is the reason the multiplayer platform is not a plugin. And the shell loads plugin code into the child's session with no isolation, so a plugin listed under Kids is a promise the author makes, not a property the system enforces; the hub's review checklist is the control.
