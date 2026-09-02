// Every layer 1 spec, run twice: once against the TypeScript source under
// src/engine, and once against the committed bundle engine/engine.mjs loaded as
// a module. The bundle is what the QML screens import, so a rule that is only
// ever asserted against the source is a rule the shipped artefact does not have
// to hold.
//
// This closes the hole the round 1 critic found: `tests/engine/*` imported
// `../../src/engine/index.ts` and never the bundle, so a bundle with a wrong
// Roll Cage consumption shipped green.
//
// The specs themselves live in tests/engine/*.spec.ts and take the engine as a
// parameter. Nothing under tests/engine imports an engine directly any more.

import { resolve } from "node:path";

import type * as EngineModule from "../src/engine/index.ts";
import * as source from "../src/engine/index.ts";

import { spec as answerLoop } from "./engine/answer-loop.spec.ts";
import { spec as cards } from "./engine/cards.spec.ts";
import { spec as deck } from "./engine/deck.spec.ts";
import { spec as determinism } from "./engine/determinism.spec.ts";
import { spec as events } from "./engine/events.spec.ts";
import { spec as factHistory } from "./engine/fact-history.spec.ts";
import { spec as fairness } from "./engine/fairness.spec.ts";
import { spec as progress } from "./engine/progress.spec.ts";
import { spec as raceFormat } from "./engine/race-format.spec.ts";
import { spec as rank } from "./engine/rank.spec.ts";
import { spec as rng } from "./engine/rng.spec.ts";
import { spec as streak } from "./engine/streak.spec.ts";
import { spec as timings } from "./engine/timings.spec.ts";

const root = resolve(import.meta.dirname, "..");
const bundle = (await import(resolve(root, "engine/engine.mjs"))) as typeof EngineModule;

const SPECS: ((engine: typeof EngineModule, label: string) => void)[] = [
  answerLoop,
  cards,
  deck,
  determinism,
  events,
  factHistory,
  fairness,
  progress,
  raceFormat,
  rank,
  rng,
  streak,
  timings,
];

const ENGINES: [string, typeof EngineModule][] = [
  ["src/engine (TypeScript source)", source],
  ["engine/engine.mjs (committed bundle)", bundle],
];

for (const [label, engine] of ENGINES) {
  for (const run of SPECS) run(engine, label);
}
