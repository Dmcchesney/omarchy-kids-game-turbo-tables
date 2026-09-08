// Design sections: "Modes" (Time trial produces the ghost; Ghost beats it and
// the record updates; Grand Prix never stores a record) and "Data" (`records`:
// per preset, best clean time, correct, attempted, answer timeline).
//
// Plan, engine specification, ghost.ts: "answer timeline recording and playback
// for records; record update rules; per preset" and the key test, "a tie keeps
// the old record."

import { describe, test } from "node:test";
import assert from "node:assert/strict";

import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const {
      beatsRecord,
      bestRecord,
      cloneTimeline,
      createRace,
      effectiveProgress,
      emptyTimeline,
      factAnswer,
      ghostLead,
      ghostProgressAt,
      ghostReachedAt,
      isCleanMode,
      isRecordEligible,
      recordFromRace,
      recordStep,
      step,
      timelineFromEvents,
      updateRecord,
    } = E;
    const { answerRightTimes, apply, racer, startRace } = helpersFor(E);

    /** Drive a solo clean run of one table and record the timeline as it goes. */
    function timeTrial(seed = 2026, mode: "timeTrial" | "ghost" = "timeTrial", gapMs = 4000) {
      let state = createRace({
        seed,
        preset: "choose",
        chosenTables: [2],
        mode,
        racers: [{ id: "you", kind: "human" as const }],
      });
      state = step(state, { kind: "start" }, 0).state;
      let timeline = emptyTimeline();
      let at = 0;
      for (let index = 0; index < 12; index++) {
        at += gapMs;
        const live = state.racers[0]!;
        const result = step(
          state,
          { kind: "answer", racerId: "you", value: factAnswer(live.currentFact) },
          at,
        );
        state = result.state;
        timeline = recordStep(timeline, state, result.events, "you");
      }
      return { state, timeline };
    }

    // ---- recording --------------------------------------------------------

    test("ghost: a timeline is one sample per answer, ascending, with no dates in it", () => {
      const run = timeTrial();
      assert.equal(run.timeline.samples.length, 12);
      let previous = -1;
      for (const sample of run.timeline.samples) {
        assert.ok(sample.atMs > previous, "samples must ascend");
        previous = sample.atMs;
        assert.deepEqual(Object.keys(sample).sort(), ["atMs", "progress"]);
      }
      assert.equal(run.timeline.samples[0]!.atMs, 4000);
      assert.equal(run.timeline.samples[11]!.atMs, 48000);
    });

    test("ghost: a sample records effective progress, so it lines the ghost up with the track", () => {
      const run = timeTrial();
      for (let index = 0; index < 12; index++)
        assert.equal(run.timeline.samples[index]!.progress, index + 1);
    });

    test("ghost: times are measured from the start of the race, not from zero on the clock", () => {
      let state = createRace({
        seed: 5,
        preset: "choose",
        chosenTables: [2],
        mode: "timeTrial",
        racers: [{ id: "you", kind: "human" as const }],
      });
      state = step(state, { kind: "start" }, 90000).state;
      assert.equal(state.startedAtMs, 90000);
      let timeline = emptyTimeline();
      const live = state.racers[0]!;
      const result = step(state, { kind: "answer", racerId: "you", value: factAnswer(live.currentFact) }, 93000);
      timeline = recordStep(timeline, result.state, result.events, "you");
      assert.equal(timeline.samples[0]!.atMs, 3000);
    });

    test("ghost: a pit-crew answer and a revealed answer are on the timeline; a wrong one is not", () => {
      const harness = startRace({
        preset: "choose",
        chosenTables: [2],
        mode: "timeTrial",
        racers: [{ id: "you", kind: "human" as const }],
      });
      let timeline = emptyTimeline();
      const hint = apply(harness, { kind: "hint" });
      timeline = recordStep(timeline, harness.state, hint, "you");
      assert.equal(timeline.samples.length, 1);
      const wrong = apply(harness, {
        kind: "answer",
        racerId: "you",
        value: factAnswer(racer(harness, "you").currentFact) + 1,
      });
      timeline = recordStep(timeline, harness.state, wrong, "you");
      assert.equal(timeline.samples.length, 1, "a wrong answer moves no kart");
      const again = apply(harness, {
        kind: "answer",
        racerId: "you",
        value: factAnswer(racer(harness, "you").currentFact) + 1,
      });
      timeline = recordStep(timeline, harness.state, again, "you");
      assert.equal(timeline.samples.length, 2, "the reveal advances, so it is a sample");
    });

    test("ghost: timelineFromEvents rebuilds the same timeline the step recorder wrote", () => {
      let state = createRace({
        seed: 77,
        preset: "choose",
        chosenTables: [2, 3],
        mode: "timeTrial",
        racers: [{ id: "you", kind: "human" as const }],
      });
      state = step(state, { kind: "start" }, 0).state;
      let timeline = emptyTimeline();
      const events: EngineModule.RaceEvent[] = [];
      let at = 0;
      for (let index = 0; index < 24; index++) {
        at += 3500;
        const live = state.racers[0]!;
        const value =
          index % 7 === 3 ? factAnswer(live.currentFact) + 1 : factAnswer(live.currentFact);
        const result = step(state, { kind: "answer", racerId: "you", value }, at);
        state = result.state;
        timeline = recordStep(timeline, state, result.events, "you");
        for (const event of result.events) events.push(event);
      }
      assert.deepEqual(timelineFromEvents(events, "you", 0), timeline);
    });

    test("ghost: cloneTimeline copies, so a saved record cannot be edited through the live one", () => {
      const run = timeTrial();
      const copy = cloneTimeline(run.timeline);
      copy.samples[0]!.progress = 999;
      assert.equal(run.timeline.samples[0]!.progress, 1);
    });

    // ---- playback ---------------------------------------------------------

    test("ghost: playback interpolates between samples and holds at both ends", () => {
      const run = timeTrial();
      assert.equal(ghostProgressAt(run.timeline, 0), 0);
      assert.equal(ghostProgressAt(run.timeline, 4000), 1);
      assert.equal(ghostProgressAt(run.timeline, 6000), 1.5);
      assert.equal(ghostProgressAt(run.timeline, 8000), 2);
      assert.equal(ghostProgressAt(run.timeline, 48000), 12);
      assert.equal(ghostProgressAt(run.timeline, 500000), 12, "the ghost stays where it finished");
      assert.equal(ghostProgressAt(emptyTimeline(), 1000), 0);
    });

    test("ghost: playback never runs backwards", () => {
      const run = timeTrial();
      let previous = -1;
      for (let at = 0; at <= 60000; at += 137) {
        const value = ghostProgressAt(run.timeline, at);
        assert.ok(value >= previous, "went backwards at " + at);
        previous = value;
      }
    });

    test("ghost: ghostReachedAt names the moment a progress mark was passed", () => {
      const run = timeTrial();
      assert.equal(ghostReachedAt(run.timeline, 1), 4000);
      assert.equal(ghostReachedAt(run.timeline, 12), 48000);
      assert.equal(ghostReachedAt(run.timeline, 13), -1);
    });

    test("ghost: the lead is the gap between the ghost and the live kart", () => {
      const run = timeTrial();
      assert.equal(ghostLead(run.timeline, 20000, 5), 0);
      assert.equal(ghostLead(run.timeline, 20000, 3), 2);
      assert.equal(ghostLead(run.timeline, 20000, 7), -2);
    });

    // ---- eligibility ------------------------------------------------------

    test("ghost: only Time trial and Ghost are clean modes", () => {
      for (const mode of ["practice", "timeTrial", "ghost", "grandPrix"] as const) {
        const state = createRace({
          seed: 1,
          preset: "2-5",
          mode,
          racers: [{ id: "you", kind: "human" as const }],
        });
        assert.equal(isCleanMode(state), mode === "timeTrial" || mode === "ghost", mode);
      }
    });

    test("ghost: a Grand Prix never sets a record, however clean it was", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "you");
      assert.equal(racer(harness, "you").finished, true);
      assert.equal(isRecordEligible(harness.state), false);
      assert.equal(recordFromRace(harness.state, emptyTimeline()), null);
    });

    test("ghost: an unfinished run sets nothing", () => {
      const run = timeTrial();
      let state = createRace({
        seed: 2026,
        preset: "choose",
        chosenTables: [2],
        mode: "timeTrial",
        racers: [{ id: "you", kind: "human" as const }],
      });
      state = step(state, { kind: "start" }, 0).state;
      state = step(state, { kind: "answer", racerId: "you", value: factAnswer(state.racers[0]!.currentFact) }, 1000).state;
      assert.equal(isRecordEligible(state), false);
      assert.equal(isRecordEligible(run.state), true);
    });

    test("ghost: a run where any card was played sets nothing", () => {
      const run = timeTrial();
      assert.equal(isRecordEligible(run.state), true);
      const dirty = E.cloneState(run.state);
      dirty.racers[0]!.cardsUsed.push({ card: "nitro", targetId: "", at: 1000 });
      assert.equal(isRecordEligible(dirty), false, "only powerup-free runs count");
    });

    test("ghost: the record carries the time, the correct count, the attempts and the timeline", () => {
      const run = timeTrial();
      const record = recordFromRace(run.state, run.timeline)!;
      assert.deepEqual(
        Object.keys(record).sort(),
        ["attempted", "correct", "preset", "timeMs", "timeline"],
      );
      assert.equal(record.preset, "choose");
      assert.equal(record.timeMs, 48000);
      assert.equal(record.correct, 12);
      assert.equal(record.attempted, 12);
      assert.equal(record.timeline.samples.length, 12);
    });

    test("ghost: a Ghost run sets records too -- beat the ghost and the record updates", () => {
      const run = timeTrial(2026, "ghost");
      assert.equal(isRecordEligible(run.state), true);
      assert.equal(recordFromRace(run.state, run.timeline)!.timeMs, 48000);
    });

    // ---- the update rule --------------------------------------------------

    test("ghost: a tie keeps the old record", () => {
      const slow = timeTrial(2026, "timeTrial", 4000);
      const first = recordFromRace(slow.state, slow.timeline)!;
      const same = timeTrial(31337, "timeTrial", 4000);
      const second = recordFromRace(same.state, same.timeline)!;
      assert.equal(second.timeMs, first.timeMs, "the two runs really do tie");
      assert.equal(beatsRecord(first, second), false);
      const update = updateRecord(first, second);
      assert.equal(update.updated, false);
      assert.deepEqual(update.record, first, "the old record still stands");
      assert.deepEqual(bestRecord(first, second), first);
    });

    test("ghost: a faster run takes the record, by a single millisecond if that is all there is", () => {
      const slow = timeTrial(2026, "timeTrial", 4000);
      const first = recordFromRace(slow.state, slow.timeline)!;
      const faster = { ...first, timeMs: first.timeMs - 1, timeline: cloneTimeline(first.timeline) };
      assert.equal(beatsRecord(first, faster), true);
      const update = updateRecord(first, faster);
      assert.equal(update.updated, true);
      assert.equal(update.record.timeMs, first.timeMs - 1);
    });

    test("ghost: a slower run with more correct answers does not take the record", () => {
      const slow = timeTrial(2026, "timeTrial", 4000);
      const first = recordFromRace(slow.state, slow.timeline)!;
      const slower = {
        ...first,
        timeMs: first.timeMs + 1,
        correct: first.correct + 5,
        attempted: first.attempted + 5,
        timeline: cloneTimeline(first.timeline),
      };
      assert.equal(beatsRecord(first, slower), false);
      assert.equal(updateRecord(first, slower).record.timeMs, first.timeMs);
    });

    test("ghost: the first run always sets the record", () => {
      const run = timeTrial();
      const record = recordFromRace(run.state, run.timeline)!;
      assert.equal(beatsRecord(null, record), true);
      const update = updateRecord(null, record);
      assert.equal(update.updated, true);
      assert.deepEqual(update.record, record);
    });

    test("ghost: a fast run beats a slow one and the timeline travels with it", () => {
      const slow = timeTrial(2026, "timeTrial", 5000);
      const fast = timeTrial(2026, "timeTrial", 3000);
      const slowRecord = recordFromRace(slow.state, slow.timeline)!;
      const fastRecord = recordFromRace(fast.state, fast.timeline)!;
      assert.equal(slowRecord.timeMs, 60000);
      assert.equal(fastRecord.timeMs, 36000);
      const update = updateRecord(slowRecord, fastRecord);
      assert.equal(update.updated, true);
      assert.deepEqual(update.record.timeline, fast.timeline);
      assert.equal(
        effectiveProgress(fast.state.racers[0]!, fast.state.questionsPerLap),
        fast.timeline.samples[11]!.progress,
        "the last sample is where the kart actually finished",
      );
    });

    test("ghost: an updated record is a copy, not a view of the run that set it", () => {
      const run = timeTrial();
      const record = recordFromRace(run.state, run.timeline)!;
      const update = updateRecord(null, record);
      record.timeline.samples[0]!.progress = 999;
      record.timeMs = -1;
      assert.equal(update.record.timeline.samples[0]!.progress, 1);
      assert.notEqual(update.record.timeMs, -1);
    });

    test("ghost: the ghost of a previous best is replayable against a live run", () => {
      const best = timeTrial(2026, "timeTrial", 4000);
      const attempt = timeTrial(2026, "ghost", 3500);
      let ahead = 0;
      for (let index = 0; index < attempt.timeline.samples.length; index++) {
        const sample = attempt.timeline.samples[index]!;
        if (sample.progress > ghostProgressAt(best.timeline, sample.atMs)) ahead += 1;
      }
      assert.equal(ahead, attempt.timeline.samples.length, "the faster run is ahead throughout");
      assert.ok(
        recordFromRace(attempt.state, attempt.timeline)!.timeMs
          < recordFromRace(best.state, best.timeline)!.timeMs,
      );
    });
  });
}
