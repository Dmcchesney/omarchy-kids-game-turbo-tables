/**
 * Seeded randomness for the Turbo Tables engine.
 *
 * xoshiro128** with a splitmix32 seeding step. Every draw the engine ever makes
 * goes through this file, so a seed plus a history is a race. There is no use of
 * `Math.random` anywhere under `src/engine`.
 *
 * Target es2016: 32-bit integer maths only, no BigInt, no typed-array views that
 * the neutral esbuild platform would have to polyfill.
 */

export interface Rng {
  a: number;
  b: number;
  c: number;
  d: number;
}

function rotl(value: number, shift: number): number {
  return ((value << shift) | (value >>> (32 - shift))) >>> 0;
}

/** splitmix32: turns one 32-bit seed into a well-mixed stream of 32-bit words. */
function splitmix32(state: number): { value: number; state: number } {
  const next = (state + 0x9e3779b9) >>> 0;
  let z = next;
  z = Math.imul(z ^ (z >>> 16), 0x21f0aaad) >>> 0;
  z = Math.imul(z ^ (z >>> 15), 0x735a2d97) >>> 0;
  z = (z ^ (z >>> 15)) >>> 0;
  return { value: z, state: next };
}

/** FNV-1a over a label, so `fork` streams are named rather than positional. */
export function hashLabel(label: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < label.length; index++) {
    hash = (hash ^ label.charCodeAt(index)) >>> 0;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

export function createRng(seed: number): Rng {
  let state = seed >>> 0;
  const words: number[] = [];
  for (let index = 0; index < 4; index++) {
    const stepped = splitmix32(state);
    state = stepped.state;
    words.push(stepped.value);
  }
  const rng: Rng = { a: words[0]!, b: words[1]!, c: words[2]!, d: words[3]! };
  if ((rng.a | rng.b | rng.c | rng.d) === 0) rng.a = 1;
  return rng;
}

/**
 * An independent stream derived from a base seed and a label. Forks never touch
 * the parent, so a stream's output does not depend on how many draws some other
 * part of the engine happened to make first.
 */
export function forkRng(seed: number, label: string): Rng {
  return createRng(((seed >>> 0) ^ hashLabel(label)) >>> 0);
}

export function cloneRng(rng: Rng): Rng {
  return { a: rng.a, b: rng.b, c: rng.c, d: rng.d };
}

export function nextUint32(rng: Rng): number {
  const result = Math.imul(rotl(Math.imul(rng.b, 5) >>> 0, 7), 9) >>> 0;
  const t = (rng.b << 9) >>> 0;
  rng.c = (rng.c ^ rng.a) >>> 0;
  rng.d = (rng.d ^ rng.b) >>> 0;
  rng.b = (rng.b ^ rng.c) >>> 0;
  rng.a = (rng.a ^ rng.d) >>> 0;
  rng.c = (rng.c ^ t) >>> 0;
  rng.d = rotl(rng.d, 11);
  return result;
}

/** A float in [0, 1) with 32 bits of resolution. */
export function nextFloat(rng: Rng): number {
  return nextUint32(rng) / 4294967296;
}

/** An integer in [0, bound), rejection-sampled so the low values are not favoured. */
export function nextInt(rng: Rng, bound: number): number {
  if (bound <= 1) return 0;
  const limit = 4294967296 - (4294967296 % bound);
  let value = nextUint32(rng);
  while (value >= limit) value = nextUint32(rng);
  return value % bound;
}

/** Fisher-Yates, driven entirely by `nextInt`. Returns a new array. */
export function shuffle<T>(rng: Rng, values: readonly T[]): T[] {
  const result = values.slice();
  for (let index = result.length - 1; index > 0; index--) {
    const swap = nextInt(rng, index + 1);
    const held = result[index]!;
    result[index] = result[swap]!;
    result[swap] = held;
  }
  return result;
}
