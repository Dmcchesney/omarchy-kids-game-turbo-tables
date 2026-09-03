// Three checks, one command.
//
// 1. Layer boundary. Only the layer 3 files -- TurboTables.qml, BarWidget.qml
//    and shell/ -- may touch the shell or the outside world. Round 2 of the
//    package review put `screens/Garage.qml` in the tree, holding Quickshell.Io,
//    a FileView and an XMLHttpRequest, and this check never looked at it: it
//    grepped `src/` and `ui/` and nothing else. The scope is inverted now. Every
//    file is grepped except the three layer 3 locations and the allow-list in
//    scope.ts, so a directory nobody has thought of yet is in scope by default.
//
// 2. File hygiene the marketplace and omarchy plugin validate care about:
//    no symlinks, nothing executable, no installer-like or bin/scripts paths,
//    no unexpected binary, and never a node_modules inside the checkout.
//
// 3. manifest.json, field by field, against the marketplace's own validator
//    rules and the required root README and licence file.

import { access, lstat, readFile, readdir } from "node:fs/promises";
import { basename, extname, join, relative, resolve } from "node:path";
import { NOT_THE_PLUGIN, NOT_WALKED, fold, glue, isPluginFile } from "./scope.ts";

const root = resolve(import.meta.dirname, "../..");
const ignored = new Set(NOT_WALKED.map((entry) => entry.match.replace(/\/$/, "")));
const forbiddenDirectoryNames = new Set(["bin", "scripts"]);
const forbiddenFileName = /^(?:install|installer|setup|uninstall)(?:\.|$)/i;
// Round 4 of the package review renamed a 4 KB ELF binary to
// `assets/karts/skin-pack.png` and walked it past all three gates, while the
// same bytes named `.bin` were caught -- because the magic-number test was
// skipped for precisely the three extensions the allowance is written for. The
// extension was trusted instead of the content, so the stated rule ("no bundled
// binaries beyond PNG, WAV and .qsb") was implemented as "no bundled binaries
// beyond files *named* .png, .wav or .qsb".
//
// Every file is opened and its first bytes read now. A file claiming one of the
// three allowed types has to actually be one; anything else may not begin with
// an executable header.
const executableMagic: { magic: Buffer; what: string }[] = [
  { magic: Buffer.from([0x7f, 0x45, 0x4c, 0x46]), what: "ELF" },
  { magic: Buffer.from([0x4d, 0x5a]), what: "PE/COFF (MZ)" },
  { magic: Buffer.from([0xcf, 0xfa, 0xed, 0xfe]), what: "Mach-O 64-bit" },
  { magic: Buffer.from([0xfe, 0xed, 0xfa, 0xcf]), what: "Mach-O 64-bit, big-endian" },
  { magic: Buffer.from([0xce, 0xfa, 0xed, 0xfe]), what: "Mach-O 32-bit" },
  { magic: Buffer.from([0xca, 0xfe, 0xba, 0xbe]), what: "Mach-O universal / Java class" },
  { magic: Buffer.from("#!"), what: "a script with a shebang" },
];

/**
 * The three binary types this repository may ship, each with the header the
 * file has to actually start with. The `.qsb` prefix is the header Qt 6's `qsb`
 * writes, read back from `shaders/road.frag.qsb` -- the only one in the tree,
 * produced by the Homebrew Qt 6 toolchain docs/environment.md names.
 */
const allowedBinaryTypes: { extension: string; what: string; ok: (bytes: Buffer) => boolean }[] = [
  {
    extension: ".png",
    what: "the 8-byte PNG signature 89 50 4E 47 0D 0A 1A 0A",
    ok: (bytes) => bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  },
  {
    extension: ".wav",
    what: "a RIFF/WAVE header",
    ok: (bytes) =>
      bytes.subarray(0, 4).toString("latin1") === "RIFF" && bytes.subarray(8, 12).toString("latin1") === "WAVE",
  },
  {
    extension: ".qsb",
    what: "the QSB header 00 00 98 3E",
    ok: (bytes) => bytes.subarray(0, 4).equals(Buffer.from([0x00, 0x00, 0x98, 0x3e])),
  },
];
const allowedBinaryExtensions = new Set(allowedBinaryTypes.map((type) => type.extension));

// The only places a shell token is allowed. Everything else in the repository
// is grepped, except the files scope.ts says are not the plugin at all.
const layerThree = ["TurboTables.qml", "BarWidget.qml", "shell/"];

// Where a binary asset is allowed to live. docs/plan.md's repository layout
// puts sprite sheets and sounds under assets/, the baked shader under shaders/,
// and one preview at the root, so those are the three places a PNG, WAV or
// .qsb belongs. Anywhere else -- notably inside ui/ or src/ -- a binary is
// somewhere code is read from, which is what the rule is actually guarding
// against, so it still fails there.
const binaryHomes = ["assets/", "shaders/", "docs/", "preview.png"];

function inABinaryHome(display: string): boolean {
  return binaryHomes.some((where) =>
    where.endsWith("/") ? display.startsWith(where) : display === where,
  );
}

// The tokens the plan names. Each is matched literally, case sensitively.
// `Process` is deliberately capitalised so Node's lowercase `process` object,
// which layer 1 tooling legitimately uses, is not a hit.
const forbiddenImports = [
  "Quickshell",
  "qs.",
  "Process",
  "FileView",
  "XMLHttpRequest",
  "Qt.labs",
];

// The check tools name the tokens for a living; they are covered by the
// `src/tools/` entry of scope.ts's allow-list, which is printed on every run of
// check:readme. Listed here too so the exemption is visible from this file.
const importGrepExemptions = new Set([
  "src/tools/check-boundary.ts",
  "src/tools/check-readme.ts",
  "src/tools/scope.ts",
]);

const failures: string[] = [];
let filesWalked = 0;
let filesGrepped = 0;
let filesTyped = 0;

/** Everything is held to the layer boundary except layer 3 and the allow-list. */
function withinLayerBoundary(display: string): boolean {
  if (layerThree.some((where) => (where.endsWith("/") ? display.startsWith(where) : display === where)))
    return false;
  return isPluginFile(display);
}

function grepImports(display: string, contents: string): void {
  if (importGrepExemptions.has(display)) return;
  filesGrepped += 1;
  const lines = contents.split(/\r?\n/);
  for (const [index, line] of lines.entries()) {
    // Round 3 spelled `XMLHttpRequest` out one character at a time in an array
    // literal and reached it with `.join("")`, and this grep -- a literal
    // `includes` -- scored zero hits on a plain plugin .qml file. Every line is
    // read twice now: as written, and with string concatenations and
    // array-assembled strings glued back into the strings they spell.
    const glued = glue(line);
    for (const token of forbiddenImports) {
      const literal = line.includes(token);
      if (!literal && !glued.includes(token)) continue;
      failures.push(
        `${display}:${index + 1}: layer boundary: "${token}"${literal ? "" : ", assembled from string fragments,"} is only allowed in TurboTables.qml, BarWidget.qml and shell/ -- ${line.trim().slice(0, 160)}`,
      );
    }
  }
  // And once over the whole file with its own single-assignment string
  // constants substituted in first, so a token split across two variables --
  // round 4's `var head = "../de"; var tail = "v/collect.mjs"` -- is read as the
  // string the two of them spell.
  const folded = fold(contents);
  for (const token of forbiddenImports) {
    if (contents.includes(token) || !folded.includes(token)) continue;
    failures.push(
      `${display}: layer boundary: "${token}", spelled by string constants this file binds once and joins, is only allowed in TurboTables.qml, BarWidget.qml and shell/`,
    );
  }
}

async function walk(directory: string): Promise<void> {
  for (const name of await readdir(directory)) {
    if (ignored.has(name)) continue;
    const path = join(directory, name);
    const display = relative(root, path);
    const stat = await lstat(path);

    if (stat.isSymbolicLink()) {
      failures.push(`${display}: symlink`);
      continue;
    }

    if (stat.isDirectory()) {
      if (forbiddenDirectoryNames.has(name.toLowerCase()))
        failures.push(`${display}: forbidden directory`);
      await walk(path);
      continue;
    }

    filesWalked += 1;

    if (forbiddenFileName.test(basename(path)))
      failures.push(`${display}: forbidden installer-like filename`);
    if ((stat.mode & 0o111) !== 0)
      failures.push(`${display}: executable bit set`);

    // Every file is read. No extension is trusted.
    const contents = await readFile(path);
    filesTyped += 1;
    const extension = extname(name).toLowerCase();
    const declaredType = allowedBinaryTypes.find((type) => type.extension === extension);

    const header = executableMagic.find((entry) =>
      contents.subarray(0, entry.magic.length).equals(entry.magic),
    );
    if (header) {
      failures.push(`${display}: executable binary (${header.what} header)`);
      continue;
    }

    if (declaredType) {
      if (!declaredType.ok(contents))
        failures.push(
          `${display}: the name says ${declaredType.extension} but the bytes are not: this file does not start with ${declaredType.what}.`
          + ` The binary allowance is for PNG, WAV and .qsb content, not for those three filename endings.`,
        );
      if (withinLayerBoundary(display) && !inABinaryHome(display))
        failures.push(`${display}: binary asset outside assets/, shaders/, docs/ and the root preview`);
      continue;
    }

    if (contents.includes(0)) {
      failures.push(
        `${display}: binary content in a file that is not a .png, .wav or .qsb. Those three are the whole binary allowance, by content and not by name.`,
      );
      continue;
    }

    if (withinLayerBoundary(display)) grepImports(display, contents.toString("utf8"));
  }
}

// --- 3. manifest ------------------------------------------------------------
//
// The same rules the marketplace applies in scripts/build-catalog.mjs
// (validateManifest, validateManifestFiles, validateRepositoryDocs) at the
// pinned commit, plus the id form the marketplace recommends. That module
// cannot simply be imported: it pulls in `sharp` at the top for preview
// resizing, and nothing may be installed into this checkout. So the rules are
// restated here, each one labelled with the rule it mirrors, and the pinned
// source is the reference to re-read when the marketplace moves.

const manifestFieldLimits: Record<string, number> = {
  id: 128,
  name: 120,
  version: 64,
  author: 120,
  description: 500,
  license: 120,
};
const supportedKinds = new Set(["bar", "bar-widget", "menu", "overlay", "panel", "service"]);
const entryPointKey = (kind: string) => (kind === "bar-widget" ? "barWidget" : kind);
const controlCharacters = /[\u0000-\u001f\u007f-\u009f]/u;
const manifestRules: string[] = [];

function rule(name: string, ok: boolean, detail: string): void {
  manifestRules.push(`${ok ? "ok  " : "FAIL"}  ${name}: ${detail}`);
  if (!ok) failures.push(`manifest.json: ${name}: ${detail}`);
}

async function isRegularFile(path: string): Promise<boolean> {
  try {
    return (await lstat(path)).isFile();
  } catch {
    return false;
  }
}

async function checkManifest(): Promise<void> {
  const raw = await readFile(join(root, "manifest.json"), "utf8");
  const manifest = JSON.parse(raw) as Record<string, any>;

  rule("schemaVersion is the number 1", manifest.schemaVersion === 1, JSON.stringify(manifest.schemaVersion));

  for (const field of ["id", "name", "version", "author", "description"]) {
    const value = manifest[field];
    const present = typeof value === "string" && value.trim().length > 0;
    const clean = present && !controlCharacters.test(value.trim());
    const short = present && value.trim().length <= manifestFieldLimits[field]!;
    rule(
      `${field} is a non-empty string, free of control characters, at most ${manifestFieldLimits[field]} characters`,
      present && clean && short,
      present ? `${JSON.stringify(value)} (${value.length})` : "missing",
    );
  }
  rule("id has no leading or trailing whitespace", manifest.id === String(manifest.id).trim(), JSON.stringify(manifest.id));
  rule(
    "license, if present, is a non-empty string within 120 characters",
    manifest.license === undefined
      || (typeof manifest.license === "string"
        && manifest.license.trim().length > 0
        && manifest.license.trim().length <= manifestFieldLimits.license!
        && !controlCharacters.test(manifest.license)),
    JSON.stringify(manifest.license),
  );
  rule(
    "id matches ^[A-Za-z0-9][A-Za-z0-9._-]*$ and contains no ..",
    /^[a-z0-9][a-z0-9._-]*$/i.test(manifest.id) && !String(manifest.id).includes(".."),
    JSON.stringify(manifest.id),
  );
  rule("id is lowercase (required of community plugins)", manifest.id === String(manifest.id).toLowerCase(), JSON.stringify(manifest.id));
  rule(
    "id is not in the reserved omarchy.* namespace",
    !String(manifest.id).toLowerCase().startsWith("omarchy."),
    JSON.stringify(manifest.id),
  );
  rule(
    "id uses the recommended io.github.<owner>.<name> form",
    /^io\.github\.[a-z0-9][a-z0-9._-]*\.[a-z0-9][a-z0-9._-]*$/.test(manifest.id),
    JSON.stringify(manifest.id),
  );
  rule(
    "kinds is a non-empty array of supported kinds",
    Array.isArray(manifest.kinds)
      && manifest.kinds.length > 0
      && manifest.kinds.every((kind: unknown) => typeof kind === "string" && supportedKinds.has(kind)),
    JSON.stringify(manifest.kinds),
  );
  const entryPoints = manifest.entryPoints;
  const entryPointsIsObject = Boolean(entryPoints) && typeof entryPoints === "object" && !Array.isArray(entryPoints);
  rule("entryPoints is an object", entryPointsIsObject, JSON.stringify(entryPoints));

  if (entryPointsIsObject && Array.isArray(manifest.kinds)) {
    for (const kind of manifest.kinds) {
      const key = entryPointKey(String(kind));
      rule(`every declared kind has its entry point (${kind} -> ${key})`, Object.hasOwn(entryPoints, key), JSON.stringify(entryPoints[key]));
    }
    const paths: unknown[] = Object.values(entryPoints);
    rule("entryPoints is not empty", paths.length > 0, `${paths.length} entry point(s)`);
    for (const path of paths) {
      const safe = typeof path === "string"
        && path.trim().length > 0
        && !path.startsWith("/")
        && !path.includes("..")
        && !/[\\:\r\n\0]/.test(path);
      rule("entry point is a safe relative path", safe, JSON.stringify(path));
      if (typeof path === "string") {
        rule(
          "entry point exists as a regular file, not a symlink",
          await isRegularFile(join(root, path)),
          path,
        );
      }
    }
  }
  const barWidget = manifest.barWidget;
  if (barWidget && typeof barWidget === "object" && Object.hasOwn(barWidget, "defaultSection")) {
    rule(
      "barWidget.defaultSection is left, center, or right",
      ["left", "center", "right"].includes(barWidget.defaultSection),
      JSON.stringify(barWidget.defaultSection),
    );
  }
  const rootNames = await readdir(root);
  rule(
    "a root README file exists",
    rootNames.some((name) => /^readme(?:\.[^/]+)?$/i.test(name)),
    rootNames.filter((name) => /^readme(?:\.[^/]+)?$/i.test(name)).join(", ") || "none",
  );
  rule(
    "a root license file exists",
    rootNames.some((name) => /^(?:licen[cs]e|copying)(?:\.[^/]+)?$/i.test(name)),
    rootNames.filter((name) => /^(?:licen[cs]e|copying)(?:\.[^/]+)?$/i.test(name)).join(", ") || "none",
  );
}

try {
  await access(join(root, "node_modules"));
  failures.push("node_modules: must never exist inside the plugin checkout (its symlinks fail omarchy plugin validate); tools run through npx");
} catch {}

await walk(root);
await checkManifest();

if (failures.length) {
  console.error(failures.join("\n"));
  console.error(`\nBoundary check failed with ${failures.length} problem(s).`);
  process.exitCode = 1;
} else {
  console.log("Boundary check passed.");
  console.log(
    `  hygiene: ${filesWalked} files, no symlinks, no executable bits, no installer-like names, no bin/ or scripts/ directory, no node_modules`,
  );
  console.log(
    `  content types: ${filesTyped} files opened and their first bytes read -- no extension is trusted. The only binary content allowed is `
    + allowedBinaryTypes.map((type) => `${type.extension} (${type.what})`).join(", ")
    + `, and a file named for one of those has to be one.`,
  );
  console.log(
    `  layer imports: ${filesGrepped} files grepped for ${forbiddenImports.map((token) => JSON.stringify(token)).join(", ")} with 0 hits -- every file in the repository except the three that may hold one (${layerThree.join(", ")}) and the allow-list below`,
  );
  for (const entry of NOT_THE_PLUGIN) console.log(`    not the plugin: ${entry.match}`);
  console.log("  not walked at all (the same list scope.ts prints, with its reasons):");
  for (const entry of NOT_WALKED) console.log(`    not walked:     ${entry.match.padEnd(16)} ${entry.why}`);
  console.log(
    `  also exempt: ${[...importGrepExemptions].join(", ")} (they are the files that list the tokens)`,
  );
  console.log(`  manifest: ${manifestRules.length} validator rules, all satisfied`);
  for (const line of manifestRules) console.log(`    ${line}`);
}
