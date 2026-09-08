/**
 * The save file.
 *
 * Design, Data: "One JSON file in the plugin's own data directory" with exactly
 * three keys -- `settings`, `records`, `facts` -- and "No dates, no session
 * counts, no Grand Prix history, no streak history. Human-readable, so a parent
 * can see exactly what is kept."
 *
 * This module is the schema and nothing else. It opens no file, knows no path
 * and holds no clock: it turns a `SaveFile` into text and text back into a
 * `SaveFile`, says exactly what is wrong with a file it will not accept, and
 * carries the fact history in and out of a race. The layer 3 store is what
 * touches the disk.
 *
 * Two rules this file exists to keep:
 *
 *   - **Unknown keys are rejected.** Not ignored, not dropped: rejected, with
 *     the path of the key that was not recognised. A save file that quietly
 *     accepts a field it does not understand is how a date gets stored.
 *   - **There are no dates.** Every number in here is a count or a duration
 *     measured from the start of its own race. `dateLikeKeys` walks a parsed
 *     file and names any key that reads like a moment in the calendar, so the
 *     rule is checkable and not merely promised.
 */

import { PRESET_TABLES, TABLE_MAX, TABLE_MIN, type PresetId } from "./deck.ts";
import {
  beatsRecord,
  cloneRecord,
  cloneTimeline,
  isRecordEligible,
  type RecordEntry,
} from "./ghost.ts";
import {
  FACT_HISTORY_WINDOW,
  cloneFactHistory,
  factRecordOf,
  type FactRecord,
} from "./history.ts";
import type { RaceState } from "./race.ts";
import { RIVAL_LEVEL_ORDER, type RivalLevel } from "./rivals.ts";
import { STREAK_THRESHOLD } from "./streak.ts";

/** The version this build writes. A file with any other version is migrated. */
export const SAVE_VERSION = 1;

// ---------------------------------------------------------------------------
// the shape
// ---------------------------------------------------------------------------

/**
 * Design, Data, `settings`: "sound, reduced motion, scanlines, kart, paint,
 * number, rival level, streak threshold if exposed."
 *
 * Kart, paint and number are counted from one, the way the garage shows them:
 * six bodies, eight paints, and the settled "Kart number range -- 1 to 99."
 */
export interface SaveSettings {
  sound: boolean;
  reducedMotion: boolean;
  scanlines: boolean;
  /** 1..6, the six original kart bodies. */
  kart: number;
  /** 1..8, the eight paint swatches. */
  paint: number;
  /** 1..99. */
  number: number;
  rivalLevel: RivalLevel;
  /** Design, Decisions: 12. Present because the design allows exposing it. */
  streakThreshold: number;
}

/**
 * Design, Data, `records`: "per preset: best clean time, correct, attempted,
 * answer timeline for the ghost." Keyed by `recordKey`, so the three fixed
 * presets are one slot each and a `Choose tables` run is one slot per subset --
 * "per preset" cannot mean one shared slot for every subset a child can build,
 * because two subsets are two different races.
 */
export type SaveRecords = Record<string, RecordEntry>;

export interface SaveFile {
  version: number;
  settings: SaveSettings;
  records: SaveRecords;
  /** Design, Data, `facts`: "per fact: attempts, correct, last three outcomes." */
  facts: FactRecord[];
}

export const KART_BODIES = 6;
export const PAINT_SWATCHES = 8;
export const KART_NUMBER_MIN = 1;
export const KART_NUMBER_MAX = 99;

/**
 * The range a saved streak threshold may take.
 *
 * Design, Decisions: "Streak threshold: **12.** ... The bellringer's 15 stays
 * in the test vectors as a parity case", and the Data row lists "streak
 * threshold if exposed" among the settings. So a file may legitimately carry
 * something other than this build's `STREAK_THRESHOLD`, and anything that
 * reads a file has to carry that value back out again rather than substituting
 * its own. One is the smallest threshold that means anything; 144 is twelve lap
 * decks of twelve, past which no lap could charge a hand.
 */
export const STREAK_THRESHOLD_MIN = 1;
export const STREAK_THRESHOLD_MAX = 144;

export function defaultSettings(): SaveSettings {
  return {
    sound: true,
    reducedMotion: false,
    scanlines: false,
    kart: 1,
    paint: 1,
    number: 1,
    rivalLevel: "pro",
    streakThreshold: STREAK_THRESHOLD,
  };
}

export function emptySave(): SaveFile {
  return { version: SAVE_VERSION, settings: defaultSettings(), records: {}, facts: [] };
}

export function cloneSettings(settings: SaveSettings): SaveSettings {
  return {
    sound: settings.sound,
    reducedMotion: settings.reducedMotion,
    scanlines: settings.scanlines,
    kart: settings.kart,
    paint: settings.paint,
    number: settings.number,
    rivalLevel: settings.rivalLevel,
    streakThreshold: settings.streakThreshold,
  };
}

export function cloneSave(file: SaveFile): SaveFile {
  const records: SaveRecords = {};
  for (const key of recordKeys(file.records)) {
    const record = file.records[key]!;
    records[key] = {
      preset: record.preset,
      timeMs: record.timeMs,
      correct: record.correct,
      attempted: record.attempted,
      timeline: cloneTimeline(record.timeline),
    };
  }
  return {
    version: file.version,
    settings: cloneSettings(file.settings),
    records,
    facts: cloneFactHistory(file.facts),
  };
}

/** Record keys, always ascending, so a written file never depends on insertion order. */
export function recordKeys(records: SaveRecords): string[] {
  const keys: string[] = [];
  for (const key in records) {
    if (Object.prototype.hasOwnProperty.call(records, key)) keys.push(key);
  }
  keys.sort();
  return keys;
}

/**
 * The slot a race's record belongs in. The three fixed presets are their own
 * key; a `Choose tables` race is keyed by the tables it chose, ascending.
 */
export function recordKey(preset: PresetId, tables: readonly number[]): string {
  if (preset !== "choose") return preset;
  const sorted = tables.slice().sort((left, right) => left - right);
  // Ascending *and* de-duplicated, the same two normalisations `tablesForPreset`
  // makes before a race ever sees its tables. Sorting alone left `recordKey`
  // able to build a key `isRecordKey` refuses -- `[5, 5, 1]` gave
  // `choose:1-5-5` -- so the writer and the validator disagreed about what a
  // key is.
  const unique: number[] = [];
  for (const table of sorted) if (unique.indexOf(table) === -1) unique.push(table);
  return "choose:" + unique.join("-");
}

export function recordKeyOf(state: RaceState): string {
  return recordKey(state.preset, state.tables);
}

const FIXED_PRESETS: readonly string[] = ["2-5", "2-10", "1-12"];
const CHOOSE_KEY = /^choose:(?:[1-9]|1[0-2])(?:-(?:[1-9]|1[0-2]))*$/;

/**
 * A `choose:` key is the tables it chose, **strictly ascending**, and that is
 * not decoration: `recordKey` sorts and `tablesForPreset` de-duplicates, so
 * `choose:3-2` and `choose:2-2` are keys this build cannot write. Accepting
 * them would let one race own two slots in the file -- a child's best time
 * filed under `choose:2-3` and another under `choose:3-2`, with only one of
 * them ever consulted again. Strict ascent rejects both the unsorted key and
 * the duplicated table in one rule.
 */
export function isRecordKey(key: string): boolean {
  if (FIXED_PRESETS.indexOf(key) !== -1) return true;
  if (!CHOOSE_KEY.test(key)) return false;
  let previous = 0;
  for (const part of key.slice("choose:".length).split("-")) {
    const table = Number(part);
    if (!(table > previous)) return false;
    previous = table;
  }
  return true;
}

// ---------------------------------------------------------------------------
// no dates
// ---------------------------------------------------------------------------

/**
 * Words a key may not contain. Design, Data: "No dates, no session counts, no
 * Grand Prix history, no streak history."
 *
 * `time` and `at` are deliberately absent: `timeMs` is how long a lap took and
 * `atMs` is how far into a race an answer landed. Both are durations from the
 * start of a race and neither can be turned back into a moment in the calendar.
 */
export const FORBIDDEN_KEY_WORDS: readonly string[] = [
  "date", "dates", "day", "days", "week", "weeks", "month", "months", "year", "years",
  "calendar", "timestamp", "epoch", "iso", "utc", "clock", "created", "updated", "modified",
  "played", "session", "sessions", "streakhistory", "history", "birthday", "today",
  "yesterday", "since", "when", "seen", "visit", "visits",
];

/** Split a camelCase or snake_case key into lowercase words. */
function keyWords(key: string): string[] {
  const spaced = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_\-.:]+/g, " ");
  const words: string[] = [];
  for (const word of spaced.split(" ")) if (word.length > 0) words.push(word.toLowerCase());
  return words;
}

/**
 * Every key anywhere in a parsed save file whose name reads like a moment in
 * the calendar. Empty is the only acceptable answer, and a test asserts it
 * against a fully populated file rather than an empty one.
 */
export function dateLikeKeys(value: unknown, path = ""): string[] {
  const found: string[] = [];
  if (value === null || typeof value !== "object") return found;
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index++) {
      for (const hit of dateLikeKeys(value[index], path + "[" + index + "]")) found.push(hit);
    }
    return found;
  }
  const record = value as Record<string, unknown>;
  for (const key in record) {
    if (!Object.prototype.hasOwnProperty.call(record, key)) continue;
    const here = path === "" ? key : path + "." + key;
    for (const word of keyWords(key)) {
      if (FORBIDDEN_KEY_WORDS.indexOf(word) !== -1) {
        found.push(here);
        break;
      }
    }
    for (const hit of dateLikeKeys(record[key], here)) found.push(hit);
  }
  return found;
}

// ---------------------------------------------------------------------------
// validation
// ---------------------------------------------------------------------------

export interface SaveIssue {
  /** Where in the file, in dotted form: `settings.kart`, `facts[3].lastThree`. */
  path: string;
  problem: string;
}

export interface SaveValidation {
  ok: boolean;
  issues: SaveIssue[];
  /** The accepted file, or null when there is any issue at all. */
  file: SaveFile | null;
}

const SETTINGS_KEYS: readonly string[] = [
  "sound", "reducedMotion", "scanlines", "kart", "paint", "number", "rivalLevel", "streakThreshold",
];
const FILE_KEYS: readonly string[] = ["version", "settings", "records", "facts"];
const RECORD_KEYS: readonly string[] = ["preset", "timeMs", "correct", "attempted", "timeline"];
const TIMELINE_KEYS: readonly string[] = ["samples"];
const SAMPLE_KEYS: readonly string[] = ["atMs", "progress"];
const FACT_KEYS: readonly string[] = ["fact", "attempts", "correct", "lastThree"];
const OUTCOMES: readonly string[] = ["correct", "wrong", "reveal", "pitCrew"];

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isWholeNumber(value: unknown): value is number {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value;
}

function unknownKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
  path: string,
  issues: SaveIssue[],
): void {
  for (const key in value) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
    if (allowed.indexOf(key) === -1)
      issues.push({ path: path === "" ? key : path + "." + key, problem: "unknown key" });
  }
  for (const key of allowed) {
    if (!Object.prototype.hasOwnProperty.call(value, key))
      issues.push({ path: path === "" ? key : path + "." + key, problem: "missing key" });
  }
}

function checkRange(
  value: unknown,
  low: number,
  high: number,
  path: string,
  issues: SaveIssue[],
): void {
  if (!isWholeNumber(value)) {
    issues.push({ path, problem: "expected a whole number" });
    return;
  }
  if (value < low || value > high)
    issues.push({ path, problem: "expected " + low + ".." + high + ", got " + value });
}

function checkBoolean(value: unknown, path: string, issues: SaveIssue[]): void {
  if (typeof value !== "boolean") issues.push({ path, problem: "expected a boolean" });
}

function validateSettings(value: unknown, issues: SaveIssue[]): void {
  if (!isPlainObject(value)) {
    issues.push({ path: "settings", problem: "expected an object" });
    return;
  }
  unknownKeys(value, SETTINGS_KEYS, "settings", issues);
  checkBoolean(value.sound, "settings.sound", issues);
  checkBoolean(value.reducedMotion, "settings.reducedMotion", issues);
  checkBoolean(value.scanlines, "settings.scanlines", issues);
  checkRange(value.kart, 1, KART_BODIES, "settings.kart", issues);
  checkRange(value.paint, 1, PAINT_SWATCHES, "settings.paint", issues);
  checkRange(value.number, KART_NUMBER_MIN, KART_NUMBER_MAX, "settings.number", issues);
  if (typeof value.rivalLevel !== "string" || RIVAL_LEVEL_ORDER.indexOf(value.rivalLevel as RivalLevel) === -1)
    issues.push({ path: "settings.rivalLevel", problem: "expected rookie, pro or champion" });
  checkRange(
    value.streakThreshold,
    STREAK_THRESHOLD_MIN,
    STREAK_THRESHOLD_MAX,
    "settings.streakThreshold",
    issues,
  );
}

function validateTimeline(value: unknown, path: string, issues: SaveIssue[]): void {
  if (!isPlainObject(value)) {
    issues.push({ path, problem: "expected an object" });
    return;
  }
  unknownKeys(value, TIMELINE_KEYS, path, issues);
  const samples = value.samples;
  if (!Array.isArray(samples)) {
    issues.push({ path: path + ".samples", problem: "expected an array" });
    return;
  }
  let previous = -1;
  for (let index = 0; index < samples.length; index++) {
    const at = path + ".samples[" + index + "]";
    const sample = samples[index];
    if (!isPlainObject(sample)) {
      issues.push({ path: at, problem: "expected an object" });
      continue;
    }
    unknownKeys(sample, SAMPLE_KEYS, at, issues);
    checkRange(sample.atMs, 0, 86400000, at + ".atMs", issues);
    // Progress is `laps x 12 + correct - (need - 12)` (ghost.ts). A record can
    // only come from a card-free run, so `need` is always 12 and progress is
    // the count of answers behind the kart: never negative. A negative one is
    // an internally impossible state, and impossible states are rejected here
    // rather than left for a track view to divide by.
    checkRange(sample.progress, 0, 100000, at + ".progress", issues);
    if (isWholeNumber(sample.atMs)) {
      if (sample.atMs < previous)
        issues.push({ path: at + ".atMs", problem: "timeline runs backwards" });
      previous = sample.atMs;
    }
  }
}

function validateRecords(value: unknown, issues: SaveIssue[]): void {
  if (!isPlainObject(value)) {
    issues.push({ path: "records", problem: "expected an object" });
    return;
  }
  for (const key in value) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
    const at = "records." + key;
    if (!isRecordKey(key)) {
      issues.push({ path: at, problem: "unknown key" });
      continue;
    }
    const record = value[key];
    if (!isPlainObject(record)) {
      issues.push({ path: at, problem: "expected an object" });
      continue;
    }
    unknownKeys(record, RECORD_KEYS, at, issues);
    const preset = record.preset;
    const presetOk =
      typeof preset === "string"
      && (Object.prototype.hasOwnProperty.call(PRESET_TABLES, preset) || preset === "choose");
    if (!presetOk) issues.push({ path: at + ".preset", problem: "not a preset" });
    else if (recordKeyMatchesPreset(key, preset as PresetId) === false)
      issues.push({ path: at + ".preset", problem: "does not match the key it is filed under" });
    checkRange(record.timeMs, 0, 86400000, at + ".timeMs", issues);
    checkRange(record.correct, 0, 100000, at + ".correct", issues);
    checkRange(record.attempted, 0, 100000, at + ".attempted", issues);
    if (isWholeNumber(record.correct) && isWholeNumber(record.attempted) && record.correct > record.attempted)
      issues.push({ path: at + ".correct", problem: "more correct than attempted" });
    validateTimeline(record.timeline, at + ".timeline", issues);
  }
}

function recordKeyMatchesPreset(key: string, preset: PresetId): boolean {
  if (preset === "choose") return key.indexOf("choose:") === 0;
  return key === preset;
}

function validateFacts(value: unknown, issues: SaveIssue[]): void {
  if (!Array.isArray(value)) {
    issues.push({ path: "facts", problem: "expected an array" });
    return;
  }
  let previous = -1;
  for (let index = 0; index < value.length; index++) {
    const at = "facts[" + index + "]";
    const record = value[index];
    if (!isPlainObject(record)) {
      issues.push({ path: at, problem: "expected an object" });
      continue;
    }
    unknownKeys(record, FACT_KEYS, at, issues);
    const fact = record.fact;
    if (!isWholeNumber(fact)) issues.push({ path: at + ".fact", problem: "expected a whole number" });
    else {
      const left = Math.floor(fact / 100);
      const right = fact % 100;
      if (left < TABLE_MIN || left > TABLE_MAX || right < 1 || right > 12)
        issues.push({ path: at + ".fact", problem: "not a fact in 1x1..12x12" });
      if (fact <= previous) issues.push({ path: at + ".fact", problem: "facts must ascend" });
      previous = fact;
    }
    checkRange(record.attempts, 0, 100000, at + ".attempts", issues);
    checkRange(record.correct, 0, 100000, at + ".correct", issues);
    if (isWholeNumber(record.attempts) && isWholeNumber(record.correct) && record.correct > record.attempts)
      issues.push({ path: at + ".correct", problem: "more correct than attempts" });
    const lastThree = record.lastThree;
    if (!Array.isArray(lastThree)) {
      issues.push({ path: at + ".lastThree", problem: "expected an array" });
      continue;
    }
    if (lastThree.length > FACT_HISTORY_WINDOW)
      issues.push({ path: at + ".lastThree", problem: "more than " + FACT_HISTORY_WINDOW + " outcomes" });
    // `recordFactOutcome` pushes exactly one outcome for every attempt and
    // trims to three, and `factHistoryDelta` and `mergeFactHistory` both keep
    // that. So the window is not merely "at most three": it holds
    // `min(attempts, 3)` outcomes, always. `attempts: 500, lastThree: []` and
    // `attempts: 0, lastThree: [correct, correct, correct]` are both states no
    // writer can reach, and both were accepted before this rule.
    else if (isWholeNumber(record.attempts)) {
      const expected = record.attempts < FACT_HISTORY_WINDOW ? record.attempts : FACT_HISTORY_WINDOW;
      if (lastThree.length !== expected)
        issues.push({
          path: at + ".lastThree",
          problem: "expected " + expected + " outcomes for " + record.attempts
            + " attempts, got " + lastThree.length,
        });
    }
    for (let slot = 0; slot < lastThree.length; slot++) {
      if (typeof lastThree[slot] !== "string" || OUTCOMES.indexOf(lastThree[slot] as string) === -1)
        issues.push({ path: at + ".lastThree[" + slot + "]", problem: "not an outcome" });
    }
  }
}

/**
 * Accept or reject, with the reason. Nothing is coerced and nothing is
 * silently dropped: a file with one unknown key is rejected whole, and the
 * caller decides whether to start from `emptySave()` or to ask.
 */
export function validateSave(value: unknown): SaveValidation {
  const issues: SaveIssue[] = [];
  if (!isPlainObject(value)) {
    return { ok: false, issues: [{ path: "", problem: "expected an object" }], file: null };
  }
  unknownKeys(value, FILE_KEYS, "", issues);
  if (value.version !== SAVE_VERSION)
    issues.push({
      path: "version",
      problem: "expected " + SAVE_VERSION + ", got " + JSON.stringify(value.version),
    });
  validateSettings(value.settings, issues);
  validateRecords(value.records, issues);
  validateFacts(value.facts, issues);
  for (const key of dateLikeKeys(value)) issues.push({ path: key, problem: "date-like key" });
  if (issues.length > 0) return { ok: false, issues, file: null };
  return { ok: true, issues, file: cloneSave(value as unknown as SaveFile) };
}

// ---------------------------------------------------------------------------
// migration
// ---------------------------------------------------------------------------

export type Migration = (raw: Record<string, unknown>) => Record<string, unknown>;

/**
 * One entry per version that has ever been written, keyed by the version it
 * upgrades *from*. Version 1 is the first, so the table is empty and that is
 * the whole of the stub: the mechanism exists, has a test, and is the only
 * place a version 2 will need to touch.
 */
export const MIGRATIONS: Readonly<Record<string, Migration | undefined>> = {};

export interface MigrationResult {
  raw: Record<string, unknown> | null;
  /** The version the file arrived at. */
  from: number;
  to: number;
  /** The versions the run migrated through, in order. */
  steps: number[];
  problem: string;
}

/**
 * Bring a parsed file up to `SAVE_VERSION`, or say why it cannot be. A file
 * from the future is never guessed at: a newer build wrote it and this one has
 * no idea what it means.
 *
 * The object handed in is never modified. The old code aliased it (`raw =
 * value`) and then stamped `raw.version = at` on it, so the caller's own parsed
 * object changed under it; harmless only for as long as `MIGRATIONS` is empty.
 * The spread is deliberate rather than `Object.assign`: object spread *defines*
 * properties, so an own `__proto__` that arrived from `JSON.parse` survives as
 * an own key and is still rejected downstream as an unknown one.
 */
export function migrateSave(value: unknown): MigrationResult {
  if (!isPlainObject(value))
    return { raw: null, from: 0, to: SAVE_VERSION, steps: [], problem: "not an object" };
  const version = value.version;
  if (!isWholeNumber(version) || version < 1)
    return { raw: null, from: 0, to: SAVE_VERSION, steps: [], problem: "no usable version" };
  if (version > SAVE_VERSION)
    return {
      raw: null,
      from: version,
      to: SAVE_VERSION,
      steps: [],
      problem: "written by a newer build (version " + version + ")",
    };
  let raw: Record<string, unknown> = { ...value };
  const steps: number[] = [];
  let at = version;
  while (at < SAVE_VERSION) {
    const migration = MIGRATIONS[String(at)];
    if (migration === undefined)
      return { raw: null, from: version, to: SAVE_VERSION, steps, problem: "no migration from version " + at };
    raw = migration(raw);
    steps.push(at);
    at += 1;
    raw.version = at;
  }
  return { raw, from: version, to: SAVE_VERSION, steps, problem: "" };
}

/** The garage's own 0-based vocabulary, as the first `ui/Store.qml` wrote it. */
const LEGACY_GARAGE_KEYS: readonly string[] = [
  "kartBody", "kartPaint", "kartNumber", "rivalLevel", "raceMode", "mathSet",
  "sound", "reducedMotion", "scanlines",
];

export interface LegacyGarageResult {
  /** The settings the legacy file meant, or null when there are none to take. */
  settings: SaveSettings | null;
  /** Empty when `settings` is filled in; otherwise why it is not. */
  problem: string;
}

/**
 * The one file shape that is not a version of this schema and still has to be
 * read: what the first `ui/Store.qml` wrote before the schema existed.
 *
 * It claims `version: 1`, like this schema does, but its `settings` are the
 * garage's own vocabulary -- `kartBody`, `kartPaint`, `kartNumber` counted from
 * zero, `rivalLevel` as an index, plus `raceMode` and `mathSet`, which the
 * design's Data row does not list -- and its `facts` is an object rather than
 * an array. It is not a schema version, so it cannot go in `MIGRATIONS`, which
 * is keyed by the version it upgrades *from* and would need two different
 * entries for the number 1. But it is still file-format knowledge, so it lives
 * here, in the module whose docstring says it is the schema, where `npm test`
 * can reach it -- and not in a QML file nothing in `npm test` can load.
 *
 * It converts settings and nothing else, because the old shape had no route
 * that ever wrote a record or a fact outcome. If one turns up anyway, this
 * refuses rather than dropping it: a file holding something this build cannot
 * read is a file to quarantine, not to silently rewrite.
 */
export function migrateLegacyGarageSettings(value: unknown): LegacyGarageResult {
  if (!isPlainObject(value)) return { settings: null, problem: "not an object" };
  const settings = value.settings;
  if (!isPlainObject(settings)) return { settings: null, problem: "no settings object" };
  if (!Object.prototype.hasOwnProperty.call(settings, "kartBody"))
    return { settings: null, problem: "not the garage's own settings shape" };
  for (const key in settings) {
    if (!Object.prototype.hasOwnProperty.call(settings, key)) continue;
    if (LEGACY_GARAGE_KEYS.indexOf(key) === -1)
      return { settings: null, problem: "unknown legacy setting: " + key };
  }
  const records = value.records;
  if (records !== undefined && (!isPlainObject(records) || Object.keys(records).length > 0))
    return { settings: null, problem: "the legacy shape never held a record, and this one does" };
  const facts = value.facts;
  const factsEmpty =
    facts === undefined
    || (Array.isArray(facts) && facts.length === 0)
    || (isPlainObject(facts) && Object.keys(facts).length === 0);
  if (!factsEmpty)
    return { settings: null, problem: "the legacy shape never held a fact history, and this one does" };

  const level = RIVAL_LEVEL_ORDER[clampWhole(settings.rivalLevel, 0, RIVAL_LEVEL_ORDER.length - 1, 1)]!;
  return {
    settings: {
      sound: settings.sound !== false,
      reducedMotion: settings.reducedMotion === true,
      scanlines: settings.scanlines === true,
      kart: clampWhole(toNumber(settings.kartBody) + 1, 1, KART_BODIES, 1),
      paint: clampWhole(toNumber(settings.kartPaint) + 1, 1, PAINT_SWATCHES, 1),
      number: clampWhole(settings.kartNumber, KART_NUMBER_MIN, KART_NUMBER_MAX, 1),
      rivalLevel: level,
      streakThreshold: STREAK_THRESHOLD,
    },
    problem: "",
  };
}

function toNumber(value: unknown): number {
  return typeof value === "number" && isFinite(value) ? value : NaN;
}

function clampWhole(value: unknown, low: number, high: number, fallback: number): number {
  const number = Math.round(toNumber(value));
  if (!isFinite(number)) return fallback;
  return number < low ? low : number > high ? high : number;
}

// ---------------------------------------------------------------------------
// resetting
// ---------------------------------------------------------------------------

/**
 * Design, Data, the "Reset by" column: `settings` is reset by Settings,
 * `records` by "Reset garage records", `facts` by "Reset fact history".
 *
 * Three operations, one per key, and each one touches exactly its own key. That
 * separation is the whole point of the column: a child who wants a clean
 * leaderboard must not lose the mastery the fact history holds, and a parent
 * clearing the fact history must not reset the kart. None of these mutates the
 * file it is given.
 */
export function resetSettings(file: SaveFile): SaveFile {
  const next = cloneSave(file);
  next.settings = defaultSettings();
  return next;
}

export function resetRecords(file: SaveFile): SaveFile {
  const next = cloneSave(file);
  next.records = {};
  return next;
}

export function resetFacts(file: SaveFile): SaveFile {
  const next = cloneSave(file);
  next.facts = [];
  return next;
}

// ---------------------------------------------------------------------------
// round trip
// ---------------------------------------------------------------------------

/**
 * Write the file. Keys in a fixed order and two-space indentation, because the
 * design says "Human-readable, so a parent can see exactly what is kept", and
 * because a byte-identical write for identical data is what makes an atomic
 * save idempotent.
 */
export function serialiseSave(file: SaveFile): string {
  const settings = file.settings;
  const ordered = {
    version: file.version,
    settings: {
      sound: settings.sound,
      reducedMotion: settings.reducedMotion,
      scanlines: settings.scanlines,
      kart: settings.kart,
      paint: settings.paint,
      number: settings.number,
      rivalLevel: settings.rivalLevel,
      streakThreshold: settings.streakThreshold,
    },
    records: {} as Record<string, unknown>,
    facts: file.facts.map((record) => ({
      fact: record.fact,
      attempts: record.attempts,
      correct: record.correct,
      lastThree: record.lastThree.slice(),
    })),
  };
  for (const key of recordKeys(file.records)) {
    const record = file.records[key]!;
    ordered.records[key] = {
      preset: record.preset,
      timeMs: record.timeMs,
      correct: record.correct,
      attempted: record.attempted,
      timeline: {
        samples: record.timeline.samples.map((sample) => ({
          atMs: sample.atMs,
          progress: sample.progress,
        })),
      },
    };
  }
  return JSON.stringify(ordered, null, 2) + "\n";
}

export interface SaveLoad {
  ok: boolean;
  file: SaveFile | null;
  issues: SaveIssue[];
  migratedFrom: number;
}

/**
 * Read the file: parse, migrate, validate. Any failure returns `ok: false` with
 * the reason; the caller starts from `emptySave()` rather than being handed a
 * half-understood file.
 */
export function parseSave(text: string): SaveLoad {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (error) {
    return {
      ok: false,
      file: null,
      issues: [{ path: "", problem: "not JSON: " + String(error) }],
      migratedFrom: 0,
    };
  }
  const migrated = migrateSave(value);
  if (migrated.raw === null)
    return {
      ok: false,
      file: null,
      issues: [{ path: "version", problem: migrated.problem }],
      migratedFrom: migrated.from,
    };
  const validated = validateSave(migrated.raw);
  return {
    ok: validated.ok,
    file: validated.file,
    issues: validated.issues,
    migratedFrom: migrated.from,
  };
}

// ---------------------------------------------------------------------------
// the fact-history seam, closed
// ---------------------------------------------------------------------------

/**
 * The load half. Hand this to `RaceConfig.factHistory` and the race starts
 * knowing everything the child has answered before, which is what the design
 * means by "Deck generation is deterministic from the seed and the fact
 * history".
 */
export function factHistoryForRace(file: SaveFile): FactRecord[] {
  return cloneFactHistory(file.facts);
}

/**
 * The save half: what one race *added* to the history it was handed.
 *
 * `history` is `factHistoryOf(state)`. `seededWith` is exactly what the race
 * was created with -- the array `factHistoryForRace(file)` returned -- or null
 * when it was created with nothing (a vector replay, a fresh install, a race
 * started before the file loaded). This is arithmetic on two arrays and asks
 * no questions about a file; `factHistoryMergeIssues` is what decides whether a
 * given baseline may be believed, and it will only believe one that is the
 * file's own history, so a null baseline commits into an empty file and into no
 * other.
 *
 * This exists because the question it answers cannot be asked of the numbers.
 * The predicate it replaces, `raceWasSeededFrom`, tried to *infer* provenance
 * by comparing counts: it called a race "seeded from this file" whenever every
 * saved fact appeared in the incoming history with attempts and correct at
 * least as high. Unseeded histories satisfy that routinely -- a file holding
 * one clean race of the twos and a stranger that got every two wrong once
 * before getting it right look identical to it -- and the caller then took the
 * *replace* branch and wrote the stranger's counts over the child's, silently
 * destroying everything the file had earned.
 *
 * The real identity condition is not a property of the two histories. It is a
 * fact about where the race came from, and the only place that fact exists is
 * in the caller that started it. So the caller carries it, and the merge
 * becomes arithmetic: the file's counts plus this race's own, always, with no
 * branch left that can discard anything.
 *
 * `lastThree` is the tail of the history's window, cut to the number of
 * outcomes this race actually filed, so a race that asked a fact once
 * contributes one outcome rather than re-contributing the two it inherited.
 */
export function factHistoryDelta(
  seededWith: readonly FactRecord[] | null,
  history: readonly FactRecord[],
): FactRecord[] {
  const baseline = seededWith ?? [];
  const delta: FactRecord[] = [];
  for (const record of history) {
    const before = factRecordOf(baseline, record.fact);
    const attempts = record.attempts - (before === null ? 0 : before.attempts);
    const correct = record.correct - (before === null ? 0 : before.correct);
    if (attempts <= 0) continue;
    const window = record.lastThree;
    const kept = attempts >= window.length ? 0 : window.length - attempts;
    delta.push({
      fact: record.fact,
      attempts,
      correct: correct > 0 ? correct : 0,
      lastThree: window.slice(kept),
    });
  }
  return delta;
}

/** Whether two fact records carry the same window, outcome for outcome. */
function sameWindow(left: FactRecord, right: FactRecord): boolean {
  if (left.lastThree.length !== right.lastThree.length) return false;
  for (let slot = 0; slot < left.lastThree.length; slot++)
    if (left.lastThree[slot] !== right.lastThree[slot]) return false;
  return true;
}

/**
 * Whether the baseline the caller declared is this file's own fact history.
 *
 * `null` means "the race was seeded with nothing", so it matches a file whose
 * fact history is empty and nothing else. Equality is on the whole record --
 * fact, attempts, correct and the window -- because "the file I seeded from"
 * is a statement about the file as it stands, not about its totals.
 */
export function baselineIsFile(
  file: SaveFile,
  seededWith: readonly FactRecord[] | null,
): boolean {
  const baseline = seededWith ?? [];
  if (baseline.length !== file.facts.length) return false;
  for (let index = 0; index < baseline.length; index++) {
    const left = baseline[index]!;
    const right = file.facts[index]!;
    if (left.fact !== right.fact) return false;
    if (left.attempts !== right.attempts) return false;
    if (left.correct !== right.correct) return false;
    if (!sameWindow(left, right)) return false;
  }
  return true;
}

/**
 * Everything wrong with the per-fact arithmetic of a declared baseline, or
 * nothing.
 *
 * A race that was really seeded from `baseline` can only have *added* to it:
 * every fact the baseline knows is still in the race's history, with attempts
 * and correct no lower, and no fact can have come back with more correct
 * answers than attempts. A baseline that fails either test is not the array
 * this race was created with, whatever the caller says, and the failure is
 * named **per fact** rather than summed: `save.ts` used to compare one total
 * against `attemptCount`, so a baseline that understated one fact and
 * overstated another by the same amount passed with `issues: []` and wrote
 * per-fact counts that were wrong while the total was right. The design's Data
 * row is "fact history is kept locally **per fact**", so the check is too.
 *
 * The overstating half is the one that does damage: `factHistoryDelta` drops a
 * fact whose delta is not positive, so an overstated baseline silently loses
 * that fact's real answers. Here it is an issue with the fact's own path.
 */
export function factHistoryDeltaIssues(
  baseline: readonly FactRecord[],
  history: readonly FactRecord[],
): SaveIssue[] {
  const issues: SaveIssue[] = [];
  for (const before of baseline) {
    const after = factRecordOf(history, before.fact);
    const attempts = after === null ? 0 : after.attempts;
    const correct = after === null ? 0 : after.correct;
    if (attempts < before.attempts || correct < before.correct) {
      issues.push({
        path: "facts." + before.fact,
        problem:
          "the declared baseline does not account for this race's answers: it claims more of this"
          + " fact than the race's own history holds",
      });
      continue;
    }
    // A fact the race never asked cannot have moved. Its window is the one
    // place a zero delta can still hide a disagreement, because a delta of no
    // attempts is dropped rather than merged, and the file's window would then
    // stand where the race's belongs.
    if (after !== null && attempts === before.attempts && !sameWindow(before, after))
      issues.push({
        path: "facts." + before.fact,
        problem:
          "the declared baseline does not account for this race's answers: the race asked this"
          + " fact no times and its last outcomes still differ from the baseline's",
      });
  }
  for (const record of history) {
    const before = factRecordOf(baseline, record.fact);
    const attempts = record.attempts - (before === null ? 0 : before.attempts);
    const correct = record.correct - (before === null ? 0 : before.correct);
    if (attempts < 0) continue; // already named above
    if (correct > attempts)
      issues.push({
        path: "facts." + record.fact,
        problem:
          "the declared baseline does not account for this race's answers: more correct answers"
          + " than attempts for this fact",
      });
  }
  return issues;
}

/**
 * Everything wrong with folding this race into this file, or nothing.
 *
 * **The caller has to prove where the race came from. Nothing here guesses.**
 *
 * Three rounds of this function tried to recognise a race by its numbers --
 * first "every saved fact appears in the history with counts at least as high",
 * then nothing at all, then "the file's window ends with the delta's" -- and
 * each of the three had a hole worth a dozen of a child's answers. The last one
 * failed because a window is three outcomes long and *forgets*: once any later
 * commit pushed a race's outcomes out of the tail, that race became
 * re-committable in full, and because the predicate was all-or-nothing across
 * the delta, one mismatching fact re-admitted all twelve. 13 + 12 answers
 * became 38 with `issues: []`.
 *
 * So the guessing is gone. There is exactly one rule left and it is not about
 * content:
 *
 *   - **The declared baseline must be this file's fact history** as it stands
 *     right now (`baselineIsFile`). A `null` baseline says "seeded with
 *     nothing", which is true of a file whose history is empty and of no other.
 *     Anything else is refused: an unproved provenance is not a licence to
 *     inspect the counts and hope.
 *
 * That one rule closes the repeat commit *by construction* rather than by
 * recognising one. A successful commit changes the file, so the same race
 * offered a second time carries a baseline that is no longer the file and is
 * refused -- and if the caller honestly re-declares the new file as its
 * baseline, the delta is empty and the accounting below refuses it instead.
 * There is no window to decay, no all-or-nothing predicate, and nothing left
 * that a later commit can re-admit.
 *
 * On top of provenance, two arithmetic checks the baseline must survive:
 *
 *   - **Per fact** (`factHistoryDeltaIssues`): nothing may go backwards, and no
 *     fact may return more correct answers than attempts.
 *   - **In total**: `race.ts` files exactly one fact outcome for every answer it
 *     counts -- every `attemptCount += 1` is paired with one `fileOutcome`, on
 *     the correct, wrong, revealed and pit-crew paths alike -- so the delta must
 *     add up to the child's `attemptCount`.
 *
 * Together those make the merge exact rather than merely plausible: with the
 * baseline equal to the file and no fact going backwards, `file.facts + delta`
 * is `history`, fact by fact. The file that comes out is the history the race
 * carried, which is the one thing here that is known to be true.
 *
 * What this costs: a race that genuinely was not seeded from this file -- a
 * vector replay, a race started before the file loaded -- can no longer be
 * committed into a file that already holds anything. It is refused, out loud,
 * with the path back stated: seed the race from the file (`factHistoryForRace`)
 * and hand that array in. The proposed `ui/Store.qml` already does exactly
 * that, on every race and after every commit, so it costs the real caller
 * nothing.
 */
export function factHistoryMergeIssues(
  file: SaveFile,
  state: RaceState,
  seededWith: readonly FactRecord[] | null,
  history: readonly FactRecord[],
): SaveIssue[] {
  const human = state.racers.find((racer) => racer.id === state.humanId);
  if (human === undefined)
    return [{ path: "facts", problem: "the race has no human racer to account for" }];
  if (!baselineIsFile(file, seededWith))
    return [{
      path: "facts",
      problem:
        "the declared baseline is not this file's fact history, so nothing here can tell where"
        + " this race came from -- seed the race from the file and declare that array",
    }];
  const baseline = seededWith ?? [];
  const perFact = factHistoryDeltaIssues(baseline, history);
  if (perFact.length > 0) return perFact;
  let added = 0;
  for (const record of factHistoryDelta(baseline, history)) added += record.attempts;
  if (added !== human.attemptCount)
    return [{
      path: "facts",
      problem: "the declared baseline does not account for this race's answers",
    }];
  return [];
}

/** `factHistoryMergeIssues` as a predicate, for callers that only want yes or no. */
export function factHistoryAccounts(
  file: SaveFile,
  state: RaceState,
  seededWith: readonly FactRecord[] | null,
  history: readonly FactRecord[],
): boolean {
  return factHistoryMergeIssues(file, state, seededWith, history).length === 0;
}

export function withFactHistory(file: SaveFile, history: readonly FactRecord[]): SaveFile {
  const next = cloneSave(file);
  next.facts = cloneFactHistory(history);
  return next;
}

/**
 * Add a race's history to a file that did not seed it: attempts and correct
 * sum, and the incoming outcomes are the most recent three, so the window still
 * means what it says.
 */
export function mergeFactHistory(
  base: readonly FactRecord[],
  incoming: readonly FactRecord[],
): FactRecord[] {
  const merged = cloneFactHistory(base);
  for (const record of incoming) {
    let at = -1;
    for (let index = 0; index < merged.length; index++) {
      if (merged[index]!.fact === record.fact) {
        at = index;
        break;
      }
    }
    if (at === -1) {
      let insert = merged.length;
      for (let index = 0; index < merged.length; index++) {
        if (merged[index]!.fact > record.fact) {
          insert = index;
          break;
        }
      }
      merged.splice(insert, 0, {
        fact: record.fact,
        attempts: record.attempts,
        correct: record.correct,
        lastThree: record.lastThree.slice(),
      });
      continue;
    }
    const existing = merged[at]!;
    existing.attempts += record.attempts;
    existing.correct += record.correct;
    const combined = existing.lastThree.concat(record.lastThree);
    existing.lastThree = combined.slice(
      combined.length > FACT_HISTORY_WINDOW ? combined.length - FACT_HISTORY_WINDOW : 0,
    );
  }
  return merged;
}

// ---------------------------------------------------------------------------
// committing a race
// ---------------------------------------------------------------------------

export interface CommitResult {
  file: SaveFile;
  /**
   * True when this race's answers were folded into the fact history. False
   * means the merge was refused -- `issues` says why -- and `file.facts` is
   * exactly what it was, byte for byte. A commit never half-writes a fact
   * history: a race is folded in whole or not at all.
   */
  factsUpdated: boolean;
  /** True when this run displaced the record for its preset. */
  recordUpdated: boolean;
  /** The record that now stands for this race's preset, if there is one. */
  record: RecordEntry | null;
  /**
   * Everything this commit refused to write, with the path it would have gone
   * to. Empty is the normal answer. A record refused because the mode does not
   * set records is reported here rather than dropped in silence, because a
   * caller that offers one is either testing the rule or has a bug.
   */
  issues: SaveIssue[];
}

/**
 * Validate one record entry the only way that cannot drift from the file
 * format: file it under the key it would really occupy, in a file that is
 * otherwise known good, and ask `validateSave`.
 *
 * This is what closes serialise-then-validate. `commitRace` used to file
 * `candidate.preset` under `recordKeyOf(state)` without checking the two
 * agreed, so a caller could hand it a `2-5` record for a `choose:2` race and
 * get back a file whose own validator rejected it with
 * `records.choose:2.preset: does not match the key it is filed under`.
 */
export function recordEntryIssues(key: string, entry: RecordEntry): SaveIssue[] {
  if (!isRecordKey(key)) return [{ path: "records." + key, problem: "not a record key" }];
  const probe = emptySave();
  (probe.records as Record<string, RecordEntry>)[key] = entry;
  return validateSave(probe).issues;
}

/** The same trick for a fact history: would this array survive a write? */
export function factHistoryIssues(facts: readonly FactRecord[]): SaveIssue[] {
  const probe = emptySave();
  probe.facts = facts as FactRecord[];
  return validateSave(probe).issues;
}

/**
 * Fold a finished race into the save file: the fact history always, the record
 * only when the design allows one.
 *
 * `history` is `factHistoryOf(state)`; `seededWith` is what the race was
 * created with, so the two together say exactly what this race added (see
 * `factHistoryDelta`); `candidate` is what `recordFromRace(state, timeline)`
 * returned -- null when the design allows no record.
 *
 * Three rules and one invariant:
 *
 *   - **The fact history is merged only when the caller can prove where the
 *     race came from.** What makes it sound is `factHistoryMergeIssues`: the
 *     declared baseline has to *be* this file's fact history, no fact may go
 *     backwards, and the delta has to add up to the child's `attemptCount`.
 *     When any of that fails the merge is refused outright and said out loud --
 *     `factsUpdated` is false and `file.facts` is untouched -- because a commit
 *     that writes counts it has just called wrong is worse than one that writes
 *     nothing. A second commit of one race fails by construction rather than by
 *     being recognised: the first commit changed the file, so the second call's
 *     baseline is either stale (not the file) or honest and empty (accounts for
 *     none of the race's answers), and both are refused.
 *   - **Records -- clean modes only.** Design, Modes: "Time trial and ghost set
 *     records; Grand Prix never does", and Grand Prix's own row: "places and
 *     times are shown, never stored as records". `recordFromRace` refuses to
 *     *build* a record for a Grand Prix; this refuses to *file* one, because a
 *     candidate can reach here from anywhere and the state is right here to
 *     check. Grand Prix changes `facts` and never `records`.
 *   - **A tie keeps the old record.** One comparison, `ghost.ts`'s
 *     `beatsRecord`, called rather than re-implemented -- there is no second
 *     copy of the rule left to drift.
 *   - **The file that comes out is a file that goes back in.** Given a `file`
 *     `parseSave` would accept, the `file` returned is one `parseSave`
 *     accepts: a record that would not validate is refused, and so is a fact
 *     history that would not.
 */
export function commitRace(
  file: SaveFile,
  state: RaceState,
  history: readonly FactRecord[],
  candidate: RecordEntry | null,
  seededWith: readonly FactRecord[] | null,
): CommitResult {
  const issues: SaveIssue[] = [];
  const key = recordKeyOf(state);

  // ---- the fact history: merged when the merge is sound, else refused ------
  //
  // Order matters and used to be the other way round: `next` was built from
  // the merge first and the accounting was consulted afterwards, so a caller
  // that lied about its baseline got the wrong counts written with an advisory
  // note attached. A merge this function has just declared unsound is a merge
  // it must not hand back.
  const mergeIssues = factHistoryMergeIssues(file, state, seededWith, history);
  for (const issue of mergeIssues) issues.push(issue);
  let next = cloneSave(file);
  let factsUpdated = false;
  if (mergeIssues.length === 0) {
    const merged = mergeFactHistory(file.facts, factHistoryDelta(seededWith, history));
    const factIssues = factHistoryIssues(merged);
    for (const issue of factIssues) issues.push(issue);
    if (factIssues.length === 0) {
      next = withFactHistory(file, merged);
      factsUpdated = true;
    }
  }

  const standing = Object.prototype.hasOwnProperty.call(next.records, key)
    ? next.records[key]!
    : null;

  if (candidate === null) return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  if (!isRecordEligible(state)) {
    issues.push({ path: "records." + key, problem: "the race is not one that sets records" });
    return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  }
  const badEntry = recordEntryIssues(key, candidate);
  if (badEntry.length > 0) {
    for (const issue of badEntry) issues.push(issue);
    return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };
  }
  if (!beatsRecord(standing, candidate))
    return { file: next, factsUpdated, recordUpdated: false, record: standing, issues };

  next.records[key] = cloneRecord(candidate);
  return { file: next, factsUpdated, recordUpdated: true, record: next.records[key]!, issues };
}
