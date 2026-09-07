# Handoff: Turbo Tables Solo, ready for the play-test pull request

Written 2026-09-07 on `gauntlet/turbo-tables-build`. This packet is for two readers: the
maintainer opening the pull request into `main`, and the next coordinator who continues the
gauntlet loop after the play test. It says where every piece stands against `docs/plan.md`
(v3.1) and `docs/design.md` (v4.2), what was proved today, and what is still open.

## 1. Where the tree stands

| piece | state | last verdict |
| --- | --- | --- |
| 1 rules engine | frozen won | "Better implementation of the specification: A" (ours) |
| 2 rivals, ghost, save | frozen won | "YES: `src/engine/save.ts` implements the design's Data and Modes rows faithfully" |
| C cars | frozen as a build (round 4) | Round 3 said craft NO on the glasshouse; round 4 answered it and was the last round on it by the maintainer's instruction |
| seam (save file end to end) | closed (round 4) | The dead START A NEW SAVE FILE button found in the VM was fixed in seam round 4 and proved on the four quarantine cases |
| 7 shell integration | won and hardened (round 3) | "As good as the first-party overlay? YES. Safe on a child's machine? YES." Cold summon 0 of 25 keys leaked |
| T track | built to round 3 | The shader world and the prop kit placed by sector; judged by the maintainer's play, not yet by a critic |
| M mouse | built to round 5 | Every control clickable with parity to the keyboard; `tst_mouse_parity` is the gate |
| F feel | **round 7 WIN; round 8 built, not yet judged** | Round 7: "the hand now fires on the first press of a key that can never be a digit ... and the answer line `7 × 8 = ▮` is unmistakably the place to type." Round 8 (`49159fd`) answered nine of the critic's twelve defects with a named test and a mutation each; a fresh critic has not seen it |
| 3 garage | round 2 under v4 | One room, one light; judged by the maintainer's play |
| 5 countdown | round 1 under v4 | The race's own view held at the start line |
| 6 package and sound | round 1 under v4; sound handed off | Fifteen synthesised power-up cues nobody has heard (`docs/open-questions.md` section 6) |

Every gate is green at HEAD: `npm run check` exit 0 (engine tests, types, boundary, qml ids,
key hints, bundle, sprites, props, terrain, sfx, README honesty, marketplace scan `passed` with
no findings and no capabilities), `qmltestrunner` 307/0 on `tests/qml` and 38/0 on
`tests/qml-shell`, 659 engine tests, and the CI mouse suite 43/0 on the runner's Qt 6.4 as well
as on Qt 6.11. CI is green at `49159fd`.

## 2. What was done for the play test on 2026-09-07

- **Piece F round 7** (`5d53a5d`): the maintainer's second-session findings. Digits never touch
  the hand; Left and Right move the highlight, Up and Down aim, Space fires; Enter is only the
  answer and Escape only leaves. The fact and the answer are one line with a blinking caret;
  the stall is drawn on that line; one callout slot; race hints are key caps; results say
  ANSWERS SHOWN, BEST COMBO and N CARDS PLAYED under a sunset band. A blind critic called it a
  WIN on the two findings.
- **Packaging** (`a88cf47`): `manifest.json` and the README stop saying the game is being built.
  `preview.png` is the garage as the plugin draws it, taken through the harness; the README gate
  now requires it and holds README and NOTICE to the same two sentences about it. The 1.78 MB
  multiplayer mock is deleted. NOTICE records the props, the sound and the shader.
- **The add, enable, play, remove cycle was executed** in the Omarchy 4 VM against a clone of
  the pushed branch under a different plugin id: add cloned, validated and enabled both kinds;
  the overlay opened and a race ran; remove deleted the folder and unloaded the plugin and left
  the second kind's `shell.json` entry behind exactly as the README says, which
  `omarchy plugin disable` cleared. The README's Remove section now says so.
- **Piece F round 8** (`49159fd`): the engine decides a card was spent. `fire()` requests a play
  and the slam, the sound and the hand's reset happen only on the engine's `cardUsed`; nothing
  fires after the child has finished, during the deal, or with no rival to aim at. `POWER-UP
  READY` reads on the charge bar at the deal; digits typed during a pit-crew reveal are held;
  the countdown draws the full line `7 × 8 = ▮`; the Pile-Up telegraph is the decided 900 ms;
  the callout slot hangs above the line's ink so it can never sit on a far kart (a departure
  from v4.1's "under the fact line" wording, with the measurements in the commit); browsing
  cards keeps the aim; the three-digit-answer test is back; the harness's card injection is
  bounded. Sixteen mutations each kill their named test. A flaky mouse-parity case was a real
  race (a card was a click target while being dealt) and is fixed.
- **CI on the runner's Qt** (`0fe3ca6`): two mouse-parity tests failed only on Ubuntu 24.04's
  Qt 6.4.2. Reproduced in a container built from the workflow's own package list; neither was a
  product defect (a discarded delegate Qt 6.4 still reports visible; the software renderer
  re-rasterising two text layers on first hover). The tests now measure the rule, and each still
  fails when its rule is broken.

## 3. Open after round 8

Unjudged: round 8 has not had a blind critic; the round-7 verdict is
`scratchpad/verdicts/pF-round7.md` in session 661478d4 and round 8's evidence is `pF8/` there.
Left deliberately: the hand card text overruns its tier label at 1024 by 600 (pre-existing);
the highlight is a border tone and a small mark, which is a design call; the victim's impact
(sparks, jolt, smoke) from `docs/open-questions.md` 5.3 item 5 is its own piece. Observed and
not touched: the fact line is drawn 114 px higher on the countdown than in the race at 1080p,
so it moves across the cut; GO on the countdown is now 17 to 19 percent of the frame beside
the wider line, down from 23. The pictures of every screen at this commit are under
`docs/handoff/` (`garage-after.png`, `countdown-after.png`, `race-after.png`,
`results-after.png`).

## 4. Performance, measured today

The plan's performance section binds every remaining round and says the in-game counter
saturates; these are the numbers behind it.

| where | state | CPU | RSS |
| --- | --- | --- | --- |
| VM shell process, llvmpipe, 1920 by 1200 | overlay closed | 0 | 644 MiB |
| | garage open | 0 | 674 MiB |
| | racing | 2.1 cores | 722 MiB |
| | closed again after a race | 0 | 731 MiB |
| Mac harness, software backend | race at 1920 by 1080 | 22 ms CPU per frame | 265 MB |
| | race at 480 by 270 | 17 ms CPU per frame | 217 MB |
| | track held still at 480 by 270 | 2.6 ms per frame | |
| | garage | about 0 | |

Read with care: the VM image forces software rendering for every shell window
(`LIBGL_ALWAYS_SOFTWARE=1`), which a child's machine with an integrated GPU does not; and under
Qt's software backend the track takes the Canvas road fallback, so the Mac's per-frame number
is the JavaScript road a GPU machine never runs. Neither is the child's machine. The plugin
retains about 87 MiB after the overlay closes, and the prop kit decodes to 145 MB of RGBA from
0.43 MB on disk (the water tower is 2592 by 2870 for a sprite sixty pixels tall). The steps, in
order: a real instrument (CPU seconds per frame at two sizes); render the whole race into a
half-resolution layer when Qt reports a software renderer; a smaller prop kit and freeing the
race's images on close; audit the per-frame JavaScript; run the VM shell without the software
variable for a virgl number; ask testers for their GPU and a shell CPU reading while racing.

## 5. Install, open, play

Install with the one-line `omarchy plugin add` command in the README's Install section (this
file may not carry a URL: the honesty gate's no-network invariant covers it). Open it from the
kart button in the bar, or bind a key:

```lua
o.bind("SUPER + SHIFT + T", "Turbo Tables", "omarchy-shell shell toggle io.github.dmcchesney.turbo-tables-solo")
```

Play, in order: Practice on the 2s to 5s; a Time trial; the Ghost against it; a Grand Prix at
Pro rivals. `Escape` is back one everywhere. Remove with
`omarchy plugin remove io.github.dmcchesney.turbo-tables-solo --yes`, then
`omarchy plugin disable` once more for the overlay's entry, then delete
`~/.local/share/turbo-tables-solo/garage.json` if the records should go too.

## 6. What testers should be asked to report

- Their graphics hardware (`lspci | grep -i vga`) and the shell's CPU while racing (`top`
  on `omarchy-shell`), because no GPU number exists yet.
- Whether the hand fires the first time, every time, and whether the answer line is where
  they typed without being told.
- Anything the sound does, since nobody who built it has heard it.
- The size of their screen: the game is checked at 1920 by 1080, 1366 by 768 and 1024 by 600.

## 7. Known flakes and environment facts

- `tst_mouse_parity` `test_32` was flaky about one run in three; round 8 found the cause (a
  card accepted clicks while being dealt) and fixed it, 6 of 6 green after.
- CI's QML job runs Ubuntu 24.04's Qt 6.4.2 and only the mouse suite and the parity walk; the
  298-test suite runs on the Mac and in the VM (Qt 6.11). A faithful container recipe is in the
  session scratchpad under `ci-qt/`.
- Every Qt process on the Mac is headless; never open a window. Never revert with git in this
  tree and never `git add -A`; several agents write to it and it is 9p-mounted into the VM.
- The VM's `omarchy-launch-shell` is a supervisor that respawns the shell; kill supervisors by
  pid, then the shells, clear `/run/user/1000/quickshell`, launch once, wait for the ping.
- The scanner needs `TURBO_TABLES_MARKETPLACE=/Users/don/Developer/omarchy-plugin-marketplace`
  when run from a worktree.

## 8. Kickoff prompt for the next session

> Continue the Turbo Tables Solo build under `docs/plan.md` v3.1 and `docs/design.md` v4.2 from
> HEAD of `gauntlet/turbo-tables-build`; read `HANDOFF.md` first. Pieces 1, 2, 6 (v1), C, 7 and
> the seam are frozen. Piece F is won on the maintainer's findings; run one blind critic on
> round 8 (`49159fd`) first and carry forward whatever it and section 3 leave open. Then a performance piece under the plan's performance section,
> instrument first, with the steps HANDOFF section 4 gives and the play testers' hardware
> reports as the bar. Then the victim-impact work of `docs/open-questions.md` 5.3 item 5 as a
> piece of its own, then 3 and 5 under v4.2, then 6, then 7 in the VM. Never two pieces on one
> file at once. For each piece fan out a builder and a fresh critic; the critic compares ours
> against the bar blind, labels stripped, on that piece's rubric, and is harsh. Every Qt process
> is headless; never open a window on this Mac. Never revert with git in this tree, and never
> `git add -A`. Never break the rules under "Rules the builder may not break." `/loop` on each
> piece until the critic picks ours. When every open piece is won and CI is green, rewrite
> `HANDOFF.md` and stop.
