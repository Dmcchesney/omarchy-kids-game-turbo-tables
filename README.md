# Turbo Tables

Turbo Tables is a solo, offline times-table kart sprint for children ages 7 to 11. Don McChesney maintains it for the Omarchy Kids Mode community.

The project is currently at repository and environment bootstrap. Its settled design and implementation plan live in [docs/design.md](docs/design.md) and [docs/plan.md](docs/plan.md).

## Install

```sh
omarchy plugin add https://github.com/Dmcchesney/omarchy-kids-game-turbo-tables --enable
```

## Open it

Use the kart button in the bar. Parents may also add this binding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Turbo Tables", "omarchy-shell shell toggle io.github.dmcchesney.turbo-tables-solo")
```

## Remove

```sh
omarchy plugin remove io.github.dmcchesney.turbo-tables-solo
```

If the family also wants to remove earned records and settings, delete `${XDG_DATA_HOME:-~/.local/share}/turbo-tables-solo/garage.json`.

## Permissions and privacy

Turbo Tables makes no network requests. It reads and writes exactly one file it owns, runs nothing privileged, needs no sudo or pkexec, and collects nothing about a child. There is no name field.

## Dependencies

Qt Multimedia is an optional dependency for sound. The game remains usable without it.

## License

Source code is MIT licensed. Original and third-party asset notices are recorded in [NOTICE](NOTICE).

## Kids Mode hub

This plugin is intended for the Omarchy Kids Mode community. It never collects anything about a child.
