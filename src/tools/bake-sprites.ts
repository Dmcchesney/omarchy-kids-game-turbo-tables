// npm run sprites -- bake every car sheet, headless, and record the manifest.
//
// For each of the six bodies and eight paints this runs Blender in background
// mode on src/tools/bake-cars.py (the model), then src/tools/pxart.py (the
// pixel pass) to produce assets/karts/<body>/<paint>.png in the layout
// pieceC's contract fixes: two cameras x eight yaws x three scales, fixed
// cells, bottom-centre anchored. bake-cars.py also writes the body's
// meta.json (number rects, lamp centres, ground anchor), which is identical
// for every paint and is copied once per body after the eight are checked
// against each other.
//
// The paints come from ui/Theme.qml -- the same eight hexes the garage's
// swatch grid shows -- so the sheets can never drift from the swatches. The
// manifest records them, and check-sprites.ts fails when the theme's list no
// longer matches the manifest's, which is the signal to rebake.
//
// Mac only: Blender lives here and never ships. CI runs check:sprites, which
// reads the manifest and never rebakes. Nothing here is loaded by the shell.
//
// Usage:
//   npm run sprites                       everything (48 sheets, about a minute)
//   npm run sprites -- --bodies coupe,hatch --paints red,blue
//                                         a subset; the manifest is rewritten
//                                         from what is on disk afterwards
//   TURBO_TABLES_BLENDER=/path/to/Blender npm run sprites
//
// The bake is deterministic: pxart.py writes the PNGs with its own fixed
// encoder, so the same model and the same renderer give the same bytes.
// `npm run sprites -- --verify` bakes into a scratch directory instead and
// fails if any file differs from what is committed -- the reproducibility
// gate, run by hand on the Mac.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { availableParallelism, tmpdir } from "node:os";
import { join, relative, resolve, sep } from "node:path";

export const BODIES = ["coupe", "hatch", "wedge", "saloon", "buggy", "pickup"] as const;
export const PAINT_NAMES = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "white"] as const;
export const KARTS_DIR = "assets/karts";
export const MANIFEST = `${KARTS_DIR}/manifest.json`;

const root = resolve(import.meta.dirname, "../..");

/** The eight swatches, in swatch-grid order, read from ui/Theme.qml. */
export async function themePaints(repositoryRoot: string): Promise<string[]> {
  const theme = await readFile(join(repositoryRoot, "ui/Theme.qml"), "utf8");
  const block = theme.match(/readonly property var paints:\s*\[([^\]]*)\]/);
  if (!block) throw new Error("ui/Theme.qml: could not find `readonly property var paints: [...]`");
  const hexes = [...block[1].matchAll(/"#([0-9a-fA-F]{6})"/g)].map((m) => m[1].toLowerCase());
  if (hexes.length !== PAINT_NAMES.length) {
    throw new Error(`ui/Theme.qml lists ${hexes.length} paints; the contract needs ${PAINT_NAMES.length}`);
  }
  return hexes;
}

export function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Every file the manifest covers: <body>/<paint>.png and <body>/meta.json. */
export function contractFiles(): string[] {
  const found: string[] = [];
  for (const body of BODIES) for (const name of [...PAINT_NAMES.map((p) => `${p}.png`), "meta.json"]) found.push(`${body}/${name}`);
  return found;
}

/**
 * Every file actually on disk under assets/karts/, at any depth, relative to
 * it -- all but the manifest itself and the directory's git placeholder. The
 * check compares this against the manifest, so a stray file anywhere under
 * assets/karts/ (a body directory, the top level, a new subdirectory) is a
 * failure, not a blind spot.
 */
const UNLISTED = new Set(["manifest.json", ".gitkeep"]);
export async function sheetFiles(repositoryRoot: string): Promise<string[]> {
  const base = join(repositoryRoot, KARTS_DIR);
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

export type Manifest = {
  generator: string;
  bodies: string[];
  paints: Record<string, string>;
  sheet: { width: number; height: number; rows: number; yaws: number };
  files: Record<string, string>;
};

export async function buildManifest(repositoryRoot: string): Promise<Manifest> {
  const hexes = await themePaints(repositoryRoot);
  const files: Record<string, string> = {};
  // The contract's files only, and every one must exist: a stray file on disk
  // never enters the manifest, and a bake that produced nothing cannot pass.
  for (const rel of contractFiles()) {
    files[rel] = sha256(await readFile(join(repositoryRoot, KARTS_DIR, rel)));
  }
  return {
    generator: "src/tools/bake-cars.py (Blender, headless) + src/tools/pxart.py; written by src/tools/bake-sprites.ts",
    bodies: [...BODIES],
    paints: Object.fromEntries(PAINT_NAMES.map((name, i) => [name, hexes[i]])),
    sheet: { width: 1536, height: 448, rows: 6, yaws: 8 },
    files,
  };
}

export function renderManifest(manifest: Manifest): string {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}

function run(command: string, args: string[], cwd: string): Promise<{ status: number; output: string }> {
  return new Promise((done) => {
    const child = spawn(command, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk: Buffer) => (output += chunk.toString()));
    child.stderr.on("data", (chunk: Buffer) => (output += chunk.toString()));
    child.on("close", (status) => done({ status: status ?? 1, output }));
    child.on("error", (error) => done({ status: 1, output: String(error) }));
  });
}

async function pool<T>(items: T[], width: number, work: (item: T) => Promise<void>): Promise<void> {
  const queue = [...items];
  const workers = Array.from({ length: Math.min(width, queue.length) }, async () => {
    for (let next = queue.shift(); next !== undefined; next = queue.shift()) await work(next);
  });
  await Promise.all(workers);
}

function listArg(name: string, all: readonly string[]): string[] {
  const i = process.argv.indexOf(name);
  if (i < 0) return [...all];
  const picked = (process.argv[i + 1] ?? "").split(",").filter(Boolean);
  for (const p of picked) if (!all.includes(p)) throw new Error(`${name}: unknown ${p}; one of ${all.join(", ")}`);
  return picked;
}

async function main(): Promise<void> {
  const blender = process.env.TURBO_TABLES_BLENDER ?? "/Applications/Blender.app/Contents/MacOS/Blender";
  if (!existsSync(blender)) {
    throw new Error(`Blender not found at ${blender}; set TURBO_TABLES_BLENDER. The bake runs on the Mac only.`);
  }
  const verify = process.argv.includes("--verify");
  const bodies = listArg("--bodies", BODIES);
  const paints = listArg("--paints", PAINT_NAMES);
  const hexes = await themePaints(root);
  const scratch = await mkdtemp(join(tmpdir(), "turbo-tables-sprites-"));
  const outRoot = verify ? join(scratch, "out") : join(root, KARTS_DIR);
  const bakeScript = join(root, "src/tools/bake-cars.py");
  const pxScript = join(root, "src/tools/pxart.py");

  const jobs: { body: string; paint: string; hex: string }[] = [];
  for (const body of bodies) for (const paint of paints) jobs.push({ body, paint, hex: hexes[PAINT_NAMES.indexOf(paint as never)] });
  const failures: string[] = [];
  const started = performance.now();
  await pool(jobs, Math.max(1, Math.min(6, availableParallelism())), async ({ body, paint, hex }) => {
    const renders = join(scratch, "render", body, paint);
    await mkdir(renders, { recursive: true });
    await mkdir(join(outRoot, body), { recursive: true });
    const bake = await run(blender, ["-b", "--python", bakeScript, "--", "--body", body, "--paint", hex, "--out", renders], root);
    if (bake.status !== 0) {
      failures.push(`${body}/${paint}: Blender exited ${bake.status}\n${bake.output.split("\n").slice(-12).join("\n")}`);
      return;
    }
    const px = await run("python3", [pxScript, "bake", renders, join(outRoot, body, `${paint}.png`), "--paint", hex], root);
    if (px.status !== 0) {
      failures.push(`${body}/${paint}: pxart exited ${px.status}\n${px.output.split("\n").slice(-12).join("\n")}`);
      return;
    }
    console.log(`baked ${body}/${paint}.png (${((performance.now() - started) / 1000).toFixed(0)}s)`);
  });
  if (failures.length > 0) {
    await rm(scratch, { recursive: true, force: true });
    throw new Error(failures.join("\n\n"));
  }

  // meta.json: one per body, and every paint's copy has to agree.
  for (const body of bodies) {
    const metas = await Promise.all(paints.map((paint) => readFile(join(scratch, "render", body, paint, "meta.json"), "utf8")));
    const disagree = metas.findIndex((m) => m !== metas[0]);
    if (disagree > 0) {
      throw new Error(`${body}: meta.json differs between ${paints[0]} and ${paints[disagree]}; the model must not depend on paint`);
    }
    await writeFile(join(outRoot, body, "meta.json"), metas[0]);
  }

  if (verify) {
    // Compare the scratch bake against the committed tree, byte for byte.
    const diffs: string[] = [];
    for (const body of bodies) {
      for (const name of [...paints.map((p) => `${p}.png`), "meta.json"]) {
        const fresh = await readFile(join(outRoot, body, name));
        const committedPath = join(root, KARTS_DIR, body, name);
        if (!existsSync(committedPath)) {
          diffs.push(`${body}/${name}: not committed`);
          continue;
        }
        const committed = await readFile(committedPath);
        if (!fresh.equals(committed)) diffs.push(`${body}/${name}: differs (${sha256(fresh)} vs committed ${sha256(committed)})`);
      }
    }
    await rm(scratch, { recursive: true, force: true });
    if (diffs.length > 0) throw new Error(`Rebake does not reproduce the committed sheets:\n${diffs.join("\n")}`);
    console.log(`Reproducible: ${bodies.length * paints.length} sheets and ${bodies.length} meta files rebaked byte-identical.`);
    return;
  }

  await rm(scratch, { recursive: true, force: true });
  const manifest = await buildManifest(root);
  await writeFile(join(root, MANIFEST), renderManifest(manifest));
  // Layer 2 may not read a file at runtime (XMLHttpRequest is a forbidden
  // token everywhere but layer 3), so the per-body meta.json is mirrored into
  // ui/parts/CarMeta.js as a JavaScript literal, and tests/carmeta.test.ts
  // fails npm test whenever the two disagree. Regenerating the mirror here,
  // in the same run that wrote the meta, is what keeps that test from being
  // the thing that reminds someone.
  await new Promise<void>((resolveMirror, rejectMirror) => {
    const mirror = spawn("python3", [join(root, "src/tools/mirror-car-meta.py"), join(root, KARTS_DIR), join(root, "ui/parts/CarMeta.js")], { stdio: "inherit" });
    mirror.on("exit", (code) => (code === 0 ? resolveMirror() : rejectMirror(new Error(`mirror-car-meta.py exited ${code}`))));
    mirror.on("error", rejectMirror);
  });
  let bytes = 0;
  for (const rel of Object.keys(manifest.files)) bytes += (await readFile(join(root, KARTS_DIR, rel))).length;
  console.log(
    `Wrote ${MANIFEST}: ${Object.keys(manifest.files).length} files, ${(bytes / 1024).toFixed(0)} KiB under ${KARTS_DIR}/<body>/ ` +
      `(${((performance.now() - started) / 1000).toFixed(0)}s).`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
