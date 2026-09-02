/**
 * Effective progress: where a kart actually is.
 *
 * Design, Powerups: "Position is effective progress: laps complete x 12, plus
 * correct this lap, minus however many questions this lap's requirement exceeds
 * twelve." The same expression as the bellringer client's
 * `computeStudentRaceProgress`, which is why a Pile-Up shoves a kart backwards
 * the instant it lands and why the kart creeps forward again as the victim
 * answers.
 */

import { QUESTIONS_PER_LAP } from "./deck.ts";

/** The triple a Tow Hook swaps, and the only three numbers position depends on. */
export interface RacePosition {
  lapsComplete: number;
  correctInLap: number;
  questionsNeededThisLap: number;
}

export function positionTriple(position: RacePosition): RacePosition {
  return {
    lapsComplete: position.lapsComplete,
    correctInLap: position.correctInLap,
    questionsNeededThisLap: position.questionsNeededThisLap,
  };
}

/** Swap the full triple, both ways. Nothing else moves with it. */
export function swapPositions(left: RacePosition, right: RacePosition): void {
  const held = positionTriple(left);
  left.lapsComplete = right.lapsComplete;
  left.correctInLap = right.correctInLap;
  left.questionsNeededThisLap = right.questionsNeededThisLap;
  right.lapsComplete = held.lapsComplete;
  right.correctInLap = held.correctInLap;
  right.questionsNeededThisLap = held.questionsNeededThisLap;
}

export function effectiveProgress(
  position: RacePosition,
  questionsPerLap: number = QUESTIONS_PER_LAP,
): number {
  const needed =
    position.questionsNeededThisLap > 0 ? position.questionsNeededThisLap : questionsPerLap;
  return (
    position.lapsComplete * questionsPerLap + position.correctInLap - (needed - questionsPerLap)
  );
}

/** Total questions in the race, used to draw the minimap loop. */
export function raceLength(totalLaps: number, questionsPerLap: number = QUESTIONS_PER_LAP): number {
  return totalLaps * questionsPerLap;
}

/** 0..1 along the circuit, clamped, for the track view and the minimap. */
export function progressFraction(
  position: RacePosition,
  totalLaps: number,
  questionsPerLap: number = QUESTIONS_PER_LAP,
): number {
  const length = raceLength(totalLaps, questionsPerLap);
  if (length <= 0) return 0;
  const value = effectiveProgress(position, questionsPerLap) / length;
  return Math.max(0, Math.min(1, value));
}
