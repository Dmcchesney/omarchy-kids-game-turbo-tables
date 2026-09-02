pragma Singleton
import QtQuick

// The theme adapter. Layer 2 reads only this; it never reaches the shell.
//
// The top block is what the shell owns: five palette roles, three menu-surface
// roles, the font family and base size, the corner radius and the spacing
// scale. Every one has a default here, chosen so that a screen loaded with
// nothing bound still renders, and every one is a plain writable property so
// that layer 3 can bind it to the live theme and the development harness can
// assign a snapshot of a real theme's values.
//
// The second block is the game's own constants -- Garage Grid's amber and
// teal, the eight kart paints, the three rival colours. The design fixes
// these; they are layered on top of whatever theme the child is running and
// deliberately do not move with it.
//
// The third block derives everything the screens actually ask for from the
// two above.
QtObject {
  id: theme

  // ---------------------------------------------------------------- shell
  // Defaults are the stock Omarchy dark values. Layer 3 overwrites them from
  // the live theme; the harness overwrites them from a captured one.
  property color background: "#1a1b26"
  property color foreground: "#a9b1d6"
  property color accent: "#7aa2f7"
  property color urgent: "#f7768e"
  property color muted: "#414868"

  property color menuBackground: "#1a1b26"
  property color menuText: "#a9b1d6"
  property color menuBorder: "#a9b1d6"

  // The fontconfig alias the shell hands down, and the concrete family it
  // resolves to. Bind text to `mono`: it prefers the resolved name and falls
  // back to the alias, so a machine where the alias works still gets it.
  property string fontFamily: "monospace"
  property string resolvedFontFamily: ""
  property int fontBaseSize: 12

  // Hyprland's decoration:rounding, mirrored by the shell. It is 0 on a stock
  // install, and a garage of square-cornered cards is not the design. So the
  // shell radius is a floor the theme may raise, never the radius itself.
  property int shellCornerRadius: 0
  property real spacingScale: 1.0

  // ------------------------------------------------------- game constants
  // Design, "Visual style": ground is near-black from the theme's darkest
  // background, light is warm amber, shadow is dark teal, chrome is the
  // theme's accent.
  readonly property color amber: "#f5a524"
  readonly property color amberDeep: "#a8690f"
  readonly property color amberGlow: "#ffd489"
  readonly property color teal: "#39b3ad"
  readonly property color tealDeep: "#12454a"
  readonly property color lime: "#86e06a"
  readonly property color limeDeep: "#1d3a18"
  readonly property color cream: "#f2e6c4"
  readonly property color hazard: "#d8a12a"

  // Eight paints, in the order the swatch grid reads them: two rows of four.
  readonly property var paints: ["#e0483a", "#ee8b3a", "#f2c93c", "#6dc94a",
                                 "#3f7fe0", "#9a55d6", "#e05fb0", "#d8dbe0"]
  readonly property var paintNames: ["RED", "ORANGE", "YELLOW", "GREEN",
                                     "BLUE", "PURPLE", "PINK", "SILVER"]

  // Six kart bodies. The names are what the stall caption reads out.
  readonly property var bodyNames: ["SPRINTER", "WEDGE", "STOCKCAR",
                                    "BUGGY", "HAULER", "PROTOTYPE"]

  // The three rivals of the design's AI table, in fixed order.
  readonly property var rivalNames: ["BOLT", "PISTON", "GASKET"]
  readonly property var rivalPaints: [2, 4, 3]
  readonly property var rivalNumbers: [21, 34, 55]
  readonly property var levelNames: ["ROOKIE", "PRO", "CHAMPION"]

  // --------------------------------------------------------------- derived
  readonly property string mono: resolvedFontFamily.length > 0 ? resolvedFontFamily : fontFamily

  // Ground. The design asks for near-black taken from the theme's darkest
  // background, and for it to stay dark under a light theme, so the page is
  // the theme background driven most of the way to black rather than a
  // hard-coded hex: a themed near-black instead of a generic one.
  readonly property color ground: Qt.rgba(background.r * 0.34, background.g * 0.34, background.b * 0.34, 1)
  readonly property color panel: Qt.rgba(background.r * 0.55, background.g * 0.55, background.b * 0.60, 1)
  readonly property color panelRaised: Qt.rgba(background.r * 0.78, background.g * 0.78, background.b * 0.84, 1)
  readonly property color panelSunken: Qt.rgba(background.r * 0.22, background.g * 0.22, background.b * 0.26, 1)

  // Four text roles, and the alphas are set by contrast rather than by taste.
  // Against this screen's darkest surfaces the menu text composites to about
  // 9.1:1 at full strength, so 0.80 lands a label near 5.9:1 and 0.72 lands a
  // disabled control near 5.4:1 -- both clear of the 4.5:1 the design's
  // accessibility section requires of body text. The previous 0.62 measured
  // 4.05 to 4.18:1 and failed. `textFaint` is not a text role: it is the dot
  // separator and the unlit lamp ring, and nothing readable uses it.
  readonly property color text: menuText
  readonly property color textBright: Qt.lighter(menuText, 1.32)
  readonly property color textLabel: Qt.rgba(menuText.r, menuText.g, menuText.b, 0.80)
  readonly property color textDisabled: Qt.rgba(menuText.r, menuText.g, menuText.b, 0.72)
  readonly property color textFaint: Qt.rgba(menuText.r, menuText.g, menuText.b, 0.38)

  readonly property color line: Qt.rgba(menuBorder.r, menuBorder.g, menuBorder.b, 0.16)
  readonly property color lineStrong: Qt.rgba(menuBorder.r, menuBorder.g, menuBorder.b, 0.30)
  readonly property color focusRing: accent
  readonly property color focusFill: Qt.rgba(accent.r, accent.g, accent.b, 0.14)
  readonly property color selectedFill: Qt.rgba(accent.r, accent.g, accent.b, 0.20)

  readonly property int cornerRadius: Math.max(10, shellCornerRadius)
  readonly property int cornerRadiusSmall: Math.max(6, shellCornerRadius)

  // The shell's space() with the same rounding rule, so a themed spacing
  // scale moves the garage the same way it moves the rest of the desktop.
  function space(px) {
    var n = Number(px) * spacingScale
    if (!isFinite(n) || n <= 0)
      return 0
    return Math.max(1, Math.round(n))
  }

  // The type scale, in the shell's multipliers off the shell's base size.
  function fontPx(mult) {
    return Math.max(1, Math.round(fontBaseSize * mult))
  }

  function paint(index) {
    return paints[((index % paints.length) + paints.length) % paints.length]
  }

  function paintName(index) {
    return paintNames[((index % paints.length) + paints.length) % paints.length]
  }

  function bodyName(index) {
    return bodyNames[((index % bodyNames.length) + bodyNames.length) % bodyNames.length]
  }

  // Foreground that stays legible on a filled paint swatch or number plate.
  function ink(onColor) {
    var c = onColor
    var luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    return luminance > 0.55 ? Qt.rgba(0.04, 0.04, 0.05, 1) : Qt.rgba(1, 1, 1, 1)
  }
}
