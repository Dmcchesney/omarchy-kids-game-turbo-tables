import QtQuick
import "../../ui"

// A window onto `ui/Theme`, for the entry-point fixture.
//
// The fixture cannot read the Theme singleton itself: it runs from a copy in a
// temporary directory, and a singleton is reached by importing the directory
// that declares it, which from there is not a directory at all. This file sits
// where the import is correct and is loaded by URL under the plugin root, the
// same way the two entry points are.
//
// It reads and never writes. What it is for is one question the shell's own
// tests cannot ask: does `shell/ThemeBridge.qml` *bind* the game's theme to the
// live one, or copy it once? A copy passes every screenshot taken after a
// summon and fails the only thing the design asks for -- that a theme change
// retints the garage while the child is looking at it.
QtObject {
  readonly property color background: Theme.background
  readonly property color foreground: Theme.foreground
  readonly property color accent: Theme.accent
  readonly property color urgent: Theme.urgent
  readonly property color muted: Theme.muted

  readonly property color menuBackground: Theme.menuBackground
  readonly property color menuText: Theme.menuText
  readonly property color menuBorder: Theme.menuBorder

  readonly property string fontFamily: Theme.fontFamily
  readonly property string resolvedFontFamily: Theme.resolvedFontFamily
  readonly property int fontBaseSize: Theme.fontBaseSize
  readonly property int shellCornerRadius: Theme.shellCornerRadius
  readonly property real spacingScale: Theme.spacingScale

  // Two derived roles, so the check reaches past the properties the bridge
  // writes and into what the screens actually paint with.
  readonly property color ground: Theme.ground
  readonly property color focusRing: Theme.focusRing
}
