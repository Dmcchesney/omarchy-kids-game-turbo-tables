// Design section: "Streaks and the powerup hand".

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { BELLRINGER_STREAK_THRESHOLD, CHARGE_GLOW_FROM, CHARGE_SEGMENTS, STREAK_THRESHOLD, chargeReady, chargeSegments, nextStreak, shouldDealHand } = E;
    const { answerRight, answerRightTimes, answerWrong, apply, eventsOfType, playCard, racer, startRace } = helpersFor(E);

    test("streak: the threshold is twelve, one clean lap", () => {
      assert.equal(STREAK_THRESHOLD, 12);
      assert.equal(BELLRINGER_STREAK_THRESHOLD, 15);
      assert.equal(startRace().state.streakThreshold, 12);
    });

    test("streak: it counts consecutive correct answers within the race", () => {
      const harness = startRace();
      for (let index = 1; index <= 5; index++) {
        answerRight(harness);
        assert.equal(racer(harness, "you").streak, index);
      }
    });

    test("streak: a wrong answer resets it to zero", () => {
      const harness = startRace();
      answerRightTimes(harness, 4);
      answerWrong(harness);
      assert.equal(racer(harness, "you").streak, 0);
    });

    test("streak: pit-crew answers neither build it nor reset it", () => {
      const harness = startRace();
      answerRightTimes(harness, 4);
      apply(harness, { kind: "hint" });
      assert.equal(racer(harness, "you").streak, 4);
      answerRight(harness);
      assert.equal(racer(harness, "you").streak, 5);
    });

    test("streak: a revealed answer does not build it", () => {
      const harness = startRace();
      answerRightTimes(harness, 3);
      answerWrong(harness);
      answerWrong(harness);
      assert.equal(racer(harness, "you").streak, 0);
    });

    test("streak: completing a lap does not touch it", () => {
      const harness = startRace({ preset: "2-5" });
      answerRightTimes(harness, 12);
      assert.equal(racer(harness, "you").lapsComplete, 1);
      assert.equal(racer(harness, "you").streak, 0, "the hand at twelve reset it, not the lap");
      answerRightTimes(harness, 3);
      assert.equal(racer(harness, "you").streak, 3, "the streak carries straight across the lap line");
    });

    test("streak: being hit does not touch it", () => {
      const harness = startRace();
      answerRightTimes(harness, 5);
      racer(harness, "bolt").hand = ["pileUp"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.equal(racer(harness, "you").streak, 5);
    });

    test("streak: at twelve in a row a hand of three is dealt and the streak resets", () => {
      const harness = startRace();
      for (let index = 0; index < 11; index++) answerRight(harness);
      assert.equal(racer(harness, "you").hand.length, 0);
      const events = answerRight(harness);
      const dealt = eventsOfType(events, "handDealt");
      assert.equal(dealt.length, 1);
      assert.equal(dealt[0]!.hand.length, 3);
      assert.equal(racer(harness, "you").streak, 0);
      assert.deepEqual(racer(harness, "you").hand, dealt[0]!.hand);
    });

    test("streak: with a hand held the streak keeps climbing and no second hand is dealt", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      const hand = racer(harness, "you").hand.slice();
      answerRightTimes(harness, 20);
      assert.equal(racer(harness, "you").streak, 20);
      assert.deepEqual(racer(harness, "you").hand, hand, "no second hand while one is held");
    });

    test("streak: the next correct answer after the hand is spent deals a new one", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      answerRightTimes(harness, 20);
      const index = racer(harness, "you").hand.indexOf("nitro");
      apply(harness, { kind: "useCard", racerId: "you", index });
      assert.equal(racer(harness, "you").hand.length, 0);
      assert.equal(racer(harness, "you").streak, 20, "spending a hand does not touch the streak");
      const events = answerRight(harness);
      assert.equal(eventsOfType(events, "handDealt").length, 1);
      assert.equal(racer(harness, "you").hand.length, 3);
    });

    test("streak: powerups are off outside Grand Prix, so no hand is ever dealt", () => {
      for (const mode of ["practice", "timeTrial", "ghost"] as const) {
        const harness = startRace({ mode, racers: [{ id: "you", kind: "human" }] });
        assert.equal(harness.state.powerupsEnabled, false, mode);
        answerRightTimes(harness, 20);
        assert.equal(racer(harness, "you").hand.length, 0, mode);
        assert.equal(eventsOfType(harness.events, "handDealt").length, 0, mode);
      }
    });

    test("streak: rivals build streaks and earn hands under the same rules", () => {
      const harness = startRace();
      for (let index = 0; index < 12; index++) answerRight(harness, "bolt");
      assert.equal(racer(harness, "bolt").hand.length, 3);
      assert.equal(racer(harness, "bolt").streak, 0);
    });

    test("streak: best streak records the highest reached this race", () => {
      const harness = startRace();
      answerRightTimes(harness, 7);
      answerWrong(harness);
      answerRightTimes(harness, 3);
      assert.equal(racer(harness, "you").bestStreak, 7);
    });

    test("streak: the pure helpers describe build, reset and hold", () => {
      assert.equal(nextStreak(4, "build"), 5);
      assert.equal(nextStreak(4, "reset"), 0);
      assert.equal(nextStreak(4, "hold"), 4);
      assert.equal(shouldDealHand(12, 12, 0), true);
      assert.equal(shouldDealHand(12, 12, 3), false, "not while a hand is held");
      assert.equal(shouldDealHand(11, 12, 0), false);
      assert.equal(shouldDealHand(30, 15, 0), true, "the parity threshold works the same way");
    });

    test("streak: the charge bar has twelve segments, glows from nine and reads ready at twelve", () => {
      assert.equal(CHARGE_SEGMENTS, 12);
      assert.equal(CHARGE_GLOW_FROM, 9);
      assert.equal(chargeSegments(0, 12), 0);
      assert.equal(chargeSegments(9, 12), 9);
      assert.equal(chargeSegments(12, 12), 12);
      assert.equal(chargeSegments(40, 12), 12, "the bar does not overflow");
      assert.equal(chargeReady(11, 12), false);
      assert.equal(chargeReady(12, 12), true);
    });

    // ---- the pit-crew deal (round 1 defect 3) ------------------------------

    test("streak: a pit-crew press at full charge with an empty hand deals NOTHING, because the design says 'the next correct answer after the hand is spent deals a new one'", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      assert.deepEqual(racer(harness, "you").hand, ["nitro", "oilSlick", "wrench"]);
      // Hold the hand while the streak climbs back to the threshold, then spend
      // it: full charge, empty hand, and the very next input is the H key.
      answerRightTimes(harness, 12);
      assert.equal(racer(harness, "you").streak, 12);
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.deepEqual(racer(harness, "you").hand, []);
      assert.equal(racer(harness, "you").streak, 12, "spending a card does not touch the streak");

      const events = apply(harness, { kind: "hint", racerId: "you" });
      assert.deepEqual(
        events.map((event) => event.type),
        ["pitCrew"],
        "no handDealt: 'Pit-crew answers ... do not count toward it'",
      );
      const you = racer(harness, "you");
      assert.deepEqual(you.hand, []);
      assert.equal(you.streak, 12, "and the streak neither grew nor reset");
      assert.equal(you.pitCrewCount, 1);
    });

    test("streak: the next CORRECT answer after the hand is spent is what deals the new one", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      answerRightTimes(harness, 12);
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      apply(harness, { kind: "hint", racerId: "you" });
      assert.deepEqual(racer(harness, "you").hand, [], "the pit-crew answer dealt nothing");
      const events = answerRight(harness);
      assert.deepEqual(
        eventsOfType(events, "handDealt").map((event) => event.hand),
        [["pothole", "rollCage", "pileUp"]],
        "the correct answer deals, and the shared cursor carries on",
      );
      assert.equal(racer(harness, "you").streak, 0);
    });

    test("streak: a revealed answer deals nothing either, for the same reason", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      answerRightTimes(harness, 12);
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.equal(racer(harness, "you").streak, 12);
      answerWrong(harness);
      assert.equal(racer(harness, "you").streak, 0, "the first wrong already zeroed it");
      const events = answerWrong(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["reveal"],
      );
      assert.deepEqual(racer(harness, "you").hand, []);
    });

    test("streak: the answer that finishes the race deals no hand, and does not move the shared cursor", () => {
      // Two laps of twelve, and the threshold is twelve, so the last correct
      // answer of the last lap both crosses the finish line and charges a hand:
      // the hand from lap one has been spent, the streak is back at twelve, and
      // the hand is empty. `advanceLaps` sets `finished` before the deal is
      // considered; without the `racer.finished` guard in `dealIfCharged` the
      // finishing answer emits `correct, lapComplete, finished, handDealt` and a
      // racer who is out of the race walks away holding three cards -- and those
      // three come off the cursor every other racer is still drawing from, so
      // every later hand in the race shifts.
      const harness = startRace({ preset: "choose", chosenTables: [2, 3] });
      answerRightTimes(harness, 12);
      assert.deepEqual(racer(harness, "you").hand, ["nitro", "oilSlick", "wrench"]);
      assert.equal(harness.state.cardCursor, 3);
      // Spend it on the one card that neither boosts the owner nor stalls the
      // victims, so the finishing lap still takes exactly twelve answers.
      playCard(harness, "you", "oilSlick");
      assert.deepEqual(racer(harness, "you").hand, []);

      for (let index = 0; index < 11; index++) answerRight(harness);
      assert.equal(racer(harness, "you").streak, 11, "one short of the threshold and of the line");
      assert.equal(racer(harness, "you").finished, false);

      const events = answerRight(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["correct", "lapComplete", "finished"],
        "no handDealt on the finishing answer",
      );
      const finisher = racer(harness, "you");
      assert.equal(finisher.finished, true);
      assert.equal(finisher.streak, 12, "the streak did reach the threshold on that answer");
      assert.deepEqual(finisher.hand, []);
      assert.equal(harness.state.cardCursor, 3, "the shared cursor did not move");

      // And the proof that the cursor really was still at three: the next racer
      // to charge gets the hand that follows, not the one after it.
      answerRightTimes(harness, 12, "bolt");
      assert.deepEqual(racer(harness, "bolt").hand, ["pothole", "rollCage", "pileUp"]);
      assert.equal(harness.state.cardCursor, 6);
    });
  });
}
