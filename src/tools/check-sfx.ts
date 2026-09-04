// npm run check:sfx -- the committed sound cues against their manifest, and
// against the table the game actually plays them from.
//
// PIECE F. `src/tools/bake-sfx.py` synthesises one PCM WAV per cue of
// docs/design.md v4's Sound rows and writes assets/sfx/manifest.json with a
// SHA-256, a duration and a peak position for each. This check, which CI runs
// and which never rebakes, fails when:
//
//   * a listed file is missing, or its bytes differ from the recorded hash;
//   * a file exists under assets/sfx/ that the manifest does not list;
//   * a file is not a RIFF/WAVE of the declared rate, channel count and bit
//     depth, or is not the declared length;
//   * a cue is in `ui/parts/Sfx.qml`'s table with no file behind it, or a file
//     exists that no cue plays.
//
// THE LAST ONE IS THE POINT. "A sound for every event" is the piece's gate, and
// it is checkable rather than assertable: the game's cue table and the bake's
// catalogue are two lists in two languages, and this is what holds them equal.
//
// WHAT THIS CANNOT CHECK, said here rather than in a report. Nobody in the
// build loop can hear. Everything below is format, length, hash and routing. It
// is not evidence that any of these files sounds like a clang, a whoosh or a
// siren, and no test in this repository is.

import { readFile, readdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const SFX_DIR = "assets/sfx";
const MANIFEST = `${SFX_DIR}/manifest.json`;
const CUE_TABLE = "ui/parts/Sfx.qml";
const BAKE = "src/tools/bake-sfx.py";

type Manifest = {
  rate: number;
  channels: number;
  depth: number;
  files: Record<string, { sha256: string; ms: number; peak: number; shape: string }>;
};

const failures: string[] = [];
const fail = (message: string): void => {
  failures.push(message);
};

/** The fmt and data chunks of a RIFF/WAVE, or null when it is not one. */
function wavFacts(bytes: Buffer): { rate: number; channels: number; depth: number; ms: number } | null {
  if (bytes.length < 44) return null;
  if (bytes.subarray(0, 4).toString("latin1") !== "RIFF") return null;
  if (bytes.subarray(8, 12).toString("latin1") !== "WAVE") return null;
  let at = 12;
  let channels = 0;
  let rate = 0;
  let depth = 0;
  let dataBytes = 0;
  while (at + 8 <= bytes.length) {
    const id = bytes.subarray(at, at + 4).toString("latin1");
    const size = bytes.readUInt32LE(at + 4);
    if (id === "fmt " && at + 8 + 16 <= bytes.length) {
      channels = bytes.readUInt16LE(at + 10);
      rate = bytes.readUInt32LE(at + 12);
      depth = bytes.readUInt16LE(at + 22);
    } else if (id === "data") {
      dataBytes = size;
    }
    at += 8 + size + (size % 2);
  }
  if (!rate || !channels || !depth) return null;
  return { rate, channels, depth, ms: Math.round((dataBytes / (channels * (depth / 8))) / rate * 1000) };
}

/** The cue names `ui/parts/Sfx.qml` routes to, read off its table. */
function cuesInTheGame(source: string): string[] {
  const table = source.match(/readonly property var cues:\s*\(\{([\s\S]*?)\}\)/);
  if (!table) {
    fail(`${CUE_TABLE}: the cue table could not be found; this check reads it rather than restating it`);
    return [];
  }
  return [...table[1]!.matchAll(/"([a-z0-9-]+)"\s*:\s*"([a-z0-9-]+)"/g)].map((m) => m[2]!);
}

/** The cue names `src/tools/bake-sfx.py` bakes, read off its catalogue. */
function cuesInTheBake(source: string): string[] {
  const table = source.match(/^CUES = \[([\s\S]*?)^\]/m);
  if (!table) {
    fail(`${BAKE}: the CUES catalogue could not be found`);
    return [];
  }
  return [...table[1]!.matchAll(/^\s*\("([a-z0-9-]+)",/gm)].map((m) => m[1]!);
}

let manifest: Manifest | null = null;
try {
  manifest = JSON.parse(await readFile(join(root, MANIFEST), "utf8")) as Manifest;
} catch (error) {
  fail(`${MANIFEST}: cannot read (${error instanceof Error ? error.message : String(error)}); run npm run sfx`);
}

const checked: string[] = [];

if (manifest) {
  const listed = Object.keys(manifest.files).sort();
  for (const name of listed) {
    const declared = manifest.files[name]!;
    let bytes: Buffer;
    try {
      bytes = await readFile(join(root, SFX_DIR, name));
    } catch {
      fail(`${SFX_DIR}/${name}: listed in the manifest but missing`);
      continue;
    }
    const digest = createHash("sha256").update(bytes).digest("hex");
    if (digest !== declared.sha256)
      fail(`${SFX_DIR}/${name}: sha256 ${digest} but the manifest records ${declared.sha256}`);
    const facts = wavFacts(bytes);
    if (!facts) {
      fail(`${SFX_DIR}/${name}: not a RIFF/WAVE with a readable fmt chunk`);
      continue;
    }
    if (facts.rate !== manifest.rate || facts.channels !== manifest.channels || facts.depth !== manifest.depth)
      fail(
        `${SFX_DIR}/${name}: ${facts.channels}ch ${facts.rate} Hz ${facts.depth}-bit, `
        + `the manifest declares ${manifest.channels}ch ${manifest.rate} Hz ${manifest.depth}-bit`,
      );
    if (Math.abs(facts.ms - declared.ms) > 2)
      fail(`${SFX_DIR}/${name}: ${facts.ms} ms of audio, the manifest records ${declared.ms} ms`);
    checked.push(
      `${name.padEnd(20)} ${String(facts.ms).padStart(5)} ms  ${facts.channels}ch ${facts.rate} Hz `
      + `${facts.depth}-bit  peak at ${declared.peak.toFixed(2)}  ${declared.shape}`,
    );
  }

  const onDisk = (await readdir(join(root, SFX_DIR))).filter(
    (name) => name !== "manifest.json" && name !== ".gitkeep",
  );
  for (const name of onDisk)
    if (!(name in manifest.files))
      fail(`${SFX_DIR}/${name}: on disk but not in the manifest; it was not produced by npm run sfx`);

  // The two lists that have to be equal, and the reason this file exists.
  const game = cuesInTheGame(await readFile(join(root, CUE_TABLE), "utf8"));
  const bake = cuesInTheBake(await readFile(join(root, BAKE), "utf8"));
  for (const cue of game) {
    if (!(`${cue}.wav` in manifest.files))
      fail(`${CUE_TABLE} plays the cue "${cue}" and ${SFX_DIR}/${cue}.wav does not exist`);
    if (!bake.includes(cue))
      fail(`${CUE_TABLE} plays the cue "${cue}" and ${BAKE} does not bake it`);
  }
  for (const cue of bake)
    if (!game.includes(cue))
      fail(`${BAKE} bakes "${cue}" and nothing in ${CUE_TABLE} ever plays it`);

  if (!failures.length) {
    console.log("Sound-cue check passed.");
    console.log(`  ${listed.length} cue file(s), every one a PCM WAV of the declared format and length:`);
    for (const line of checked) console.log(`    ${line}`);
    console.log(
      `  routing: the ${game.length} cue(s) ${CUE_TABLE} plays and the ${bake.length} ${BAKE} bakes are the same list`,
    );
    console.log(
      "  NOT CHECKED, and it cannot be: whether any of these sounds like what its shape says. "
      + "Nobody in the build loop can hear, and this tool measures bytes, format, length and routing only.",
    );
  }
}

if (failures.length) {
  console.error(failures.join("\n"));
  console.error(`\nSound-cue check failed with ${failures.length} problem(s).`);
  process.exitCode = 1;
}
