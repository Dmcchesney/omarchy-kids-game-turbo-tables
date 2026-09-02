import { build } from "esbuild";

await build({
  entryPoints: ["src/engine/index.ts"],
  outfile: "engine/engine.mjs",
  bundle: true,
  format: "esm",
  platform: "neutral",
  target: "es2016",
});
