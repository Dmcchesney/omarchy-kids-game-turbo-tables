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
