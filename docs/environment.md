# Development environment

Last verified: 2026-09-02 11:00 EDT

## Host

- macOS 26.6.2 (25G83), Apple Silicon
- Plugin checkout: `/Users/don/Developer/omarchy-kids-game-turbo-tables`
- Marketplace baseline checkout: `/Users/don/Developer/omarchy-plugin-marketplace`
- Marketplace source: `https://github.com/omacom/omarchy-plugin-marketplace.git`
- Marketplace commit at setup: `9c59dd37f4b203ba92dbdc69eeb98aa853579146`

The marketplace checkout is the repository sibling expected by `npm run scan`.

## Never install packages inside the plugin checkout

The checkout is mounted into the VM at the plugin path, and `omarchy plugin validate` rejects any symlink inside the folder. A `node_modules` directory contains symlinks (`node_modules/.bin/*`), so `npm install` here breaks validation the moment it runs. The repository therefore has no `devDependencies`: `npm run build`, `check:types`, and `check:bundle` invoke pinned tools through `npx`, which caches them under `~/.npm`, and `npm test` uses Node's built-in runner with native TypeScript. A `preinstall` script refuses `npm install`, and `check:boundary` fails if `node_modules` exists. `check:types` type-checks the pure engine under `src/engine` only; the Node-side tools and tests are validated by running them, since Node type definitions are a package and packages are not installed here.

## Omarchy VM and SSH

- UTM: 4.7.5
- VM: `Omarchy 4 ARM64`
- VM UUID: `DD993D9B-7807-44F5-9D89-26261F3226CC`
- Image: `omarchy-arm-utm-v2.zip` from `https://archive.org/download/omarchy-arm-utm/omarchy-arm-utm-v2.zip`
- Verified SHA-256: `96d4ac82915f8e8044eeb7a1d02312cc8b69728619bdafd09a25fd08b511cde9`
- SSH host alias: `omarchy-turbo-tables`
- Current guest address: `192.168.64.2`
- SSH user: `omarchy`
- Connect with: `ssh omarchy-turbo-tables`
- Host identity file: `~/.ssh/omarchy-turbo-tables-utm`
- Guest architecture: `aarch64`

UTM shared-directory access points at the host plugin checkout. VirtFS mounts it directly and persistently at:

```text
/home/omarchy/.config/omarchy/plugins/io.github.dmcchesney.turbo-tables-solo
```

The mount is a `9p` `share` filesystem configured in `/etc/fstab`. The original image fstab is preserved inside the guest as `/etc/fstab.pre-turbo-tables`. Host edits are visible immediately in the guest. The guest mount is intentionally used as a read-only development view for the unprivileged `omarchy` account; edit the checkout on the Mac.

If the shared-network address changes, obtain the current address with:

```sh
utmctl ip-address "Omarchy 4 ARM64"
```

Then update `HostName` for `omarchy-turbo-tables` in `~/.ssh/config`.

## SSH smoke commands

The non-graphical SSH session needs `OMARCHY_PATH=/usr/share/omarchy` for both `omarchy-shell` and `omarchy plugin enable|list`; without it `omarchy plugin enable` prints "OMARCHY_PATH is not set" and changes nothing. Quickshell needs `--any-display` when reading the live Wayland instance.

Two traps found on 2026-09-02, both now guarded:

- `omarchy-shell shell toggle <id>` exits 0 even when the plugin is not enabled; the only sign is `summon: plugin not enabled, not summoning` in `qs log`. Always confirm `omarchy plugin list` shows `enabled` and `overlay,bar-widget` before trusting a toggle, and grep the log for `not summoning` after it.
- Enabling a two-kind plugin wrote only the bar-widget layout entry at first; the overlay needs its own `{ "id": ... }` entry under `plugins` in `~/.config/omarchy/shell.json`. `OMARCHY_PATH=/usr/share/omarchy omarchy plugin enable <id>` writes it correctly. The overlay is enabled now and renders the bootstrap screen.

```sh
ssh omarchy-turbo-tables 'cd ~/.config/omarchy/plugins/io.github.dmcchesney.turbo-tables-solo && omarchy plugin validate .'

ssh omarchy-turbo-tables 'OMARCHY_PATH=/usr/share/omarchy omarchy plugin list | grep turbo-tables'

ssh omarchy-turbo-tables 'qs log -p /usr/share/omarchy/shell --any-display --tail 100 --no-color'

ssh omarchy-turbo-tables 'OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle io.github.dmcchesney.turbo-tables-solo'

ssh omarchy-turbo-tables 'WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 grim /tmp/turbo-tables-overlay.png'
```

Verified results on 2026-09-02:

- `omarchy plugin validate .`: exit 0.
- `qs log`: exit 0 against the live `wayland-1` shell; the plugin reload produced no Turbo Tables QML error.
- `omarchy-shell shell toggle`: exit 0; the Turbo Tables bootstrap overlay rendered.
- `grim`: exit 0; produced a visually verified 1920×1200 overlay PNG with SHA-256 `b04d26dc46221426d3fe41a251aec7afdd531eb4a476882cbf37b9bc3068d016`.

## Bellringer source

Both required source paths are reachable on this Mac:

- Runtime: `/Users/don/Developer/LiveClassBackend/internal/bellringerruntime/`
  - Repository commit at setup: `c19f8dc70559bb3cd2fafe937d34a4c640028d28`
- Student feature: `/Users/don/Developer/StudentApp3.0-powerups-testing/src/features/bellringer/`
  - Repository commit at setup: `6458f106dd0f44a06544020c98525dc176235278`

These commit values are setup-time provenance, not a claim that either checkout is clean or current with its remote.
