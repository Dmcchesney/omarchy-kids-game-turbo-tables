# Contributing

Turbo Tables is a times-table kart sprint for children aged 7 to 11, built as an Omarchy shell
plugin and a spoke of the [Omarchy Kids Mode hub](https://github.com/markcuda/omarchy-kids-mode).
You do not need to be a developer to help. Playing it with a child and saying what happened is the
most useful thing anyone can do right now.

## Ways in

| Time you have | Do this |
| --- | --- |
| Ten minutes | Install it, race once, and file a [play-test report](../../issues/new?template=play-test.yml) |
| An evening | Pick an issue labelled `good first issue` or `help wanted` and open a pull request |
| With your child | Race together, then file the report with an age band only, never a name, photo or exact age |
| Something is wrong | File a [bug](../../issues/new?template=bug.yml), with the screen size and what you pressed |

## Rules

1. **Nothing about a real child.** No names, photos, voices, usernames or exact ages, anywhere:
   not in an issue, not in a screenshot, not in a commit. Age bands are fine.
2. **The game never collects anything.** No network code, no processes, no free-text entry, no name
   field, no dates in the save file. `npm run check:readme` asserts all four against every file in
   the tree, unconditionally, and a pull request that breaks one cannot pass CI.
3. **AI help is fine. Say so** in the pull request, and own every line you submit.
4. **The design is settled.** [docs/design.md](docs/design.md) is the specification and its
   Decisions table records why. A change to a rule, a number or a mechanic starts as an issue that
   argues against the recorded reason, not as a pull request.
5. **Never run `npm install` inside the checkout.** A `node_modules` directory contains symlinks,
   and `omarchy plugin validate` refuses a plugin with a symlink anywhere in it. Every tool runs
   through `npx`, and `npm run check` fails outright if `node_modules` exists.
6. Be kind to beginners. Parents and teachers are exactly who this needs.

## Running it on Omarchy

The plugin is a directory of QML and JavaScript with no build step. Clone it where Omarchy looks for
third-party plugins and enable it:

```sh
git clone https://github.com/Dmcchesney/omarchy-kids-game-turbo-tables.git \
  ~/.config/omarchy/plugins/io.github.dmcchesney.turbo-tables-solo
omarchy plugin enable io.github.dmcchesney.turbo-tables-solo
```

Saving any file under that directory reloads the plugin in the running shell, so you can leave an
editor open and watch a change land. Open the game from the kart button in the bar, or with
`omarchy-shell shell toggle io.github.dmcchesney.turbo-tables-solo`. QML errors appear in
`qs log -p /usr/share/omarchy/shell --tail 100`.

## Running the checks

You need Node 24 and the Qt 6 declarative tools. On Omarchy or any Arch system:

```sh
sudo pacman -S --needed nodejs npm qt6-declarative
```

Then, from the checkout:

```sh
npm run check
qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml
qmltestrunner -platform offscreen -import ui -import tests/qml-shell -input tests/qml-shell
```

`npm run check` is the whole gate CI runs: the engine's tests and seed vectors, the type check,
the layer boundary (nothing under `ui/` or `src/` may touch the shell), the committed bundle's
freshness, the sprite, prop, terrain and sound manifests, the README honesty gate, and the
marketplace's own security scanner. The scanner needs a checkout of
`omacom/omarchy-plugin-marketplace` beside this one, or `TURBO_TABLES_MARKETPLACE` pointing at
one. The two `qmltestrunner` lines are the screen tests and the shell tests; set
`QT_QPA_PLATFORM=offscreen` and `QT_QUICK_BACKEND=software` if a window would otherwise open.

Any screen can be run on its own, without the shell, through the harness:

```sh
qml -platform offscreen -I dev/imports dev/Harness.qml -- --screen Race --shot /tmp/race.png --exit
```

`dev/Harness.qml` documents every flag at the top of the file: seeding the save file, pressing
keys, clicking, injecting a power-up event, measuring frame rate, dumping every text element with
its position.

Blender is needed only to rebake the car and prop sprites, and only on a machine that has it; the
baked sheets are committed and `npm run check:sprites` verifies them against their manifest, so a
contributor never needs Blender to work on the game.

## How the code is laid out

- `src/engine/` is the rules, in TypeScript, as one pure function `step(state, input, now)`.
  `npm run build` compiles it to `engine/engine.mjs`, which is committed and is what the shell
  loads. Change the engine and the bundle in the same commit; `npm run check:bundle` enforces it.
- `ui/` is every screen, in QML that never imports the shell. `dev/imports/` holds the mock theme
  it is bound against, so screens run and are tested on any machine.
- `TurboTables.qml`, `BarWidget.qml` and `shell/` are the only files that talk to Omarchy: the
  overlay window, the bar button, the theme bridge, the save file, the sound.
- `assets/` is baked art and sound, each directory with a manifest of SHA-256 hashes and a check
  that the committed files match it.

[docs/plan.md](docs/plan.md) explains the four layers and how the game was built; `HANDOFF.md`
says where every piece stands and what is open.

## Pull requests

Branch from `main`, keep the change to one thing, and open the pull request against `main`. CI
must be green. If you changed what the game does, say what you played to see it work and at
which screen size; the game is checked at 1920 by 1080, 1366 by 768 and 1024 by 600. If you
changed a rule's test, show that the test fails when the rule is broken: a test that passes either
way proves nothing, and that standard is applied to every test in this repository.

Everything here is [MIT](LICENSE). By contributing you agree to that.
