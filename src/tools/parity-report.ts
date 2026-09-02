// Replays the shared parity script through the Turbo Tables engine and prints
// one event per line in the same normalised text form the Go driver prints.
//
//   node src/tools/parity-report.ts <script.json>
//
// The script says only what a racer did -- answered, answered wrongly, took a
// hint, or played hand slot i at a target. Facts, decks, timers and the stall
// lock never appear in it, so the two runtimes can be compared line for line.
//
// The clock advances ten seconds an action so a stall, which the other runtime
// has no concept of, can never swallow a scripted answer.

import { readFile } from "node:fs/promises";
import {
  CARDS,
  CARD_SCHEDULE,
  createRace,
  effectiveProgress,
  factAnswer,
  racerById,
  step,
  type Card,
  type RaceEvent,
  type RaceState,
  type Racer,
} from "../engine/index.ts";

const CLOCK_STEP = 10000;

interface ScriptStep {
  n: number;
  act: "answer" | "hint" | "card";
  racer: string;
  outcome?: "correct" | "wrong";
  slot?: number;
  card?: string;
  target?: string;
  expectRefused?: string;
}

interface Script {
  seed: number;
  preset: "2-5" | "2-10" | "1-12" | "choose";
  totalLaps: number;
  questionsPerLap: number;
  streakThreshold: number;
  racers: { id: string; kind: "human" | "rival" }[];
  steps: ScriptStep[];
}

const path = process.argv[2];
if (!path) {
  console.error("usage: node src/tools/parity-report.ts <script.json>");
  process.exit(2);
}
const plan: Script = JSON.parse(await readFile(path, "utf8"));

const bellringerName = (card: Card): string => CARDS[card].bellringerName;
const byBellringerName = new Map<string, Card>(
  CARD_SCHEDULE.map((card) => [CARDS[card].bellringerName, card]),
);
void byBellringerName;

interface Line {
  laps: number;
  lap: number;
  need: number;
  progress: number;
  cage: number;
  finished: boolean;
  hand: string;
}

function handOf(racer: Racer): string {
  if (racer.hand.length === 0) return "-";
  return racer.hand.map(bellringerName).join("|");
}

function lineOf(racer: Racer): Line {
  return {
    laps: racer.lapsComplete,
    lap: racer.correctInLap,
    need: racer.questionsNeededThisLap,
    progress: effectiveProgress(racer),
    cage: racer.rollCages,
    finished: racer.finished,
    hand: handOf(racer),
  };
}

function snapshot(state: RaceState): Record<string, Line> {
  const result: Record<string, Line> = {};
  for (const racer of state.racers) result[racer.id] = lineOf(racer);
  return result;
}

const order = plan.racers.map((racer) => racer.id);
const out: string[] = [];
let current = 0;

function emit(kind: string, rest: string): void {
  out.push(String(current).padStart(3, "0") + " " + kind + " " + rest);
}

function states(before: Record<string, Line>, after: Record<string, Line>): void {
  for (const id of order) {
    const was = before[id]!;
    const now = after[id]!;
    if (
      was.laps === now.laps &&
      was.lap === now.lap &&
      was.need === now.need &&
      was.cage === now.cage &&
      was.finished === now.finished &&
      was.hand === now.hand
    ) {
      continue;
    }
    emit(
      "ST",
      id +
        " laps=" + now.laps +
        " lap=" + now.lap +
        " need=" + now.need +
        " prog=" + now.progress +
        " cage=" + now.cage +
        " fin=" + (now.finished ? 1 : 0) +
        " hand=" + now.hand,
    );
  }
}

/**
 * Translate the engine's events into the shared vocabulary. `passed` and
 * `passedBy` are dropped: they are the race view's callouts, and the other
 * runtime has no notion of them.
 */
function emitEvents(events: readonly RaceEvent[]): void {
  for (const event of events) {
    switch (event.type) {
      case "correct":
        emit("EV", "correct " + event.racerId);
        break;
      case "wrong":
        emit("EV", "wrong " + event.racerId);
        break;
      case "reveal":
        emit("EV", "reveal " + event.racerId);
        break;
      case "pitCrew":
        emit("EV", "hint " + event.racerId);
        break;
      case "lapComplete":
        emit("EV", "lap " + event.racerId + " " + event.lapsComplete);
        break;
      case "finished":
        emit("EV", "finish " + event.racerId);
        break;
      case "handDealt":
        emit("EV", "hand " + event.racerId + " " + event.hand.map(bellringerName).join("|"));
        break;
      case "cardUsed": {
        emit(
          "EV",
          "card " + event.racerId + " " + bellringerName(event.card) + " " +
            (event.targetId === "" ? "-" : event.targetId),
        );
        // A Roll Cage has no delta and no victim; the other runtime reports it
        // as one impact carrying the owner's new shield count.
        if (event.card === "rollCage") {
          const owner = racerById(state, event.racerId);
          if (owner !== null) emit("EV", "cage " + event.racerId + " " + owner.rollCages);
        }
        break;
      }
      case "hit":
        emit(
          "EV",
          "hit " + event.racerId + " " + bellringerName(event.card) +
            " delta=" + event.questionDelta,
        );
        break;
      case "blocked":
        emit(
          "EV",
          "blocked " + event.racerId + " " + bellringerName(event.card) +
            " cages=" + event.rollCagesLeft,
        );
        break;
      case "swap":
        emit("EV", "swap " + event.racerId + " " + event.withId);
        break;
      default:
        break;
    }
  }
}

/**
 * The other runtime answers a refused card play with a rejection code. Derive
 * the same code from the same conditions so the two transcripts line up.
 */
function refusalCode(state: RaceState, racerId: string, card: Card, targetId: string): string {
  const attacker = racerById(state, racerId);
  if (attacker === null || attacker.finished) return "runtime_not_active";
  const definition = CARDS[card];
  if (definition.scope === "targeted") {
    if (targetId === "" || targetId === racerId) return "invalid_target";
    const target = racerById(state, targetId);
    if (target === null || target.finished) return "invalid_target";
  } else if (targetId !== "") {
    return "unexpected_target";
  }
  return "runtime_rejected";
}

// ---------------------------------------------------------------------------

let state = createRace({
  seed: plan.seed,
  preset: plan.preset,
  mode: "grandPrix",
  streakThreshold: plan.streakThreshold,
  racers: plan.racers,
});
let clock = 0;
state = step(state, { kind: "start" }, (clock += CLOCK_STEP)).state;

out.push("### turbo tables engine, driven through step(state, input, now)");
out.push(
  "CFG racers=" + order.join(",") +
    " laps=" + plan.totalLaps +
    " perLap=" + plan.questionsPerLap +
    " threshold=" + plan.streakThreshold,
);

for (const action of plan.steps) {
  current = action.n;
  const before = snapshot(state);

  if (action.act === "answer" || action.act === "hint") {
    const racer = racerById(state, action.racer)!;
    const detail = action.act === "hint" ? "forced" : action.outcome!;
    emit("ACT", action.act + " " + action.racer + " " + detail);
    const input =
      action.act === "hint"
        ? ({ kind: "hint", racerId: action.racer } as const)
        : ({
            kind: "answer",
            racerId: action.racer,
            value:
              action.outcome === "correct"
                ? factAnswer(racer.currentFact)
                : factAnswer(racer.currentFact) + 1,
          } as const);
    const result = step(state, input, (clock += CLOCK_STEP));
    state = result.state;
    emitEvents(result.events);
    states(before, snapshot(state));
    continue;
  }

  const actor = racerById(state, action.racer)!;
  const slot = action.slot ?? 0;
  if (slot >= actor.hand.length) {
    emit(
      "ACT",
      "card " + action.racer + " slot" + slot + " " + (action.card ?? "?") + " -> " +
        (action.target ? action.target : "-"),
    );
    emit("EV", "refused " + action.racer + " slot_not_held");
    continue;
  }
  const card = actor.hand[slot]!;
  emit(
    "ACT",
    "card " + action.racer + " slot" + slot + " " + bellringerName(card) + " -> " +
      (action.target ? action.target : "-"),
  );
  const result = step(
    state,
    { kind: "useCard", racerId: action.racer, index: slot, targetId: action.target },
    (clock += CLOCK_STEP),
  );
  if (result.events.length === 0) {
    emit(
      "EV",
      "refused " + action.racer + " " + refusalCode(state, action.racer, card, action.target ?? ""),
    );
    state = result.state;
    continue;
  }
  state = result.state;
  emitEvents(result.events);
  states(before, snapshot(state));
}

out.push("END");
for (const id of order) {
  const racer = racerById(state, id)!;
  out.push(
    "FIN " + id +
      " laps=" + racer.lapsComplete +
      " lap=" + racer.correctInLap +
      " need=" + racer.questionsNeededThisLap +
      " prog=" + effectiveProgress(racer) +
      " cage=" + racer.rollCages +
      " fin=" + (racer.finished ? 1 : 0) +
      " hand=" + handOf(racer) +
      " answered=" + racer.attemptCount +
      " streak=" + racer.streak,
  );
}

console.log(out.join("\n"));
