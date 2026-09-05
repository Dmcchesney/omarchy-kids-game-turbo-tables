# Open questions and known hazards

Things found during the build that need a decision or a fix, recorded so they
are not lost between sessions. Neither is a defect in shipped behaviour today.

## 1. `raceMode` and `mathSet` do not survive a restart

**Status:** needs a decision from the maintainer, after playing it.

`docs/design.md`'s Data table lists exactly what `settings` holds:

> sound, reduced motion, scanlines, kart, paint, number, rival level, streak
> threshold if exposed

Race mode and math set (the preset) are not in that list, and `src/engine/save.ts`
rejects unknown keys by design. So the garage's `RACE MODE` and `MATH SET` rows
are usable in-session and reset to their defaults on restart.

That is faithful to the design as written. It may still be wrong for a child, who
would have to re-pick their preset every time they open the game. The fix, if it
is one, is an edit to the design's Data row followed by adding the two keys to the
`settings` schema and its validator — not a workaround in the UI layer, and not
smuggling unknown keys past the validator.

Decide after a play session. Recorded rather than changed, because the design is
settled and a build agent may not amend it.

## 2. `git checkout --` in this working tree destroys uncommitted work

**Status:** hazard, largely mitigated; keep the rule.

While mutation-testing the engine, a build agent reverted its own edits with
`git checkout -- src/engine/save.ts` and destroyed the entire uncommitted file,
which at that moment held an hour of unrelated finished work. It was reconstructed,
but the failure mode is real and silent.

Two things make this tree unusually exposed:

- Work arrives from several agents at once, so at any moment the tree can hold
  finished work from someone else that `git checkout --` will not warn about.
- The checkout is 9p-shared into the Omarchy VM, so a file can also change under
  a process that is mid-read.

Rules that follow, and that every build and critic brief now carries:

- **Never** use `git checkout --`, `git restore`, `git stash` or `git clean` to
  undo a mutation in this tree. Copy the file to a backup path first and restore
  from the copy.
- Verify a revert by content hash against your own pre-edit copy, not by
  `git diff` — much of this tree has been untracked for long stretches, and
  `git diff` shows nothing for a file git has never seen.
- Commit each piece as its critic freezes it, so the window in which uncommitted
  work exists stays short.

## 3. Maintainer feedback after the first play session, 2026-09-04

Don played the game — in the VM as the real plugin, and reported it fun. Two
changes he wants first, ahead of anything the loop was doing when it paused:

### 3.1 The course should be more beautiful

The race view is the screen a child spends the whole game looking at, and it is
the one that has had the least art. What is known about it, from the critics:

- The roadside is code-drawn props: two boards, four barrels and a cone against
  a reference that fills both verges edge to edge. A critic named this and the
  sky as the two largest remaining gaps to the bar.
- `ui/parts/SunsetSky.qml` is shared by the race view, the garage and the
  countdown, has no owner, and every piece so far has declined to take it. Two
  builders have named it as the largest single gap in the picture. It needs one
  owner and probably its own piece.
- The far road has no surface past z ~ 20 was fixed, but the road at z >= 14 is
  still not resolvable at the 480x270 internal buffer.
- The circuit's twelve sectors have landmarks, but the minimap outline is a
  schematic rather than a projection of the sector table, so the two disagree.

This is a piece-4 re-run with an art brief, not a defect list.

### 3.2 The power-ups need much cooler animations

Today a card landing is a callout and a gauge change. The design's motion
section asks for more than currently exists — a road lurch on Turbo, a horizon
pull-back on being hit, and 1.6 s callouts — and the eight cards have no
distinct visual identity in play beyond their name in the hand panel.

Note the constraints this has to live inside, none of which the design changes:

- reduced motion must remove all shake, lurch and streak lines and keep
  position changes as cuts;
- nothing may flash faster than 3 Hz;
- the fact stays the largest thing on screen at every moment, and nothing may
  cross the answer field;
- a wrong answer must never be punished with motion — the design's second
  pillar is that mistakes cost the streak and nothing else.

Neither of these is a bug. Both are art and motion direction, and both should
be briefed as their own pieces with their own bars rather than folded into a
defect round.

## 4. The Pile-Up's photosensitivity margin — RESOLVED 2026-09-05: option 1, telegraph 900 ms

**Decision (maintainer, 2026-09-05):** lengthen the telegraph to 900 ms with the two amber swings at 0 and 450 ms and the impact flash at 900, so no two whole-frame changes fall within 333 ms of each other. Applied in `docs/design.md` (Pile-Up, v4.1). The rest of this section is the record of how it was found.

Raised 2026-09-05 by piece F round 3, which measured it rather than asserting
it, and flagged it instead of acting because the remedy is a design number and
build agents may not change the design.

The design gives the Pile-Up a 600 ms telegraph in which "the sky flashes amber
twice", then an impact flash. Measured on the shipped frames, whole-frame mean
luma, Rec.601 on 8-bit sRGB as stored:

- three crossings of a tint a child would notice inside **580 ms**;
- two of the three are amber **hue** swings that move whole-frame luma by about
  8 %, which is not a luminance flash on any reading of the standard I know;
- the third is a real **2.19×** whole-frame flash at +660 ms (round 2's was
  1.17×, and round 3 raised it deliberately, because two critics in a row said
  the legendary card was the quietest thing in the game).

So the letter of the rule — "nothing flashes faster than 3 Hz" — is met on the
luminance reading, and three noticeable changes in 580 ms is nevertheless
exactly the shape of the pattern the rule exists to prevent. The margin is not
comfortable and this is a game for six-year-olds.

Three ways out, all of them one number, none of them a builder's to pick:

1. **Lengthen the Pile-Up's telegraph** from 600 ms, which separates the two
   amber swings from the impact flash.
2. **Drop one of the two sky flashes**, keeping the telegraph as it is.
3. **Accept it as measured**, on the grounds that two of the three are hue and
   not luminance.

Whichever is chosen belongs in `docs/design.md` as an amendment, so the piece F
critic can judge against it rather than around it.

### 4.1 Confirmed independently, and the design contradicts itself

A second blind critic, judging round 3 against round 2 without seeing the first
verdict or this file, reached the same place from its own measurements and added
the finding that matters most:

**The design's own instruction breaks the design's own rule.** "The sky flashes
amber twice" inside a 600 ms telegraph is **3.33 Hz**, and the accessibility
section says nothing may flash faster than 3 Hz. Two independent builders each
noticed and each quietly stretched the spacing to 360 ms — **2.78 Hz, under the
limit with no margin at all** — across about 44 % of the screen. Neither was
asked to; both were right; neither could say so in the document, because build
agents may not change the design.

The critic also measured the impact flash on its own terms: the whole screen
goes **74 → 162 → 100 → 76 luma inside 180 ms**, a full-screen near-doubling,
and its verdict was that it would not ship that to a six-year-old without a
designer watching it on a real panel. That is a stronger statement than §4's,
made blind, and it should be treated as the operative one.

**And it survives reduced motion at +77 %** (round 2's was +16 %). That is
backwards: the setting most likely to be switched on by a photosensitive child
is the one keeping most of the flash. Whatever is decided above, reduced motion
should cap flash amplitude and not only remove shake and spin — and that is a
defect the loop can fix without a design change, so it is going into piece F
round 4 rather than waiting for this decision.

## 5. Maintainer feedback after the second play session, 2026-09-05

Don played the build at `7084222`, piece F round 6 in progress, in the VM as the
real plugin. His agent then drove every screen and the five card moments through
the harness at 1080p (`--warmup`, `--inject`, 80 ms strips) to find causes. The
design is amended to v4.1 and the plan to v3.1 for the items below; the rest are
piece F rubric additions. In the maintainer's own words the two headline
findings were: *clicking things did not do much*, and *launching a power up
feels weird, I had to attempt to trigger it multiple times*.

### 5.1 The mouse does nothing, and it is the game, not the VM

No screen under `ui/` has a `MouseArea`, `TapHandler` or `HoverHandler`. The
only click areas in the plugin are the overlay's scrim (dismiss) and the bar
button. The design said "every screen operates with the keyboard alone", which
was read as keyboard-only. It now says keyboard first, mouse always
(design v4.1, Accessibility), and the plan carries it as piece **M Mouse**.

### 5.2 The hand is unreliable to fire, and the cause is the design's own key choice

`1`, `2` and `3` are both card keys and digits. The build handled the collision
honestly and at length: the same press is also a digit, so the digit is parked
in the answer field; Enter spends the card only if the field is empty, otherwise
Enter is the answer; on the 23 single-digit facts the digit is deferred and
Backspace means "it was a card"; mid-answer, the keys are digits and no card can
be chosen at all. Four rounds went into printing those rules on the panel. From
the keyboard it reads as a card that sometimes fires and sometimes does not.

The fix is not more explanation. Design v4.1 removes digits from the hand
entirely: Left and Right move a highlight across the three cards, Up and Down
change a targeted card's rival, **Space fires**, Enter is only ever the answer,
Escape only ever leaves. Nothing is parked or deferred. The piece F rubric gains
a strip that types `1` on `2 × 3` while a hand is held and must get a wrong
answer and no card. The parked-digit machinery in `ui/Race.qml` and the deferred
sentences in `ui/Picker.qml` come out with it.

### 5.3 The race screen explains itself in text where the child is reading a fact

Judged from the warmed race and the strips, in priority order. All are piece F.

1. **The answer box does not say it is the answer.** The fact is huge and the
   input is a dark rectangle floating below it with no equals sign. Design
   v4.1: one line, `7 × 8 = ▮`, the caret blinking.
2. **Callouts stack over the road.** After one hit there were four boxes in the
   child's eye line: `ENGINE HIT · 3s`, `WRENCH ◂ BOLT`, `PISTON SLIPPED PAST`,
   `GASKET SLIPPED PAST`. Design v4.1: one slot under the fact line, newest
   replaces oldest; a rival passing is a tag on its kart and a minimap pulse,
   not a sentence.
3. **The stall is a banner, not the field.** The design's bolts overlay belongs
   on the answer line itself.
4. **Rival names on billboards at the horizon** (`PISTON`, `GASKET`, `BOLT` on
   sign boards) read as places. Rivals are identified by their kart tags;
   retire the name boards. The kit's banners replace them in piece T.
5. **Being hit is weaker than hitting.** The pothole strip shows the lamp row
   grow and the sky flash, but no dip of the child's kart and no pothole on the
   road, and 800 ms of near-identical frames. The wrench lands with a `+5` and a
   ring but no sparks, no jolt, no smoke on the victim. Impact is a tag; the
   design asks for telegraph, impact, aftermath.
6. **A billboard fades in and out** while a projectile flies past it, because
   the near-prop dimming rule fires on the whole board. Dim only what overlaps
   the fact line.
7. **`H  PIT CREW`** bottom-left is cryptic. Key caps, as the garage draws them:
   `[H] PIT CREW · shows the answer`.

What is working and must not regress: the Turbo (flash beat, speed lines, road
stretch, afterimages, the lap rolling over with two PASSED callouts), the hand
deal (charge flare, three cards sliding in, tier colours, "using one spends all
three"), the Tow Hook (line latches, TOWED, the rival slides back past you), the
HUD, the lamp row growing hollow lamps on a hit.

### 5.4 Words a child will misread

- `OFFLINE` in the garage's corner reads as broken; the rail already says
  THIS COMPUTER ONLY. Drop the badge.
- `MIDNIGHT GARAGE` for a sunset track. `GOLDEN HOUR`, or `THE PIT`.
- `PIT CREW 4` on results means nothing to a child: `ANSWERS SHOWN 4`.
- `BEST STREAK` on results is `BEST COMBO` (design, and the hub's stance).
- The `POWER-UPS` line on results is a wall of names that wraps. Icons, or
  "8 cards played".

### 5.5 Small

- Results cut from golden hour to near-black. The chrome-stays-native rule is
  right; a thin sunset band behind the headline would keep it the same game.
- The countdown's gantry and the race's grid floor are the Canvas versions;
  the kit's gantry and the terrain arrive with piece T and are not counted here.

### 5.6 Open item 4 (the Pile-Up's flashes) is resolved

The maintainer chose option 1 on 2026-09-05: telegraph 900 ms, swings at 0 and
450, impact at 900. Applied in the design; item 4 above records the decision.
