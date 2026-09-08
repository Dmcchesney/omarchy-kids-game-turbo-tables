/**
 * The ghost: the answer timeline a clean run leaves behind, and the rules that
 * decide whether it becomes the record.
 *
 * Design, Modes: Time trial "sets the personal best per preset; produces the
 * ghost"; Ghost races "your previous best", and "beat the ghost and the record
 * updates". Grand Prix "places and times are shown, never stored as records".
 * Design, Data: `records` is "per preset: best clean time, correct, attempted,
 * answer timeline for the ghost".
 *
 * A timeline is a list of samples, one per answer, each holding the race clock
 * and the effective progress the answer left the kart at. That is enough for
 * the track view to place a translucent kart at any moment of the replay and
 * enough for the results screen to say whether the ghost was beaten, and it is
 * the smallest thing that is. There are no dates in it; every number is a
 * duration measured from the start of its own race.
 */

import { effectiveProgress } from "./progress.ts";
import { QUESTIONS_PER_LAP, type PresetId } from "./deck.ts";
import type { RaceEvent } from "./events.ts";
import type { RaceState } from "./race.ts";

/** One answer, as the ghost replays it. */
export interface GhostSample {
  /** Milliseconds since the start of the race. Never a date. */
  atMs: number;
  /** Effective progress after the answer: laps x 12 + correct − (need − 12). */
  progress: number;
}

export interface GhostTimeline {
  /** Ascending by `atMs`. */
  samples: GhostSample[];
}

/** Design, Data: "per preset: best clean time, correct, attempted, answer timeline". */
export interface RecordEntry {
  preset: PresetId;
  /** The finishing time of the run, in milliseconds from the start. */
  timeMs: number;
  correct: number;
  attempted: number;
  timeline: GhostTimeline;
}

export function emptyTimeline(): GhostTimeline {
  return { samples: [] };
}

export function cloneTimeline(timeline: GhostTimeline): GhostTimeline {
  return {
    samples: timeline.samples.map((sample) => ({ atMs: sample.atMs, progress: sample.progress })),
  };
}

export function cloneRecord(record: RecordEntry): RecordEntry {
  return {
    preset: record.preset,
    timeMs: record.timeMs,
    correct: record.correct,
    attempted: record.attempted,
    timeline: cloneTimeline(record.timeline),
  };
}

// ---------------------------------------------------------------------------
// recording
// ---------------------------------------------------------------------------

/** The event types that move a kart, and therefore leave a sample. */
const ANSWER_EVENTS = ["correct", "reveal", "pitCrew"];

/**
 * Add the samples one step's events produced for the racer being recorded.
 *
 * The progress is read from the state *after* the step, so a sample records
 * where the kart ended up, including any lap the answer completed. A step that
 * produced several answer events for the same racer -- which the reducer never
 * does, but a caller batching inputs could -- records the last one only, since
 * they would all read the same progress.
 */
export function recordStep(
  timeline: GhostTimeline,
  state: RaceState,
  events: readonly RaceEvent[],
  racerId: string,
): GhostTimeline {
  const next = cloneTimeline(timeline);
  let at = -1;
  for (const event of events) {
    if (event.racerId !== racerId) continue;
    if (ANSWER_EVENTS.indexOf(event.type) === -1) continue;
    at = event.at;
  }
  if (at < 0) return next;
  const racer = state.racers.find((entry) => entry.id === racerId);
  if (racer === undefined) return next;
  const progress = effectiveProgress(racer, state.questionsPerLap);
  const atMs = at - state.startedAtMs;
  const last = next.samples.length > 0 ? next.samples[next.samples.length - 1]! : null;
  if (last !== null && last.atMs === atMs) {
    last.progress = progress;
    return next;
  }
  next.samples.push({ atMs: atMs < 0 ? 0 : atMs, progress });
  return next;
}

/**
 * Build a whole timeline from a finished replay: the events of the race in
 * order, plus the final state. Used by the vectors and by any caller that has
 * the event stream rather than the steps.
 */
export function timelineFromEvents(
  events: readonly RaceEvent[],
  racerId: string,
  startedAtMs: number,
  questionsPerLap: number = QUESTIONS_PER_LAP,
): GhostTimeline {
  const timeline = emptyTimeline();
  let lapsComplete = 0;
  let correctInLap = 0;
  let need = questionsPerLap;
  for (const event of events) {
    if (event.racerId !== racerId) continue;
    if (event.type === "hit") {
      need = event.questionsNeededThisLap;
      continue;
    }
    if (event.type === "lapComplete") {
      lapsComplete = event.lapsComplete;
      correctInLap = event.surplus;
      need = questionsPerLap;
      continue;
    }
    if (ANSWER_EVENTS.indexOf(event.type) === -1) continue;
    correctInLap += 1;
    const progress = lapsComplete * questionsPerLap + correctInLap - (need - questionsPerLap);
    const atMs = event.at - startedAtMs;
    timeline.samples.push({ atMs: atMs < 0 ? 0 : atMs, progress });
  }
  return timeline;
}

// ---------------------------------------------------------------------------
// playback
// ---------------------------------------------------------------------------

/**
 * Where the ghost is at a given moment of the replay.
 *
 * Before its first answer the ghost is at zero; after its last it stays where
 * it finished. Between two samples the progress is interpolated linearly, so
 * the ghost kart glides rather than teleporting once per answer, and the value
 * is a float on purpose -- it is a position on the track, not a question count.
 */
export function ghostProgressAt(timeline: GhostTimeline, atMs: number): number {
  const samples = timeline.samples;
  if (samples.length === 0) return 0;
  if (atMs <= samples[0]!.atMs) {
    const first = samples[0]!;
    if (first.atMs <= 0) return first.progress;
    const fraction = atMs <= 0 ? 0 : atMs / first.atMs;
    return first.progress * fraction;
  }
  const last = samples[samples.length - 1]!;
  if (atMs >= last.atMs) return last.progress;
  let low = 0;
  let high = samples.length - 1;
  while (high - low > 1) {
    const middle = (low + high) >> 1;
    if (samples[middle]!.atMs <= atMs) low = middle;
    else high = middle;
  }
  const before = samples[low]!;
  const after = samples[high]!;
  const span = after.atMs - before.atMs;
  if (span <= 0) return after.progress;
  const fraction = (atMs - before.atMs) / span;
  return before.progress + (after.progress - before.progress) * fraction;
}

/** The moment the ghost first reached this much progress, or -1 if it never did. */
export function ghostReachedAt(timeline: GhostTimeline, progress: number): number {
  for (const sample of timeline.samples) if (sample.progress >= progress) return sample.atMs;
  return -1;
}

/** How far ahead of the live kart the ghost is, in questions. Negative is behind. */
export function ghostLead(timeline: GhostTimeline, atMs: number, progress: number): number {
  return ghostProgressAt(timeline, atMs) - progress;
}

// ---------------------------------------------------------------------------
// the record rules
// ---------------------------------------------------------------------------

/**
 * Design, Modes: "Records are clean by construction: only powerup-free runs
 * count", and the settled decision "Records -- Clean modes only. Time trial and
 * ghost set records; Grand Prix never does."
 *
 * Four conditions, all of them read off the state rather than promised:
 * a clean mode, powerups actually off, no card played by anybody, and the
 * child across the line. Practice sets nothing, because Practice has no timer
 * and reveals every mistake.
 */
export function isCleanMode(state: RaceState): boolean {
  return state.mode === "timeTrial" || state.mode === "ghost";
}

export function isRecordEligible(state: RaceState): boolean {
  if (!isCleanMode(state)) return false;
  if (state.powerupsEnabled) return false;
  for (const racer of state.racers) if (racer.cardsUsed.length > 0) return false;
  const human = state.racers.find((racer) => racer.id === state.humanId);
  if (human === undefined) return false;
  return human.finished;
}

/** The record a finished clean run would set, or null when it sets none. */
export function recordFromRace(state: RaceState, timeline: GhostTimeline): RecordEntry | null {
  if (!isRecordEligible(state)) return null;
  const human = state.racers.find((racer) => racer.id === state.humanId);
  if (human === undefined) return null;
  return {
    preset: state.preset,
    timeMs: human.finishTimeMs - state.startedAtMs,
    correct: human.correctCount,
    attempted: human.attemptCount,
    timeline: cloneTimeline(timeline),
  };
}

/**
 * Design, plan, ghost.ts: "a tie keeps the old record."
 *
 * Strictly faster wins, and nothing else is compared: a run with more correct
 * answers but the same time does not displace the record, because the record is
 * the time. The comparison is one `<`, and it is here so it can be named.
 */
export function beatsRecord(previous: RecordEntry | null, candidate: RecordEntry): boolean {
  if (previous === null) return true;
  return candidate.timeMs < previous.timeMs;
}

export function bestRecord(previous: RecordEntry | null, candidate: RecordEntry): RecordEntry {
  return beatsRecord(previous, candidate) ? cloneRecord(candidate) : cloneRecord(previous!);
}

export interface RecordUpdate {
  record: RecordEntry;
  /** False when the run tied or lost and the old record stands. */
  updated: boolean;
}

export function updateRecord(
  previous: RecordEntry | null,
  candidate: RecordEntry,
): RecordUpdate {
  const updated = beatsRecord(previous, candidate);
  return { record: updated ? cloneRecord(candidate) : cloneRecord(previous!), updated };
}
