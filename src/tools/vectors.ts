// Regenerate vectors/ from a fixed seed list.
//
//   node src/tools/vectors.ts            rewrite every vector file
//   node src/tools/vectors.ts --check    fail if any file would change
//
// A race vector is { seed, preset, level, inputs[], expected: { events[],
// finalState } } where every input is already a concrete, timestamped keystroke
// or card choice, so tests/vectors.test.ts can replay a vector without knowing
// anything about the policy that produced it.

import { writeFile, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  BELLRINGER_STREAK_THRESHOLD,
  CARDS,
  CARD_SCHEDULE,
  STREAK_THRESHOLD,
  createRace,
  dealHand,
  effectiveProgress,
  factAnswer,
  forkRng,
  lapDeck,
  nextFloat,
  nextInt,
  step,
  tablesForPreset,
  type Card,
  type PresetId,
  type RaceConfig,
  type RaceEvent,
  type RaceInput,
  type RaceState,
  type Racer,
} from "../engine/index.ts";

const root = resolve(import.meta.dirname, "../..");

export interface ScriptEntry {
  at: number;
  input: RaceInput;
}

export interface RaceVector {
  name: string;
  seed: number;
  preset: PresetId;
  chosenTables?: number[];
  /** The rival difficulty the vector was recorded at. */
  level: "rookie" | "pro" | "champion";
  mode: "practice" | "timeTrial" | "ghost" | "grandPrix";
  streakThreshold: number;
  racers: { id: string; kind: "human" | "rival" }[];
  /** A forced dealing schedule, when the vector needs specific cards in hand. */
  schedule?: Card[];
  inputs: ScriptEntry[];
  expected: { events: RaceEvent[]; finalState: RaceState };
}

export const RACE_SEEDS = [1, 7, 42, 1337, 20260902];

const ACTION_MS = 700;

/**
 * Drive one race with a deterministic policy and record the concrete inputs it
 * chose. The policy is not part of the engine; it exists only to write a script
 * that exercises answers, mistakes, reveals, pit crew, hands and every card.
 */
export function recordRace(config: RaceConfig, accuracy: number, cardBias: number): RaceVector {
  const rng = forkRng(config.seed, "script:" + accuracy + ":" + cardBias);
  let state = createRace(config);
  const inputs: ScriptEntry[] = [];
  const events: RaceEvent[] = [];
  let at = 0;

  function push(input: RaceInput): void {
    at += ACTION_MS;
    inputs.push({ at, input });
    const result = step(state, input, at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }

  push({ kind: "start" });

  let guard = 0;
  while (state.status !== "finished" && guard < 20000) {
    guard += 1;
    for (const racer of state.racers) {
      if (racer.finished) continue;
      const live = state.racers.find((entry) => entry.id === racer.id)!;
      if (live.finished) continue;
      if (live.hand.length > 0 && nextFloat(rng) < cardBias) {
        const index = nextInt(rng, live.hand.length);
        const card = live.hand[index]!;
        let targetId: string | undefined;
        if (CARDS[card].scope === "targeted") {
          const options = state.racers.filter(
            (entry) => entry.id !== live.id && !entry.finished,
          );
          if (options.length === 0) continue;
          targetId = options[nextInt(rng, options.length)]!.id;
        }
        push({ kind: "useCard", racerId: live.id, index, targetId });
        continue;
      }
      const roll = nextFloat(rng);
      const answer = factAnswer(live.currentFact);
      if (roll < accuracy) push({ kind: "answer", racerId: live.id, value: answer });
      else if (roll < accuracy + 0.04) push({ kind: "hint", racerId: live.id });
      else push({ kind: "answer", racerId: live.id, value: answer + 1 });
    }
    // Push the clock past any stall so a locked field never wedges the script.
    push({ kind: "tick" });
    at += 3000;
  }
  if (state.status !== "finished") throw new Error("scripted race did not finish");

  return {
    name: "",
    seed: config.seed,
    preset: config.preset ?? "1-12",
    level: "pro",
    mode: config.mode ?? "grandPrix",
    streakThreshold: state.streakThreshold,
    racers: config.racers.map((racer) => ({ id: racer.id, kind: racer.kind ?? "rival" })),
    schedule: config.schedule === undefined ? undefined : config.schedule.slice(),
    inputs,
    expected: { events, finalState: state },
  };
}

/** Replay a recorded script. This is what the vector test asserts against. */
export function replayVector(vector: RaceVector): { events: RaceEvent[]; finalState: RaceState } {
  let state = createRace({
    seed: vector.seed,
    preset: vector.preset,
    chosenTables: vector.chosenTables,
    mode: vector.mode,
    streakThreshold: vector.streakThreshold,
    schedule: vector.schedule,
    racers: vector.racers,
  });
  const events: RaceEvent[] = [];
  for (const entry of vector.inputs) {
    const result = step(state, entry.input, entry.at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }
  return { events, finalState: state };
}

/**
 * A hand-scripted vector, because no policy-driven race has ever produced one:
 * a racer holding *two* Roll Cages, taking two attacks that are both blocked,
 * and then a third that lands.
 *
 * Without it the committed race vectors never observe `rollCagesLeft > 0` after
 * a block, so "each Roll Cage absorbs exactly one incoming attack" never crosses
 * the source/bundle boundary and a bundle that got cage consumption wrong would
 * replay byte-identically.
 *
 * The schedule is three distinct cards so every hand is the same three, and the
 * script names hand slots rather than cards.
 */
export function recordRollCageStack(): RaceVector {
  const schedule: Card[] = ["rollCage", "wrench", "oilSlick"];
  const ROLL_CAGE = 0;
  const WRENCH = 1;
  const OIL_SLICK = 2;
  const racers = [
    { id: "you", kind: "human" as const },
    { id: "bolt", kind: "rival" as const },
    { id: "piston", kind: "rival" as const },
  ];
  const config: RaceConfig = {
    seed: 20260902,
    preset: "1-12",
    mode: "grandPrix",
    streakThreshold: STREAK_THRESHOLD,
    schedule,
    racers,
  };
  let state = createRace(config);
  const inputs: ScriptEntry[] = [];
  const events: RaceEvent[] = [];
  let at = 0;

  function push(input: RaceInput): void {
    at += ACTION_MS;
    inputs.push({ at, input });
    const result = step(state, input, at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }

  function chargeAHand(racerId: string): void {
    for (let index = 0; index < STREAK_THRESHOLD; index++) {
      const live = state.racers.find((entry) => entry.id === racerId)!;
      push({ kind: "answer", racerId, value: factAnswer(live.currentFact) });
    }
    const live = state.racers.find((entry) => entry.id === racerId)!;
    if (live.hand.length !== 3) throw new Error(racerId + " did not draw a full hand");
  }

  push({ kind: "start" });

  // "you" stacks two Roll Cages, one hand each.
  chargeAHand("you");
  push({ kind: "useCard", racerId: "you", index: ROLL_CAGE });
  chargeAHand("you");
  push({ kind: "useCard", racerId: "you", index: ROLL_CAGE });

  // Three attacks: a targeted one, an area one, then a targeted one that lands.
  chargeAHand("bolt");
  push({ kind: "useCard", racerId: "bolt", index: WRENCH, targetId: "you" });
  chargeAHand("bolt");
  push({ kind: "useCard", racerId: "bolt", index: OIL_SLICK });
  chargeAHand("bolt");
  push({ kind: "useCard", racerId: "bolt", index: WRENCH, targetId: "you" });
  push({ kind: "tick" });

  const you = state.racers.find((entry) => entry.id === "you")!;
  if (you.rollCages !== 0) throw new Error("the two cages were not both consumed");
  const blocked = events.filter((event) => event.type === "blocked");
  if (blocked.length !== 2) throw new Error("expected exactly two blocks, got " + blocked.length);
  if (blocked[0]!.rollCagesLeft !== 1 || blocked[1]!.rollCagesLeft !== 0) {
    throw new Error("the cages were not consumed one at a time");
  }
  if (you.questionsNeededThisLap !== 17) throw new Error("the third attack did not land");

  return {
    name: "roll-cage-stack-20260902",
    seed: config.seed,
    preset: "1-12",
    level: "pro",
    mode: "grandPrix",
    streakThreshold: STREAK_THRESHOLD,
    racers,
    schedule: schedule.slice(),
    inputs,
    expected: { events, finalState: state },
  };
}

/**
 * The second hand-scripted vector, for the two rules the 347-step parity run
 * never witnesses (round 2 verdict, "Shared blind spots", items 1 and 2):
 *
 *  - a **Wrench that lands**. Of the eight cards this is the only magnitude the
 *    parity script never demonstrates -- its one Lightning was refused -- and
 *    the policy-driven race vectors never happen to land one unblocked either.
 *    Here `need` goes 12 -> 17 with nothing absorbing it.
 *  - **"Roll Cages stay with their owners"** through a Tow Hook. The parity
 *    run's only successful swap is between two racers who both hold `cage=0`,
 *    so the rule is asserted by nothing there. Here the attacker swaps while
 *    holding a cage and still holds it afterwards, and the victim still holds
 *    none.
 *
 * Both have named unit tests; this puts them in a committed vector as well, so
 * the committed bundle has to reproduce them too. That is the same hole class as
 * round 2's Roll Cage stacking defect.
 *
 * The schedule is three distinct cards so every hand is the same three and the
 * script can name slots rather than cards.
 */
export function recordWrenchAndTowHook(): RaceVector {
  const schedule: Card[] = ["wrench", "rollCage", "towHook"];
  const WRENCH = 0;
  const ROLL_CAGE = 1;
  const TOW_HOOK = 2;
  const racers = [
    { id: "you", kind: "human" as const },
    { id: "bolt", kind: "rival" as const },
    { id: "piston", kind: "rival" as const },
  ];
  const config: RaceConfig = {
    seed: 20260902,
    preset: "1-12",
    mode: "grandPrix",
    streakThreshold: STREAK_THRESHOLD,
    schedule,
    racers,
  };
  let state = createRace(config);
  const inputs: ScriptEntry[] = [];
  const events: RaceEvent[] = [];
  let at = 0;

  function push(input: RaceInput): void {
    at += ACTION_MS;
    inputs.push({ at, input });
    const result = step(state, input, at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }

  function live(racerId: string): Racer {
    return state.racers.find((entry) => entry.id === racerId)!;
  }

  function chargeAHand(racerId: string): void {
    for (let index = 0; index < STREAK_THRESHOLD; index++) {
      // A Wrench stalls for three seconds and the clock only moves ACTION_MS an
      // input, so nudge it past any lock before answering.
      push({ kind: "tick" });
      at += 3000;
      push({ kind: "answer", racerId, value: factAnswer(live(racerId).currentFact) });
    }
    if (live(racerId).hand.length !== 3) throw new Error(racerId + " did not draw a full hand");
  }

  push({ kind: "start" });

  // 1. A Wrench that lands: +5 on a racer with no Roll Cage.
  chargeAHand("bolt");
  const needBefore = live("piston").questionsNeededThisLap;
  push({ kind: "useCard", racerId: "bolt", index: WRENCH, targetId: "piston" });
  const needAfter = live("piston").questionsNeededThisLap;
  if (needAfter - needBefore !== 5) {
    throw new Error("the Wrench did not land +5: " + needBefore + " -> " + needAfter);
  }
  if (events.filter((event) => event.type === "blocked").length !== 0) {
    throw new Error("the Wrench was blocked; this vector needs it to land");
  }

  // 2. A Tow Hook thrown by a racer who is holding a Roll Cage. The cage must
  //    stay with its owner: a swapped cage would leave `you` on zero and
  //    `piston` on one.
  chargeAHand("you");
  push({ kind: "useCard", racerId: "you", index: ROLL_CAGE });
  if (live("you").rollCages !== 1) throw new Error("the Roll Cage did not go up");
  chargeAHand("you");
  const youBefore = [
    live("you").lapsComplete,
    live("you").correctInLap,
    live("you").questionsNeededThisLap,
  ];
  const pistonBefore = [
    live("piston").lapsComplete,
    live("piston").correctInLap,
    live("piston").questionsNeededThisLap,
  ];
  if (
    youBefore[0] === pistonBefore[0] &&
    youBefore[1] === pistonBefore[1] &&
    youBefore[2] === pistonBefore[2]
  ) {
    throw new Error("the two positions are identical, so a swap would prove nothing");
  }
  push({ kind: "useCard", racerId: "you", index: TOW_HOOK, targetId: "piston" });
  if (events.filter((event) => event.type === "swap").length !== 1) {
    throw new Error("the Tow Hook did not swap: the victim must hold no cage");
  }
  const youAfter = [
    live("you").lapsComplete,
    live("you").correctInLap,
    live("you").questionsNeededThisLap,
  ];
  if (youAfter[0] !== pistonBefore[0] || youAfter[2] !== pistonBefore[2]) {
    throw new Error("the positions did not swap");
  }
  if (live("you").rollCages !== 1 || live("piston").rollCages !== 0) {
    throw new Error(
      "a Roll Cage moved with the swap: you=" +
        live("you").rollCages +
        " piston=" +
        live("piston").rollCages,
    );
  }
  push({ kind: "tick" });

  return {
    name: "wrench-and-tow-hook-20260902",
    seed: config.seed,
    preset: "1-12",
    level: "pro",
    mode: "grandPrix",
    streakThreshold: STREAK_THRESHOLD,
    racers,
    schedule: schedule.slice(),
    inputs,
    expected: { events, finalState: state },
  };
}

const FOUR = [
  { id: "you", kind: "human" as const },
  { id: "bolt", kind: "rival" as const },
  { id: "piston", kind: "rival" as const },
  { id: "gasket", kind: "rival" as const },
];

function buildDecks(): unknown {
  const presets: PresetId[] = ["2-5", "2-10", "1-12"];
  return {
    note:
      "Seed to lap-deck vectors, generated by this engine and pinned. The design's requirement " +
      "is that the multiplayer engine reproduce these byte for byte; that is a requirement on " +
      "any future engine, not a claim that another engine has been checked against them.",
    questionsPerLap: 12,
    decks: RACE_SEEDS.flatMap((seed) =>
      presets.map((preset) => {
        const tables = tablesForPreset(preset);
        return {
          seed,
          preset,
          tables,
          questions: tables.length * 12,
          laps: tables.map((table, lapIndex) => ({
            lapIndex,
            table,
            facts: lapDeck(seed, lapIndex, table),
          })),
        };
      }),
    ),
  };
}

function buildHands(): unknown {
  const rounds: { cursorBefore: number; hand: Card[]; cursorAfter: number }[] = [];
  let cursor = 0;
  for (let round = 0; round < 12; round++) {
    const dealt = dealHand(CARD_SCHEDULE, cursor);
    rounds.push({ cursorBefore: cursor, hand: dealt.hand, cursorAfter: dealt.cursor });
    cursor = dealt.cursor;
  }

  // The shared cursor, seen through the reducer: four racers each charge a hand
  // in turn and the cards keep marching down one schedule.
  const shared: { racerId: string; hand: Card[]; cursorAfter: number }[] = [];
  let state = createRace({ seed: 2026, preset: "1-12", racers: FOUR });
  state = step(state, { kind: "start" }, 0).state;
  let at = 0;
  for (const racer of FOUR) {
    for (let index = 0; index < STREAK_THRESHOLD; index++) {
      at += 500;
      const live = state.racers.find((entry) => entry.id === racer.id)!;
      state = step(state, { kind: "answer", racerId: racer.id, value: factAnswer(live.currentFact) }, at)
        .state;
    }
    const live = state.racers.find((entry) => entry.id === racer.id)!;
    shared.push({ racerId: racer.id, hand: live.hand.slice(), cursorAfter: state.cardCursor });
  }

  return {
    note:
      "The fixed schedule, the round-robin cursor, and the same cursor seen from four racers. " +
      "The schedule order is transcribed from Go's canonicalPowerupSchedule; the rounds and the " +
      "shared-cursor rows are this engine's output, pinned as a regression lock.",
    threshold: STREAK_THRESHOLD,
    handSize: 3,
    schedule: CARD_SCHEDULE.slice(),
    definitions: CARD_SCHEDULE.map((card) => ({
      card,
      bellringerName: CARDS[card].bellringerName,
      scope: CARDS[card].scope,
      questionDelta: CARDS[card].questionDelta,
      tier: CARDS[card].tier,
      stallMs: CARDS[card].stallMs,
    })),
    rounds,
    sharedCursorAcrossRacers: shared,
  };
}

/**
 * The bellringer's own expectations, at its own threshold of 15.
 *
 * Everything in `GO_*` below is a literal transcription from
 * `/Users/don/Developer/LiveClassBackend/internal/bellringerruntime/service_test.go`
 * -- the numbers the Go test itself asserts, copied by hand, not computed here.
 * `buildParity15` puts them in the vector file as the expected values, and
 * `tests/vectors.test.ts` runs this engine against them. That is the whole point
 * of the file: without the transcription its authority would be circular,
 * because every other vector in this repository is this engine checking itself.
 */

/**
 * `TestPowerupAwardsFollowDeterministicEightPowerSchedule`, `expectedAwards`.
 * Transcribed verbatim.
 */
const GO_FIRST_THREE_HANDS: readonly (readonly string[])[] = [
  ["FuelBoost", "GravityWell", "Lightning"],
  ["BlackHole", "Shield", "Supernova"],
  ["Turbo", "Wormhole", "FuelBoost"],
];

interface GoPosition {
  lapsComplete: number;
  correctInLap: number;
  questionsNeededThisLap: number;
}

/**
 * `TestAllEightPowerupsReturnAuthoritativePositionsAndImpacts` asserts
 * `resolution.InitiatorBeforePosition == racePosition{LapsComplete: 1,
 * CorrectInLap: 3, QuestionsNeededThisLap: 12}` for every row: a single answer
 * record of `powerupStreakThreshold` (15) questions. Answering fifteen facts one
 * at a time has to land on exactly that triple.
 */
const GO_INITIATOR_BEFORE: GoPosition = {
  lapsComplete: 1,
  correctInLap: 3,
  questionsNeededThisLap: 12,
};

interface GoPerCardRow {
  /** The Go test's `powerup` field. */
  bellringerName: string;
  /** The Go test's `target` field: "" means the card takes no target. */
  target: string;
  /** `expectedAttacker`. Go zero-values the fields it does not name. */
  expectedAttacker: GoPosition;
  /** `expectedTarget`. */
  expectedTarget: GoPosition;
  /** `expectedImpactCount`: how many racers the resolution reported changing. */
  expectedImpactCount: number;
  /** `expectedAppliedDelta`: unset in Go means zero. */
  expectedAppliedDelta: number;
  /** `expectedShieldCount`: the initiator's shields after the play. */
  expectedShieldCount: number;
}

/**
 * The eight rows of `TestAllEightPowerupsReturnAuthoritativePositionsAndImpacts`,
 * transcribed literal for literal. Go's `racePosition{QuestionsNeededThisLap: 12}`
 * is `{0, 0, 12}`, and an omitted `expectedAppliedDelta` or `expectedShieldCount`
 * is zero; both are written out here rather than left implicit.
 */
const GO_PER_CARD: readonly GoPerCardRow[] = [
  {
    bellringerName: "FuelBoost",
    target: "",
    expectedAttacker: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 8 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 12 },
    expectedImpactCount: 1,
    expectedAppliedDelta: -4,
    expectedShieldCount: 0,
  },
  {
    bellringerName: "GravityWell",
    target: "",
    expectedAttacker: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 15 },
    expectedImpactCount: 2,
    expectedAppliedDelta: 3,
    expectedShieldCount: 0,
  },
  {
    bellringerName: "Lightning",
    target: "target",
    expectedAttacker: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 17 },
    expectedImpactCount: 1,
    expectedAppliedDelta: 5,
    expectedShieldCount: 0,
  },
  {
    bellringerName: "BlackHole",
    target: "target",
    expectedAttacker: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 20 },
    expectedImpactCount: 1,
    expectedAppliedDelta: 8,
    expectedShieldCount: 0,
  },
  {
    bellringerName: "Shield",
    target: "",
    expectedAttacker: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 12 },
    expectedImpactCount: 1,
    expectedAppliedDelta: 0,
    expectedShieldCount: 1,
  },
  {
    bellringerName: "Supernova",
    target: "target",
    expectedAttacker: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 27 },
    expectedImpactCount: 1,
    expectedAppliedDelta: 15,
    expectedShieldCount: 0,
  },
  {
    bellringerName: "Turbo",
    target: "",
    expectedAttacker: { lapsComplete: 2, correctInLap: 1, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 12 },
    expectedImpactCount: 1,
    expectedAppliedDelta: -10,
    expectedShieldCount: 0,
  },
  {
    bellringerName: "Wormhole",
    target: "target",
    expectedAttacker: { lapsComplete: 0, correctInLap: 0, questionsNeededThisLap: 12 },
    expectedTarget: { lapsComplete: 1, correctInLap: 3, questionsNeededThisLap: 12 },
    expectedImpactCount: 1,
    expectedAppliedDelta: 0,
    expectedShieldCount: 0,
  },
];

/**
 * `TestShieldBlocksAndIsConsumedByNextAttack`: the target holds one Shield, a
 * Lightning is thrown at it, the resolution reports `ShieldAbsorbed` with an
 * applied delta of zero, and the target is left with no shield and its
 * requirement untouched at twelve.
 */
const GO_SHIELD_BLOCK = {
  attackerPowerup: "Lightning",
  shieldAbsorbed: true,
  appliedQuestionDelta: 0,
  targetShieldCountAfter: 0,
  targetQuestionsNeededThisLap: 12,
};

/**
 * The garage names for the bellringer's, from the design's Powerups table. A
 * naming table, not a computed value; the Go literals above stay in Go's
 * vocabulary and this is the only place the two vocabularies meet.
 */
const GARAGE_NAME_FOR: Readonly<Record<string, Card>> = {
  FuelBoost: "nitro",
  GravityWell: "oilSlick",
  Lightning: "wrench",
  BlackHole: "pothole",
  Shield: "rollCage",
  Supernova: "pileUp",
  Turbo: "turbo",
  Wormhole: "towHook",
};

function buildParity15(): unknown {
  return {
    note:
      "The bellringer's threshold of 15 and the literal expectations transcribed from " +
      "internal/bellringerruntime/service_test.go. firstThreeHands comes from " +
      "TestPowerupAwardsFollowDeterministicEightPowerSchedule's expectedAwards; " +
      "initiatorBefore and every perCard row come from " +
      "TestAllEightPowerupsReturnAuthoritativePositionsAndImpacts's table; shieldBlock comes " +
      "from TestShieldBlocksAndIsConsumedByNextAttack. These are Go's numbers, copied by hand, " +
      "and tests/vectors.test.ts asserts THIS engine against them. Two things in this file are " +
      "not Go's: the garage-name column, which is the design's Powerups table, and " +
      "attackerPositionAfterFifteenAnswers.effectiveProgressDerived, which Go does not compute at " +
      "all and which is derived here from Go's own triple by the design's effective-progress " +
      "formula (1 x 12 + 3 - (12 - 12) = 15).",
    provenance: {
      file: "internal/bellringerruntime/service_test.go",
      repository: "/Users/don/Developer/LiveClassBackend",
      tests: [
        "TestPowerupAwardsFollowDeterministicEightPowerSchedule",
        "TestAllEightPowerupsReturnAuthoritativePositionsAndImpacts",
        "TestShieldBlocksAndIsConsumedByNextAttack",
      ],
      transcribedByHand: true,
      generatedByThisEngine: false,
    },
    threshold: BELLRINGER_STREAK_THRESHOLD,
    bellringerSchedule: GO_PER_CARD.map((row) => row.bellringerName),
    firstThreeHands: GO_FIRST_THREE_HANDS.map((hand, index) => ({
      handNumber: index + 1,
      bellringerHand: hand.slice(),
      hand: hand.map((name) => GARAGE_NAME_FOR[name]!),
    })),
    attackerPositionAfterFifteenAnswers: {
      lapsComplete: GO_INITIATOR_BEFORE.lapsComplete,
      correctInLap: GO_INITIATOR_BEFORE.correctInLap,
      questionsNeededThisLap: GO_INITIATOR_BEFORE.questionsNeededThisLap,
      effectiveProgressDerived: 15,
    },
    perCard: GO_PER_CARD.map((row) => ({
      card: GARAGE_NAME_FOR[row.bellringerName]!,
      bellringerName: row.bellringerName,
      target: row.target,
      initiatorBefore: GO_INITIATOR_BEFORE,
      initiatorAfter: row.expectedAttacker,
      targetAfter: row.expectedTarget,
      impactCount: row.expectedImpactCount,
      appliedQuestionDelta: row.expectedAppliedDelta,
      rollCagesAfter: row.expectedShieldCount,
    })),
    shieldBlock: GO_SHIELD_BLOCK,
  };
}

function buildRaces(): unknown {
  const vectors: RaceVector[] = [];
  for (const seed of RACE_SEEDS) {
    const vector = recordRace(
      { seed, preset: "2-5", mode: "grandPrix", racers: FOUR },
      0.86,
      0.55,
    );
    vector.name = "grand-prix-2-5-" + seed;
    vectors.push(vector);
  }
  const full = recordRace(
    { seed: 20260902, preset: "1-12", mode: "grandPrix", racers: FOUR },
    0.9,
    0.5,
  );
  full.name = "grand-prix-1-12-20260902";
  vectors.push(full);

  const solo = recordRace(
    {
      seed: 42,
      preset: "2-10",
      mode: "timeTrial",
      racers: [{ id: "you", kind: "human" }],
    },
    0.88,
    0,
  );
  solo.name = "time-trial-2-10-42";
  vectors.push(solo);

  vectors.push(recordRollCageStack());
  vectors.push(recordWrenchAndTowHook());

  return {
    note:
      "Full reducer vectors: concrete timestamped inputs, the events they emit, and the final " +
      "state. The expected blocks are THIS engine's own output, recorded once and pinned as a " +
      "regression lock. They are not a transcription of any other runtime and witness nothing " +
      "about the bellringer; the only cross-runtime evidence lives in the separate parity " +
      "harness and in vectors/parity-15.json's transcribed Go constants.",
    vectors,
  };
}

export const VECTOR_FILES: { path: string; build: () => unknown }[] = [
  { path: "vectors/decks.json", build: buildDecks },
  { path: "vectors/hands.json", build: buildHands },
  { path: "vectors/races.json", build: buildRaces },
  { path: "vectors/parity-15.json", build: buildParity15 },
];

export function serialise(value: unknown): string {
  return JSON.stringify(value, null, 2) + "\n";
}

async function main(check: boolean): Promise<void> {
  let stale = 0;
  for (const file of VECTOR_FILES) {
    const contents = serialise(file.build());
    const target = resolve(root, file.path);
    if (check) {
      let existing = "";
      try {
        existing = await readFile(target, "utf8");
      } catch {}
      if (existing !== contents) {
        console.error(file.path + " is stale; run node src/tools/vectors.ts");
        stale += 1;
      } else {
        console.log(file.path + " up to date (" + contents.length + " bytes)");
      }
    } else {
      await writeFile(target, contents);
      console.log("wrote " + file.path + " (" + contents.length + " bytes)");
    }
  }
  if (stale > 0) process.exitCode = 1;
}

// Only regenerate when this file is the program being run; importing it from a
// test must have no side effects.
const invoked = (process.argv[1] ?? "").replace(/\\/g, "/");
if (invoked.endsWith("src/tools/vectors.ts")) {
  await main(process.argv.indexOf("--check") !== -1);
}
