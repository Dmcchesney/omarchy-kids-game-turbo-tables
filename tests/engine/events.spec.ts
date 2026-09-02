// Plan, layer 1: "events.ts -- event union and the ordering guarantee within one
// step" and "every state change emits exactly one event".

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import type { RaceEventType } from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { EVENT_ORDER, SIGNAL_CATALOG, cloneState, isEventOrdered, step } = E;
    const { answerRight, answerRightTimes, answerWrong, apply, eventsOfType, racer, startRace } = helpersFor(E);

    const UNION: RaceEventType[] = [
      "correct",
      "wrong",
      "reveal",
      "pitCrew",
      "lapComplete",
      "handDealt",
      "cardUsed",
      "hit",
      "blocked",
      "swap",
      "passed",
      "passedBy",
      "finished",
      "signal",
    ];

    test("events: the union is exactly the fourteen types the plan names", () => {
      assert.deepEqual(Object.keys(EVENT_ORDER).slice().sort(), UNION.slice().sort());
    });

    test("events: the four-signal catalog is the one the lobby uses", () => {
      assert.equal(SIGNAL_CATALOG.length, 4);
      assert.deepEqual(SIGNAL_CATALOG.slice(), ["goodLuck", "niceRun", "soClose", "goodGame"]);
    });

    test("events: an input that changes nothing emits nothing", () => {
      const harness = startRace();
      const before = JSON.stringify(cloneState(harness.state));
      const events = apply(harness, { kind: "digit", value: 0 });
      assert.deepEqual(events, []);
      const after = cloneState(harness.state);
      after.nowMs = harness.state.nowMs - 1000;
      assert.equal(JSON.stringify(after), before);
    });

    test("events: every rule change emits exactly one event", () => {
      const harness = startRace({ preset: "2-5" });
      assert.deepEqual(
        answerRight(harness).map((event) => event.type),
        ["correct"],
      );
      assert.deepEqual(
        answerWrong(harness).map((event) => event.type),
        ["wrong"],
      );
      assert.deepEqual(
        answerWrong(harness).map((event) => event.type),
        ["reveal"],
      );
      assert.deepEqual(
        apply(harness, { kind: "hint" }).map((event) => event.type),
        ["pitCrew"],
      );
      racer(harness, "you").hand = ["rollCage"];
      assert.deepEqual(
        apply(harness, { kind: "useCard", racerId: "you", index: 0 }).map((event) => event.type),
        ["cardUsed"],
      );
    });

    test("events: a lap completed by an answer emits correct then lapComplete", () => {
      const harness = startRace({ preset: "2-5", powerupsEnabled: false });
      for (let index = 0; index < 11; index++) answerRight(harness);
      assert.deepEqual(
        answerRight(harness).map((event) => event.type),
        ["correct", "lapComplete"],
      );
    });

    test("events: a card that lands, completes a lap and finishes a race is ordered", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 11, "bolt");
      racer(harness, "bolt").hand = ["turbo"];
      const events = apply(harness, { kind: "useCard", racerId: "bolt", index: 0 });
      assert.deepEqual(
        events.map((event) => event.type),
        ["cardUsed", "hit", "lapComplete", "finished"],
      );
      assert.ok(isEventOrdered(events));
    });

    test("events: the ordering guarantee holds across a long race", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 48; index++) {
        const events = answerRight(harness);
        assert.ok(isEventOrdered(events), "out of order at answer " + index);
      }
    });

    test("events: an answer that charges a hand puts handDealt after the lap", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 11; index++) answerRight(harness);
      assert.deepEqual(
        answerRight(harness).map((event) => event.type),
        ["correct", "lapComplete", "handDealt"],
      );
    });

    test("events: a pass and a pass-by are reported from the child's seat", () => {
      const harness = startRace();
      answerRightTimes(harness, 3, "bolt");
      const overtake = eventsOfType(harness.events, "passedBy");
      assert.equal(overtake.length, 1);
      assert.equal(overtake[0]!.racerId, "you");
      assert.equal(overtake[0]!.otherId, "bolt");
      harness.events.length = 0;
      answerRightTimes(harness, 4, "you");
      const passed = eventsOfType(harness.events, "passed");
      assert.equal(passed.length, 1);
      assert.equal(passed[0]!.otherId, "bolt");
    });

    test("events: a Tow Hook that changes the order reports the pass", () => {
      const harness = startRace();
      answerRightTimes(harness, 8, "bolt");
      racer(harness, "you").hand = ["towHook"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.deepEqual(
        events.map((event) => event.type),
        ["cardUsed", "swap", "passed"],
      );
    });

    test("events: every event carries the clock the step ran at", () => {
      const harness = startRace({ preset: "2-5" });
      for (let index = 0; index < 20; index++) answerRight(harness);
      for (const event of harness.events) {
        assert.ok(Number.isInteger(event.at), "not a timestamp: " + JSON.stringify(event));
      }
      assert.equal(harness.events[harness.events.length - 1]!.at, harness.now);
    });

    test("events: the reducer never mutates the state it was handed", () => {
      const harness = startRace();
      const snapshot = JSON.stringify(harness.state);
      step(harness.state, { kind: "answer", racerId: "you", value: 1 }, 5000);
      step(harness.state, { kind: "useCard", racerId: "you", index: 0 }, 5000);
      assert.equal(JSON.stringify(harness.state), snapshot);
    });
  });
}
