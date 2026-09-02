// The presentation timings the design fixes, and where each one is carried.
//
// Round 1 left NEXT_FACT_MS, SPUTTER_MS and CALLOUT_MS exported, read by
// nothing and asserted by nothing. Three of the five now ride on the event they
// belong to; all five are pinned here against the design line that sets them.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { CALLOUT_MS, NEXT_FACT_MS, REVEAL_MS, SETTLE_MS, SPUTTER_MS } = E;
    const { answerRightTimes, answerWrong, eventsOfType, racer, startRace } = helpersFor(E);

    test("timings: the five design timings are 250, 500, 1500, 1600 and 15000", () => {
      // "the next fact appears within 250 ms"        -- The answer loop, 3
      assert.equal(NEXT_FACT_MS, 250);
      // "500 ms sputter"                             -- The answer loop, 4
      assert.equal(SPUTTER_MS, 500);
      // "the correct answer is shown for 1500 ms"    -- The answer loop, 5
      assert.equal(REVEAL_MS, 1500);
      // "Callouts for 1.6 s"                         -- The view
      assert.equal(CALLOUT_MS, 1600);
      // "Rivals keep racing for up to fifteen seconds" -- Finish
      assert.equal(SETTLE_MS, 15000);
    });

    test("timings: a wrong answer carries its 500 ms sputter on the event", () => {
      const harness = startRace();
      const events = answerWrong(harness);
      const wrong = eventsOfType(events, "wrong");
      assert.equal(wrong.length, 1);
      assert.equal(wrong[0]!.sputterMs, SPUTTER_MS);
      assert.equal(wrong[0]!.sputterMs, 500);
    });

    test("timings: a reveal carries its 1500 ms hold on the event", () => {
      const harness = startRace();
      answerWrong(harness);
      const reveal = eventsOfType(answerWrong(harness), "reveal");
      assert.equal(reveal.length, 1);
      assert.equal(reveal[0]!.revealMs, REVEAL_MS);
    });

    test("timings: a pass callout carries its 1.6 s hold on the event", () => {
      const harness = startRace();
      // Move a rival ahead, then take the place back, so both callouts fire.
      answerRightTimes(harness, 3, "bolt");
      const passedBy = eventsOfType(harness.events, "passedBy");
      assert.ok(passedBy.length > 0, "a rival went past");
      assert.equal(passedBy[0]!.calloutMs, CALLOUT_MS);
      answerRightTimes(harness, 4, "you");
      const passed = eventsOfType(harness.events, "passed");
      assert.ok(passed.length > 0, "and the child went back past");
      assert.equal(passed[0]!.calloutMs, CALLOUT_MS);
      assert.equal(racer(harness, "you").correctCount, 4);
    });

    test("timings: the settle window on a fresh race is the design's fifteen seconds", () => {
      assert.equal(startRace().state.settleMs, SETTLE_MS);
    });
  });
}
