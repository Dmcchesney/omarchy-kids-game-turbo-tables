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

// ---------------------------------------------------------------------------
// ROUND 4 -- WIDENED, BECAUSE A THIRD OF THE STRINGS WAS NOT ENOUGH.
// ---------------------------------------------------------------------------
//
// Round three read `text:` literals only, which a critic measured at 31 of the
// 96 `text:` bindings under `ui/` -- and then wrote four printed key hints into
// a screen, of which this check saw ONE, and lost even that one when the same
// two Texts were wrapped in a `Repeater` (the literal moves into the model, and
// the model is not a `text:`). Two of the four are beyond any source check --
// `text: someProperty` is a binding, not a string -- and those are caught at
// RUNTIME now, by the fourth oracle in `dev/Harness.qml` (see the block in
// `dev/KeyHints.js`). The two this check can reach, it now reaches:
//
//   EVERY LITERAL, wherever it is written. A model entry, a `label:`, a
//   `sublabel:`, an argument to `Canvas.fillText` -- if a person typed a string
//   that reads as a printed key hint, it is read. The exceptions are the parity
//   contract's own columns (`key`, `keys`, `does`, `help`, the accessible name
//   and description), which exist precisely to SAY what key does what and would
//   otherwise fail on their own subject.
//
//   THE HINT GRAMMAR ASSEMBLED BY HAND. `text: keys + "  " + action` holds no
//   hint literal at all -- it holds two spaces -- and it is exactly how
//   `ui/parts/KeyHint.qml` builds its own line. A `text:`, `label:` or
//   `sublabel:` binding that joins a run of two or more spaces, or a newline, to
//   anything else is that component being rebuilt by hand, and the rule is that
//   there is one of it.
//
// A literal never spans a line here: `[^"\\\n]` rather than `[^"\\]`, because a
// stray quote inside a regex or a shell fragment otherwise swallows forty lines
// of code and offers them to the grammar as one string.
const PROP_LITERAL = /(^|[^A-Za-z0-9_.$])([A-Za-z_][A-Za-z0-9_.]*)\s*:\s*((?:"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|[ \t]*\+[ \t]*)+)/g;
const ONE_LITERAL = /"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'/g;
const FILL_TEXT = /fillText\s*\(\s*(?:"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)')/g;
const ASSEMBLED = /(^|[^A-Za-z0-9_.$])(text|label|sublabel)\s*:\s*([^\n]*)/g;
// A separator with a `+` on BOTH sides, which is what joining two things with it
// looks like. `(chosen ? "▸ " : "  ") + label` is an alignment pad on the one
// modal in the game, not a hint being assembled, and the first cut of this rule
// failed it.
const SEPARATOR_LITERAL = /\+\s*(?:"(?:[ \t]{2,}|\\n)"|'(?:[ \t]{2,}|\\n)')\s*\+/;

// WHAT A SOURCE CHECK MAY READ, AND WHERE THE LINE IS DRAWN.
//
// The first attempt at this widening read EVERY literal in every screen and
// produced fifty-six failures on a build with no defect in it: `"left"` and
// `"right"` in an anchor and a key route, `" up"` and `" down"` joined onto a
// control's name, and a screen-reader description split across two lines
// (`"Enter chooses, Escape goes back."`). A rule that has to be argued with is a
// rule the next builder turns off, and the critic's own finding against round
// two was that widening a guess buys a false negative at the price of a false
// positive somewhere else.
//
// So this reads the strings that certainly reach a screen: a `text:` binding,
// and an argument to `Canvas.fillText` -- which is the one way in this game to
// draw words that are not a `Text` item, and the one the critic used. Everything
// else a critic demonstrated -- a runtime-assembled string, a literal that moved
// into a `Repeater`'s model, a `text:` bound to a property, a `label:` with a
// keycap in it -- is caught at RUNTIME, by the fourth oracle in
// `dev/Harness.qml`, where the question "and can a child press it?" is
// answerable. That is the honest split, and `label:`/`sublabel:` are on the
// runtime side of it deliberately: `label: "RACE AGAIN ⏎"` is a printed key on a
// control that DOES what it says, which no source check can tell from one that
// does not.
const DRAWING_PROPERTIES = new Set(["text"]);

// `ui/parts/KeyHint.qml` is the component every other file is being told to use,
// so it is the one file allowed to build the grammar; `ui/parts/KeyLegend.qml`
// is the one declared caption that prints keys and is not a control, and it
// declares itself to the runtime oracle too.
const GRAMMAR_OWNERS = new Set(["ui/parts/KeyHint.qml", "ui/parts/KeyLegend.qml"]);

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
// ROUND 4. The screens, and only the screens. `dev/` and `shell/` are a harness
// and a shell adapter: they hold key TABLES (`"esc"`, `"backtab"`, the map a
// synthetic press is posted from) and environment names, none of which is drawn
// on a screen a child looks at, and reading them turned the widened rule into
// forty false positives on its first run. Every file that draws a screen is
// under `ui/`, and `npm run check:boundary` is what keeps it that way.
const qml = tree.files.filter((f) => isQml(f.path) && f.path.startsWith("ui/"));

const failures: string[] = [];
let literalsRead = 0;

let looseRead = 0;

for (const file of qml) {
  const source = stripComments(file.text);
  const consumed: Array<[number, number]> = [];

  for (const match of source.matchAll(PROP_LITERAL)) {
    const property = match[2] ?? "";
    const group = match[3] ?? "";
    const groupAt = (match.index ?? 0) + match[0].length - group.length;
    consumed.push([groupAt, groupAt + group.length]);
    if (!DRAWING_PROPERTIES.has(property)) continue;
    const pieces = [...group.matchAll(ONE_LITERAL)].map((m) => m[1] ?? m[2] ?? "");
    if (pieces.length === 0) continue;
    const printed = pieces.join("");
    if (printed.trim().length === 0) continue;
    literalsRead += 1;
    if (!isPrintedHint(printed)) continue;
    failures.push(
      `${file.path}:${lineOf(source, match.index ?? 0)}: ${JSON.stringify(printed)} is a printed key hint written as a string (property \`${property}\`).`
      + ` A key printed on this screen is a promise that pressing it does something, and a child who finds one of these clickable will press the next one.`
      + ` Write it as a KeyHint (ui/parts/KeyHint.qml), which carries the words, the hover, the Accessible role and the click target that does what the key does.`,
    );
  }

  // WORDS DRAWN WITHOUT A `Text`. A critic wrote `SPACE  FIRE THE CARD` with
  // `Canvas.fillText` and nothing in this repository could see it -- not the
  // source check, which read `text:` bindings, and not the runtime oracles,
  // because a canvas has no Text item in the tree to walk. This is the one
  // reading that closes it, and it is exact rather than a guess: a literal
  // handed to fillText is words on the screen.
  for (const match of source.matchAll(FILL_TEXT)) {
    const printed = match[1] ?? match[2] ?? "";
    if (printed.trim().length === 0) continue;
    looseRead += 1;
    if (!isPrintedHint(printed)) continue;
    failures.push(
      `${file.path}:${lineOf(source, match.index ?? 0)}: ${JSON.stringify(printed)} is a printed key hint drawn with Canvas.fillText.`
      + ` A canvas leaves no Text item in the tree, so no walk of the running screen can find it and ask whether a click on it does anything.`
      + ` Write it as a KeyHint (ui/parts/KeyHint.qml).`,
    );
  }

  // The grammar, assembled by hand out of a separator and two properties.
  if (GRAMMAR_OWNERS.has(file.path)) continue;
  for (const match of source.matchAll(ASSEMBLED)) {
    const expression = match[3] ?? "";
    if (!expression.includes("+")) continue;
    if (!SEPARATOR_LITERAL.test(expression)) continue;
    failures.push(
      `${file.path}:${lineOf(source, match.index ?? 0)}: \`${match[2]}\` is assembled from a two-space or newline separator and something else.`
      + ` That is this game's printed-hint grammar -- \`keys + "  " + action\` -- rebuilt by hand, and it holds no literal for this check to read, so nothing would ever see the hint it draws.`
      + ` There is one of that component and it is ui/parts/KeyHint.qml.`,
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
  console.log(`  ${qml.length} .qml files under ui/, ${literalsRead} \`text:\` literals and ${looseRead} Canvas.fillText literals read with comments blanked`);
  console.log("  also refused: a `text:`, `label:` or `sublabel:` assembled from a two-space or newline separator, which is ui/parts/KeyHint.qml's own grammar rebuilt by hand");
  console.log("  every printed key hint in this repository is a KeyHint, so dev/Harness.qml's walk finds them by asking the component rather than by parsing prose");
  console.log("  not read here, and caught at runtime instead: a `text:` built from properties, a literal that moved into a Repeater's model, a `label:` or `sublabel:` with a keycap in it");
  console.log("  those are dev/Harness.qml's fourth oracle and test_33 in tests/qml/tst_mouse_parity.qml, which read the words on the screen and can also answer whether a click on them does anything");
  console.log("  not flagged: one bare digit beside a word (`3  CORRECT`, `2  TO GO`) -- a lap number, a place and a typed answer are all bare digits, and a scoreboard is not a promise about a key");
}
}
