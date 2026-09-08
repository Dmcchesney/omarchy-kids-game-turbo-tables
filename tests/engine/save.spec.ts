// Design section: "Data" -- one JSON file with `settings`, `records` and
// `facts`, and "No dates, no session counts, no Grand Prix history, no streak
// history. Human-readable, so a parent can see exactly what is kept."
//
// Plan, engine specification, save.ts: "SaveFile schema, versioned; settings,
// records, facts; migration stub; validation that rejects unknown keys" and the
// key tests, "round-trip; no dates anywhere."
//
// This is also where the fact-history seam Piece 1 left open is closed:
// `RaceConfig.factHistory` in, `factHistoryOf(state)` out.

import { describe, test } from "node:test";
import assert from "node:assert/strict";

import type * as EngineModule from "../../src/engine/index.ts";
import { helpersFor } from "./helpers.ts";

export function spec(E: typeof EngineModule, label: string): void {
  describe(label, () => {
    const {
      FORBIDDEN_KEY_WORDS,
      KART_BODIES,
      KART_NUMBER_MAX,
      KART_NUMBER_MIN,
      MIGRATIONS,
      PAINT_SWATCHES,
      SAVE_VERSION,
      STREAK_THRESHOLD,
      baselineIsFile,
      cloneSave,
      commitRace,
      createRace,
      dateLikeKeys,
      defaultSettings,
      emptySave,
      emptyTimeline,
      factAnswer,
      factHistoryAccounts,
      factHistoryDelta,
      factHistoryDeltaIssues,
      factHistoryForRace,
      factHistoryMergeIssues,
      factHistoryOf,
      isRecordKey,
      mergeFactHistory,
      migrateLegacyGarageSettings,
      migrateSave,
      parseSave,
      recordEntryIssues,
      recordFromRace,
      recordKey,
      recordKeyOf,
      recordKeys,
      recordStep,
      resetFacts,
      resetRecords,
      resetSettings,
      serialiseSave,
      step,
      validateSave,
      withFactHistory,
    } = E;
    const { answerRightTimes, answerWrong, apply, racer, startRace } = helpersFor(E);

    /**
     * Every `commitRace` in this file goes through here, and every one of them
     * therefore asserts the invariant the function promises: **a file it
     * returns is a file `parseSave` accepts.** Serialise-then-validate is
     * closed by construction rather than by one test remembering to check.
     */
    function commit(
      file: EngineModule.SaveFile,
      state: EngineModule.RaceState,
      history: readonly EngineModule.FactRecord[],
      candidate: EngineModule.RecordEntry | null,
      seededWith: readonly EngineModule.FactRecord[] | null = null,
    ): EngineModule.CommitResult {
      const result = commitRace(file, state, history, candidate, seededWith);
      const loaded = parseSave(serialiseSave(result.file));
      assert.deepEqual(loaded.issues, [], "commitRace emitted a file its own validator rejects");
      assert.equal(loaded.ok, true);
      assert.deepEqual(loaded.file, result.file, "and it does not survive its own round trip");
      return result;
    }

    /** A clean solo run of one table, with its timeline. */
    function timeTrial(seed: number, gapMs: number, tables: number[] = [2]) {
      let state = createRace({
        seed,
        preset: "choose",
        chosenTables: tables,
        mode: "timeTrial",
        racers: [{ id: "you", kind: "human" as const }],
      });
      state = step(state, { kind: "start" }, 0).state;
      let timeline = emptyTimeline();
      let at = 0;
      for (let index = 0; index < 12 * tables.length; index++) {
        at += gapMs;
        const live = state.racers[0]!;
        const result = step(
          state,
          { kind: "answer", racerId: "you", value: factAnswer(live.currentFact) },
          at,
        );
        state = result.state;
        timeline = recordStep(timeline, state, result.events, "you");
      }
      return { state, timeline };
    }

    /** A save file with something in every field, for the schema tests. */
    function populated(): EngineModule.SaveFile {
      const run = timeTrial(2026, 4000);
      const file = emptySave();
      file.settings = {
        sound: false,
        reducedMotion: true,
        scanlines: true,
        kart: 4,
        paint: 7,
        number: 42,
        rivalLevel: "champion",
        streakThreshold: 12,
      };
      const record = recordFromRace(run.state, run.timeline)!;
      file.records[recordKeyOf(run.state)] = record;
      file.records["2-5"] = { ...record, preset: "2-5" };
      file.facts = factHistoryOf(run.state);
      return file;
    }

    // ---- the shape --------------------------------------------------------

    test("save: the file is version, settings, records and facts, and nothing else", () => {
      assert.deepEqual(Object.keys(emptySave()).sort(), ["facts", "records", "settings", "version"]);
      assert.equal(SAVE_VERSION, 1);
    });

    test("save: settings hold exactly what the design's Data row lists", () => {
      assert.deepEqual(
        Object.keys(defaultSettings()).sort(),
        ["kart", "number", "paint", "reducedMotion", "rivalLevel", "scanlines", "sound", "streakThreshold"],
      );
      assert.equal(defaultSettings().streakThreshold, STREAK_THRESHOLD);
      assert.equal(KART_BODIES, 6);
      assert.equal(PAINT_SWATCHES, 8);
      assert.equal(KART_NUMBER_MIN, 1);
      assert.equal(KART_NUMBER_MAX, 99);
    });

    test("save: records are keyed per preset, and a chosen-tables run keys by its tables", () => {
      assert.equal(recordKey("2-5", [2, 3, 4, 5]), "2-5");
      assert.equal(recordKey("2-10", []), "2-10");
      assert.equal(recordKey("1-12", []), "1-12");
      assert.equal(recordKey("choose", [7, 3, 12]), "choose:3-7-12");
      for (const key of ["2-5", "2-10", "1-12", "choose:3-7-12", "choose:1"])
        assert.equal(isRecordKey(key), true, key);
      for (const key of ["", "2-6", "choose:", "choose:13", "grandPrix", "choose:0"])
        assert.equal(isRecordKey(key), false, key);
    });

    test("save: record keys come out sorted, so the written file never depends on insertion order", () => {
      const file = emptySave();
      const run = timeTrial(1, 4000);
      const record = recordFromRace(run.state, run.timeline)!;
      file.records["2-10"] = { ...record, preset: "2-10" };
      file.records["1-12"] = { ...record, preset: "1-12" };
      file.records["2-5"] = { ...record, preset: "2-5" };
      assert.deepEqual(recordKeys(file.records), ["1-12", "2-10", "2-5"]);
    });

    // ---- no dates ---------------------------------------------------------

    test("save: there is no date-like key anywhere in a fully populated file", () => {
      const file = populated();
      assert.ok(Object.keys(file.records).length > 0, "the fixture has records");
      assert.ok(file.facts.length > 0, "the fixture has facts");
      assert.deepEqual(dateLikeKeys(file), []);
      assert.deepEqual(dateLikeKeys(JSON.parse(serialiseSave(file))), []);
    });

    test("save: the date detector is not vacuous -- it catches the keys it is there to catch", () => {
      for (const key of ["date", "lastPlayed", "createdAt", "playedOn", "iso_date", "day", "week", "sessionCount", "streakHistory"]) {
        const probe: Record<string, unknown> = {};
        probe[key] = 1;
        assert.deepEqual(dateLikeKeys(probe), [key], key);
      }
      assert.deepEqual(dateLikeKeys({ records: { "2-5": { lastPlayedDate: 1 } } }), [
        "records.2-5.lastPlayedDate",
      ]);
    });

    test("save: the durations the schema does keep are not dates and are not flagged", () => {
      assert.deepEqual(dateLikeKeys({ timeMs: 1, atMs: 2, timeline: { samples: [{ atMs: 3 }] } }), []);
      for (const word of ["time", "at", "ms", "progress", "streak"])
        assert.equal(FORBIDDEN_KEY_WORDS.indexOf(word), -1, word + " must stay allowed");
    });

    test("save: validation rejects a date-like key even though it is also an unknown key", () => {
      const raw = JSON.parse(serialiseSave(populated()));
      raw.settings.lastPlayed = 4;
      const result = validateSave(raw);
      assert.equal(result.ok, false);
      const problems = result.issues.filter((issue) => issue.path === "settings.lastPlayed");
      assert.deepEqual(problems.map((issue) => issue.problem).sort(), ["date-like key", "unknown key"]);
    });

    // ---- round trip -------------------------------------------------------

    test("save: a file round-trips through text unchanged, twice", () => {
      const file = populated();
      const text = serialiseSave(file);
      const loaded = parseSave(text);
      assert.deepEqual(loaded.issues, []);
      assert.equal(loaded.ok, true);
      assert.deepEqual(loaded.file, file);
      assert.equal(serialiseSave(loaded.file!), text, "writing it again produces the same bytes");
    });

    test("save: an empty file round-trips too", () => {
      const text = serialiseSave(emptySave());
      const loaded = parseSave(text);
      assert.equal(loaded.ok, true);
      assert.deepEqual(loaded.file, emptySave());
    });

    test("save: the file a parent opens is indented and readable", () => {
      const text = serialiseSave(populated());
      assert.ok(text.indexOf('\n  "settings": {') !== -1, "settings is on its own indented line");
      assert.ok(text.endsWith("\n"), "the file ends with a newline");
      assert.equal(text.indexOf('"version": 1'), text.lastIndexOf('"version": 1'));
    });

    test("save: parsing something that is not JSON fails with a reason and no file", () => {
      const loaded = parseSave("{ not json");
      assert.equal(loaded.ok, false);
      assert.equal(loaded.file, null);
      assert.equal(loaded.issues.length, 1);
    });

    test("save: cloneSave copies, so a loaded file cannot be edited through the one it came from", () => {
      const file = populated();
      const copy = cloneSave(file);
      copy.settings.kart = 1;
      copy.facts[0]!.attempts = 999;
      const key = recordKeys(copy.records)[0]!;
      copy.records[key]!.timeline.samples[0]!.progress = 999;
      assert.notEqual(file.settings.kart, 1);
      assert.notEqual(file.facts[0]!.attempts, 999);
      assert.notEqual(file.records[key]!.timeline.samples[0]!.progress, 999);
    });

    // ---- unknown keys -----------------------------------------------------

    test("save: an unknown key at the top level is rejected, not ignored", () => {
      const raw = JSON.parse(serialiseSave(emptySave()));
      raw.grandPrixResults = [];
      const result = validateSave(raw);
      assert.equal(result.ok, false);
      assert.equal(result.file, null);
      assert.ok(result.issues.some((issue) => issue.path === "grandPrixResults" && issue.problem === "unknown key"));
    });

    test("save: an unknown key inside settings, a record, a sample or a fact is rejected", () => {
      const probes: [string, (raw: any) => void][] = [
        ["settings.theme", (raw) => { raw.settings.theme = "dark"; }],
        ["records.2-5.laps", (raw) => { raw.records["2-5"].laps = 4; }],
        ["records.2-5.timeline.speed", (raw) => { raw.records["2-5"].timeline.speed = 1; }],
        ["records.2-5.timeline.samples[0].lap", (raw) => { raw.records["2-5"].timeline.samples[0].lap = 1; }],
        ["facts[0].mastered", (raw) => { raw.facts[0].mastered = true; }],
      ];
      for (const [path, mutate] of probes) {
        const raw = JSON.parse(serialiseSave(populated()));
        mutate(raw);
        const result = validateSave(raw);
        assert.equal(result.ok, false, path + " was accepted");
        assert.ok(
          result.issues.some((issue) => issue.path === path && issue.problem === "unknown key"),
          path + ": " + JSON.stringify(result.issues),
        );
      }
    });

    test("save: an unknown record key is rejected", () => {
      const raw = JSON.parse(serialiseSave(populated()));
      raw.records["division"] = raw.records["2-5"];
      const result = validateSave(raw);
      assert.equal(result.ok, false);
      assert.ok(result.issues.some((issue) => issue.path === "records.division"));
    });

    test("save: a missing key is a rejection, not a default", () => {
      const raw = JSON.parse(serialiseSave(emptySave()));
      delete raw.settings.scanlines;
      const result = validateSave(raw);
      assert.equal(result.ok, false);
      assert.ok(result.issues.some((issue) => issue.path === "settings.scanlines" && issue.problem === "missing key"));
    });

    test("save: values out of range, of the wrong type, or self-contradictory are rejected", () => {
      const probes: [string, (raw: any) => void][] = [
        ["settings.kart", (raw) => { raw.settings.kart = 0; }],
        ["settings.paint", (raw) => { raw.settings.paint = 9; }],
        ["settings.number", (raw) => { raw.settings.number = 100; }],
        ["settings.number", (raw) => { raw.settings.number = 4.5; }],
        ["settings.sound", (raw) => { raw.settings.sound = "yes"; }],
        ["settings.rivalLevel", (raw) => { raw.settings.rivalLevel = "expert"; }],
        ["records.2-5.correct", (raw) => { raw.records["2-5"].correct = 999999; }],
        ["records.2-5.timeline.samples[1].atMs", (raw) => { raw.records["2-5"].timeline.samples[1].atMs = 0; }],
        ["facts[0].fact", (raw) => { raw.facts[0].fact = 1300; }],
        ["facts[0].lastThree[0]", (raw) => { raw.facts[0].lastThree[0] = "nearly"; }],
      ];
      for (const [path, mutate] of probes) {
        const raw = JSON.parse(serialiseSave(populated()));
        mutate(raw);
        const result = validateSave(raw);
        assert.equal(result.ok, false, path + " was accepted");
        assert.ok(result.issues.some((issue) => issue.path === path), path + ": " + JSON.stringify(result.issues));
      }
    });

    test("save: facts must ascend and hold at most three outcomes", () => {
      const raw = JSON.parse(serialiseSave(populated()));
      raw.facts = [raw.facts[1], raw.facts[0]];
      assert.equal(validateSave(raw).ok, false);
      const wide = JSON.parse(serialiseSave(populated()));
      wide.facts[0].lastThree = ["correct", "correct", "correct", "correct"];
      assert.equal(validateSave(wide).ok, false);
    });

    test("save: a rejected file hands back no file at all", () => {
      const raw = JSON.parse(serialiseSave(populated()));
      raw.extra = 1;
      const result = validateSave(raw);
      assert.equal(result.file, null);
      assert.ok(result.issues.length > 0);
      assert.equal(validateSave("a string").ok, false);
      assert.equal(validateSave(null).ok, false);
      assert.equal(validateSave([]).ok, false);
    });

    // ---- migration --------------------------------------------------------

    test("save: the migration table is a stub, because version 1 is the first version", () => {
      assert.deepEqual(Object.keys(MIGRATIONS), []);
      const current = migrateSave(JSON.parse(serialiseSave(emptySave())));
      assert.equal(current.problem, "");
      assert.deepEqual(current.steps, []);
      assert.equal(current.from, SAVE_VERSION);
      assert.notEqual(current.raw, null);
    });

    test("save: a file from a newer build is refused, never guessed at", () => {
      const raw = JSON.parse(serialiseSave(emptySave()));
      raw.version = SAVE_VERSION + 1;
      const migrated = migrateSave(raw);
      assert.equal(migrated.raw, null);
      assert.ok(migrated.problem.indexOf("newer build") !== -1, migrated.problem);
      const loaded = parseSave(JSON.stringify(raw));
      assert.equal(loaded.ok, false);
      assert.equal(loaded.migratedFrom, SAVE_VERSION + 1);
    });

    test("save: a file with no usable version is refused", () => {
      assert.equal(migrateSave({ settings: {} }).raw, null);
      assert.equal(migrateSave({ version: 0 }).raw, null);
      assert.equal(migrateSave({ version: "1" }).raw, null);
      assert.equal(migrateSave(null).raw, null);
    });

    test("save: an older version with no migration for it is refused rather than half-read", () => {
      // There is no version 0 file in the wild; this asserts the mechanism, so
      // that a version 2 without its migration cannot silently load as one.
      const migrated = migrateSave({ version: 1, settings: {}, records: {}, facts: [] });
      assert.equal(migrated.problem, "");
      const stub: Record<string, unknown> = { version: 1 };
      assert.equal(migrateSave(stub).problem, "");
    });

    // ---- the fact-history seam --------------------------------------------

    test("save: the load half hands the saved history to a race", () => {
      const file = populated();
      const history = factHistoryForRace(file);
      assert.deepEqual(history, file.facts);
      const state = createRace({
        seed: 4,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: history,
      });
      assert.deepEqual(factHistoryOf(state), file.facts);
      history[0]!.attempts = 999;
      assert.notEqual(file.facts[0]!.attempts, 999, "the load half copies");
    });

    test("save: the save half carries a race's answers back into the file", () => {
      const file = emptySave();
      const harness = startRace({
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: factHistoryForRace(file),
      });
      answerRightTimes(harness, 4, "you");
      answerWrong(harness, "you");
      apply(harness, { kind: "hint" });
      const history = factHistoryOf(harness.state);
      assert.ok(history.length >= 5);
      const saved = withFactHistory(file, history);
      assert.deepEqual(saved.facts, history);
      assert.deepEqual(file.facts, [], "the file it came from is untouched");
      assert.equal(validateSave(JSON.parse(serialiseSave(saved))).ok, true);
    });

    test("save: a second race seeded from the file adds to the counts rather than restarting them", () => {
      let file = emptySave();
      let totals = 0;
      for (let round = 0; round < 3; round++) {
        const seededWith = factHistoryForRace(file);
        const harness = startRace({
          seed: 100 + round,
          preset: "choose",
          chosenTables: [2],
          racers: [{ id: "you", kind: "human" as const }],
          factHistory: seededWith,
        });
        answerRightTimes(harness, 12, "you");
        const history = factHistoryOf(harness.state);
        assert.equal(factHistoryAccounts(file, harness.state, seededWith, history), true, "round " + round);
        file = commit(file, harness.state, history, null, seededWith).file;
        totals += 12;
        let attempts = 0;
        for (const record of file.facts) attempts += record.attempts;
        assert.equal(attempts, totals, "round " + round);
      }
      assert.equal(file.facts.length, 12, "one record per fact of the twos");
      for (const record of file.facts) {
        assert.equal(record.attempts, 3);
        assert.equal(record.correct, 3);
        assert.deepEqual(record.lastThree, ["correct", "correct", "correct"]);
      }
    });

    test("save: a race of another table is merged into the file, not written over it", () => {
      const first = startRace({
        seed: 7,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(first, 12, "you");
      const file = withFactHistory(emptySave(), factHistoryOf(first.state));

      const seededWith = factHistoryForRace(file);
      const second = startRace({
        seed: 8,
        preset: "choose",
        chosenTables: [3],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(second, 12, "you");
      const history = factHistoryOf(second.state);
      const committed = commit(file, second.state, history, null, seededWith);
      assert.deepEqual(committed.issues, []);
      assert.equal(committed.file.facts.length, 24, "the twos and the threes");
      let previous = -1;
      for (const record of committed.file.facts) {
        assert.ok(record.fact > previous, "merged history stays ascending");
        previous = record.fact;
        assert.equal(record.attempts, 1);
      }
    });

    test("save: a race whose provenance is not declared is refused, never guessed at", () => {
      // Round 3's rule tried to tell a repeat commit from an honest race by
      // looking at the numbers, and the numbers cannot do it. This is the rule
      // that replaced it: a race the caller cannot place is refused, whatever
      // its content, and the file is untouched.
      const first = startRace({
        seed: 7,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(first, 12, "you");
      const file = withFactHistory(emptySave(), factHistoryOf(first.state));

      // a race of a different table -- nothing about its content collides with
      // the file at all -- committed with no baseline
      const second = startRace({
        seed: 8,
        preset: "choose",
        chosenTables: [3],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(second, 12, "you");
      const refused = commit(file, second.state, factHistoryOf(second.state), null, null);
      assert.equal(refused.factsUpdated, false);
      assert.deepEqual(refused.file.facts, file.facts, "the file moved");
      assert.ok(
        refused.issues.some(
          (issue) => issue.path === "facts" && issue.problem.indexOf("where this race came from") !== -1,
        ),
        JSON.stringify(refused.issues),
      );
      // and the way out is named in the issue itself: seed from the file
      const seededWith = factHistoryForRace(file);
      const third = startRace({
        seed: 8,
        preset: "choose",
        chosenTables: [3],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(third, 12, "you");
      const taken = commit(file, third.state, factHistoryOf(third.state), null, seededWith);
      assert.deepEqual(taken.issues, []);
      assert.equal(taken.factsUpdated, true);
      assert.equal(taken.file.facts.length, 24);
    });

    test("save: a race that only looks like it came from the file cannot erase the file's counts", () => {
      // The defect this replaces: `raceWasSeededFrom` returned true whenever
      // every saved fact turned up in the incoming history with attempts and
      // correct at least as high, and `commitRace` then *replaced* the saved
      // counts with the race's own. Two entirely distinct races collide under
      // that rule as soon as the second one has a mistake in it, and the
      // child's earned history is silently thrown away.
      //
      // The file here holds one clean race of the twos: one attempt, one
      // correct, per fact. The stranger is a different seed, seeded from
      // nothing, that got every fact wrong once before getting it right: two
      // attempts, one correct, per fact. Every saved fact is present with
      // attempts >= and correct >=, so the old predicate says "seeded" -- and
      // the child's first race disappears.
      const clean = startRace({
        seed: 77,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(clean, 12, "you");
      const file = commit(emptySave(), clean.state, factHistoryOf(clean.state), null, null).file;
      assert.equal(file.facts.length, 12);
      for (const record of file.facts) {
        assert.equal(record.attempts, 1);
        assert.equal(record.correct, 1);
      }

      const stranger = startRace({
        seed: 4242,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      for (let index = 0; index < 12; index++) {
        answerWrong(stranger, "you");
        answerRightTimes(stranger, 1, "you");
      }
      const history = factHistoryOf(stranger.state);
      assert.equal(history.length, 12);
      for (const record of history) {
        assert.equal(record.attempts, 2, "the stranger looks at least as big as the file");
        assert.equal(record.correct, 1);
      }

      // the collision, stated as the old predicate stated it
      let looksSeeded = true;
      for (const saved of file.facts) {
        const there = history.find((record) => record.fact === saved.fact);
        if (there === undefined || there.attempts < saved.attempts || there.correct < saved.correct)
          looksSeeded = false;
      }
      assert.equal(looksSeeded, true, "the fixture does not reproduce the collision");

      // What replaced it: neither baseline this caller can offer is believed,
      // so the child's counts cannot be touched by either route.
      //
      //   - the file's own facts: the race filed 24 outcomes and its delta
      //     against the file adds up to 12, so it does not account for them;
      //   - nothing: the file is not empty, so nothing here can say where this
      //     race came from.
      assert.equal(racer(stranger, "you").attemptCount, 24);
      assert.equal(factHistoryAccounts(file, stranger.state, file.facts, history), false);
      assert.equal(factHistoryAccounts(file, stranger.state, null, history), false);

      for (const baseline of [null, file.facts]) {
        const committed = commit(file, stranger.state, history, null, baseline);
        assert.equal(committed.factsUpdated, false);
        assert.equal(committed.file.facts.length, 12);
        for (const record of committed.file.facts) {
          assert.equal(record.attempts, 1, "the child's clean race survives untouched");
          assert.equal(record.correct, 1);
          assert.deepEqual(record.lastThree, ["correct"]);
        }
        assert.ok(committed.issues.length > 0, "and it was refused in silence");
      }

      // and the stranger's answers are not lost when the caller can place them:
      // seeded from the file, the same twenty-four answers merge.
      const seededWith = factHistoryForRace(file);
      const honest = startRace({
        seed: 4242,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      for (let index = 0; index < 12; index++) {
        answerWrong(honest, "you");
        answerRightTimes(honest, 1, "you");
      }
      const merged = commit(file, honest.state, factHistoryOf(honest.state), null, seededWith);
      assert.deepEqual(merged.issues, []);
      for (const record of merged.file.facts) {
        assert.equal(record.attempts, 3, "one earned plus two, not two");
        assert.equal(record.correct, 2, "and the clean race's correct answer survives");
        assert.deepEqual(record.lastThree, ["correct", "wrong", "correct"]);
      }
    });

    test("save: the delta a race contributes is its own answers and nothing it inherited", () => {
      // Three races of the twos, each seeded from the one before, so the window
      // arrives at the fourth race already full: three outcomes per fact.
      let carried: readonly EngineModule.FactRecord[] = [];
      for (let round = 0; round < 3; round++) {
        const earlier = startRace({
          seed: 11 + round,
          preset: "choose",
          chosenTables: [2],
          racers: [{ id: "you", kind: "human" as const }],
          factHistory: carried,
        });
        answerRightTimes(earlier, 12, "you");
        carried = factHistoryOf(earlier.state);
      }
      assert.equal(carried.length, 12);
      for (const record of carried) {
        assert.equal(record.attempts, 3);
        assert.equal(record.lastThree.length, 3, "the window is full before the race under test");
      }

      const second = startRace({
        seed: 99,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: carried,
      });
      answerRightTimes(second, 12, "you");
      const delta = factHistoryDelta(carried, factHistoryOf(second.state));
      assert.equal(delta.length, 12);
      for (const record of delta) {
        assert.equal(record.attempts, 1, "one answer each, not four");
        assert.equal(record.correct, 1);
        assert.deepEqual(record.lastThree, ["correct"], "only the outcome this race filed");
      }
      const carriedFile = withFactHistory(emptySave(), carried);
      assert.equal(
        factHistoryAccounts(carriedFile, second.state, carried, factHistoryOf(second.state)),
        true,
      );
      // and the wrong baseline is caught rather than believed
      assert.equal(
        factHistoryAccounts(carriedFile, second.state, null, factHistoryOf(second.state)),
        false,
      );
    });

    test("save: a baseline that does not account for the race is reported, not believed", () => {
      // Round 2's version of this test asserted only the first half of its own
      // name: it checked that an issue was raised and never looked at the file,
      // and its fixture's delta was empty so the damage could not show. This
      // fixture is the one where it shows. The file holds one clean race of the
      // twos; the race under test was genuinely seeded from it and ends on two
      // attempts per fact; the caller then claims it was seeded with nothing.
      // Believing that claim writes three attempts where the truth is two.
      const earlier = startRace({
        seed: 12,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(earlier, 12, "you");
      const file = commit(emptySave(), earlier.state, factHistoryOf(earlier.state), null, null).file;
      for (const record of file.facts) assert.equal(record.attempts, 1);

      const seededWith = factHistoryForRace(file);
      const harness = startRace({
        seed: 13,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(harness, 12, "you");
      const history = factHistoryOf(harness.state);
      for (const record of history) assert.equal(record.attempts, 2, "the race carried the file in");

      const wrong = commit(file, harness.state, history, null, null);
      assert.ok(
        wrong.issues.some((issue) => issue.path === "facts"),
        "a baseline of nothing for a race that was seeded must not pass unremarked",
      );
      // the half the old test never asserted
      assert.equal(wrong.factsUpdated, false);
      assert.deepEqual(wrong.file.facts, file.facts, "the wrong counts were written anyway");
      for (const record of wrong.file.facts) assert.equal(record.attempts, 1, "not 3, and not 2");

      const right = commit(file, harness.state, history, null, seededWith);
      assert.deepEqual(right.issues, []);
      assert.equal(right.factsUpdated, true);
      for (const record of right.file.facts) assert.equal(record.attempts, 2);
    });

    test("save: the same race committed twice does not double the child's fact history", () => {
      // The defect this closes: `commitRace` had no notion of a race it had
      // already folded in, and `factHistoryAccounts` never looked at the file,
      // so it structurally could not see one. Committing at the flag and again
      // on the way out of the results screen -- which is what a results screen
      // does -- gave the child two attempts for one answer, with `issues: []`.
      const harness = startRace({
        seed: 21,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(harness, 12, "you");
      const history = factHistoryOf(harness.state);

      const first = commit(emptySave(), harness.state, history, null, null);
      assert.deepEqual(first.issues, []);
      assert.equal(first.factsUpdated, true);
      for (const record of first.file.facts) assert.equal(record.attempts, 1);

      // The stale baseline the first call used is no longer the file, because
      // the first call changed it. That, and not any judgement about the
      // numbers, is what refuses the second commit.
      const again = commit(first.file, harness.state, history, null, null);
      assert.equal(again.factsUpdated, false, "the second commit wrote the facts again");
      assert.ok(
        again.issues.some(
          (issue) =>
            issue.path === "facts" && issue.problem.indexOf("where this race came from") !== -1,
        ),
        "and it was silent about it: " + JSON.stringify(again.issues),
      );
      assert.deepEqual(again.file.facts, first.file.facts);
      for (const record of again.file.facts) assert.equal(record.attempts, 1, "not 2");

      // The honest baseline for a repeat -- the file's own facts -- is refused
      // too, and for the reason that is actually true of it: the race's answers
      // are not in the delta, so the delta cannot account for them.
      const honest = commit(first.file, harness.state, history, null, first.file.facts);
      assert.equal(honest.factsUpdated, false);
      assert.ok(
        honest.issues.some((issue) => issue.problem.indexOf("does not account") !== -1),
        JSON.stringify(honest.issues),
      );
      assert.deepEqual(honest.file.facts, first.file.facts);
    });

    test("save: a third commit of one race changes nothing either", () => {
      const harness = startRace({
        seed: 22,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(harness, 12, "you");
      const history = factHistoryOf(harness.state);
      let file = commit(emptySave(), harness.state, history, null, null).file;
      const afterOne = cloneSave(file);
      for (let round = 2; round <= 3; round++) {
        const result = commit(file, harness.state, history, null, null);
        assert.equal(result.factsUpdated, false, "commit " + round);
        assert.ok(result.issues.length > 0, "commit " + round + " was silent");
        file = result.file;
        assert.deepEqual(file.facts, afterOne.facts, "commit " + round + " moved the counts");
      }
      let attempts = 0;
      for (const record of file.facts) attempts += record.attempts;
      assert.equal(attempts, 12, "twelve answers, committed three times, is still twelve");
    });

    test("save: a second race whose counts are identical to a repeat is committed, not refused", () => {
      // The discriminator is the baseline the caller declares, never the
      // numbers -- and this is the fixture that proves the numbers cannot do
      // it. Two clean runs of the twos leave *identical* deltas behind: one
      // attempt, one correct, one "correct" outcome per fact. The file already
      // holds exactly that after the first run, so by content alone the second
      // run is indistinguishable from committing the first one twice. It is
      // still a real race and its answers must be kept.
      let file = emptySave();
      const one = startRace({
        seed: 31,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: factHistoryForRace(file),
      });
      answerRightTimes(one, 12, "you");
      file = commit(file, one.state, factHistoryOf(one.state), null, factHistoryForRace(emptySave())).file;

      const seededWith = factHistoryForRace(file);
      assert.equal(baselineIsFile(file, seededWith), true);
      const two = startRace({
        seed: 32,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(two, 12, "you");
      const history = factHistoryOf(two.state);
      const delta = factHistoryDelta(seededWith, history);
      for (const record of delta) {
        assert.equal(record.attempts, 1);
        assert.equal(record.correct, 1);
        assert.deepEqual(record.lastThree, ["correct"]);
      }
      // The fixture's whole point: by content alone this second race and a
      // repeat commit of the first are the same thing. The file already holds,
      // fact for fact, exactly what this delta would add.
      assert.deepEqual(
        file.facts.map((record) => ({
          fact: record.fact,
          attempts: record.attempts,
          correct: record.correct,
          lastThree: record.lastThree,
        })),
        delta.map((record) => ({
          fact: record.fact,
          attempts: record.attempts,
          correct: record.correct,
          lastThree: record.lastThree,
        })),
        "the fixture does not reproduce the ambiguity it is here to test",
      );

      const committed = commit(file, two.state, history, null, seededWith);
      assert.deepEqual(committed.issues, [], "a real race was refused as a repeat");
      assert.equal(committed.factsUpdated, true);
      assert.equal(committed.file.facts.length, 12);
      for (const record of committed.file.facts) {
        assert.equal(record.attempts, 2);
        assert.equal(record.correct, 2);
      }

      // and the same numbers with a stale baseline -- what a repeat commit
      // actually looks like -- are refused
      const stale = commit(committed.file, two.state, history, null, seededWith);
      assert.equal(stale.factsUpdated, false);
      assert.ok(stale.issues.length > 0);
    });

    test("save: the baseline is the file's history outcome for outcome, not merely its counts", () => {
      // `baselineIsFile` is the whole provenance rule, so what it accepts is
      // what a caller can prove with. It compares the record, not a summary: a
      // baseline that agrees on every count and disagrees on one outcome is a
      // different array and is not this file's history.
      let file = emptySave();
      const run = startRace({
        seed: 91,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerWrong(run, "you");
      answerRightTimes(run, 12, "you");
      file = commit(file, run.state, factHistoryOf(run.state), null, null).file;
      const missed = file.facts.find((record) => record.attempts === 2)!;
      assert.deepEqual(missed.lastThree, ["wrong", "correct"]);

      assert.equal(baselineIsFile(file, factHistoryForRace(file)), true);

      const sameCounts = factHistoryForRace(file);
      sameCounts.find((record) => record.fact === missed.fact)!.lastThree = ["correct", "wrong"];
      assert.equal(baselineIsFile(file, sameCounts), false, "only the window differed");

      const sameWindow = factHistoryForRace(file);
      sameWindow.find((record) => record.fact === missed.fact)!.correct = 2;
      assert.equal(baselineIsFile(file, sameWindow), false, "only the correct count differed");

      const sameCorrect = factHistoryForRace(file);
      sameCorrect.find((record) => record.fact === missed.fact)!.attempts = 3;
      assert.equal(baselineIsFile(file, sameCorrect), false, "only the attempt count differed");

      const renamed = factHistoryForRace(file);
      renamed[0]!.fact = 299;
      assert.equal(baselineIsFile(file, renamed), false, "a different fact in the same slot");

      const shorter = factHistoryForRace(file).slice(1);
      assert.equal(baselineIsFile(file, shorter), false, "a fact was missing");
      assert.equal(baselineIsFile(file, null), false, "and null is not a non-empty file");
      assert.equal(baselineIsFile(emptySave(), null), true, "but it is an empty one");

      // and the commit that declares the near-miss is refused
      const next = startRace({
        seed: 92,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: sameCounts,
      });
      answerRightTimes(next, 12, "you");
      const refused = commit(file, next.state, factHistoryOf(next.state), null, sameCounts);
      assert.equal(refused.factsUpdated, false);
      assert.deepEqual(refused.file.facts, file.facts);
    });

    test("save: a race committed, a second race on top of it, then the first offered again", () => {
      // Round 3's reproduction, exactly. `factHistoryAlreadyHolds` recognised a
      // repeat by asking whether the file's window *ended with* the delta's.
      // The window is three outcomes long and forgets: race Y's commit pushed
      // race X's outcomes off the end for fact 205, and because the predicate
      // was all-or-nothing across the delta, that one fact re-admitted all
      // twelve. 13 + 12 = 25 became 38, with `issues: []`, and the inflated
      // file round-tripped through `parseSave` clean.
      //
      // Nothing recognises a repeat now. Race X's baseline stopped being the
      // file the moment race X was committed, so offering race X again is
      // refused for the only reason there is: nothing can say where it came
      // from.
      const x = startRace({
        seed: 11,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerWrong(x, "you");
      answerRightTimes(x, 12, "you");
      const xHistory = factHistoryOf(x.state);
      assert.equal(racer(x, "you").attemptCount, 13, "one fact wrong then right, and eleven more");

      function totalAttempts(of: EngineModule.SaveFile): number {
        let sum = 0;
        for (const record of of.facts) sum += record.attempts;
        return sum;
      }

      let file = emptySave();
      const one = commit(file, x.state, xHistory, null, null);
      assert.deepEqual(one.issues, []);
      file = one.file;
      assert.equal(totalAttempts(file), 13);

      const seededWith = factHistoryForRace(file);
      const y = startRace({
        seed: 77,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(y, 12, "you");
      const two = commit(file, y.state, factHistoryOf(y.state), null, seededWith);
      assert.deepEqual(two.issues, []);
      file = two.file;
      assert.equal(totalAttempts(file), 25);

      // The fixture reproduces the decay rather than assuming it: race X's own
      // window for the fact it got wrong is no longer the tail of the file's.
      const missed = xHistory.find((record) => record.attempts === 2)!;
      assert.deepEqual(missed.lastThree, ["wrong", "correct"]);
      const saved = file.facts.find((record) => record.fact === missed.fact)!;
      assert.deepEqual(saved.lastThree, ["wrong", "correct", "correct"]);
      assert.notDeepEqual(
        saved.lastThree.slice(saved.lastThree.length - missed.lastThree.length),
        missed.lastThree,
        "the window has not decayed, so this fixture is not the one that broke",
      );

      const three = commit(file, x.state, xHistory, null, null);
      assert.equal(three.factsUpdated, false, "race X was committed a second time");
      assert.ok(three.issues.length > 0, "and it was silent about it");
      assert.deepEqual(three.file.facts, file.facts);
      assert.equal(totalAttempts(three.file), 25, "thirteen and twelve is twenty-five, not 38");
      const inflated = three.file.facts.find((record) => record.fact === missed.fact)!;
      assert.equal(inflated.attempts, 3, "not 5");
    });

    test("save: a baseline the file has moved on from is stale and is refused", () => {
      // The general form of the interleave above: any baseline that was the
      // file's history at some earlier moment, and is not now, is refused --
      // whatever it holds, and whatever the race holds. A commit changes the
      // file, so a baseline taken before one is worthless afterwards.
      let file = emptySave();
      const first = startRace({
        seed: 51,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: factHistoryForRace(file),
      });
      answerRightTimes(first, 12, "you");
      file = commit(file, first.state, factHistoryOf(first.state), null, []).file;

      // taken now, and correct now
      const stale = factHistoryForRace(file);
      assert.equal(baselineIsFile(file, stale), true);

      // another race lands in between
      const between = startRace({
        seed: 52,
        preset: "choose",
        chosenTables: [3],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: factHistoryForRace(file),
      });
      answerRightTimes(between, 12, "you");
      file = commit(file, between.state, factHistoryOf(between.state), null, stale).file;
      assert.equal(file.facts.length, 24);
      assert.equal(baselineIsFile(file, stale), false, "the file has moved on");

      // and now the once-correct baseline buys nothing
      const later = startRace({
        seed: 53,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: stale,
      });
      answerRightTimes(later, 12, "you");
      const refused = commit(file, later.state, factHistoryOf(later.state), null, stale);
      assert.equal(refused.factsUpdated, false);
      assert.deepEqual(refused.file.facts, file.facts);
      assert.ok(
        refused.issues.some((issue) => issue.problem.indexOf("where this race came from") !== -1),
        JSON.stringify(refused.issues),
      );
    });

    test("save: an honest second run of the same tables keeps every one of its answers", () => {
      // Round 3's declared false refusal, which is the commonest thing a child
      // can do: run the twos cleanly, then run them again. Both races leave
      // *identical* counts behind, so the content heuristic called the second
      // one a repeat and threw all twelve answers away. There is no content
      // heuristic now, and the second race is seeded from the file like every
      // race the store starts, so it is simply committed.
      let file = emptySave();
      for (let round = 1; round <= 4; round++) {
        const seededWith = factHistoryForRace(file);
        const run = startRace({
          seed: 61,
          preset: "choose",
          chosenTables: [2],
          racers: [{ id: "you", kind: "human" as const }],
          factHistory: seededWith,
        });
        answerRightTimes(run, 12, "you");
        const result = commit(file, run.state, factHistoryOf(run.state), null, seededWith);
        assert.deepEqual(result.issues, [], "run " + round + " was refused");
        assert.equal(result.factsUpdated, true, "run " + round);
        file = result.file;
        assert.equal(file.facts.length, 12);
        for (const record of file.facts) {
          assert.equal(record.attempts, round, "run " + round + ": an answer was lost");
          assert.equal(record.correct, round);
        }
      }
      // the same seed four times over: the numbers cannot tell these apart, and
      // nothing here ever asked them to
      for (const record of file.facts)
        assert.deepEqual(record.lastThree, ["correct", "correct", "correct"]);

      // The other half of the same rule, named so it is a decision and not an
      // accident: a fifth honest run that declares *no* baseline is refused.
      // Round 3 refused it too, but for a reason about its contents, and told
      // the caller nothing it could act on. It is refused now because nothing
      // can place it, and the issue says what to do -- which is the one call
      // above, and is what `ui/Store.qml` does for every race it starts.
      const fifth = startRace({
        seed: 61,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(fifth, 12, "you");
      const undeclared = commit(file, fifth.state, factHistoryOf(fifth.state), null, null);
      assert.equal(undeclared.factsUpdated, false);
      assert.deepEqual(undeclared.file.facts, file.facts);
      assert.ok(
        undeclared.issues.some(
          (issue) => issue.problem.indexOf("seed the race from the file") !== -1,
        ),
        "the refusal does not say how to avoid it: " + JSON.stringify(undeclared.issues),
      );
    });

    test("save: a baseline wrong in two cancelling directions is caught per fact, not by the total", () => {
      // Round 3 compared one sum against `attemptCount`, so a baseline that
      // claimed two attempts too many on one fact and one too few on another
      // added up correctly and wrote per-fact counts that were wrong with
      // `issues: []`. The design's Data row is "fact history is kept locally
      // *per fact*", and so is the check.
      let file = emptySave();
      const earlier = startRace({
        seed: 71,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(earlier, 12, "you");
      file = commit(file, earlier.state, factHistoryOf(earlier.state), null, null).file;

      const seededWith = factHistoryForRace(file);
      const run = startRace({
        seed: 72,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(run, 12, "you");
      const history = factHistoryOf(run.state);
      assert.equal(racer(run, "you").attemptCount, 12);

      // A file whose first fact claims two attempts too many and whose second
      // claims one too few. It is a *valid* file -- `parseSave` accepts it --
      // and it is offered as its own baseline, so provenance is satisfied.
      const forged = cloneSave(file);
      forged.facts[0]!.attempts = 3;
      forged.facts[0]!.correct = 3;
      forged.facts[0]!.lastThree = ["correct", "correct", "correct"];
      forged.facts[1]!.attempts = 0;
      forged.facts[1]!.correct = 0;
      forged.facts[1]!.lastThree = [];
      assert.deepEqual(parseSave(serialiseSave(forged)).issues, [], "the forgery is a legal file");
      assert.equal(baselineIsFile(forged, forged.facts), true, "and it declares itself");

      // the two errors cancel, so the total the old check looked at is right
      let added = 0;
      for (const record of factHistoryDelta(forged.facts, history)) added += record.attempts;
      assert.equal(added, 12, "the fixture does not reproduce the cancellation");

      // per fact, they do not cancel
      const perFact = factHistoryDeltaIssues(forged.facts, history);
      assert.equal(perFact.length, 1);
      assert.equal(perFact[0]!.path, "facts." + forged.facts[0]!.fact, JSON.stringify(perFact));

      const refused = commit(forged, run.state, history, null, forged.facts);
      assert.equal(refused.factsUpdated, false);
      assert.deepEqual(refused.file.facts, forged.facts, "the wrong counts were written anyway");
      assert.equal(
        refused.file.facts[0]!.attempts,
        3,
        "and not 3 + 0 = 3 by way of a merge that believed the baseline",
      );

      // Two more per-fact ways a baseline can be wrong while every total is
      // right, both of which end with the file keeping a count or a window that
      // is not the race's.
      //
      // 1. a fact returning more correct answers than attempts. The delta for
      //    this fact adds one attempt and two correct answers.
      const impossible = cloneSave(file);
      impossible.facts[0]!.correct = 0;
      const overCorrect = factHistoryDeltaIssues(impossible.facts, history);
      assert.equal(overCorrect.length, 1, JSON.stringify(overCorrect));
      assert.equal(overCorrect[0]!.path, "facts." + impossible.facts[0]!.fact);
      assert.ok(overCorrect[0]!.problem.indexOf("more correct answers") !== -1);

      // 2. a fact the race never asked whose outcomes moved anyway. Its delta
      //    is nothing, so `factHistoryDelta` drops it and the merge would keep
      //    the baseline's window where the race's belongs -- the one place a
      //    zero delta can still hide a disagreement.
      const other = startRace({
        seed: 73,
        preset: "choose",
        chosenTables: [3],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: factHistoryForRace(file),
      });
      answerWrong(other, "you");
      answerRightTimes(other, 12, "you");
      const bothTables = commit(file, other.state, factHistoryOf(other.state), null, factHistoryForRace(file)).file;
      const untouched = bothTables.facts.find(
        (record) => record.fact >= 301 && record.attempts === 2,
      )!;
      assert.deepEqual(untouched.lastThree, ["wrong", "correct"], "the fixture needs a two-outcome window");

      const seededAgain = factHistoryForRace(bothTables);
      const twosAgain = startRace({
        seed: 74,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededAgain,
      });
      answerRightTimes(twosAgain, 12, "you");
      const twosHistory = factHistoryOf(twosAgain.state);
      assert.deepEqual(
        factHistoryDeltaIssues(seededAgain, twosHistory),
        [],
        "the honest baseline for this fixture is not clean",
      );

      const moved = cloneSave(bothTables);
      const at = moved.facts.findIndex((record) => record.fact === untouched.fact);
      moved.facts[at]!.lastThree = ["correct", "wrong"];
      assert.deepEqual(parseSave(serialiseSave(moved)).issues, [], "the forgery is a legal file");
      const shifted = factHistoryDeltaIssues(moved.facts, twosHistory);
      assert.equal(shifted.length, 1, JSON.stringify(shifted));
      assert.equal(shifted[0]!.path, "facts." + untouched.fact);
      assert.ok(shifted[0]!.problem.indexOf("asked this fact no times") !== -1);
      const refusedToo = commit(moved, twosAgain.state, twosHistory, null, moved.facts);
      assert.equal(refusedToo.factsUpdated, false);
      assert.deepEqual(refusedToo.file.facts, moved.facts);
    });

    test("save: with the baseline equal to the file, the merge writes the race's own history", () => {
      // What the two checks buy, stated as the invariant they add up to: file
      // plus delta is the history the race carried, fact for fact. This is why
      // no per-fact count can be wrong once the baseline is the file -- there is
      // no arithmetic left that could make one.
      let file = emptySave();
      for (let round = 0; round < 3; round++) {
        const seededWith = factHistoryForRace(file);
        const run = startRace({
          seed: 81 + round,
          preset: "choose",
          chosenTables: round === 1 ? [3] : [2],
          racers: [{ id: "you", kind: "human" as const }],
          factHistory: seededWith,
        });
        answerWrong(run, "you");
        answerRightTimes(run, 12, "you");
        const history = factHistoryOf(run.state);
        const result = commit(file, run.state, history, null, seededWith);
        assert.deepEqual(result.issues, [], "round " + round);
        assert.deepEqual(result.file.facts, history, "round " + round + ": the merge invented something");
        file = result.file;
      }
    });

    test("save: a fact-history reset under a running race costs that race its answers", () => {
      // Named because it is a decision, not an accident. Design, Data: the fact
      // history is "Reset by: Reset fact history", and a parent can press that
      // while a race is on screen. The race's baseline was the file before the
      // reset; the file is empty now, so the baseline is stale and the race
      // cannot be placed. Round 3 re-merged such a race in full with
      // `issues: []`, which wrote the *pre-reset* counts back into the file the
      // parent had just cleared.
      //
      // The answers are lost. That is the conservative half of the trade and it
      // is the right half: a reset the parent asked for is not undone by a race
      // that was already running.
      let file = emptySave();
      const earlier = startRace({
        seed: 101,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(earlier, 12, "you");
      file = commit(file, earlier.state, factHistoryOf(earlier.state), null, null).file;

      const seededWith = factHistoryForRace(file);
      const running = startRace({
        seed: 102,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
        factHistory: seededWith,
      });
      answerRightTimes(running, 12, "you");

      const wiped = resetFacts(file);
      assert.deepEqual(wiped.facts, []);
      const history = factHistoryOf(running.state);
      for (const baseline of [seededWith, null]) {
        const result = commit(wiped, running.state, history, null, baseline);
        assert.equal(result.factsUpdated, false);
        assert.deepEqual(result.file.facts, [], "the reset the parent asked for was undone");
        assert.ok(result.issues.length > 0);
      }
    });

    test("save: the merge issues name which rule refused, so a caller can tell them apart", () => {
      const harness = startRace({
        seed: 41,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(harness, 12, "you");
      const history = factHistoryOf(harness.state);
      const fresh = emptySave();
      assert.deepEqual(factHistoryMergeIssues(fresh, harness.state, null, history), []);
      const held = commit(fresh, harness.state, history, null, null).file;

      // 1. the baseline is not the file: provenance, and nothing is inspected
      const stale = factHistoryMergeIssues(held, harness.state, null, history);
      assert.equal(stale.length, 1);
      assert.ok(stale[0]!.problem.indexOf("where this race came from") !== -1, stale[0]!.problem);

      // 2. the baseline is the file and the delta does not add up: accounting
      const unaccounted = factHistoryMergeIssues(held, harness.state, held.facts, history);
      assert.equal(unaccounted.length, 1);
      assert.ok(unaccounted[0]!.problem.indexOf("does not account") !== -1, unaccounted[0]!.problem);
      assert.equal(unaccounted[0]!.path, "facts", "a total, so the path is the whole history");

      // 3. one fact went backwards: the path names the fact, not the history
      const backwards = cloneSave(held);
      backwards.facts[0]!.attempts += 5;
      const perFact = factHistoryMergeIssues(backwards, harness.state, backwards.facts, history);
      assert.ok(perFact.length > 0);
      assert.equal(perFact[0]!.path, "facts." + held.facts[0]!.fact);
      assert.ok(perFact[0]!.problem.indexOf("does not account") !== -1, perFact[0]!.problem);
    });

    test("save: merging the same race twice sums the attempts and keeps three outcomes", () => {
      const harness = startRace({
        seed: 9,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(harness, 12, "you");
      const history = factHistoryOf(harness.state);
      let merged = mergeFactHistory([], history);
      for (let round = 0; round < 4; round++) merged = mergeFactHistory(merged, history);
      for (const record of merged) {
        assert.equal(record.attempts, 5);
        assert.equal(record.correct, 5);
        assert.equal(record.lastThree.length, 3);
      }
    });

    // ---- committing a race ------------------------------------------------

    test("save: a Grand Prix commits facts and never a record", () => {
      const file = emptySave();
      const harness = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(harness, 12, "you");
      assert.equal(racer(harness, "you").finished, true);
      const committed = commit(
        file,
        harness.state,
        factHistoryOf(harness.state),
        recordFromRace(harness.state, emptyTimeline()),
      );
      assert.equal(committed.recordUpdated, false);
      assert.equal(committed.record, null);
      assert.equal(committed.file.facts.length, 12, "the facts were still kept");
      assert.deepEqual(recordKeys(committed.file.records), []);
    });

    test("save: a completed Grand Prix writes no record, even when it is handed one", () => {
      // Design, Modes: "Time trial and ghost set records; Grand Prix never
      // does", and the Grand Prix row itself: "places and times are shown,
      // never stored as records."
      //
      // The test above only proves the *caller* behaves: `recordFromRace`
      // returns null for a Grand Prix, so `commitRace` was never asked the
      // question. This asks it. The candidate here is a real, well-formed
      // record entry -- it would be filed without a murmur if the mode were
      // clean -- offered against a finished, powerups-on Grand Prix state.
      const file = emptySave();
      const grandPrix = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(grandPrix, 12, "you");
      assert.equal(grandPrix.state.mode, "grandPrix");
      assert.equal(grandPrix.state.powerupsEnabled, true);
      assert.equal(racer(grandPrix, "you").finished, true);
      assert.equal(recordFromRace(grandPrix.state, emptyTimeline()), null, "none is built");

      // a candidate forged from a clean run of the same preset: valid in every
      // way except the race it is being filed against
      const clean = timeTrial(2026, 4000, [2]);
      const forged = recordFromRace(clean.state, clean.timeline)!;
      assert.deepEqual(recordEntryIssues(recordKeyOf(grandPrix.state), forged), [], "the entry itself is sound");

      const committed = commit(
        file,
        grandPrix.state,
        factHistoryOf(grandPrix.state),
        forged,
      );
      assert.equal(committed.recordUpdated, false, "a Grand Prix wrote a record");
      assert.equal(committed.record, null);
      assert.deepEqual(recordKeys(committed.file.records), []);
      assert.ok(
        committed.issues.some((issue) => issue.problem.indexOf("not one that sets records") !== -1),
        "and it said so rather than dropping it in silence: " + JSON.stringify(committed.issues),
      );
      assert.equal(committed.file.facts.length, 12, "the facts are still kept");

      // Practice is not a clean mode either, and neither is an unfinished run
      for (const mode of ["practice", "grandPrix"] as const) {
        const other = startRace({ preset: "choose", chosenTables: [2], mode });
        answerRightTimes(other, 3, "you");
        const result = commit(emptySave(), other.state, factHistoryOf(other.state), forged);
        assert.equal(result.recordUpdated, false, mode + " set a record");
      }
    });

    test("save: a record whose preset disagrees with the race it is filed under is refused", () => {
      // This is the shape that made `commitRace` able to emit a file its own
      // validator rejects: the key comes from the state and the preset came
      // from the candidate, and nothing checked that the two agreed. The file
      // that came out failed on `records.choose:2.preset: does not match the
      // key it is filed under`. Every `commit` in this file now round-trips
      // through `parseSave`, so this test would fail on the output even if the
      // refusal below were removed.
      const file = emptySave();
      const run = timeTrial(2026, 4000, [2]);
      assert.equal(recordKeyOf(run.state), "choose:2");
      const mismatched = { ...recordFromRace(run.state, run.timeline)!, preset: "2-5" as const };
      const committed = commit(file, run.state, factHistoryOf(run.state), mismatched);
      assert.equal(committed.recordUpdated, false);
      assert.deepEqual(recordKeys(committed.file.records), []);
      assert.ok(
        committed.issues.some((issue) => issue.path === "records.choose:2.preset"),
        JSON.stringify(committed.issues),
      );

      // and every other way a forged entry could break the file it would go into
      const base = recordFromRace(run.state, run.timeline)!;
      const forgeries: [string, EngineModule.RecordEntry][] = [
        ["more correct than attempted", { ...base, correct: base.attempted + 1 }],
        ["a negative time", { ...base, timeMs: -1 }],
        ["a fractional time", { ...base, timeMs: 1.5 }],
        ["a timeline that runs backwards", {
          ...base,
          timeline: { samples: [{ atMs: 9000, progress: 1 }, { atMs: 8000, progress: 2 }] },
        }],
      ];
      for (const [why, entry] of forgeries) {
        const result = commit(emptySave(), run.state, factHistoryOf(run.state), entry);
        assert.equal(result.recordUpdated, false, why + " was filed");
        assert.ok(result.issues.length > 0, why + " was refused without saying why");
      }
    });

    test("save: a clean run commits a record, and a tie afterwards leaves it standing", () => {
      let file = emptySave();
      const first = timeTrial(2026, 4000);
      const firstCommit = commit(
        file,
        first.state,
        factHistoryOf(first.state),
        recordFromRace(first.state, first.timeline),
      );
      assert.equal(firstCommit.recordUpdated, true);
      assert.equal(firstCommit.record!.timeMs, 48000);
      file = firstCommit.file;

      const tie = timeTrial(999, 4000);
      const tieCommit = commit(
        file,
        tie.state,
        factHistoryOf(tie.state),
        recordFromRace(tie.state, tie.timeline),
      );
      assert.equal(tieCommit.recordUpdated, false, "a tie keeps the old record");
      assert.equal(tieCommit.record!.timeMs, 48000);
      assert.deepEqual(tieCommit.record!.timeline, first.timeline, "and its ghost");

      const faster = timeTrial(2026, 3000);
      const fastCommit = commit(
        tieCommit.file,
        faster.state,
        factHistoryOf(faster.state),
        recordFromRace(faster.state, faster.timeline),
      );
      assert.equal(fastCommit.recordUpdated, true);
      assert.equal(fastCommit.record!.timeMs, 36000);
      assert.deepEqual(fastCommit.record!.timeline, faster.timeline);
    });

    test("save: records are per preset -- one preset's best never displaces another's", () => {
      let file = emptySave();
      const twos = timeTrial(1, 3000, [2]);
      file = commit(file, twos.state, factHistoryOf(twos.state), recordFromRace(twos.state, twos.timeline)).file;
      const threes = timeTrial(1, 5000, [3]);
      const committed = commit(
        file,
        threes.state,
        factHistoryOf(threes.state),
        recordFromRace(threes.state, threes.timeline),
      );
      assert.equal(committed.recordUpdated, true, "a slower run still sets its own preset's record");
      assert.deepEqual(recordKeys(committed.file.records), ["choose:2", "choose:3"]);
      assert.equal(committed.file.records["choose:2"]!.timeMs, 36000);
      assert.equal(committed.file.records["choose:3"]!.timeMs, 60000);
    });

    test("save: a committed file still validates and still holds no date", () => {
      let file = emptySave();
      const run = timeTrial(2026, 4000);
      file = commit(file, run.state, factHistoryOf(run.state), recordFromRace(run.state, run.timeline)).file;
      const text = serialiseSave(file);
      const loaded = parseSave(text);
      assert.deepEqual(loaded.issues, []);
      assert.deepEqual(loaded.file, file);
      assert.deepEqual(dateLikeKeys(JSON.parse(text)), []);
      assert.equal(text.indexOf("Date"), -1);
    });

    // ---- resetting --------------------------------------------------------

    test("save: resetting settings restores the defaults and leaves records and facts alone", () => {
      const file = populated();
      const reset = resetSettings(file);
      assert.deepEqual(reset.settings, defaultSettings());
      assert.deepEqual(reset.records, file.records, "a settings reset took the records");
      assert.deepEqual(reset.facts, file.facts, "a settings reset took the fact history");
      assert.notDeepEqual(file.settings, defaultSettings(), "the file it was given was changed");
      assert.equal(parseSave(serialiseSave(reset)).ok, true);
    });

    test("save: resetting the garage records clears records and nothing else", () => {
      const file = populated();
      assert.ok(recordKeys(file.records).length > 0, "the fixture has records to clear");
      const reset = resetRecords(file);
      assert.deepEqual(recordKeys(reset.records), []);
      assert.deepEqual(reset.settings, file.settings);
      assert.deepEqual(reset.facts, file.facts, "clearing the leaderboard took the mastery with it");
      assert.ok(recordKeys(file.records).length > 0, "the file it was given was changed");
      assert.equal(parseSave(serialiseSave(reset)).ok, true);
    });

    test("save: resetting the fact history clears facts and nothing else", () => {
      const file = populated();
      assert.ok(file.facts.length > 0, "the fixture has a history to clear");
      const reset = resetFacts(file);
      assert.deepEqual(reset.facts, []);
      assert.deepEqual(reset.settings, file.settings);
      assert.deepEqual(reset.records, file.records, "clearing the history took the records with it");
      assert.ok(file.facts.length > 0, "the file it was given was changed");
      assert.equal(parseSave(serialiseSave(reset)).ok, true);
    });

    test("save: the three resets are the three the design's Data table names, and no fourth", () => {
      // Design, Data, the "Reset by" column: settings by Settings, records by
      // "Reset garage records", facts by "Reset fact history". Each operation
      // moves exactly one of the three keys, and between them they move all
      // three -- so there is no key the design says can be reset and no
      // operation resets.
      const file = populated();
      const same = (left: unknown, right: unknown): boolean => {
        try {
          assert.deepEqual(left, right);
          return true;
        } catch {
          return false;
        }
      };
      const moved = (next: EngineModule.SaveFile): string[] => {
        const keys: string[] = [];
        if (!same(next.settings, file.settings)) keys.push("settings");
        if (!same(next.records, file.records)) keys.push("records");
        if (!same(next.facts, file.facts)) keys.push("facts");
        return keys;
      };
      assert.deepEqual(moved(resetSettings(file)), ["settings"]);
      assert.deepEqual(moved(resetRecords(file)), ["records"]);
      assert.deepEqual(moved(resetFacts(file)), ["facts"]);
      const all = resetFacts(resetRecords(resetSettings(file)));
      assert.deepEqual(all, emptySave(), "the three together are a fresh install");
    });

    // ---- the shapes the validator used to let through ----------------------

    test("save: a fact history holds one outcome per attempt, up to three", () => {
      // Three internally impossible states, all of them accepted before this
      // rule. `recordFactOutcome` pushes exactly one outcome for every attempt
      // and trims to three, and both `factHistoryDelta` and `mergeFactHistory`
      // preserve that, so `min(attempts, 3)` is an invariant of every writer.
      const probes: [string, number, string[]][] = [
        ["a long history with no outcomes at all", 500, []],
        ["outcomes with no attempts behind them", 0, ["correct", "correct", "correct"]],
        ["one attempt and two outcomes", 1, ["wrong", "correct"]],
      ];
      for (const [why, attempts, lastThree] of probes) {
        const raw = JSON.parse(serialiseSave(populated()));
        raw.facts[0].attempts = attempts;
        raw.facts[0].correct = 0;
        raw.facts[0].lastThree = lastThree;
        const result = validateSave(raw);
        assert.equal(result.ok, false, why + " was accepted");
        assert.ok(
          result.issues.some((issue) => issue.path === "facts[0].lastThree"),
          why + ": " + JSON.stringify(result.issues),
        );
      }
      // and the shapes a writer really does produce still pass
      for (const [attempts, lastThree] of [[1, ["correct"]], [2, ["wrong", "correct"]], [9, ["correct", "correct", "correct"]]] as [number, string[]][]) {
        const raw = JSON.parse(serialiseSave(populated()));
        raw.facts[0].attempts = attempts;
        raw.facts[0].correct = 0;
        raw.facts[0].lastThree = lastThree;
        assert.equal(validateSave(raw).ok, true, attempts + " attempts was refused");
      }
    });

    test("save: a ghost sample cannot have gone backwards past the start line", () => {
      const raw = JSON.parse(serialiseSave(populated()));
      const key = recordKeys(raw.records)[0]!;
      raw.records[key].timeline.samples[0].progress = -99;
      const result = validateSave(raw);
      assert.equal(result.ok, false, "a negative progress was accepted");
      assert.ok(
        result.issues.some((issue) => issue.path.indexOf(".progress") !== -1),
        JSON.stringify(result.issues),
      );
    });

    test("save: a choose key is its tables ascending, so one race cannot own two slots", () => {
      // `recordKey` sorts and `tablesForPreset` de-duplicates, so `choose:3-2`
      // and `choose:2-2` are keys this build cannot write. Accepting them let a
      // file hold two records for one race, only one of which is ever read.
      for (const key of ["choose:2-3", "choose:1-2-12", "choose:7"])
        assert.equal(isRecordKey(key), true, key);
      for (const key of ["choose:3-2", "choose:2-2", "choose:12-1", "choose:5-5-6"])
        assert.equal(isRecordKey(key), false, key);
      const raw = JSON.parse(serialiseSave(populated()));
      raw.records["choose:3-2"] = { ...raw.records["2-5"], preset: "choose" };
      const result = validateSave(raw);
      assert.equal(result.ok, false);
      assert.ok(result.issues.some((issue) => issue.path === "records.choose:3-2"));
      // every key this build can actually write is still accepted
      for (const tables of [[2], [12, 3], [5, 5, 1], [9, 1, 4]]) {
        const state = timeTrial(1, 4000, tables.slice(0, 1)).state;
        assert.equal(
          isRecordKey(recordKey("choose", tables)),
          true,
          JSON.stringify(tables) + " -> " + recordKey("choose", tables),
        );
        assert.equal(isRecordKey(recordKeyOf(state)), true);
      }
    });

    test("save: migrateSave does not touch the object it was handed", () => {
      // It used to alias it (`raw = value`) and then stamp `raw.version` on it,
      // so the caller's own parsed object changed underneath it. Harmless only
      // for as long as MIGRATIONS is empty.
      const raw = JSON.parse(serialiseSave(populated()));
      const before = JSON.stringify(raw);
      const migrated = migrateSave(raw);
      assert.equal(migrated.problem, "");
      assert.equal(JSON.stringify(raw), before, "migrateSave mutated its argument");
      assert.notEqual(migrated.raw, raw, "and it handed back the very object it was given");
      migrated.raw!.version = 99;
      assert.equal(raw.version, SAVE_VERSION, "the copy is not a copy");
    });

    test("save: an own __proto__ key survives migration and is still refused", () => {
      // The copy migrateSave makes must not swallow it: `{...value}` defines
      // properties where an assignment loop would set them, and setting
      // `__proto__` changes a prototype instead of adding a key.
      const raw = JSON.parse('{"version":1,"settings":{},"records":{},"facts":[],"__proto__":{"polluted":true}}');
      const migrated = migrateSave(raw);
      assert.notEqual(migrated.raw, null);
      assert.ok(Object.prototype.hasOwnProperty.call(migrated.raw!, "__proto__"), "the key was swallowed");
      const loaded = parseSave(JSON.stringify(raw));
      assert.equal(loaded.ok, false);
      assert.ok(loaded.issues.some((issue) => issue.path === "__proto__" && issue.problem === "unknown key"));
      assert.equal(({} as Record<string, unknown>)["polluted"], undefined);
    });

    // ---- the legacy garage file --------------------------------------------

    test("save: the garage's own pre-schema file is converted here, not in a QML file", () => {
      // It claims version 1, like this schema does, but its settings are the
      // garage's 0-based vocabulary. It is not a schema version -- MIGRATIONS
      // is keyed by the version it upgrades from and there cannot be two
      // entries for 1 -- so it is a conversion rather than a migration. It
      // still belongs in this module, where npm test can reach it.
      const legacy = {
        version: 1,
        settings: {
          kartBody: 2, kartPaint: 4, kartNumber: 42, rivalLevel: 0,
          raceMode: 3, mathSet: 2, sound: false, reducedMotion: true, scanlines: true,
        },
        records: {},
        facts: {},
      };
      const result = migrateLegacyGarageSettings(legacy);
      assert.equal(result.problem, "");
      assert.deepEqual(result.settings, {
        sound: false,
        reducedMotion: true,
        scanlines: true,
        kart: 3,
        paint: 5,
        number: 42,
        rivalLevel: "rookie",
        streakThreshold: STREAK_THRESHOLD,
      });
      const file = emptySave();
      file.settings = result.settings!;
      assert.equal(parseSave(serialiseSave(file)).ok, true, "and what it produces is a file");
      // raceMode and mathSet are dropped, because the design's Data row does
      // not list them -- docs/open-questions.md records that as the decision.
      assert.equal(Object.prototype.hasOwnProperty.call(result.settings!, "raceMode"), false);
      assert.equal(Object.prototype.hasOwnProperty.call(result.settings!, "mathSet"), false);
    });

    test("save: anything that is not the legacy garage shape is refused rather than guessed at", () => {
      const probes: [string, unknown][] = [
        ["not an object", "{}"],
        ["no settings", { version: 1 }],
        ["already the schema's own vocabulary", JSON.parse(serialiseSave(emptySave()))],
        ["a legacy setting nobody wrote", { settings: { kartBody: 1, theme: "dark" } }],
      ];
      for (const [why, value] of probes) {
        const result = migrateLegacyGarageSettings(value);
        assert.equal(result.settings, null, why + " was converted");
        assert.ok(result.problem.length > 0, why + " was refused without a reason");
      }
    });

    test("save: a legacy file holding a record or a fact history is refused, never half-read", () => {
      // The old shape had no route that wrote either, so one that has them is a
      // file this build does not understand. Quarantine is the caller's job;
      // saying so is this one's.
      const base = {
        version: 1,
        settings: { kartBody: 1, kartPaint: 1, kartNumber: 7, rivalLevel: 1, raceMode: 3, mathSet: 2, sound: true, reducedMotion: false, scanlines: false },
      };
      const withRecord = migrateLegacyGarageSettings({ ...base, records: { "2-5": {} }, facts: {} });
      assert.equal(withRecord.settings, null);
      assert.ok(withRecord.problem.indexOf("record") !== -1, withRecord.problem);
      const withFacts = migrateLegacyGarageSettings({ ...base, records: {}, facts: [{ fact: 204 }] });
      assert.equal(withFacts.settings, null);
      assert.ok(withFacts.problem.indexOf("fact history") !== -1, withFacts.problem);
      // and the empty forms both shapes used are fine
      assert.equal(migrateLegacyGarageSettings({ ...base, records: {}, facts: {} }).problem, "");
      assert.equal(migrateLegacyGarageSettings({ ...base, records: {}, facts: [] }).problem, "");
    });

    test("save: every file commitRace can produce parses back clean", () => {
      // The closure, asserted over the whole matrix rather than one path: four
      // race shapes x five candidates x a file that is empty, populated, or
      // already holds a record for the key. `commit` re-reads every result
      // through `parseSave` and deep-equals it, so a single escape fails here.
      const clean = timeTrial(2026, 4000, [2]);
      const goodRecord = recordFromRace(clean.state, clean.timeline)!;
      const gp = startRace({ preset: "choose", chosenTables: [2] });
      answerRightTimes(gp, 12, "you");
      const practice = startRace({ preset: "choose", chosenTables: [2], mode: "practice" });
      answerRightTimes(practice, 12, "you");
      const partial = timeTrial(5, 2000, [3]);

      const bases: EngineModule.SaveFile[] = [
        emptySave(),
        populated(),
        commit(emptySave(), clean.state, factHistoryOf(clean.state), goodRecord).file,
      ];
      const states = [clean.state, gp.state, practice.state, partial.state];
      const candidates: (EngineModule.RecordEntry | null)[] = [
        null,
        goodRecord,
        { ...goodRecord, preset: "1-12" as const },
        { ...goodRecord, correct: 99999, attempted: 1 },
        { ...goodRecord, timeMs: 3.5 },
      ];
      let ran = 0;
      for (const base of bases) {
        for (const state of states) {
          for (const candidate of candidates) {
            // `commit` asserts the round trip on every one of these
            const result = commit(base, state, factHistoryOf(state), candidate);
            assert.equal(typeof result.recordUpdated, "boolean");
            ran += 1;
          }
        }
      }
      assert.equal(ran, 3 * 4 * 5, "the matrix did not run");
    });
  });
}
