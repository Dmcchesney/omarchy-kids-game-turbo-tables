// Design section: "Race format and results" -- the ranking rule and the
// headline rule.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import type { Rankable } from "../../src/engine/index.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { compareRacers, headlineForPlace, ordinal, placeOf, positionOrder, rankRacers } = E;

    function makeRacer(id: string, seat: number, overrides: Partial<Rankable> = {}): Rankable {
      return {
        id,
        seat,
        lapsComplete: 0,
        correctInLap: 0,
        questionsNeededThisLap: 12,
        finished: false,
        finishTimeMs: 0,
        correctCount: 0,
        pitCrewCount: 0,
        ...overrides,
      };
    }

    test("rank: finished comes before unfinished", () => {
      const done = makeRacer("done", 1, { finished: true, finishTimeMs: 99999, lapsComplete: 12 });
      const leading = makeRacer("leading", 0, { lapsComplete: 11, correctInLap: 11 });
      assert.deepEqual(positionOrder([leading, done]), ["done", "leading"]);
    });

    test("rank: among finished, the earlier finish time wins", () => {
      const early = makeRacer("early", 1, { finished: true, finishTimeMs: 1000 });
      const late = makeRacer("late", 0, { finished: true, finishTimeMs: 2000 });
      assert.deepEqual(positionOrder([late, early]), ["early", "late"]);
    });

    test("rank: among unfinished, higher effective progress wins", () => {
      const ahead = makeRacer("ahead", 1, { lapsComplete: 3, correctInLap: 4 });
      const shoved = makeRacer("shoved", 0, { lapsComplete: 3, correctInLap: 4, questionsNeededThisLap: 27 });
      assert.deepEqual(positionOrder([shoved, ahead]), ["ahead", "shoved"]);
    });

    test("rank: the next tiebreak is the correct-answer count", () => {
      const many = makeRacer("many", 1, { correctCount: 30 });
      const few = makeRacer("few", 0, { correctCount: 10 });
      assert.deepEqual(positionOrder([few, many]), ["many", "few"]);
    });

    test("rank: the last tiebreak is fewer pit-crew answers", () => {
      const clean = makeRacer("clean", 1, { correctCount: 30, pitCrewCount: 0 });
      const helped = makeRacer("helped", 0, { correctCount: 30, pitCrewCount: 4 });
      assert.deepEqual(positionOrder([helped, clean]), ["clean", "helped"]);
    });

    test("rank: identical racers tie deterministically by seat", () => {
      const left = makeRacer("left", 0);
      const right = makeRacer("right", 1);
      assert.deepEqual(positionOrder([right, left]), ["left", "right"]);
      assert.deepEqual(positionOrder([left, right]), ["left", "right"]);
      assert.equal(compareRacers(left, left), 0);
    });

    test("rank: places are numbered from one and carry the finishing detail", () => {
      const racers = [
        makeRacer("you", 0, { finished: true, finishTimeMs: 5000, correctCount: 144 }),
        makeRacer("bolt", 1, { finished: true, finishTimeMs: 4000, correctCount: 144 }),
        makeRacer("piston", 2, { lapsComplete: 11, correctCount: 132 }),
      ];
      const ranked = rankRacers(racers);
      assert.deepEqual(
        ranked.map((entry) => [entry.id, entry.place]),
        [
          ["bolt", 1],
          ["you", 2],
          ["piston", 3],
        ],
      );
      assert.equal(ranked[2]!.effectiveProgress, 132);
      assert.equal(placeOf(racers, "you"), 2);
      assert.equal(placeOf(racers, "nobody"), 0);
    });

    test("rank: every finish is positive", () => {
      assert.equal(headlineForPlace(1), "VICTORY LAP");
      assert.equal(headlineForPlace(2), "PODIUM FINISH");
      assert.equal(headlineForPlace(3), "PODIUM FINISH");
      assert.equal(headlineForPlace(4), "RACE COMPLETE");
      assert.equal(headlineForPlace(9), "RACE COMPLETE");
    });

    test("rank: ordinals read the way the results screen prints them", () => {
      assert.equal(ordinal(1), "1st");
      assert.equal(ordinal(2), "2nd");
      assert.equal(ordinal(3), "3rd");
      assert.equal(ordinal(4), "4th");
      assert.equal(ordinal(11), "11th");
      assert.equal(ordinal(12), "12th");
      assert.equal(ordinal(21), "21st");
    });
  });
}
