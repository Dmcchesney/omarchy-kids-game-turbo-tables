// Piece 2's specs -- rivals, ghost and save -- run twice: once against the
// TypeScript source under src/engine, and once against the committed bundle
// engine/engine.mjs loaded as a module.
//
// The bundle is what the QML screens import, so a rule that is only ever
// asserted against the source is a rule the shipped artefact does not have to
// hold. This driver mirrors tests/engine.test.ts, which does the same for the
// Piece 1 specs; it is a separate file so the two pieces' specs can be edited
// without touching each other's driver.

import { resolve } from "node:path";

import type * as EngineModule from "../src/engine/index.ts";
import * as source from "../src/engine/index.ts";

import { spec as ghost } from "./engine/ghost.spec.ts";
import { spec as rivals } from "./engine/rivals.spec.ts";
import { spec as save } from "./engine/save.spec.ts";

const root = resolve(import.meta.dirname, "..");
const bundle = (await import(resolve(root, "engine/engine.mjs"))) as typeof EngineModule;

const SPECS: ((engine: typeof EngineModule, label: string) => void)[] = [rivals, ghost, save];

const ENGINES: [string, typeof EngineModule][] = [
  ["src/engine (TypeScript source)", source],
  ["engine/engine.mjs (committed bundle)", bundle],
];

for (const [label, engine] of ENGINES) {
  for (const run of SPECS) run(engine, label);
}
