// Bundle parity: engine/engine.mjs must be the build output of src/engine at
// this exact working-tree state. The build settings are not repeated here;
// they are imported from esbuild.config.mjs, which npm run build also uses.

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  entryPoint,
  esbuildFlags,
  esbuildPackage,
  outFile,
  repositoryRoot,
  runEsbuild,
} from "../../esbuild.config.mjs";

const committed = await readFile(resolve(repositoryRoot, outFile), "utf8");
const result = runEsbuild();

if (result.status !== 0) {
  if (result.stderr) console.error(result.stderr);
  console.error(`Could not rebuild ${outFile} from ${entryPoint}.`);
  process.exitCode = result.status ?? 2;
} else if (result.stdout !== committed) {
  console.error(`${outFile} is stale relative to ${entryPoint}; run npm run build and commit the result.`);
  process.exitCode = 1;
} else {
  console.log(
    `Bundle parity check passed: ${outFile} matches ${entryPoint} rebuilt with ${esbuildPackage} ${esbuildFlags.join(" ")}.`,
  );
}
