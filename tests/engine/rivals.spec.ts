// Design section: "AI rivals" -- the table, the levels, the rubber band, the
// play policy, the mercy rules and the signals. One named test per line of it.
//
// Run twice, once against src/engine and once against the committed bundle, by
// tests/engine-piece2.test.ts.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";
import { GATE_CHILD, runRace } from "../../src/tools/rivals-report.ts";

const root = resolve(import.meta.dirname, "../..");
const vectors = JSON.parse(await readFile(resolve(root, "vectors/rivals.json"), "utf8"));

const RIVAL_SEATS = [
  { id: "bolt", personality: "bolt" as const },
  { id: "piston", personality: "piston" as const },
  { id: "gasket", personality: "gasket" as const },
];

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const {
      ATTACK_CARDS,
      BOOST_CARDS,
      HALF_LAP,
      POLICY_INTERVAL,
      RIVAL_FLOOR_MS,
      RIVAL_LEVELS,
      RIVAL_PACE_WINDOW,
      RIVAL_PROFILES,
      RUBBER_BAND_LIMIT,
      SIGNAL_CATALOG,
      childPaceMs,
      chooseTarget,
      choosePlay,
      createRace,
      createRivals,
      drawThinkTime,
      drawThinkTimeMs,
      drawWrongAnswer,
      effectiveProgress,
      factAnswer,
      forkRng,
      isEventOrdered,
      lapDeck,
      mergeSignals,
      lastPlaceIds,
      mayAttack,
      mindOf,
      rivalObserve,
      rivalStep,
      rivalTuning,
      rubberBandScale,
      step,
    } = E;
    const { answerRight, answerRightTimes, answerWrong, apply, racer, startRace } = helpersFor(E);

    /** A started Grand Prix with the three rivals wired up at one level. */
    function withRivals(level: "rookie" | "pro" | "champion" = "pro", overrides = {}) {
      const harness = startRace(overrides);
      const rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level })),
      );
      return { harness, rivals };
    }

    // ---- the table, verbatim ---------------------------------------------

    test("rivals: the design's table is the engine's table", () => {
      assert.equal(RIVAL_PROFILES.bolt.accuracyPercent, 84);
      assert.equal(RIVAL_PROFILES.bolt.thinkTimeMeanMs, 2800);
      assert.equal(RIVAL_PROFILES.bolt.thinkTimeSpreadMs, 900);
      assert.equal(RIVAL_PROFILES.piston.accuracyPercent, 91);
      assert.equal(RIVAL_PROFILES.piston.thinkTimeMeanMs, 3400);
      assert.equal(RIVAL_PROFILES.piston.thinkTimeSpreadMs, 700);
      assert.equal(RIVAL_PROFILES.gasket.accuracyPercent, 96);
      assert.equal(RIVAL_PROFILES.gasket.thinkTimeMeanMs, 4600);
      assert.equal(RIVAL_PROFILES.gasket.thinkTimeSpreadMs, 1000);
    });

    test("rivals: Pro is the table itself", () => {
      for (const seat of RIVAL_SEATS) {
        const profile = RIVAL_PROFILES[seat.personality];
        const tuning = rivalTuning(seat.personality, "pro");
        assert.equal(tuning.accuracyPercent, profile.accuracyPercent, seat.id);
        assert.equal(tuning.thinkTimeMeanMs, profile.thinkTimeMeanMs, seat.id);
        assert.equal(tuning.thinkTimeSpreadMs, profile.thinkTimeSpreadMs, seat.id);
      }
    });

    test("rivals: Rookie multiplies think time by 1.5 and subtracts 8 points of accuracy", () => {
      assert.equal(RIVAL_LEVELS.rookie.thinkTimeScale, 1.5);
      assert.equal(RIVAL_LEVELS.rookie.accuracyDelta, -8);
      for (const seat of RIVAL_SEATS) {
        const profile = RIVAL_PROFILES[seat.personality];
        const tuning = rivalTuning(seat.personality, "rookie");
        assert.equal(tuning.accuracyPercent, profile.accuracyPercent - 8, seat.id);
        assert.equal(tuning.thinkTimeMeanMs, Math.round(profile.thinkTimeMeanMs * 1.5), seat.id);
        assert.equal(tuning.thinkTimeSpreadMs, Math.round(profile.thinkTimeSpreadMs * 1.5), seat.id);
      }
    });

    test("rivals: Champion multiplies think time by 0.75 and adds 3", () => {
      assert.equal(RIVAL_LEVELS.champion.thinkTimeScale, 0.75);
      assert.equal(RIVAL_LEVELS.champion.accuracyDelta, 3);
      for (const seat of RIVAL_SEATS) {
        const profile = RIVAL_PROFILES[seat.personality];
        const tuning = rivalTuning(seat.personality, "champion");
        assert.equal(tuning.accuracyPercent, profile.accuracyPercent + 3, seat.id);
        assert.equal(tuning.thinkTimeMeanMs, Math.round(profile.thinkTimeMeanMs * 0.75), seat.id);
        assert.equal(tuning.thinkTimeSpreadMs, Math.round(profile.thinkTimeSpreadMs * 0.75), seat.id);
      }
    });

    test("rivals: the three levels order think time and accuracy the way the design does", () => {
      for (const seat of RIVAL_SEATS) {
        const rookie = rivalTuning(seat.personality, "rookie");
        const pro = rivalTuning(seat.personality, "pro");
        const champion = rivalTuning(seat.personality, "champion");
        assert.ok(rookie.thinkTimeMeanMs > pro.thinkTimeMeanMs, seat.id + " rookie is slower");
        assert.ok(pro.thinkTimeMeanMs > champion.thinkTimeMeanMs, seat.id + " champion is faster");
        assert.ok(rookie.accuracyPercent < pro.accuracyPercent, seat.id);
        assert.ok(pro.accuracyPercent < champion.accuracyPercent, seat.id);
      }
    });

    // ---- their own copy of the same deck ----------------------------------

    test("rivals: a rival answers its own copy of the same lap deck from the same seed", () => {
      const harness = startRace({ seed: 4242 });
      const deck = lapDeck(4242, 0, 1);
      for (const id of ["you", "bolt", "piston", "gasket"]) {
        assert.deepEqual(racer(harness, id).queue, deck, id);
        assert.equal(racer(harness, id).currentFact, deck[0], id);
      }
      // ...and a rival on lap seven is answering sevens.
      answerRightTimes(harness, 6 * 12, "bolt");
      const bolt = racer(harness, "bolt");
      assert.equal(bolt.lapsComplete, 6);
      assert.deepEqual(bolt.queue, lapDeck(4242, 6, 7));
    });

    // ---- the rubber band --------------------------------------------------

    test("rivals: the rubber band scales toward the child's pace and never past ±15%", () => {
      assert.equal(RUBBER_BAND_LIMIT, 0.15);
      // a slower child pulls a fast rival up, to the limit
      assert.equal(rubberBandScale(9000, 2800), 1.15);
      // a faster child pulls a slow rival down, to the limit
      assert.equal(rubberBandScale(1000, 4600), 0.85);
      // inside the band the rival lands on the child's pace exactly
      assert.ok(Math.abs(rubberBandScale(4000, 4600) * 4600 - 4000) < 1e-9);
      // and it is toward, never away
      for (const pace of [500, 1500, 2500, 3500, 4500, 6500, 12000]) {
        for (const mean of [2100, 2800, 3400, 4600, 6900]) {
          const scale = rubberBandScale(pace, mean);
          assert.ok(scale >= 0.85 && scale <= 1.15, pace + "/" + mean + " -> " + scale);
          const moved = mean * scale;
          if (pace > mean) assert.ok(moved >= mean && moved <= pace + 1e-9, "up");
          else assert.ok(moved <= mean && moved >= pace - 1e-9, "down");
        }
      }
    });

    test("rivals: with no pace yet the band is exactly one", () => {
      assert.equal(rubberBandScale(0, 2800), 1);
      const { rivals } = withRivals();
      assert.equal(childPaceMs(rivals), 0);
      for (const mind of rivals.minds) assert.equal(mind.lastScale, 1);
    });

    test("rivals: the pace window is the last twelve of the child's answers", () => {
      assert.equal(RIVAL_PACE_WINDOW, 12);
      const { harness } = withRivals();
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      for (let index = 0; index < 20; index++) {
        const events = answerRight(harness, "you", 3000);
        rivals = rivalObserve(rivals, harness.state, events).rivals;
      }
      assert.equal(rivals.childGaps.length, 12, "never more than twelve");
      assert.equal(childPaceMs(rivals), 3000);
    });

    test("rivals: a rival never answers faster than 1.5 s, however hard the band pulls", () => {
      assert.equal(RIVAL_FLOOR_MS, 1500);
      for (const seat of RIVAL_SEATS) {
        const tuning = rivalTuning(seat.personality, "champion");
        const rng = forkRng(7, "floor:" + seat.id);
        for (let index = 0; index < 4000; index++) {
          const drawn = drawThinkTime(rng, tuning.thinkTimeMeanMs, tuning.thinkTimeSpreadMs, 0.85);
          assert.ok(drawn.thinkMs >= RIVAL_FLOOR_MS, seat.id + " " + drawn.thinkMs);
          assert.ok(drawn.thinkMs === drawn.drawnMs || drawn.drawnMs < RIVAL_FLOOR_MS, "floor only lifts");
        }
      }
    });

    test("rivals: a think-time draw stays inside mean ± spread and averages the mean", () => {
      for (const seat of RIVAL_SEATS) {
        const tuning = rivalTuning(seat.personality, "pro");
        const rng = forkRng(11, "spread:" + seat.id);
        let total = 0;
        let low = Number.MAX_SAFE_INTEGER;
        let high = 0;
        const draws = 20000;
        for (let index = 0; index < draws; index++) {
          const value = drawThinkTimeMs(rng, tuning.thinkTimeMeanMs, tuning.thinkTimeSpreadMs, 1);
          total += value;
          if (value < low) low = value;
          if (value > high) high = value;
        }
        assert.ok(low >= tuning.thinkTimeMeanMs - tuning.thinkTimeSpreadMs, seat.id + " min " + low);
        assert.ok(high <= tuning.thinkTimeMeanMs + tuning.thinkTimeSpreadMs, seat.id + " max " + high);
        const mean = total / draws;
        assert.ok(
          Math.abs(mean - tuning.thinkTimeMeanMs) < tuning.thinkTimeSpreadMs / 20,
          seat.id + " mean " + mean.toFixed(1) + " vs " + tuning.thinkTimeMeanMs,
        );
      }
    });

    test("rivals: a wrong answer is wrong, positive, and drawn from the seed", () => {
      const rng = forkRng(3, "wrong");
      for (let left = 1; left <= 12; left++) {
        for (let right = 1; right <= 12; right++) {
          const fact = left * 100 + right;
          for (let index = 0; index < 8; index++) {
            const value = drawWrongAnswer(rng, fact);
            assert.notEqual(value, factAnswer(fact), "gave the right answer for " + fact);
            assert.ok(value > 0, "gave " + value + " for " + fact);
          }
        }
      }
    });

    // ---- streaks and hands ------------------------------------------------

    test("rivals: rivals build streaks and earn hands from the same shared cursor", () => {
      const harness = startRace();
      answerRightTimes(harness, 12, "bolt");
      const first = racer(harness, "bolt").hand.slice();
      assert.deepEqual(first, ["nitro", "oilSlick", "wrench"]);
      assert.equal(harness.state.cardCursor, 3);
      answerRightTimes(harness, 12, "you");
      assert.deepEqual(racer(harness, "you").hand, ["pothole", "rollCage", "pileUp"]);
      assert.equal(harness.state.cardCursor, 6);
      answerRightTimes(harness, 12, "gasket");
      assert.deepEqual(racer(harness, "gasket").hand, ["turbo", "towHook", "nitro"]);
    });

    // ---- the play policy --------------------------------------------------

    test("rivals: a boost goes when the rival is more than half a lap behind the leader", () => {
      assert.equal(HALF_LAP, 6);
      assert.deepEqual(BOOST_CARDS.slice().sort(), ["nitro", "turbo"]);
      const { harness, rivals } = withRivals();
      const mind = mindOf(rivals, "bolt")!;
      answerRightTimes(harness, 6, "you");
      racer(harness, "bolt").hand = ["turbo", "towHook", "nitro"];
      // exactly half a lap behind is not "more than", so the boost rule does not
      // fire and the hand falls through to the rule below it
      assert.notEqual(choosePlay(harness.state, mind)!.rule, "boost");
      answerRight(harness, "you");
      const choice = choosePlay(harness.state, mind)!;
      assert.equal(choice.rule, "boost");
      assert.equal(choice.card, "turbo", "the stronger boost when the hand holds both");
      assert.equal(choice.targetId, "");
      // a boost-only hand is simply held until the gap opens
      const held = withRivals();
      const holder = mindOf(held.rivals, "bolt")!;
      answerRightTimes(held.harness, 3, "you");
      racer(held.harness, "bolt").hand = ["nitro"];
      assert.equal(choosePlay(held.harness.state, holder), null, "three behind is not half a lap");
    });

    test("rivals: a Roll Cage goes when none is active and the rival is first or second", () => {
      const { harness, rivals } = withRivals();
      const mind = mindOf(rivals, "bolt")!;
      answerRightTimes(harness, 4, "bolt");
      racer(harness, "bolt").hand = ["rollCage", "pileUp", "turbo"];
      const choice = choosePlay(harness.state, mind)!;
      assert.equal(choice.rule, "rollCage");
      assert.equal(choice.card, "rollCage");
      // with one already up, the rule stops applying
      racer(harness, "bolt").rollCages = 1;
      racer(harness, "bolt").hand = ["rollCage", "pileUp", "turbo"];
      const withCage = choosePlay(harness.state, mind);
      if (withCage !== null) assert.notEqual(withCage.card, "rollCage");
      // and it does not apply from third: a Roll Cage on its own is then held
      racer(harness, "bolt").rollCages = 0;
      answerRightTimes(harness, 8, "piston");
      answerRightTimes(harness, 8, "gasket");
      answerRightTimes(harness, 8, "you");
      assert.ok(E.raceOrder(harness.state).indexOf("bolt") >= 2, "Bolt is third or fourth");
      racer(harness, "bolt").hand = ["rollCage"];
      assert.equal(choosePlay(harness.state, mind), null);
    });

    test("rivals: an attack targets the current leader when the leader is not itself", () => {
      const { harness, rivals } = withRivals();
      const mind = mindOf(rivals, "piston")!;
      answerRightTimes(harness, 9, "bolt");
      answerRightTimes(harness, 6, "piston");
      answerRightTimes(harness, 3, "gasket");
      answerRightTimes(harness, 1, "you");
      racer(harness, "piston").hand = ["wrench"];
      const choice = choosePlay(harness.state, mind)!;
      assert.equal(choice.rule, "attack");
      assert.equal(choice.targetId, "bolt");
    });

    test("rivals: a leader with an attack takes the closest kart behind instead", () => {
      const { harness, rivals } = withRivals();
      const mind = mindOf(rivals, "bolt")!;
      answerRightTimes(harness, 9, "bolt");
      answerRightTimes(harness, 6, "piston");
      answerRightTimes(harness, 3, "gasket");
      answerRightTimes(harness, 1, "you");
      racer(harness, "bolt").hand = ["wrench"];
      const choice = choosePlay(harness.state, mind)!;
      assert.equal(choice.targetId, "piston", "the kart directly behind, not the one after it");
    });

    test("rivals: the policy looks when the hand is dealt and again every three answers", () => {
      assert.equal(POLICY_INTERVAL, 3);
      const harness = startRace({ seed: 99 });
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      // Bolt earns a hand it may not spend: everybody is level, so the leader is
      // Bolt itself and everyone behind is tied last.
      racer(harness, "bolt").hand = ["wrench", "pothole", "rollCage"];
      racer(harness, "bolt").rollCages = 2;
      const mind = mindOf(rivals, "bolt")!;
      mind.handSize = 3;
      mind.answersSincePolicy = 0;
      assert.equal(choosePlay(harness.state, mind), null, "nothing is legal yet");
      // Three answers later the policy looks again, and by then Piston is clear
      // of last place, so the attack becomes legal.
      answerRightTimes(harness, 5, "piston");
      answerRightTimes(harness, 2, "gasket");
      answerRightTimes(harness, 1, "you");
      const choice = choosePlay(harness.state, mind);
      assert.notEqual(choice, null, "the re-evaluation found a legal target");
      void rivals;
    });

    // ---- the mercy rules --------------------------------------------------

    test("rivals: never attack the racer in last place", () => {
      const { harness, rivals } = withRivals();
      answerRightTimes(harness, 9, "bolt");
      answerRightTimes(harness, 6, "piston");
      answerRightTimes(harness, 3, "gasket");
      // "you" has answered nothing and is last by effective progress
      assert.deepEqual(lastPlaceIds(harness.state), ["you"]);
      const mind = mindOf(rivals, "piston")!;
      assert.equal(mayAttack(harness.state, mind, "you", lastPlaceIds(harness.state)), false);
      racer(harness, "piston").hand = ["pileUp"];
      const choice = choosePlay(harness.state, mind)!;
      assert.notEqual(choice.targetId, "you");
    });

    test("rivals: every racer tied at the lowest progress counts as last", () => {
      const { harness } = withRivals();
      assert.deepEqual(lastPlaceIds(harness.state).slice().sort(), ["bolt", "gasket", "piston", "you"]);
      answerRightTimes(harness, 3, "bolt");
      assert.deepEqual(lastPlaceIds(harness.state).slice().sort(), ["gasket", "piston", "you"]);
    });

    test("rivals: never attack the child twice with consecutive hands", () => {
      const { harness, rivals } = withRivals();
      answerRightTimes(harness, 7, "you");
      answerRightTimes(harness, 5, "piston");
      answerRightTimes(harness, 1, "gasket");
      const mind = mindOf(rivals, "bolt")!;
      const last = lastPlaceIds(harness.state);
      assert.equal(last.indexOf("you"), -1, "the child is not last here");
      assert.equal(mayAttack(harness.state, mind, "you", last), true);
      mind.lastHandAttackedHuman = true;
      assert.equal(mayAttack(harness.state, mind, "you", last), false);
      racer(harness, "bolt").hand = ["wrench"];
      const choice = choosePlay(harness.state, mind);
      if (choice !== null) assert.notEqual(choice.targetId, "you");
    });

    test("rivals: an Oil Slick only goes when everyone it would reach is allowed", () => {
      const { harness, rivals } = withRivals();
      const mind = mindOf(rivals, "bolt")!;
      racer(harness, "bolt").hand = ["oilSlick"];
      // At the start everyone is tied last, so the slick would land on last place.
      assert.equal(choosePlay(harness.state, mind), null);
      // Once Bolt itself is the only racer at the lowest progress, nobody it
      // reaches is last and the slick is legal.
      answerRightTimes(harness, 4, "you");
      answerRightTimes(harness, 3, "piston");
      answerRightTimes(harness, 2, "gasket");
      assert.deepEqual(lastPlaceIds(harness.state), ["bolt"]);
      racer(harness, "bolt").hand = ["oilSlick"];
      const choice = choosePlay(harness.state, mind)!;
      assert.equal(choice.card, "oilSlick");
      assert.equal(choice.targetId, "");
    });

    test("rivals: the mercy rules cover every card the policy calls an attack", () => {
      assert.deepEqual(
        ATTACK_CARDS.slice().sort(),
        ["oilSlick", "pileUp", "pothole", "towHook", "wrench"],
      );
      const { harness, rivals } = withRivals();
      const mind = mindOf(rivals, "piston")!;
      answerRightTimes(harness, 9, "bolt");
      answerRightTimes(harness, 6, "piston");
      answerRightTimes(harness, 3, "gasket");
      const last = lastPlaceIds(harness.state);
      for (const card of ATTACK_CARDS) {
        racer(harness, "piston").hand = [card];
        const choice = choosePlay(harness.state, mind);
        if (choice === null) continue;
        if (choice.targetId !== "") assert.equal(last.indexOf(choice.targetId), -1, card);
      }
    });

    test("rivals: a finished racer is never targeted and never targets", () => {
      const { harness, rivals } = withRivals("pro", { preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "gasket");
      assert.equal(racer(harness, "gasket").finished, true);
      const mind = mindOf(rivals, "bolt")!;
      assert.equal(mayAttack(harness.state, mind, "gasket", lastPlaceIds(harness.state)), false);
      const finished = mindOf(rivals, "gasket")!;
      assert.equal(choosePlay(harness.state, finished), null);
    });

    test("rivals: chooseTarget never returns the rival itself", () => {
      const { harness, rivals } = withRivals();
      answerRightTimes(harness, 9, "bolt");
      answerRightTimes(harness, 6, "piston");
      answerRightTimes(harness, 3, "gasket");
      answerRightTimes(harness, 1, "you");
      const order = E.raceOrder(harness.state);
      for (const seat of RIVAL_SEATS) {
        const mind = mindOf(rivals, seat.id)!;
        const target = chooseTarget(harness.state, mind, order, lastPlaceIds(harness.state));
        assert.notEqual(target, seat.id);
      }
    });

    // ---- signals ----------------------------------------------------------

    test("rivals: a NICE RUN when the child completes a lap with no mistakes", () => {
      const harness = startRace({ preset: "2-5" });
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      const sent: string[] = [];
      for (let index = 0; index < 12; index++) {
        const events = answerRight(harness, "you");
        const observed = rivalObserve(rivals, harness.state, events);
        rivals = observed.rivals;
        for (const signal of observed.signals) sent.push(signal.signal + ":" + signal.racerId);
      }
      assert.equal(sent.length, 1, "one signal for one clean lap");
      assert.equal(sent[0]!.indexOf("niceRun:"), 0);
      assert.notEqual(sent[0]!.slice("niceRun:".length), "you", "a rival sends it, not the child");
    });

    test("rivals: no NICE RUN for a lap with a mistake in it", () => {
      const harness = startRace({ preset: "2-5" });
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      const sent: string[] = [];
      const mistake = answerWrong(harness, "you");
      rivals = rivalObserve(rivals, harness.state, mistake).rivals;
      for (let index = 0; index < 12; index++) {
        const events = answerRight(harness, "you");
        const observed = rivalObserve(rivals, harness.state, events);
        rivals = observed.rivals;
        for (const signal of observed.signals) sent.push(signal.signal);
      }
      assert.deepEqual(sent, [], "a wrong answer costs the lap its NICE RUN");
      assert.equal(racer(harness, "you").lapsComplete, 1);
    });

    test("rivals: a GOOD GAME at the finish, once from each rival", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      const sent: { racerId: string; signal: string }[] = [];
      for (let index = 0; index < 12; index++) {
        const events = answerRight(harness, "you");
        const observed = rivalObserve(rivals, harness.state, events);
        rivals = observed.rivals;
        for (const signal of observed.signals) sent.push({ racerId: signal.racerId, signal: signal.signal });
      }
      const goodGames = sent.filter((entry) => entry.signal === "goodGame");
      assert.deepEqual(
        goodGames.map((entry) => entry.racerId).sort(),
        ["bolt", "gasket", "piston"],
      );
      // and never twice
      const again = rivalObserve(rivals, harness.state, harness.events);
      assert.deepEqual(again.signals.filter((entry) => entry.signal === "goodGame"), []);
    });

    test("rivals: every signal comes from the four-signal catalog", () => {
      const outcome = runRace(E, { seed: 20260902, preset: "2-5", level: "pro", child: GATE_CHILD });
      assert.ok(outcome.signals.length > 0, "the race sent no signals at all");
      for (const signal of outcome.signals)
        assert.ok(SIGNAL_CATALOG.indexOf(signal.signal as never) !== -1, signal.signal);
      assert.deepEqual(SIGNAL_CATALOG.slice().sort(), ["goodGame", "goodLuck", "niceRun", "soClose"]);
    });

    test("rivals: a signal slots into a step's events above handDealt and below the callouts", () => {
      const harness = startRace({ preset: "2-5" });
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      let merged = 0;
      for (let index = 0; index < 48; index++) {
        const events = answerRight(harness, "you");
        const observed = rivalObserve(rivals, harness.state, events);
        rivals = observed.rivals;
        const stream = mergeSignals(events, observed.signals);
        assert.ok(isEventOrdered(stream), "a merged step was out of order at answer " + index);
        if (observed.signals.length === 0) continue;
        merged += observed.signals.length;
        for (let slot = 0; slot < stream.length; slot++) {
          if (stream[slot]!.type !== "signal") continue;
          for (let before = 0; before < slot; before++)
            assert.notEqual(stream[before]!.type, "passed", "a signal came after a callout");
        }
      }
      assert.ok(merged > 0, "the sample sent no signals, so it proved nothing about them");
    });

    test("rivals: rivalStep's events hold the ordering guarantee one step at a time", () => {
      const harness = startRace({ preset: "2-5" });
      let rivals = createRivals(
        harness.state,
        RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
      );
      // rivalStep flattens the events of several reducer steps into one list, so
      // the guarantee to assert is per step: within each slice the ranks never
      // fall, and a slice only ever begins at rank 0 -- the answer or the card
      // that caused it. A signal, at rank 5, therefore always sits above the
      // handDealt it may follow and below the callouts that close a step.
      let slices = 0;
      for (let index = 0; index < 200; index++) {
        harness.now += 1000;
        const stepped = rivalStep(harness.state, rivals, harness.now);
        harness.state = stepped.state;
        rivals = stepped.rivals;
        let slice: EngineModule.RaceEvent[] = [];
        for (const event of stepped.events) {
          const startsASlice = slice.length > 0 && E.EVENT_ORDER[event.type] < E.EVENT_ORDER[slice[slice.length - 1]!.type];
          if (startsASlice) {
            assert.ok(isEventOrdered(slice), "a step's events were out of order");
            assert.equal(E.EVENT_ORDER[event.type], 0, "a step began above rank 0");
            slices += 1;
            slice = [];
          }
          slice.push(event);
        }
        if (slice.length > 0) {
          assert.ok(isEventOrdered(slice), "the last step's events were out of order");
          slices += 1;
        }
      }
      assert.ok(slices > 100, "only " + slices + " steps in the sample");
    });

    // ---- the reducer ------------------------------------------------------

    test("rivals: the tick size does not change the race", () => {
      function drive(tick: number): { answers: string[]; plays: string[] } {
        let state = createRace({
          seed: 5150,
          preset: "2-5",
          mode: "grandPrix",
          racers: [
            { id: "you", kind: "human" },
            ...RIVAL_SEATS.map((seat) => ({ id: seat.id, kind: "rival" as const })),
          ],
        });
        state = step(state, { kind: "start" }, 0).state;
        let rivals = createRivals(
          state,
          RIVAL_SEATS.map((seat) => ({ id: seat.id, personality: seat.personality, level: "pro" as const })),
        );
        const answers: string[] = [];
        const plays: string[] = [];
        for (let now = tick; now <= 400000; now += tick) {
          const stepped = rivalStep(state, rivals, now);
          state = stepped.state;
          rivals = stepped.rivals;
          for (const answer of stepped.answers)
            answers.push(answer.racerId + "@" + answer.at + ":" + answer.fact + ":" + answer.value);
          for (const play of stepped.plays)
            plays.push(play.racerId + "@" + play.at + ":" + play.card + ":" + play.targetId);
        }
        return { answers, plays };
      }
      const fine = drive(1);
      assert.ok(fine.answers.length > 100);
      assert.ok(fine.plays.length > 0);
      assert.deepEqual(drive(100), fine, "a 100 ms tick");
      assert.deepEqual(drive(1000), fine, "a 1 s tick");
    });

    test("rivals: the same seed is the same rival decisions", () => {
      const first = runRace(E, { seed: 1337, preset: "2-5", level: "pro", child: GATE_CHILD, detail: true });
      const again = runRace(E, { seed: 1337, preset: "2-5", level: "pro", child: GATE_CHILD, detail: true });
      assert.deepEqual(again.answers, first.answers);
      assert.deepEqual(again.plays, first.plays);
      assert.deepEqual(again.signals, first.signals);
      assert.deepEqual(again.places, first.places);
      const other = runRace(E, { seed: 1338, preset: "2-5", level: "pro", child: GATE_CHILD, detail: true });
      assert.notDeepEqual(other.answers, first.answers, "a different seed is a different race");
    });

    test("rivals: rivalStep never mutates the state or the rivals it was given", () => {
      const { harness, rivals } = withRivals();
      const stateBefore = JSON.stringify(harness.state);
      const rivalsBefore = JSON.stringify(rivals);
      rivalStep(harness.state, rivals, 60000);
      assert.equal(JSON.stringify(harness.state), stateBefore);
      assert.equal(JSON.stringify(rivals), rivalsBefore);
    });

    // ---- the fairness property, in miniature ------------------------------

    test("rivals: over 200 seeded races no rival breaks a mercy rule", () => {
      let attacks = 0;
      const violations: string[] = [];
      for (let seed = 0; seed < 200; seed++) {
        const outcome = runRace(E, { seed, preset: "2-10", level: "pro", child: GATE_CHILD });
        attacks += outcome.attacks;
        for (const violation of outcome.violations)
          violations.push(seed + " " + violation.kind + " " + violation.attackerId + " -> " + violation.victimId);
      }
      assert.ok(attacks > 100, "the sample landed only " + attacks + " attacks");
      assert.deepEqual(violations, []);
    });

    test("rivals: over 200 seeded races the band and the floor hold", () => {
      let lowestThink = Number.MAX_SAFE_INTEGER;
      let lowestScale = Number.MAX_SAFE_INTEGER;
      let highestScale = 0;
      for (let seed = 0; seed < 200; seed++) {
        const outcome = runRace(E, { seed, preset: "2-10", level: "champion", child: GATE_CHILD });
        if (outcome.minThinkMs > 0 && outcome.minThinkMs < lowestThink) lowestThink = outcome.minThinkMs;
        if (outcome.minScale < lowestScale) lowestScale = outcome.minScale;
        if (outcome.maxScale > highestScale) highestScale = outcome.maxScale;
      }
      assert.ok(lowestThink >= RIVAL_FLOOR_MS, "a rival answered in " + lowestThink + "ms");
      assert.ok(lowestScale >= 1 - RUBBER_BAND_LIMIT - 1e-12, "scale " + lowestScale);
      assert.ok(highestScale <= 1 + RUBBER_BAND_LIMIT + 1e-12, "scale " + highestScale);
    });

    // ---- the vector file --------------------------------------------------

    test("rivals: vectors/rivals.json carries the design's table", () => {
      for (const row of vectors.profiles) {
        const tuning = rivalTuning(row.personality, row.level);
        assert.equal(tuning.accuracyPercent, row.accuracyPercent, row.personality + " " + row.level);
        assert.equal(tuning.thinkTimeMeanMs, row.thinkTimeMeanMs, row.personality + " " + row.level);
        assert.equal(tuning.thinkTimeSpreadMs, row.thinkTimeSpreadMs, row.personality + " " + row.level);
      }
      assert.equal(vectors.rubberBand.limit, RUBBER_BAND_LIMIT);
      assert.equal(vectors.rubberBand.floorMs, RIVAL_FLOOR_MS);
      assert.equal(vectors.rubberBand.paceWindow, RIVAL_PACE_WINDOW);
      assert.equal(vectors.policy.interval, POLICY_INTERVAL);
      assert.equal(vectors.policy.halfLap, HALF_LAP);
    });

    test("rivals: vectors/rivals.json replays its rubber-band and think-time cases", () => {
      for (const row of vectors.rubberBand.cases)
        assert.equal(rubberBandScale(row.childPaceMs, row.meanMs), row.scale, JSON.stringify(row));
      for (const row of vectors.thinkTimeDraws) {
        const tuning = rivalTuning(row.personality, row.level);
        const rng = forkRng(row.seed, "vector:" + row.personality + ":" + row.level);
        const values: number[] = [];
        for (let index = 0; index < row.thinkTimesMs.length; index++)
          values.push(drawThinkTimeMs(rng, tuning.thinkTimeMeanMs, tuning.thinkTimeSpreadMs, 1));
        assert.deepEqual(values, row.thinkTimesMs, row.personality + " " + row.level);
      }
    });

    test("rivals: vectors/rivals.json replays every recorded rival decision", () => {
      for (const vector of vectors.races) {
        const outcome = runRace(E, {
          seed: vector.seed,
          preset: vector.preset,
          chosenTables: vector.chosenTables,
          level: vector.level,
          child: {
            paceMs: vector.child.paceMs,
            accuracyPercent: vector.child.accuracyPercent,
            playsCards: GATE_CHILD.playsCards,
          },
          detail: true,
        });
        assert.deepEqual(
          JSON.parse(JSON.stringify(outcome.answers)),
          vector.answers,
          vector.name + " answers",
        );
        assert.deepEqual(JSON.parse(JSON.stringify(outcome.plays)), vector.plays, vector.name + " plays");
        assert.deepEqual(outcome.signals, vector.signals, vector.name + " signals");
        assert.deepEqual(outcome.places, vector.places, vector.name + " places");
        assert.deepEqual(outcome.finishTimeMs, vector.finishTimeMs, vector.name + " finish times");
      }
    });

    test("rivals: every recorded play in the vectors obeys both mercy rules", () => {
      for (const vector of vectors.races) {
        const spent = new Map<string, boolean>();
        for (const play of vector.plays) {
          const isAttack = ATTACK_CARDS.indexOf(play.card) !== -1;
          if (!isAttack) {
            spent.set(play.racerId, false);
            continue;
          }
          let lowest = Number.MAX_SAFE_INTEGER;
          for (const row of play.standingsBefore) if (row.progress < lowest) lowest = row.progress;
          let hitChild = false;
          for (const victimId of play.victimIds) {
            const victim = play.standingsBefore.find((row: any) => row.id === victimId);
            assert.notEqual(victim.progress, lowest, vector.name + ": attacked last place");
            if (victimId === "you") hitChild = true;
          }
          if (hitChild)
            assert.notEqual(spent.get(play.racerId), true, vector.name + ": two hands at the child");
          spent.set(play.racerId, hitChild);
        }
      }
    });

    test("rivals: the recorded races between them use a boost, a Roll Cage and an attack", () => {
      const rules = new Set<string>();
      for (const vector of vectors.races) for (const play of vector.plays) rules.add(play.rule);
      assert.deepEqual([...rules].sort(), ["attack", "boost", "rollCage"]);
    });

    test("rivals: effective progress is what last place is read from", () => {
      const { harness } = withRivals();
      answerRightTimes(harness, 5, "you");
      racer(harness, "bolt").hand = ["pileUp"];
      // Shove Piston backwards and it becomes last by progress alone.
      answerRightTimes(harness, 3, "piston");
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "piston" });
      const piston = racer(harness, "piston");
      assert.equal(effectiveProgress(piston, harness.state.questionsPerLap), 3 - 15);
      assert.deepEqual(lastPlaceIds(harness.state), ["piston"]);
    });
  });
}
