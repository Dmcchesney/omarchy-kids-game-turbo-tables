// PIECE M ROUND 3. A PRINTED KEY IS A COMPONENT, NEVER A STRING.
//
// This game prints its keyboard on the screen -- `ESC  LEAVE`, `H  PIT CREW`,
// `⏎  USE IT      ESC  BACK` -- and round one made some of those lines
// clickable and left the rest as paint. Round two's answer was an oracle that
// READ THE RENDERED STRINGS and failed any hint-shaped one with no click target
// over it. A critic then demonstrated, in the running game, that a rule which
// guesses intent from appearance is wrong in BOTH directions and always will be:
//
//   false positives -- innocent copy turned the gate red. `3  CORRECT`,
//     `7  LAPS`, `5  IN A ROW`, `2  TO GO`, `9  BEST TIME` were every one of
//     them classified as dead key hints, because a bare digit was accepted as a
//     key inside a multi-group line. Those are scoreboard strings for a maths
//     racing game. The next builder who writes `2  TO GO` on the HUD would have
//     had to make a scoreboard clickable or reword the copy to appease a
//     heuristic.
//
//   false negatives -- `PAUSE  P` (the rule only looked for keycap-then-action),
//     `H\nPIT CREW` (a two-line hint returned early and was invisible),
//     `ESC BACK` with one space (the rule required two), `⎋  BACK`, `↵  USE IT`,
//     `⇧TAB  BACK` (glyphs not in the table) and `F1  HELP`, `CTRL  QUIT`,
//     `ALT  MENU` (words not in the table).
//
// So the runtime oracle no longer reads prose at all. `ui/parts/KeyHint.qml`
// declares `isKeyHint`, `dev/Harness.qml`'s walk asks the tree for that, and a
// hint is a hint because the component says so. That is a check nothing can
// fool with a label -- and it moves the whole question to a different place:
// what stops somebody printing a key with a plain `Text` again?
//
// THIS. The rule is not "is this Text a hint" -- which is the guess -- it is
//
//     no .qml file may write a printed key hint as a string at all.
//
// A rule about what may be WRITTEN, checked on the source, is not a guess about
// what something means at runtime. Its false positives cost a build message and
// a rename rather than a red gate on a shipped screen, and it reads the literal
// a person typed rather than a string a binding assembled, so scoreboard copy
// like `"3  CORRECT"` never reaches it as one piece: a scoreboard is a value
// beside a label, in two items, and it stays two items.
//
// AND BARE DIGITS ARE STILL NOT KEYS, ON PURPOSE. A lap number, a place and a
// typed answer are all bare digits. One digit beside a word is a scoreboard and
// this check says nothing about it. A RUN of them -- `1 2 3  CHOOSE A CARD` --
// is the game's own card-key idiom and no scoreboard prints it, so a run of two
// or more single digits is read as keys. The cost of that line is stated below
// rather than hidden: a dead `text: "3  CORRECT"` is not caught here, and it is
// not a defect either.
//
// Run: npm run check:keyhints  (inside npm run check)

import { walkTree, isQml, stripComments } from "./scope.ts";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");

// Every key this game can print, by the name or the glyph it is printed with.
// Single letters are keys too and are handled below, because a single letter
// alone is also half the alphabet.
const KEYCAP_WORDS = new Set([
  "esc", "escape", "enter", "return", "tab", "backtab", "space", "spacebar",
  "backspace", "shift", "ctrl", "control", "alt", "option", "cmd", "command",
  "meta", "super", "win", "del", "delete", "ins", "insert", "home", "end",
  "pgup", "pgdn", "pageup", "pagedown", "up", "down", "left", "right",
  "arrows", "arrow",
  "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
]);

// The glyphs the same keys are drawn with. `⇧TAB` is one token and one key, so
// these are stripped from a token before its remainder is looked up.
//
// `▲` and `▼` are deliberately NOT here. This game prints its arrow keys as
// `↑ ↓ ◀ ▶`, and the solid triangles are used for something else entirely --
// `ui/TrackView.qml` draws a `▼` as a pointer over the road. A glyph that means
// "this way" on one screen and "the down arrow" on another is a glyph this
// check would be guessing about, so it reads only the four this game actually
// prints keys with.
const KEYCAP_GLYPHS = /[⏎↵⌫⎋⇧⇥␣⌥⌘⌃↑↓←→◀▶]/gu;

/** Is one token a key a child could press? */
function isKeyToken(token: string): boolean {
  const bare = token.toLowerCase().replace(KEYCAP_GLYPHS, "");
  if (bare.length === 0) return true; // the token was nothing but glyphs
  if (KEYCAP_WORDS.has(bare)) return true;
  return bare.length === 1 && bare >= "a" && bare <= "z";
}

function isNamedKeyToken(token: string): boolean {
  const bare = token.toLowerCase().replace(KEYCAP_GLYPHS, "");
  return bare.length === 0 || KEYCAP_WORDS.has(bare);
}

function tokens(group: string): string[] {
  return group.trim().split(/\s+/).filter((t) => t.length > 0);
}

/**
 * Is this group of words a group of KEYS?
 *
 * A single letter alone is a key -- `S` on the garage door, `H` in the race --
 * and so is a run of single digits, which is this game's card-key idiom
 * (`1 2 3`). One digit alone is a lap number and is not a key.
 */
function isKeyGroup(group: string): boolean {
  const parts = tokens(group);
  if (parts.length === 0) return false;
  const digits = parts.filter((t) => t.length === 1 && t >= "0" && t <= "9");
  if (digits.length === parts.length) return parts.length >= 2;
  return parts.every((t) => isKeyToken(t) || (t.length === 1 && t >= "0" && t <= "9"));
}

/** Is this group of words a group that says what the keys DO? */
function isActionGroup(group: string): boolean {
  const parts = tokens(group);
  if (parts.length === 0) return false;
  if (isKeyGroup(group)) return false;
  return parts.some((t) => t.length >= 2 && !isKeyToken(t));
}

/**
 * Is this string a printed key hint -- keys and what they do, in one string?
 *
 * Both orders, because `PAUSE  P` is as much a promise as `P  PAUSE` and round
 * two's rule could only see the second. The separator is the game's own hint
 * grammar -- two or more spaces, a newline, or the mid-dot the screens use to
 * join clauses -- plus, for a NAMED key only, a single space: `ESC BACK` is a
 * hint and `A LAP` is not.
 */
export function isPrintedHint(text: string): boolean {
  const raw = String(text);
  if (raw.trim().length === 0) return false;

  const groups = raw.split(/\s{2,}|\\n|\n|\s+·\s+/).map((g) => g.trim()).filter((g) => g.length > 0);
  for (let i = 0; i + 1 < groups.length; i++) {
    const a = groups[i]!;
    const b = groups[i + 1]!;
    if (isKeyGroup(a) && isActionGroup(b)) return true;
    if (isActionGroup(a) && isKeyGroup(b)) return true;
  }

  if (groups.length === 1) {
    const parts = tokens(groups[0]!);
    if (parts.length >= 2) {
      const first = parts[0]!;
      const last = parts[parts.length - 1]!;
      if (isNamedKeyToken(first) && isActionGroup(parts.slice(1).join(" "))) return true;
      if (isNamedKeyToken(last) && isActionGroup(parts.slice(0, -1).join(" "))) return true;
    }
    // A `Text` that is nothing but a named key -- `text: "ESC"` -- is a keycap
    // drawn as paint. A single LETTER is not caught here: `"S"` beside
    // `"SETTINGS AND RESETS"` is the garage door, it is one control with one
    // hover state, and a letter alone carries no promise a check can read.
    if (parts.length === 1 && isNamedKeyToken(parts[0]!)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// The scan
// ---------------------------------------------------------------------------

// `text: "…"`, and `text: "…" + "…"`: everything a person typed as a literal.
// A binding that assembles a string from properties is out of reach and is said
// so in the report rather than pretended about.
const TEXT_LITERAL = /(^|[^A-Za-z0-9_.$])text\s*:\s*((?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\s*\+\s*)+)/g;
const ONE_LITERAL = /"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'/g;

function lineOf(source: string, index: number): number {
  return source.slice(0, index).split("\n").length;
}

// Guarded so the grammar above can be imported and exercised on its own -- the
// scan is what `npm run check:keyhints` runs, not what reading the rule costs.
if (import.meta.main) await run()

async function run() {
const tree = await walkTree(root);
// The vendored Quickshell stubs under dev/imports are somebody else's files and
// draw nothing a child sees.
const qml = tree.files.filter((f) => isQml(f.path) && !f.path.startsWith("dev/imports/"));

const failures: string[] = [];
let literalsRead = 0;

for (const file of qml) {
  const source = stripComments(file.text);
  for (const match of source.matchAll(TEXT_LITERAL)) {
    const pieces = [...(match[2] ?? "").matchAll(ONE_LITERAL)].map((m) => m[1] ?? m[2] ?? "");
    if (pieces.length === 0) continue;
    const printed = pieces.join("");
    if (printed.trim().length === 0) continue;
    literalsRead += 1;
    if (!isPrintedHint(printed)) continue;
    failures.push(
      `${file.path}:${lineOf(source, match.index ?? 0)}: ${JSON.stringify(printed)} is a printed key hint written as a string.`
      + ` A key printed on this screen is a promise that pressing it does something, and a child who finds one of these clickable will press the next one.`
      + ` Write it as a KeyHint (ui/parts/KeyHint.qml), which carries the words, the hover, the Accessible role and the click target that does what the key does.`,
    );
  }
}

if (failures.length) {
  console.error(failures.join("\n"));
  console.error(
    `\nKey-hint check failed with ${failures.length} printed key hint(s) written as a string.`
    + ` See the block at the top of src/tools/check-keyhints.ts.`,
  );
  process.exitCode = 1;
} else {
  console.log("Key-hint check passed.");
  console.log(`  ${qml.length} .qml files, ${literalsRead} literal \`text:\` strings read with comments blanked`);
  console.log("  every printed key hint in this repository is a KeyHint, so dev/Harness.qml's walk finds them by asking the component rather than by parsing prose");
  console.log("  not read: a `text:` built from properties or model data at runtime -- a legend rail's `modelData.key` is two items and no literal, and this check does not guess at bindings");
  console.log("  not flagged: one bare digit beside a word (`3  CORRECT`, `2  TO GO`) -- a lap number, a place and a typed answer are all bare digits, and a scoreboard is not a promise about a key");
}
}
