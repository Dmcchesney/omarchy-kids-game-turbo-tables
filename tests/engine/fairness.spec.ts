// Design section: "Fairness" -- the guardrails written down so nobody removes
// one by accident. One test per bullet.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { CARDS, CARD_SCHEDULE, PODIUM_SIZE, effectiveProgress, placeOf, rankRacers, resultsBoard } = E;
    const { answerRight, answerRightTimes, answerWrong, apply, eventsOfType, position, racer, startRace } = helpersFor(E);

    test("fairness: a wrong answer costs only the streak", () => {
      const harness = startRace();
      answerRightTimes(harness, 4);
      const before = position(racer(harness, "you"));
      const events = answerWrong(harness);
      const you = racer(harness, "you");
      assert.equal(you.streak, 0);
      assert.deepEqual(position(you), before, "it never moves the kart back");
      assert.equal(you.questionsNeededThisLap, 12, "it never adds questions");
      assert.equal(you.stalledUntilMs, 0, "it never starts a timer");
      assert.deepEqual(
        events.map((event) => event.type),
        ["wrong"],
      );
    });

    test("fairness: attacks inflate one lap and die at its end", () => {
      const harness = startRace({ preset: "2-5" });
      racer(harness, "you").hand = ["pileUp"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 27);
      for (let index = 0; index < 27; index++) answerRight(harness, "bolt", index === 0 ? 3000 : 1000);
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 12);
    });

    test("fairness: magnitude is bounded by the lap, not by the attacker", () => {
      // Even four Pile-Ups on one lap cost exactly that lap; the next is a clean 12.
      const harness = startRace({ preset: "2-5" });
      for (let round = 0; round < 4; round++) {
        racer(harness, "you").hand = ["pileUp"];
        apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      }
      const needed = racer(harness, "bolt").questionsNeededThisLap;
      assert.equal(needed, 72);
      for (let index = 0; index < needed; index++) {
        answerRight(harness, "bolt", index === 0 ? 3000 : 1000);
      }
      assert.deepEqual(position(racer(harness, "bolt")), [1, 0, 12]);
    });

    test("fairness: a finished racer is out of reach and out of the fight", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "bolt");
      assert.equal(racer(harness, "bolt").finished, true);
      for (const card of CARD_SCHEDULE) {
        if (CARDS[card].scope !== "targeted") continue;
        racer(harness, "you").hand = [card];
        assert.deepEqual(
          apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" }),
          [],
          card + " reached a finished racer",
        );
      }
      racer(harness, "bolt").hand = ["pileUp"];
      assert.deepEqual(
        apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" }),
        [],
        "a finished racer attacked",
      );
    });

    test("fairness: pit crew is always available and always counts for progress", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 20; index++) {
        const before = racer(harness, "you").correctInLap + racer(harness, "you").lapsComplete * 12;
        apply(harness, { kind: "hint" });
        const after = racer(harness, "you").correctInLap + racer(harness, "you").lapsComplete * 12;
        assert.equal(after, before + 1, "hint " + index);
      }
      assert.equal(racer(harness, "you").pitCrewCount, 20);
    });

    test("fairness: a child can never be trapped on a fact", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      answerWrong(harness);
      assert.notEqual(racer(harness, "you").currentFact, fact);
    });

    test("fairness: stalls are two to three seconds and come from nothing else", () => {
      for (const card of CARD_SCHEDULE) {
        const stall = CARDS[card].stallMs;
        if (card === "wrench") assert.equal(stall, 3000, card);
        else if (card === "pothole" || card === "pileUp") assert.equal(stall, 2000, card);
        else assert.equal(stall, 0, card);
      }
    });

    test("fairness: no card that reaches its own owner carries a stall, so a self boost cannot stall", () => {
      // Honest name, because the old one ("even though the card can stall") named
      // a condition its fixture could not create. Every card that can reach its
      // own owner -- the self-scoped ones -- has stallMs 0, so playing one can
      // never distinguish `applyQuestionDelta`'s
      // `attacker.id === victim.id ? 0 : stallMs` from its absence. That guard is
      // unreachable defence today; what actually holds the rule up is the card
      // table, and that is what this test pins. If a self-scoped card is ever
      // given a stall, this goes red and the guard starts mattering.
      for (const card of CARD_SCHEDULE) {
        if (CARDS[card].scope !== "self") continue;
        assert.equal(CARDS[card].stallMs, 0, card + " is self-scoped and must not stall");
      }
      // Oil Slick is the only other card that could reach its owner, and it does
      // not: it skips the attacker outright. It carries no stall either.
      assert.equal(CARDS.oilSlick.scope, "aoe");
      assert.equal(CARDS.oilSlick.stallMs, 0);
      // And a targeted card, which is where every stall lives, is refused at self.
      for (const card of CARD_SCHEDULE) {
        if (CARDS[card].stallMs === 0) continue;
        assert.equal(CARDS[card].scope, "targeted", card);
        const harness = startRace();
        racer(harness, "you").hand = [card];
        const refused = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "you" });
        assert.deepEqual(refused, [], card + " played at self is refused, hand and all");
        assert.deepEqual(racer(harness, "you").hand, [card], card + " stays in the hand");
        assert.equal(racer(harness, "you").stalledUntilMs, 0);
      }
      // The observable rule itself: a self boost lands, and nothing locks.
      const harness = startRace();
      racer(harness, "you").hand = ["turbo"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      const hits = eventsOfType(events, "hit");
      assert.equal(hits.length, 1);
      assert.equal(hits[0]!.stallMs, 0);
      assert.equal(racer(harness, "you").stalledUntilMs, 0);
    });

    test("fairness: nothing an attack does can push a racer's requirement below one", () => {
      const harness = startRace();
      for (let round = 0; round < 6; round++) {
        racer(harness, "you").hand = ["turbo"];
        apply(harness, { kind: "useCard", racerId: "you", index: 0 });
        assert.ok(racer(harness, "you").questionsNeededThisLap >= 1);
      }
    });

    test("fairness: a shoved kart's effective progress recovers exactly, never overshoots", () => {
      const harness = startRace();
      answerRightTimes(harness, 8, "bolt");
      const before = effectiveProgress(racer(harness, "bolt"));
      racer(harness, "you").hand = ["wrench"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(effectiveProgress(racer(harness, "bolt")), before - 5);
      for (let index = 0; index < 5; index++) {
        answerRight(harness, "bolt", index === 0 ? 4000 : 1000);
      }
      assert.equal(effectiveProgress(racer(harness, "bolt")), before);
    });

    test("fairness: the only position callouts are passed and passedBy, from the child's seat", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 24; index++) {
        answerRight(harness, index % 2 === 0 ? "you" : "bolt");
        answerRight(harness, "gasket");
      }
      const callouts = harness.events.filter(
        (event) => event.type === "passed" || event.type === "passedBy",
      );
      assert.ok(callouts.length > 0, "the script never changed the order");
      for (const callout of callouts) {
        assert.equal(callout.racerId, "you", "a callout was written from a rival's seat");
        assert.deepEqual(
          Object.keys(callout).slice().sort(),
          ["at", "calloutMs", "otherId", "racerId", "type"],
          "a callout carried more than the two karts, the clock and its 1.6 s hold",
        );
      }
      // Nothing in the event stream ever names a place, so a running last-place
      // label cannot be built from it.
      for (const event of harness.events) {
        assert.ok(
          !("place" in event) || event.type === "finished",
          "a non-finish event carried a place: " + event.type,
        );
      }
    });

    // ---- the results screen has no bottom (round 1 defect 6) ---------------

    test("fairness: the results screen has no bottom -- it names the child's own place and the top three, nothing else", () => {
      const harness = startRace();
      // Put the child last by a clear margin: every rival answers, the child
      // does not.
      for (const id of ["bolt", "piston", "gasket"]) answerRightTimes(harness, 6, id);
      const board = resultsBoard(harness.state.racers, "you");

      assert.equal(board.place, 4, "the child's own place is named");
      assert.equal(board.total, 4);
      assert.equal(board.headline, "RACE COMPLETE", "and every finish is positive");
      assert.equal(board.podium.length, PODIUM_SIZE);
      assert.deepEqual(
        board.podium.map((entry) => entry.place),
        [1, 2, 3],
        "nobody below third is enumerated",
      );
      assert.equal(
        board.podium.find((entry) => entry.id === "you"),
        undefined,
        "a 4th-of-4 racer never appears in the list",
      );
      assert.deepEqual(
        Object.keys(board).sort(),
        ["headline", "place", "podium", "total"],
        "and there is no other field for a bottom to hide in",
      );
      const flattened = JSON.stringify(board);
      assert.equal(flattened.indexOf('"id":"you"'), -1, "the child is not in the list at all");
    });

    test("fairness: a podium finisher is still named on the podium, and a six-racer field still shows three", () => {
      const harness = startRace();
      answerRightTimes(harness, 6, "you");
      answerRightTimes(harness, 3, "bolt");
      const board = resultsBoard(harness.state.racers, "you");
      assert.equal(board.place, 1);
      assert.equal(board.headline, "VICTORY LAP");
      assert.equal(board.podium[0]!.id, "you");

      const six = harness.state.racers.concat([
        { ...harness.state.racers[1]!, id: "extra-1", seat: 4 },
        { ...harness.state.racers[1]!, id: "extra-2", seat: 5 },
      ]);
      const wider = resultsBoard(six, "you");
      assert.equal(wider.total, 6);
      assert.equal(wider.podium.length, PODIUM_SIZE, "still three, however big the field");
    });

    test("fairness: the engine's own ordering primitive still knows the whole order, so the guarantee lives in the results shape", () => {
      const harness = startRace();
      for (const id of ["bolt", "piston", "gasket"]) answerRightTimes(harness, 6, id);
      // The HUD and the pass callouts need the full order; the results screen
      // is the thing that must not show it.
      assert.equal(placeOf(harness.state.racers, "you"), 4);
      assert.equal(rankRacers(harness.state.racers).length, 4);
    });
  });
}
