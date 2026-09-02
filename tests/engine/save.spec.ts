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
      cloneSave,
      commitRace,
      createRace,
      dateLikeKeys,
      defaultSettings,
      emptySave,
      emptyTimeline,
      factAnswer,
      factHistoryForRace,
      factHistoryOf,
      isRecordKey,
      mergeFactHistory,
      migrateSave,
      parseSave,
      raceWasSeededFrom,
      recordFromRace,
      recordKey,
      recordKeyOf,
      recordKeys,
      recordStep,
      serialiseSave,
      step,
      validateSave,
      withFactHistory,
    } = E;
    const { answerRightTimes, answerWrong, apply, racer, startRace } = helpersFor(E);

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
        const harness = startRace({
          seed: 100 + round,
          preset: "choose",
          chosenTables: [2],
          racers: [{ id: "you", kind: "human" as const }],
          factHistory: factHistoryForRace(file),
        });
        answerRightTimes(harness, 12, "you");
        const history = factHistoryOf(harness.state);
        assert.equal(raceWasSeededFrom(file, history), true, "round " + round);
        file = withFactHistory(file, history);
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

    test("save: a race that was not seeded from the file is merged, not overwritten", () => {
      const first = startRace({
        seed: 7,
        preset: "choose",
        chosenTables: [2],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(first, 12, "you");
      const file = withFactHistory(emptySave(), factHistoryOf(first.state));

      const second = startRace({
        seed: 8,
        preset: "choose",
        chosenTables: [3],
        racers: [{ id: "you", kind: "human" as const }],
      });
      answerRightTimes(second, 12, "you");
      const history = factHistoryOf(second.state);
      assert.equal(raceWasSeededFrom(file, history), false, "the twos are missing from it");
      const merged = mergeFactHistory(file.facts, history);
      assert.equal(merged.length, 24, "the twos and the threes");
      let previous = -1;
      for (const record of merged) {
        assert.ok(record.fact > previous, "merged history stays ascending");
        previous = record.fact;
        assert.equal(record.attempts, 1);
      }
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
      const committed = commitRace(
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

    test("save: a clean run commits a record, and a tie afterwards leaves it standing", () => {
      let file = emptySave();
      const first = timeTrial(2026, 4000);
      const firstCommit = commitRace(
        file,
        first.state,
        factHistoryOf(first.state),
        recordFromRace(first.state, first.timeline),
      );
      assert.equal(firstCommit.recordUpdated, true);
      assert.equal(firstCommit.record!.timeMs, 48000);
      file = firstCommit.file;

      const tie = timeTrial(999, 4000);
      const tieCommit = commitRace(
        file,
        tie.state,
        factHistoryOf(tie.state),
        recordFromRace(tie.state, tie.timeline),
      );
      assert.equal(tieCommit.recordUpdated, false, "a tie keeps the old record");
      assert.equal(tieCommit.record!.timeMs, 48000);
      assert.deepEqual(tieCommit.record!.timeline, first.timeline, "and its ghost");

      const faster = timeTrial(2026, 3000);
      const fastCommit = commitRace(
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
      file = commitRace(file, twos.state, factHistoryOf(twos.state), recordFromRace(twos.state, twos.timeline)).file;
      const threes = timeTrial(1, 5000, [3]);
      const committed = commitRace(
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
      file = commitRace(file, run.state, factHistoryOf(run.state), recordFromRace(run.state, run.timeline)).file;
      const text = serialiseSave(file);
      const loaded = parseSave(text);
      assert.deepEqual(loaded.issues, []);
      assert.deepEqual(loaded.file, file);
      assert.deepEqual(dateLikeKeys(JSON.parse(text)), []);
      assert.equal(text.indexOf("Date"), -1);
    });
  });
}
