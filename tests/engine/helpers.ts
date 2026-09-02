// Shared scaffolding for the layer 1 specs. Nothing here asserts a rule; the
// rules are asserted in the *.spec.ts files, one named test per design line.
//
// Every helper is bound to an engine rather than importing one, because each
// spec is run twice: once against src/engine and once against the committed
// bundle engine/engine.mjs. See tests/engine.test.ts.

import type * as EngineModule from "../../src/engine/index.ts";
import type {
  Card,
  RaceConfig,
  RaceEvent,
  RaceState,
  Racer,
} from "../../src/engine/index.ts";

export type Engine = typeof EngineModule;

export const FOUR_RACERS = [
  { id: "you", kind: "human" as const },
  { id: "bolt", kind: "rival" as const },
  { id: "piston", kind: "rival" as const },
  { id: "gasket", kind: "rival" as const },
];

export interface Harness {
  state: RaceState;
  events: RaceEvent[];
  now: number;
}

export function helpersFor(E: Engine) {
  const { createRace, factAnswer, step } = E;

  /** A started race with the given overrides, clock at zero. */
  function startRace(overrides: Partial<RaceConfig> = {}): Harness {
    const config: RaceConfig = {
      seed: 2026,
      preset: "1-12",
      mode: "grandPrix",
      racers: FOUR_RACERS,
      ...overrides,
    };
    const created = createRace(config);
    const started = step(created, { kind: "start" }, 0);
    return { state: started.state, events: started.events.slice(), now: 0 };
  }

  /** Apply one input at `now + advanceMs`, keeping every event emitted so far. */
  function apply(
    harness: Harness,
    input: Parameters<typeof step>[1],
    advanceMs = 1000,
  ): RaceEvent[] {
    harness.now += advanceMs;
    const result = step(harness.state, input, harness.now);
    harness.state = result.state;
    for (const event of result.events) harness.events.push(event);
    return result.events;
  }

  function racer(harness: Harness, id: string): Racer {
    const found = harness.state.racers.find((entry) => entry.id === id);
    if (!found) throw new Error("no racer " + id);
    return found;
  }

  /** Answer the current fact correctly. */
  function answerRight(harness: Harness, id = "you", advanceMs = 1000): RaceEvent[] {
    const target = racer(harness, id);
    return apply(
      harness,
      { kind: "answer", racerId: id, value: factAnswer(target.currentFact) },
      advanceMs,
    );
  }

  /** Answer the current fact with something that is definitely not the answer. */
  function answerWrong(harness: Harness, id = "you", advanceMs = 1000): RaceEvent[] {
    const target = racer(harness, id);
    return apply(
      harness,
      { kind: "answer", racerId: id, value: factAnswer(target.currentFact) + 1 },
      advanceMs,
    );
  }

  function answerRightTimes(harness: Harness, count: number, id = "you"): void {
    for (let index = 0; index < count; index++) answerRight(harness, id);
  }

  /** Charge and hold a hand, then return it. */
  function earnHand(harness: Harness, id = "you"): Card[] {
    const threshold = harness.state.streakThreshold;
    for (let index = 0; index < threshold; index++) answerRight(harness, id);
    return racer(harness, id).hand.slice();
  }

  /** Play the named card out of a racer's hand. */
  function playCard(
    harness: Harness,
    id: string,
    card: Card,
    targetId?: string,
    advanceMs = 1000,
  ): RaceEvent[] {
    const index = racer(harness, id).hand.indexOf(card);
    if (index < 0) throw new Error(id + " does not hold " + card);
    return apply(harness, { kind: "useCard", racerId: id, index, targetId }, advanceMs);
  }

  /** Force a racer to hold exactly this hand, bypassing the streak. */
  function giveHand(harness: Harness, id: string, hand: Card[]): void {
    racer(harness, id).hand = hand.slice();
  }

  function eventsOfType<T extends RaceEvent["type"]>(
    events: readonly RaceEvent[],
    type: T,
  ): Extract<RaceEvent, { type: T }>[] {
    return events.filter((event) => event.type === type) as Extract<RaceEvent, { type: T }>[];
  }

  function position(target: Racer): [number, number, number] {
    return [target.lapsComplete, target.correctInLap, target.questionsNeededThisLap];
  }

  return {
    startRace,
    apply,
    racer,
    answerRight,
    answerWrong,
    answerRightTimes,
    earnHand,
    playCard,
    giveHand,
    eventsOfType,
    position,
  };
}
