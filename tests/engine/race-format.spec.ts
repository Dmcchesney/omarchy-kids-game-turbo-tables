// Design section: "Race format and results" -- start, finish, and the numbers
// on the results screen.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { SETTLE_MS, accuracyPercent, createRace, headlineForPlace, rankRacers, step } = E;
    const { answerRight, answerRightTimes, answerWrong, apply, eventsOfType, racer, startRace } = helpersFor(E);

    test("format: a race starts in the countdown and nothing can be answered yet", () => {
      const created = createRace({ seed: 1, preset: "2-5", racers: [{ id: "you", kind: "human" }] });
      assert.equal(created.status, "countdown");
      const blocked = step(created, { kind: "answer", value: 4 }, 100);
      assert.deepEqual(blocked.events, []);
      assert.equal(blocked.state.racers[0]!.attemptCount, 0);
      const started = step(created, { kind: "start" }, 500);
      assert.equal(started.state.status, "racing");
      assert.equal(started.state.startedAtMs, 500);
    });

    test("format: the finish line is the last correct answer of the last lap", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 47; index++) answerRight(harness);
      assert.equal(racer(harness, "you").finished, false);
      const events = answerRight(harness);
      const finished = eventsOfType(events, "finished");
      assert.equal(finished.length, 1);
      assert.equal(finished[0]!.racerId, "you");
      assert.equal(racer(harness, "you").lapsComplete, 4);
    });

    test("format: in a Grand Prix the rivals keep racing for up to fifteen seconds", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "you");
      assert.equal(harness.state.status, "settling");
      assert.equal(harness.state.settleUntilMs, harness.now + SETTLE_MS);
      assert.equal(SETTLE_MS, 15000);
      apply(harness, { kind: "tick" }, SETTLE_MS - 1);
      assert.equal(harness.state.status, "settling");
      answerRight(harness, "bolt", 1);
      assert.equal(racer(harness, "bolt").correctCount, 1, "a rival can still answer while settling");
      apply(harness, { kind: "tick" }, 1);
      assert.equal(harness.state.status, "finished");
    });

    test("format: settling ends early when every racer has finished", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "you");
      assert.equal(harness.state.status, "settling");
      for (const id of ["bolt", "piston", "gasket"]) answerRightTimes(harness, 12, id);
      assert.equal(harness.state.status, "finished");
    });

    test("format: in Time trial and Ghost the race ends at the finish line, rival or no rival", () => {
      // The second racer is the point of this test, not decoration. The Modes
      // table gives Ghost a rival ("your previous best"), so the shipping Ghost
      // race is two karts; with one racer `allFinished` is true the instant the
      // child crosses and `advanceStatus` never reaches the mode check at all,
      // which is how a deleted `mode === "grandPrix"` guard used to leave the
      // whole suite green. Here the second racer is still on lap zero when the
      // human finishes, so only the mode can decide between finished and
      // settling.
      for (const mode of ["timeTrial", "ghost"] as const) {
        const withRival = startRace({
          mode,
          preset: "choose",
          chosenTables: [2],
          racers: [
            { id: "you", kind: "human" },
            { id: "ghost", kind: "rival" },
          ],
        });
        answerRightTimes(withRival, 12);
        assert.equal(racer(withRival, "you").finished, true, mode);
        assert.equal(racer(withRival, "ghost").finished, false, mode + ": the rival has not finished");
        assert.ok(withRival.state.settleMs > 0, mode + ": settling is configured, and still not used");
        assert.equal(withRival.state.status, "finished", mode);
        assert.equal(withRival.state.settleUntilMs, 0, mode);

        const solo = startRace({
          mode,
          preset: "choose",
          chosenTables: [2],
          racers: [{ id: "you", kind: "human" }],
        });
        answerRightTimes(solo, 12);
        assert.equal(solo.state.status, "finished", mode + " solo");
        assert.equal(solo.state.settleUntilMs, 0, mode + " solo");
      }
    });

    test("format: a finished race accepts no further answers", () => {
      const harness = startRace({
        mode: "timeTrial",
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" }],
      });
      answerRightTimes(harness, 12);
      const events = answerRight(harness);
      assert.deepEqual(events, []);
    });

    test("format: places are handed out in finishing order", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "piston");
      answerRightTimes(harness, 12, "you");
      answerRightTimes(harness, 12, "bolt");
      assert.equal(racer(harness, "piston").place, 1);
      assert.equal(racer(harness, "you").place, 2);
      assert.equal(racer(harness, "bolt").place, 3);
      const ranked = rankRacers(harness.state.racers);
      assert.deepEqual(
        ranked.map((entry) => entry.id),
        ["piston", "you", "bolt", "gasket"],
      );
      assert.equal(headlineForPlace(2), "PODIUM FINISH");
    });

    test("format: the results counters are kept apart", () => {
      const harness = startRace({ preset: "2-5" });
      answerRightTimes(harness, 3);
      answerWrong(harness);
      answerRight(harness);
      answerWrong(harness);
      answerWrong(harness);
      apply(harness, { kind: "hint" });
      const you = racer(harness, "you");
      assert.equal(you.correctCount, 4);
      assert.equal(you.wrongCount, 3);
      assert.equal(you.revealCount, 1);
      assert.equal(you.pitCrewCount, 1);
      assert.equal(you.attemptCount, 8);
      assert.equal(you.correctInLap, 6, "reveal and pit crew both count for progress");
      assert.equal(accuracyPercent(you), 50);
    });

    test("format: a race with no attempts reports zero accuracy rather than a division by zero", () => {
      const harness = startRace();
      assert.equal(accuracyPercent(racer(harness, "you")), 0);
    });

    test("format: the accuracy on the results screen is rounded, not truncated", () => {
      // 2 of 3 is 66.66...; rounded that prints 67 and truncated it prints 66.
      // Every other accuracy the suite computes is a whole number, so `Math.round`
      // and `Math.floor` were indistinguishable in the bundle until this line.
      const harness = startRace({ preset: "2-5" });
      answerRight(harness); // one correct
      answerWrong(harness); // one wrong: the same fact stays, no reveal yet
      answerRight(harness); // and the retry lands: 2 correct of 3 attempts
      const you = racer(harness, "you");
      assert.equal(you.correctCount, 2);
      assert.equal(you.attemptCount, 3);
      assert.equal(accuracyPercent(you), 67, "2 of 3 rounds up to 67, it does not truncate to 66");

      // Rounding down where rounding down is right, so this pins rounding and
      // not merely "always add one".
      assert.equal(accuracyPercent({ ...you, correctCount: 1, attemptCount: 3 }), 33);
      assert.equal(accuracyPercent({ ...you, correctCount: 5, attemptCount: 6 }), 83);
    });
  });
}
