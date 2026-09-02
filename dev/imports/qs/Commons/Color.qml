pragma Singleton
import QtQuick

// MOCK of the Omarchy shell's Color singleton, for layer-2 development on a
// machine that has no shell. Layer 2 (ui/) never imports this; only the
// harness under dev/ does, and it copies the values it reads into the
// ui/Theme adapter. The real singleton lives at
//   /usr/share/omarchy/shell/Commons/Color.qml
// and is a QtObject with the same property names and the same nesting.
//
// Property names are copied from the real file. Values are the ones the real
// singleton produces on the development VM, read on 2026-09-02 from
//   ~/.local/state/omarchy/current/theme/colors.toml   (Tokyo Night, dark)
//   ~/.local/state/omarchy/current/theme/shell.toml
// after the real loadColors()/loadShell() pass, so what is written here is the
// resolved result, not the raw TOML. Where the real file composes a color from
// a base token and an "-alpha" companion, the composed value is written out.
//
// What is deliberately absent: the file readers, the TOML parsers, the theme
// IPC hooks. Those are shell concerns and a mock that reproduced them would be
// testing the shell rather than the game.
QtObject {
  id: root

  // -- foundational palette, from colors.toml -------------------------------
  // background/foreground/accent/urgent/muted are the four roles every
  // surface below falls back to.
  property color foreground: "#a9b1d6"
  property color background: "#1a1b26"
  property color accent: "#7aa2f7"
  property color urgent: "#f7768e"
  property color muted: "#414868"

  // The rest of colors.toml. The real singleton does not expose these as
  // properties -- it folds them into the four roles above -- but the harness
  // prints them in its theme readout, and a second theme swapped in here is
  // the cheapest way to check that nothing in ui/ has a hard-coded hue.
  readonly property QtObject palette: QtObject {
    readonly property color selection: "#292e42"
    readonly property color darkBackground: "#13141c"
    readonly property color darkerBackground: "#0e0e14"
    readonly property color lighterBackground: "#24283b"
    readonly property color darkForeground: "#565f89"
    readonly property color lightForeground: "#b4bee6"
    readonly property color brightForeground: "#c0caf5"
    readonly property color red: "#f7768e"
    readonly property color yellow: "#e0af68"
    readonly property color orange: "#eb927b"
    readonly property color green: "#9ece6a"
    readonly property color cyan: "#449dab"
    readonly property color blue: "#7aa2f7"
    readonly property color magenta: "#ad8ee6"
  }

  // -- per-surface roles, from shell.toml -----------------------------------
  readonly property QtObject bar: QtObject {
    property color background: "#1a1b26"
    property color text: "#a9b1d6"
    property color active: "#f7768e"
  }
  readonly property QtObject popups: QtObject {
    property color background: "#1a1b26"
    property color text: "#a9b1d6"
    property color border: "#7aa2f7"
  }
  readonly property QtObject tooltip: QtObject {
    property color background: Qt.rgba(0.102, 0.106, 0.149, 0.97)
    property color text: "#a9b1d6"
    property color border: "#a9b1d6"
  }
  readonly property QtObject notifications: QtObject {
    property color background: "#1a1b26"
    property color text: "#a9b1d6"
    property color border: "#7aa2f7"
    property color countdown: "#7aa2f7"
  }
  // The surface the overlay reads. menu.border resolves through
  // "hyprland.active-border-foreground", which on this theme is the
  // foreground; scrim and the selected-* roles carry their alpha companions.
  readonly property QtObject menu: QtObject {
    property color background: "#1a1b26"
    property color text: "#a9b1d6"
    property color border: "#a9b1d6"
    property color scrim: Qt.rgba(0.102, 0.106, 0.149, 0.5)
    property color selectedBackground: Qt.rgba(0.663, 0.694, 0.839, 0.08)
    property color selectedText: "#7aa2f7"
    property color selectedBorder: Qt.rgba(0.663, 0.694, 0.839, 0.25)
  }
  readonly property QtObject polkit: QtObject {
    property color background: "#1a1b26"
    property color text: "#a9b1d6"
    property color textError: "#f7768e"
    property color border: "#7aa2f7"
    property color borderError: "#f7768e"
    property color accent: "#7aa2f7"
    property color scrim: Qt.rgba(0.102, 0.106, 0.149, 0.5)
  }
  readonly property QtObject lock: QtObject {
    property color background: Qt.rgba(0.102, 0.106, 0.149, 0.8)
    property color text: "#a9b1d6"
    property color placeholder: Qt.rgba(0.663, 0.694, 0.839, 0.66)
    property color textError: "#f7768e"
    property color border: "#a9b1d6"
    property color borderActive: "#7aa2f7"
    property color borderError: "#f7768e"
    property color selection: Qt.rgba(0.478, 0.635, 0.969, 0.45)
  }
  readonly property QtObject imagePicker: QtObject {
    property color scrim: Qt.rgba(0.102, 0.106, 0.149, 0.5)
    property color text: "#a9b1d6"
    property color selectedBorder: "#7aa2f7"
    property color unselectedBorder: Qt.rgba(0.663, 0.694, 0.839, 0.28)
  }
}
