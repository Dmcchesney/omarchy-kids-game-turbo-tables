/**
 * Laps, decks and presets.
 *
 * A race is a sequence of laps and each lap is one table. Within a lap the
 * twelve facts of that table are shuffled by the seed. Extra questions forced by
 * an attack are drawn from facts missed in this race first and then from the
 * current lap's table.
 *
 * A fact is packed into one integer, `left * 100 + right`, so a deck is a plain
 * `number[]`: cheap to clone once per reducer call and cheap to compare in a
 * vector file.
 */

import { orderByFactHistory, type FactRecord } from "./history.ts";
import { forkRng, shuffle } from "./rng.ts";

export type Fact = number;

export const QUESTIONS_PER_LAP = 12;
export const TABLE_MIN = 1;
export const TABLE_MAX = 12;

export type PresetId = "2-5" | "2-10" | "1-12" | "choose";

export const PRESET_TABLES: Readonly<Record<Exclude<PresetId, "choose">, readonly number[]>> = {
  "2-5": [2, 3, 4, 5],
  "2-10": [2, 3, 4, 5, 6, 7, 8, 9, 10],
  "1-12": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
};

export const TABLE_NAMES: readonly string[] = [
  "",
  "THE ONES",
  "THE TWOS",
  "THE THREES",
  "THE FOURS",
  "THE FIVES",
  "THE SIXES",
  "THE SEVENS",
  "THE EIGHTS",
  "THE NINES",
  "THE TENS",
  "THE ELEVENS",
  "THE TWELVES",
];

export function packFact(left: number, right: number): Fact {
  return left * 100 + right;
}

export function factLeft(fact: Fact): number {
  return Math.floor(fact / 100);
}

export function factRight(fact: Fact): number {
  return fact % 100;
}

export function factAnswer(fact: Fact): number {
  return factLeft(fact) * factRight(fact);
}

export function factLabel(fact: Fact): string {
  return factLeft(fact) + " × " + factRight(fact);
}

export function tableName(table: number): string {
  return TABLE_NAMES[table] ?? "";
}

/**
 * `n x 1` through `n x 12`, in order, before any shuffle. The design's
 * "the twelve facts of that table".
 */
export function tableFacts(table: number): Fact[] {
  const facts: Fact[] = [];
  for (let right = 1; right <= QUESTIONS_PER_LAP; right++) facts.push(packFact(table, right));
  return facts;
}

/**
 * Resolve a preset into its laps. `choose` takes any subset of 1..12 and sorts
 * it ascending, per the design's "any subset, in ascending order".
 */
export function tablesForPreset(preset: PresetId, chosen?: readonly number[]): number[] {
  if (preset !== "choose") return PRESET_TABLES[preset].slice();
  const unique: number[] = [];
  for (const table of chosen ?? []) {
    const value = Math.floor(table);
    if (value < TABLE_MIN || value > TABLE_MAX) continue;
    if (unique.indexOf(value) === -1) unique.push(value);
  }
  unique.sort((left, right) => left - right);
  return unique.length > 0 ? unique : PRESET_TABLES["1-12"].slice();
}

export function questionCountForPreset(preset: PresetId, chosen?: readonly number[]): number {
  return tablesForPreset(preset, chosen).length * QUESTIONS_PER_LAP;
}

/**
 * The lap deck: the table's twelve facts, shuffled by the seed. Every racer in
 * the race is handed the same lap deck, which is what makes "a rival on lap
 * seven is answering sevens" honest and comparable.
 */
export function lapDeck(seed: number, lapIndex: number, table: number): Fact[] {
  return shuffle(forkRng(seed, "deck:" + lapIndex + ":" + table), tableFacts(table));
}

/**
 * Extra questions, for when an attack pushes a lap past its twelve facts.
 * Missed facts first, shuffled; then the lap's own table, shuffled. Both from
 * the seed, so an extra question is reproducible and is a reason to see the
 * missed fact again rather than a random tax.
 *
 * Design: "Deck generation is deterministic from the seed and the fact history."
 * The seed decides which facts are in the missed group and in what order; the
 * history then reorders that group weakest first, so an attack returns the fact
 * the child is least sure of. The lap's own table stays purely seeded, because
 * the design fixes it as "the twelve facts of that table ... shuffled by the
 * seed". `history` empty reproduces the seed-only order exactly.
 */
export function extraQuestions(
  seed: number,
  racerId: string,
  lapIndex: number,
  drawIndex: number,
  table: number,
  missed: readonly Fact[],
  history: readonly FactRecord[] = [],
): Fact[] {
  const label = "extra:" + racerId + ":" + lapIndex + ":" + drawIndex;
  const sortedMissed = missed.slice().sort((left, right) => left - right);
  const shuffledMissed = shuffle(forkRng(seed, label + ":missed"), sortedMissed);
  const fromMissed = orderByFactHistory(shuffledMissed, history);
  const fromTable = shuffle(forkRng(seed, label + ":table"), tableFacts(table));
  return fromMissed.concat(fromTable);
}
