/**
 * Ranking and the results headline.
 *
 * Design, Race format and results: "Ranking: finished before unfinished; among
 * finished, finish time; among unfinished, effective progress; then
 * correct-answer count; then fewer pit-crew answers."
 *
 * The last tiebreak is the racer's seat order, so the comparator is a total
 * order and two identical racers never rank nondeterministically.
 */

import { QUESTIONS_PER_LAP } from "./deck.ts";
import { effectiveProgress, type RacePosition } from "./progress.ts";

export interface Rankable extends RacePosition {
  id: string;
  seat: number;
  finished: boolean;
  finishTimeMs: number;
  correctCount: number;
  pitCrewCount: number;
}

export interface RankedRacer {
  id: string;
  place: number;
  finished: boolean;
  finishTimeMs: number;
  effectiveProgress: number;
  correctCount: number;
  pitCrewCount: number;
}

export type Headline = "VICTORY LAP" | "PODIUM FINISH" | "RACE COMPLETE";

export function compareRacers(
  left: Rankable,
  right: Rankable,
  questionsPerLap: number = QUESTIONS_PER_LAP,
): number {
  // finished before unfinished
  if (left.finished !== right.finished) return left.finished ? -1 : 1;
  // among finished, finish time
  if (left.finished && right.finished && left.finishTimeMs !== right.finishTimeMs) {
    return left.finishTimeMs - right.finishTimeMs;
  }
  // among unfinished, effective progress
  if (!left.finished) {
    const leftProgress = effectiveProgress(left, questionsPerLap);
    const rightProgress = effectiveProgress(right, questionsPerLap);
    if (leftProgress !== rightProgress) return rightProgress - leftProgress;
  }
  // then correct-answer count
  if (left.correctCount !== right.correctCount) return right.correctCount - left.correctCount;
  // then fewer pit-crew answers
  if (left.pitCrewCount !== right.pitCrewCount) return left.pitCrewCount - right.pitCrewCount;
  // then seat order, so the comparator is total and stable
  return left.seat - right.seat;
}

/** The finishing order, places numbered from one. */
export function rankRacers(
  racers: readonly Rankable[],
  questionsPerLap: number = QUESTIONS_PER_LAP,
): RankedRacer[] {
  const ordered = racers.slice().sort((left, right) => compareRacers(left, right, questionsPerLap));
  return ordered.map((racer, index) => ({
    id: racer.id,
    place: index + 1,
    finished: racer.finished,
    finishTimeMs: racer.finishTimeMs,
    effectiveProgress: effectiveProgress(racer, questionsPerLap),
    correctCount: racer.correctCount,
    pitCrewCount: racer.pitCrewCount,
  }));
}

/**
 * Ids in position order, for the live HUD and the pass callouts. Same order as
 * `rankRacers`, without building the result records, because this runs twice per
 * reducer call.
 */
export function positionOrder(
  racers: readonly Rankable[],
  questionsPerLap: number = QUESTIONS_PER_LAP,
): string[] {
  const ordered = racers.slice().sort((left, right) => compareRacers(left, right, questionsPerLap));
  const ids: string[] = [];
  for (const racer of ordered) ids.push(racer.id);
  return ids;
}

export function placeOf(
  racers: readonly Rankable[],
  racerId: string,
  questionsPerLap: number = QUESTIONS_PER_LAP,
): number {
  const order = positionOrder(racers, questionsPerLap);
  return order.indexOf(racerId) + 1;
}

/**
 * Design, Fairness: "The results screen has no bottom: it names the child's own
 * place and the top three, nothing else."
 *
 * `rankRacers` is the engine's ordering primitive and will happily tell you a
 * racer is 4th of 4, because the live HUD and the pass callouts need the whole
 * order. The results screen must not. `resultsBoard` is the shape the results
 * screen is allowed to read: the child's own place as a number, the headline for
 * it, and the podium. Nobody below third is ever enumerated.
 */
export const PODIUM_SIZE = 3;

export interface ResultsBoard {
  /** The child's own place. Named, never ranked against a visible bottom. */
  place: number;
  /** How many racers were in the race, so "2nd of 4" can be written. */
  total: number;
  /** Design, Results: "every finish is positive". */
  headline: Headline;
  /** The top three and nothing else. Shorter only if the race was smaller. */
  podium: RankedRacer[];
}

export function resultsBoard(
  racers: readonly Rankable[],
  racerId: string,
  questionsPerLap: number = QUESTIONS_PER_LAP,
): ResultsBoard {
  const ranked = rankRacers(racers, questionsPerLap);
  const own = ranked.find((entry) => entry.id === racerId);
  const place = own === undefined ? 0 : own.place;
  return {
    place,
    total: ranked.length,
    headline: headlineForPlace(place),
    podium: ranked.slice(0, PODIUM_SIZE),
  };
}

/** Design, Results: "every finish is positive". */
export function headlineForPlace(place: number): Headline {
  if (place === 1) return "VICTORY LAP";
  if (place === 2 || place === 3) return "PODIUM FINISH";
  return "RACE COMPLETE";
}

export function ordinal(place: number): string {
  const tens = place % 100;
  if (tens >= 11 && tens <= 13) return place + "th";
  const ones = place % 10;
  if (ones === 1) return place + "st";
  if (ones === 2) return place + "nd";
  if (ones === 3) return place + "rd";
  return place + "th";
}
