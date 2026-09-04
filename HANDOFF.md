# Handoff: Turbo Tables Solo, after piece C round 3

Written 2026-09-04 at `cc4064b` on `gauntlet/turbo-tables-build`. The run stopped
on the maintainer's instruction once the cars were judged ready enough to hand
back to the gauntlet loop with the new assets, not because every piece is won.
This packet is written for the next coordinator. Read `docs/plan.md` (v2) and
`docs/design.md` (v3) first; this file says where the tree is against them.

## 1. Where the tree stands

| piece | state | last verdict |
| --- | --- | --- |
| 1 rules engine | frozen won (round 2) | "Better implementation of the specification: A" (ours) |
| 2 rivals, ghost, save | frozen won (round 4) | "YES: `src/engine/save.ts` now implements the design's Data and Modes rows faithfully" |
| 6 package and gates | frozen won (round 4, hardened round 5) | "Winner: Candidate A" (ours) |
| 7 shell integration | won round 2, hardened round 3 | "As good as the first-party overlay? YES. Safe on a child's machine? YES." Round 3 (cold-summon warm-up) is built and VM-verified: 0 of 25 keys leaked over 5 cold starts, 0 of 35 warm. |
| C cars | **built through round 3, not yet judged** | Round 2: "Craft: NO. Pipeline: YES." Round 3 answers round 2's coordinates; see section 3. |
| 3 garage | to re-run under v3 | Round 5: ours won "on content and interface, not on craft". Round 6 built (one camera, real shadow, Tab) and never judged. |
| 4 race view | to re-run under v3 | Round 2: ours won "partly on craft, for the first time, and still not on the picture". Round 3 built (minimap, the loop that never ran) and never judged. |
| 5 countdown, picker, results, settings | to re-run under v3 | Round 3: NO (the card key cost a streak). Round 4 built (the rewrite) and never judged. |
| seam (save file end to end) | **open, and the first thing to do** | Round 2: "YES, this plugin can still replace a child's records". Round 3 built. Then the VM verifier found the way out dead; section 4. |

Every gate is green at `cc4064b`: `npm run check` exit 0 (657 engine tests,
types, boundary, bundle, sprites, README honesty), `qmltestrunner` 136/0 on
`tests/qml` and 37/0 on `tests/qml-shell`, scanner `passed`, and
`npm run sprites -- --verify` rebakes all 48 sheets byte-identical.

## 2. Install, open, play

Install as the README says: clone into `~/.config/omarchy/plugins/` and
`OMARCHY_PATH=/usr/share/omarchy omarchy plugin enable io.github.dmcchesney.turbo-tables-solo`.
The overlay needs its own entry under `plugins` in `~/.config/omarchy/shell.json`;
`omarchy plugin enable` writes it (see `docs/environment.md` for the traps).
Open it from the kart button in the bar, or bind a key:

```lua
o.bind("SUPER + SHIFT + T", "Turbo Tables", "omarchy-shell shell toggle io.github.dmcchesney.turbo-tables-solo")
```

`Escape` closes the overlay and hands the keyboard back.

What to play, in order, to see the whole game:

1. Practice on the 2s to 5s (garage: MATH SET, then READY UP).
2. A Time trial on the same set.
3. The Ghost against your own time trial.
4. A Grand Prix at Pro rivals: the full 12-lap race with power-ups and the results screen.

## 3. The cars, before and after

The bar is `docs/golden-hour-car.png`. The pictures:

- `docs/handoff/coupe-beside-the-bar.png`: the crop, then the round-2 coupe, then the round-3 coupe, stall camera, nose to the lens, at 3x.
- `docs/handoff/bodies-before-after.png`: six bodies, round 2 on the left, round 3 on the right, at stall/0, stall/4 and road/0.
- `docs/handoff/cutouts-before-after.png`: the same as black cut-outs, the plan's silhouette test.
- `docs/handoff/garage-after.png`, `countdown-after.png`, `race-after.png`: the three screens at 1920x1080 through the harness, seeded body 0, paint 0, number 42.

What round 3 changed and measured (the critic's own scripts, 192 cells):

| measure | round 2 | round 3 |
| --- | --- | --- |
| air under the sills from behind, columns with >= 8 px of gap | 0% (max 3 px) | 87 to 97%, max 11 to 18 px |
| coupe vs saloon as cut-outs, XOR over union, 48 px road/0 | 4.6% | 11.1% |
| same at 192 px | 9.4% | 16.1% |
| rim (highlight step) from the road camera, coupe / wedge / saloon | 1.2 / 0.6 / 1.9% | 5.3 / 5.2 / 5.6% |
| rim from the road camera, hatch / buggy / pickup | 0.8 / 0.8 / 0.4% | 1.8 / 1.8 / 3.5% |
| chromatic sheets swatch-dominant by hue | 42 of 42 | 42 of 42 (own-hue 81.8 to 97.2%) |
| number panel visible, stall yaws | pickup 2 of 8 | pickup 4 of 8, others 5 to 6 of 8 |
| sheets on disk | 1,495,037 bytes | 1,294,730 bytes |

The move that did it was the camera, not the tyres alone. From a camera 2.8
units up the rear bumper's bottom edge projects within half a degree of the
tyre-contact line, so no geometry could show air from behind. Both cameras
came down to the bar's eye level (stall z 3.7 to 2.0, road 2.8 to 1.8), and
the bodies changed under them: bumpers lifted to the sill line, tyres larger
and proud of narrower flares, arch openings clear of the tyre, the coupe
wider and lower against a narrower taller saloon, tail bars tall enough to
survive the 48 cell, the pickup's roundel moved out from behind its flare.
Raising the bumpers buried the rear plates and two CarSprite tests failed;
the plates moved up. The commit message at `cc4064b` has the full table.

**Reservations on the cars, stated plainly.** Round 3 has not been judged by
a blind critic. Against my own targets it misses three: coupe vs saloon at
48 px is 11.1% apart, not 15%; the road-camera rim is under 4% on the hatch,
buggy and pickup; pickup/purple's own-hue share is 81.8%, under 84%. Not done
at all: the number in the roundel and the plate together where both face the
camera (a contract change, `scratchpad` `pieceC/CONTRACT.md` and `meta.json`
would gain an `also` list); digits at the 96 cell; a cream livery panel and
stripe on chromatic paints (the band is the paint's highlight step, which
reads as a tone, not a decal). The number on white paint sits on a dark band
and reads; on the pickup the roundel is on the bed side, not the door.

## 4. The seam: the way out is dead, and the tests hid it

A verifier drove the real shell in the VM at `b9fb591` and found that the
quarantine's START A NEW SAVE FILE button never reaches `shell/FileStore.qml`
for any read-side quarantine (corrupt, legacy, `chmod 000`, shut home). Cause:
`ui/Store.qml` runs `adopt(null)` at construction, before `TurboTables.qml`
assigns the text backend, which sets the protocol latch to "object"; the
authorised replacement then refuses "text" against "object" and the strip
shows an internal sentence about protocols. `tests/qml/tst_store.qml` hid it
by setting `Store._adoptedFormat = ""` by hand before the button scenarios.
Underneath, the shell runtime's file writer cannot replace a `chmod 000`
file at all (`saveFailed(PermissionDenied)`, atomic or not), which the test
double under `tests/qml-shell/` (`FakeFs.qml`) models as succeeding. No save was
destroyed; the family is left in the trapdoor. The full report is section 4
of the verifier's file (`scratchpad/verdicts/vm-b9fb591.md` in session
2feb2154; the defect list is reproduced in the kickoff prompt below). A seam
round-4 builder was briefed and died at a usage limit before editing anything.
**This is the first piece to run.**

## 5. Frame rates, honestly framed

- Mac, software rasteriser, offscreen, 1920x1080 through the harness: garage 62.7 fps, countdown 62.4, race 61.7. These are the harness's own counter under the software backend; they say the CPU can paint the frame, not what a GPU does.
- VM, real shell, race view: 35.5 fps, median 29 ms per frame, p95 37 ms. **The VM image pins every Qt client to llvmpipe** (`LIBGL_ALWAYS_SOFTWARE=1` in Hyprland's environment), so this is the software path; a scratch instance without the variable gets virgl and 60 fps on a trivial scene. The device number has still not been measured on a GPU.

## 6. Placeholders and things accepted with a reservation

- The garage's left wall and shelves are flat; the roller door and sunset are the prototype's.
- The race view's rival labels float under or over far cars, and lane 0 puts a car's wheels on the kerb at the start line (both noted by two critics; piece 4's re-run owns them).
- Sound is absent by design at this stage; the README makes no audio claim.
- `docs/open-questions.md`: race mode and math set are not persisted (the design's Data row), and the multi-agent tree rule (never `git checkout --` here).
- The M2 gate clause at Pro (about 50%) was diagnosed as correlation and recorded, not fixed.
- Piece 7's "the first summon leaks keys" is closed and VM-measured; the "full disk" and "hung mount" cases remain inference.

## 7. Environment facts the next coordinator needs

- Every Qt process on the Mac is headless (`QT_QPA_PLATFORM=offscreen`, `QT_QUICK_BACKEND=software`, `-platform offscreen`); Don works on the machine while agents run. Blender runs `-b` only.
- Never revert with git in this tree; several agents write to it and it is 9p-mounted live into the VM. A builder that must rebake works in a worktree and fast-forwards.
- The VM is up again (`ssh omarchy-turbo-tables`); `utmctl start` on a running VM says OSStatus -2700, which is not an error. Never `omarchy plugin remove` there.
- The scanner needs `TURBO_TABLES_MARKETPLACE=/Users/don/Developer/omarchy-plugin-marketplace` from a worktree.
- `qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml` and `-import ui -import tests/qml-shell -input tests/qml-shell`.

## 8. Kickoff prompt for the next session

> Continue the Turbo Tables Solo build under `docs/plan.md` v2 and `docs/design.md` v3 from `cc4064b` on `gauntlet/turbo-tables-build`; read `HANDOFF.md` first. Pieces 1, 2 and 6 are frozen won; piece 7 is won and hardened. First run **seam round 4** as a piece of its own: the quarantine's START A NEW SAVE FILE button is dead in the shipping wiring (`ui/Store.qml` latches "object" at construction before `TurboTables.qml` assigns the text backend; `tst_store.qml` hides it by hand-setting `_adoptedFormat`; `FakeFs.qml` models a `chmod 000` file as writable when the shell runtime in the VM refuses it) and the fix must be proved in the VM with the button route S, Down x7, Return, Right, Return on a legacy file, a `chmod 000` file, a corrupt file and a missing file, restoring the guest's save byte-identical. Then run the **piece C critic once more, blind, on `cc4064b`** against `docs/golden-hour-car.png` with the cut-out test first; if craft is YES freeze piece C, if NO run one more builder round from its coordinates and stop there either way. Then pieces 3, 4 and 5 in parallel from the current tree (the prototype is already merged; do not start from `proto/golden-hour`), then 6, then 7 in the VM. For each piece fan out a builder and a fresh critic; the critic compares ours against the bar blind, labels stripped, on that piece's rubric, and is harsh. Every Qt process is headless; never open a window on this Mac. Never revert with git in this tree. Never break the rules under "Rules the builder may not break." `/loop` on each piece until the critic picks ours. When every open piece is won and CI is green, rewrite `HANDOFF.md` and stop.
