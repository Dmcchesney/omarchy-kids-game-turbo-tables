import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { createRng, cloneRng, forkRng, nextFloat, nextInt, nextUint32, shuffle } = E;

    test("rng: xoshiro128** produces a known answer sequence for seed 1", () => {
      const rng = createRng(1);
      const drawn = [];
      for (let index = 0; index < 8; index++) drawn.push(nextUint32(rng));
      // Known answer, captured once and pinned. A change here changes every vector.
      assert.deepEqual(drawn, [
        393288148, 2174103013, 3814759091, 2092745082, 1865176206, 2179171167, 3207394750, 2858353069,
      ]);
    });

    test("rng: the same seed always gives the same stream", () => {
      const left = createRng(20260902);
      const right = createRng(20260902);
      for (let index = 0; index < 64; index++) {
        assert.equal(nextUint32(left), nextUint32(right));
      }
    });

    test("rng: different seeds give different streams", () => {
      const left = createRng(1);
      const right = createRng(2);
      let differences = 0;
      for (let index = 0; index < 32; index++) {
        if (nextUint32(left) !== nextUint32(right)) differences += 1;
      }
      assert.ok(differences > 30, "expected almost every draw to differ, got " + differences);
    });

    test("rng: a zero seed still produces a live generator", () => {
      const rng = createRng(0);
      const drawn = new Set<number>();
      for (let index = 0; index < 32; index++) drawn.add(nextUint32(rng));
      assert.ok(drawn.size > 1);
    });

    test("rng: every 32-bit draw is an unsigned integer", () => {
      const rng = createRng(7);
      for (let index = 0; index < 4096; index++) {
        const value = nextUint32(rng);
        assert.ok(Number.isInteger(value), "not an integer: " + value);
        assert.ok(value >= 0 && value <= 4294967295, "out of range: " + value);
      }
    });

    test("rng: nextFloat stays inside [0, 1)", () => {
      const rng = createRng(11);
      for (let index = 0; index < 4096; index++) {
        const value = nextFloat(rng);
        assert.ok(value >= 0 && value < 1, "out of range: " + value);
      }
    });

    test("rng: nextInt stays in range and covers every bucket", () => {
      const rng = createRng(13);
      const counts = new Array<number>(7).fill(0);
      for (let index = 0; index < 70000; index++) {
        const value = nextInt(rng, 7);
        assert.ok(value >= 0 && value < 7);
        counts[value] = counts[value]! + 1;
      }
      // Rejection sampling, so the buckets should be close to even.
      for (const count of counts) assert.ok(count > 9000 && count < 11000, "skewed bucket " + count);
    });

    test("rng: nextInt of one is always zero", () => {
      const rng = createRng(3);
      for (let index = 0; index < 16; index++) assert.equal(nextInt(rng, 1), 0);
    });

    test("rng: shuffle is a permutation and never mutates its input", () => {
      const source = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      const shuffled = shuffle(createRng(99), source);
      assert.deepEqual(source, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      assert.deepEqual(shuffled.slice().sort((left, right) => left - right), source);
      assert.notDeepEqual(shuffled, source);
    });

    test("rng: shuffle is deterministic for a seed", () => {
      const source = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
      assert.deepEqual(shuffle(createRng(5), source), shuffle(createRng(5), source));
    });

    test("rng: fork gives a labelled stream that ignores draw history", () => {
      const first = forkRng(42, "deck:0:2");
      const second = forkRng(42, "deck:0:2");
      const other = forkRng(42, "deck:1:3");
      assert.equal(nextUint32(first), nextUint32(second));
      assert.notEqual(nextUint32(forkRng(42, "deck:0:2")), nextUint32(other));
    });

    test("rng: fork streams are independent of one another", () => {
      const drained = forkRng(42, "a");
      for (let index = 0; index < 100; index++) nextUint32(drained);
      assert.equal(nextUint32(forkRng(42, "b")), nextUint32(forkRng(42, "b")));
    });

    test("rng: cloneRng copies the state without aliasing it", () => {
      const rng = createRng(17);
      const copy = cloneRng(rng);
      assert.equal(nextUint32(rng), nextUint32(copy));
      nextUint32(rng);
      assert.notDeepEqual(rng, copy);
    });
  });
}
