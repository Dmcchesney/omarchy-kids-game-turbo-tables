// The single source of truth for how engine/engine.mjs is built.
//
// A listed plugin must run from the repository exactly as cloned, so the
// bundle is committed. `npm run build` writes it and `npm run check:bundle`
// rebuilds it to memory and diffs. Both go through runEsbuild() below, so the
// two invocations cannot drift apart: there is only one argument list.
//
// esbuild is never installed into this checkout. node_modules inside a plugin
// directory fails `omarchy plugin validate`, so the bundler is fetched and run
// by npx at a pinned version instead.

import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

export const repositoryRoot = import.meta.dirname;

/** Pinned bundler. Changing this changes the committed bundle; rebuild it. */
export const esbuildPackage = "esbuild@0.28.2";

export const entryPoint = "src/engine/index.ts";
export const outFile = "engine/engine.mjs";

/**
 * es2016 so Qt's QML engine accepts it; ESM because QML imports the bundle as
 * a module; neutral platform so no Node built-in is ever pulled in; minify
 * stays off so the marketplace scanner and human reviewers can read it.
 */
export const esbuildFlags = Object.freeze([
  "--bundle",
  "--format=esm",
  "--platform=neutral",
  "--target=es2016",
]);

/**
 * Runs the pinned bundler with the shared settings.
 * With no extra arguments esbuild writes the bundle to stdout.
 */
export function runEsbuild(extraArgs = []) {
  return spawnSync(
    "npx",
    ["--yes", esbuildPackage, entryPoint, ...esbuildFlags, ...extraArgs],
    { cwd: repositoryRoot, encoding: "utf8" },
  );
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
  const result = runEsbuild([`--outfile=${outFile}`]);
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) process.exitCode = result.status ?? 2;
  else console.log(`Wrote ${outFile} with ${esbuildPackage} ${esbuildFlags.join(" ")}`);
}
