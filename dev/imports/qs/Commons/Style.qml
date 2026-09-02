pragma Singleton
import QtQuick

// MOCK of the Omarchy shell's Style singleton. Same contract as the Color
// mock beside it: layer 2 never imports this, the harness does.
// The real singleton lives at
//   /usr/share/omarchy/shell/Commons/Style.qml
//
// Property and function names are copied from the real file, including the
// space()/spaceReal() pair, the nested `spacing`, `font` and `bar` objects,
// and the fontPx() multipliers. Values are the ones the real singleton
// produces on the development VM, read on 2026-09-02:
//
//   [font] base-size = 12, no per-token overrides    -> the whole type scale
//   [spacing] scale = 1.0, scale-with-font = true    -> effective scale 1.0
//   [bar] size-horizontal = 26, size-vertical = 28
//   hyprctl decoration:rounding = 0                  -> cornerRadius 0
//   hyprctl general:gaps_out   = 10                  -> gapsOut 5 (halved)
//
// cornerRadius being 0 on a stock install is the reason ui/Theme treats the
// shell radius as a floor it may only raise, never as the radius itself.
QtObject {
  id: root

  // -- Hyprland-derived structure ------------------------------------------
  property int cornerRadius: 0
  property int gapsOut: 5

  // -- control state tokens, from [controls] in shell.toml ------------------
  readonly property int normalBorderWidth: 1
  readonly property int hoverBorderWidth: 1
  readonly property int selectedBorderWidth: 0
  readonly property int focusBorderWidth: 1

  readonly property real normalFillAlpha: 0.04
  readonly property real hoverFillAlpha: 0.08
  readonly property real selectedFillAlpha: 0.18
  readonly property real pressedFillAlpha: 0.22
  readonly property real focusFillAlpha: 0.08
  readonly property real selectionFillAlpha: 0.35

  readonly property real normalBorderAlpha: 0.4
  readonly property real hoverBorderAlpha: 0.25
  readonly property real selectedBorderAlpha: 1.0
  readonly property real focusBorderAlpha: 0.25

  // -- spacing --------------------------------------------------------------
  property real spacingScale: 1.0
  property bool spacingScaleWithFont: true
  readonly property real effectiveSpacingScale: spacingScale * (spacingScaleWithFont ? fontScale : 1)

  function spaceReal(px) {
    var n = Number(px)
    if (!isFinite(n) || n <= 0)
      return 0
    return n * effectiveSpacingScale
  }

  function space(px) {
    var n = spaceReal(px)
    if (n <= 0)
      return 0
    return Math.max(1, Math.round(n))
  }

  readonly property QtObject spacing: QtObject {
    readonly property real scale: root.effectiveSpacingScale
    readonly property int hairline: root.space(1)
    readonly property int xxs: root.space(2)
    readonly property int xs: root.space(3)
    readonly property int sm: root.space(4)
    readonly property int md: root.space(6)
    readonly property int lg: root.space(8)
    readonly property int xl: root.space(10)
    readonly property int xxl: root.space(12)
    readonly property int xxxl: root.space(14)
    readonly property int huge: root.space(18)
    readonly property int controlGap: root.space(8)
    readonly property int controlPaddingX: root.space(10)
    readonly property int controlPaddingY: root.space(6)
    readonly property int inputPaddingY: root.space(7)
    readonly property int controlHeight: root.space(28)
    readonly property int popupRowHeight: root.space(28)
    readonly property int rowGap: root.space(8)
    readonly property int rowPaddingX: root.space(12)
    readonly property int labelGap: root.space(4)
    readonly property int panelGap: root.space(14)
    readonly property int panelPadding: root.space(18)
    readonly property int popupPadding: root.space(14)
  }

  // -- typography -----------------------------------------------------------
  //
  // The real singleton keeps `fontFamily` at the fontconfig alias
  // "monospace" and publishes the concrete family it resolves to as
  // `resolvedFontFamily`. On the VM that pair is "monospace" ->
  // "Noto Sans Mono". macOS has no fontconfig, so "monospace" is not a family
  // here and Qt would silently substitute a proportional face -- which would
  // make every readout in the garage a lie about how it looks on Omarchy.
  // So the mock keeps the alias in `fontFamily`, exactly as the shell does,
  // and resolves `resolvedFontFamily` against the fonts actually installed,
  // preferring the VM's face if it is present. The harness binds ui/Theme to
  // the resolved name.
  property string fontFamily: "monospace"
  property string resolvedFontFamily: {
    var installed = Qt.fontFamilies()
    var wanted = ["Noto Sans Mono", "DejaVu Sans Mono", "JetBrainsMono Nerd Font",
                  "JetBrains Mono", "Menlo", "Monaco", "Andale Mono", "Courier New"]
    for (var i = 0; i < wanted.length; i++)
      if (installed.indexOf(wanted[i]) >= 0)
        return wanted[i]
    return "monospace"
  }
  property string menuFontFamily: root.fontFamily

  property int fontBaseSize: 12
  readonly property real fontScale: Math.max(1 / 12, fontBaseSize / 12)

  function fontPx(mult) {
    return Math.max(1, Math.round(fontBaseSize * mult))
  }

  readonly property QtObject font: QtObject {
    readonly property string family: root.fontFamily
    readonly property string resolvedFamily: root.resolvedFontFamily
    readonly property string menuFamily: root.menuFontFamily
    readonly property int baseSize: root.fontBaseSize

    readonly property int caption: root.fontPx(0.833)
    readonly property int bodySmall: root.fontPx(0.917)
    readonly property int body: root.fontPx(1.0)
    readonly property int subtitle: root.fontPx(1.083)
    readonly property int title: root.fontPx(1.167)
    readonly property int heading: root.fontPx(1.333)
    readonly property int display: root.fontPx(2.0)
    readonly property int displayLarge: root.fontPx(2.333)

    readonly property int iconSmall: bodySmall
    readonly property int icon: title
    readonly property int iconLarge: root.fontPx(1.5)
  }

  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: Math.round(26 * root.fontScale)
    readonly property int sizeVertical: Math.round(28 * root.fontScale)
    readonly property int iconSlot: Math.round(27 * root.fontScale)
    readonly property int iconCanvas: Math.round(16 * root.fontScale)
    readonly property int iconFont: Math.round(13 * root.fontScale)
    readonly property int statusSlot: Math.round(21 * root.fontScale)
  }
}
