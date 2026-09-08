// Plan, M1 gate: "a headless four-racer Grand Prix with scripted inputs replays
// identically."
//
// Round 1 spent 6.9 s of an 8.2 s suite replaying a pure function 10,000 times
// in one V8. That can only fail if V8 itself is broken, and it is not the claim
// the design makes. Design, Laps decks presets: "the multiplayer engine must
// reproduce them byte for byte" -- a *different runtime*. So the in-process
// replay is kept small and cheap here, and the claim that matters is measured
// by tests/bundle-qml, which replays every committed race vector through
// engine/engine.mjs under the QML JavaScript engine and diffs the JSON byte for
// byte against Node's.
//
// The script is the committed grand-prix-1-12 vector: 144 questions per racer,
// four racers, every card in play. Each replay is hashed and every hash must be
// the first one.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type * as EngineModule from "../../src/engine/index.ts";

const root = resolve(import.meta.dirname, "../..");
const races = JSON.parse(await readFile(resolve(root, "vectors/races.json"), "utf8"));
const vector = races.vectors.find((entry: any) => entry.name === "grand-prix-1-12-20260902");

/**
 * How many in-process replays. Enough to catch ambient state, iteration order
 * or a leaked reference; not a substitute for the cross-runtime gate.
 */
const REPLAYS = Number(process.env.TURBO_TABLES_REPLAYS ?? "25");

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { createRace, step } = E;

    function digestOf(seed: number): string {
      let state = createRace({
        seed,
        preset: vector.preset,
        mode: vector.mode,
        streakThreshold: vector.streakThreshold,
        schedule: vector.schedule,
        racers: vector.racers,
      });
      const hash = createHash("sha256");
      for (const entry of vector.inputs) {
        const result = step(state, entry.input, entry.at);
        state = result.state;
        if (result.events.length > 0) hash.update(JSON.stringify(result.events));
      }
      hash.update(JSON.stringify(state));
      return hash.digest("hex");
    }

    const runOnce = (): string => digestOf(vector.seed);

    test("determinism: a four-racer Grand Prix replays identically " + REPLAYS + " times", () => {
      const first = runOnce();
      for (let index = 1; index < REPLAYS; index++) {
        const again = runOnce();
        if (again !== first) assert.fail("replay " + index + " diverged: " + again + " != " + first);
      }
      assert.equal(first.length, 64);
    });

    test("determinism: the recorded expectation in races.json is that same digest", () => {
      const hash = createHash("sha256");
      let state = createRace({
        seed: vector.seed,
        preset: vector.preset,
        mode: vector.mode,
        streakThreshold: vector.streakThreshold,
        schedule: vector.schedule,
        racers: vector.racers,
      });
      const events: unknown[] = [];
      for (const entry of vector.inputs) {
        const result = step(state, entry.input, entry.at);
        state = result.state;
        if (result.events.length > 0) hash.update(JSON.stringify(result.events));
        for (const event of result.events) events.push(event);
      }
      hash.update(JSON.stringify(state));
      assert.deepEqual(events, vector.expected.events);
      assert.deepEqual(state, vector.expected.finalState);
      assert.equal(hash.digest("hex"), runOnce());
    });

    test("determinism: a different seed is a different race", () => {
      assert.notEqual(digestOf(vector.seed + 1), runOnce());
    });

    test("determinism: replaying from a fresh race leaves no trace in the one before it", () => {
      // The reducer clones; nothing is shared between two races of the same
      // seed, and nothing a first replay did can reach a second.
      const first = createRace({
        seed: vector.seed,
        preset: vector.preset,
        mode: vector.mode,
        streakThreshold: vector.streakThreshold,
        schedule: vector.schedule,
        racers: vector.racers,
      });
      const untouched = JSON.stringify(first);
      let state = first;
      for (const entry of vector.inputs.slice(0, 60)) state = step(state, entry.input, entry.at).state;
      assert.equal(JSON.stringify(first), untouched, "step never mutated the state it was given");
    });
  });
}
