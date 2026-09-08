// Design section: "Laps, decks, presets" -- "Fact history is kept locally per
// fact: attempts, correct, last three outcomes. It drives the mastery lamps in
// the garage and the order of pit-lane re-asks", and "Deck generation is
// deterministic from the seed and the fact history."
//
// The engine owns the record and the two orderings it drives. It does not own
// storage: `RaceConfig.factHistory` is the load seam and `factHistoryOf` is the
// save seam, and Piece 2's save.ts is what fills them.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import type { FactRecord } from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const {
      FACT_HISTORY_WINDOW,
      compareByFactHistory,
      createRace,
      extraQuestions,
      factHistoryEntry,
      factHistoryOf,
      factRecordOf,
      orderByFactHistory,
      packFact,
      recentSuccesses,
      recordFactOutcome,
    } = E;
    const { answerRight, answerWrong, apply, racer, startRace } = helpersFor(E);

    function record(fact: number, attempts: number, correct: number, lastThree: string[]): FactRecord {
      return { fact, attempts, correct, lastThree: lastThree.slice() as FactRecord["lastThree"] };
    }

    test("fact history: a fact carries attempts, correct and its last three outcomes", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      const afterWrong = factHistoryEntry(racer(harness, "you"), fact)!;
      assert.deepEqual(afterWrong, { fact, attempts: 1, correct: 0, lastThree: ["wrong"] });
      answerRight(harness);
      const afterRight = factHistoryEntry(racer(harness, "you"), fact)!;
      assert.deepEqual(afterRight, {
        fact,
        attempts: 2,
        correct: 1,
        lastThree: ["wrong", "correct"],
      });
    });

    test("fact history: a reveal and a pit-crew answer are attempts but never correct", () => {
      const revealed = startRace();
      const revealedFact = racer(revealed, "you").currentFact;
      answerWrong(revealed);
      answerWrong(revealed);
      assert.deepEqual(factHistoryEntry(racer(revealed, "you"), revealedFact), {
        fact: revealedFact,
        attempts: 2,
        correct: 0,
        lastThree: ["wrong", "reveal"],
      });

      const helped = startRace();
      const helpedFact = racer(helped, "you").currentFact;
      apply(helped, { kind: "hint", racerId: "you" });
      assert.deepEqual(factHistoryEntry(racer(helped, "you"), helpedFact), {
        fact: helpedFact,
        attempts: 1,
        correct: 0,
        lastThree: ["pitCrew"],
      });
    });

    test("fact history: only the last three outcomes are kept", () => {
      assert.equal(FACT_HISTORY_WINDOW, 3);
      const history: FactRecord[] = [];
      const fact = packFact(7, 8);
      for (const outcome of ["wrong", "correct", "wrong", "correct", "pitCrew"] as const) {
        recordFactOutcome(history, fact, outcome);
      }
      const kept = factRecordOf(history, fact)!;
      assert.equal(kept.attempts, 5);
      assert.equal(kept.correct, 2);
      assert.deepEqual(kept.lastThree, ["wrong", "correct", "pitCrew"]);
      assert.equal(recentSuccesses(kept), 1);
    });

    test("fact history: the record list stays ascending by fact whatever order the race asked in", () => {
      const history: FactRecord[] = [];
      recordFactOutcome(history, packFact(7, 9), "correct");
      recordFactOutcome(history, packFact(7, 2), "wrong");
      recordFactOutcome(history, packFact(7, 5), "correct");
      assert.deepEqual(
        history.map((entry) => entry.fact),
        [packFact(7, 2), packFact(7, 5), packFact(7, 9)],
      );
    });

    test("fact history: weakest first is fewer recent successes, then a lower ratio, then more attempts", () => {
      const shaky = packFact(7, 8);
      const solid = packFact(7, 4);
      const byRecent = [
        record(shaky, 6, 3, ["wrong", "correct", "wrong"]),
        record(solid, 6, 3, ["correct", "correct", "correct"]),
      ];
      assert.ok(compareByFactHistory(byRecent, shaky, solid) < 0, "fewer recent successes first");

      const byRatio = [
        record(shaky, 10, 2, ["correct", "wrong", "wrong"]),
        record(solid, 10, 9, ["correct", "wrong", "wrong"]),
      ];
      assert.ok(compareByFactHistory(byRatio, shaky, solid) < 0, "then the lower ratio first");

      const byAttempts = [
        record(shaky, 9, 3, ["correct", "wrong", "wrong"]),
        record(solid, 3, 1, ["correct", "wrong", "wrong"]),
      ];
      assert.ok(compareByFactHistory(byAttempts, shaky, solid) < 0, "then the fact fought for longer");

      // A partial order on purpose: two facts the history cannot tell apart
      // compare equal, and each caller supplies its own final tiebreak, so
      // nothing depends on Array.prototype.sort being stable.
      assert.equal(compareByFactHistory([], shaky, shaky), 0);
      assert.equal(compareByFactHistory([], solid, shaky), 0);
    });

    test("fact history: it drives the order of pit-lane re-asks, weakest fact first", () => {
      // The same two facts, the same pit lane, the same due answer -- twice, with
      // the history reversed between the runs. Every other rule `pickPitLaneEntry`
      // knows is blind to that reversal: insertion order always names the fact
      // missed first, and the numeric tiebreak always names the lower fact number.
      // So each of those, on its own, returns the SAME entry in both runs and
      // fails one of them. Only the history can answer differently twice, and
      // only a comparator that reads it gets both right.
      //
      // That is the whole point: the earlier version of this test fixed the weak
      // fact once, and replacing `compareByFactHistory(...)` with `0` left it
      // green, because the fall-through to the lower fact number happened to pick
      // the same entry.
      const served: number[] = [];
      for (const weakIsSecond of [true, false]) {
        const harness = startRace();
        const first = racer(harness, "you").currentFact;
        answerWrong(harness);
        answerWrong(harness);
        const second = racer(harness, "you").currentFact;
        answerWrong(harness);
        answerWrong(harness);

        const you = racer(harness, "you");
        assert.deepEqual(
          you.pitLane.map((entry) => entry.fact),
          [first, second],
          "the pit lane holds both, in the order they were missed",
        );
        assert.notEqual(first, second);

        // Make both due on the same answer, so nothing but the history can decide.
        for (const entry of you.pitLane) entry.dueAtAnswer = you.answersThisLap;
        const weak = weakIsSecond ? second : first;
        const strong = weakIsSecond ? first : second;
        you.factHistory = [
          record(strong, 8, 8, ["correct", "correct", "correct"]),
          record(weak, 8, 0, ["wrong", "wrong", "wrong"]),
        ];

        // One more answer, and the fact that comes back is the weak one.
        answerRight(harness);
        const asked = racer(harness, "you");
        assert.equal(asked.currentFromPitLane, true);
        assert.equal(
          asked.currentFact,
          weak,
          weakIsSecond
            ? "the weak fact is the one missed second, against insertion order"
            : "and with the history reversed the answer reverses with it",
        );
        assert.notEqual(asked.currentFact, strong);
        served.push(asked.currentFact);
      }
      assert.notEqual(
        served[0],
        served[1],
        "the two runs must serve different facts, or the history decided nothing",
      );
    });

    test("fact history: it drives the missed half of an extra-question draw, weakest first", () => {
      const shaky = packFact(2, 7);
      const solid = packFact(2, 3);
      const missed = [solid, shaky];
      const seedOnly = extraQuestions(2026, "you", 0, 1, 2, missed);
      const weakFirst = extraQuestions(2026, "you", 0, 1, 2, missed, [
        record(solid, 6, 6, ["correct", "correct", "correct"]),
        record(shaky, 6, 0, ["wrong", "wrong", "wrong"]),
      ]);
      assert.deepEqual(seedOnly.slice(0, 2).slice().sort(), [solid, shaky].slice().sort());
      assert.deepEqual(weakFirst.slice(0, 2), [shaky, solid], "the weaker missed fact comes back first");
      assert.deepEqual(
        weakFirst.slice(2),
        seedOnly.slice(2),
        "the lap's own table stays purely seeded",
      );
    });

    test("decks: deck generation is deterministic from the seed and the fact history", () => {
      const missed = [packFact(2, 3), packFact(2, 7), packFact(2, 11)];
      const history = [
        record(packFact(2, 3), 4, 4, ["correct", "correct", "correct"]),
        record(packFact(2, 7), 4, 1, ["wrong", "correct", "wrong"]),
        record(packFact(2, 11), 4, 0, ["wrong", "wrong", "wrong"]),
      ];
      const once = extraQuestions(7, "you", 0, 1, 2, missed, history);
      const twice = extraQuestions(7, "you", 0, 1, 2, missed, history);
      assert.deepEqual(once, twice, "same seed and same history is the same draw");
      const other = extraQuestions(7, "you", 0, 1, 2, missed, []);
      assert.notDeepEqual(once.slice(0, 3), other.slice(0, 3), "a different history is a different draw");
      const otherSeed = extraQuestions(8, "you", 0, 1, 2, missed, history);
      assert.notDeepEqual(once, otherSeed, "a different seed is a different draw");
    });

    test("fact history: orderByFactHistory keeps the seeded order as its last tiebreak", () => {
      const facts = [packFact(3, 4), packFact(3, 9), packFact(3, 1)];
      assert.deepEqual(orderByFactHistory(facts, []), facts, "no history changes nothing");
    });

    test("fact history: the load and save seam round-trips, and the engine never stores anything", () => {
      const carried: FactRecord[] = [
        record(packFact(1, 7), 9, 2, ["wrong", "correct", "wrong"]),
        record(packFact(1, 9), 9, 9, ["correct", "correct", "correct"]),
      ];
      const state = createRace({
        seed: 2026,
        preset: "1-12",
        racers: [
          { id: "you", kind: "human" },
          { id: "bolt", kind: "rival" },
        ],
        factHistory: carried,
      });
      assert.deepEqual(factHistoryOf(state), carried, "what goes in comes back out");
      assert.deepEqual(
        state.racers.find((entry) => entry.id === "bolt")!.factHistory,
        [],
        "a rival starts with no history of its own",
      );
      // The seam hands back a copy, so a caller cannot reach into a live race.
      factHistoryOf(state)[0]!.attempts = 999;
      assert.equal(factHistoryOf(state)[0]!.attempts, 9);
      // And a race created without the seam is exactly the race it always was.
      const fresh = createRace({
        seed: 2026,
        preset: "1-12",
        racers: [{ id: "you", kind: "human" }],
      });
      assert.deepEqual(factHistoryOf(fresh), []);
    });
  });
}
