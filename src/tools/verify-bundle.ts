import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { build } from "esbuild";

const root = resolve(import.meta.dirname, "../..");
const committed = await readFile(resolve(root, "engine/engine.mjs"), "utf8");
const result = await build({
  entryPoints: [resolve(root, "src/engine/index.ts")],
  bundle: true,
  format: "esm",
  platform: "neutral",
  target: "es2016",
  write: false,
});
const generated = result.outputFiles[0]?.text;

if (generated !== committed) {
  console.error("engine/engine.mjs is stale; run npm run build.");
  process.exitCode = 1;
} else {
  console.log("Bundle parity check passed.");
}
