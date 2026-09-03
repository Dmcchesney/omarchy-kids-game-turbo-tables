/**
 * The three AI rivals.
 *
 * Design, AI rivals: "three karts with names, colors, and a simple, seeded model
 * of a child at the keyboard." Everything in this file is a function of the race
 * seed and the race state, so a Grand Prix is replayable and every rival
 * decision is a test vector.
 *
 * The engine stays a reducer. Nothing here holds a clock, opens a file or calls
 * `Math.random`. `rivalStep(state, rivals, now)` is a second reducer layered on
 * the first: it decides which `RaceInput`s the rivals would have produced by
 * `now` and hands them to `step` one at a time, in due-time order, so a rival
 * answer is exactly the same input a child's keystroke would have been.
 *
 * The two halves the caller wires up:
 *
 *   - `rivalObserve(rivals, state, events)` watches the events of a step the
 *     caller made (the child's answers) and returns the signals the rivals send
 *     back. It is what keeps the rubber band fed.
 *   - `rivalStep(state, rivals, now)` runs the rivals up to `now`, observing its
 *     own events as it goes.
 */

import { CARDS, type Card } from "./cards.ts";
import { QUESTIONS_PER_LAP, factAnswer, factLeft, factRight, type Fact } from "./deck.ts";
import type { RaceEvent, Signal, SignalEvent } from "./events.ts";
import { effectiveProgress } from "./progress.ts";
import { racerById, step, type RaceState, type Racer } from "./race.ts";
import { positionOrder } from "./rank.ts";
import { cloneRng, forkRng, nextFloat, nextInt, type Rng } from "./rng.ts";

// ---------------------------------------------------------------------------
// the table, verbatim
// ---------------------------------------------------------------------------

export type RivalPersonality = "bolt" | "piston" | "gasket";

export type RivalLevel = "rookie" | "pro" | "champion";

export interface RivalProfile {
  personality: RivalPersonality;
  /** The name on the kart. There is no name field anywhere; these are fixed. */
  label: string;
  /** Design, AI rivals: the "Personality" column. */
  temperament: string;
  /** Design: the Pro accuracy, in whole percentage points. */
  accuracyPercent: number;
  /** Design: the Pro think-time mean, in milliseconds. */
  thinkTimeMeanMs: number;
  /**
   * Design: the "±" half of "mean ± spread", in milliseconds. Read as the half
   * width of the draw: a rival's think time is drawn from a symmetric
   * distribution on [mean − spread, mean + spread] and never leaves it, so the
   * two numbers in the design's table are the two ends of the range.
   */
  thinkTimeSpreadMs: number;
}

/**
 * Design, AI rivals:
 *
 *   Bolt    fast, sloppy    84%   2.8 s ± 0.9
 *   Piston  steady          91%   3.4 s ± 0.7
 *   Gasket  careful, slow   96%   4.6 s ± 1.0
 */
export const RIVAL_PROFILES: Readonly<Record<RivalPersonality, RivalProfile>> = {
  bolt: {
    personality: "bolt",
    label: "Bolt",
    temperament: "fast, sloppy",
    accuracyPercent: 84,
    thinkTimeMeanMs: 2800,
    thinkTimeSpreadMs: 900,
  },
  piston: {
    personality: "piston",
    label: "Piston",
    temperament: "steady",
    accuracyPercent: 91,
    thinkTimeMeanMs: 3400,
    thinkTimeSpreadMs: 700,
  },
  gasket: {
    personality: "gasket",
    label: "Gasket",
    temperament: "careful, slow",
    accuracyPercent: 96,
    thinkTimeMeanMs: 4600,
    thinkTimeSpreadMs: 1000,
  },
};

/** Design, Decisions: "Rival count -- Three everywhere." */
export const RIVAL_ORDER: readonly RivalPersonality[] = ["bolt", "piston", "gasket"];

export interface RivalLevelAdjustment {
  level: RivalLevel;
  /** The badge on the roster slot. */
  label: string;
  /** Design: "Rookie multiplies think time by 1.5 ... Champion multiplies by 0.75". */
  thinkTimeScale: number;
  /** Design: "subtracts 8 points of accuracy" / "adds 3". */
  accuracyDelta: number;
}

/** Design, AI rivals: "Those are the Pro numbers." */
export const RIVAL_LEVELS: Readonly<Record<RivalLevel, RivalLevelAdjustment>> = {
  rookie: { level: "rookie", label: "ROOKIE", thinkTimeScale: 1.5, accuracyDelta: -8 },
  pro: { level: "pro", label: "PRO", thinkTimeScale: 1, accuracyDelta: 0 },
  champion: { level: "champion", label: "CHAMPION", thinkTimeScale: 0.75, accuracyDelta: 3 },
};

export const RIVAL_LEVEL_ORDER: readonly RivalLevel[] = ["rookie", "pro", "champion"];

/** Design, AI rivals: "scales by up to ±15% toward the child's rolling pace". */
export const RUBBER_BAND_LIMIT = 0.15;

/** Design, AI rivals: "without ever letting a rival answer faster than 1.5 s". */
export const RIVAL_FLOOR_MS = 1500;

/** Design, AI rivals: "the child's rolling pace over the last twelve answers". */
export const RIVAL_PACE_WINDOW = 12;

/** Design, Rival play policy: "re-evaluated every three answers while it is held". */
export const POLICY_INTERVAL = 3;

/** Design, Rival play policy: "behind the leader by more than half a lap". */
export const HALF_LAP = QUESTIONS_PER_LAP / 2;

/**
 * Design, AI rivals: "Rivals send preset signals **occasionally**."
 *
 * The clean lap is the design's trigger; this is the design's *frequency*, and
 * the design gives it no number, so one is chosen here and named. One in three
 * turns a clean twelve-lap race from twelve NICE RUNs -- a signal at the end of
 * every single lap, which no reader would call occasional -- into about four.
 * It is drawn from `RivalsState.rng`, the same seeded stream that picks the
 * speaker, so "everything the rivals do is derived from the race seed" holds.
 */
export const NICE_RUN_CHANCE = 1 / 3;

/**
 * The cards the policy treats as a boost. Membership is all that is ever
 * consulted -- `choosePlay` spends the first boost in hand order, not the
 * first in this list -- so the order here carries no meaning.
 */
export const BOOST_CARDS: readonly Card[] = ["turbo", "nitro"];

/**
 * The cards the policy treats as an attack, and therefore the cards the mercy
 * rules govern. Oil Slick is in the list even though it takes no target: it
 * lands on every other racer, so "never attack the racer in last place" has to
 * be read against everybody it would reach.
 */
export const ATTACK_CARDS: readonly Card[] = ["pileUp", "pothole", "wrench", "oilSlick", "towHook"];

export function isAttackCard(card: Card): boolean {
  return ATTACK_CARDS.indexOf(card) !== -1;
}

// ---------------------------------------------------------------------------
// the numbers a level produces
// ---------------------------------------------------------------------------

export interface RivalTuning {
  personality: RivalPersonality;
  level: RivalLevel;
  accuracyPercent: number;
  thinkTimeMeanMs: number;
  thinkTimeSpreadMs: number;
}

export function rivalTuning(personality: RivalPersonality, level: RivalLevel): RivalTuning {
  const profile = RIVAL_PROFILES[personality];
  const adjust = RIVAL_LEVELS[level];
  const accuracy = profile.accuracyPercent + adjust.accuracyDelta;
  return {
    personality,
    level,
    accuracyPercent: accuracy < 0 ? 0 : accuracy > 100 ? 100 : accuracy,
    thinkTimeMeanMs: Math.round(profile.thinkTimeMeanMs * adjust.thinkTimeScale),
    thinkTimeSpreadMs: Math.round(profile.thinkTimeSpreadMs * adjust.thinkTimeScale),
  };
}

/**
 * The rubber band.
 *
 * Design: "Each rival's think time scales by up to ±15% toward the child's
 * rolling pace over the last twelve answers." The scale is the ratio between
 * the child's pace and the rival's own mean, clamped to [0.85, 1.15]; a child
 * slower than the rival pulls the rival up, a faster child pulls it down, and
 * neither ever moves it further than the fifteen points the design allows. With
 * no pace yet -- before the child's first answer -- the scale is exactly 1.
 */
export function rubberBandScale(childPaceMs: number, meanMs: number): number {
  if (childPaceMs <= 0 || meanMs <= 0) return 1;
  const ratio = childPaceMs / meanMs;
  if (ratio > 1 + RUBBER_BAND_LIMIT) return 1 + RUBBER_BAND_LIMIT;
  if (ratio < 1 - RUBBER_BAND_LIMIT) return 1 - RUBBER_BAND_LIMIT;
  return ratio;
}

/**
 * One think-time draw.
 *
 * Symmetric and triangular on [centre − spread, centre + spread]: the sum of
 * two uniform draws minus one. Bounded on purpose, so "2.8 s ± 0.9" means a
 * rival never takes eight seconds over a fact, and the mean of the draw is the
 * mean in the design's table.
 *
 * The floor is applied last and to the drawn value, because the design's
 * promise is about the answer -- "without ever letting a rival answer faster
 * than 1.5 s" -- and not about the mean it was drawn from.
 */
export function drawThinkTime(
  rng: Rng,
  meanMs: number,
  spreadMs: number,
  scale: number,
): { drawnMs: number; thinkMs: number } {
  const centre = meanMs * scale;
  const spread = spreadMs * scale;
  const wobble = nextFloat(rng) + nextFloat(rng) - 1;
  const drawnMs = Math.round(centre + spread * wobble);
  return { drawnMs, thinkMs: drawnMs < RIVAL_FLOOR_MS ? RIVAL_FLOOR_MS : drawnMs };
}

/** The gap a rival actually waits, floor applied. */
export function drawThinkTimeMs(
  rng: Rng,
  meanMs: number,
  spreadMs: number,
  scale: number,
): number {
  return drawThinkTime(rng, meanMs, spreadMs, scale).thinkMs;
}

/** True when this draw comes out correct at the given accuracy. */
export function drawsCorrect(rng: Rng, accuracyPercent: number): boolean {
  return nextFloat(rng) * 100 < accuracyPercent;
}

/**
 * A wrong answer a child might actually give: a neighbouring row or column of
 * the table, or an off-by-one. Never the right answer, never zero or negative.
 */
export function drawWrongAnswer(rng: Rng, fact: Fact): number {
  const answer = factAnswer(fact);
  const left = factLeft(fact);
  const right = factRight(fact);
  const candidates = [
    answer + left,
    answer - left,
    answer + right,
    answer - right,
    answer + 1,
    answer - 1,
  ];
  const start = nextInt(rng, candidates.length);
  for (let index = 0; index < candidates.length; index++) {
    const value = candidates[(start + index) % candidates.length]!;
    if (value > 0 && value !== answer) return value;
  }
  return answer + 1;
}

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------

export interface RivalConfig {
  /** The racer id in the race. */
  id: string;
  personality: RivalPersonality;
  level: RivalLevel;
}

export interface RivalMind {
  id: string;
  personality: RivalPersonality;
  level: RivalLevel;
  accuracyPercent: number;
  thinkTimeMeanMs: number;
  thinkTimeSpreadMs: number;
  /** This rival's own stream, forked from the race seed and its id. */
  rng: Rng;
  /** When the next answer is due. */
  nextAnswerAtMs: number;
  /** The last draw before the 1.5 s floor, so a test can see the floor bite. */
  lastDrawnThinkMs: number;
  /** The gap actually used. Never below `RIVAL_FLOOR_MS`. */
  lastThinkMs: number;
  /** The rubber-band scale the last draw used. Always within ±15%. */
  lastScale: number;
  answersTaken: number;
  /** Answers since the play policy last looked at the hand this rival holds. */
  answersSincePolicy: number;
  /** Whether the hand this rival last spent landed on the child. */
  lastHandAttackedHuman: boolean;
}

export interface RivalsState {
  humanId: string;
  minds: RivalMind[];
  /** Gaps between the child's last twelve answers, oldest first. */
  childGaps: number[];
  childLastAnswerAtMs: number;
  childAnswers: number;
  /** Wrong and revealed answers on the child's current lap. */
  childLapMistakes: number;
  /** Laps of the child's that have already offered a NICE RUN. */
  niceRunLaps: number[];
  /** True once the race's one GOOD GAME has gone. */
  sentGoodGame: boolean;
  /** The stream that picks which rival speaks. Separate from every mind. */
  rng: Rng;
}

export function cloneMind(mind: RivalMind): RivalMind {
  return {
    id: mind.id,
    personality: mind.personality,
    level: mind.level,
    accuracyPercent: mind.accuracyPercent,
    thinkTimeMeanMs: mind.thinkTimeMeanMs,
    thinkTimeSpreadMs: mind.thinkTimeSpreadMs,
    rng: cloneRng(mind.rng),
    nextAnswerAtMs: mind.nextAnswerAtMs,
    lastDrawnThinkMs: mind.lastDrawnThinkMs,
    lastThinkMs: mind.lastThinkMs,
    lastScale: mind.lastScale,
    answersTaken: mind.answersTaken,
    answersSincePolicy: mind.answersSincePolicy,
    lastHandAttackedHuman: mind.lastHandAttackedHuman,
  };
}

export function cloneRivals(rivals: RivalsState): RivalsState {
  return {
    humanId: rivals.humanId,
    minds: rivals.minds.map(cloneMind),
    childGaps: rivals.childGaps.slice(),
    childLastAnswerAtMs: rivals.childLastAnswerAtMs,
    childAnswers: rivals.childAnswers,
    childLapMistakes: rivals.childLapMistakes,
    niceRunLaps: rivals.niceRunLaps.slice(),
    sentGoodGame: rivals.sentGoodGame,
    rng: cloneRng(rivals.rng),
  };
}

/**
 * Build the rivals for a race that has already started, so the first think time
 * is measured from the moment the countdown ended.
 */
export function createRivals(state: RaceState, configs: readonly RivalConfig[]): RivalsState {
  const rivals: RivalsState = {
    humanId: state.humanId,
    minds: [],
    childGaps: [],
    childLastAnswerAtMs: 0,
    childAnswers: 0,
    childLapMistakes: 0,
    niceRunLaps: [],
    sentGoodGame: false,
    rng: forkRng(state.seed, "rivals:signals"),
  };
  for (const config of configs) {
    const tuning = rivalTuning(config.personality, config.level);
    const mind: RivalMind = {
      id: config.id,
      personality: config.personality,
      level: config.level,
      accuracyPercent: tuning.accuracyPercent,
      thinkTimeMeanMs: tuning.thinkTimeMeanMs,
      thinkTimeSpreadMs: tuning.thinkTimeSpreadMs,
      rng: forkRng(state.seed, "rival:" + config.id + ":" + config.personality + ":" + config.level),
      nextAnswerAtMs: state.startedAtMs,
      lastDrawnThinkMs: 0,
      lastThinkMs: 0,
      lastScale: 1,
      answersTaken: 0,
      answersSincePolicy: 0,
      lastHandAttackedHuman: false,
    };
    schedule(rivals, mind, state.startedAtMs);
    rivals.minds.push(mind);
  }
  return rivals;
}

export function mindOf(rivals: RivalsState, racerId: string): RivalMind | null {
  for (const mind of rivals.minds) if (mind.id === racerId) return mind;
  return null;
}

/** The child's rolling pace, or 0 before the child has answered anything. */
export function childPaceMs(rivals: RivalsState): number {
  if (rivals.childGaps.length === 0) return 0;
  let total = 0;
  for (const gap of rivals.childGaps) total += gap;
  return total / rivals.childGaps.length;
}

function schedule(rivals: RivalsState, mind: RivalMind, fromMs: number): void {
  const scale = rubberBandScale(childPaceMs(rivals), mind.thinkTimeMeanMs);
  const drawn = drawThinkTime(mind.rng, mind.thinkTimeMeanMs, mind.thinkTimeSpreadMs, scale);
  mind.lastScale = scale;
  mind.lastDrawnThinkMs = drawn.drawnMs;
  mind.lastThinkMs = drawn.thinkMs;
  mind.nextAnswerAtMs = fromMs + drawn.thinkMs;
}

// ---------------------------------------------------------------------------
// standings, and the two mercy rules
// ---------------------------------------------------------------------------

export interface RivalStanding {
  id: string;
  progress: number;
  finished: boolean;
}

/** Every racer's effective progress, in seat order. */
export function standings(state: RaceState): RivalStanding[] {
  const rows: RivalStanding[] = [];
  for (const racer of state.racers) {
    rows.push({
      id: racer.id,
      progress: effectiveProgress(racer, state.questionsPerLap),
      finished: racer.finished,
    });
  }
  return rows;
}

/**
 * Design, Rival play policy: "never attack a racer who is in last place."
 *
 * Last place is read by effective progress, the design's own definition of
 * position, and every racer tied at the lowest progress is last -- which is
 * stricter than naming one kart, and is the reading the fairness gate measures.
 */
export function lastPlaceIds(state: RaceState): string[] {
  const rows = standings(state);
  if (rows.length === 0) return [];
  let lowest = rows[0]!.progress;
  for (const row of rows) if (row.progress < lowest) lowest = row.progress;
  const ids: string[] = [];
  for (const row of rows) if (row.progress === lowest) ids.push(row.id);
  return ids;
}

/**
 * Whether this rival may land an attack on this racer right now.
 *
 * Both mercy rules and the two rules the engine already enforces: never itself,
 * never a finished racer.
 */
export function mayAttack(
  state: RaceState,
  mind: RivalMind,
  victimId: string,
  last: readonly string[],
): boolean {
  if (victimId === mind.id) return false;
  const victim = racerById(state, victimId);
  if (victim === null || victim.finished) return false;
  if (last.indexOf(victimId) !== -1) return false;
  // Design: "Never attack the child twice with consecutive hands."
  if (victimId === state.humanId && mind.lastHandAttackedHuman) return false;
  return true;
}

/** Everyone an Oil Slick would reach: every racer but the attacker, unfinished. */
export function aoeVictims(state: RaceState, attackerId: string): string[] {
  const ids: string[] = [];
  for (const racer of state.racers) {
    if (racer.id === attackerId || racer.finished) continue;
    ids.push(racer.id);
  }
  return ids;
}

// ---------------------------------------------------------------------------
// the play policy
// ---------------------------------------------------------------------------

export type PolicyRule = "boost" | "rollCage" | "attack";

export interface RivalPlayChoice {
  /** Index into the rival's hand, which is what `useCard` takes. */
  index: number;
  card: Card;
  /** "" for the cards that take no target. */
  targetId: string;
  rule: PolicyRule;
}

function handIndexOf(racer: Racer, card: Card): number {
  return racer.hand.indexOf(card);
}

/**
 * Design, Rival play policy, in the order the design writes it:
 *
 *   - Holding a boost while behind the leader by more than half a lap: use it.
 *   - Holding a Roll Cage with none active while in first or second: use it.
 *   - Holding an attack: target the current leader if it is not itself;
 *     otherwise the closest kart behind.
 *
 * The design fixes the rules and their order. It says nothing about which card
 * a hand holding two of a kind should spend, so neither does this: **the first
 * matching card in hand order goes**, for boosts and for attacks alike. A hand
 * of `["nitro", "turbo"]` plays Nitro; a hand of `["towHook", "pileUp"]` plays
 * the Tow Hook. Hand order is itself seeded -- it is the shared round-robin
 * cursor -- so this is a deterministic rule and not an accident, and it invents
 * no ordering the design does not have. (An earlier draft of this comment
 * claimed Turbo before Nitro and largest-question-delta first. The code never
 * did either.)
 *
 * Returns null when nothing in the hand applies, or when the mercy rules leave
 * an attack with nobody it is allowed to reach. The hand is then held and the
 * policy looks again three answers later, which is what the design says it does.
 */
export function choosePlay(state: RaceState, mind: RivalMind): RivalPlayChoice | null {
  const racer = racerById(state, mind.id);
  if (racer === null || racer.finished || racer.hand.length === 0) return null;
  if (!state.powerupsEnabled) return null;

  const order = positionOrder(state.racers, state.questionsPerLap);
  const own = effectiveProgress(racer, state.questionsPerLap);
  const leaderId = order.length > 0 ? order[0]! : "";
  const leader = leaderId === "" ? null : racerById(state, leaderId);
  const leaderProgress = leader === null ? own : effectiveProgress(leader, state.questionsPerLap);

  // 1. a boost, when more than half a lap behind the leader
  if (leaderProgress - own > HALF_LAP) {
    for (let index = 0; index < racer.hand.length; index++) {
      const card = racer.hand[index]!;
      if (BOOST_CARDS.indexOf(card) !== -1) return { index, card, targetId: "", rule: "boost" };
    }
  }

  // 2. a Roll Cage with none active, in first or second
  const place = order.indexOf(mind.id) + 1;
  if (racer.rollCages === 0 && (place === 1 || place === 2)) {
    const index = handIndexOf(racer, "rollCage");
    if (index >= 0) return { index, card: "rollCage", targetId: "", rule: "rollCage" };
  }

  // 3. an attack
  const last = lastPlaceIds(state);
  for (let index = 0; index < racer.hand.length; index++) {
    const card = racer.hand[index]!;
    if (!isAttackCard(card)) continue;
    if (CARDS[card].scope === "aoe") {
      // Oil Slick has no target, so every racer it would reach has to pass.
      const victims = aoeVictims(state, mind.id);
      if (victims.length === 0) continue;
      let legal = true;
      for (const victimId of victims) {
        if (!mayAttack(state, mind, victimId, last)) {
          legal = false;
          break;
        }
      }
      if (legal) return { index, card, targetId: "", rule: "attack" };
      continue;
    }
    const targetId = chooseTarget(state, mind, order, last);
    if (targetId !== "") return { index, card, targetId, rule: "attack" };
  }
  return null;
}

/**
 * Design: "target the current leader if it is not itself; otherwise the closest
 * kart behind." Applied over the racers the mercy rules leave available, so the
 * prohibitions narrow the field and the design's rule then picks from it.
 * "Closest behind" is the next kart down the position order that is available.
 */
export function chooseTarget(
  state: RaceState,
  mind: RivalMind,
  order: readonly string[],
  last: readonly string[],
): string {
  const leaderId = order.length > 0 ? order[0]! : "";
  if (leaderId !== "" && leaderId !== mind.id && mayAttack(state, mind, leaderId, last)) {
    return leaderId;
  }
  const ownIndex = order.indexOf(mind.id);
  if (ownIndex >= 0) {
    for (let index = ownIndex + 1; index < order.length; index++) {
      const candidate = order[index]!;
      if (mayAttack(state, mind, candidate, last)) return candidate;
    }
  }
  return "";
}

// ---------------------------------------------------------------------------
// signals
// ---------------------------------------------------------------------------

/**
 * Design, AI rivals: "Rivals send preset signals **occasionally**: a NICE RUN
 * when the child completes a lap with no mistakes, a GOOD GAME at the finish.
 * From the same four-signal catalog as the multiplayer lobby."
 *
 * A mistake is a wrong answer or a revealed one. A pit-crew answer is not a
 * mistake: the design's answer loop says the streak "neither grows nor resets",
 * and a child who asked the pit crew still drove a clean lap.
 *
 * Three words in that sentence set the frequency, and each is read here:
 *
 *   - **"occasionally"** is the only frequency the design gives, and it gives
 *     no number. A clean lap therefore *offers* a NICE RUN and one goes with
 *     probability `NICE_RUN_CHANCE`, drawn from the signal stream. Twelve clean
 *     laps send about four signals rather than twelve. A chance is the smallest
 *     mechanism that makes the word true, and it needs no new state: the
 *     stream that already picks the speaker draws it.
 *   - **"a NICE RUN"**, singular: one rival speaks, not the field.
 *   - **"a GOOD GAME"**, singular and in the same list, read the same way: one
 *     rival sends one at the finish. Three simultaneous GOOD GAMEs from three
 *     karts at the same millisecond is not what "a GOOD GAME, occasionally"
 *     describes, and the finish is a single moment, so there is nothing for a
 *     chance to be spread over -- the rule there is the singular, not a draw.
 *
 * Everything is still a function of the race seed: `RivalsState.rng` is forked
 * from it, so the same race sends the same signals at the same moments.
 */
export function rivalObserve(
  rivals: RivalsState,
  state: RaceState,
  events: readonly RaceEvent[],
): { rivals: RivalsState; signals: SignalEvent[] } {
  const next = cloneRivals(rivals);
  const signals = observeInto(next, state, events);
  return { rivals: next, signals };
}

function observeInto(
  rivals: RivalsState,
  state: RaceState,
  events: readonly RaceEvent[],
): SignalEvent[] {
  const signals: SignalEvent[] = [];
  for (const event of events) {
    if (event.type === "correct" || event.type === "reveal" || event.type === "pitCrew") {
      if (event.racerId === rivals.humanId) recordChildAnswer(rivals, state, event.at);
      if (event.racerId === rivals.humanId && event.type === "reveal") rivals.childLapMistakes += 1;
      continue;
    }
    if (event.type === "wrong") {
      if (event.racerId === rivals.humanId) rivals.childLapMistakes += 1;
      continue;
    }
    if (event.type === "lapComplete" && event.racerId === rivals.humanId) {
      const clean = rivals.childLapMistakes === 0;
      const lap = event.lapsComplete;
      rivals.childLapMistakes = 0;
      if (clean && rivals.niceRunLaps.indexOf(lap) === -1) {
        rivals.niceRunLaps.push(lap);
        // "occasionally": the lap earns the signal, the draw decides whether it
        // goes. Drawn before the speaker so a lap that sends nothing costs the
        // stream one number and not two.
        if (nextFloat(rivals.rng) < NICE_RUN_CHANCE) {
          const speaker = pickSpeaker(rivals, state);
          if (speaker !== null) signals.push(signalEvent(speaker.id, "niceRun", event.at));
        }
      }
      continue;
    }
    if (event.type === "finished" && event.racerId === rivals.humanId) {
      // "a GOOD GAME at the finish": one, from one rival.
      if (rivals.sentGoodGame) continue;
      const speaker = pickSpeaker(rivals, state);
      if (speaker === null) continue;
      rivals.sentGoodGame = true;
      signals.push(signalEvent(speaker.id, "goodGame", event.at));
    }
  }
  return signals;
}

function signalEvent(racerId: string, signal: Signal, at: number): SignalEvent {
  return { type: "signal", at, racerId, signal };
}

function recordChildAnswer(rivals: RivalsState, state: RaceState, at: number): void {
  const since = rivals.childLastAnswerAtMs > 0 ? rivals.childLastAnswerAtMs : state.startedAtMs;
  const gap = at - since;
  rivals.childGaps.push(gap > 0 ? gap : 0);
  while (rivals.childGaps.length > RIVAL_PACE_WINDOW) rivals.childGaps.shift();
  rivals.childLastAnswerAtMs = at;
  rivals.childAnswers += 1;
}

/**
 * Which rival speaks: one, drawn from the signal stream.
 *
 * A rival still on the track is preferred, because a signal from a kart the
 * child can see beside them is the one the design's lobby vocabulary is for.
 * When none is left the whole field is eligible instead -- the child crossing
 * the line last, with all three rivals already parked, is exactly the finish
 * that most needs its `GOOD GAME`, and a "prefer racing" rule with no fallback
 * would silence it.
 */
function pickSpeaker(rivals: RivalsState, state: RaceState): RivalMind | null {
  const racing: RivalMind[] = [];
  for (const mind of rivals.minds) {
    const racer = racerById(state, mind.id);
    if (racer !== null && !racer.finished) racing.push(mind);
  }
  if (racing.length === 0) for (const mind of rivals.minds) racing.push(mind);
  if (racing.length === 0) return null;
  return racing[nextInt(rivals.rng, racing.length)]!;
}

/**
 * Slot signals into the events of one step so the ordering guarantee in
 * events.ts still holds: `signal` ranks 5, above `handDealt` and below the
 * `passed` and `passedBy` callouts that always come last.
 *
 * A caller that steps the child itself does the same merge with the signals
 * `rivalObserve` hands back, which is why this is exported rather than private:
 * the guarantee belongs to the event stream the UI sees, not to this file.
 */
export function mergeSignals(
  events: readonly RaceEvent[],
  signals: readonly SignalEvent[],
): RaceEvent[] {
  const out: RaceEvent[] = [];
  if (signals.length === 0) {
    for (const event of events) out.push(event);
    return out;
  }
  let placed = false;
  for (const event of events) {
    if (!placed && (event.type === "passed" || event.type === "passedBy")) {
      for (const signal of signals) out.push(signal);
      placed = true;
    }
    out.push(event);
  }
  if (!placed) for (const signal of signals) out.push(signal);
  return out;
}

// ---------------------------------------------------------------------------
// the rival reducer
// ---------------------------------------------------------------------------

/** One answer a rival gave, with the decision that produced it. */
export interface RivalAnswer {
  at: number;
  racerId: string;
  fact: Fact;
  correct: boolean;
  value: number;
  /** The gap that led to this answer, after the 1.5 s floor. */
  thinkMs: number;
  /** The gap before the floor, so a report can count how often the floor bit. */
  drawnThinkMs: number;
  /** The rubber-band scale that gap was drawn at. */
  scale: number;
}

/** One card a rival played, and the standings it was decided against. */
export interface RivalPlay {
  at: number;
  racerId: string;
  card: Card;
  targetId: string;
  rule: PolicyRule;
  /**
   * Everyone the play landed on, taken from the `hit`, `blocked` and `swap`
   * events the race reducer emitted -- not from the policy's own opinion of who
   * it was aiming at.
   */
  victimIds: string[];
  /** Every racer's effective progress at the instant before the card resolved. */
  standingsBefore: RivalStanding[];
  /** Whether this rival's previous hand had landed on the child. */
  previousHandAttackedHuman: boolean;
  attackedHuman: boolean;
}

export interface RivalStepResult {
  state: RaceState;
  rivals: RivalsState;
  events: RaceEvent[];
  answers: RivalAnswer[];
  plays: RivalPlay[];
}

/**
 * A safety net, not a rule: the loop below is bounded by the fact that every
 * iteration either advances a rival's deadline or ends the race, and both of
 * those are monotonic. If it ever is not, stopping is better than hanging.
 */
const MAX_ACTIONS_PER_STEP = 4096;

/**
 * Advance every rival up to `now`.
 *
 * Rivals act in due-time order, earliest first and seat order on a tie, so the
 * result does not depend on the order the caller listed them in or on how big
 * the caller's tick is. Each answer is applied at the instant it was due, not
 * at `now`, so a 100 ms tick and a 1 ms tick produce the same race.
 */
export function rivalStep(state: RaceState, rivals: RivalsState, now: number): RivalStepResult {
  let next = state;
  const minds = cloneRivals(rivals);
  const events: RaceEvent[] = [];
  const answers: RivalAnswer[] = [];
  const plays: RivalPlay[] = [];

  if (next.status !== "racing" && next.status !== "settling") {
    // A rival cannot answer during the countdown or after the flag. Its
    // deadline still moves with the clock so the countdown is not banked.
    if (next.status === "countdown") {
      for (const mind of minds.minds) {
        if (mind.nextAnswerAtMs < now) mind.nextAnswerAtMs = now;
      }
    }
    return { state: next, rivals: minds, events, answers, plays };
  }

  let guard = 0;
  for (;;) {
    if (++guard > MAX_ACTIONS_PER_STEP) break;
    // A stalled rival's deadline slides to the end of the stall; the design's
    // Stalled rule locks the field, it does not queue an answer behind it.
    for (const mind of minds.minds) {
      const racer = racerById(next, mind.id);
      if (racer === null) continue;
      if (mind.nextAnswerAtMs < racer.stalledUntilMs) mind.nextAnswerAtMs = racer.stalledUntilMs;
    }
    const mind = dueMind(next, minds, now);
    if (mind === null) break;

    const at = mind.nextAnswerAtMs;
    const racer = racerById(next, mind.id)!;
    const fact = racer.currentFact;
    const handBefore = racer.hand.length;
    const correct = drawsCorrect(mind.rng, mind.accuracyPercent);
    const value = correct ? factAnswer(fact) : drawWrongAnswer(mind.rng, fact);

    const applied = step(next, { kind: "answer", racerId: mind.id, value }, at);
    next = applied.state;
    const signals = observeInto(minds, next, applied.events);
    for (const event of mergeSignals(applied.events, signals)) events.push(event);

    mind.answersTaken += 1;
    mind.answersSincePolicy += 1;
    answers.push({
      at,
      racerId: mind.id,
      fact,
      correct,
      value,
      thinkMs: mind.lastThinkMs,
      drawnThinkMs: mind.lastDrawnThinkMs,
      scale: mind.lastScale,
    });
    schedule(minds, mind, at);

    const after = racerById(next, mind.id)!;
    const handAfter = after.hand.length;
    const dealt = handBefore === 0 && handAfter > 0;
    // Design: "evaluated when a hand is dealt and re-evaluated every three
    // answers while it is held."
    if (handAfter > 0 && (dealt || mind.answersSincePolicy >= POLICY_INTERVAL)) {
      mind.answersSincePolicy = 0;
      const choice = choosePlay(next, mind);
      if (choice !== null) {
        const before = standings(next);
        const played = step(
          next,
          {
            kind: "useCard",
            racerId: mind.id,
            index: choice.index,
            targetId: choice.targetId === "" ? undefined : choice.targetId,
          },
          at,
        );
        next = played.state;
        const playSignals = observeInto(minds, next, played.events);
        for (const event of mergeSignals(played.events, playSignals)) events.push(event);
        const victimIds = victimsOf(played.events, mind.id);
        const attackedHuman =
          isAttackCard(choice.card) && victimIds.indexOf(next.humanId) !== -1;
        plays.push({
          at,
          racerId: mind.id,
          card: choice.card,
          targetId: choice.targetId,
          rule: choice.rule,
          victimIds,
          standingsBefore: before,
          previousHandAttackedHuman: mind.lastHandAttackedHuman,
          attackedHuman,
        });
        mind.lastHandAttackedHuman = attackedHuman;
      }
    }
  }

  return { state: next, rivals: minds, events, answers, plays };
}

function dueMind(state: RaceState, rivals: RivalsState, now: number): RivalMind | null {
  let best: RivalMind | null = null;
  let bestSeat = 0;
  for (const mind of rivals.minds) {
    const racer = racerById(state, mind.id);
    if (racer === null || racer.finished) continue;
    if (racer.currentFact < 0) continue;
    if (mind.nextAnswerAtMs > now) continue;
    if (best === null || mind.nextAnswerAtMs < best.nextAnswerAtMs) {
      best = mind;
      bestSeat = racer.seat;
      continue;
    }
    if (mind.nextAnswerAtMs === best.nextAnswerAtMs && racer.seat < bestSeat) {
      best = mind;
      bestSeat = racer.seat;
    }
  }
  return best;
}

/** Who a play actually reached, read off the race reducer's own events. */
export function victimsOf(events: readonly RaceEvent[], attackerId: string): string[] {
  const ids: string[] = [];
  for (const event of events) {
    if (event.type === "hit" || event.type === "blocked") {
      if (event.fromId !== attackerId) continue;
      if (event.racerId === attackerId) continue;
      if (ids.indexOf(event.racerId) === -1) ids.push(event.racerId);
      continue;
    }
    if (event.type === "swap" && event.racerId === attackerId) {
      if (ids.indexOf(event.withId) === -1) ids.push(event.withId);
    }
  }
  return ids;
}

/**
 * The earliest moment a rival is next due to act, or -1 when none of them is
 * still racing. A caller that wants to advance the clock exactly, rather than
 * on a fixed tick, asks this.
 */
export function nextRivalDeadline(state: RaceState, rivals: RivalsState): number {
  let soonest = -1;
  for (const mind of rivals.minds) {
    const racer = racerById(state, mind.id);
    if (racer === null || racer.finished) continue;
    const at = mind.nextAnswerAtMs < racer.stalledUntilMs ? racer.stalledUntilMs : mind.nextAnswerAtMs;
    if (soonest < 0 || at < soonest) soonest = at;
  }
  return soonest;
}
