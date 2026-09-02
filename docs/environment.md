# Development environment

Last verified: 2026-09-02 11:00 EDT

## Host

- macOS 26.6.2 (25G83), Apple Silicon
- Plugin checkout: `/Users/don/Developer/omarchy-kids-game-turbo-tables`
- Marketplace baseline checkout: `/Users/don/Developer/omarchy-plugin-marketplace`
- Marketplace source: `https://github.com/omacom/omarchy-plugin-marketplace.git`
- Marketplace commit at setup: `9c59dd37f4b203ba92dbdc69eeb98aa853579146`

The marketplace checkout is the repository sibling expected by `npm run scan`.

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

The non-graphical SSH session needs `OMARCHY_PATH` for `omarchy-shell`, and Quickshell needs `--any-display` when reading the live Wayland instance.

```sh
ssh omarchy-turbo-tables 'cd ~/.config/omarchy/plugins/io.github.dmcchesney.turbo-tables-solo && omarchy plugin validate .'

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
