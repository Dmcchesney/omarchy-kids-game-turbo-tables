import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "../..");
const committed = await readFile(resolve(root, "engine/engine.mjs"), "utf8");
const result = spawnSync("npx", [
  "--yes", "esbuild@0.28.2", "src/engine/index.ts",
  "--bundle", "--format=esm", "--platform=neutral", "--target=es2016",
], { cwd: root, encoding: "utf8" });

if (result.status !== 0) {
  console.error(result.stderr);
  process.exitCode = result.status ?? 2;
} else if (result.stdout !== committed) {
  console.error("engine/engine.mjs is stale; run npm run build.");
  process.exitCode = 1;
} else {
  console.log("Bundle parity check passed.");
}
