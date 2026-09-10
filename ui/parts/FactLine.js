.pragma library

// THE LINE'S GEOMETRY, IN ONE PLACE, BECAUSE TWO SCREENS DRAW IT.
//
// `7 × 8 = ▮` is drawn twice: by `ui/Countdown.qml` from the GO beat, and by
// `ui/Race.qml` for the whole race after it. The design's rule is that the two
// are the SAME OBJECT one second apart -- "the thing the child is told to type
// on" must not move at the cut -- and the way that rule was kept was by each
// screen computing the same placement separately.
//
// ISSUE #4: IT WAS NOT THE SAME PLACEMENT. At 1920 x 1080 the race drew the
// line's ink at y = 271 and the countdown at y = 157, so at GO the line jumped
// 114 px DOWN the screen, which is the one thing the shared construction exists
// to prevent. Three numbers had drifted apart between the two files:
//
//   the top of the line   race `rightHud.y + mapPanel.height + px(12)` = px(232)
//                         countdown a literal `px(118)`            <- 114 px
//   the size's floor      race `fs(100)`, countdown `fs(118)`
//   the scale's floor     race 0.40, countdown 0.42
//
// Only the first was visible at the sizes this game is played at, because at
// all three of them the other two are dominated by the terms beside them. They
// are all here now regardless: a copy that agrees today is the copy that
// drifts, and this one already had.
//
// The race's placement is the one that survived, because it is the one with a
// reason: the line sits under the minimap panel, above the horizon, and clear
// of every kart. The countdown has no minimap -- it does not need one to put
// the line where the race will put it, which is the whole point of asking this
// file instead of the panel.

// The right-hand HUD's own geometry in `ui/Race.qml`, at 1920 x 1080, which is
// what puts the line under it. The race sets its HUD from these, so the panel
// and the line can never part company again.
var HUD_TOP = 24
var MAP_HEIGHT = 196
// A hand's margin between the panel's bottom edge and the top of the em box.
var LINE_GAP = 12

// The scale both screens work in. The floor is the race's 0.40.
var SCALE_FLOOR = 0.40

// The design's floor for the line: "never smaller than a tenth of the screen
// height" in INK -- the tight bounding box of the glyphs, not the em box --
// with a hair over it so rounding never lands under it.
var INK_FRACTION = 0.105
// A floor under the floor, for a window too short for the ratio to mean
// anything.
var SIZE_FLOOR = 100
// The margin the widest line is kept inside on a narrow screen.
var WIDTH_MARGIN = 120
// The fixed size both screens measure their probe string at. Fixed so that
// nothing here is circular: the probe never follows the size it is used to
// compute.
var PROBE_SIZE = 200
// The widest line the game can ever draw, which is what the width cap above is
// measured on. It is the whole line and not just the fact: the fact and the
// answer share a row (design v4.1), so measuring `12 × 12` alone would let the
// answer to the widest fact run off the right of a narrow screen.
var PROBE_TEXT = "12 × 12 = 144"

function scale(width, height) {
  return Math.max(SCALE_FLOOR, Math.min(width / 1920, height / 1080))
}

function px(width, height, v) {
  return Math.round(v * scale(width, height))
}

// The top of the line's em box, in screen coordinates. Both screens put their
// line here, so the ink does not move at the cut.
function topY(width, height) {
  return px(width, height, HUD_TOP)
         + px(width, height, MAP_HEIGHT)
         + px(width, height, LINE_GAP)
}

// The size the line is drawn at. `inkRatio` is the face's own ink-to-em ratio,
// measured by the caller off a `TextMetrics` at `PROBE_SIZE` -- so the size
// follows the shell's font rather than a constant measured once on one Mac --
// and `probeAdvance` is that same probe's advance width.
function pixelSize(width, height, inkRatio, probeAdvance) {
  var wanted = Math.ceil((height * INK_FRACTION) / Math.max(0.25, inkRatio))
  var widest = probeAdvance > 0
               ? Math.floor((width - px(width, height, WIDTH_MARGIN))
                            * PROBE_SIZE / probeAdvance)
               : wanted
  var floor = Math.max(8, Math.round(SIZE_FLOOR * scale(width, height)))
  return Math.max(floor, Math.min(wanted, widest))
}
