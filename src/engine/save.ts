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
import { cloneTimeline, type RecordEntry } from "./ghost.ts";
import { FACT_HISTORY_WINDOW, cloneFactHistory, type FactRecord } from "./history.ts";
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
  return "choose:" + sorted.join("-");
}

export function recordKeyOf(state: RaceState): string {
  return recordKey(state.preset, state.tables);
}

const FIXED_PRESETS: readonly string[] = ["2-5", "2-10", "1-12"];
const CHOOSE_KEY = /^choose:(?:[1-9]|1[0-2])(?:-(?:[1-9]|1[0-2]))*$/;

export function isRecordKey(key: string): boolean {
  return FIXED_PRESETS.indexOf(key) !== -1 || CHOOSE_KEY.test(key);
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
  checkRange(value.streakThreshold, 1, 144, "settings.streakThreshold", issues);
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
    if (!isWholeNumber(sample.progress))
      issues.push({ path: at + ".progress", problem: "expected a whole number" });
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
  let raw: Record<string, unknown> = value;
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
 * The save half. The race was seeded from this file, so the history it hands
 * back with `factHistoryOf(state)` already contains everything the file held
 * plus everything this race added: it replaces, it does not merge.
 *
 * `raceWasSeededFrom` is the precondition, and it is checkable rather than
 * assumed. When it does not hold -- a race created without a history, replayed
 * from a vector, or loaded from a different file -- use `mergeFactHistory`,
 * which adds the two together instead.
 */
export function raceWasSeededFrom(file: SaveFile, history: readonly FactRecord[]): boolean {
  for (const saved of file.facts) {
    let found = false;
    for (const record of history) {
      if (record.fact !== saved.fact) continue;
      found = true;
      if (record.attempts < saved.attempts || record.correct < saved.correct) return false;
      break;
    }
    if (!found) return false;
  }
  return true;
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
  /** True when this run displaced the record for its preset. */
  recordUpdated: boolean;
  /** The record that now stands for this race's preset, if there is one. */
  record: RecordEntry | null;
}

/**
 * Fold a finished race into the save file: the fact history always, the record
 * only when the design allows one.
 *
 * `history` is `factHistoryOf(state)` and `candidate` is what
 * `recordFromRace(state, timeline)` returned -- null when the design allows no
 * record. Grand Prix changes `facts` and never `records`, which is the settled
 * decision "Records -- Clean modes only" written as code.
 */
export function commitRace(
  file: SaveFile,
  state: RaceState,
  history: readonly FactRecord[],
  candidate: RecordEntry | null,
): CommitResult {
  const next = raceWasSeededFrom(file, history)
    ? withFactHistory(file, history)
    : withFactHistory(file, mergeFactHistory(file.facts, history));
  if (candidate === null) {
    const key = recordKeyOf(state);
    return {
      file: next,
      recordUpdated: false,
      record: Object.prototype.hasOwnProperty.call(next.records, key) ? next.records[key]! : null,
    };
  }
  const key = recordKeyOf(state);
  const previous = Object.prototype.hasOwnProperty.call(next.records, key) ? next.records[key]! : null;
  // Design, plan, ghost.ts: "a tie keeps the old record."
  const updated = previous === null || candidate.timeMs < previous.timeMs;
  if (updated) {
    next.records[key] = {
      preset: candidate.preset,
      timeMs: candidate.timeMs,
      correct: candidate.correct,
      attempted: candidate.attempted,
      timeline: cloneTimeline(candidate.timeline),
    };
  }
  return { file: next, recordUpdated: updated, record: next.records[key]! };
}
