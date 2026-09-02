// README.md is the only artefact a parent reads. This is the gate behind it.
//
// Round 2 of the package review took the previous version apart, and the four
// things it broke are the four things this version is built around.
//
//  1. SCOPE WAS A WHITELIST. Six directory prefixes counted as "the runtime",
//     so `screens/Garage.qml` -- a FileView, a TextInput, a `new Date()` and an
//     XMLHttpRequest POST of a child's typed name -- was invisible. Scope is now
//     inverted in scope.ts: every file is the plugin unless it is on a short,
//     named, printed allow-list, and no .qml file is ever exempt.
//
//  2. A COMMENT WAS EVIDENCE. `hits()` was `line.includes(token)`, so
//     `// TODO(M4): a SoundEffect behind a loader.` proved an audio loader
//     existed. Evidence now comes only from source files with comments and
//     string bodies stripped (scope.ts `strip()`), and string concatenations
//     are glued back together before a *forbidden* token is looked for.
//
//  3. THE README COULD DISARM THE README. Every absence rule was gated on a
//     literal quote of the promise still being in the prose, so rewording a
//     privacy bullet into stronger English turned two rules into notes and the
//     build stayed green -- next to a real `ui/NamePrompt.qml` logging a child's
//     name and an ISO timestamp. The four safety invariants below are now
//     asserted unconditionally, as a fixed list in this file. Nothing in the
//     README can switch one off. The README's *disclosure* of each invariant is
//     a separate, additional requirement, and its absence is a failure.
//
//  4. GRAMMAR WAS LOAD-BEARING. Present tense was a seven-verb alternation, so
//     passive voice, verbless list items and table cells walked past it. Grammar
//     is still here, and it is still useful, but it is no longer what the safety
//     properties rest on. Those rest on: the unconditional invariants; the
//     backward direction (a capability in the tree demands a disclosing
//     sentence); grounding rules that need no verb at all (a named screen must
//     exist as a file, a named key must be handled in code); and a loud failure
//     for any capability claim this gate has no row for.
//
// What this gate still cannot do is written down in README.md under
// "What this gate does not check", and that list is part of the deal.

import { readFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import {
  NOT_THE_PLUGIN,
  NOT_WALKED,
  findToken,
  glue,
  isEvidenceFile,
  isPluginFile,
  isQml,
  qmlOutsideTheWalk,
  strip,
  stripComments,
  underInvariants,
  walkTree,
  type Hit,
  type TreeFile,
} from "./scope.ts";

const root = resolve(import.meta.dirname, "../..");
const readmePath = join(root, "README.md");
const tree = await walkTree(root);

const failures: string[] = [];
const audited: string[] = [];

function fail(rule: string, detail: string): void {
  failures.push(`${rule}: ${detail}`);
}

// ---------------------------------------------------------------------------
// Evidence
// ---------------------------------------------------------------------------

/** Where a token appears as code, in a file that is part of the plugin. */
function evidenceFor(tokens: string[]): { token: string; at: Hit } | undefined {
  for (const file of tree.files) {
    if (!isEvidenceFile(file)) continue;
    for (const token of tokens) {
      const [first] = findToken(file, token, "code");
      if (first) return { token, at: first };
    }
  }
  return undefined;
}

/** Where a token appears anywhere at all, in a file the invariants cover. */
function forbiddenSites(tokens: string[]): { token: string; at: Hit }[] {
  const found: { token: string; at: Hit }[] = [];
  for (const file of tree.files) {
    if (!underInvariants(file)) continue;
    for (const token of tokens)
      for (const at of findToken(file, token, "any")) found.push({ token, at });
  }
  return found;
}

const pluginFiles = tree.files.filter((file) => isPluginFile(file.path) && !file.binary);
const evidenceFiles = tree.files.filter(isEvidenceFile);
const invariantFiles = tree.files.filter(underInvariants);

// ---------------------------------------------------------------------------
// The README, in units: sentences, list items, table cells, headings
// ---------------------------------------------------------------------------

const readme = await readFile(readmePath, "utf8");
const readmeLines = readme.split("\n");

type Unit = { text: string; line: number; kind: "prose" | "list" | "cell" | "heading" };

/** Fenced blocks, with their line numbers, so they can be checked as commands. */
const fences: { line: number; language: string; body: string[] }[] = [];

const units: Unit[] = [];

{
  let inFence = false;
  let paragraph: { text: string; line: number } | null = null;
  let item: { text: string; line: number } | null = null;

  const flushParagraph = () => {
    if (!paragraph) return;
    const { text, line } = paragraph;
    paragraph = null;
    // Split a paragraph into sentences on terminal punctuation.
    let start = 0;
    for (let i = 0; i < text.length; i++) {
      if (!/[.!?]/.test(text[i]!)) continue;
      if (i + 1 < text.length && !/\s/.test(text[i + 1]!)) continue;
      const piece = text.slice(start, i + 1).trim();
      if (piece) units.push({ text: piece, line, kind: "prose" });
      start = i + 1;
    }
    const tail = text.slice(start).trim();
    if (tail) units.push({ text: tail, line, kind: "prose" });
  };
  const flushItem = () => {
    if (item && item.text.trim()) units.push({ text: item.text.trim(), line: item.line, kind: "list" });
    item = null;
  };

  for (const [index, raw] of readmeLines.entries()) {
    const line = index + 1;
    const fenceMatch = raw.match(/^\s*```(\S*)/);
    if (fenceMatch) {
      if (!inFence) {
        flushParagraph();
        flushItem();
        fences.push({ line, language: fenceMatch[1] ?? "", body: [] });
      }
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      fences[fences.length - 1]!.body.push(raw);
      continue;
    }
    if (!raw.trim()) {
      flushParagraph();
      flushItem();
      continue;
    }
    if (/^\s*#{1,6}\s/.test(raw)) {
      flushParagraph();
      flushItem();
      units.push({ text: raw.replace(/^\s*#+\s*/, "").trim(), line, kind: "heading" });
      continue;
    }
    if (/^\s*\|/.test(raw)) {
      flushParagraph();
      flushItem();
      if (/^\s*\|[\s|:-]+\|\s*$/.test(raw)) continue; // the ---|--- separator row
      const cells = raw.split("|").map((part) => part.trim()).filter(Boolean);
      for (const cell of cells) units.push({ text: cell, line, kind: "cell" });
      // The row as a whole, too: a table splits subject from predicate across
      // the pipe, and round 2 hid "Podium | ranks the four racers" in that gap.
      if (cells.length > 1) units.push({ text: cells.join(" "), line, kind: "cell" });
      continue;
    }
    const listMatch = raw.match(/^\s*(?:[-*]|\d+\.)\s+(.*)$/);
    if (listMatch) {
      flushParagraph();
      flushItem();
      item = { text: listMatch[1]!, line };
      continue;
    }
    if (item && /^\s{2,}\S/.test(raw)) {
      item.text += ` ${raw.trim()}`;
      continue;
    }
    flushItem();
    if (paragraph) paragraph.text += ` ${raw.trim()}`;
    else paragraph = { text: raw.trim(), line };
  }
  flushParagraph();
  flushItem();
}

// Fence bodies were not units at all, and the compensating "prose in a fence"
// rule was a shape heuristic that skipped `#`- and `/`-leading lines and required
// a capital first letter. Round 3 walked through both holes: a `#`-prefixed
// comment in an ```sh block claiming a stored history of every race with its
// date, and a lowercase-leading line in a ```text block claiming a podium and
// stored best times, both exit 0. Fence content is now read as prose, one line
// per unit, with any comment marker stripped first. Every rule that applies to a
// sentence in the README applies to a sentence in a fence.
for (const fence of fences)
  for (const [offset, raw] of fence.body.entries()) {
    const text = raw.replace(/^\s*(?:#+|\/\/|--)\s*/, "").trim();
    if (text) units.push({ text, line: fence.line + offset + 1, kind: "prose" });
  }

// ---------------------------------------------------------------------------
// Is a unit asserting something about the plugin as it is today?
// ---------------------------------------------------------------------------

// `only` was in this list until round 3 pointed out that it is not a denial in
// English, it is a narrowing: "The Podium screen only ranks the four racers by
// their best lap" is a claim about a screen that does not exist, and one word
// turned it into a non-claim. It is gone.
const NEGATOR = /\b(?:no|not|never|nothing|none|nor|without|neither|cannot)\b/i;
const FUTURE = /\b(?:will|shall|would|going to|planned|plans to|once it|when it lands|not yet)\b/i;
const TRAILING_HEDGE = /\byet\b/i;

// Where one clause of a sentence ends and the next begins, for the purpose of
// deciding which verbs a "will" governs. Round 3 put a future marker in an
// opening flourish -- "Parents will be pleased that the Results screen shows
// every race a child has run and stores each best time in garage.json" -- and
// the unwindowed test disarmed every verb after it.
const CLAUSE_BREAK = /[,;:()]|\b(?:and|but|that|which|while|so|because|though|although|however)\b/gi;

/** The text from the last clause break before `index` up to `index`. */
function clauseBefore(text: string, index: number): string {
  const prefix = text.slice(0, index);
  CLAUSE_BREAK.lastIndex = 0;
  let start = 0;
  let match: RegExpExecArray | null;
  while ((match = CLAUSE_BREAK.exec(prefix)) !== null) start = match.index + match[0].length;
  return prefix.slice(start);
}

// Third-person present verbs that turn a sentence about a capability into a
// claim about today. Generous, but not exhaustive -- see "What this gate does
// not check" in README.md.
const ACTIVE = new RegExp(
  "\\b(?:writes|reads|stores|saves|creates|persists|keeps|holds|shows|displays|draws|renders"
  + "|opens|closes|toggles|takes|runs|installs|uses|loads|plays|sits|falls back|degrades|wraps|hosts"
  + "|sends|syncs|uploads|downloads|collects|logs|tracks|cycles|doubles|ranks|remembers"
  + "|survives|ships|supports|handles|reaches|generates|contains|includes|adds|awards|earns|lands"
  + "|enables|disables|has|have|lives|depart|departs|drops|deletes|clones|validates|enters|answers)\\b",
  "i",
);
// Passive voice: "Records are stored in garage.json" is a claim too.
const PARTICIPLE_LIST =
  "stored|saved|written|kept|held|persisted|recorded|logged|sent|uploaded|collected|shown|displayed"
  + "|drawn|synced|transmitted|tracked|remembered|generated|unlocked|answered|built";
const PASSIVE = new RegExp(`\\b(?:is|are|was|were|gets|get|be|been)\\s+(?:\\w+ly\\s+)?(?:${PARTICIPLE_LIST})\\b`, "i");
// A verbless list item or table cell -- "Ghost replays ..., saved per preset" --
// is a claim as surely as a sentence is.
const BARE_PARTICIPLE = new RegExp(`\\b(?:${PARTICIPLE_LIST})\\b`, "i");

function verbSites(text: string, pattern: RegExp): number[] {
  const global = new RegExp(pattern.source, `${pattern.flags.replace("g", "")}g`);
  const out: number[] = [];
  let match: RegExpExecArray | null;
  while ((match = global.exec(text)) !== null) out.push(match.index);
  return out;
}

function assertedAt(text: string, index: number): boolean {
  const before = text.slice(Math.max(0, index - 45), index);
  const after = text.slice(index, index + 40);
  // Negation is windowed: "writes ... and nothing else" is still a claim, which
  // is why the window starts at the verb and is short.
  if (NEGATOR.test(before) || NEGATOR.test(after)) return false;
  // Future tense is windowed to the clause the verb sits in. A "will" earlier in
  // the sentence, in a clause of its own, governs its own clause and not this
  // one.
  if (FUTURE.test(clauseBefore(text, index))) return false;
  if (TRAILING_HEDGE.test(after)) return false;
  return true;
}

/**
 * A row is about a unit only when the subject itself is not negated, and only a
 * negation *before* the subject counts. "never stored, shown across sessions"
 * is a denial; "writes the records to `garage.json` and nothing else" is not,
 * and round 2 singled that asymmetry out as the piece of the old design worth
 * keeping.
 */
function subjectApplies(unit: Unit, subject: RegExp): boolean {
  for (const index of verbSites(unit.text, subject)) {
    const before = unit.text.slice(Math.max(0, index - 45), index);
    if (!NEGATOR.test(before)) return true;
  }
  return false;
}

/** True when the unit says the plugin does something, now. */
function isClaim(unit: Unit): boolean {
  for (const pattern of [ACTIVE, PASSIVE])
    for (const index of verbSites(unit.text, pattern)) if (assertedAt(unit.text, index)) return true;
  if (unit.kind === "list" || unit.kind === "cell" || unit.kind === "heading")
    for (const index of verbSites(unit.text, BARE_PARTICIPLE)) if (assertedAt(unit.text, index)) return true;
  return false;
}

// ---------------------------------------------------------------------------
// 1. The four safety invariants -- asserted unconditionally
// ---------------------------------------------------------------------------
//
// These are the plugin's promise to a parent. They are a fixed list in this
// file. They do not consult the README to decide whether to run, they run on
// every invocation, and they cover every file scope.ts says the invariants
// cover -- which is the whole repository minus a printed allow-list, plus every
// .qml file without exception.
//
// Each one carries, separately:
//   disclosure    the README has to say it. Absence is a failure, not a note.
//   contradiction the README may not claim the opposite anywhere.

type Invariant = {
  name: string;
  tokens: string[];
  /**
   * The exact words the README has to carry. Deliberately literal: round 2
   * reworded a privacy bullet into stronger English and two rules turned
   * themselves off with a note. Rewording is no longer silent -- the invariant
   * keeps running either way, and the build stops until someone decides, in
   * this file, that the new wording is the promise.
   */
  disclosure: string;
  disclosureText: string;
  /** The README may not assert the capability this invariant forbids. */
  contradiction: RegExp;
  contradictionText: string;
};

const INVARIANTS: Invariant[] = [
  {
    name: "no network code",
    tokens: [
      "XMLHttpRequest", "WebSocket", "EventSource", "fetch(", "navigator.sendBeacon",
      "Qt.openUrlExternally", "http://", "https://", "ftp://", "ws://", "wss://",
      "node:http", "node:https", "node:net", "node:dgram", "Socket", "DatagramSocket",
      "QNetworkAccessManager", "curl ", "wget ",
    ],
    disclosure: "makes no network requests, and contains no network code at all",
    disclosureText: "Permissions and privacy must state that the plugin makes no network requests and contains no network code",
    contradiction:
      /\b(?:syncs?|synced|uploads?|downloads?|leaderboard|telemetry|analytics|crash report|cloud|internet|online|server|network request|multiplayer|invite code|peer-to-peer|\bLAN\b)\b/i,
    contradictionText: "the README claims networked behaviour while promising there is no network code",
  },
  {
    name: "no process or shell execution",
    tokens: [
      "Process", "execDetached", "child_process", "Qt.createProcess", "spawnSync", "spawn(",
      "execSync", "execFile", "popen(", "Runtime.exec", "QProcess",
    ],
    disclosure: "starts no processes, runs no shell commands",
    disclosureText: "Permissions and privacy must state that the plugin starts no processes and runs no shell commands",
    contradiction: /\b(?:sudo|pkexec|shell command|spawns|subprocess|launches a process|runs a command|executes a)\b/i,
    contradictionText: "the README claims process or shell execution while promising there is none",
  },
  {
    name: "no free-text entry and no name field",
    tokens: [
      "TextInput", "TextEdit", "TextField", "TextArea", "inputMethodHints", "Qt.inputMethod",
      "InputPanel", "VirtualKeyboard", "onTextChanged", "prompt(",
    ],
    disclosure: "no name field, no free-text entry anywhere",
    disclosureText: "Permissions and privacy must state that there is no name field and no free-text entry",
    contradiction:
      /\b(?:first name|last name|full name|child's name|childs name|school year|name field|free[- ]text|text (?:box|field|entry)|types? (?:in )?(?:a|their) name|enters? (?:a|their) name)\b/i,
    contradictionText: "the README describes collecting a name or free text while promising neither exists",
  },
  {
    name: "no dates stored",
    tokens: [
      "new Date(", "Date.now(", "Date.parse(", "Date.UTC(", "toISOString", "getTime()",
      "getFullYear(", "Qt.formatDateTime", "Qt.formatDate", "toLocaleDateString",
    ],
    disclosure: "stores no dates",
    disclosureText: "Permissions and privacy must state that no dates are stored",
    contradiction: /\b(?:dates\b|the date\b|a date\b|timestamp|birthday|day streak|calendar|ISO 8601)\b/i,
    contradictionText: "the README describes storing or showing a date while promising none is stored",
  },
];

for (const invariant of INVARIANTS) {
  const sites = forbiddenSites(invariant.tokens);
  if (sites.length)
    fail(
      `safety invariant "${invariant.name}"`,
      `${sites.length} forbidden token site(s) in the plugin. This invariant is asserted unconditionally; it cannot be waived by editing README.md.\n`
      + sites
        .slice(0, 8)
        .map((site) => `    ${site.token} ${site.at.how} at ${site.at.path}:${site.at.line}  ${site.at.excerpt}`)
        .join("\n"),
    );
  else audited.push(`invariant "${invariant.name}": 0 sites across ${invariantFiles.length} files`);

  if (!readme.includes(invariant.disclosure))
    fail(
      `invariant disclosure "${invariant.name}"`,
      `README.md no longer carries the words that disclose this invariant, verbatim:\n        "${invariant.disclosure}"\n    ${invariant.disclosureText}.\n`
      + "    The invariant itself is still enforced -- it is unconditional -- but a parent reading the README would\n"
      + "    no longer be told about it. Restore the sentence, or change INVARIANTS in src/tools/check-readme.ts deliberately.",
    );
}

// ---------------------------------------------------------------------------
// 2. The README may not claim the opposite of an invariant
// ---------------------------------------------------------------------------
//
// The exculpatory words are the ones that make a mention not a claim about
// today: a negation, or an explicit reference to the future.
//
// The canonical description of the design mock is three exact sentences owned by
// this file. Round 3 broke the previous version of this exemption: it matched a
// 60-character *prefix* against a whole unit and then deleted that unit from the
// claim scan and the contradiction scan alike, so a clause appended to the
// sentence -- a leaderboard sync, a stored full name and birthday with an ISO
// timestamp, a shell command to upload them -- was invisible to every rule in
// the file and the build exited 0. Two things changed:
//
//   * the exemption is exact string equality against a whole unit, normalised
//     for whitespace only. A prefix buys nothing, and a sentence that starts
//     with a canonical one but continues is not exempt;
//   * nothing is ever removed from the contradiction scan. It runs over every
//     unit of the README, unconditionally, including these three.

const MOCK_IMAGE = "docs/garage-room-mock.png";
const MOCK_DESCRIPTION = [
  "`docs/garage-room-mock.png` is a design mock of the future multiplayer lobby: an invite code, four"
  + " named children, ready toggles and APPROVED FRIEND / DEVICE VERIFIED badges, none of which exists"
  + " in this plugin, which is solo and offline.",
  "Only the kart stall on its left, the body, paint and number pickers, is the reference the solo garage"
  + " will be built against.",
  "It is not a screenshot of this plugin and must never be used as its preview.",
];

const EXCULPATORY = /\b(?:no|not|never|nothing|none|nor|without|neither|future|will|would|planned|design mock)\b/i;

const flatten = (text: string) => text.replace(/\s+/g, " ").trim();
const CANONICAL_MOCK_UNITS = new Set(MOCK_DESCRIPTION.map(flatten));

/** True only when the unit *is* one of this file's own sentences, in full. */
function isCanonicalMockSentence(text: string): boolean {
  return CANONICAL_MOCK_UNITS.has(flatten(text));
}

for (const unit of units) {
  for (const invariant of INVARIANTS) {
    for (const index of verbSites(unit.text, invariant.contradiction)) {
      const before = unit.text.slice(Math.max(0, index - 60), index);
      const after = unit.text.slice(index, index + 30);
      if (EXCULPATORY.test(before) || EXCULPATORY.test(after)) continue;
      fail(
        `README contradicts invariant "${invariant.name}"`,
        `README.md:${unit.line}: ${invariant.contradictionText}\n    claim: "${unit.text.slice(0, 160)}"`,
      );
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// 3. No dynamically constructed code in the plugin
// ---------------------------------------------------------------------------
//
// Round 2 assembled `XMLHttpRequest` from string fragments and reached it
// through `globalThis[...]`. `glue()` catches the fragments; this catches the
// mechanism. A plugin whose whole job is arithmetic has no use for it.

// Round 3 walked past this list twice: `globalThis?.[` does not contain the
// substring `globalThis[`, and `Qt.createComponent(` was not here at all.
const OBFUSCATION = [
  "eval(", "new Function(", "Function(", "globalThis", "window[", "window?.[",
  "Qt.createQmlObject(", "Qt.createComponent(", "Reflect.get(", "Reflect.has(",
  "atob(", "String.fromCharCode(", "unescape(",
];
for (const file of tree.files) {
  if (!underInvariants(file)) continue;
  for (const token of OBFUSCATION)
    for (const at of findToken(file, token, "code"))
      fail("dynamic code construction", `${at.path}:${at.line}: \`${token}\` in the plugin  ${at.excerpt}`);
}

// ---------------------------------------------------------------------------
// 3a. A plugin .qml file may not build an identifier or a URL at runtime
// ---------------------------------------------------------------------------
//
// The token lists above are a blocklist, and round 3 showed a blocklist is the
// wrong shape for this: `ui/parts/Ledger.qml` spelled `XMLHttpRequest`,
// `https://`, `POST` and `toISOString` one character at a time in array literals
// and reached them through `globalThis?.[...]`, scoring zero hits in check:readme,
// zero in check:boundary and `passed` from the marketplace scanner. `glue()` now
// reads those arrays as the strings they spell, but the deeper point is that the
// *shape* is the defect. This game is arithmetic and a kart. Nothing in it has a
// reason to assemble a name at runtime, so the assembly itself fails, whatever it
// spells. Scoped to plugin QML because that is the only language Omarchy runs.

// Note what is *not* here: a plain array literal of strings. `ui/Theme.qml` has
// several honest ones (paint names, rival names), and glue() already reads any
// array of string pieces as the string it spells, so the token lists see through
// them. What is left here is the machinery for turning a string into a name, an
// object or a module at runtime, which is what has no honest use in this tree.
const RUNTIME_CONSTRUCTION: { pattern: RegExp; what: string }[] = [
  { pattern: /\.\s*join\s*\(/, what: "Array.prototype.join" },
  { pattern: /\.\s*concat\s*\(/, what: "Array.prototype.concat" },
  { pattern: /\.\s*fromCharCode\b|\.\s*charCodeAt\s*\(|\.\s*codePointAt\s*\(/, what: "character-code arithmetic" },
  { pattern: /(?:[A-Za-z_$][\w$]*)\s*\?\?\s*\.\s*\[|(?:[A-Za-z_$][\w$]*)\s*\?\.\s*\[/, what: "an optional computed member access" },
  { pattern: /\bnew\s+[a-z_$][\w$]*\s*\(/, what: "`new` on a lower-case identifier, which is a variable rather than a type" },
  { pattern: /\bimport\s*\(/, what: "a dynamic import" },
];
for (const file of tree.files) {
  if (!isQml(file.path) || !isPluginFile(file.path)) continue;
  const code = strip(file.text).split(/\r?\n/);
  const raw = file.text.split(/\r?\n/);
  for (const [index, line] of code.entries())
    for (const shape of RUNTIME_CONSTRUCTION)
      if (shape.pattern.test(line))
        fail(
          "runtime construction in a plugin QML file",
          `${file.path}:${index + 1}: ${shape.what}. A plugin file in this repository has no reason to build a name, a URL or an object at runtime; whatever it spells, the shape is the defect.\n    ${(raw[index] ?? "").trim().slice(0, 120)}`,
        );
}

// ---------------------------------------------------------------------------
// 3b. The allow-list may not be reached from the plugin
// ---------------------------------------------------------------------------
//
// The allow-list is only honest while the files on it are genuinely unreachable
// from a manifest entry point. If a plugin file imports or reads a path under
// one of them, that path is running in a child's session and the exemption is a
// lie. This is the check that keeps the allow-list from becoming a hiding place.

// Round 3 defeated this rule with `await import("../de" + "v/collect.mjs")`: it
// used a literal `includes` while the invariant scanner used `glue()`. It uses
// `glue()` now, and it covers the exact-path entries as well as the directory
// ones -- the old `endsWith("/")` guard skipped every single-file exemption.
for (const file of tree.files) {
  if (!isEvidenceFile(file)) continue;
  const lines = glue(stripComments(file.text)).split(/\r?\n/);
  for (const entry of NOT_THE_PLUGIN) {
    const index = lines.findIndex((text) => text.includes(entry.match));
    if (index === -1) continue;
    fail(
      "allow-list reached from the plugin",
      `${file.path}:${index + 1} refers to \`${entry.match}\`, which check:readme treats as not part of the plugin. Either it is part of the plugin, or this reference should not exist.`,
    );
  }
}

// The walk itself skips four directories, and round 3 was right that this was a
// second allow-list, printed nowhere and reasoned nowhere -- one that even a
// `.qml` file could hide behind. It is printed with the other one now, and a
// `.qml` file under any of them is a failure.
for (const path of await qmlOutsideTheWalk(root))
  fail(
    "QML outside the walk",
    `${path} is a .qml file under a directory this tool does not walk (see the "not walked" list it prints). No .qml file is ever exempt from the four invariants; move it into the tree or delete it.`,
  );

// ---------------------------------------------------------------------------
// 4. Capability rows -- the forward and backward directions
// ---------------------------------------------------------------------------
//
// A row is the gate's vocabulary. If a unit is a claim and matches a row's
// subject, the row's evidence has to exist. If a row's evidence exists and the
// README never discloses it, that is the Lode Runner defect and it fails too.
// A claim that matches no row at all is a failure of its own (section 5).

type Row = {
  name: string;
  subject: RegExp;
  tokens: string[];
  /** Extra evidence beyond tokens: a file whose path proves the capability. */
  files?: (path: string) => boolean;
  what: string;
  missing: string;
  /** Backward direction: if the evidence exists, the README must say this. */
  disclosure?: RegExp;
  undisclosed?: string;
  /** Verb-free grounding rules run on every claiming unit. */
  ground?: (unit: Unit) => string[];
};

// The screens the settled design names (docs/plan.md, layer 2). A claim about
// "the garage screen" is grounded by a file named for that screen existing.
const DESIGN_SCREENS = [
  "Garage", "Countdown", "Race", "TrackView", "Minimap", "Picker", "Results", "Settings", "Podium",
];
const GENERIC_SCREEN_WORDS = new Set([
  "game", "no", "any", "every", "each", "the", "a", "an", "one", "other", "another", "real", "whole",
  "this", "that", "first", "next", "current", "same", "only", "main", "single", "new", "full", "home",
]);

function screenFileFor(name: string): string | undefined {
  const wanted = [`${name.toLowerCase()}.qml`, `${name.toLowerCase()}screen.qml`];
  return tree.files.find(
    (file) => isPluginFile(file.path) && wanted.includes(basename(file.path).toLowerCase()),
  )?.path;
}

const KEY_NAME = /^(?:Escape|Esc|Enter|Return|Space|Tab|Backspace|Shift|Ctrl|Control|Alt|Super|Meta|F\d{1,2}|Left|Right|Up|Down|PageUp|PageDown|Home|End)$/;

/** Qt spells some of these differently from a README. */
const KEY_ALIASES: Record<string, string> = { Esc: "Escape", Ctrl: "Control", Super: "Meta" };

/**
 * A key is handled when a QML file names the Qt identifier that handles it, with
 * identifier boundaries. This was a bare `strip(file.text).includes(key)` until
 * round 3 enumerated what that grounded: `Tab` was "handled" by the substring in
 * `tableFacts`, `Up` by `pileUp`, `Left` by `factLeft`. Three false keyboard
 * promises, all green.
 */
function keyIsHandled(key: string): boolean {
  const name = KEY_ALIASES[key] ?? key;
  const patterns = [
    new RegExp(`\\bQt\\.Key_${name}\\b`),
    new RegExp(`\\bKey_${name}\\b`),
    new RegExp(`\\bKeys\\.on${name}Pressed\\b`),
    new RegExp(`\\bStandardKey\\.${name}\\b`),
    new RegExp(`\\b${name}Modifier\\b`),
  ];
  return evidenceFiles.some((file) => {
    const code = strip(file.text);
    return patterns.some((pattern) => pattern.test(code));
  });
}

/** Every backticked key name in a unit, `SUPER + SHIFT + T` split apart. */
function keysNamedIn(text: string): string[] {
  const keys: string[] = [];
  for (const match of text.matchAll(/`([^`\n]+)`/g))
    for (const part of match[1]!.split(/\s*\+\s*/).map((piece) => piece.trim()))
      if (KEY_NAME.test(part)) keys.push(part);
  return keys;
}

const ROWS: Row[] = [
  {
    name: "save file",
    subject:
      /garage\.json|\bsave file\b|\bdata file\b|\bthe file\b|\bone file\b|\bbest times?\b|\bghost\b|\brecords\b|\bpersist|\bremembers?\b|\bsurvives? a restart\b|\bacross sessions\b|\bbetween sessions\b|\bsave data\b/i,
    tokens: ["FileView", "writeFileSync", "Qt.labs.settings", "localStorage", "StandardPaths", "atomicWrites"],
    what: "file it reads or writes",
    missing:
      "README claims the plugin reads, writes or remembers something across runs, but nothing in the plugin writes anything. "
      + "Either build it, or put the sentence in the future tense.",
    disclosure: /reads? and writes? exactly one file it owns|writes? .{0,40}garage\.json/i,
    undisclosed: "The plugin can write files and no present-tense README sentence discloses it. Say so under Permissions and privacy.",
  },
  {
    name: "audio",
    subject: /multimedia|soundeffect|mediaplayer|\baudio\b|\bsound\b|\bmusic\b|\bvolume\b|silent stub/i,
    tokens: ["SoundEffect", "MediaPlayer", "AudioOutput", "QtMultimedia", "Multimedia"],
    what: "audio component",
    missing:
      "README claims audio or its silent fallback exists, but no multimedia token is in the plugin. "
      + "Either build the loader, or put the sentence in the future tense.",
    disclosure: /Qt Multimedia/i,
    undisclosed: "The plugin uses Qt Multimedia and no present-tense README sentence describes the audio path. Say so under Dependencies.",
  },
  {
    name: "overlay and bar widget",
    subject: /\boverlay\b|\bbar widget\b|\bkart button\b|\bpanel window\b/i,
    tokens: ["PanelWindow"],
    what: "shell window",
    missing: "README describes the overlay behaving, but no QML window exists to behave. Build it or reword.",
  },
  {
    name: "game screen",
    subject: new RegExp(`\\bscreens?\\b|\\bscene\\b|\\bgauge\\b|\\btrack view\\b|\\b(?:${DESIGN_SCREENS.join("|")})\\b`, "i"),
    tokens: [],
    files: (path) =>
      DESIGN_SCREENS.some((name) => {
        const base = basename(path).toLowerCase();
        return base === `${name.toLowerCase()}.qml` || base === `${name.toLowerCase()}screen.qml`;
      }),
    what: "screen file from the settled design",
    missing:
      "README describes a game screen behaving, but no screen from the settled design exists as a file yet "
      + `(looked for ${DESIGN_SCREENS.map((name) => `ui/${name}.qml`).join(", ")}).`,
    ground: (unit) => {
      const problems: string[] = [];
      // A design screen named by its own name -- "| Podium | ranks the four
      // racers |" -- needs its file as much as "the podium screen" does.
      for (const name of DESIGN_SCREENS)
        if (new RegExp(`\\b${name}\\b`).test(unit.text) && !screenFileFor(name))
          problems.push(
            `README.md:${unit.line} names "${name}" as something the plugin has, but there is no ui/${name}.qml in the tree`,
          );
      for (const match of unit.text.matchAll(/\b([A-Za-z][A-Za-z]*)\s+screens?\b/g)) {
        const word = match[1]!;
        if (GENERIC_SCREEN_WORDS.has(word.toLowerCase())) continue;
        const name = word[0]!.toUpperCase() + word.slice(1).toLowerCase();
        if (!screenFileFor(name))
          problems.push(
            `README.md:${unit.line} names "${word} screen" as something the plugin has, but there is no ui/${name}.qml in the tree`,
          );
      }
      return problems;
    },
  },
  {
    name: "keyboard behaviour",
    // The vocabulary half of this subject was the whole of it until round 3
    // wrote a Controls table that never says "key" or "press" -- `Tab` cycles
    // the focus ring, `Home` jumps to the first stall -- and the row never fired
    // at all. A backticked key name is now a keyboard claim on its own.
    subject: new RegExp(
      "\\bkeyboard\\b|\\bkeybinding\\b|\\bkeys?\\b|\\bshortcut\\b|\\bpress(?:es|ing)?\\b|\\bholding\\b"
      + `|\`${KEY_NAME.source.replace(/^\^|\$$/g, "")}\``,
      "i",
    ),
    tokens: ["Keys", "Shortcut", "Keys.onPressed", "focus"],
    what: "key handling in any QML file",
    missing: "README describes keyboard behaviour, but no QML file handles keys.",
    ground: () => [], // grounded unconditionally below, over every unit, claim or not
  },
  {
    name: "game rules",
    subject: /\blaps?\b|\brivals?\b|\bstreaks?\b|\bpowerups?\b|\bdifficulty\b|\bmodes?\b|\bunlock|\bbonus\b|\bmultiplication facts?\b|\brace\b|\bracers?\b/i,
    tokens: ["streak", "lap", "rival", "race", "card"],
    what: "rules engine",
    missing: "README describes a game rule, but no engine source implements anything of the kind.",
    ground: (unit) => {
      // "Rookie, Pro and Champion" -- a claim that names things has to name
      // things that exist. Only enumerations of three or more capitalised
      // words fire, so ordinary prose is untouched.
      const problems: string[] = [];
      for (const match of unit.text.matchAll(/\b([A-Z][a-z]{2,})(?:,\s*([A-Z][a-z]{2,}))+(?:,?\s+and\s+([A-Z][a-z]{2,}))?/g)) {
        for (const name of match.slice(1).filter(Boolean) as string[])
          if (!evidenceFor([name]))
            problems.push(
              `README.md:${unit.line} names "${name}" as something the game has, but no file in the plugin defines it`,
            );
      }
      return problems;
    },
  },
];

const rowEvidence = new Map<string, { how: string; where: string } | undefined>();
for (const row of ROWS) {
  const byToken = evidenceFor(row.tokens);
  if (byToken) {
    rowEvidence.set(row.name, { how: byToken.token, where: `${byToken.at.path}:${byToken.at.line}` });
    continue;
  }
  const byFile = row.files ? evidenceFiles.find((file) => row.files!(file.path)) : undefined;
  rowEvidence.set(row.name, byFile ? { how: "a file named for it", where: byFile.path } : undefined);
}

// The three canonical mock sentences are this tool's own words, quoted back, so
// they are not read as claims about the plugin. That is the only thing the
// exemption buys, and it buys it only for a unit that equals one of them exactly:
// the contradiction scan above already ran over them like everything else.
const claims = units.filter((unit) => !isCanonicalMockSentence(unit.text) && isClaim(unit));
const classified = new Set<Unit>();

for (const row of ROWS) {
  const matching = claims.filter((unit) => subjectApplies(unit, row.subject));
  for (const unit of matching) classified.add(unit);
  const evidence = rowEvidence.get(row.name);

  if (matching.length && !evidence)
    for (const unit of matching)
      fail(
        `capability "${row.name}"`,
        `README.md:${unit.line} claims it in the present tense but the plugin has no ${row.what}\n`
        + `    claim: "${unit.text.slice(0, 160)}"\n    ${row.missing}`,
      );

  if (row.ground)
    for (const unit of matching) for (const problem of row.ground(unit)) fail(`capability "${row.name}"`, problem);

  if (!matching.length && evidence && row.disclosure && !row.disclosure.test(readme))
    fail(
      `capability "${row.name}"`,
      `${evidence.how} is in the plugin at ${evidence.where} but the README never discloses it\n    ${row.undisclosed ?? ""}`,
    );

  audited.push(
    `${row.name}: ${matching.length} present-tense claim(s); evidence ${evidence ? `${evidence.how} at ${evidence.where}` : "absent"}`,
  );
}

// ---------------------------------------------------------------------------
// 4a. Every key the README names, whether or not the sentence looks like a claim
// ---------------------------------------------------------------------------
//
// Grounding used to run only on units the row had already classified as claims,
// which meant a Controls table row -- "| `Home` | jumps to the first stall |" --
// carried no recognised verb, was not a claim, and was never grounded. A key
// name in backticks is a promise to a parent however the sentence is shaped, so
// this pass is unconditional over every unit. A negated unit ("`F7` does
// nothing") is the one exception.

let keysChecked = 0;
for (const unit of units) {
  if (NEGATOR.test(unit.text)) continue;
  for (const key of keysNamedIn(unit.text)) {
    keysChecked += 1;
    if (!keyIsHandled(key))
      fail(
        "keyboard grounding",
        `README.md:${unit.line} names \`${key}\` as a key this plugin responds to, but no plugin file handles it: nothing declares Qt.Key_${KEY_ALIASES[key] ?? key}, Keys.on${KEY_ALIASES[key] ?? key}Pressed or StandardKey.${KEY_ALIASES[key] ?? key}.\n    claim: "${unit.text.slice(0, 160)}"`,
      );
  }
}
audited.push(`keyboard: ${keysChecked} backticked key name(s) in the README, each grounded in a Qt key identifier`);

// ---------------------------------------------------------------------------
// 4b. A denial has to stay true as the tree grows
// ---------------------------------------------------------------------------
//
// The forward direction stops a sentence claiming what is not there. This is the
// other half: a sentence saying something is *not* there, left standing after it
// arrives. "No game screen is built yet" is exactly as false as an overclaim
// once ui/Garage.qml lands, and nothing in round 2 would have noticed.

const DENIALS: { phrase: RegExp; row: string; message: string }[] = [
  { phrase: /\bno (?:game )?screens? (?:is|are) built\b|\bno screens? exists?\b/i, row: "game screen", message: "a screen from the settled design exists as a file" },
  { phrase: /\bnothing is written to disk\b|\bwrites no files at all\b|\bno save file\b/i, row: "save file", message: "the plugin can write files" },
  { phrase: /\bthere is no (?:sound|audio)\b|\bno audio loader has been built\b/i, row: "audio", message: "a multimedia token is in the plugin" },
  { phrase: /\bno overlay\b/i, row: "overlay and bar widget", message: "a shell window exists" },
];

for (const denial of DENIALS) {
  if (!denial.phrase.test(readme)) continue;
  const evidence = rowEvidence.get(denial.row);
  if (!evidence) continue;
  const line = readme.slice(0, readme.search(denial.phrase)).split("\n").length;
  fail(
    "stale denial",
    `README.md:${line} still says this is not built, but ${denial.message} (${evidence.how} at ${evidence.where}). Update the sentence.`,
  );
}

// ---------------------------------------------------------------------------
// 5. A claim this gate has no row for fails loudly
// ---------------------------------------------------------------------------
//
// The round-2 report appended seven false claims about screens, keyboard
// behaviour, modes, records, the data file, network sync and a screenshot, and
// every one exited 0 because the table had three rows. Silence is the bug. A
// capability word in a present-tense sentence that no row recognises is now a
// failure that names itself.

const CLAIM_VOCABULARY = new RegExp(
  [
    ROWS.map((row) => row.subject.source).join("|"),
    INVARIANTS.map((invariant) => invariant.contradiction.source).join("|"),
    "\\b(?:screenshot|preview image|clipboard|camera|microphone|notification|database|cache|cookie"
    + "|account|login|password|friend|invite|chat|message|profile|leaderboard|achievement|reward)\\b",
  ].join("|"),
  "i",
);

for (const unit of claims) {
  if (classified.has(unit)) continue;
  if (!subjectApplies(unit, CLAIM_VOCABULARY)) continue;
  fail(
    "unclassified claim",
    `README.md:${unit.line} asserts a capability in the present tense that this gate has no row for.\n`
    + `    claim: "${unit.text.slice(0, 160)}"\n`
    + "    Add a row to ROWS in src/tools/check-readme.ts so the claim is checked against the tree, or reword the sentence.",
  );
}

// ---------------------------------------------------------------------------
// 6. Images
// ---------------------------------------------------------------------------
//
// No image in this repository is a picture of the running plugin, and the one
// image it ships is a multiplayer lobby. Round 2 embedded it as a screenshot of
// the current game and the gate approved it.

for (const match of readme.matchAll(/!\[([^\]]*)\]\(([^)\s]+)\)/g)) {
  const line = readme.slice(0, match.index).split("\n").length;
  fail(
    "embedded image",
    `README.md:${line} embeds \`${match[2]}\`. This repository ships no picture of the running plugin, so an embedded image reads as a screenshot of one. Remove the embed, or add the file to this rule deliberately.`,
  );
}

// The marketplace reads `preview.png` from the repository root. Round 3 found one
// tracked at HEAD, byte-identical to `docs/garage-room-mock.png` -- the multiplayer
// lobby this README says must never be used as its preview -- under precisely that
// filename. Nothing in this gate had a rule about it. Until M6 produces a real one
// from a recording of the finished game, a root preview.png is a failure. Delete
// this rule in the same commit that adds the real image, deliberately.
if (tree.paths.has("preview.png"))
  fail(
    "preview image",
    "preview.png exists at the repository root. This repository ships no picture of the running plugin, and the marketplace"
    + " publishes this exact filename as the plugin's preview, so whatever it holds is presented to a parent as a screenshot"
    + " of the game. The real one is made at M6 from a recording of the finished game; until then there is none.",
  );
else audited.push("preview image: no preview.png at the repository root, as NOTICE says");

const SCREENSHOT_CLAIM =
  /\b(?:screenshot of (?:this|the) (?:plugin|game)|as the game draws it|what the game looks like|pictured above|shown above|the screenshot above|screen recording of)\b/i;
for (const unit of units) {
  if (!SCREENSHOT_CLAIM.test(unit.text)) continue;
  if (NEGATOR.test(unit.text)) continue;
  fail(
    "screenshot claim",
    `README.md:${unit.line} presents an image as a picture of the running plugin. There is none in this repository.\n    claim: "${unit.text.slice(0, 160)}"`,
  );
}

// The mock image is described in two files. Round 2 found three different
// descriptions of it, one of which hid the invite code. Every paragraph that
// names the file, in either document, must carry the same words.
{
  const noticePath = join(root, "NOTICE");
  const notice = await readFile(noticePath, "utf8");
  for (const [name, text] of [["README.md", readme], ["NOTICE", notice]] as const) {
    const paragraphs = text.split(/\n\s*\n/);
    const mentioning = paragraphs.filter((paragraph) => paragraph.includes(MOCK_IMAGE));
    if (!mentioning.length) {
      fail("mock image", `${name} never mentions ${MOCK_IMAGE}; both documents must describe it, identically`);
      continue;
    }
    for (const paragraph of mentioning)
      for (const piece of MOCK_DESCRIPTION) {
        const flat = paragraph.replace(/\s+/g, " ");
        if (!flat.includes(piece.replace(/\s+/g, " ")))
          fail(
            "mock image",
            `${name} describes ${MOCK_IMAGE} without the required words. Every paragraph naming that file, in README.md and in NOTICE, must contain, verbatim:\n    "${piece}"`,
          );
      }
  }
  audited.push(`mock image: ${MOCK_IMAGE} described identically in README.md and NOTICE`);
}

// ---------------------------------------------------------------------------
// 7. Sections, content and placeholders
// ---------------------------------------------------------------------------

const REQUIRED_SECTIONS: { number: number; what: string; anchor: RegExp }[] = [
  { number: 1, what: "what it is, who owns it, a link to the Kids Mode hub", anchor: /omarchy-kids-mode/ },
  { number: 2, what: "Install", anchor: /^##\s+Install\b/m },
  { number: 3, what: "Open it", anchor: /^##\s+Open it\b/m },
  { number: 4, what: "Remove", anchor: /^##\s+Remove\b/m },
  { number: 5, what: "Permissions and privacy", anchor: /^##\s+Permissions and privacy\b/m },
  { number: 6, what: "Dependencies", anchor: /^##\s+Dependencies\b/m },
  { number: 7, what: "License and attributions", anchor: /^##\s+Licen[cs]e\b/im },
  { number: 8, what: "the hub sentence, in those words", anchor: /The plugin never collects anything about a child\./ },
];

const REQUIRED_CONTENT: { what: string; anchor: RegExp }[] = [
  { what: "Install gives a pasteable `omarchy plugin add ... --enable`", anchor: /omarchy plugin add \S+ --enable/ },
  { what: "Open it gives a pasteable keybinding line", anchor: /omarchy-shell shell toggle \S+/ },
  { what: "Remove gives the `omarchy plugin remove` verb", anchor: /omarchy plugin remove /},
  { what: "Permissions states the privilege position for the scanner's negation rule", anchor: /needs no sudo or pkexec/ },
  { what: "the README's own gate is named", anchor: /npm run check:readme/ },
  {
    what: "the README certifies its own present tense (deleting this sentence is a failure, not a downgrade)",
    anchor: /Every present-tense sentence in this README describes something that is in this repository\./,
  },
  {
    what: "the README says which of its claims were read from source rather than executed",
    anchor: /read from source rather than executed/i,
  },
  {
    what: "the README says what its own gate cannot check",
    anchor: /^###?\s+What this gate does not check\b/m,
  },
];

for (const section of REQUIRED_SECTIONS)
  if (!section.anchor.test(readme)) fail("required section", `${section.number}. ${section.what} is missing`);
for (const item of REQUIRED_CONTENT)
  if (!item.anchor.test(readme)) fail("required content", item.what);

// The certification has to be enforced by the command it names.
const packageJson = await readFile(join(root, "package.json"), "utf8");
if (!/"check"\s*:\s*"[^"]*check:readme/.test(packageJson))
  fail("honesty claim", "README.md certifies its own present tense, but check:readme is not part of `npm run check`");
else audited.push("honesty claim: made, and npm run check runs this gate");

const placeholder = /<(?:owner|you|your[a-z-]*|name|id|user(?:name)?|repo|path|version|todo|tbd|x)>/gi;
for (const match of readme.matchAll(placeholder))
  fail("placeholder", `"${match[0]}" survives in the README; substitute the real value`);
for (const match of readme.matchAll(/\bpath\/to\/|\bTODO\b|\bFIXME\b|\bTBD\b/g))
  fail("placeholder", `"${match[0]}" survives in the README`);

// ---------------------------------------------------------------------------
// 8. Plugin ids, install commands, fenced blocks and the paths named in prose
// ---------------------------------------------------------------------------

const manifest = JSON.parse(await readFile(join(root, "manifest.json"), "utf8")) as { id: string };
const idShaped = /\b(?:io|com|org|net|dev|app)\.[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9._-]*\b/g;
const idsInReadme = [...new Set([...readme.matchAll(idShaped)].map((match) => match[0]))];
for (const id of idsInReadme)
  if (id !== manifest.id) fail("plugin id", `README names "${id}" but manifest.json's id is "${manifest.id}"`);
if (!idsInReadme.includes(manifest.id))
  fail("plugin id", `the README never names the plugin id "${manifest.id}"`);

// Every install command, not just the first: round 2 appended a second one
// pointing at another repository and the gate never looked.
const origin = spawnSync("git", ["remote", "get-url", "origin"], { cwd: root, encoding: "utf8" });
const expectedOrigin = origin.status === 0 ? `${origin.stdout.trim().replace(/\.git$/, "")}.git` : undefined;
let installCommands = 0;
for (const match of readme.matchAll(/omarchy plugin add (\S+) --enable/g)) {
  installCommands += 1;
  const url = match[1]!;
  if (!url.endsWith(".git"))
    fail("install command", `"${url}" has no .git suffix; repositoryGitUrl() in the marketplace's build-catalog.mjs appends .git to every installCommand it writes`);
  else if (expectedOrigin && url !== expectedOrigin)
    fail("install command", `README installs from "${url}" but origin is "${expectedOrigin}"`);
}
if (installCommands === 0) fail("install command", "the README gives no install command");
audited.push(
  `install command: ${installCommands} occurrence(s), ${expectedOrigin ? `all equal to origin + .git ("${expectedOrigin}")` : "no git origin available, .git suffix checked only"}`,
);

// Fenced blocks are commands, not prose. They must say what language they are,
// they may not smuggle a claim, and an `rm` in one may only delete this
// plugin's own data file.
const FENCE_LANGUAGES = new Set(["sh", "bash", "zsh", "lua", "json", "qml", "js", "ts", "yaml", "yml", "text", "console"]);
const SAFE_RM = /^rm(?: -f)? (?:~|\$XDG_DATA_HOME)\/[^\s]*turbo-tables-solo\/[^\s]+$/;
for (const fence of fences) {
  if (!FENCE_LANGUAGES.has(fence.language))
    fail("fenced block", `README.md:${fence.line}: the block is tagged "${fence.language || "(nothing)"}"; tag it with the language it is`);
  for (const [offset, line] of fence.body.entries()) {
    const at = fence.line + offset + 1;
    if (/^[A-Z][^`]*\s\w+.*\.\s*$/.test(line.trim()) && !/^[#/]/.test(line.trim()))
      fail("fenced block", `README.md:${at}: a prose sentence inside a code fence is not a command and is not checked as prose -- move it out\n    "${line.trim().slice(0, 120)}"`);
    if (/^\s*rm\b/.test(line) && !SAFE_RM.test(line.trim()))
      fail(
        "remove command",
        `README.md:${at}: \`${line.trim()}\` is not a safe removal. The README may only tell a parent to delete this plugin's own data file, with no -r and no wildcard.`,
      );
  }
}

// Every repository path the README names has to exist -- including the
// root-level ones, which the previous version skipped because they have no "/".
const extensions = /\.(?:md|qml|mjs|js|ts|json|png|wav|frag|qsb|lua|yml|yaml|txt)$/i;
const ROOT_DOCUMENTS = new Set(["README", "LICENSE", "NOTICE", "COPYING", "CHANGELOG"]);
// A bare basename may belong to another project -- `build-catalog.mjs` is the
// marketplace's, `shell.json` is Omarchy's. These naming conventions are ours,
// so a bare one of these has to exist here. Round 2 found `TurboTables.qml`,
// `NOTICE` and `manifest.json` exempt from existence checking entirely.
const OURS_BY_CONVENTION = /^(?:[A-Za-z0-9._-]+\.qml|manifest\.json|package\.json|tsconfig\.json|qmldir)$/;
const candidates = new Set<string>();
for (const match of readme.matchAll(/`([^`\n]+)`/g)) candidates.add(match[1]!.trim());
for (const match of readme.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) candidates.add(match[1]!.trim());

let pathsChecked = 0;
for (const candidate of candidates) {
  if (/^[~/$]|:\/\/|^\.\/|\s/.test(candidate)) continue; // home, absolute, URL, variable, a command
  if (candidate.endsWith("/")) continue; // a directory named in prose
  const bare = !candidate.includes("/");
  if (bare && !ROOT_DOCUMENTS.has(candidate) && !OURS_BY_CONVENTION.test(candidate)) continue;
  if (!extensions.test(candidate) && !ROOT_DOCUMENTS.has(candidate)) continue;
  pathsChecked += 1;
  if (!tree.paths.has(candidate))
    fail("repository path", `the README names \`${candidate}\`, which does not exist in the tree`);
}

// A directory the README calls empty has to be empty.
for (const unit of units) {
  if (!/empty director/i.test(unit.text)) continue;
  for (const match of unit.text.matchAll(/`([^`\n]+\/)`/g)) {
    const directory = match[1]!;
    const inside = tree.directories.get(directory);
    if (inside === undefined) {
      fail("empty directory", `the README names \`${directory}\`, which does not exist in the tree`);
      continue;
    }
    const real = inside.filter((name) => name !== ".gitkeep");
    if (real.length)
      fail("empty directory", `README.md:${unit.line} calls \`${directory}\` empty, but it holds ${real.join(", ")}`);
  }
}

// ---------------------------------------------------------------------------

const scopeSummary = `${pluginFiles.length} plugin text files (${evidenceFiles.length} of them source), ${invariantFiles.length} files under the invariants, out of ${tree.files.length} in the repository`;

if (failures.length) {
  console.error(failures.join("\n"));
  console.error(`\nREADME check failed with ${failures.length} problem(s).`);
  process.exitCode = 1;
} else {
  console.log("README check passed.");
  console.log(`  scope: everything is the plugin except the allow-list below -- ${scopeSummary}`);
  for (const entry of NOT_THE_PLUGIN) console.log(`    not the plugin: ${entry.match.padEnd(20)} ${entry.why}`);
  console.log("  not walked at all -- the second list, printed here because round 3 was right that it was hidden:");
  for (const entry of NOT_WALKED) console.log(`    not walked:     ${entry.match.padEnd(20)} ${entry.why}`);
  console.log("    (0 .qml files found under any of them; a .qml file there is a failure)");
  console.log(`  README: ${units.length} units read, ${claims.length} of them present-tense claims; ${ROWS.length} capability rows`);
  console.log(`  invariants: ${INVARIANTS.length}, asserted unconditionally, each disclosed in the README`);
  console.log(`  ids: ${idsInReadme.length} plugin id string(s), all equal to manifest.json's "${manifest.id}"; 0 placeholders`);
  console.log(`  paths: ${pathsChecked} repository path(s) named in the README, all present`);
  for (const line of audited) console.log(`    ${line}`);
}
