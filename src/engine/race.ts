/**
 * The race: state, the reducer, and every rule that moves a kart.
 *
 * `step(state, input, now) -> { state, events }`. No timers, no input or output,
 * no randomness outside the seed carried in the state. The caller owns the
 * clock; the engine only ever reads the `now` it is handed and never lets it run
 * backwards.
 *
 * The lap, delta, floor, swap, shield and immunity rules are transcribed from
 * the bellringer runtime (advanceStudentLaps, applyQuestionDelta,
 * swapStudentPositions, ApplyPowerup). What the design changes is named at the
 * rule it changes.
 */

import { CARDS, CARD_SCHEDULE, applyFloor, dealHand, type Card } from "./cards.ts";
import {
  QUESTIONS_PER_LAP,
  extraQuestions,
  factAnswer,
  lapDeck,
  tableName,
  tablesForPreset,
  type Fact,
  type PresetId,
} from "./deck.ts";
import type { RaceEvent } from "./events.ts";
import {
  cloneFactHistory,
  compareByFactHistory,
  factRecordOf,
  recordFactOutcome,
  type FactOutcome,
  type FactRecord,
} from "./history.ts";
import { effectiveProgress, swapPositions } from "./progress.ts";
import { positionOrder, type Rankable } from "./rank.ts";
import { STREAK_THRESHOLD, shouldDealHand } from "./streak.ts";

export type RaceMode = "practice" | "timeTrial" | "ghost" | "grandPrix";

export type RaceStatus = "countdown" | "racing" | "settling" | "finished";

export type RacerKind = "human" | "rival";

/**
 * Presentation timings the design fixes. Each one is carried on the event it
 * belongs to, so the UI never has to know a number the engine already knows:
 * `sputterMs` on `wrong`, `revealMs` on `reveal`, `calloutMs` on `passed` and
 * `passedBy`, `settleMs` on the state. `NEXT_FACT_MS` is the one that has no
 * event of its own -- it is the gap *between* two questions, so it is asserted
 * by name in `answer loop 3` and read by the UI's question swap.
 */
/** Design, The answer loop 3: "the next fact appears within 250 ms". */
export const NEXT_FACT_MS = 250;
/** Design, The answer loop 4: "500 ms sputter". */
export const SPUTTER_MS = 500;
/** Design, The answer loop 5: "the correct answer is shown for 1500 ms". */
export const REVEAL_MS = 1500;
/** Design, The view: "Callouts for 1.6 s". */
export const CALLOUT_MS = 1600;
/** Design, Finish: "Rivals keep racing for up to fifteen seconds". */
export const SETTLE_MS = 15000;

/** A fact that was missed twice and is owed one return in the pit lane. */
export interface PitLaneEntry {
  fact: Fact;
  /** The lap it was missed on. An entry from an earlier lap is served first. */
  lap: number;
  /** Design, Pit lane: "three questions later in the same lap". */
  dueAtAnswer: number;
}

export interface UsedCard {
  card: Card;
  targetId: string;
  at: number;
}

export interface Racer extends Rankable {
  id: string;
  seat: number;
  kind: RacerKind;

  // the position triple, exactly the bellringer's three fields
  lapsComplete: number;
  correctInLap: number;
  questionsNeededThisLap: number;

  finished: boolean;
  finishTimeMs: number;
  place: number;

  streak: number;
  bestStreak: number;
  hand: Card[];
  rollCages: number;

  correctCount: number;
  wrongCount: number;
  pitCrewCount: number;
  revealCount: number;
  attemptCount: number;

  /** Locked field, from an unblocked Wrench, Pothole or Pile-Up. */
  stalledUntilMs: number;
  /** What the child has typed so far. Digits only, never a leading zero. */
  entry: string;
  /** Consecutive wrong answers on the fact currently being asked. */
  wrongOnCurrentFact: number;

  /** The fact being asked, or -1 when the racer has finished. */
  currentFact: Fact;
  /** True when `currentFact` came out of the pit lane rather than the deck. */
  currentFromPitLane: boolean;

  /** Remaining lap questions, head first. */
  queue: Fact[];
  /** How many times the lap queue has been filled: 0 is the lap deck itself. */
  queueDraws: number;
  /** Questions served this lap, which is what the pit lane counts against. */
  answersThisLap: number;
  pitLane: PitLaneEntry[];
  /** Every fact missed at least once this race, ascending. */
  missed: Fact[];
  /**
   * Design, Laps decks presets: "Fact history is kept locally per fact:
   * attempts, correct, last three outcomes." Ascending by fact. It orders the
   * pit-lane re-asks and the missed half of an extra-question draw. Persisting
   * it across races is Piece 2's `save.ts`; the engine only carries it.
   */
  factHistory: FactRecord[];
  cardsUsed: UsedCard[];
}

export interface RaceState {
  version: number;
  seed: number;
  mode: RaceMode;
  preset: PresetId;
  tables: number[];
  questionsPerLap: number;
  totalLaps: number;
  streakThreshold: number;
  powerupsEnabled: boolean;
  /**
   * How many wrong answers on one fact before the answer is revealed and the
   * race moves on. Two everywhere except Practice, where the design's Modes
   * table says "mistakes show the answer immediately".
   */
  revealAfterWrong: number;
  schedule: Card[];
  /** The one cursor every racer deals from. Design: "Shared round-robin". */
  cardCursor: number;
  settleMs: number;
  status: RaceStatus;
  startedAtMs: number;
  nowMs: number;
  settleUntilMs: number;
  finishedCount: number;
  humanId: string;
  racers: Racer[];
}

export interface RacerConfig {
  id: string;
  kind?: RacerKind;
}

export interface RaceConfig {
  seed: number;
  mode?: RaceMode;
  preset?: PresetId;
  chosenTables?: readonly number[];
  racers: readonly RacerConfig[];
  humanId?: string;
  streakThreshold?: number;
  powerupsEnabled?: boolean;
  schedule?: readonly Card[];
  settleMs?: number;
  startedAtMs?: number;
  /**
   * The load half of the fact-history seam. Piece 2's `save.ts` reads the saved
   * records off disk and hands them in here; `factHistoryOf` hands them back at
   * the end of the race. The engine itself never opens a file, and a race
   * created without this is exactly the race it was before the seam existed.
   */
  factHistory?: readonly FactRecord[];
}

export type RaceInput =
  | { kind: "start" }
  | { kind: "tick" }
  | { kind: "digit"; racerId?: string; value: number }
  | { kind: "backspace"; racerId?: string }
  | { kind: "submit"; racerId?: string }
  | { kind: "answer"; racerId?: string; value: number }
  | { kind: "hint"; racerId?: string }
  | { kind: "useCard"; racerId?: string; index: number; targetId?: string };

export interface StepResult {
  state: RaceState;
  events: RaceEvent[];
}

// ---------------------------------------------------------------------------
// construction
// ---------------------------------------------------------------------------

function newRacer(config: RacerConfig, seat: number, questionsPerLap: number): Racer {
  return {
    id: config.id,
    seat,
    kind: config.kind ?? "rival",
    lapsComplete: 0,
    correctInLap: 0,
    questionsNeededThisLap: questionsPerLap,
    finished: false,
    finishTimeMs: 0,
    place: 0,
    streak: 0,
    bestStreak: 0,
    hand: [],
    rollCages: 0,
    correctCount: 0,
    wrongCount: 0,
    pitCrewCount: 0,
    revealCount: 0,
    attemptCount: 0,
    stalledUntilMs: 0,
    entry: "",
    wrongOnCurrentFact: 0,
    currentFact: -1,
    currentFromPitLane: false,
    queue: [],
    queueDraws: 0,
    answersThisLap: 0,
    pitLane: [],
    missed: [],
    factHistory: [],
    cardsUsed: [],
  };
}

export function createRace(config: RaceConfig): RaceState {
  const preset = config.preset ?? "1-12";
  const tables = tablesForPreset(preset, config.chosenTables);
  const mode = config.mode ?? "grandPrix";
  const racers = config.racers.map((racer, seat) => newRacer(racer, seat, QUESTIONS_PER_LAP));
  const humanId = config.humanId ?? racers.find((racer) => racer.kind === "human")?.id ?? racers[0]?.id ?? "";
  const state: RaceState = {
    version: 1,
    seed: config.seed >>> 0,
    mode,
    preset,
    tables,
    questionsPerLap: QUESTIONS_PER_LAP,
    totalLaps: tables.length,
    streakThreshold: config.streakThreshold ?? STREAK_THRESHOLD,
    powerupsEnabled: config.powerupsEnabled ?? mode === "grandPrix",
    revealAfterWrong: mode === "practice" ? 1 : 2,
    schedule: (config.schedule ?? CARD_SCHEDULE).slice(),
    cardCursor: 0,
    settleMs: config.settleMs ?? SETTLE_MS,
    status: "countdown",
    startedAtMs: config.startedAtMs ?? 0,
    nowMs: config.startedAtMs ?? 0,
    settleUntilMs: 0,
    finishedCount: 0,
    humanId,
    racers,
  };
  if (config.factHistory !== undefined) {
    const human = racerById(state, humanId);
    if (human !== null) human.factHistory = cloneFactHistory(config.factHistory);
  }
  for (const racer of state.racers) refreshQuestion(state, racer);
  return state;
}

/**
 * The save half of the fact-history seam: the human's records, ready for Piece
 * 2 to merge into the save file. Returns a copy, so a caller cannot reach into
 * a live race.
 */
export function factHistoryOf(state: RaceState): FactRecord[] {
  const human = racerById(state, state.humanId);
  return human === null ? [] : cloneFactHistory(human.factHistory);
}

/** The record for one fact, for the garage's mastery lamps. */
export function factHistoryEntry(racer: Racer, fact: Fact): FactRecord | null {
  return factRecordOf(racer.factHistory, fact);
}

export function cloneRacer(racer: Racer): Racer {
  return {
    id: racer.id,
    seat: racer.seat,
    kind: racer.kind,
    lapsComplete: racer.lapsComplete,
    correctInLap: racer.correctInLap,
    questionsNeededThisLap: racer.questionsNeededThisLap,
    finished: racer.finished,
    finishTimeMs: racer.finishTimeMs,
    place: racer.place,
    streak: racer.streak,
    bestStreak: racer.bestStreak,
    hand: racer.hand.slice(),
    rollCages: racer.rollCages,
    correctCount: racer.correctCount,
    wrongCount: racer.wrongCount,
    pitCrewCount: racer.pitCrewCount,
    revealCount: racer.revealCount,
    attemptCount: racer.attemptCount,
    stalledUntilMs: racer.stalledUntilMs,
    entry: racer.entry,
    wrongOnCurrentFact: racer.wrongOnCurrentFact,
    currentFact: racer.currentFact,
    currentFromPitLane: racer.currentFromPitLane,
    queue: racer.queue.slice(),
    queueDraws: racer.queueDraws,
    answersThisLap: racer.answersThisLap,
    pitLane: racer.pitLane.map((entry) => ({
      fact: entry.fact,
      lap: entry.lap,
      dueAtAnswer: entry.dueAtAnswer,
    })),
    missed: racer.missed.slice(),
    factHistory: cloneFactHistory(racer.factHistory),
    cardsUsed: racer.cardsUsed.map((used) => ({
      card: used.card,
      targetId: used.targetId,
      at: used.at,
    })),
  };
}

export function cloneState(state: RaceState): RaceState {
  return {
    version: state.version,
    seed: state.seed,
    mode: state.mode,
    preset: state.preset,
    tables: state.tables.slice(),
    questionsPerLap: state.questionsPerLap,
    totalLaps: state.totalLaps,
    streakThreshold: state.streakThreshold,
    powerupsEnabled: state.powerupsEnabled,
    revealAfterWrong: state.revealAfterWrong,
    schedule: state.schedule.slice(),
    cardCursor: state.cardCursor,
    settleMs: state.settleMs,
    status: state.status,
    startedAtMs: state.startedAtMs,
    nowMs: state.nowMs,
    settleUntilMs: state.settleUntilMs,
    finishedCount: state.finishedCount,
    humanId: state.humanId,
    racers: state.racers.map(cloneRacer),
  };
}

// ---------------------------------------------------------------------------
// reads
// ---------------------------------------------------------------------------

export function racerById(state: RaceState, racerId: string): Racer | null {
  for (const racer of state.racers) if (racer.id === racerId) return racer;
  return null;
}

export function humanRacer(state: RaceState): Racer {
  return racerById(state, state.humanId) ?? state.racers[0]!;
}

/** The table this racer is on, 1..12. Zero once they have finished. */
export function currentTable(state: RaceState, racer: Racer): number {
  return state.tables[racer.lapsComplete] ?? 0;
}

export function currentTableName(state: RaceState, racer: Racer): string {
  return tableName(currentTable(state, racer));
}

export function isStalled(racer: Racer, now: number): boolean {
  return now < racer.stalledUntilMs;
}

export function racerProgress(state: RaceState, racer: Racer): number {
  return effectiveProgress(racer, state.questionsPerLap);
}

export function raceOrder(state: RaceState): string[] {
  return positionOrder(state.racers, state.questionsPerLap);
}

export function accuracyPercent(racer: Racer): number {
  if (racer.attemptCount === 0) return 0;
  return Math.round((racer.correctCount / racer.attemptCount) * 100);
}

// ---------------------------------------------------------------------------
// the question queue: lap deck, extras, pit lane
// ---------------------------------------------------------------------------

function fillQueue(state: RaceState, racer: Racer): void {
  const table = currentTable(state, racer);
  if (table === 0) {
    racer.queue = [];
    return;
  }
  if (racer.queueDraws === 0) {
    racer.queue = lapDeck(state.seed, racer.lapsComplete, table);
  } else {
    racer.queue = extraQuestions(
      state.seed,
      racer.id,
      racer.lapsComplete,
      racer.queueDraws,
      table,
      racer.missed,
      racer.factHistory,
    );
  }
  racer.queueDraws += 1;
}

/**
 * Which pit-lane entry, of the ones that are due, comes back first.
 *
 * Design, Pit lane: "a fact missed twice returns once, three questions later in
 * the same lap, or at the start of the next lap if the lap is nearly over" --
 * so an entry carried over from an earlier lap is overdue and outranks one that
 * has only just come due. Design, Laps decks presets: fact history "drives ...
 * the order of pit-lane re-asks" -- so among entries of the same standing the
 * weakest fact comes back first. The last two tiebreaks make the order total.
 */
function pickPitLaneEntry(racer: Racer): PitLaneEntry | null {
  let best: PitLaneEntry | null = null;
  let bestCarriedOver = false;
  for (const entry of racer.pitLane) {
    const carriedOver = entry.lap < racer.lapsComplete;
    const dueThisLap = entry.lap === racer.lapsComplete && racer.answersThisLap >= entry.dueAtAnswer;
    if (!carriedOver && !dueThisLap) continue;
    if (best === null) {
      best = entry;
      bestCarriedOver = carriedOver;
      continue;
    }
    if (carriedOver !== bestCarriedOver) {
      if (carriedOver) {
        best = entry;
        bestCarriedOver = true;
      }
      continue;
    }
    const byHistory = compareByFactHistory(racer.factHistory, entry.fact, best.fact);
    if (byHistory < 0) {
      best = entry;
      bestCarriedOver = carriedOver;
      continue;
    }
    if (byHistory > 0) continue;
    if (entry.dueAtAnswer < best.dueAtAnswer) {
      best = entry;
      bestCarriedOver = carriedOver;
      continue;
    }
    if (entry.dueAtAnswer === best.dueAtAnswer && entry.fact < best.fact) {
      best = entry;
      bestCarriedOver = carriedOver;
    }
  }
  return best;
}

/**
 * Pick the fact to ask next.
 *
 * A new fact is a new question. `wrongOnCurrentFact` and the typed entry belong
 * to the fact that was showing, not to the racer, so both are cleared whenever
 * this installs a different fact. Without that, a lap completed by a boost or a
 * position taken by a Tow Hook carries a stale first-wrong forward and the
 * child's *first* mistake on an unrelated fact is revealed and filed in the pit
 * lane -- which would break "The answer loop" 4 and 5 and Fairness's "A wrong
 * answer costs only the streak".
 */
function refreshQuestion(state: RaceState, racer: Racer): void {
  const previousFact = racer.currentFact;
  if (racer.finished) {
    racer.currentFact = -1;
    racer.currentFromPitLane = false;
  } else {
    const entry = pickPitLaneEntry(racer);
    if (entry !== null) {
      racer.currentFact = entry.fact;
      racer.currentFromPitLane = true;
    } else {
      if (racer.queue.length === 0) fillQueue(state, racer);
      racer.currentFact = racer.queue.length > 0 ? racer.queue[0]! : -1;
      racer.currentFromPitLane = false;
    }
  }
  // A belt, not a guard, and it is worth saying so rather than leaving it to
  // look like defence that works. Every path that reaches here having changed
  // the fact has already zeroed both fields: `consumeQuestion` on every answered
  // question, `startLap` on every lap boundary and on both sides of a Tow Hook.
  // The one path that arrives with a live counter -- an attack landing on a
  // racer who has missed the showing fact once -- either completes a lap (and
  // `startLap` clears it) or leaves the same fact showing (and this branch does
  // not fire). So no test can distinguish this reset from its absence, and none
  // claims to; see the round 3 report's "What is not covered". It stays because
  // the invariant belongs to the fact and not to any one caller.
  if (racer.currentFact !== previousFact) {
    racer.wrongOnCurrentFact = 0;
    racer.entry = "";
  }
}

function consumeQuestion(racer: Racer): void {
  if (racer.currentFromPitLane) {
    for (let index = 0; index < racer.pitLane.length; index++) {
      if (racer.pitLane[index]!.fact === racer.currentFact) {
        racer.pitLane.splice(index, 1);
        break;
      }
    }
  } else if (racer.queue.length > 0 && racer.queue[0] === racer.currentFact) {
    racer.queue.shift();
  }
  racer.answersThisLap += 1;
  racer.wrongOnCurrentFact = 0;
  racer.entry = "";
}

/**
 * A fresh lap: a fresh queue, and a fresh question. The wrong-answer counter and
 * the typed entry belong to the fact that was showing, and that fact is about to
 * be replaced, so neither survives the lap boundary.
 *
 * This is the reset that does the work: `refreshQuestion`'s only fires when the
 * new fact differs from the old one, and a pit-lane entry filed on the lap just
 * finished is carried over and re-installed unchanged, so across that boundary
 * this is the only thing that clears the counter. `tests/engine/answer-loop.spec.ts`,
 * "a lap boundary clears the wrong counter even when the new lap opens on the
 * SAME fact", is the test that fails if this line goes.
 */
function startLap(racer: Racer): void {
  racer.queue = [];
  racer.queueDraws = 0;
  racer.answersThisLap = 0;
  racer.wrongOnCurrentFact = 0;
  racer.entry = "";
}

function rememberMissed(racer: Racer, fact: Fact): void {
  if (racer.missed.indexOf(fact) === -1) racer.missed.push(fact);
}

/** Design: "Fact history is kept locally per fact: attempts, correct, last
 * three outcomes." Every answered question files exactly one outcome. */
function fileOutcome(racer: Racer, fact: Fact, outcome: FactOutcome): void {
  if (fact < 0) return;
  recordFactOutcome(racer.factHistory, fact, outcome);
}

// ---------------------------------------------------------------------------
// laps and finishing
// ---------------------------------------------------------------------------

/**
 * Transcribed from the runtime's `advanceStudentLaps`, including the order of
 * the three statements inside the loop and the discard of the surplus on the
 * finishing lap.
 */
function advanceLaps(state: RaceState, racer: Racer, at: number, events: RaceEvent[]): void {
  while (racer.correctInLap >= racer.questionsNeededThisLap && !racer.finished) {
    const table = currentTable(state, racer);
    racer.correctInLap -= racer.questionsNeededThisLap;
    racer.lapsComplete += 1;
    racer.questionsNeededThisLap = state.questionsPerLap;
    startLap(racer);
    events.push({
      type: "lapComplete",
      at,
      racerId: racer.id,
      lapsComplete: racer.lapsComplete,
      table,
      surplus: racer.correctInLap,
    });
    if (racer.lapsComplete >= state.totalLaps) {
      racer.finished = true;
      racer.finishTimeMs = at;
      racer.correctInLap = 0;
      state.finishedCount += 1;
      racer.place = state.finishedCount;
      events.push({
        type: "finished",
        at,
        racerId: racer.id,
        place: racer.place,
        finishTimeMs: at,
      });
    }
  }
}

/**
 * Go's `applyQuestionDelta`: floor at one, no ceiling, then re-check the lap.
 * The `hit` event is pushed between the two halves so the ordering guarantee
 * holds: the effect first, then whatever lap it completed.
 */
function applyQuestionDelta(
  state: RaceState,
  attacker: Racer,
  victim: Racer,
  card: Card,
  at: number,
  events: RaceEvent[],
): void {
  const definition = CARDS[card];
  victim.questionsNeededThisLap = applyFloor(
    victim.questionsNeededThisLap,
    definition.questionDelta,
  );
  const stallMs = attacker.id === victim.id ? 0 : definition.stallMs;
  if (stallMs > 0) victim.stalledUntilMs = at + stallMs;
  events.push({
    type: "hit",
    at,
    racerId: victim.id,
    fromId: attacker.id,
    card,
    questionDelta: definition.questionDelta,
    questionsNeededThisLap: victim.questionsNeededThisLap,
    stallMs,
  });
  advanceLaps(state, victim, at, events);
  refreshQuestion(state, victim);
}

// ---------------------------------------------------------------------------
// answers
// ---------------------------------------------------------------------------

function dealIfCharged(state: RaceState, racer: Racer, at: number, events: RaceEvent[]): void {
  if (!state.powerupsEnabled) return;
  if (racer.finished) return;
  if (!shouldDealHand(racer.streak, state.streakThreshold, racer.hand.length)) return;
  const schedule = state.schedule.length > 0 ? state.schedule : CARD_SCHEDULE;
  const dealt = dealHand(schedule, state.cardCursor);
  state.cardCursor = dealt.cursor;
  racer.hand = dealt.hand;
  racer.streak = 0;
  events.push({
    type: "handDealt",
    at,
    racerId: racer.id,
    hand: dealt.hand.slice(),
    cursorAfter: dealt.cursor,
  });
}

function canAnswer(state: RaceState, racer: Racer, at: number): boolean {
  if (state.status !== "racing" && state.status !== "settling") return false;
  if (racer.finished) return false;
  if (racer.currentFact < 0) return false;
  if (isStalled(racer, at)) return false;
  return true;
}

/** A correct, genuine answer. */
function answerCorrect(state: RaceState, racer: Racer, at: number, events: RaceEvent[]): void {
  const fact = racer.currentFact;
  racer.attemptCount += 1;
  racer.correctCount += 1;
  racer.correctInLap += 1;
  racer.streak += 1;
  if (racer.streak > racer.bestStreak) racer.bestStreak = racer.streak;
  fileOutcome(racer, fact, "correct");
  consumeQuestion(racer);
  events.push({
    type: "correct",
    at,
    racerId: racer.id,
    fact,
    answer: factAnswer(fact),
    streak: racer.streak,
    correctInLap: racer.correctInLap,
    questionsNeededThisLap: racer.questionsNeededThisLap,
  });
  advanceLaps(state, racer, at, events);
  dealIfCharged(state, racer, at, events);
  refreshQuestion(state, racer);
}

/**
 * A wrong answer.
 *
 * Design, Pillars: "Mistakes cost the streak, never the position." The first
 * wrong on a fact resets the streak and leaves the fact where it is. The second
 * reveals and advances, per the settled decision "Second wrong answer - Reveal
 * and advance." A revealed answer counts for progress but does not build the
 * streak, which is already zero.
 */
function answerWrong(
  state: RaceState,
  racer: Racer,
  given: number,
  at: number,
  events: RaceEvent[],
): void {
  const fact = racer.currentFact;
  racer.attemptCount += 1;
  racer.wrongCount += 1;
  racer.streak = 0;
  racer.wrongOnCurrentFact += 1;
  racer.entry = "";
  rememberMissed(racer, fact);
  if (racer.wrongOnCurrentFact < state.revealAfterWrong) {
    fileOutcome(racer, fact, "wrong");
    events.push({
      type: "wrong",
      at,
      racerId: racer.id,
      fact,
      given,
      wrongOnThisFact: racer.wrongOnCurrentFact,
      sputterMs: SPUTTER_MS,
    });
    return;
  }
  fileOutcome(racer, fact, "reveal");
  racer.revealCount += 1;
  racer.correctInLap += 1;
  const lap = racer.lapsComplete;
  consumeQuestion(racer);
  // Design, Pit lane: "three questions later in the same lap" -- three further
  // questions are served, and the fourth is the fact coming back.
  racer.pitLane.push({ fact, lap, dueAtAnswer: racer.answersThisLap + 3 });
  events.push({ type: "reveal", at, racerId: racer.id, fact, answer: factAnswer(fact), revealMs: REVEAL_MS });
  advanceLaps(state, racer, at, events);
  // No deal here. Design, Streaks and the powerup hand: "the next *correct
  // answer* after the hand is spent deals a new one". A revealed answer is not
  // a correct answer, and the streak it would have to spend is already zero.
  refreshQuestion(state, racer);
}

/**
 * Pit crew. Design, The answer loop: "press H at any time and the answer is
 * shown, the question counts for progress, and the streak neither grows nor
 * resets. It is always available."
 */
function answerPitCrew(state: RaceState, racer: Racer, at: number, events: RaceEvent[]): void {
  const fact = racer.currentFact;
  racer.attemptCount += 1;
  racer.pitCrewCount += 1;
  racer.correctInLap += 1;
  fileOutcome(racer, fact, "pitCrew");
  consumeQuestion(racer);
  events.push({ type: "pitCrew", at, racerId: racer.id, fact, answer: factAnswer(fact) });
  advanceLaps(state, racer, at, events);
  // No deal here either. Design, Streaks and the powerup hand: "Pit-crew answers
  // do not reset it and do not count toward it", and the hand is dealt by "the
  // next correct answer after the hand is spent". A pit-crew press at full
  // charge with an empty hand must deal nothing.
  refreshQuestion(state, racer);
}

function submitAnswer(
  state: RaceState,
  racer: Racer,
  value: number,
  at: number,
  events: RaceEvent[],
): void {
  if (!canAnswer(state, racer, at)) return;
  if (value === factAnswer(racer.currentFact)) answerCorrect(state, racer, at, events);
  else answerWrong(state, racer, value, at, events);
}

// ---------------------------------------------------------------------------
// cards
// ---------------------------------------------------------------------------

function attackOne(
  state: RaceState,
  attacker: Racer,
  victim: Racer,
  card: Card,
  at: number,
  events: RaceEvent[],
): void {
  if (victim.rollCages > 0) {
    // Design: "Roll Cages stack without limit and each absorbs exactly one
    // incoming attack. A blocked attack does nothing and costs the attacker
    // their hand anyway." The hand is already gone by the time we get here.
    victim.rollCages -= 1;
    events.push({
      type: "blocked",
      at,
      racerId: victim.id,
      fromId: attacker.id,
      card,
      rollCagesLeft: victim.rollCages,
    });
    return;
  }
  if (card === "towHook") {
    // Design: "Tow Hook swaps position outright: laps complete, correct in lap,
    // and questions needed, both ways. Roll Cages stay with their owners. A Tow
    // Hook can never finish a race for anyone" -- which is why no lap check runs
    // after the swap, matching the runtime's `swapStudentPositions`.
    swapPositions(attacker, victim);
    startLap(attacker);
    startLap(victim);
    refreshQuestion(state, attacker);
    refreshQuestion(state, victim);
    events.push({ type: "swap", at, racerId: attacker.id, withId: victim.id });
    return;
  }
  applyQuestionDelta(state, attacker, victim, card, at, events);
}

function playCard(
  state: RaceState,
  racer: Racer,
  index: number,
  targetId: string,
  at: number,
  events: RaceEvent[],
): void {
  if (!state.powerupsEnabled) return;
  if (state.status !== "racing" && state.status !== "settling") return;
  // Design, Fairness: "A finished racer is out of reach and out of the fight."
  if (racer.finished) return;
  if (index < 0 || index >= racer.hand.length) return;
  const card = racer.hand[index]!;
  const definition = CARDS[card];

  let target: Racer | null = null;
  if (definition.scope === "targeted") {
    if (targetId === "" || targetId === racer.id) return;
    target = racerById(state, targetId);
    if (target === null || target.finished) return;
  } else if (targetId !== "") {
    return;
  }

  const discarded: Card[] = [];
  for (let held = 0; held < racer.hand.length; held++) {
    if (held !== index) discarded.push(racer.hand[held]!);
  }
  // Design: "Using a powerup costs the whole hand." The runtime empties the
  // inventory before it resolves anything, so a blocked attack still costs it.
  racer.hand = [];
  racer.cardsUsed.push({ card, targetId, at });
  events.push({ type: "cardUsed", at, racerId: racer.id, card, targetId, discarded });

  if (card === "rollCage") {
    racer.rollCages += 1;
    return;
  }
  if (definition.scope === "self") {
    // Design: "Boosts can complete laps instantly ... and any surplus carries
    // into the next." Self boosts never stall their owner.
    applyQuestionDelta(state, racer, racer, card, at, events);
    return;
  }
  if (definition.scope === "aoe") {
    // Design: "Oil Slick hits every racer except the attacker, checking and
    // consuming each victim's Roll Cage separately", and a finished racer
    // "cannot be attacked, by anything, including Oil Slick".
    for (const victim of state.racers) {
      if (victim.id === racer.id || victim.finished) continue;
      attackOne(state, racer, victim, card, at, events);
    }
    return;
  }
  attackOne(state, racer, target!, card, at, events);
}

// ---------------------------------------------------------------------------
// typing
// ---------------------------------------------------------------------------

function typeDigit(
  state: RaceState,
  racer: Racer,
  value: number,
  at: number,
  events: RaceEvent[],
): void {
  if (!canAnswer(state, racer, at)) return;
  if (value < 0 || value > 9) return;
  // Design: "Leading zeros and stray characters are simply not accepted into the
  // field, so '07' cannot happen."
  if (racer.entry === "" && value === 0) return;
  const expected = String(factAnswer(racer.currentFact));
  if (racer.entry.length >= expected.length) return;
  racer.entry += String(value);
  // "Submit ... automatically when the digit count matches the answer."
  if (racer.entry.length === expected.length) {
    const typed = Number(racer.entry);
    submitAnswer(state, racer, typed, at, events);
  }
}

// ---------------------------------------------------------------------------
// status
// ---------------------------------------------------------------------------

function allFinished(state: RaceState): boolean {
  if (state.racers.length === 0) return false;
  for (const racer of state.racers) if (!racer.finished) return false;
  return true;
}

function advanceStatus(state: RaceState, at: number): void {
  if (state.status === "countdown" || state.status === "finished") return;
  const human = humanRacer(state);
  if (state.status === "racing" && human.finished) {
    // Design, Finish: the child's last correct answer of the last lap ends the
    // race in Time trial and Ghost; in a Grand Prix the rivals keep racing for
    // up to fifteen seconds so the final order settles.
    if (state.mode === "grandPrix" && state.settleMs > 0 && !allFinished(state)) {
      state.status = "settling";
      state.settleUntilMs = at + state.settleMs;
    } else {
      state.status = "finished";
    }
  }
  if (state.status === "settling" && (allFinished(state) || at >= state.settleUntilMs)) {
    state.status = "finished";
  }
  if (state.status === "racing" && allFinished(state)) state.status = "finished";
}

function passEvents(
  state: RaceState,
  before: string[],
  at: number,
  events: RaceEvent[],
): void {
  const after = raceOrder(state);
  const humanId = state.humanId;
  const beforeHuman = before.indexOf(humanId);
  const afterHuman = after.indexOf(humanId);
  if (beforeHuman < 0 || afterHuman < 0) return;
  for (const racer of state.racers) {
    if (racer.id === humanId) continue;
    const wasAhead = before.indexOf(racer.id) < beforeHuman;
    const isAhead = after.indexOf(racer.id) < afterHuman;
    if (wasAhead && !isAhead)
      events.push({ type: "passed", at, racerId: humanId, otherId: racer.id, calloutMs: CALLOUT_MS });
    else if (!wasAhead && isAhead)
      events.push({
        type: "passedBy",
        at,
        racerId: humanId,
        otherId: racer.id,
        calloutMs: CALLOUT_MS,
      });
  }
}

// ---------------------------------------------------------------------------
// the reducer
// ---------------------------------------------------------------------------

export function step(state: RaceState, input: RaceInput, now: number): StepResult {
  const next = cloneState(state);
  const events: RaceEvent[] = [];
  // The clock never runs backwards, whatever the caller hands in.
  const at = now > next.nowMs ? now : next.nowMs;
  next.nowMs = at;
  const before = raceOrder(next);

  if (input.kind === "start") {
    if (next.status === "countdown") {
      next.status = "racing";
      next.startedAtMs = at;
    }
  } else if (input.kind !== "tick") {
    const racerId = input.racerId ?? next.humanId;
    const racer = racerById(next, racerId);
    if (racer !== null) {
      if (input.kind === "digit") typeDigit(next, racer, input.value, at, events);
      else if (input.kind === "backspace") {
        if (canAnswer(next, racer, at)) racer.entry = racer.entry.slice(0, -1);
      }
      else if (input.kind === "submit") {
        if (racer.entry !== "") submitAnswer(next, racer, Number(racer.entry), at, events);
      } else if (input.kind === "answer") submitAnswer(next, racer, input.value, at, events);
      else if (input.kind === "hint") {
        if (canAnswer(next, racer, at)) answerPitCrew(next, racer, at, events);
      } else if (input.kind === "useCard")
        playCard(next, racer, input.index, input.targetId ?? "", at, events);
    }
  }

  advanceStatus(next, at);
  passEvents(next, before, at, events);
  return { state: next, events };
}

/** Run a script of inputs from a fresh race. Used by the vectors and the tests. */
export interface ScriptedInput {
  input: RaceInput;
  at: number;
}

export function replay(
  config: RaceConfig,
  script: readonly ScriptedInput[],
): { state: RaceState; events: RaceEvent[] } {
  let state = createRace(config);
  const events: RaceEvent[] = [];
  for (const entry of script) {
    const result = step(state, entry.input, entry.at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }
  return { state, events };
}
