// A GATE FOR THE BUG THAT HALF THE DECK DIED OF.
//
// Round 4 of piece F found this in `ui/Picker.qml`, at `e1a3199`:
//
//     property var hand: Engine.dealHand(...).hand          // line 86, the root
//     ...
//     readonly property string chosenCard: (chosen >= 0 && chosen < hand.length)
//     ...
//         Row { id: hand ... }                              // line 531
//
// In QML's unqualified lookup a file-scope `id` beats the root object's own
// property of the same name, so `hand` in that binding resolved to the `Row`.
// `Row.length` is `undefined`, `chosen < undefined` is false, and `chosenCard`
// was the empty string on every frame of every race. `needsTarget` fell with
// it, the panel never offered a rival to aim at, and `cardUsed(index, "")` for
// a targeted card is refused by the engine. THE WRENCH, THE POTHOLE, THE
// PILE-UP AND THE TOW HOOK -- half the deck, and every card that attacks
// anybody -- could be chosen, could print `USE IT`, and then did nothing at
// all.
//
// The failure mode is what makes it worth a machine:
//
//   * the code reads correctly. `hand[chosen]` is exactly what a reader
//     expects, and the `Row` that stole the name is four hundred lines away;
//   * 227 tests passed. Every spending case in `tst_race_keys.qml` happened to
//     choose a `self`-scoped card, so no test ever asked for a target;
//   * nothing is logged, nothing throws, nothing renders wrong. The game
//     quietly stops working.
//
// A memory does not catch that a second time. This does.
//
// THE RULE, and it is deliberately stricter than the bug: no `.qml` file may
// declare an `id` whose name is also declared in that file as a property, a
// property alias, a signal, or a function. The bug needs the id at file scope
// and the property on the root object; this check does not try to work out
// which object a declaration belongs to, because the analysis that would tell
// it apart is exactly the analysis a reader has to do to see the bug, and the
// tree has no legitimate instance of the loose form either -- 67 .qml files,
// zero collisions. A name that means two things in one file is a defect
// whichever object owns it.
//
// The proof this is a red gate and not a green one is in the round-5 report:
// run against `e1a3199:ui/Picker.qml` it fails, naming `hand`, both lines.

import { walkTree, isQml, strip } from "./scope.ts";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");

/** What a name can be declared as, other than an id. */
type Kind = "property" | "signal" | "function";

const DECLARATIONS: { kind: Kind; pattern: RegExp }[] = [
  // `property int foo:`, `readonly property var foo:`, `default property alias
  // foo:`, `required property real foo`, `property list<Item> foo:`. The type
  // may carry dots (`Qt.labs`-style), angle brackets (`list<T>`) or be the
  // literal `alias`.
  {
    kind: "property",
    pattern:
      /\b(?:readonly\s+|default\s+|required\s+)*property\s+(?:alias\s+|[A-Za-z_][\w.]*(?:<[^>\n]*>)?\s+)([A-Za-z_]\w*)\b/g,
  },
  // `signal fired()`, `signal fired(int a)`, `signal fired`
  { kind: "signal", pattern: /\bsignal\s+([A-Za-z_]\w*)\s*[(\s]/g },
  { kind: "function", pattern: /\bfunction\s+([A-Za-z_]\w*)\s*\(/g },
];

const ID_PATTERN = /\bid\s*:\s*([A-Za-z_]\w*)/g;

function lineOf(text: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index && i < text.length; i++) if (text[i] === "\n") line += 1;
  return line;
}

const tree = await walkTree(root);
const qml = tree.files.filter((file) => !file.binary && isQml(file.path));

const failures: string[] = [];
let idsSeen = 0;
let namesSeen = 0;

for (const file of qml) {
  // Comments and string bodies are blanked, so a name written in prose above
  // the code -- and this file is full of them -- is not a declaration.
  const source = strip(file.text);

  const ids = new Map<string, number[]>();
  for (const match of source.matchAll(ID_PATTERN)) {
    const at = lineOf(source, match.index ?? 0);
    const seen = ids.get(match[1]!);
    if (seen) seen.push(at);
    else ids.set(match[1]!, [at]);
  }
  idsSeen += [...ids.values()].reduce((sum, lines) => sum + lines.length, 0);

  const declared = new Map<string, { kind: Kind; line: number }[]>();
  for (const { kind, pattern } of DECLARATIONS) {
    for (const match of source.matchAll(pattern)) {
      const name = match[1]!;
      const line = lineOf(source, match.index ?? 0);
      const seen = declared.get(name);
      if (seen) seen.push({ kind, line });
      else declared.set(name, [{ kind, line }]);
    }
  }
  namesSeen += declared.size;

  for (const [name, idLines] of ids) {
    const clash = declared.get(name);
    if (!clash) continue;
    const where = clash.map((entry) => `${entry.kind} at line ${entry.line}`).join(", ");
    failures.push(
      `${file.path}: "${name}" is both an id (line ${idLines.join(", line ")}) and a ${where}.`
      + ` In QML an unqualified read of "${name}" anywhere in this file resolves to the ID, not to the ${clash[0]!.kind}` +
      `, and nothing warns. Rename one of them, and qualify every unqualified read of it.`,
    );
  }
}

if (failures.length) {
  console.error(failures.join("\n"));
  console.error(
    `\nQML id/name check failed with ${failures.length} collision(s). See the block at the top of src/tools/check-qml-ids.ts for the defect this gate exists for.`,
  );
  process.exitCode = 1;
} else {
  console.log("QML id/name check passed.");
  console.log(
    `  ${qml.length} .qml files, ${idsSeen} ids and ${namesSeen} declared names read with comments and string bodies blanked`,
  );
  console.log(
    "  no id in any file shares a name with a property, property alias, signal or function declared in that same file",
  );
}
