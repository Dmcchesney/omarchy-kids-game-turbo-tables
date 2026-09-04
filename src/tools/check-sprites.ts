// npm run check:sprites -- the committed car sheets against their manifest.
//
// assets/karts/manifest.json is written by npm run sprites (bake-sprites.ts)
// and records a SHA-256 for every <body>/<paint>.png and <body>/meta.json.
// This check, which CI runs and which never rebakes (Blender lives only on the
// Mac), fails when:
//
//   * a listed file is missing, or its bytes differ from the recorded hash
//     -- an edited sheet, or a stale manifest after a rebake;
//   * a file exists under a body directory that the manifest does not list
//     -- a sheet that was never baked by the script;
//   * the manifest's paints are not ui/Theme.qml's eight swatches, in order
//     -- the theme changed a paint and the sheets were not rebaked;
//   * a body is missing a paint or its meta.json, a sheet is not a
//     1536x448 PNG, or a meta.json does not carry eight rects per camera.
//
// So a model change cannot land without its sheets, and a sheet cannot land
// without the model that made it.

import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { BODIES, KARTS_DIR, MANIFEST, PAINT_NAMES, sha256, sheetFiles, themePaints, type Manifest } from "./bake-sprites.ts";

const root = resolve(import.meta.dirname, "../..");
const failures: string[] = [];
const fail = (message: string): void => {
  failures.push(message);
};

const SHEET = { width: 1536, height: 448 };

function pngSize(bytes: Buffer): { width: number; height: number } | null {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature) || bytes.subarray(12, 16).toString("latin1") !== "IHDR") return null;
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

let manifest: Manifest | null = null;
try {
  manifest = JSON.parse(await readFile(join(root, MANIFEST), "utf8")) as Manifest;
} catch (error) {
  fail(`${MANIFEST}: cannot read (${error instanceof Error ? error.message : String(error)}); run npm run sprites on the Mac`);
}

if (manifest) {
  // 1. Paints: the manifest's eight against the theme's eight, in order.
  const theme = await themePaints(root);
  PAINT_NAMES.forEach((name, i) => {
    const recorded = manifest.paints?.[name];
    if (recorded !== theme[i]) {
      fail(`paint ${name}: ui/Theme.qml says #${theme[i]} but the sheets were baked with #${recorded ?? "(unrecorded)"}; rebake`);
    }
  });

  // 2. Every listed file: present and byte-identical to its hash.
  const listed = Object.keys(manifest.files ?? {}).sort();
  for (const rel of listed) {
    let bytes: Buffer;
    try {
      bytes = await readFile(join(root, KARTS_DIR, rel));
    } catch {
      fail(`${KARTS_DIR}/${rel}: listed in the manifest but missing`);
      continue;
    }
    const actual = sha256(bytes);
    if (actual !== manifest.files[rel]) fail(`${KARTS_DIR}/${rel}: sha256 ${actual} but the manifest records ${manifest.files[rel]}`);
    if (rel.endsWith(".png")) {
      const size = pngSize(bytes);
      if (!size) fail(`${KARTS_DIR}/${rel}: not a PNG`);
      else if (size.width !== SHEET.width || size.height !== SHEET.height) {
        fail(`${KARTS_DIR}/${rel}: ${size.width}x${size.height}, the contract's sheet is ${SHEET.width}x${SHEET.height}`);
      }
    } else if (rel.endsWith("meta.json")) {
      try {
        const meta = JSON.parse(bytes.toString("utf8")) as { number?: Record<string, unknown[]>; body?: string };
        for (const camera of ["stall", "road"]) {
          const rects = meta.number?.[camera];
          if (!Array.isArray(rects) || rects.length !== 8) fail(`${KARTS_DIR}/${rel}: number.${camera} must hold 8 rects`);
        }
        if (meta.body !== rel.split("/")[0]) fail(`${KARTS_DIR}/${rel}: body "${meta.body}" does not match its directory`);
      } catch {
        fail(`${KARTS_DIR}/${rel}: not valid JSON`);
      }
    }
  }

  // 3. Every file on disk under a body directory: listed.
  const onDisk = await sheetFiles(root);
  for (const rel of onDisk) if (!(rel in manifest.files)) fail(`${KARTS_DIR}/${rel}: on disk but not in the manifest; it was not produced by npm run sprites`);

  // 4. Completeness: six bodies x (eight paints + meta.json).
  for (const body of BODIES) {
    for (const name of [...PAINT_NAMES.map((p) => `${p}.png`), "meta.json"]) {
      if (!listed.includes(`${body}/${name}`)) fail(`${KARTS_DIR}/${body}/${name}: not in the manifest`);
    }
  }
  if (manifest.bodies?.join(",") !== BODIES.join(",")) fail(`manifest bodies ${JSON.stringify(manifest.bodies)} are not ${JSON.stringify(BODIES)}`);
}

if (failures.length > 0) {
  console.error(`check:sprites FAILED (${failures.length}):`);
  for (const line of failures) console.error(`  ${line}`);
  process.exitCode = 1;
} else {
  const count = Object.keys(manifest!.files).length;
  console.log(
    `Sprite manifest check passed: ${count} files under ${KARTS_DIR}/ match ${MANIFEST}; paints match ui/Theme.qml; ` +
      `${BODIES.length} bodies x ${PAINT_NAMES.length} paints, every sheet ${SHEET.width}x${SHEET.height}.`,
  );
}
