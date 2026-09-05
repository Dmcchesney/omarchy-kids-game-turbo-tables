import QtQuick
import QtQuick.Controls.impl

// THE SUN HALF OF THE LIGHT RULE ON A KIT PROP. Two flat silhouettes of the
// cell in the design's warm rim colour, offset toward the sun and drawn
// UNDERNEATH the cell, so that all that shows of either is the part that falls
// outside the prop's own outline: a warm edge, two steps deep, along every
// sun-facing contour. `PropWash.qml` is the other half and goes on top.
//
// WHY A RIM AND NOT A BAND. The first cut of this cropped the sheet to the
// right-hand third of the cell and washed that share warm. It is cheaper and it
// is measurably lighter on the sun side -- and it drew a HARD VERTICAL EDGE
// straight down the middle of every rock in the quarry, because a crop is a
// rectangle and a rock is not. An offset silhouette has no straight edge
// anywhere: it is the prop's own outline, moved, so the lit edge is exactly as
// crooked as the thing it is lighting. It is also what the design asks for in
// as many words -- "warmth lives in the RIM and the lamps, never in the paint".
//
// TWO OFFSETS AND NOT ONE. A single one-pixel offset is a hairline and reads as
// an outline rather than as light. Two, at 1% and 3% of the prop's drawn width
// and at falling strength, give a rim that is thick enough on a six-metre rock
// wall to read as a lit face and still lands inside a single pixel on a marker
// post, where it correctly disappears.
//
// UP AS WELL AS ACROSS. The sun in this game is low and on the right at u 0.68,
// and it is at effective infinity -- the disc does not move with the camera --
// so the lit side of every object on this circuit is its right side and its top,
// at every depth and in every sector. That is why the offset is a constant and
// not a test against the sun's screen position: a prop that passed the disc's
// own column would otherwise flip which side of it was lit, mid-frame.
Item {
  id: key

  property var host: null
  readonly property var cell: host ? host.cell : null
  readonly property real drawnW: host ? host.drawnW : 0
  readonly property real drawnH: host ? host.drawnH : 0
  // The rim's reach, in screen pixels. A share of the prop's drawn width, so a
  // rock wall and the same rock wall four times further away are lit the same.
  readonly property real reach: Math.max(1, drawnW * (host ? host.keyReach : 0.030))
  readonly property real lit: host ? host.clarity * host.keyAmount : 0

  Repeater {
    model: 2

    ColorImage {
      // Step 0 is the outer, softer reach; step 1 is the bright edge against
      // the prop itself.
      readonly property real step: index === 0 ? 1.0 : 0.34
      visible: key.cell !== null && key.lit > 0.004 && key.drawnW > 3
      source: key.cell ? key.host.sheetRoot + key.host.kind + ".png" : ""
      sourceClipRect: key.cell
                      ? Qt.rect(key.cell.x, key.cell.y, key.cell.width, key.cell.height)
                      : Qt.rect(0, 0, 1, 1)
      color: key.host ? key.host.keyColor : "#f0b07a"
      width: key.drawnW
      height: key.drawnH
      x: (key.host ? -key.host.anchorDx : 0) + key.reach * step
      y: (key.host ? -key.host.anchorDy : 0) - key.reach * step * 0.55
      opacity: Math.min(1, key.lit * (index === 0 ? 0.72 : 1.0))
      smooth: false
      mipmap: false
      cache: true
      asynchronous: false
    }
  }
}
