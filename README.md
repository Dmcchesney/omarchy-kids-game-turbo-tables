# Turbo Tables

A times-table kart sprint for children ages 7 to 11. The design is twelve laps for the twelve tables,
three AI rivals racing alongside, and a clean streak that earns a powerup picked from a hand of three.
Solo, offline, and keyboard-only. It runs as an Omarchy shell overlay with a kart button in the bar.

Maintained by Don McChesney (`Dmcchesney`) as a games spoke of the
[Omarchy Kids Mode hub](https://github.com/markcuda/omarchy-kids-mode).

| | |
| - | - |
| Plugin id | `io.github.dmcchesney.turbo-tables-solo` |
| Kinds | `overlay` and `bar-widget` |
| Category | Kids |
| License | MIT |

**Status: in development.** The overlay opens, takes the keyboard, and closes, and the rules engine
behind it is written and covered by tests. The overlay hosts the garage screen: a parent who installs this today and
clicks the kart button gets the real garage, and the kart, paint, number and
race settings they change there are written to one file and are still there
next time. The other screens in the design are not wired into the overlay
yet, and there is no sound yet. The settled design and the
build plan are in
[docs/design.md](docs/design.md) and [docs/plan.md](docs/plan.md).

Every present-tense sentence in this README describes something that is in this repository. Where a
capability is designed but not built, the sentence is in the future tense and says so.

`npm run check:readme` is the gate behind that promise. This is the whole of what it does:

- It asserts four safety invariants against the tree, unconditionally: no network code, no process
  or shell execution, no free-text entry and no name field, and no stored dates. They are a fixed
  list in `src/tools/check-readme.ts`. Editing this README cannot switch one of them off.
- Their scope is every file in the repository except a short allow-list it prints on every run, plus
  every `.qml` file with no exception at all.
- It requires this README to disclose each of the four, and fails if a sentence here asserts the
  opposite of one.
- It reads a present-tense capability sentence here against source code in the tree, with comments
  and string literals removed first, so no comment can stand in for an implementation. Lines inside
  fenced code blocks are read the same way, comment markers stripped, so a fence is not a hiding
  place for a sentence.
- Every key name this README writes in backticks has to be handled by a Qt key identifier in a plugin
  file — `Qt.Key_Name`, `Keys.onNamePressed` or `StandardKey.Name` — whether or not the sentence
  around it looks like a claim.
- A capability sentence it has a vocabulary for but no rule for is a failure, not a pass.
- A plugin `.qml` file may not assemble a name, a URL or an object at runtime: no `join`, no
  `globalThis`, no computed member access on a global, no `Qt.createComponent`, no dynamic `import`.
  String pieces joined by `+` or by an array are read as the string they spell before the token lists
  run, so spelling `XMLHttpRequest` one character at a time is the same as writing it.
- It checks the flat things: required sections, content anchors, the plugin id, every install
  command against `git remote`, placeholders, the repository paths named here, the shape of the
  removal command, and the wording used for the one image in `docs/`.

What it cannot do is listed under [What this gate does not check](#what-this-gate-does-not-check).

## Install

```sh
omarchy plugin add https://github.com/Dmcchesney/omarchy-kids-game-turbo-tables.git --enable
```

That is character for character the command the marketplace catalog generates for this repository:
`repositoryGitUrl()` in the marketplace's `build-catalog.mjs` appends `.git` to the repository URL of
every `installCommand` it writes. The command clones the repository into
`~/.config/omarchy/plugins/io.github.dmcchesney.turbo-tables-solo/`, validates the manifest, and
enables both kinds. There is no build step: the game's rules are committed as a ready-to-run ES module
at `engine/engine.mjs`, so the plugin runs from the repository exactly as cloned.

## Open it

Click the kart button in the bar. It toggles the overlay and nothing else.

Parents who prefer a key can add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Turbo Tables", "omarchy-shell shell toggle io.github.dmcchesney.turbo-tables-solo")
```

`Escape` closes the overlay and hands the keyboard straight back to the desktop.

## Remove

```sh
omarchy plugin remove io.github.dmcchesney.turbo-tables-solo --yes
```

`omarchy plugin remove [id] [--yes]`, aliased `omarchy plugin rm`, is a real Omarchy 4 verb; the
command above was read back from `omarchy plugin remove --help` on an Omarchy 4 machine. `--yes` is
needed only when the command is not run from a terminal. Omarchy disables the plugin, which drops the
kart button's entry from `~/.config/omarchy/shell.json`, and then deletes the plugin folder. One
caveat worth knowing: Omarchy drops a single `shell.json` entry per disable and this plugin declares
two kinds, so the overlay's own `{ "id": ... }` line under `plugins` is left behind. It is inert once
the folder is gone, and one more

```sh
omarchy plugin disable io.github.dmcchesney.turbo-tables-solo
```

clears it.

**How strong that evidence is.** The `omarchy plugin remove [id] [--yes]` form, the `omarchy plugin rm`
alias, `omarchy plugin disable` and the two-entry `shell.json` caveat above were all **read from source
rather than executed**: from `omarchy plugin remove --help` and from Omarchy 4's own plugin scripts on a
development VM. A full add-then-remove cycle has deliberately not been run against this checkout,
because the removal deletes the plugin folder and this checkout is the working tree. One real cycle on a
throwaway clone is a task for M7, before submission. Nothing in this repository verifies any of it:
`npm run check:readme` checks the shape of these commands, never their behaviour.

The garage writes one file it owns, and deleting it is all that is left to do. It holds the settings
and records described under Permissions and privacy, and nothing else:

```sh
rm ~/.local/share/turbo-tables-solo/garage.json
```

That path holds nothing until the save file is built, so the command is only useful once it exists;
`rm` will report the file is missing before then. If `XDG_DATA_HOME` is set, the file will be at
`$XDG_DATA_HOME/turbo-tables-solo/garage.json` instead.

## Permissions and privacy

Turbo Tables:

- makes no network requests, and contains no network code at all, not merely no network features
- runs nothing privileged: it starts no processes, runs no shell commands, and ships no executables
- needs no sudo or pkexec
- collects nothing about a child
- has no name field, no free-text entry anywhere, and stores no dates
- reads and writes exactly one file it owns, `garage.json` under
  `${XDG_DATA_HOME:-~/.local/share}/turbo-tables-solo/`, and touches no other
  configuration

What that one file holds: chosen kart body, paint and number; the stored preferences for reduced
motion, scanlines and the timer, plus a `sound` key that nothing reads yet; the rival level; best
times and ghost timelines per preset; and one correct-answer count per multiplication fact. Nothing
that identifies anybody, nothing that leaves the machine.

Omarchy loads plugin code into the child's session with no sandbox, so any plugin can do whatever the
logged-in user can. That is exactly why this one has no network code and no process calls to audit:
the list above is meant to be checkable by reading the repository, and the checks below are how it
stays true.

## Dependencies

- **Omarchy 4** with the Quattro shell. The overlay and bar widget use only the documented plugin
  contract.
- **Qt Multimedia** for sound, and it will be an optional one. There is no audio in the plugin yet and
  no audio loader has been built. When it lands, the sound component will sit behind a loader and the
  game will fall back to a silent stub with the same interface when the module is absent.

Nothing else. The repository has no runtime dependencies, no lockfile, and no `node_modules`; the build
and check tooling is fetched on demand by `npx` and never lands inside the checkout, because a
`node_modules` directory here would break `omarchy plugin validate`.

## Development and checks

Node 24 and Qt 6 on the developer machine; nothing is installed into the checkout.

```sh
npm run check
```

runs the whole gate, and each part can be run alone:

| Command | What it proves |
| - | - |
| `npm test` | the engine's rules, against committed seed-to-sequence vectors |
| `npm run check:types` | `src/engine` type-checks with no dependencies and no ambient types |
| `npm run check:boundary` | no symlink, executable, installer-like name, `bin/`, `scripts/` or `node_modules`; the manifest against the marketplace's validator rules; and no shell token in any file except the three that may hold one, read both as written and with string concatenations glued back together |
| `npm run check:bundle` | `engine/engine.mjs` is the current build of `src/engine`, not a stale copy |
| `npm run check:readme` | the four safety invariants against the whole tree, this README's disclosure of them, and each present-tense capability claim here against stripped source — the list above |
| `npm run scan` | the marketplace's own security-baseline rules, run against the working tree, and that the index holds no file the working tree has lost |
| `npm run build` | rebuilds the committed bundle |

`npm run scan` reports `passed` with no findings and no capabilities. It runs the marketplace's analysis
unmodified against the files on disk, so a change is checked before it is committed rather than after it
is pushed; `npm run scan -- --remote` reproduces what the marketplace itself will run, against the last
pushed commit. The same gate runs in CI on every push.

### Things this repository ships on purpose

Two files here are development material rather than game code. Both are required by this project's own
build plan, under "Prerequisites before kicking it off" in [docs/plan.md](docs/plan.md), and both are
listed here so a reviewer can see they were decided rather than overlooked:

- `.claude/skills/gauntlet-loop/` — 8 KB describing the development workflow this repository is built
  with, required in-tree by prerequisite 4. The shell never loads it and it is not part of the running
  plugin; its licence and provenance are recorded in [NOTICE](NOTICE).
- the design mock under `docs/` — 1.78 MB, required by prerequisite 3, and described in its own
  paragraph below because that description is a fixed string in `src/tools/check-readme.ts` rather
  than prose anybody may reword.

`docs/garage-room-mock.png` is a design mock of the future multiplayer lobby: an invite code, four
named children, ready toggles and APPROVED FRIEND / DEVICE VERIFIED badges, none of which exists
in this plugin, which is solo and offline. Only the kart stall on its left, the body, paint and number
pickers, is the reference the solo garage will be built against. It is not a screenshot of this plugin
and must never be used as its preview.

Those three sentences are owned by the gate, not by this document: [NOTICE](NOTICE) carries them
verbatim, `npm run check:readme` fails if the two documents ever differ, and the exemption that keeps
the gate from reading them as claims about the plugin applies to each sentence exactly, in full, and to
nothing else. Both files are reconsidered at M6, when the submission commit is tagged and the real
preview image is made.

The directories the build plan has still to fill carry a `.gitkeep`, so the shape of the finished
plugin is visible and reviewable before the files land.

### What this gate does not check

`npm run check:readme` is a text-and-token check, not a program analyser. Its limits, plainly:

- It cannot tell whether a capability that exists is *correct*, and it cannot tell whether it is
  *reachable*. `ui/Garage.qml` existing makes a sentence about the garage screen pass; that the
  overlay does not yet load that file is something only a person reading `TurboTables.qml` will
  notice, which is why the status line above says it in words.
- **Its vocabulary is a closed list.** A capability nobody wrote a row or a keyword for is not
  recognised as a claim at all, so it is neither checked nor reported: accessibility, fonts, colour,
  localisation and performance are all outside it today. "A claim this gate has no rule for fails
  loudly" is true only of claims whose *words* the gate already knows. This is the largest hole left
  in it, it is not closed, and closing it means inverting the test rather than lengthening the list.
- The runtime-construction rule covers plugin `.qml` files only. A plugin `.mjs` file — the committed
  bundle at `engine/engine.mjs` is one — may still call `join`, and only the token lists (which do
  read glued strings) stand behind it there.
- Its sense of present tense is a verb list, plus passive-voice and participle detection. Ordinary
  English it does not recognise will slip past that test — a table cell reading
  "a weekly digest, mailed to the address in `garage.json`, listing every fact" carries no verb the
  list knows, so it is not a claim and no rule grounds it. The four safety invariants do not rest on
  it: they are unconditional and token-based, and they run whatever this file says.
- Its forbidden-token search uses identifier boundaries, so a token buried inside a longer identifier
  or a longer string literal is not a hit. A single string holding
  `"XMLHttpRequesthttps://example.com"`, sliced apart at runtime, is invisible to this gate.
  `npm run check:boundary` catches that one — its layer-boundary grep is a plain substring search over
  every plugin file, and both greps now read concatenated and array-assembled strings — but
  `check:readme` alone does not, and the two searches disagree on purpose.
- Its evidence is a token in stripped source, not a call graph. An identifier with the right name and
  nothing behind it counts: a property called `SoundEffect` satisfies the audio rule, and a `FileView`
  that is never instantiated satisfies the save-file rule.
- It reads one sentence at a time. A sentence that names a subject, followed by a sentence that
  supplies the verb, is two units, and neither alone carries a claim the gate can check.
- The allow-list of files that are not the plugin — `docs/`, `tests/`, `dev/`, `src/tools/`, the build
  configuration and this file — is not examined for capabilities. Every `.qml` file in those
  directories is still held to the four invariants, but a non-QML capability placed there is out of
  scope by design: a network call in a `.mjs` file under `dev/` passes. What the gate does enforce is
  that no plugin file refers to an allow-listed path — the reference scan glues concatenated and
  array-assembled strings back together first, and it covers the single-file entries as well as the
  directories — so the exemption cannot quietly become an import. The list is short, it is printed on
  every run, and each entry says why.
- There is a second list: four directories the walk never descends into at all (`.git/`,
  `node_modules/`, `coverage/`, `evidence/`). It went undisclosed until round 3 of the package review
  found it. Both tools now print it with a reason per entry, and a `.qml` file found under any of them
  is a failure rather than an exemption.
- Nothing here runs Omarchy. The install, open and remove commands are checked for shape rather than
  executed; the Remove section says which of its claims were read from source rather than executed.
- It does not look at images. The wording used for the one image under `docs/` is checked against
  [NOTICE](NOTICE); the pixels are not. What it does check is that no `preview.png` exists at the
  repository root at all, because the marketplace publishes that exact filename to parents as a
  picture of the game.
- It reads the working tree, not the index. A file deleted from the tree but still staged for commit
  would be invisible to it; `npm run scan` refuses to report at all while an unstaged deletion exists,
  which is the only guard against that.

## License and attributions

Source code is MIT licensed; see [LICENSE](LICENSE). Asset licences and third-party attributions are
recorded in [NOTICE](NOTICE) as assets land.

## For the Kids Mode hub

Turbo Tables is a Tier 1 spoke of the Omarchy Kids Mode hub: solo, offline, no peer, no account.

The plugin never collects anything about a child.

There is no name field, no free text, no telemetry, no analytics, no crash reporting, no dates in the
save file, and nothing that leaves the machine.

Streaks and attacks depart from the hub's pedagogy notes on purpose, and the reasoning is written down in
[docs/design.md](docs/design.md): the streak lives inside a single race and is never stored, shown across
sessions, or tied to days, so it is a race mechanic rather than an attendance hook; and powerups land on
the AI rivals, never on another child, because this game has no other child in it.
