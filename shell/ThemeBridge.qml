import QtQuick
import qs.Commons
import "../ui"

// The theme handoff, and the only place the game meets the shell's palette.
//
// `ui/Theme` is a plain adapter with a default for every property, so a screen
// renders with nothing bound to it and the development harness can assign a
// captured theme by hand. This binds the same properties to the live shell
// singletons instead.
//
// Bindings, not a copy. The harness copies once because it takes a snapshot
// and never changes it; the shell does not work that way. `Color` re-reads
// theme/colors.toml and `Style` re-reads shell.toml whenever the child's theme
// changes, and the design's promise is that the game "belongs to the child's
// theme" -- so a theme switch has to retint the garage while it is on screen,
// with no reload and no reopen. A copy would leave the garage painted in the
// previous theme until the next shell restart.
//
// `restoreMode: Binding.RestoreNone` because there is nothing to restore to:
// Theme's defaults are a fallback for a screen with no shell, not a value the
// shell should be handing back when this bridge goes away.
//
// What is deliberately NOT bound: everything under Theme's "game constants"
// heading. Garage Grid's amber and teal, the eight kart paints and the three
// rival colours are the design's own and are readonly on the adapter, so a
// theme cannot repaint a kart it does not know the meaning of.
Item {
  id: bridge

  visible: false
  width: 0
  height: 0

  // The five palette roles.
  Binding { target: Theme; property: "background"; value: Color.background; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "foreground"; value: Color.foreground; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "accent"; value: Color.accent; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "urgent"; value: Color.urgent; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "muted"; value: Color.muted; restoreMode: Binding.RestoreNone }

  // The menu surface. The design's Theme section names these three, and the
  // reasoning is the emojis overlay's: a theme that styles the menu styles
  // every full-screen surface the shell puts in front of the user, so the
  // garage shares them rather than inventing a fourth surface nobody themes.
  Binding { target: Theme; property: "menuBackground"; value: Color.menu.background; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "menuText"; value: Color.menu.text; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "menuBorder"; value: Color.menu.border; restoreMode: Binding.RestoreNone }

  // Type. `fontFamily` is the fontconfig alias `omarchy font set` writes and
  // `resolvedFamily` is the concrete family it currently resolves to; Theme
  // prefers the resolved name and falls back to the alias, so both are bound.
  Binding { target: Theme; property: "fontFamily"; value: Style.font.family; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "resolvedFontFamily"; value: Style.font.resolvedFamily; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "fontBaseSize"; value: Style.font.baseSize; restoreMode: Binding.RestoreNone }

  // Geometry. Theme treats the shell radius as a floor rather than the radius,
  // because Hyprland's rounding is 0 on a stock install and a garage of
  // square-cornered cards is not the design; the floor lives on the adapter so
  // this bridge stays a plain handoff.
  Binding { target: Theme; property: "shellCornerRadius"; value: Style.cornerRadius; restoreMode: Binding.RestoreNone }
  Binding { target: Theme; property: "spacingScale"; value: Style.spacing.scale; restoreMode: Binding.RestoreNone }
}
