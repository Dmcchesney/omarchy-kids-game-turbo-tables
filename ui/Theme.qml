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

  // PROTOTYPE: "Golden Hour at the Pit". The palette sampled off the Omarchy
  // Quattro wallpaper -- one low sun behind-right of the subject, a magenta
  // sky, purple shadows. Added for the proposal branch; nothing above is
  // renamed, and the design's amber, cream and teal keep their roles (teal
  // is now the door-frame accent only). If the direction is adopted these
  // move into docs/design.md as Visual Style v3; if not, they go with the
  // branch.
  readonly property color duskSkyTop: "#5e1a50"
  readonly property color duskSkyMid: "#a4337b"
  readonly property color duskSkyHot: "#c24073"
  readonly property color duskHorizon: "#d75d6b"
  readonly property color duskSun: "#efcb72"
  readonly property color duskSunEdge: "#f0956e"
  readonly property color duskHillFar: "#bc405f"
  readonly property color duskHillNear: "#8e2c50"
  readonly property color duskGround: "#3c1228"
  readonly property color duskShadow: "#5f255e"
  readonly property color duskRim: "#f0b07a"
  readonly property color duskNeon: "#ff4fa3"
  readonly property color duskInk: "#280e27"

  // ADDED IN PIECE 3, ROUND 7, and added rather than substituted: `ground`,
  // `panel`, `panelRaised` and `panelSunken` below are untouched, so every
  // screen that has not been re-run under v3 renders exactly as it did.
  //
  // The design's Visual style names the ground "near-black purple #3c1228".
  // The derived `ground` below is the theme's own background driven to 34% --
  // on stock Omarchy that is #090911, a cold neutral near-black, and it is
  // what made a 1920x1080 garage frame read as a dark desktop panel with a
  // small lit window cut in it rather than as a room at golden hour. These
  // five are the same surface stack in the bar's family, with #3c1228 itself
  // as the raised card. They are fixed rather than derived for the reason the
  // block above them is fixed: the design settles the game's palette and it
  // deliberately does not move with the child's theme. The chrome ON these
  // surfaces -- the accent, the focus ring, the text roles, the hairlines --
  // is still the theme's and is unchanged.
  readonly property color duskPage: "#1e0816"
  readonly property color duskSurface: "#2e0f21"
  readonly property color duskSurfaceRaised: "#3c1228"
  readonly property color duskSurfaceSunken: "#170510"
  // A hairline and a rule that belong to the room rather than to the desktop:
  // warm, low-alpha, and used only where an edge is catching the sun.
  readonly property color duskEdgeWarm: Qt.rgba(duskRim.r, duskRim.g, duskRim.b, 0.22)

  // Eight paints, in the order the swatch grid reads them: two rows of four.
  readonly property var paints: ["#e0483a", "#ee8b3a", "#f2c93c", "#6dc94a",
                                 "#3f7fe0", "#9a55d6", "#e05fb0", "#d8dbe0"]
  readonly property var paintNames: ["RED", "ORANGE", "YELLOW", "GREEN",
                                     "BLUE", "PURPLE", "PINK", "SILVER"]

  // Six car bodies. The names are what the stall caption reads out, and they
  // are the six archetypes design v3 names, in the sheet order below: piece C
  // shipped with v1's names still here, so index 3 -- a saloon -- was captioned
  // BUGGY on the dais. The caption has to name the shape the child is looking at.
  readonly property var bodyNames: ["COUPE", "HATCH", "WEDGE",
                                    "SALOON", "BUGGY", "PICKUP"]

  // ---------------------------------------------------- the car sheets
  // PIECE C. Every car on every screen is a cell of a baked sprite sheet,
  // `assets/karts/<body>/<paint>.png`, and these two lists are the piece C
  // contract's file names in the order of the two indices above: body 0 is
  // `coupe`, paint 7 is `white`. bodyNames above is the same six in the same
  // order, upper-cased for the caption; paintNames keeps SILVER where the file
  // says white, because that is the word on the swatch a child already knows.
  readonly property var bodySheetNames: ["coupe", "hatch", "wedge",
                                         "saloon", "buggy", "pickup"]
  readonly property var paintSheetNames: ["red", "orange", "yellow", "green",
                                          "blue", "purple", "pink", "white"]
  // Where the sheets live. A plain writable property so the development
  // harness can point every CarSprite at a stand-in set of sheets with one
  // assignment; the plugin never writes it.
  property url carSheetRoot: Qt.resolvedUrl("../assets/karts/")

  function bodySheetName(index) {
    return bodySheetNames[((index % bodySheetNames.length) + bodySheetNames.length) % bodySheetNames.length]
  }

  function paintSheetName(index) {
    return paintSheetNames[((index % paintSheetNames.length) + paintSheetNames.length) % paintSheetNames.length]
  }

  // ------------------------------------------------------- the one camera
  // ROUND-6. The kart and the floor it stands on are drawn by two different
  // files, and until now they were drawn by two different cameras. A critic
  // put the number on it: solving the sprite's own published basis gave an
  // apparent pitch of about 31 degrees, while a least-squares fit of the
  // turntable's rim (486 points, rms 0.35 px) gave 23.96 -- the dais was
  // drawn 27 px flatter than the kart's projection required, 77 times the
  // fit residual. Two cameras in one picture is why the kart read as
  // composited onto the dais rather than standing on it.
  //
  // These four numbers are now the ONLY camera in the garage. The v1 live
  // sprite took its projection from them and GarageStall still derives the
  // turntable from them, so the plinth is the one a critic measured. The
  // car on it is now a baked sheet cell (piece C); the sheet's own stall
  // camera is fixed by the bake, and these numbers describe the dais.
  // Nothing here is a colour or a theme value; it lives in Theme because
  // Theme is the one module both files already import.
  readonly property real kartYawDeg: 22
  readonly property real kartPitchDeg: 25
  // Distance to the picture plane, in model units, and the height of the
  // point the camera is aimed at above the floor. Both are what makes the
  // far side of the kart smaller than the near side.
  readonly property real kartFocal: 190
  readonly property real kartAimHeight: 13

  // A horizontal circle of model radius `r` centred on the point where the
  // kart's wheels touch the floor, projected by that camera, in the kart
  // sprite's own view-box units:
  //
  //   a   the semi-axis across the screen
  //   b   the semi-axis down the screen
  //   dy  how far the ellipse's CENTRE falls below the contact point
  //
  // `dy` is not a fudge. Under a projection with a finite focal length the
  // near arc of a floor circle is closer to the camera than the far arc, so
  // it swings further from the contact point than the far arc does, and the
  // projected ellipse's centre is not the projection of the circle's centre.
  // A dais drawn as an ellipse centred on the kart's wheels is therefore
  // wrong even if its axis ratio is right.
  //
  // Closed form, derived from the projection rather than fitted. With
  // A = f sin(pitch) + aimHeight cos(pitch) and q = f^2 - r^2:
  //
  //   a = r f / sqrt(q)      b = r f A / q      dy = r^2 A / q
  //
  // It reproduces a 1440-point conic fit of the same circle to five decimal
  // places, and as f grows it collapses to the orthographic answer
  // b/a -> sin(pitch), dy -> 0, which is the check that it is the right
  // formula and not a coincidence.
  function groundEllipse(r) {
    var f = kartFocal
    var A = f * Math.sin(kartPitchDeg * Math.PI / 180)
            + kartAimHeight * Math.cos(kartPitchDeg * Math.PI / 180)
    var q = f * f - r * r
    if (q <= 0 || r <= 0)
      return { a: 0, b: 0, dy: 0 }
    return { a: r * f / Math.sqrt(q), b: r * f * A / q, dy: r * r * A / q }
  }

  // The apparent pitch of a floor circle of radius `r` under that camera, in
  // degrees: asin(b/a). It is NOT kartPitchDeg -- the perspective divide and
  // the camera's height above the floor both steepen it, and it grows with
  // the circle. This is the number a critic measures off the frame, so it is
  // the number this file publishes.
  function groundPitchDeg(r) {
    var e = groundEllipse(r)
    return e.a > 0 ? Math.asin(Math.min(1, e.b / e.a)) * 180 / Math.PI : 0
  }

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
