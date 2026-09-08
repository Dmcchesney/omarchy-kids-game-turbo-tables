// npm run check:props -- the committed prop kit against its manifest.
//
// assets/props/manifest.json is written by npm run props (bake-props.ts) and
// records a SHA-256 for every <name>.png and for props-meta.json. This check,
// which CI runs and which never rebakes (Blender lives only on the Mac), fails
// when a listed file is missing or differs from its hash; when a file exists
// under assets/props/ that the manifest does not list; when a prop in the meta
// has no sheet or a sheet has no meta; or when a sheet is not a PNG of the
// size the meta says. So a model change cannot land without its sheets, and a
// sheet cannot land without the model that made it.

import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { MANIFEST, META, PROPS_DIR, kitFiles, sha256, type Manifest, type PropMeta } from "./bake-props.ts";

const root = resolve(import.meta.dirname, "../..");
const failures: string[] = [];
const fail = (message: string): void => {
  failures.push(message);
};

function pngSize(bytes: Buffer): { width: number; height: number } | null {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature) || bytes.subarray(12, 16).toString("latin1") !== "IHDR") return null;
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

let manifest: Manifest | null = null;
let meta: PropMeta | null = null;
try {
  manifest = JSON.parse(await readFile(join(root, MANIFEST), "utf8")) as Manifest;
  meta = JSON.parse(await readFile(join(root, META), "utf8")) as PropMeta;
} catch (error) {
  fail(`${MANIFEST} / ${META}: cannot read (${error instanceof Error ? error.message : String(error)}); run npm run props on the Mac`);
}

if (manifest && meta) {
  const listed = Object.keys(manifest.files).sort();
  for (const rel of listed) {
    let bytes: Buffer;
    try {
      bytes = await readFile(join(root, PROPS_DIR, rel));
    } catch {
      fail(`${PROPS_DIR}/${rel}: listed in the manifest but missing`);
      continue;
    }
    const actual = sha256(bytes);
    if (actual !== manifest.files[rel]) fail(`${PROPS_DIR}/${rel}: sha256 ${actual} but the manifest records ${manifest.files[rel]}`);
    if (rel.endsWith(".png")) {
      const name = rel.slice(0, -4);
      const size = pngSize(bytes);
      const m = meta[name];
      if (!size) fail(`${PROPS_DIR}/${rel}: not a PNG`);
      else if (!m) fail(`${PROPS_DIR}/${rel}: no entry in props-meta.json`);
      else if (m.sheet && (size.width !== m.sheet[0] || size.height !== m.sheet[1])) {
        fail(`${PROPS_DIR}/${rel}: ${size.width}x${size.height}, the meta says ${m.sheet[0]}x${m.sheet[1]}`);
      }
    }
  }
  for (const rel of await kitFiles(root)) if (!(rel in manifest.files)) fail(`${PROPS_DIR}/${rel}: on disk but not in the manifest; it was not produced by npm run props`);
  for (const name of Object.keys(meta)) if (!listed.includes(`${name}.png`)) fail(`${PROPS_DIR}/${name}.png: in props-meta.json but not in the manifest`);
  if (manifest.props.join(",") !== Object.keys(meta).sort().join(",")) fail(`manifest props do not match props-meta.json`);
}

if (failures.length > 0) {
  console.error(`check:props FAILED (${failures.length}):`);
  for (const line of failures) console.error(`  ${line}`);
  process.exitCode = 1;
} else {
  console.log(`Prop manifest check passed: ${manifest!.props.length} props, ${Object.keys(manifest!.files).length} files under ${PROPS_DIR}/ match ${MANIFEST}.`);
}
