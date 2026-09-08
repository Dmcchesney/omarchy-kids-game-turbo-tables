import QtQuick
import "../"
import "CardFx.js" as CardFx

// The Roll Cage's outline, around one car.
//
// Design v4, Roll Cage: "a cage frame draws itself around your kart line by
// line over 300, then settles to a soft amber pulse that stays as long as it is
// active." And, in the Wrench's blocked row: "the wrench shatters against the
// target's Roll Cage with a white flash and a ring, the cage outline cracks and
// vanishes ... the block is the payoff and must be loud."
//
// WHY IT IS A FILE. Round two built this inside `ui/TrackView.qml`, bound to
// the child's own kart, because the child's cage was the only one ever drawn.
// A blind critic then found the other half missing on both builds: "there is no
// cage outline on the victim, nothing cracks, nothing shatters -- three grey
// puffs, a screen flash, and a text callout." The block needs the same eight
// lines around a DIFFERENT car, so the eight lines are here and the two callers
// are in TrackView. Copying the spec would have been two copies of a shape that
// has already been got wrong twice.
//
// It is drawn in QML rather than baked for the reason `docs/prop-kit.md` gives:
// it is an outline around a thing whose size changes every frame.
//
// A ROLL CAGE, NOT A LADDER. Round one drew a grid -- two horizontals, two
// verticals and four more uprights, evenly spaced. What a roll cage is, is a
// main hoop over the driver, two tapered uprights down to the sill, a waist
// rail, a front hoop and a diagonal cross-brace, and the brace is the line that
// makes the shape read as a cage rather than as a box.
Item {
  id: cage

  // Where the car is: the centre of its footprint and the point it stands on.
  property real cx: 0
  property real cy: 0
  // Half the cage's width and its full height, in pixels. Both come off the
  // car's own drawn size in the caller.
  property real span: 40
  property real tall: 40
  // The highest y this may occupy, from `TrackView.fxTopFor` -- the fact's
  // guard band, the same one every other mark in the piece obeys.
  property real topLimit: 0
  // 0..1 through the 300 ms weld. 1 under reduced motion, where a cage is
  // simply there.
  property real draw: 1
  // 0..1 through the 260 ms break-up, or -1 when it is not cracking.
  property real crack: -1
  // The whole outline's opacity, which the caller pulses.
  property real amount: 1
  property color tone: Theme.amber
  property real thickness: 2

  readonly property real crackU: crack < 0 ? 0 : Math.max(0, Math.min(1, crack))
  // Bright for the first half of the break-up, then a ghost, then gone. A cage
  // that faded evenly read as a cage being switched off.
  readonly property real live: crackU > 0
                               ? Math.max(0, 1 - crackU) * (crackU < 0.5 ? 1 : 0.4)
                               : amount

  // Each entry is [x1, y1, x2, y2, start] in this item's own 0..1 box, and
  // `start` is where in the weld that member begins, so the frame assembles
  // hoop-first the way one is welded.
  readonly property var spec: [
    // the main hoop, over the roof
    [0.10, 0.06, 0.90, 0.06, 0.00],
    // its two uprights, tapering out to the sill
    [0.10, 0.06, 0.03, 1.00, 0.18],
    [0.90, 0.06, 0.97, 1.00, 0.18],
    // the sill, along the bottom of the doors
    [0.03, 1.00, 0.97, 1.00, 0.40],
    // the waist rail, at the window line
    [0.05, 0.60, 0.95, 0.60, 0.52],
    // the cross-brace: the line that says cage
    [0.10, 0.06, 0.97, 1.00, 0.64],
    [0.90, 0.06, 0.03, 1.00, 0.72],
    // the front hoop
    [0.20, 0.30, 0.80, 0.30, 0.84]
  ]

  x: cx - span
  y: Math.max(topLimit, cy - tall * 0.926)
  width: span * 2
  height: tall
  visible: live > 0.02 && crackU < 1

  Repeater {
    model: cage.visible ? cage.spec : 0

    Line {
      readonly property real begin: modelData[4]
      readonly property real g: Math.max(0, Math.min(1, (cage.draw - begin) / 0.20))
      x1: modelData[0] * cage.width
      y1: modelData[1] * cage.height
      x2: modelData[2] * cage.width
      y2: modelData[3] * cage.height
      thickness: cage.thickness
      tone: cage.tone
      // Cracking: each member lets go a little after the one before it, so the
      // frame comes apart in the order it was welded rather than blinking out.
      grow: cage.crackU > 0 ? Math.max(0, 1 - cage.crackU * (1 + begin)) : g
      amount: cage.live
    }
  }
}
