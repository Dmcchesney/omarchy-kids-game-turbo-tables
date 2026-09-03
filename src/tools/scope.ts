// What "the plugin" is, for every check in this repository.
//
// Round 2 of the package review broke the old answer. `check:readme` and
// `check:boundary` each carried their own list of directories that counted as
// the runtime -- six prefixes and three root files -- so a new directory was
// out of scope by default. A single file, `screens/Garage.qml`, holding a
// FileView, a TextInput, a `new Date()` and an XMLHttpRequest POST of a child's
// typed name to an external host, passed both checks and the marketplace
// scanner with the README untouched.
//
// The scope is therefore inverted here, once, for both tools:
//
//     every file in the repository is the plugin, unless it is named below.
//
// The allow-list is short, every entry says why, and every entry is printed on
// every run so a reviewer sees exactly what was not examined. A new directory,
// a new file type, a file nobody has thought of yet -- all in scope, no edit
// required.
//
// Two things the allow-list deliberately does *not* buy:
//
//   * QML is never exempt. `.qml` is the only language Omarchy executes, so
//     every .qml file in the repository -- including one under an allow-listed
//     path -- is held to the four safety invariants in check-readme.ts.
//   * Being in scope for the invariants is not the same as being usable as
//     *evidence*. Evidence is narrower still: see `strip()` below.

import { lstat, readFile, readdir } from "node:fs/promises";
import { extname, join, relative } from "node:path";

// ---------------------------------------------------------------------------
// The tree
// ---------------------------------------------------------------------------

/**
 * Directories the walk never descends into. Round 3 of the package review found
 * this list was a *second* allow-list -- undisclosed, unreasoned, and one that
 * even a `.qml` file could hide behind, which is the single exemption the design
 * says it never grants. It is now shaped like the main allow-list, carries a
 * reason per entry, is printed by both tools on every run, and `check:readme`
 * fails if any `.qml` file is found under one of them.
 */
export const NOT_WALKED: Exemption[] = [
  { match: ".git/", why: "git's own object store; not files anybody wrote" },
  { match: "node_modules/", why: "must never exist here at all; check:boundary fails outright if it does" },
  { match: "coverage/", why: "generated coverage output, git-ignored, never committed" },
  { match: "evidence/", why: "generated review evidence, git-ignored, never committed" },
  {
    match: ".DS_Store",
    why: "macOS Finder metadata; git-ignored, never committed, and never cloned onto a child's machine -- listed since round 5, when check:boundary started reading every file's bytes and found three of them",
  },
];

const NOT_WALKED_NAMES = new Set(NOT_WALKED.map((entry) => entry.match.replace(/\/$/, "")));

/** Every `.qml` file hiding under a not-walked directory. Should always be empty. */
export async function qmlOutsideTheWalk(root: string): Promise<string[]> {
  const found: string[] = [];
  async function walk(directory: string): Promise<void> {
    let names: string[];
    try {
      names = await readdir(directory);
    } catch {
      return;
    }
    for (const name of names) {
      const absolute = join(directory, name);
      let stat;
      try {
        stat = await lstat(absolute);
      } catch {
        continue;
      }
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) await walk(absolute);
      else if (isQml(name)) found.push(relative(root, absolute));
    }
  }
  for (const name of NOT_WALKED_NAMES) await walk(join(root, name));
  return found.sort();
}

export type TreeFile = {
  /** Repository-relative, forward slashes. */
  path: string;
  /** "" when the file is binary. */
  text: string;
  binary: boolean;
};

export type Tree = {
  files: TreeFile[];
  /** Every path in the repository, files and `directory/` entries alike. */
  paths: Set<string>;
  /** Directory path (with trailing slash) -> the names directly inside it. */
  directories: Map<string, string[]>;
};

export async function walkTree(root: string): Promise<Tree> {
  const files: TreeFile[] = [];
  const paths = new Set<string>();
  const directories = new Map<string, string[]>();

  async function walk(directory: string): Promise<void> {
    const names = (await readdir(directory)).sort();
    const display = directory === root ? "" : `${relative(root, directory)}/`;
    directories.set(display, names.filter((name) => !NOT_WALKED_NAMES.has(name)));
    for (const name of names) {
      if (NOT_WALKED_NAMES.has(name)) continue;
      const absolute = join(directory, name);
      const shown = relative(root, absolute);
      const stat = await lstat(absolute);
      if (stat.isSymbolicLink()) continue; // check:boundary fails on these
      if (stat.isDirectory()) {
        paths.add(`${shown}/`);
        await walk(absolute);
        continue;
      }
      paths.add(shown);
      const bytes = await readFile(absolute);
      const binary = bytes.includes(0);
      files.push({ path: shown, text: binary ? "" : bytes.toString("utf8"), binary });
    }
  }

  await walk(root);
  return { files, paths, directories };
}

// ---------------------------------------------------------------------------
// The allow-list: what is in the repository but is not the plugin
// ---------------------------------------------------------------------------

export type Exemption = {
  /** A path ending in "/" is a prefix; anything else is one exact path. */
  match: string;
  why: string;
};

export const NOT_THE_PLUGIN: Exemption[] = [
  {
    match: "docs/",
    why: "the settled design and the build plan; they describe the finished game in the present tense on purpose and Omarchy never loads them",
  },
  {
    match: ".claude/",
    why: "the development workflow skill; text only, never loaded by the shell (NOTICE explains why it ships)",
  },
  {
    match: ".github/",
    why: "CI configuration; it runs on GitHub's runners, never in a child's session",
  },
  {
    match: "src/tools/",
    why: "the maintainer's own check tooling; run by npm run check under Node, never loaded by Quickshell -- and these are the files that list the forbidden tokens",
  },
  {
    match: "tests/",
    why: "node:test and qmltestrunner suites; not reachable from any manifest entry point",
  },
  {
    match: "dev/",
    why: "the layer-2 harness and its qs.* mocks; run by `qml -I dev/imports` on the maintainer's machine, never by Omarchy (its .qml files are still held to the four invariants)",
  },
  { match: "esbuild.config.mjs", why: "the bundler that produces engine/engine.mjs; a build tool" },
  { match: "package.json", why: "npm scripts; not code the shell loads" },
  { match: "tsconfig.json", why: "compiler configuration" },
  { match: ".gitignore", why: "git configuration" },
  { match: "README.md", why: "the document under test; treating it as evidence for itself is the circularity round 2 broke" },
  { match: "NOTICE", why: "attribution prose" },
  { match: "LICENSE", why: "licence text" },
];

/** True when the file is part of the plugin Omarchy loads onto a child's machine. */
export function isPluginFile(path: string): boolean {
  return !NOT_THE_PLUGIN.some((entry) =>
    entry.match.endsWith("/") ? path.startsWith(entry.match) : path === entry.match,
  );
}

export function isQml(path: string): boolean {
  return path.toLowerCase().endsWith(".qml");
}

/**
 * Scope for the four safety invariants: the plugin, plus every .qml file
 * anywhere. QML only ever runs inside a Qt session, so a text field or a
 * network call in one is a defect wherever it sits.
 */
export function underInvariants(file: TreeFile): boolean {
  if (file.binary) return false;
  return isPluginFile(file.path) || isQml(file.path);
}

/**
 * Scope for evidence that a capability exists: plugin files that are source
 * code. A `.md`, a `.txt`, a `.gitkeep` or a `.json` cannot implement anything,
 * so none of them may back a README claim.
 */
const CODE_EXTENSIONS = new Set([".qml", ".js", ".mjs", ".ts", ".mts", ".frag", ".vert", ".glsl"]);

/**
 * The languages a Qt/QML session can actually load and run off disk. Round 4 of
 * the package review found the shape rules in check-readme.ts scoped to `.qml`
 * alone, and pointed out that `.js` is the format QML imports its libraries from
 * -- `import "wire.js" as Wire` -- so every shape rule skipped the one file type
 * an attacker would reach for. Scope for those rules is this set now, not `.qml`.
 *
 * `.ts` is deliberately outside it: Qt cannot load TypeScript, and this
 * repository's own `.ts` under `src/engine` is compiled to `engine/engine.mjs`,
 * which *is* in the set and is checked here like any other runtime file.
 */
const RUNTIME_LANGUAGES = new Set([".qml", ".js", ".mjs"]);

/** True when Omarchy could load this file as code: a plugin file in a runtime language. */
export function isRuntimeCode(path: string): boolean {
  return isPluginFile(path) && RUNTIME_LANGUAGES.has(extname(path).toLowerCase());
}

export function isEvidenceFile(file: TreeFile): boolean {
  if (file.binary) return false;
  if (!isPluginFile(file.path)) return false;
  return CODE_EXTENSIONS.has(extname(file.path).toLowerCase());
}

// ---------------------------------------------------------------------------
// Comments and string literals are not code
// ---------------------------------------------------------------------------

/**
 * Blank out line comments, block comments and the contents of string literals,
 * preserving every byte offset and newline so line numbers still line up.
 *
 * This is the fix for the second round-2 defect: a file containing nothing but
 *
 *     // TODO(M4): the sound component will be a SoundEffect behind a loader.
 *
 * was accepted as proof that an audio loader existed, because the old `hits()`
 * was `line.includes(token)`. After stripping, that file contributes nothing.
 */
export function strip(text: string): string {
  return blankOut(text, true);
}

/**
 * Comments only. A path inside a string literal is a real reference -- round 3's
 * own probe hid `"dev/collect.mjs"` in one -- so the allow-list reachability
 * check keeps strings and drops only the commentary.
 */
export function stripComments(text: string): string {
  return blankOut(text, false);
}

function blankOut(text: string, alsoStrings: boolean): string {
  const out = text.split("");
  const blank = (from: number, to: number) => {
    for (let i = from; i < to && i < out.length; i++) if (out[i] !== "\n") out[i] = " ";
  };
  let i = 0;
  while (i < text.length) {
    const two = text.slice(i, i + 2);
    if (two === "//") {
      let end = text.indexOf("\n", i);
      if (end === -1) end = text.length;
      blank(i, end);
      i = end;
      continue;
    }
    if (two === "/*") {
      let end = text.indexOf("*/", i + 2);
      end = end === -1 ? text.length : end + 2;
      blank(i, end);
      i = end;
      continue;
    }
    const quote = text[i]!;
    if (alsoStrings && (quote === '"' || quote === "'" || quote === "`")) {
      let j = i + 1;
      while (j < text.length) {
        if (text[j] === "\\") {
          j += 2;
          continue;
        }
        if (text[j] === quote) break;
        j += 1;
      }
      blank(i + 1, Math.min(j, text.length)); // keep the quotes, drop the contents
      i = Math.min(j + 1, text.length);
      continue;
    }
    i += 1;
  }
  return out.join("");
}

/**
 * An array literal built only out of string pieces. Round 3 assembled
 * `XMLHttpRequest`, `https://`, `toISOString` and `POST` out of
 * `["X","M","L",...]` arrays and reached them with `.join("")` on another line,
 * and all three gates scored zero hits: a comma is not a plus, so `glue()` never
 * saw it. Any such array is now read as the string it spells, whether or not the
 * `.join("")` is on the same line -- there is no honest reason to spell an
 * identifier one character at a time in this repository.
 */
const ARRAY_OF_STRINGS =
  /\[\s*((?:(['"`])(?:\\.|(?!\2)[^\\])*\2\s*,\s*)+(['"`])(?:\\.|(?!\3)[^\\])*\3)\s*,?\s*\]/g;

/**
 * Glue string literals back together so an assembled string is scanned as the
 * string it assembles: `"htt" + "ps://telemetry.example.com"`,
 * `globalThis["XML" + "HttpRequest"]`, and `["a","b"].join("")` alike. Round 2
 * got the first two past the gate; round 3 got the third.
 */
export function glue(text: string): string {
  let out = text;
  for (let pass = 0; pass < 6; pass++) {
    const next = out
      .replace(ARRAY_OF_STRINGS, (_match, items: string) => JSON.stringify(pieces(items).join("")))
      .replace(/(["'`])\s*\+\s*(["'`])/g, "");
    if (next === out) break;
    out = next;
  }
  return out;
}

/** Every string literal inside an array literal, unescaped, in order. */
function pieces(items: string): string[] {
  return [...items.matchAll(/(['"`])((?:\\.|(?!\1)[^\\])*)\1/g)].map((match) =>
    match[2]!.replace(/\\(.)/g, "$1"),
  );
}

/**
 * A name bound exactly once, in this file, to a string literal. Round 4 of the
 * package review reached the allow-list with two of them --
 *
 *     var head = "../de"; var tail = "v/collect.mjs"; import(head + tail)
 *
 * -- and `glue()` saw nothing, because `head + tail` are identifiers and glue()
 * only joins adjacent *literals*. A name bound once to a literal and never
 * reassigned is that literal, so `fold()` substitutes it before gluing.
 */
const STRING_CONSTANT = new RegExp(
  "(?:^|[;{}(,\\n])\\s*(?:"
  + "(?:readonly\\s+)?property\\s+(?:string|url|var)\\s+([A-Za-z_$][\\w$]*)\\s*:"
  + "|(?:var|let|const)\\s+([A-Za-z_$][\\w$]*)\\s*="
  + ")\\s*(['\"`])((?:\\\\.|(?!\\3)[^\\\\])*)\\3",
  "g",
);

/** Every name this file binds exactly once to a string literal, and to what. */
export function stringConstants(text: string): Map<string, string> {
  const bound = new Map<string, string>();
  const rejected = new Set<string>();
  for (const match of text.matchAll(STRING_CONSTANT)) {
    const name = (match[1] ?? match[2])!;
    const value = match[4]!.replace(/\\(.)/g, "$1");
    if (bound.has(name) && bound.get(name) !== value) rejected.add(name);
    bound.set(name, value);
  }
  for (const name of [...bound.keys()]) {
    // Bound more than once, anywhere, by any syntax: not a constant.
    const assignments = text.match(new RegExp(`\\b${name}\\s*(?::|=(?!=))`, "g")) ?? [];
    if (assignments.length > 1) rejected.add(name);
  }
  for (const name of rejected) bound.delete(name);
  return bound;
}

/**
 * `glue()`, plus the file's own single-assignment string constants substituted
 * first, so a path split across two variables is read as the path it spells.
 * Deliberately generous about the left-hand side of a dotted reference
 * (`parent.base` folds as `base` does): over-folding can only turn into a
 * failure when the folded text spells a path this repository forbids, and no
 * honest file in it spells one.
 */
export function fold(text: string): string {
  let out = text;
  for (const [name, value] of stringConstants(text))
    out = out.replace(
      new RegExp(`(?<![\\w$])(?:[\\w$]+\\s*\\.\\s*)?${name}(?![\\w$])`, "g"),
      () => JSON.stringify(value),
    );
  return glue(out);
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

/**
 * A literal token, matched with identifier boundaries so `Process` does not
 * fire on `Processing` and `Date.parse(` does not fire on `myDate.parse(`.
 */
export function tokenPattern(token: string): RegExp {
  const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const left = /^[A-Za-z0-9_]/.test(token) ? "(?<![A-Za-z0-9_$])" : "";
  const right = /[A-Za-z0-9_]$/.test(token) ? "(?![A-Za-z0-9_$])" : "";
  return new RegExp(`${left}${escaped}${right}`);
}

export type Hit = { path: string; line: number; how: string; excerpt: string };

export type ScanMode =
  /** Comments and string bodies removed: this is what counts as *evidence*. */
  | "code"
  /** Everything, plus glued string concatenations: this is what a *promise of absence* is held to. */
  | "any";

/** Every place `token` appears in `file`, under the given reading of the file. */
export function findToken(file: TreeFile, token: string, mode: ScanMode): Hit[] {
  const pattern = tokenPattern(token);
  const found: Hit[] = [];
  const source = mode === "code" ? strip(file.text) : file.text;
  const lines = source.split(/\r?\n/);
  const raw = file.text.split(/\r?\n/);
  for (const [index, line] of lines.entries()) {
    if (pattern.test(line)) {
      found.push({ path: file.path, line: index + 1, how: mode === "code" ? "in code" : "present", excerpt: (raw[index] ?? "").trim().slice(0, 120) });
      continue;
    }
    if (mode === "any" && pattern.test(glue(line)))
      found.push({ path: file.path, line: index + 1, how: "assembled from string fragments", excerpt: (raw[index] ?? "").trim().slice(0, 120) });
  }
  if (mode === "any" && found.length === 0) {
    // Last resort: a concatenation split across lines.
    const collapsed = glue(file.text.replace(/\s*\n\s*/g, " "));
    if (pattern.test(collapsed))
      found.push({ path: file.path, line: 0, how: "assembled from string fragments across lines", excerpt: "" });
  }
  return found;
}
