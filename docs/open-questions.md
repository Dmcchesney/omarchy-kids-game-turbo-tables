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

## 4. The Pile-Up's photosensitivity margin — a decision only the maintainer can make

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
