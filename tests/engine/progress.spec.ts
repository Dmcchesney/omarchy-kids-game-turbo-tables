// Design section: "Powerups", last bullet -- "Position is effective progress".

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { effectiveProgress, positionTriple, progressFraction, raceLength, swapPositions } = E;
    const { answerRight, answerRightTimes, apply, racer, startRace } = helpersFor(E);

    test("progress: it is laps x 12, plus correct this lap, minus the excess requirement", () => {
      assert.equal(effectiveProgress({ lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 12 }), 0);
      assert.equal(effectiveProgress({ lapsComplete: 3, correctInLap: 5, questionsNeededThisLap: 12 }), 41);
      assert.equal(
        effectiveProgress({ lapsComplete: 3, correctInLap: 5, questionsNeededThisLap: 27 }),
        41 - 15,
      );
      assert.equal(
        effectiveProgress({ lapsComplete: 3, correctInLap: 5, questionsNeededThisLap: 2 }),
        41 + 10,
        "a boost pushes it forward by the same arithmetic",
      );
    });

    test("progress: an unset requirement falls back to twelve", () => {
      assert.equal(effectiveProgress({ lapsComplete: 1, correctInLap: 4, questionsNeededThisLap: 0 }), 16);
    });

    test("progress: a Pile-Up moves a racer back fifteen the instant it lands", () => {
      const harness = startRace();
      answerRightTimes(harness, 6, "bolt");
      const before = racer(harness, "bolt");
      assert.equal(effectiveProgress(before), 6);
      racer(harness, "you").hand = ["pileUp"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(effectiveProgress(racer(harness, "bolt")), -9, "6 - 15");
    });

    test("progress: the kart creeps forward again as the victim answers", () => {
      const harness = startRace();
      answerRightTimes(harness, 6, "bolt");
      racer(harness, "you").hand = ["pileUp"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      let last = effectiveProgress(racer(harness, "bolt"));
      for (let index = 0; index < 5; index++) {
        answerRight(harness, "bolt", index === 0 ? 3000 : 1000);
        const now = effectiveProgress(racer(harness, "bolt"));
        assert.equal(now, last + 1);
        last = now;
      }
    });

    test("progress: the kart never actually reverses when it answers", () => {
      const harness = startRace({ preset: "2-5" });
      let last = effectiveProgress(racer(harness, "you"));
      for (let index = 0; index < 40; index++) {
        answerRight(harness);
        const now = effectiveProgress(racer(harness, "you"));
        assert.ok(now >= last, "went backwards on an answer: " + last + " -> " + now);
        last = now;
      }
    });

    test("progress: the position triple is exactly the three numbers a Tow Hook swaps", () => {
      const left = { lapsComplete: 2, correctInLap: 3, questionsNeededThisLap: 20 };
      const right = { lapsComplete: 0, correctInLap: 1, questionsNeededThisLap: 12 };
      assert.deepEqual(positionTriple(left), { lapsComplete: 2, correctInLap: 3, questionsNeededThisLap: 20 });
      swapPositions(left, right);
      assert.deepEqual(left, { lapsComplete: 0, correctInLap: 1, questionsNeededThisLap: 12 });
      assert.deepEqual(right, { lapsComplete: 2, correctInLap: 3, questionsNeededThisLap: 20 });
    });

    test("progress: the race length is the whole preset, and the fraction is clamped", () => {
      assert.equal(raceLength(12), 144);
      assert.equal(raceLength(4), 48);
      const behind = { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 40 };
      assert.equal(progressFraction(behind, 4), 0, "a shoved kart clamps at the start line");
      const done = { lapsComplete: 4, correctInLap: 0, questionsNeededThisLap: 12 };
      assert.equal(progressFraction(done, 4), 1);
    });
  });
}
