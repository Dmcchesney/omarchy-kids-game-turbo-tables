// npm run props -- bake the prop kit, headless, and record its manifest.
//
// Runs Blender in background mode once on src/tools/bake-props.py (the model
// of every roadside landmark and power-up effect sprite), then
// src/tools/px-props.py (the pixel pass, which shares pxart.py with the car
// sheets) to produce assets/props/<name>.png, one indexed sheet per prop, and
// assets/props/props-meta.json (cells, views, anchors, opaque bounds). The
// manifest records a SHA-256 for every file, check-props.ts holds the tree to
// it in CI, and the meta is mirrored into ui/parts/PropMeta.js for layer 2.
//
// Mac only: Blender lives here and never ships. The bake is deterministic
// (EEVEE's sampling is pinned in the model; pxart's encoder is fixed), so
// `npm run props -- --verify` bakes into a scratch directory and fails if any
// byte differs from what is committed -- the reproducibility gate.
//
//   npm run props                      the whole kit (25 props, a few minutes)
//   npm run props -- --only gantry,crowd
//   npm run props -- --verify
//   TURBO_TABLES_BLENDER=/path/to/Blender npm run props

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative, resolve, sep } from "node:path";

export const PROPS_DIR = "assets/props";
export const MANIFEST = `${PROPS_DIR}/manifest.json`;
export const META = `${PROPS_DIR}/props-meta.json`;
const root = resolve(import.meta.dirname, "../..");

export function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

const UNLISTED = new Set(["manifest.json", ".gitkeep"]);
/** Every file on disk under assets/props/, relative to it, but the manifest and the git placeholder. */
export async function kitFiles(repositoryRoot: string): Promise<string[]> {
  const base = join(repositoryRoot, PROPS_DIR);
  if (!existsSync(base)) return [];
  const found: string[] = [];
  for (const entry of await readdir(base, { recursive: true, withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const rel = relative(base, join(entry.parentPath, entry.name)).split(sep).join("/");
    if (UNLISTED.has(rel)) continue;
    found.push(rel);
  }
  return found.sort();
}

export type PropMeta = Record<string, { cell: [number, number]; views: string[]; effect: boolean; ground: [number, number] | null; sheet?: [number, number]; rows?: number[]; bounds?: Record<string, number[]> }>;
export type Manifest = { generator: string; fine: number; props: string[]; files: Record<string, string> };

export async function buildManifest(repositoryRoot: string): Promise<Manifest> {
  const meta = JSON.parse(await readFile(join(repositoryRoot, META), "utf8")) as PropMeta;
  const props = Object.keys(meta).sort();
  const files: Record<string, string> = {};
  for (const rel of [...props.map((p) => `${p}.png`), "props-meta.json"]) {
    files[rel] = sha256(await readFile(join(repositoryRoot, PROPS_DIR, rel)));
  }
  return {
    generator: "src/tools/bake-props.py (Blender, headless) + src/tools/px-props.py; written by src/tools/bake-props.ts",
    fine: 4,
    props,
    files,
  };
}

function run(command: string, args: string[], cwd: string, env?: NodeJS.ProcessEnv): Promise<{ status: number; output: string }> {
  return new Promise((done) => {
    const child = spawn(command, args, { cwd, stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, ...env } });
    let output = "";
    child.stdout.on("data", (chunk: Buffer) => (output += chunk.toString()));
    child.stderr.on("data", (chunk: Buffer) => (output += chunk.toString()));
    child.on("close", (status) => done({ status: status ?? 1, output }));
    child.on("error", (error) => done({ status: 1, output: String(error) }));
  });
}

async function main(): Promise<void> {
  const blender = process.env.TURBO_TABLES_BLENDER ?? "/Applications/Blender.app/Contents/MacOS/Blender";
  if (!existsSync(blender)) throw new Error(`Blender not found at ${blender}; set TURBO_TABLES_BLENDER. The bake runs on the Mac only.`);
  const verify = process.argv.includes("--verify");
  const onlyIndex = process.argv.indexOf("--only");
  const only = onlyIndex >= 0 ? (process.argv[onlyIndex + 1] ?? "") : "";
  if (verify && only) throw new Error("--verify bakes the whole kit; drop --only");
  const scratch = await mkdtemp(join(tmpdir(), "turbo-tables-props-"));
  const renders = join(scratch, "render");
  const outDir = verify ? join(scratch, "out") : join(root, PROPS_DIR);
  await mkdir(renders, { recursive: true });
  await mkdir(outDir, { recursive: true });
  const started = performance.now();

  const bakeArgs = ["-b", "--python", join(root, "src/tools/bake-props.py"), "--", "--out", renders];
  if (only) bakeArgs.push("--only", only);
  const bake = await run(blender, bakeArgs, root);
  if (bake.status !== 0) {
    await rm(scratch, { recursive: true, force: true });
    throw new Error(`Blender exited ${bake.status}\n${bake.output.split("\n").slice(-20).join("\n")}`);
  }
  console.log(`rendered ${only || "the whole kit"} (${((performance.now() - started) / 1000).toFixed(0)}s)`);

  const px = await run("python3", [join(root, "src/tools/px-props.py"), renders, outDir, "--px", "2"], root);
  if (px.status !== 0) {
    await rm(scratch, { recursive: true, force: true });
    throw new Error(`px-props exited ${px.status}\n${px.output.split("\n").slice(-20).join("\n")}`);
  }
  if (only) {
    // A subset bake must not shrink the meta: px-props wrote entries for the
    // subset only, so fold them into what is committed for every other prop.
    const committed = existsSync(join(root, META)) ? (JSON.parse(await readFile(join(root, META), "utf8")) as PropMeta) : {};
    const subset = JSON.parse(await readFile(join(outDir, "props-meta.json"), "utf8")) as PropMeta;
    await writeFile(join(outDir, "props-meta.json"), `${JSON.stringify({ ...committed, ...subset }, null, 1)}\n`);
  }

  if (verify) {
    const diffs: string[] = [];
    const names = (await readdir(outDir)).filter((n) => n.endsWith(".png") || n === "props-meta.json").sort();
    for (const name of names) {
      const committedPath = join(root, PROPS_DIR, name);
      if (!existsSync(committedPath)) {
        diffs.push(`${name}: not committed`);
        continue;
      }
      const a = await readFile(join(outDir, name));
      const b = await readFile(committedPath);
      if (!a.equals(b)) diffs.push(`${name}: differs (${sha256(a)} vs committed ${sha256(b)})`);
    }
    await rm(scratch, { recursive: true, force: true });
    if (diffs.length > 0) throw new Error(`Rebake does not reproduce the committed kit:\n${diffs.join("\n")}`);
    console.log(`Reproducible: ${names.length} files rebaked byte-identical.`);
    return;
  }

  await rm(scratch, { recursive: true, force: true });
  const manifest = await buildManifest(root);
  await writeFile(join(root, MANIFEST), `${JSON.stringify(manifest, null, 2)}\n`);
  const mirror = await run("python3", [join(root, "src/tools/mirror-prop-meta.py"), join(root, PROPS_DIR), join(root, "ui/parts/PropMeta.js")], root);
  if (mirror.status !== 0) throw new Error(`mirror-prop-meta.py exited ${mirror.status}\n${mirror.output}`);
  let bytes = 0;
  for (const rel of Object.keys(manifest.files)) bytes += (await readFile(join(root, PROPS_DIR, rel))).length;
  console.log(`Wrote ${MANIFEST}: ${manifest.props.length} props, ${Object.keys(manifest.files).length} files, ${(bytes / 1024).toFixed(0)} KiB (${((performance.now() - started) / 1000).toFixed(0)}s).`);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
