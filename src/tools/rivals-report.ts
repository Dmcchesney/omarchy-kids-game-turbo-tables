// The rivals statistics harness.
//
//   node src/tools/rivals-report.ts                  10,000 races per level
//   node src/tools/rivals-report.ts --races 500      a quicker look
//   node src/tools/rivals-report.ts --bundle         through engine/engine.mjs
//   node src/tools/rivals-report.ts --vectors        rewrite vectors/rivals.json
//
// Plan, M2 gate: "over 10,000 seeded Grand Prix races the mercy rules never
// break, rival finish-time distributions per level match the design's intent
// (Rookie slower than Pro slower than Champion, with overlap), and a child
// scripted at 4 s per answer and 90% accuracy finishes second or third at Pro
// more often than not."
//
// Nothing here decides anything. The engine decides; this file drives it,
// counts what happened and prints the numbers. In particular the two mercy
// checks are re-derived from the race reducer's own `hit`, `blocked` and `swap`
// events and from a standings snapshot taken at the instant the card resolved,
// and re-ranked here with the engine's `effectiveProgress` -- not with the
// policy's opinion of who it was aiming at.

import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import type * as EngineModule from "../engine/index.ts";
import * as sourceEngine from "../engine/index.ts";

export type Engine = typeof EngineModule;

const root = resolve(import.meta.dirname, "../..");

export const RIVAL_SEATS: {
  id: string;
  personality: "bolt" | "piston" | "gasket";
}[] = [
  { id: "bolt", personality: "bolt" },
  { id: "piston", personality: "piston" },
  { id: "gasket", personality: "gasket" },
];

export const HUMAN_ID = "you";

export interface ChildScript {
  /** Design gate: 4 s per answer. A fixed gap, not a draw. */
  paceMs: number;
  /** Design gate: 90% accuracy. */
  accuracyPercent: number;
  /** Whether the scripted child spends the hands it earns. */
  playsCards: boolean;
}

export const GATE_CHILD: ChildScript = { paceMs: 4000, accuracyPercent: 90, playsCards: true };

export interface RaceOptions {
  seed: number;
  preset: "2-5" | "2-10" | "1-12" | "choose";
  chosenTables?: number[];
  level: "rookie" | "pro" | "champion";
  child: ChildScript;
  /**
   * The design's Finish rule is fifteen seconds of settling, and that is what
   * decides the child's place. Raised only for the finish-time measurement,
   * where a rival that never crossed the line contributes no time at all and a
   * distribution built from the ones that did is a distribution of the fast
   * half. Never changed for the place measurement.
   */
  settleMs?: number;
  /**
   * Off only for the control run in section 4, which measures the rival table
   * on speed and accuracy alone. Grand Prix has them on.
   */
  powerupsEnabled?: boolean;
  /** Keep every rival answer and play, for the vector file. Off for the gate run. */
  detail?: boolean;
}

export interface MercyViolation {
  kind: "lastPlace" | "consecutiveChild";
  at: number;
  attackerId: string;
  victimId: string;
  card: string;
  detail: string;
}

export interface RaceOutcome {
  seed: number;
  level: string;
  /** Finishing place per racer id, 1..4. */
  places: Record<string, number>;
  finished: Record<string, boolean>;
  finishTimeMs: Record<string, number>;
  correct: Record<string, number>;
  childPlace: number;
  /** Every rival answer's think time, after the 1.5 s floor. */
  minThinkMs: number;
  maxThinkMs: number;
  minScale: number;
  maxScale: number;
  /** Draws the 1.5 s floor pulled up. */
  flooredDraws: number;
  rivalAnswers: number;
  attacks: number;
  attacksOnChild: number;
  violations: MercyViolation[];
  signals: { at: number; racerId: string; signal: string }[];
  /** Only when `detail` is set. */
  answers: EngineModule.RivalAnswer[];
  plays: EngineModule.RivalPlay[];
  events: string[];
}

/**
 * One race. The child answers on a fixed clock; the rivals answer on theirs;
 * whichever deadline is soonest moves the race, so the result does not depend
 * on any tick size.
 */
export function runRace(E: Engine, options: RaceOptions): RaceOutcome {
  const racers = [
    { id: HUMAN_ID, kind: "human" as const },
    ...RIVAL_SEATS.map((seat) => ({ id: seat.id, kind: "rival" as const })),
  ];
  let state = E.createRace({
    seed: options.seed,
    preset: options.preset,
    chosenTables: options.chosenTables,
    mode: "grandPrix",
    settleMs: options.settleMs,
    powerupsEnabled: options.powerupsEnabled,
    racers,
  });
  state = E.step(state, { kind: "start" }, 0).state;
  let rivals = E.createRivals(
    state,
    RIVAL_SEATS.map((seat) => ({
      id: seat.id,
      personality: seat.personality,
      level: options.level,
    })),
  );

  const childRng = E.forkRng(options.seed, "scripted-child:" + options.child.accuracyPercent);
  let childDue = options.child.paceMs;
  let childAnswersSincePolicy = 0;
  // The child is given the rivals' own play policy, and nothing else of theirs:
  // `choosePlay` reads the mind's id and whether its previous hand landed on
  // the child, and draws no randomness at all.
  const childMind = E.createRivals(state, [
    { id: HUMAN_ID, personality: "piston", level: options.level },
  ]).minds[0]!;

  const outcome: RaceOutcome = {
    seed: options.seed,
    level: options.level,
    places: {},
    finished: {},
    finishTimeMs: {},
    correct: {},
    childPlace: 0,
    minThinkMs: Number.MAX_SAFE_INTEGER,
    maxThinkMs: 0,
    minScale: Number.MAX_SAFE_INTEGER,
    maxScale: 0,
    flooredDraws: 0,
    rivalAnswers: 0,
    attacks: 0,
    attacksOnChild: 0,
    violations: [],
    signals: [],
    answers: [],
    plays: [],
    events: [],
  };

  const attackCards = new Set<string>(E.ATTACK_CARDS as readonly string[]);
  /** The last hand each rival spent, and whether it landed on the child. */
  const lastHandHitChild = new Map<string, boolean>();

  function absorb(result: { events: readonly EngineModule.RaceEvent[] }): void {
    for (const event of result.events) {
      if (event.type === "signal")
        outcome.signals.push({ at: event.at, racerId: event.racerId, signal: event.signal });
      if (options.detail) outcome.events.push(event.type + ":" + event.racerId + ":" + event.at);
    }
  }

  function auditPlays(plays: readonly EngineModule.RivalPlay[]): void {
    for (const play of plays) {
      if (options.detail) outcome.plays.push(play);
      if (!attackCards.has(play.card)) {
        // A boost or a Roll Cage ends the hand without attacking anybody.
        lastHandHitChild.set(play.racerId, false);
        continue;
      }
      outcome.attacks += 1;
      // Re-rank the snapshot here, with the engine's own progress numbers.
      let lowest = Number.MAX_SAFE_INTEGER;
      for (const row of play.standingsBefore) if (row.progress < lowest) lowest = row.progress;
      const last = new Set<string>();
      for (const row of play.standingsBefore) if (row.progress === lowest) last.add(row.id);
      let hitChild = false;
      for (const victimId of play.victimIds) {
        if (victimId === HUMAN_ID) hitChild = true;
        if (last.has(victimId)) {
          outcome.violations.push({
            kind: "lastPlace",
            at: play.at,
            attackerId: play.racerId,
            victimId,
            card: play.card,
            detail:
              "progress " + lowest + " was the lowest of "
              + play.standingsBefore.map((row) => row.id + "=" + row.progress).join(" "),
          });
        }
      }
      if (hitChild) {
        outcome.attacksOnChild += 1;
        if (lastHandHitChild.get(play.racerId) === true) {
          outcome.violations.push({
            kind: "consecutiveChild",
            at: play.at,
            attackerId: play.racerId,
            victimId: HUMAN_ID,
            card: play.card,
            detail: "the previous hand this rival spent also landed on the child",
          });
        }
      }
      lastHandHitChild.set(play.racerId, hitChild);
    }
  }

  function absorbRivalStep(result: EngineModule.RivalStepResult): void {
    absorb(result);
    for (const answer of result.answers) {
      outcome.rivalAnswers += 1;
      if (answer.thinkMs < outcome.minThinkMs) outcome.minThinkMs = answer.thinkMs;
      if (answer.thinkMs > outcome.maxThinkMs) outcome.maxThinkMs = answer.thinkMs;
      if (answer.scale < outcome.minScale) outcome.minScale = answer.scale;
      if (answer.scale > outcome.maxScale) outcome.maxScale = answer.scale;
      if (answer.drawnThinkMs < answer.thinkMs) outcome.flooredDraws += 1;
      if (options.detail) outcome.answers.push(answer);
    }
    auditPlays(result.plays);
  }

  let now = 0;
  let guard = 0;
  for (;;) {
    if (++guard > 200000) break;
    const human = state.racers.find((racer) => racer.id === HUMAN_ID)!;
    const rivalDue = E.nextRivalDeadline(state, rivals);
    const humanDue = human.finished
      ? -1
      : childDue < human.stalledUntilMs
        ? human.stalledUntilMs
        : childDue;
    let next = -1;
    if (humanDue >= 0) next = humanDue;
    if (rivalDue >= 0 && (next < 0 || rivalDue < next)) next = rivalDue;
    if (next < 0) break;
    if (next < now) next = now;

    if (state.status === "settling" && next > state.settleUntilMs) {
      const closed = E.step(state, { kind: "tick" }, state.settleUntilMs);
      state = closed.state;
      absorb(closed);
      break;
    }
    now = next;

    if (humanDue >= 0 && humanDue <= now) {
      const fact = human.currentFact;
      const handBefore = human.hand.length;
      const correct = E.nextFloat(childRng) * 100 < options.child.accuracyPercent;
      const value = correct ? E.factAnswer(fact) : E.drawWrongAnswer(childRng, fact);
      const applied = E.step(state, { kind: "answer", racerId: HUMAN_ID, value }, now);
      state = applied.state;
      const observed = E.rivalObserve(rivals, state, applied.events);
      rivals = observed.rivals;
      absorb(applied);
      for (const signal of observed.signals)
        outcome.signals.push({ at: signal.at, racerId: signal.racerId, signal: signal.signal });
      childDue = now + options.child.paceMs;
      childAnswersSincePolicy += 1;
      const live = state.racers.find((racer) => racer.id === HUMAN_ID)!;
      const dealt = handBefore === 0 && live.hand.length > 0;
      if (
        options.child.playsCards
        && live.hand.length > 0
        && (dealt || childAnswersSincePolicy >= E.POLICY_INTERVAL)
      ) {
        childAnswersSincePolicy = 0;
        const choice = E.choosePlay(state, childMind);
        if (choice !== null) {
          const played = E.step(
            state,
            {
              kind: "useCard",
              racerId: HUMAN_ID,
              index: choice.index,
              targetId: choice.targetId === "" ? undefined : choice.targetId,
            },
            now,
          );
          state = played.state;
          // The child's own card can finish a lap, or the race: a boost takes
          // questions off the current lap. Those events are the caller's to
          // observe, exactly like the answer above, or a NICE RUN and the whole
          // GOOD GAME round go unsent.
          const seen = E.rivalObserve(rivals, state, played.events);
          rivals = seen.rivals;
          absorb(played);
          for (const signal of seen.signals)
            outcome.signals.push({ at: signal.at, racerId: signal.racerId, signal: signal.signal });
          childMind.lastHandAttackedHuman = false;
        }
      }
    }

    const stepped = E.rivalStep(state, rivals, now);
    state = stepped.state;
    rivals = stepped.rivals;
    absorbRivalStep(stepped);

    if (state.status === "finished") break;
  }

  const ranked = E.rankRacers(state.racers, state.questionsPerLap);
  for (const entry of ranked) {
    outcome.places[entry.id] = entry.place;
    outcome.finished[entry.id] = entry.finished;
    outcome.finishTimeMs[entry.id] = entry.finishTimeMs;
    outcome.correct[entry.id] = entry.correctCount;
  }
  outcome.childPlace = outcome.places[HUMAN_ID] ?? 0;
  if (outcome.minThinkMs === Number.MAX_SAFE_INTEGER) outcome.minThinkMs = 0;
  if (outcome.minScale === Number.MAX_SAFE_INTEGER) outcome.minScale = 1;
  if (outcome.maxScale === 0) outcome.maxScale = 1;
  return outcome;
}

// ---------------------------------------------------------------------------
// statistics
// ---------------------------------------------------------------------------

export interface Distribution {
  count: number;
  min: number;
  q1: number;
  median: number;
  q3: number;
  max: number;
  mean: number;
}

export function distribution(values: number[]): Distribution {
  if (values.length === 0) return { count: 0, min: 0, q1: 0, median: 0, q3: 0, max: 0, mean: 0 };
  const sorted = values.slice().sort((left, right) => left - right);
  const at = (fraction: number): number => {
    const index = Math.floor(fraction * (sorted.length - 1));
    return sorted[index < 0 ? 0 : index >= sorted.length ? sorted.length - 1 : index]!;
  };
  let total = 0;
  for (const value of sorted) total += value;
  return {
    count: sorted.length,
    min: sorted[0]!,
    q1: at(0.25),
    median: at(0.5),
    q3: at(0.75),
    max: sorted[sorted.length - 1]!,
    mean: total / sorted.length,
  };
}

export function overlapFraction(left: number[], right: number[]): number {
  // What share of the slower group falls inside the faster group's range.
  if (left.length === 0 || right.length === 0) return 0;
  const leftSorted = left.slice().sort((a, b) => a - b);
  const low = leftSorted[0]!;
  const high = leftSorted[leftSorted.length - 1]!;
  let inside = 0;
  for (const value of right) if (value >= low && value <= high) inside += 1;
  return inside / right.length;
}

/** The place counts 1..4 for the child, indexed by place. */
function places(stats: LevelStatistics): number[] {
  const counts = [0, 0, 0, 0, 0];
  for (const place of stats.childPlaces) counts[place] = (counts[place] ?? 0) + 1;
  return counts;
}

function share(part: number, whole: number): string {
  return ((part / Math.max(1, whole)) * 100).toFixed(2) + "%";
}

function seconds(ms: number): string {
  return (ms / 1000).toFixed(1) + "s";
}

function padRight(text: string, width: number): string {
  return text.length >= width ? text : text + " ".repeat(width - text.length);
}

function padLeft(text: string, width: number): string {
  return text.length >= width ? text : " ".repeat(width - text.length) + text;
}

export function histogram(values: number[], buckets: number, unit: (value: number) => string): string[] {
  if (values.length === 0) return ["(none)"];
  const sorted = values.slice().sort((a, b) => a - b);
  const low = sorted[0]!;
  const high = sorted[sorted.length - 1]!;
  const width = high > low ? (high - low) / buckets : 1;
  const counts = new Array<number>(buckets).fill(0);
  for (const value of sorted) {
    let index = width > 0 ? Math.floor((value - low) / width) : 0;
    if (index >= buckets) index = buckets - 1;
    if (index < 0) index = 0;
    counts[index] += 1;
  }
  let peak = 1;
  for (const count of counts) if (count > peak) peak = count;
  const lines: string[] = [];
  for (let index = 0; index < buckets; index++) {
    const from = low + width * index;
    const to = index === buckets - 1 ? high : low + width * (index + 1);
    const bar = "#".repeat(Math.round((counts[index]! / peak) * 40));
    lines.push(
      "    " + padLeft(unit(from), 8) + " .. " + padLeft(unit(to), 8)
      + " " + padLeft(String(counts[index]), 6) + "  " + bar,
    );
  }
  return lines;
}

// ---------------------------------------------------------------------------
// the gate run
// ---------------------------------------------------------------------------

const LEVELS: ("rookie" | "pro" | "champion")[] = ["rookie", "pro", "champion"];

export interface LevelStatistics {
  level: string;
  races: number;
  finishTimes: Record<string, number[]>;
  unfinished: Record<string, number>;
  childPlaces: number[];
  minThinkMs: number;
  maxThinkMs: number;
  minScale: number;
  maxScale: number;
  flooredDraws: number;
  rivalAnswers: number;
  attacks: number;
  attacksOnChild: number;
  violations: MercyViolation[];
  signals: Record<string, number>;
}

export function runLevel(
  E: Engine,
  level: "rookie" | "pro" | "champion",
  races: number,
  firstSeed: number,
  child: ChildScript,
  settleMs?: number,
  powerupsEnabled?: boolean,
): LevelStatistics {
  const stats: LevelStatistics = {
    level,
    races,
    finishTimes: { bolt: [], piston: [], gasket: [], you: [] },
    unfinished: { bolt: 0, piston: 0, gasket: 0, you: 0 },
    childPlaces: [],
    minThinkMs: Number.MAX_SAFE_INTEGER,
    maxThinkMs: 0,
    minScale: Number.MAX_SAFE_INTEGER,
    maxScale: 0,
    flooredDraws: 0,
    rivalAnswers: 0,
    attacks: 0,
    attacksOnChild: 0,
    violations: [],
    signals: {},
  };
  for (let index = 0; index < races; index++) {
    const outcome = runRace(E, {
      seed: firstSeed + index,
      preset: "1-12",
      level,
      child,
      settleMs,
      powerupsEnabled,
    });
    for (const id of ["bolt", "piston", "gasket", "you"]) {
      if (outcome.finished[id]) stats.finishTimes[id]!.push(outcome.finishTimeMs[id]!);
      else stats.unfinished[id]! += 1;
    }
    stats.childPlaces.push(outcome.childPlace);
    if (outcome.minThinkMs > 0 && outcome.minThinkMs < stats.minThinkMs)
      stats.minThinkMs = outcome.minThinkMs;
    if (outcome.maxThinkMs > stats.maxThinkMs) stats.maxThinkMs = outcome.maxThinkMs;
    if (outcome.minScale < stats.minScale) stats.minScale = outcome.minScale;
    if (outcome.maxScale > stats.maxScale) stats.maxScale = outcome.maxScale;
    stats.flooredDraws += outcome.flooredDraws;
    stats.rivalAnswers += outcome.rivalAnswers;
    stats.attacks += outcome.attacks;
    stats.attacksOnChild += outcome.attacksOnChild;
    for (const violation of outcome.violations)
      if (stats.violations.length < 20) stats.violations.push(violation);
    for (const signal of outcome.signals)
      stats.signals[signal.signal] = (stats.signals[signal.signal] ?? 0) + 1;
  }
  if (stats.minThinkMs === Number.MAX_SAFE_INTEGER) stats.minThinkMs = 0;
  if (stats.minScale === Number.MAX_SAFE_INTEGER) stats.minScale = 1;
  return stats;
}

/**
 * Two passes, because one number cannot be measured the way the other one has
 * to be.
 *
 *   Pass A is the race the design describes: fifteen seconds of settling after
 *   the child crosses the line, and then the flag. It decides the child's
 *   finishing place, and it is where the mercy rules, the rubber band and the
 *   signals are counted.
 *
 *   Pass B is the same seeds with the settle raised until every kart finishes.
 *   Only there is a rival's finish time a number at all: in pass A a slow rival
 *   is cut off, contributes nothing, and a distribution built from the rivals
 *   that did cross the line is a distribution of the fast half. Both sets of
 *   numbers are printed.
 */
function report(E: Engine, races: number, label: string): number {
  const lines: string[] = [];
  const out = (text = ""): void => {
    lines.push(text);
  };

  out("Turbo Tables -- rival statistics");
  out("engine: " + label);
  out("races: " + races + " seeded Grand Prix (preset 1-12, 144 questions) per rival level, twice over");
  out(
    "child: " + GATE_CHILD.paceMs + " ms per answer, " + GATE_CHILD.accuracyPercent
    + "% accuracy, spends the hands it earns under the rivals' own play policy",
  );
  out();

  out("The design's rival table, and what the levels make of it");
  out("  " + padRight("rival", 10) + padRight("level", 11) + padLeft("accuracy", 9) + padLeft("mean", 9) + padLeft("spread", 9));
  for (const seat of RIVAL_SEATS) {
    for (const level of LEVELS) {
      const tuning = E.rivalTuning(seat.personality, level);
      out(
        "  " + padRight(E.RIVAL_PROFILES[seat.personality].label, 10) + padRight(level, 11)
        + padLeft(tuning.accuracyPercent + "%", 9)
        + padLeft(tuning.thinkTimeMeanMs + "ms", 9)
        + padLeft("±" + tuning.thinkTimeSpreadMs + "ms", 9),
      );
    }
  }
  out();

  const FIRST_SEED = 1000000;
  const SETTLE_OFF = 36000000;

  const passA: LevelStatistics[] = [];
  const passB: LevelStatistics[] = [];
  for (let index = 0; index < LEVELS.length; index++) {
    const level = LEVELS[index]!;
    const seed = FIRST_SEED + index * races;
    const startedA = Date.now();
    passA.push(runLevel(E, level, races, seed, GATE_CHILD));
    const startedB = Date.now();
    passB.push(runLevel(E, level, races, seed, GATE_CHILD, SETTLE_OFF));
    out(
      "level " + padRight(level, 10)
      + " pass A " + ((startedB - startedA) / 1000).toFixed(1) + "s"
      + "   pass B " + ((Date.now() - startedB) / 1000).toFixed(1) + "s"
      + "   " + passA[index]!.rivalAnswers + " rival answers, "
      + passA[index]!.attacks + " rival attacks in pass A",
    );
  }
  out();

  out("1. Mercy rules  (both passes; every attack the race reducer actually landed)");
  let violations = 0;
  let attacks = 0;
  for (let index = 0; index < LEVELS.length; index++) {
    for (const [pass, stats] of [["A", passA[index]!], ["B", passB[index]!]] as [string, LevelStatistics][]) {
      violations += stats.violations.length;
      attacks += stats.attacks;
      out(
        "  " + padRight(stats.level, 10) + "pass " + pass
        + padLeft(String(stats.attacks), 9) + " attacks, "
        + padLeft(String(stats.attacksOnChild), 6) + " of them on the child, "
        + stats.violations.length + " violations",
      );
      for (const violation of stats.violations.slice(0, 5))
        out("      " + violation.kind + " " + violation.attackerId + " -> " + violation.victimId
          + " with " + violation.card + " at " + violation.at + "ms: " + violation.detail);
    }
  }
  out("  " + attacks + " attacks landed in total; violations: " + violations);
  out();

  out("2. Rival finish times per level, pass B, every kart across the line (ms)");
  for (const stats of passB) {
    out("  " + stats.level);
    for (const id of ["bolt", "piston", "gasket", "you"]) {
      const spread = distribution(stats.finishTimes[id]!);
      out(
        "    " + padRight(id, 8)
        + " n=" + padLeft(String(spread.count), 6)
        + " unfinished=" + padLeft(String(stats.unfinished[id]), 5)
        + "  min " + padLeft(seconds(spread.min), 8)
        + "  q1 " + padLeft(seconds(spread.q1), 8)
        + "  med " + padLeft(seconds(spread.median), 8)
        + "  q3 " + padLeft(seconds(spread.q3), 8)
        + "  max " + padLeft(seconds(spread.max), 8)
        + "  mean " + padLeft(seconds(spread.mean), 8),
      );
    }
  }
  out();

  out("   The same, pass A, the fifteen-second settle in place -- a rival still racing when the");
  out("   flag falls has no finish time at all, so these rows are the fast half and are printed");
  out("   for the unfinished counts rather than for their quantiles");
  for (const stats of passA) {
    out("  " + stats.level);
    for (const id of ["bolt", "piston", "gasket", "you"]) {
      const spread = distribution(stats.finishTimes[id]!);
      out(
        "    " + padRight(id, 8)
        + " n=" + padLeft(String(spread.count), 6)
        + " unfinished=" + padLeft(String(stats.unfinished[id]), 5)
        + "  med " + padLeft(seconds(spread.median), 8)
        + "  mean " + padLeft(seconds(spread.mean), 8),
      );
    }
  }
  out();

  out("   Level ordering, per rival, pass B: median finish time");
  for (const seat of RIVAL_SEATS) {
    const medians = LEVELS.map((level) => {
      const stats = passB.find((entry) => entry.level === level)!;
      return distribution(stats.finishTimes[seat.id]!).median;
    });
    const ordered = medians[0]! > medians[1]! && medians[1]! > medians[2]!;
    out(
      "    " + padRight(seat.id, 8)
      + " rookie " + padLeft(seconds(medians[0]!), 8)
      + " > pro " + padLeft(seconds(medians[1]!), 8)
      + " > champion " + padLeft(seconds(medians[2]!), 8)
      + "   " + (ordered ? "ordered" : "NOT ORDERED"),
    );
  }
  out();

  out("   Overlap between adjacent levels, pass B: share of the faster level's finishes that fall");
  out("   inside the slower level's observed range");
  for (const seat of RIVAL_SEATS) {
    const rookie = passB[0]!.finishTimes[seat.id]!;
    const pro = passB[1]!.finishTimes[seat.id]!;
    const champion = passB[2]!.finishTimes[seat.id]!;
    out(
      "    " + padRight(seat.id, 8)
      + " pro inside rookie " + padLeft((overlapFraction(rookie, pro) * 100).toFixed(1) + "%", 7)
      + "   champion inside pro " + padLeft((overlapFraction(pro, champion) * 100).toFixed(1) + "%", 7)
      + "   rookie min " + padLeft(seconds(distribution(rookie).min), 8)
      + " vs pro max " + padLeft(seconds(distribution(pro).max), 8)
      + "   pro min " + padLeft(seconds(distribution(pro).min), 8)
      + " vs champion max " + padLeft(seconds(distribution(champion).max), 8),
    );
  }
  out();

  out("3. Rubber band, as observed across both passes");
  let bandLow = Number.MAX_SAFE_INTEGER;
  let bandHigh = 0;
  let thinkLow = Number.MAX_SAFE_INTEGER;
  let thinkHigh = 0;
  for (let index = 0; index < LEVELS.length; index++) {
    for (const [pass, stats] of [["A", passA[index]!], ["B", passB[index]!]] as [string, LevelStatistics][]) {
      if (stats.minThinkMs > 0 && stats.minThinkMs < thinkLow) thinkLow = stats.minThinkMs;
      if (stats.maxThinkMs > thinkHigh) thinkHigh = stats.maxThinkMs;
      if (stats.minScale < bandLow) bandLow = stats.minScale;
      if (stats.maxScale > bandHigh) bandHigh = stats.maxScale;
      out(
        "  " + padRight(stats.level, 10) + "pass " + pass
        + "  think time " + padLeft(stats.minThinkMs + "ms", 8) + " .. " + padLeft(stats.maxThinkMs + "ms", 8)
        + "   scale " + stats.minScale.toFixed(6) + " .. " + stats.maxScale.toFixed(6)
        + "   floor lifted " + stats.flooredDraws + " of " + stats.rivalAnswers
        + " (" + ((stats.flooredDraws / Math.max(1, stats.rivalAnswers)) * 100).toFixed(3) + "%)",
      );
    }
  }
  out(
    "  overall: think time " + thinkLow + "ms .. " + thinkHigh + "ms against a floor of "
    + E.RIVAL_FLOOR_MS + "ms; scale " + bandLow.toFixed(6) + " .. " + bandHigh.toFixed(6)
    + " against a limit of " + (1 - E.RUBBER_BAND_LIMIT) + " .. " + (1 + E.RUBBER_BAND_LIMIT),
  );
  out();

  out("4. The scripted child's finishing place, pass A -- the race as the design ends it");
  for (const stats of passA) {
    const counts = places(stats);
    const podium = counts[2]! + counts[3]!;
    out(
      "  " + padRight(stats.level, 39)
      + " 1st " + padLeft(String(counts[1]), 7)
      + "  2nd " + padLeft(String(counts[2]), 7)
      + "  3rd " + padLeft(String(counts[3]), 7)
      + "  4th " + padLeft(String(counts[4]), 7)
      + "   2nd-or-3rd " + share(podium, stats.childPlaces.length)
      + "   on the podium " + share(counts[1]! + podium, stats.childPlaces.length),
    );
  }
  out();

  const sideRaces = races < 2000 ? races : 2000;
  const sideSeed = FIRST_SEED + races * LEVELS.length;

  const holding = runLevel(E, "pro", sideRaces, sideSeed, {
    paceMs: GATE_CHILD.paceMs,
    accuracyPercent: GATE_CHILD.accuracyPercent,
    playsCards: false,
  });
  const holdCounts = places(holding);
  out(
    "   the same child, never spending a hand   (" + sideRaces + " races)"
    + "   1st " + padLeft(String(holdCounts[1]), 7)
    + "  2nd " + padLeft(String(holdCounts[2]), 7)
    + "  3rd " + padLeft(String(holdCounts[3]), 7)
    + "  4th " + padLeft(String(holdCounts[4]), 7)
    + "   2nd-or-3rd " + share(holdCounts[2]! + holdCounts[3]!, sideRaces),
  );

  const noCards = runLevel(E, "pro", sideRaces, sideSeed, GATE_CHILD, undefined, false);
  const noCardCounts = places(noCards);
  out(
    "   control, powerups off for everyone      (" + sideRaces + " races)"
    + "   1st " + padLeft(String(noCardCounts[1]), 7)
    + "  2nd " + padLeft(String(noCardCounts[2]), 7)
    + "  3rd " + padLeft(String(noCardCounts[3]), 7)
    + "  4th " + padLeft(String(noCardCounts[4]), 7)
    + "   2nd-or-3rd " + share(noCardCounts[2]! + noCardCounts[3]!, sideRaces),
  );
  out("   with the cards off, the four medians are");
  for (const id of ["bolt", "piston", "gasket", "you"]) {
    const spread = distribution(noCards.finishTimes[id]!);
    out(
      "     " + padRight(id, 8) + " med " + padLeft(seconds(spread.median), 8)
      + "  min " + padLeft(seconds(spread.min), 8) + "  max " + padLeft(seconds(spread.max), 8)
      + "  unfinished " + noCards.unfinished[id],
    );
  }
  out();

  out("5. Finish-time histograms at pro, pass B");
  const pro = passB[1]!;
  for (const id of ["bolt", "piston", "gasket", "you"]) {
    out("  " + id);
    for (const line of histogram(pro.finishTimes[id]!, 12, seconds)) out(line);
  }
  out();

  out("6. Signals sent, pass A");
  for (const stats of passA) {
    const names = Object.keys(stats.signals).sort();
    out(
      "  " + padRight(stats.level, 10)
      + (names.length === 0 ? "(none)" : names.map((name) => name + " " + stats.signals[name]).join("   ")),
    );
  }
  out();

  const proStats = passA[1]!;
  const proCounts = places(proStats);
  const proPodium = (proCounts[2]! + proCounts[3]!) / Math.max(1, proStats.childPlaces.length);
  const ordered = RIVAL_SEATS.every((seat) => {
    const medians = LEVELS.map((level) => {
      const stats = passB.find((entry) => entry.level === level)!;
      return distribution(stats.finishTimes[seat.id]!).median;
    });
    return medians[0]! > medians[1]! && medians[1]! > medians[2]!;
  });
  const overlapped = RIVAL_SEATS.every((seat) => {
    const rookie = passB[0]!.finishTimes[seat.id]!;
    const pro2 = passB[1]!.finishTimes[seat.id]!;
    const champion = passB[2]!.finishTimes[seat.id]!;
    return overlapFraction(rookie, pro2) > 0 && overlapFraction(pro2, champion) > 0;
  });
  const floored = thinkLow >= E.RIVAL_FLOOR_MS;
  const banded =
    bandLow >= 1 - E.RUBBER_BAND_LIMIT - 1e-12 && bandHigh <= 1 + E.RUBBER_BAND_LIMIT + 1e-12;

  out("Gate");
  out("  mercy rules never broken           : " + (violations === 0 ? "yes, 0 of " + attacks + " attacks" : "NO (" + violations + ")"));
  out("  level ordering rookie > pro > champ: " + (ordered ? "yes" : "no"));
  out("  with overlap                       : " + (overlapped ? "yes" : "no"));
  out("  never faster than 1.5 s            : " + (floored ? "yes, lowest observed " + thinkLow + "ms" : "no, " + thinkLow + "ms"));
  out("  never scaled beyond ±15%           : " + (banded ? "yes, " + bandLow.toFixed(6) + " .. " + bandHigh.toFixed(6) : "no"));
  out("  child 2nd or 3rd at pro, more often than not: "
    + (proPodium * 100).toFixed(2) + "% -> " + (proPodium > 0.5 ? "yes" : "no"));

  const text = lines.join("\n") + "\n";
  process.stdout.write(text);
  const failures =
    (violations === 0 ? 0 : 1) + (ordered ? 0 : 1) + (overlapped ? 0 : 1)
    + (floored ? 0 : 1) + (banded ? 0 : 1) + (proPodium > 0.5 ? 0 : 1);
  return failures;
}

// ---------------------------------------------------------------------------
// vectors/rivals.json
// ---------------------------------------------------------------------------

/**
 * The seeds the vector file pins. The 2-5 preset, four laps of forty-eight
 * questions, because it is the shortest race long enough for a rival to fall
 * half a lap behind and spend a boost -- so the file exercises all three
 * branches of the play policy and still fits.
 */
export const VECTOR_SEEDS = [1, 42, 20260902];

export function buildRivalVectors(E: Engine): unknown {
  const profiles: unknown[] = [];
  for (const seat of RIVAL_SEATS) {
    const profile = E.RIVAL_PROFILES[seat.personality];
    for (const level of LEVELS) {
      const tuning = E.rivalTuning(seat.personality, level);
      profiles.push({
        personality: seat.personality,
        label: profile.label,
        temperament: profile.temperament,
        level,
        accuracyPercent: tuning.accuracyPercent,
        thinkTimeMeanMs: tuning.thinkTimeMeanMs,
        thinkTimeSpreadMs: tuning.thinkTimeSpreadMs,
      });
    }
  }

  const band: unknown[] = [];
  for (const childPaceMs of [0, 1000, 2000, 2500, 2800, 3400, 4000, 4600, 6000, 9000]) {
    for (const seat of RIVAL_SEATS) {
      const tuning = E.rivalTuning(seat.personality, "pro");
      band.push({
        childPaceMs,
        personality: seat.personality,
        meanMs: tuning.thinkTimeMeanMs,
        scale: E.rubberBandScale(childPaceMs, tuning.thinkTimeMeanMs),
      });
    }
  }

  const draws: unknown[] = [];
  for (const seat of RIVAL_SEATS) {
    for (const level of LEVELS) {
      const tuning = E.rivalTuning(seat.personality, level);
      const rng = E.forkRng(20260902, "vector:" + seat.personality + ":" + level);
      const values: number[] = [];
      for (let index = 0; index < 12; index++)
        values.push(E.drawThinkTimeMs(rng, tuning.thinkTimeMeanMs, tuning.thinkTimeSpreadMs, 1));
      draws.push({ personality: seat.personality, level, seed: 20260902, thinkTimesMs: values });
    }
  }

  const races: unknown[] = [];
  for (const seed of VECTOR_SEEDS) {
    for (const level of LEVELS) {
      if (level !== "pro" && seed !== 42) continue;
      const outcome = runRace(E, {
        seed,
        preset: "2-5",
        level,
        child: GATE_CHILD,
        detail: true,
      });
      races.push({
        name: "rivals-" + level + "-2-5-" + seed,
        seed,
        preset: "2-5",
        level,
        child: { paceMs: GATE_CHILD.paceMs, accuracyPercent: GATE_CHILD.accuracyPercent },
        answers: outcome.answers.map((answer) => ({
          at: answer.at,
          racerId: answer.racerId,
          fact: answer.fact,
          correct: answer.correct,
          value: answer.value,
          thinkMs: answer.thinkMs,
          drawnThinkMs: answer.drawnThinkMs,
          scale: answer.scale,
        })),
        plays: outcome.plays.map((play) => ({
          at: play.at,
          racerId: play.racerId,
          card: play.card,
          targetId: play.targetId,
          rule: play.rule,
          victimIds: play.victimIds,
          standingsBefore: play.standingsBefore,
          previousHandAttackedHuman: play.previousHandAttackedHuman,
          attackedHuman: play.attackedHuman,
        })),
        signals: outcome.signals,
        places: outcome.places,
        finished: outcome.finished,
        finishTimeMs: outcome.finishTimeMs,
      });
    }
  }

  return {
    note:
      "Rival decisions, pinned. The profile and level rows are transcribed from the design's AI "
      + "rivals table; every other block is this engine's own output, recorded once and locked so a "
      + "policy change cannot pass unnoticed. The race blocks use the two-table Choose preset so a "
      + "whole race of decisions fits in the file.",
    profiles,
    rubberBand: {
      limit: E.RUBBER_BAND_LIMIT,
      floorMs: E.RIVAL_FLOOR_MS,
      paceWindow: E.RIVAL_PACE_WINDOW,
      cases: band,
    },
    policy: {
      interval: E.POLICY_INTERVAL,
      halfLap: E.HALF_LAP,
      boostCards: E.BOOST_CARDS,
      attackCards: E.ATTACK_CARDS,
    },
    thinkTimeDraws: draws,
    races,
  };
}

// ---------------------------------------------------------------------------
// entry point
// ---------------------------------------------------------------------------

/**
 * Every rival decision of a race, as one string. Used by the parity run: the
 * TypeScript source and the committed bundle have to produce the same one.
 */
export function decisionStream(E: Engine, seed: number, level: "rookie" | "pro" | "champion"): string {
  const outcome = runRace(E, { seed, preset: "2-5", level, child: GATE_CHILD, detail: true });
  const parts: string[] = [];
  for (const answer of outcome.answers)
    parts.push(
      "a " + answer.at + " " + answer.racerId + " " + answer.fact + " " + answer.value
      + " " + answer.thinkMs + " " + answer.drawnThinkMs + " " + answer.scale,
    );
  for (const play of outcome.plays)
    parts.push(
      "p " + play.at + " " + play.racerId + " " + play.card + " " + play.targetId + " " + play.rule
      + " " + play.victimIds.join(",") + " " + play.attackedHuman,
    );
  for (const signal of outcome.signals) parts.push("s " + signal.at + " " + signal.racerId + " " + signal.signal);
  for (const id of ["you", "bolt", "piston", "gasket"])
    parts.push("f " + id + " " + outcome.places[id] + " " + outcome.finishTimeMs[id]);
  return parts.join("\n");
}

async function parity(races: number): Promise<number> {
  const bundle = (await import(resolve(root, "engine/engine.mjs"))) as Engine;
  let mismatches = 0;
  let decisions = 0;
  for (let index = 0; index < races; index++) {
    for (const level of LEVELS) {
      const fromSource = decisionStream(sourceEngine, index, level);
      const fromBundle = decisionStream(bundle, index, level);
      decisions += fromSource.split("\n").length;
      if (fromSource !== fromBundle) {
        mismatches += 1;
        if (mismatches <= 3) console.error("seed " + index + " " + level + " diverged");
      }
    }
  }
  console.log(
    "Rival decision parity: " + races + " seeds x " + LEVELS.length + " levels = "
    + races * LEVELS.length + " races, " + decisions
    + " recorded decisions, through src/engine and engine/engine.mjs.",
  );
  console.log("Mismatching races: " + mismatches);
  return mismatches;
}

function argumentValue(name: string, fallback: number): number {
  const index = process.argv.indexOf(name);
  if (index === -1) return fallback;
  const value = Number(process.argv[index + 1]);
  return isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

const invoked = (process.argv[1] ?? "").replace(/\\/g, "/");
if (invoked.endsWith("rivals-report.ts")) {
  const useBundle = process.argv.indexOf("--bundle") !== -1;
  const engine: Engine = useBundle
    ? ((await import(resolve(root, "engine/engine.mjs"))) as Engine)
    : sourceEngine;
  const label = useBundle ? "engine/engine.mjs (committed bundle)" : "src/engine (TypeScript source)";
  if (process.argv.indexOf("--parity") !== -1) {
    const mismatches = await parity(argumentValue("--parity", 200));
    if (mismatches > 0) process.exitCode = 1;
  } else if (process.argv.indexOf("--vectors") !== -1) {
    const contents = JSON.stringify(buildRivalVectors(engine), null, 2) + "\n";
    await writeFile(resolve(root, "vectors/rivals.json"), contents);
    console.log("wrote vectors/rivals.json (" + contents.length + " bytes)");
  } else {
    const races = argumentValue("--races", 10000);
    const failures = report(engine, races, label);
    if (failures > 0) process.exitCode = 1;
  }
}
