// Design section: "The answer loop", numbered points 1 through 8.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { REVEAL_MS, factAnswer, factLeft, isStalled, step } = E;
    const {
      answerRight,
      answerRightTimes,
      answerWrong,
      apply,
      eventsOfType,
      giveHand,
      position,
      racer,
      startRace,
    } = helpersFor(E);

    test("answer loop 1: a fresh race is already asking a fact with an empty field", () => {
      const harness = startRace();
      const you = racer(harness, "you");
      assert.ok(you.currentFact > 0);
      assert.equal(you.entry, "");
      assert.equal(factLeft(you.currentFact), 1, "the Grand Prix opens on the ones");
    });

    test("answer loop 2: digits type into the field and Enter submits", () => {
      const harness = startRace({ preset: "1-12" });
      // Every fact on lap one of 1-12 is 1 x n, so answers are one or two digits.
      const fact = racer(harness, "you").currentFact;
      const answer = String(factAnswer(fact));
      if (answer.length === 1) {
        apply(harness, { kind: "digit", value: Number(answer[0]) });
        assert.equal(racer(harness, "you").correctCount, 1, "one-digit answers auto-submit");
        return;
      }
      apply(harness, { kind: "digit", value: Number(answer[0]) });
      assert.equal(racer(harness, "you").entry, answer[0]);
      apply(harness, { kind: "digit", value: Number(answer[1]) });
      assert.equal(racer(harness, "you").correctCount, 1);
    });

    test("answer loop 2: the field auto-submits when the digit count matches the answer", () => {
      const harness = startRace({ preset: "choose", chosenTables: [12] });
      const fact = racer(harness, "you").currentFact;
      const answer = String(factAnswer(fact));
      for (const digit of answer) apply(harness, { kind: "digit", value: Number(digit) });
      assert.equal(racer(harness, "you").correctCount, 1);
      assert.equal(racer(harness, "you").entry, "");
    });

    test("answer loop 2: backspace edits the field", () => {
      const harness = startRace({ preset: "choose", chosenTables: [12] });
      apply(harness, { kind: "digit", value: 9 });
      apply(harness, { kind: "backspace" });
      assert.equal(racer(harness, "you").entry, "");
      assert.equal(racer(harness, "you").attemptCount, 0);
    });

    test("answer loop 2: a leading zero is never accepted, so 07 cannot happen", () => {
      const harness = startRace({ preset: "choose", chosenTables: [12] });
      apply(harness, { kind: "digit", value: 0 });
      assert.equal(racer(harness, "you").entry, "");
      apply(harness, { kind: "digit", value: 1 });
      apply(harness, { kind: "digit", value: 0 });
      assert.equal(racer(harness, "you").entry.charAt(0), "1");
    });

    test("answer loop 2: other keys do nothing", () => {
      const harness = startRace();
      const before = JSON.stringify(harness.state);
      apply(harness, { kind: "digit", value: 42 });
      apply(harness, { kind: "digit", value: -1 });
      assert.equal(JSON.stringify(harness.state), before.replace(/"nowMs":0/, '"nowMs":2000'));
    });

    test("answer loop 2: an empty field cannot be submitted", () => {
      const harness = startRace();
      apply(harness, { kind: "submit" });
      assert.equal(racer(harness, "you").attemptCount, 0);
    });

    test("answer loop 3: a correct answer lights the lamp, ticks the streak and moves on", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      const events = answerRight(harness);
      assert.equal(events.length, 1);
      assert.equal(events[0]!.type, "correct");
      const you = racer(harness, "you");
      assert.equal(you.streak, 1);
      assert.equal(you.correctInLap, 1);
      assert.equal(you.correctCount, 1);
      assert.notEqual(you.currentFact, fact, "the next fact appears");
    });

    test("answer loop 4: a wrong answer resets the streak and keeps the same fact", () => {
      const harness = startRace();
      answerRight(harness);
      answerRight(harness);
      const fact = racer(harness, "you").currentFact;
      const events = answerWrong(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["wrong"],
      );
      const you = racer(harness, "you");
      assert.equal(you.streak, 0);
      assert.equal(you.currentFact, fact, "the same fact stays");
      assert.equal(you.entry, "", "the field clears");
    });

    test("answer loop 4: a wrong answer never moves the kart and never adds questions", () => {
      const harness = startRace();
      answerRight(harness);
      const before = position(racer(harness, "you"));
      answerWrong(harness);
      assert.deepEqual(position(racer(harness, "you")), before);
    });

    test("answer loop 5: a second wrong on the same fact reveals the answer and advances", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      const events = answerWrong(harness);
      const reveals = eventsOfType(events, "reveal");
      assert.equal(reveals.length, 1);
      assert.equal(reveals[0]!.fact, fact);
      assert.equal(reveals[0]!.answer, factAnswer(fact));
      assert.equal(reveals[0]!.revealMs, REVEAL_MS);
      const you = racer(harness, "you");
      assert.equal(you.correctInLap, 1, "progress advances as if answered");
      assert.notEqual(you.currentFact, fact, "the race moves on");
      assert.equal(you.streak, 0, "the streak is already zero");
      assert.equal(you.revealCount, 1);
      assert.equal(you.correctCount, 0, "a reveal is not a correct answer");
    });

    test("answer loop 5: a revealed fact is queued for the pit lane", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      answerWrong(harness);
      assert.deepEqual(
        racer(harness, "you").pitLane.map((entry) => entry.fact),
        [fact],
      );
    });

    test("answer loop 5: Practice mode shows the answer on the first mistake", () => {
      const harness = startRace({ mode: "practice", racers: [{ id: "you", kind: "human" }] });
      assert.equal(harness.state.revealAfterWrong, 1);
      const events = answerWrong(harness);
      assert.equal(eventsOfType(events, "reveal").length, 1);
    });

    test("answer loop 6: pit crew shows the answer, counts for progress and holds the streak", () => {
      const harness = startRace();
      answerRight(harness);
      answerRight(harness);
      const fact = racer(harness, "you").currentFact;
      const events = apply(harness, { kind: "hint" });
      const hints = eventsOfType(events, "pitCrew");
      assert.equal(hints.length, 1);
      assert.equal(hints[0]!.answer, factAnswer(fact));
      const you = racer(harness, "you");
      assert.equal(you.streak, 2, "the streak neither grows nor resets");
      assert.equal(you.correctInLap, 3, "the question counts for progress");
      assert.equal(you.pitCrewCount, 1);
      assert.equal(you.correctCount, 2, "pit-crew answers are counted separately");
    });

    test("answer loop 6: pit crew is always available, even on a fact already missed", () => {
      const harness = startRace();
      answerWrong(harness);
      const events = apply(harness, { kind: "hint" });
      assert.equal(eventsOfType(events, "pitCrew").length, 1);
      assert.equal(racer(harness, "you").correctInLap, 1);
    });

    test("answer loop 7: a fact missed twice returns three questions later in the same lap", () => {
      const harness = startRace({ preset: "2-5" });
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      answerWrong(harness);
      const served: number[] = [];
      for (let index = 0; index < 4; index++) {
        served.push(racer(harness, "you").currentFact);
        answerRight(harness);
      }
      // question 1, 2 and 3 after the reveal, then the missed fact returns.
      assert.equal(served.indexOf(fact), 3, "served order was " + served.join(","));
      assert.equal(
        racer(harness, "you").pitLane.length,
        0,
        "it returns once, not on a loop",
      );
    });

    test("answer loop 7: a fact missed at the end of a lap returns at the start of the next", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 10; index++) answerRight(harness);
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      answerWrong(harness);
      answerRight(harness);
      assert.equal(racer(harness, "you").lapsComplete, 1, "the lap ended");
      assert.equal(racer(harness, "you").currentFact, fact, "the missed fact opens the next lap");
    });

    test("answer loop 8: an unblocked Wrench locks the field for three seconds", () => {
      const harness = startRace();
      racer(harness, "you").hand = [];
      racer(harness, "bolt").hand = ["wrench"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" }, 1000);
      const you = racer(harness, "you");
      assert.equal(you.stalledUntilMs, 4000);
      assert.ok(isStalled(you, 3999));
      assert.ok(!isStalled(you, 4000));
      answerRight(harness, "you", 500);
      assert.equal(racer(harness, "you").correctCount, 0, "the field is locked");
      answerRight(harness, "you", 3000);
      assert.equal(racer(harness, "you").correctCount, 1, "the lock lifts");
    });

    test("answer loop 8: a Pothole and a Pile-Up lock the field for two seconds", () => {
      for (const card of ["pothole", "pileUp"] as const) {
        const harness = startRace();
        racer(harness, "bolt").hand = [card];
        apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" }, 1000);
        assert.equal(racer(harness, "you").stalledUntilMs, 3000, card + " stall");
      }
    });

    test("answer loop 8: Oil Slick, Tow Hook, self boosts and blocked hits never stall", () => {
      const harness = startRace();
      racer(harness, "bolt").hand = ["oilSlick"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0 });
      assert.equal(racer(harness, "you").stalledUntilMs, 0, "Oil Slick");

      racer(harness, "bolt").hand = ["towHook"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.equal(racer(harness, "you").stalledUntilMs, 0, "Tow Hook");

      racer(harness, "you").hand = ["turbo"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.equal(racer(harness, "you").stalledUntilMs, 0, "a self boost");

      racer(harness, "you").rollCages = 1;
      racer(harness, "bolt").hand = ["wrench"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.equal(racer(harness, "you").stalledUntilMs, 0, "a blocked hit");
    });

    test("answer loop: there are no per-question timers, so a tick never advances a fact", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      for (let index = 0; index < 100; index++) apply(harness, { kind: "tick" }, 10000);
      assert.equal(racer(harness, "you").currentFact, fact);
      assert.equal(racer(harness, "you").attemptCount, 0);
      assert.equal(racer(harness, "you").streak, 0);
    });

    test("answer loop: the engine never lets the clock run backwards", () => {
      const harness = startRace();
      answerRight(harness, "you", 5000);
      const back = step(harness.state, { kind: "tick" }, 10);
      assert.equal(back.state.nowMs, 5000);
    });

    // ---- the stale wrong-answer counter (round 1 defect 1) ----------------
    //
    // `wrongOnCurrentFact` belongs to the fact that is showing, not to the
    // racer. Anything that installs a different fact without a question being
    // answered has to clear it, or the child's FIRST mistake on the new fact is
    // revealed, advanced and filed in the pit lane after a single miss.

    test("answer loop 4: a lap finished by a boost clears the wrong counter, so the first mistake on the next fact is only a wrong", () => {
      const harness = startRace();
      answerRightTimes(harness, 3);
      const missedOnce = racer(harness, "you").currentFact;
      answerWrong(harness);
      racer(harness, "you").entry = "4";
      assert.equal(racer(harness, "you").wrongOnCurrentFact, 1);

      giveHand(harness, "you", ["turbo"]);
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      const you = racer(harness, "you");
      assert.equal(you.lapsComplete, 1, "the Turbo finished the lap");
      assert.notEqual(you.currentFact, missedOnce, "and a different fact is being asked");
      assert.equal(you.wrongOnCurrentFact, 0, "the counter does not follow the racer");
      assert.equal(you.entry, "", "and neither does what was typed at the old fact");

      const before = position(you);
      const events = answerWrong(harness);
      const after = racer(harness, "you");
      assert.deepEqual(
        events.map((event) => event.type),
        ["wrong"],
        "the first mistake on the new fact is a wrong, not a reveal",
      );
      assert.deepEqual(position(after), before, "nothing advanced");
      assert.equal(after.revealCount, 0);
      assert.deepEqual(after.pitLane, [], "and nothing was filed after a single miss");
    });

    test("answer loop 4: a Tow Hook swap clears the wrong counter, so the first mistake after it is only a wrong", () => {
      const harness = startRace();
      answerRightTimes(harness, 5);
      answerWrong(harness);
      racer(harness, "you").entry = "7";
      assert.equal(racer(harness, "you").wrongOnCurrentFact, 1);

      giveHand(harness, "bolt", ["towHook"]);
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      const you = racer(harness, "you");
      assert.equal(you.wrongOnCurrentFact, 0, "the swap handed over a position, not a mistake");
      assert.equal(you.entry, "");

      const events = answerWrong(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["wrong"],
      );
      assert.equal(racer(harness, "you").revealCount, 0);
      assert.deepEqual(racer(harness, "you").pitLane, []);
    });

    test("answer loop 4: a fact answered right after one miss takes the count with it, so the next fact starts clean", () => {
      // The plainest form of the stale-counter bug, and until now nothing in the
      // suite drove it: miss a fact once, get it right, then miss the NEXT fact.
      // If the count survived the answered question, that second miss would be
      // the fact's second and the child would be shown an answer they never
      // failed twice. Two mechanisms can prevent it -- `consumeQuestion`'s reset
      // and `refreshQuestion`'s -- and they shadow each other, so this is what
      // pins the pair; neither is individually necessary. See the round 3 report.
      const harness = startRace();
      const first = racer(harness, "you").currentFact;
      answerWrong(harness);
      assert.equal(racer(harness, "you").wrongOnCurrentFact, 1);
      assert.equal(racer(harness, "you").currentFact, first, "the same fact stays");

      answerRight(harness);
      const moved = racer(harness, "you");
      assert.equal(moved.wrongOnCurrentFact, 0, "the count went with the answered fact");
      assert.notEqual(moved.currentFact, first);

      const events = answerWrong(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["wrong"],
        "the first miss on the new fact is a wrong, not a reveal",
      );
      assert.equal(racer(harness, "you").revealCount, 0);
      assert.deepEqual(racer(harness, "you").pitLane, []);
    });

    test("answer loop 4: a lap boundary clears the wrong counter even when the new lap opens on the SAME fact", () => {
      // The two tests above cannot tell `startLap`'s reset from
      // `refreshQuestion`'s, because in both of them the fact changes across the
      // boundary and either mechanism would do it. Delete `startLap`'s alone and
      // they stay green.
      //
      // This is the case where they come apart: the fact showing when the boost
      // lands is a pit-lane re-ask, and a pit-lane entry filed on the old lap is
      // *carried over* into the new one, so `refreshQuestion` installs the very
      // same fact it found. `currentFact === previousFact`, its reset does not
      // fire, and `startLap`'s is the only thing standing between a first miss on
      // the new lap and a reveal the child did not earn.
      const harness = startRace();
      const filed = racer(harness, "you").currentFact;
      answerWrong(harness);
      answerWrong(harness); // second wrong: revealed and filed for the pit lane
      assert.deepEqual(
        racer(harness, "you").pitLane.map((entry) => entry.fact),
        [filed],
      );
      answerRightTimes(harness, 3); // "three questions later in the same lap"
      const beforeBoost = racer(harness, "you");
      assert.equal(beforeBoost.currentFact, filed, "the filed fact is back");
      assert.equal(beforeBoost.currentFromPitLane, true);
      assert.equal(beforeBoost.lapsComplete, 0);

      answerWrong(harness); // one miss on it, and the counter is standing at one
      racer(harness, "you").entry = "9";
      assert.equal(racer(harness, "you").wrongOnCurrentFact, 1);
      assert.equal(racer(harness, "you").currentFact, filed, "still showing, still unanswered");

      giveHand(harness, "you", ["turbo"]);
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      const you = racer(harness, "you");
      assert.equal(you.lapsComplete, 1, "the Turbo finished the lap");
      assert.equal(you.currentFact, filed, "and the SAME fact carries over into the new lap");
      assert.equal(you.currentFromPitLane, true);
      assert.equal(you.wrongOnCurrentFact, 0, "so only the lap boundary can have cleared it");
      assert.equal(you.entry, "");

      const events = answerWrong(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["wrong"],
        "a fresh lap means a fresh count, even on a fact that came with it",
      );
      assert.equal(racer(harness, "you").revealCount, 1, "no second reveal was earned");
    });

    test("answer loop 5: two wrongs on the SAME fact still reveal, so the fix did not delete the rule", () => {
      const harness = startRace();
      const fact = racer(harness, "you").currentFact;
      answerWrong(harness);
      const events = answerWrong(harness);
      assert.deepEqual(
        events.map((event) => event.type),
        ["reveal"],
      );
      const you = racer(harness, "you");
      assert.equal(you.revealCount, 1);
      assert.equal(you.correctInLap, 1, "progress advances as if answered");
      assert.deepEqual(
        you.pitLane.map((entry) => entry.fact),
        [fact],
      );
    });
  });
}
