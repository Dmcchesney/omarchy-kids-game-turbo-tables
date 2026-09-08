// Design section: "Laps, decks, presets".

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { QUESTIONS_PER_LAP, extraQuestions, factAnswer, factLabel, factLeft, factRight, lapDeck, packFact, questionCountForPreset, tableFacts, tableName, tablesForPreset } = E;
    const { answerRight, apply, racer, startRace } = helpersFor(E);

    test("decks: a fact packs and unpacks to its own multiplication", () => {
      const fact = packFact(7, 8);
      assert.equal(factLeft(fact), 7);
      assert.equal(factRight(fact), 8);
      assert.equal(factAnswer(fact), 56);
      assert.equal(factLabel(fact), "7 × 8");
    });

    test("decks: a lap is one table, n x 1 through n x 12", () => {
      const facts = tableFacts(7);
      assert.equal(facts.length, QUESTIONS_PER_LAP);
      assert.deepEqual(
        facts.map((fact) => factRight(fact)),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      );
      assert.ok(facts.every((fact) => factLeft(fact) === 7));
    });

    test("decks: the 2-5 preset is four laps and 48 questions", () => {
      assert.deepEqual(tablesForPreset("2-5"), [2, 3, 4, 5]);
      assert.equal(questionCountForPreset("2-5"), 48);
    });

    test("decks: the 2-10 preset is nine laps and 108 questions", () => {
      assert.deepEqual(tablesForPreset("2-10"), [2, 3, 4, 5, 6, 7, 8, 9, 10]);
      assert.equal(questionCountForPreset("2-10"), 108);
    });

    test("decks: the 1-12 Grand Prix is twelve laps and 144 questions", () => {
      assert.deepEqual(tablesForPreset("1-12"), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      assert.equal(questionCountForPreset("1-12"), 144);
    });

    test("decks: choose tables takes any subset, in ascending order, deduplicated", () => {
      assert.deepEqual(tablesForPreset("choose", [9, 3, 12, 3]), [3, 9, 12]);
      assert.deepEqual(tablesForPreset("choose", [0, 13, 6]), [6]);
      assert.equal(questionCountForPreset("choose", [9, 3, 12]), 36);
    });

    test("decks: each lap holds its table exactly once, shuffled by the seed", () => {
      const deck = lapDeck(2026, 6, 7);
      assert.equal(deck.length, QUESTIONS_PER_LAP);
      assert.deepEqual(
        deck.slice().sort((left, right) => left - right),
        tableFacts(7),
      );
      assert.notDeepEqual(deck, tableFacts(7));
    });

    test("decks: deck generation is deterministic from the seed", () => {
      assert.deepEqual(lapDeck(42, 3, 4), lapDeck(42, 3, 4));
      assert.notDeepEqual(lapDeck(42, 3, 4), lapDeck(43, 3, 4));
    });

    test("decks: lap seven of the Grand Prix is the sevens", () => {
      const harness = startRace({ preset: "1-12" });
      const you = racer(harness, "you");
      for (let lap = 0; lap < 6; lap++) {
        for (let question = 0; question < QUESTIONS_PER_LAP; question++) answerRight(harness);
      }
      assert.equal(racer(harness, "you").lapsComplete, 6);
      assert.equal(factLeft(racer(harness, "you").currentFact), 7);
      assert.equal(tableName(7), "THE SEVENS");
      assert.equal(you.lapsComplete, 0, "the first snapshot is not aliased by later steps");
    });

    test("decks: a lap serves its twelve facts once before any extra is drawn", () => {
      const harness = startRace({ preset: "2-5" });
      const seen: number[] = [];
      for (let index = 0; index < QUESTIONS_PER_LAP; index++) {
        seen.push(racer(harness, "you").currentFact);
        answerRight(harness);
      }
      assert.deepEqual(
        seen.slice().sort((left, right) => left - right),
        tableFacts(2),
      );
    });

    test("decks: extra questions come from missed facts first, then the lap's table", () => {
      const missed = [packFact(2, 9), packFact(2, 4)];
      const extras = extraQuestions(2026, "you", 0, 1, 2, missed);
      assert.deepEqual(
        extras.slice(0, 2).sort((left, right) => left - right),
        [packFact(2, 4), packFact(2, 9)],
      );
      assert.deepEqual(
        extras.slice(2).sort((left, right) => left - right),
        tableFacts(2),
      );
    });

    test("decks: extra questions are deterministic from the seed", () => {
      const missed = [packFact(3, 7)];
      assert.deepEqual(
        extraQuestions(7, "bolt", 2, 1, 3, missed),
        extraQuestions(7, "bolt", 2, 1, 3, missed),
      );
      assert.notDeepEqual(
        extraQuestions(7, "bolt", 2, 1, 3, missed),
        extraQuestions(7, "bolt", 2, 2, 3, missed),
      );
    });

    test("decks: an inflated lap keeps asking questions past its twelve facts", () => {
      const harness = startRace({ preset: "2-5", powerupsEnabled: true });
      racer(harness, "you").hand = ["pileUp"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      const bolt = racer(harness, "bolt");
      assert.equal(bolt.questionsNeededThisLap, 27);
      for (let index = 0; index < 26; index++) {
        assert.ok(racer(harness, "bolt").currentFact > 0, "ran out of questions at " + index);
        // The first answer waits out the Pile-Up's two-second stall.
        answerRight(harness, "bolt", index === 0 ? 3000 : 1000);
      }
      assert.equal(racer(harness, "bolt").lapsComplete, 0);
      answerRight(harness, "bolt");
      assert.equal(racer(harness, "bolt").lapsComplete, 1);
    });

    test("decks: every racer answers the same lap deck from the same seed", () => {
      const harness = startRace({ preset: "2-5" });
      const facts = harness.state.racers.map((entry) => entry.currentFact);
      assert.equal(new Set(facts).size, 1);
    });
  });
}
