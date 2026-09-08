/**
 * The event union and the ordering guarantee.
 *
 * Every rule change the engine makes emits exactly one event, and the UI never
 * re-derives a rule: it animates and sounds the events it is handed. The union
 * is closed — `RaceEventType` is the complete list from the implementation plan.
 */

import type { Card } from "./cards.ts";
import type { Fact } from "./deck.ts";

export type Signal = "niceRun" | "goodGame" | "goodLuck" | "soClose";

export const SIGNAL_CATALOG: readonly Signal[] = ["goodLuck", "niceRun", "soClose", "goodGame"];

export type RaceEventType =
  | "correct"
  | "wrong"
  | "reveal"
  | "pitCrew"
  | "lapComplete"
  | "handDealt"
  | "cardUsed"
  | "hit"
  | "blocked"
  | "swap"
  | "passed"
  | "passedBy"
  | "finished"
  | "signal";

/** A correct, genuine answer. Builds the streak. */
export interface CorrectEvent {
  type: "correct";
  at: number;
  racerId: string;
  fact: Fact;
  answer: number;
  streak: number;
  correctInLap: number;
  questionsNeededThisLap: number;
}

/** A wrong answer. Costs the streak and nothing else; the fact stays. */
export interface WrongEvent {
  type: "wrong";
  at: number;
  racerId: string;
  fact: Fact;
  given: number;
  wrongOnThisFact: number;
  /** Design, The answer loop 4: "500 ms sputter". How long the kart coughs. */
  sputterMs: number;
}

/** Second wrong on the same fact: show the answer, count it, move on. */
export interface RevealEvent {
  type: "reveal";
  at: number;
  racerId: string;
  fact: Fact;
  answer: number;
  revealMs: number;
}

/** Pit crew (the `H` key). Counts for progress; the streak neither grows nor resets. */
export interface PitCrewEvent {
  type: "pitCrew";
  at: number;
  racerId: string;
  fact: Fact;
  answer: number;
}

export interface LapCompleteEvent {
  type: "lapComplete";
  at: number;
  racerId: string;
  lapsComplete: number;
  table: number;
  surplus: number;
}

export interface HandDealtEvent {
  type: "handDealt";
  at: number;
  racerId: string;
  hand: Card[];
  cursorAfter: number;
}

export interface CardUsedEvent {
  type: "cardUsed";
  at: number;
  racerId: string;
  card: Card;
  targetId: string;
  discarded: Card[];
}

/** An effect that landed: an attack that was not blocked, or a self boost. */
export interface HitEvent {
  type: "hit";
  at: number;
  racerId: string;
  fromId: string;
  card: Card;
  questionDelta: number;
  questionsNeededThisLap: number;
  stallMs: number;
}

/** An attack a Roll Cage absorbed. Nothing happened to the victim's lap. */
export interface BlockedEvent {
  type: "blocked";
  at: number;
  racerId: string;
  fromId: string;
  card: Card;
  rollCagesLeft: number;
}

export interface SwapEvent {
  type: "swap";
  at: number;
  racerId: string;
  withId: string;
}

/** Design, The view: "Callouts for 1.6 s". `PASSED BOLT`. */
export interface PassedEvent {
  type: "passed";
  at: number;
  racerId: string;
  otherId: string;
  calloutMs: number;
}

/** `BOLT SLIPPED PAST`, held for the same 1.6 s. */
export interface PassedByEvent {
  type: "passedBy";
  at: number;
  racerId: string;
  otherId: string;
  calloutMs: number;
}

export interface FinishedEvent {
  type: "finished";
  at: number;
  racerId: string;
  place: number;
  finishTimeMs: number;
}

export interface SignalEvent {
  type: "signal";
  at: number;
  racerId: string;
  signal: Signal;
}

export type RaceEvent =
  | CorrectEvent
  | WrongEvent
  | RevealEvent
  | PitCrewEvent
  | LapCompleteEvent
  | HandDealtEvent
  | CardUsedEvent
  | HitEvent
  | BlockedEvent
  | SwapEvent
  | PassedEvent
  | PassedByEvent
  | FinishedEvent
  | SignalEvent;

/**
 * Ordering guarantee for the events of one `step`:
 *
 *   1. the answer or card event that caused the step (`correct`, `wrong`,
 *      `reveal`, `pitCrew`, `cardUsed`),
 *   2. the effects it had on racers, in racer order (`hit`, `blocked`, `swap`),
 *   3. lap and finish consequences, per racer, in racer order (`lapComplete`
 *      then `finished`),
 *   4. `handDealt` if the answer charged a hand,
 *   5. `passed` / `passedBy` for the human racer, last, because the callouts
 *      describe the state the rest of the step left behind.
 *
 * `EVENT_ORDER` gives the rank of each type so a test can assert it.
 */
export const EVENT_ORDER: Readonly<Record<RaceEventType, number>> = {
  correct: 0,
  wrong: 0,
  reveal: 0,
  pitCrew: 0,
  cardUsed: 0,
  hit: 1,
  blocked: 1,
  swap: 1,
  lapComplete: 2,
  finished: 3,
  handDealt: 4,
  signal: 5,
  passed: 6,
  passedBy: 6,
};

export function isEventOrdered(events: readonly RaceEvent[]): boolean {
  let seen = -1;
  for (const event of events) {
    const rank = EVENT_ORDER[event.type];
    if (rank < seen) return false;
    seen = rank;
  }
  return true;
}
