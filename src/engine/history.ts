/**
 * Fact history.
 *
 * Design, Laps decks presets: "Fact history is kept locally per fact: attempts,
 * correct, last three outcomes. It drives the mastery lamps in the garage and
 * the order of pit-lane re-asks. It does not change which laps a race contains:
 * the race is the table." And: "Deck generation is deterministic from the seed
 * and the fact history."
 *
 * This module owns the record and the ordering it implies. It owns no storage:
 * the engine is still a pure function of `(state, input, now)`. The load/save
 * seam is `RaceConfig.factHistory` in and `factHistoryOf` out — Piece 2's
 * `save.ts` fills both ends and nothing here ever touches a file.
 *
 * `compareByFactHistory` is a *partial* order on purpose: two facts the history
 * cannot tell apart compare equal, and each caller adds its own final tiebreak
 * so that the order it sorts by is total. Nothing in the engine may depend on
 * `Array.prototype.sort` being stable, because the shipping runtime is the QML
 * JavaScript engine and not V8.
 */

import type { Fact } from "./deck.ts";

/** What happened the last time a fact was asked. */
export type FactOutcome = "correct" | "wrong" | "reveal" | "pitCrew";

/** Design: "last three outcomes". */
export const FACT_HISTORY_WINDOW = 3;

export interface FactRecord {
  fact: Fact;
  /** Every time the fact was asked and answered, by any route. */
  attempts: number;
  /** How many of those were genuine correct answers. */
  correct: number;
  /** The last three outcomes, oldest first. */
  lastThree: FactOutcome[];
}

export function newFactRecord(fact: Fact): FactRecord {
  return { fact, attempts: 0, correct: 0, lastThree: [] };
}

export function cloneFactRecord(record: FactRecord): FactRecord {
  return {
    fact: record.fact,
    attempts: record.attempts,
    correct: record.correct,
    lastThree: record.lastThree.slice(),
  };
}

export function cloneFactHistory(history: readonly FactRecord[]): FactRecord[] {
  return history.map(cloneFactRecord);
}

/** The record for one fact, or null when the fact has never been asked. */
export function factRecordOf(history: readonly FactRecord[], fact: Fact): FactRecord | null {
  for (const record of history) if (record.fact === fact) return record;
  return null;
}

/**
 * File one outcome against one fact, in place, keeping the list ascending by
 * fact so the history is byte-identical whatever order the race asked in.
 */
export function recordFactOutcome(
  history: FactRecord[],
  fact: Fact,
  outcome: FactOutcome,
): FactRecord {
  let record = factRecordOf(history, fact);
  if (record === null) {
    record = newFactRecord(fact);
    let at = history.length;
    for (let index = 0; index < history.length; index++) {
      if (history[index]!.fact > fact) {
        at = index;
        break;
      }
    }
    history.splice(at, 0, record);
  }
  record.attempts += 1;
  if (outcome === "correct") record.correct += 1;
  record.lastThree.push(outcome);
  while (record.lastThree.length > FACT_HISTORY_WINDOW) record.lastThree.shift();
  return record;
}

/** How many of the last three outcomes were genuine correct answers. */
export function recentSuccesses(record: FactRecord | null): number {
  if (record === null) return 0;
  let count = 0;
  for (const outcome of record.lastThree) if (outcome === "correct") count += 1;
  return count;
}

/**
 * Weakest fact first, on the history alone.
 *
 * 1. fewer of the last three outcomes correct,
 * 2. then a lower lifetime correct/attempts ratio, compared by cross
 *    multiplication so no float ever reaches a vector,
 * 3. then more attempts, because a fact fought for longer is the one to return.
 *
 * Two facts the history cannot tell apart compare equal, deliberately: this is
 * a *partial* order and every caller supplies its own final tiebreak, so
 * nothing here ever depends on `Array.prototype.sort` being stable. The pit
 * lane falls back to the due answer and then the fact; a deck draw falls back
 * to the position the seed put the fact in.
 *
 * A fact with no record sorts as attempts 0, correct 0, no recent successes.
 */
export function compareByFactHistory(
  history: readonly FactRecord[],
  left: Fact,
  right: Fact,
): number {
  if (left === right) return 0;
  const leftRecord = factRecordOf(history, left);
  const rightRecord = factRecordOf(history, right);
  const leftRecent = recentSuccesses(leftRecord);
  const rightRecent = recentSuccesses(rightRecord);
  if (leftRecent !== rightRecent) return leftRecent - rightRecent;
  const leftAttempts = leftRecord === null ? 0 : leftRecord.attempts;
  const rightAttempts = rightRecord === null ? 0 : rightRecord.attempts;
  const leftCorrect = leftRecord === null ? 0 : leftRecord.correct;
  const rightCorrect = rightRecord === null ? 0 : rightRecord.correct;
  const leftRatio = leftCorrect * rightAttempts;
  const rightRatio = rightCorrect * leftAttempts;
  if (leftRatio !== rightRatio) return leftRatio - rightRatio;
  if (leftAttempts !== rightAttempts) return rightAttempts - leftAttempts;
  return 0;
}

/**
 * Reorder an already-seeded list weakest first.
 *
 * The seed decides the list; the history decides the order within it. The final
 * tiebreak is the position the seed put the fact in, so this is a total order
 * and the result is identical in every JavaScript engine.
 */
export function orderByFactHistory(
  facts: readonly Fact[],
  history: readonly FactRecord[],
): Fact[] {
  const decorated = facts.map((fact, position) => ({ fact, position }));
  decorated.sort((left, right) => {
    const byHistory = compareByFactHistory(history, left.fact, right.fact);
    if (byHistory !== 0) return byHistory;
    return left.position - right.position;
  });
  return decorated.map((entry) => entry.fact);
}
