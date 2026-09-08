// Design section: "Powerups", including the rules quoted verbatim from the
// bellringer runtime. Every bullet under "The rules underneath" has a test here.

import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type * as EngineModule from "../../src/engine/index.ts";
import type { Card } from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const { CARDS, CARD_SCHEDULE, HAND_SIZE, QUESTIONS_NEEDED_FLOOR, applyFloor, cardByBellringerName, dealHand, isCard } = E;
    const { answerRight, answerRightTimes, apply, eventsOfType, position, racer, startRace } = helpersFor(E);

    test("cards: the eight cards carry the bellringer's effects, targets and tiers", () => {
      assert.deepEqual(
        CARD_SCHEDULE.map((card) => [
          card,
          CARDS[card].bellringerName,
          CARDS[card].questionDelta,
          CARDS[card].scope,
          CARDS[card].tier,
        ]),
        [
          ["nitro", "FuelBoost", -4, "self", "common"],
          ["oilSlick", "GravityWell", 3, "aoe", "common"],
          ["wrench", "Lightning", 5, "targeted", "uncommon"],
          ["pothole", "BlackHole", 8, "targeted", "rare"],
          ["rollCage", "Shield", 0, "self", "uncommon"],
          ["pileUp", "Supernova", 15, "targeted", "legendary"],
          ["turbo", "Turbo", -10, "self", "rare"],
          ["towHook", "Wormhole", 0, "targeted", "legendary"],
        ],
      );
      assert.equal(cardByBellringerName("Supernova"), "pileUp");
      assert.equal(isCard("nitro"), true);
      assert.equal(isCard("rocket"), false);
    });

    test("cards: the schedule is the bellringer's canonical order, renamed", () => {
      assert.deepEqual(CARD_SCHEDULE.slice(), [
        "nitro",
        "oilSlick",
        "wrench",
        "pothole",
        "rollCage",
        "pileUp",
        "turbo",
        "towHook",
      ]);
      assert.equal(HAND_SIZE, 3);
    });

    test("cards: the hand is dealt round-robin and wraps around the schedule", () => {
      const first = dealHand(CARD_SCHEDULE, 0);
      const second = dealHand(CARD_SCHEDULE, first.cursor);
      const third = dealHand(CARD_SCHEDULE, second.cursor);
      const fourth = dealHand(CARD_SCHEDULE, third.cursor);
      assert.deepEqual(first.hand, ["nitro", "oilSlick", "wrench"]);
      assert.deepEqual(second.hand, ["pothole", "rollCage", "pileUp"]);
      assert.deepEqual(third.hand, ["turbo", "towHook", "nitro"]);
      assert.deepEqual(fourth.hand, ["oilSlick", "wrench", "pothole"]);
      assert.equal(fourth.cursor, 12);
    });

    test("cards: a schedule shorter than a hand deals what it has, without repeating", () => {
      const dealt = dealHand(["turbo"], 0);
      assert.deepEqual(dealt.hand, ["turbo"]);
      assert.equal(dealt.cursor, 1);
    });

    test("cards: dealHand terminates on a schedule that repeats a card, and never repeats it", () => {
      // `RaceConfig.schedule` is public and unvalidated, and the engine runs on
      // the QML main thread: a schedule whose distinct cards number fewer than
      // three used to spin here forever, which is a frozen plugin with no error
      // and no log line. Termination is counted in cards scanned, so one pass
      // over the schedule always ends the deal.
      //
      // A schedule that reports its own length honestly but counts how often it
      // is indexed, so that a `dealHand` which does not terminate FAILS here
      // rather than hanging the suite. The old condition reads the same three
      // slots forever; this one throws on the seventeenth read.
      let reads = 0;
      const counted = new Proxy(["nitro", "nitro", "wrench"], {
        get(target, property, receiver) {
          if (typeof property === "string" && /^[0-9]+$/.test(property)) {
            reads += 1;
            if (reads > 16) {
              throw new Error("dealHand did not terminate: " + reads + " reads of a 3-card schedule");
            }
          }
          return Reflect.get(target, property, receiver);
        },
      }) as unknown as Card[];

      const twice = dealHand(counted, 0);
      assert.equal(reads, 3, "one pass over the schedule and no more");
      assert.deepEqual(twice.hand, ["nitro", "wrench"]);
      assert.equal(twice.cursor, 3, "the cursor advances once per card scanned, duplicates included");

      const allSame = dealHand(["turbo", "turbo", "turbo", "turbo"], 2);
      assert.deepEqual(allSame.hand, ["turbo"]);
      assert.equal(allSame.cursor, 6);

      // And it is still the same deal on every duplicate-free schedule, which is
      // why this fix moves no vector: two distinct cards, three distinct cards,
      // and the canonical eight all land exactly where they did before.
      assert.deepEqual(dealHand(["rollCage", "wrench"], 0), { hand: ["rollCage", "wrench"], cursor: 2 });
      assert.deepEqual(dealHand(["rollCage", "wrench", "oilSlick"], 1), {
        hand: ["wrench", "oilSlick", "rollCage"],
        cursor: 4,
      });
      assert.deepEqual(dealHand(CARD_SCHEDULE, 6), { hand: ["turbo", "towHook", "nitro"], cursor: 9 });
    });

    test("cards: the first hand of a race is always Nitro, Oil Slick, Wrench", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      assert.deepEqual(racer(harness, "you").hand, ["nitro", "oilSlick", "wrench"]);
    });

    test("cards: the cursor is shared by every racer in the race, human and AI alike", () => {
      const harness = startRace();
      for (let index = 0; index < 12; index++) answerRight(harness, "you");
      for (let index = 0; index < 12; index++) answerRight(harness, "bolt");
      for (let index = 0; index < 12; index++) answerRight(harness, "piston");
      assert.deepEqual(racer(harness, "you").hand, ["nitro", "oilSlick", "wrench"]);
      assert.deepEqual(racer(harness, "bolt").hand, ["pothole", "rollCage", "pileUp"]);
      assert.deepEqual(racer(harness, "piston").hand, ["turbo", "towHook", "nitro"]);
      assert.equal(harness.state.cardCursor, 9);
    });

    test("cards: using a powerup costs the whole hand, and the other two are gone", () => {
      const harness = startRace();
      answerRightTimes(harness, 12);
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      const used = eventsOfType(events, "cardUsed");
      assert.equal(used.length, 1);
      assert.equal(used[0]!.card, "nitro");
      assert.deepEqual(used[0]!.discarded, ["oilSlick", "wrench"]);
      assert.deepEqual(racer(harness, "you").hand, []);
    });

    test("cards: there is no cooldown, and a hand may be held across laps", () => {
      const harness = startRace({ preset: "2-5" });
      answerRightTimes(harness, 12);
      assert.equal(racer(harness, "you").lapsComplete, 1);
      answerRightTimes(harness, 12);
      assert.equal(racer(harness, "you").lapsComplete, 2);
      assert.deepEqual(racer(harness, "you").hand, ["nitro", "oilSlick", "wrench"]);
    });

    test("cards: attacks and boosts change only the current lap's requirement", () => {
      const harness = startRace();
      racer(harness, "you").hand = ["pothole"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.deepEqual(position(racer(harness, "bolt")), [0, 0, 20]);
      racer(harness, "you").hand = ["nitro"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.deepEqual(position(racer(harness, "you")), [0, 0, 8]);
    });

    test("cards: the floor on questions needed is one", () => {
      assert.equal(QUESTIONS_NEEDED_FLOOR, 1);
      assert.equal(applyFloor(12, -10), 2);
      assert.equal(applyFloor(2, -10), 1);
      assert.equal(applyFloor(1, -4), 1);
      const harness = startRace();
      racer(harness, "you").hand = ["turbo"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.equal(racer(harness, "you").questionsNeededThisLap, 2);
      racer(harness, "you").hand = ["turbo"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.equal(racer(harness, "you").questionsNeededThisLap, 1, "never below one");
    });

    test("cards: there is no ceiling on questions needed", () => {
      const harness = startRace();
      for (let round = 0; round < 4; round++) {
        racer(harness, "you").hand = ["pileUp"];
        apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      }
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 12 + 60);
    });

    test("cards: when the lap ends the requirement resets to twelve", () => {
      const harness = startRace({ preset: "2-5" });
      racer(harness, "you").hand = ["pothole"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 20);
      for (let index = 0; index < 20; index++) answerRight(harness, "bolt", index === 0 ? 3000 : 1000);
      assert.deepEqual(position(racer(harness, "bolt")), [1, 0, 12]);
    });

    test("cards: a Pile-Up is bounded by one lap", () => {
      const harness = startRace({ preset: "2-5" });
      racer(harness, "you").hand = ["pileUp"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 27);
      for (let index = 0; index < 27; index++) answerRight(harness, "bolt", index === 0 ? 3000 : 1000);
      assert.deepEqual(position(racer(harness, "bolt")), [1, 0, 12], "the next lap is a clean twelve");
    });

    test("cards: a Turbo at the start of a lap takes ten off twelve and two answers finish it", () => {
      const harness = startRace({ preset: "2-5" });
      racer(harness, "you").hand = ["turbo"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.equal(racer(harness, "you").questionsNeededThisLap, 2);
      answerRight(harness);
      assert.equal(racer(harness, "you").lapsComplete, 0);
      answerRight(harness);
      assert.deepEqual(position(racer(harness, "you")), [1, 0, 12]);
    });

    test("cards: a boost can complete a lap instantly, and the surplus carries", () => {
      const harness = startRace({ preset: "2-5" });
      answerRightTimes(harness, 5);
      racer(harness, "you").hand = ["turbo"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.equal(eventsOfType(events, "lapComplete").length, 1);
      // need 12 - 10 = 2, correctInLap 5, so the lap completes with three to spare.
      assert.deepEqual(position(racer(harness, "you")), [1, 3, 12]);
    });

    test("cards: Roll Cage stacks without limit", () => {
      const harness = startRace();
      for (let index = 0; index < 5; index++) {
        racer(harness, "you").hand = ["rollCage"];
        apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      }
      assert.equal(racer(harness, "you").rollCages, 5);
    });

    test("cards: each Roll Cage absorbs exactly one incoming attack", () => {
      const harness = startRace();
      racer(harness, "you").rollCages = 2;
      racer(harness, "bolt").hand = ["wrench"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.equal(racer(harness, "you").rollCages, 1);
      assert.equal(racer(harness, "you").questionsNeededThisLap, 12);
      racer(harness, "bolt").hand = ["wrench"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.equal(racer(harness, "you").rollCages, 0);
      assert.equal(racer(harness, "you").questionsNeededThisLap, 12);
      racer(harness, "bolt").hand = ["wrench"];
      apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.equal(racer(harness, "you").questionsNeededThisLap, 17, "the third one lands");
    });

    test("cards: a blocked attack does nothing and costs the attacker their hand anyway", () => {
      const harness = startRace();
      racer(harness, "you").rollCages = 1;
      racer(harness, "bolt").hand = ["pileUp", "turbo", "nitro"];
      const before = position(racer(harness, "you"));
      const events = apply(harness, { kind: "useCard", racerId: "bolt", index: 0, targetId: "you" });
      assert.deepEqual(position(racer(harness, "you")), before);
      assert.deepEqual(racer(harness, "bolt").hand, [], "the whole hand is gone");
      const blocked = eventsOfType(events, "blocked");
      assert.equal(blocked.length, 1);
      assert.equal(blocked[0]!.rollCagesLeft, 0);
      assert.equal(eventsOfType(events, "hit").length, 0);
    });

    test("cards: Oil Slick hits every racer except the attacker", () => {
      const harness = startRace();
      racer(harness, "bolt").hand = ["oilSlick"];
      const events = apply(harness, { kind: "useCard", racerId: "bolt", index: 0 });
      const hits = eventsOfType(events, "hit");
      assert.deepEqual(
        hits.map((hit) => hit.racerId),
        ["you", "piston", "gasket"],
      );
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 12, "not the attacker");
      for (const id of ["you", "piston", "gasket"]) {
        assert.equal(racer(harness, id).questionsNeededThisLap, 15, id);
      }
    });

    test("cards: Oil Slick checks and consumes each victim's Roll Cage separately", () => {
      const harness = startRace();
      racer(harness, "you").rollCages = 1;
      racer(harness, "piston").rollCages = 2;
      racer(harness, "bolt").hand = ["oilSlick"];
      const events = apply(harness, { kind: "useCard", racerId: "bolt", index: 0 });
      assert.deepEqual(
        eventsOfType(events, "blocked").map((event) => event.racerId),
        ["you", "piston"],
      );
      assert.deepEqual(
        eventsOfType(events, "hit").map((event) => event.racerId),
        ["gasket"],
      );
      assert.equal(racer(harness, "you").rollCages, 0);
      assert.equal(racer(harness, "piston").rollCages, 1);
      assert.equal(racer(harness, "you").questionsNeededThisLap, 12);
      assert.equal(racer(harness, "gasket").questionsNeededThisLap, 15);
    });

    test("cards: Tow Hook swaps laps complete, correct in lap and questions needed, both ways", () => {
      const harness = startRace();
      answerRightTimes(harness, 5, "you");
      answerRightTimes(harness, 9, "bolt");
      racer(harness, "bolt").questionsNeededThisLap = 20;
      racer(harness, "you").hand = ["towHook"];
      const youBefore = position(racer(harness, "you"));
      const boltBefore = position(racer(harness, "bolt"));
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(eventsOfType(events, "swap").length, 1);
      assert.deepEqual(position(racer(harness, "you")), boltBefore);
      assert.deepEqual(position(racer(harness, "bolt")), youBefore);
    });

    test("cards: Roll Cages stay with their owners through a Tow Hook", () => {
      const harness = startRace();
      racer(harness, "you").rollCages = 3;
      racer(harness, "bolt").rollCages = 0;
      racer(harness, "you").hand = ["towHook"];
      apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(racer(harness, "you").rollCages, 3);
      assert.equal(racer(harness, "bolt").rollCages, 0);
    });

    test("cards: a Tow Hook can never finish a race for anyone", () => {
      const harness = startRace({ preset: "2-5" });
      // bolt sits one answer from the finish line; you sit at the start.
      const bolt = racer(harness, "bolt");
      bolt.lapsComplete = 3;
      bolt.correctInLap = 11;
      bolt.questionsNeededThisLap = 12;
      racer(harness, "you").hand = ["towHook"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(eventsOfType(events, "finished").length, 0);
      assert.equal(eventsOfType(events, "lapComplete").length, 0);
      assert.equal(racer(harness, "you").finished, false);
      assert.deepEqual(position(racer(harness, "you")), [3, 11, 12]);
    });

    test("cards: a Tow Hook is an attack, so a Roll Cage blocks it", () => {
      const harness = startRace();
      answerRightTimes(harness, 4, "bolt");
      racer(harness, "bolt").rollCages = 1;
      racer(harness, "you").hand = ["towHook"];
      const before = position(racer(harness, "you"));
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.equal(eventsOfType(events, "blocked").length, 1);
      assert.equal(eventsOfType(events, "swap").length, 0);
      assert.deepEqual(position(racer(harness, "you")), before);
      assert.equal(racer(harness, "bolt").rollCages, 0);
    });

    test("cards: a finished racer cannot attack", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "you");
      assert.equal(racer(harness, "you").finished, true);
      racer(harness, "you").hand = ["pileUp"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.deepEqual(events, []);
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 12);
      assert.deepEqual(racer(harness, "you").hand, ["pileUp"], "the card was never played");
    });

    test("cards: a finished racer cannot be attacked by a targeted card", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "bolt");
      assert.equal(racer(harness, "bolt").finished, true);
      racer(harness, "you").hand = ["pileUp"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
      assert.deepEqual(events, []);
      assert.deepEqual(racer(harness, "you").hand, ["pileUp"]);
    });

    test("cards: a finished racer cannot be attacked by Oil Slick either", () => {
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "bolt");
      racer(harness, "you").hand = ["oilSlick"];
      const events = apply(harness, { kind: "useCard", racerId: "you", index: 0 });
      assert.deepEqual(
        eventsOfType(events, "hit").map((hit) => hit.racerId),
        ["piston", "gasket"],
      );
      assert.equal(racer(harness, "bolt").questionsNeededThisLap, 12);
    });

    test("cards: a targeted card is refused without a live target other than the attacker", () => {
      const harness = startRace();
      for (const targetId of [undefined, "", "you", "nobody"]) {
        racer(harness, "you").hand = ["wrench"];
        const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId });
        assert.deepEqual(events, [], "target " + String(targetId));
        assert.deepEqual(racer(harness, "you").hand, ["wrench"]);
      }
    });

    test("cards: a self or area card is refused when handed a target", () => {
      const harness = startRace();
      for (const card of ["nitro", "turbo", "rollCage", "oilSlick"] as Card[]) {
        racer(harness, "you").hand = [card];
        const events = apply(harness, { kind: "useCard", racerId: "you", index: 0, targetId: "bolt" });
        assert.deepEqual(events, [], card);
      }
    });

    test("cards: an index outside the held hand plays nothing", () => {
      const harness = startRace();
      racer(harness, "you").hand = ["nitro"];
      assert.deepEqual(apply(harness, { kind: "useCard", racerId: "you", index: 3 }), []);
      assert.deepEqual(apply(harness, { kind: "useCard", racerId: "you", index: -1 }), []);
      assert.deepEqual(racer(harness, "you").hand, ["nitro"]);
    });
  });
}
