// Every committed vector is replayed twice: once through the TypeScript source
// under src/engine, and once through the committed bundle engine/engine.mjs
// loaded as a module. The two must agree with each other and with the file.
//
// Plan, "TypeScript into QML": "tests/vectors.test.ts replays every vector
// through the TypeScript source and, separately, through engine/engine.mjs
// loaded as a module, and requires identical output."

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import * as source from "../src/engine/index.ts";

const root = resolve(import.meta.dirname, "..");
const bundle = (await import(resolve(root, "engine/engine.mjs"))) as typeof source;

type Engine = typeof source;

const ENGINES: [string, Engine][] = [
  ["src/engine (TypeScript source)", source],
  ["engine/engine.mjs (committed bundle)", bundle],
];

async function loadVector(name: string): Promise<any> {
  return JSON.parse(await readFile(resolve(root, "vectors/" + name), "utf8"));
}

const decks = await loadVector("decks.json");
const hands = await loadVector("hands.json");
const races = await loadVector("races.json");
const parity = await loadVector("parity-15.json");

function replay(engine: Engine, vector: any): { events: unknown[]; finalState: unknown } {
  let state = engine.createRace({
    seed: vector.seed,
    preset: vector.preset,
    chosenTables: vector.chosenTables,
    mode: vector.mode,
    streakThreshold: vector.streakThreshold,
    schedule: vector.schedule,
    racers: vector.racers,
  });
  const events: unknown[] = [];
  for (const entry of vector.inputs) {
    const result = engine.step(state, entry.input, entry.at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }
  return { events, finalState: state };
}

test("vectors: the committed bundle exports the same engine surface as the source", () => {
  const missing = Object.keys(source).filter((name) => !(name in bundle));
  assert.deepEqual(missing, []);
});

for (const [label, engine] of ENGINES) {
  test("vectors: decks.json replays through " + label, () => {
    for (const deck of decks.decks) {
      assert.deepEqual(engine.tablesForPreset(deck.preset), deck.tables, deck.preset);
      assert.equal(deck.questions, deck.tables.length * decks.questionsPerLap);
      for (const lap of deck.laps) {
        assert.deepEqual(
          engine.lapDeck(deck.seed, lap.lapIndex, lap.table),
          lap.facts,
          "seed " + deck.seed + " preset " + deck.preset + " lap " + lap.lapIndex,
        );
      }
    }
  });

  test("vectors: hands.json replays through " + label, () => {
    assert.deepEqual(engine.CARD_SCHEDULE.slice(), hands.schedule);
    assert.equal(engine.STREAK_THRESHOLD, hands.threshold);
    assert.equal(engine.HAND_SIZE, hands.handSize);
    for (const round of hands.rounds) {
      const dealt = engine.dealHand(engine.CARD_SCHEDULE, round.cursorBefore);
      assert.deepEqual(dealt.hand, round.hand, "cursor " + round.cursorBefore);
      assert.equal(dealt.cursor, round.cursorAfter);
    }
    for (const definition of hands.definitions) {
      const card = engine.CARDS[definition.card as keyof typeof engine.CARDS];
      assert.equal(card.bellringerName, definition.bellringerName);
      assert.equal(card.scope, definition.scope);
      assert.equal(card.questionDelta, definition.questionDelta);
      assert.equal(card.tier, definition.tier);
      assert.equal(card.stallMs, definition.stallMs);
    }
  });

  test("vectors: the shared hand cursor in hands.json replays through " + label, () => {
    const racers = hands.sharedCursorAcrossRacers.map((entry: any, index: number) => ({
      id: entry.racerId,
      kind: index === 0 ? ("human" as const) : ("rival" as const),
    }));
    let state = engine.createRace({ seed: 2026, preset: "1-12", racers });
    state = engine.step(state, { kind: "start" }, 0).state;
    let at = 0;
    for (const expected of hands.sharedCursorAcrossRacers) {
      for (let index = 0; index < hands.threshold; index++) {
        at += 500;
        const live = state.racers.find((entry) => entry.id === expected.racerId)!;
        state = engine.step(
          state,
          { kind: "answer", racerId: expected.racerId, value: engine.factAnswer(live.currentFact) },
          at,
        ).state;
      }
      const live = state.racers.find((entry) => entry.id === expected.racerId)!;
      assert.deepEqual(live.hand, expected.hand, expected.racerId);
      assert.equal(state.cardCursor, expected.cursorAfter, expected.racerId);
    }
  });

  test("vectors: the hands transcribed from the Go test replay through " + label, () => {
    // parity-15.json's numbers are transcribed by hand from
    // internal/bellringerruntime/service_test.go. This asserts our engine
    // against Go's literals, not against its own recorded output.
    assert.equal(parity.provenance.transcribedByHand, true);
    assert.equal(parity.provenance.generatedByThisEngine, false);
    assert.equal(engine.BELLRINGER_STREAK_THRESHOLD, parity.threshold);
    assert.deepEqual(
      engine.CARD_SCHEDULE.map((card) => engine.CARDS[card].bellringerName),
      parity.bellringerSchedule,
    );
    const racers = [
      { id: "attacker", kind: "human" as const },
      { id: "target", kind: "rival" as const },
      { id: "observer", kind: "rival" as const },
    ];
    let state = engine.createRace({
      seed: 2026,
      preset: "1-12",
      streakThreshold: parity.threshold,
      racers,
    });
    state = engine.step(state, { kind: "start" }, 0).state;
    let at = 0;
    for (const expected of parity.firstThreeHands) {
      for (let index = 0; index < parity.threshold; index++) {
        at += 500;
        const live = state.racers.find((entry) => entry.id === "attacker")!;
        state = engine.step(
          state,
          { kind: "answer", racerId: "attacker", value: engine.factAnswer(live.currentFact) },
          at,
        ).state;
      }
      const live = state.racers.find((entry) => entry.id === "attacker")!;
      assert.deepEqual(live.hand, expected.hand, "hand " + expected.handNumber);
      assert.deepEqual(
        live.hand.map((card) => engine.CARDS[card].bellringerName),
        expected.bellringerHand,
        "Go's expectedAwards row " + expected.handNumber,
      );
      if (expected.handNumber === 1) {
        const position = parity.attackerPositionAfterFifteenAnswers;
        assert.equal(live.lapsComplete, position.lapsComplete);
        assert.equal(live.correctInLap, position.correctInLap);
        assert.equal(live.questionsNeededThisLap, position.questionsNeededThisLap);
        // Go does not compute effective progress; this is the design's formula
        // applied to Go's own triple, and the vector says so.
        assert.equal(engine.effectiveProgress(live), position.effectiveProgressDerived);
      }
      at += 500;
      const card = live.hand[0]!;
      const targetId = engine.CARDS[card].scope === "targeted" ? "target" : undefined;
      state = engine.step(state, { kind: "useCard", racerId: "attacker", index: 0, targetId }, at)
        .state;
    }
  });

  test("vectors: the eight-row Go table in parity-15.json replays through " + label, () => {
    for (const expected of parity.perCard) {
      const racers = [
        { id: "attacker", kind: "human" as const },
        { id: "target", kind: "rival" as const },
        { id: "observer", kind: "rival" as const },
      ];
      let state = engine.createRace({
        seed: 2026,
        preset: "1-12",
        streakThreshold: parity.threshold,
        schedule: [expected.card],
        racers,
      });
      state = engine.step(state, { kind: "start" }, 0).state;
      let at = 0;
      for (let index = 0; index < parity.threshold; index++) {
        at += 500;
        const live = state.racers.find((entry) => entry.id === "attacker")!;
        state = engine.step(
          state,
          { kind: "answer", racerId: "attacker", value: engine.factAnswer(live.currentFact) },
          at,
        ).state;
      }
      const before = state.racers.find((entry) => entry.id === "attacker")!;
      assert.deepEqual(
        {
          lapsComplete: before.lapsComplete,
          correctInLap: before.correctInLap,
          questionsNeededThisLap: before.questionsNeededThisLap,
        },
        expected.initiatorBefore,
        expected.card + ": Go's InitiatorBeforePosition",
      );
      const cagesBefore = before.rollCages;
      at += 500;
      // Go's `target` field is "" for the cards that take no target.
      const targetId = expected.target === "" ? undefined : expected.target;
      const played = engine.step(
        state,
        { kind: "useCard", racerId: "attacker", index: 0, targetId },
        at,
      );
      state = played.state;
      const after = state.racers.find((entry) => entry.id === "attacker")!;
      const victim = state.racers.find((entry) => entry.id === "target")!;
      assert.deepEqual(
        {
          lapsComplete: after.lapsComplete,
          correctInLap: after.correctInLap,
          questionsNeededThisLap: after.questionsNeededThisLap,
        },
        expected.initiatorAfter,
        expected.card + ": Go's expectedAttacker",
      );
      assert.deepEqual(
        {
          lapsComplete: victim.lapsComplete,
          correctInLap: victim.correctInLap,
          questionsNeededThisLap: victim.questionsNeededThisLap,
        },
        expected.targetAfter,
        expected.card + ": Go's expectedTarget",
      );
      assert.equal(
        after.rollCages,
        expected.rollCagesAfter,
        expected.card + ": Go's expectedShieldCount",
      );
      // Go's expectedImpactCount is how many racers the resolution changed. Our
      // engine says the same thing with events, plus the shield it granted its
      // own owner, which Go counts as an impact and we carry on the state.
      const touched = played.events.filter(
        (event) => event.type === "hit" || event.type === "blocked" || event.type === "swap",
      );
      assert.equal(
        touched.length + (after.rollCages - cagesBefore),
        expected.impactCount,
        expected.card + ": Go's expectedImpactCount",
      );
      const hits = played.events.filter((event) => event.type === "hit");
      const delta = hits.length === 0 ? 0 : (hits[0] as { questionDelta: number }).questionDelta;
      assert.equal(
        delta,
        expected.appliedQuestionDelta,
        expected.card + ": Go's expectedAppliedDelta",
      );
    }
  });

  test("vectors: Go's TestShieldBlocksAndIsConsumedByNextAttack replays through " + label, () => {
    const block = parity.shieldBlock;
    const racers = [
      { id: "attacker", kind: "human" as const },
      { id: "target", kind: "rival" as const },
      { id: "observer", kind: "rival" as const },
    ];
    const shield = engine.cardByBellringerName("Shield")!;
    const attack = engine.cardByBellringerName(block.attackerPowerup)!;
    let state = engine.createRace({
      seed: 2026,
      preset: "1-12",
      streakThreshold: parity.threshold,
      schedule: [shield, attack],
      racers,
    });
    state = engine.step(state, { kind: "start" }, 0).state;
    let at = 0;
    function charge(racerId: string): void {
      for (let index = 0; index < parity.threshold; index++) {
        at += 500;
        const live = state.racers.find((entry) => entry.id === racerId)!;
        state = engine.step(
          state,
          { kind: "answer", racerId, value: engine.factAnswer(live.currentFact) },
          at,
        ).state;
      }
    }
    charge("target");
    at += 500;
    const shieldIndex = state.racers
      .find((entry) => entry.id === "target")!
      .hand.indexOf(shield);
    state = engine.step(state, { kind: "useCard", racerId: "target", index: shieldIndex }, at).state;
    charge("attacker");
    at += 500;
    const attackIndex = state.racers
      .find((entry) => entry.id === "attacker")!
      .hand.indexOf(attack);
    const played = engine.step(
      state,
      { kind: "useCard", racerId: "attacker", index: attackIndex, targetId: "target" },
      at,
    );
    const blocked = played.events.filter((event) => event.type === "blocked");
    assert.equal(blocked.length === 1, block.shieldAbsorbed, "Go's ShieldAbsorbed");
    assert.equal(
      played.events.filter((event) => event.type === "hit").length,
      block.appliedQuestionDelta,
      "Go's AppliedQuestionDelta of zero means nothing landed",
    );
    const victim = played.state.racers.find((entry) => entry.id === "target")!;
    assert.equal(victim.rollCages, block.targetShieldCountAfter, "Go's target.ShieldCount");
    assert.equal(
      victim.questionsNeededThisLap,
      block.targetQuestionsNeededThisLap,
      "Go's target.QuestionsNeededThisLap",
    );
  });

  for (const vector of races.vectors) {
    test("vectors: race " + vector.name + " replays through " + label, () => {
      const replayed = replay(engine, vector);
      assert.deepEqual(replayed.events, vector.expected.events, "events");
      assert.deepEqual(replayed.finalState, vector.expected.finalState, "final state");
    });
  }
}

test("vectors: source and bundle produce byte-identical race output", () => {
  for (const vector of races.vectors) {
    const fromSource = JSON.stringify(replay(source, vector));
    const fromBundle = JSON.stringify(replay(bundle, vector));
    assert.equal(fromSource, fromBundle, vector.name);
  }
});

test("vectors: the race vectors exercise every card, reveal, pit crew and block", () => {
  const seen = new Set<string>();
  for (const vector of races.vectors) {
    for (const event of vector.expected.events) {
      seen.add(event.type);
      if (event.type === "cardUsed") seen.add("card:" + event.card);
    }
  }
  for (const type of ["correct", "wrong", "reveal", "pitCrew", "lapComplete", "handDealt", "cardUsed", "hit", "blocked", "swap", "passed", "passedBy", "finished"]) {
    assert.ok(seen.has(type), "no " + type + " event in any race vector");
  }
  for (const card of source.CARD_SCHEDULE) {
    assert.ok(seen.has("card:" + card), "no vector ever played " + card);
  }
});

test("vectors: some vector lands every card's own magnitude, unblocked", () => {
  // Playing a card is not the same as landing it. Round 2's parity run played a
  // Wrench once and had it refused, so +5 -- the one magnitude of the eight the
  // run never demonstrated -- was witnessed by no committed artefact at all.
  // This asserts the deltas the vectors actually *apply*, card by card.
  const landed = new Map<string, Set<number>>();
  for (const vector of races.vectors) {
    for (const event of vector.expected.events) {
      if (event.type !== "hit") continue;
      if (!landed.has(event.card)) landed.set(event.card, new Set());
      landed.get(event.card)!.add(event.questionDelta);
    }
  }
  for (const card of source.CARD_SCHEDULE) {
    const expected = source.CARDS[card].questionDelta;
    if (expected === 0) continue; // Roll Cage and Tow Hook emit no hit at all
    assert.ok(
      landed.get(card)?.has(expected),
      "no vector ever lands " + card + " for its delta of " + expected,
    );
  }
});

test("vectors: some vector swaps positions with a Tow Hook while a Roll Cage is held, and the cage stays", () => {
  // Design, Powerups: "Roll Cages stay with their owners." Round 2's parity run
  // never witnessed this -- its only successful swap had cage 0 on both sides --
  // and neither did any vector here until this one.
  let witnessed = 0;
  for (const [label, engine] of ENGINES) {
    for (const vector of races.vectors) {
      let state = engine.createRace({
        seed: vector.seed,
        preset: vector.preset,
        chosenTables: vector.chosenTables,
        mode: vector.mode,
        streakThreshold: vector.streakThreshold,
        schedule: vector.schedule,
        racers: vector.racers,
      });
      for (const entry of vector.inputs) {
        const before = new Map(state.racers.map((racer) => [racer.id, racer.rollCages]));
        const result = engine.step(state, entry.input, entry.at);
        state = result.state;
        for (const event of result.events) {
          if (event.type !== "swap") continue;
          const attackerBefore = before.get(event.racerId) ?? 0;
          const victimBefore = before.get(event.withId) ?? 0;
          // A swap between two racers holding the same number of cages proves
          // nothing either way; only an uneven pair can witness the rule.
          if (attackerBefore === victimBefore) continue;
          const after = new Map(state.racers.map((racer) => [racer.id, racer.rollCages]));
          assert.equal(after.get(event.racerId), attackerBefore, label + ": the attacker keeps his");
          assert.equal(after.get(event.withId), victimBefore, label + ": the victim keeps hers");
          witnessed += 1;
        }
      }
    }
  }
  assert.ok(
    witnessed > 0,
    "every committed swap has the same cage count on both sides, so a swapped cage would be invisible",
  );
});
