import QtQuick

// A straight line between two points in the parent's coordinates.
//
// The third of the three soft things `docs/prop-kit.md` says are drawn in QML
// rather than baked: the speed lines on a boost, the tow line from the hook to
// a rival's kart, and the Roll Cage outline that draws itself around the
// child's car. All three are lines whose ends move every frame, so a sprite
// could not have been used for any of them anyway.
//
// It is one Rectangle, rotated about its left-hand end. That is deliberately
// the cheapest possible construction: a Shape with a ShapePath costs a
// triangulation per frame on the software scene graph this game is measured
// on, and a cage is eight of these.
//
// `grow` is what makes the cage "draw itself line by line": at 0 the line is
// not there, at 1 it reaches its far end, and the caller steps it from the
// effect clock. Nothing here animates itself, for the same reason nothing in
// `Sparks` does -- a frame strip has to be reproducible.
Item {
  id: line

  property real x1: 0
  property real y1: 0
  property real x2: 0
  property real y2: 0
  property real thickness: 2
  property color tone: "#f2e6c4"
  property real amount: 1.0
  // 0..1: how much of the line, from (x1, y1), is drawn.
  property real grow: 1.0
  // Off by default: a speed line at a shallow angle is a pixel-art streak and
  // must not be resampled into a grey smear.
  property bool soft: false

  readonly property real dx: x2 - x1
  readonly property real dy: y2 - y1
  readonly property real len: Math.sqrt(dx * dx + dy * dy)

  x: 0
  y: 0
  width: 0
  height: 0
  visible: amount > 0.004 && len > 0.5 && grow > 0.004

  Rectangle {
    x: line.x1
    y: line.y1 - line.thickness / 2
    width: line.len * Math.max(0, Math.min(1, line.grow))
    height: Math.max(1, line.thickness)
    color: line.tone
    opacity: line.amount
    antialiasing: line.soft
    // About the left-hand end, which is (x1, y1) -- so the line grows away
    // from its first point, which is the end a cage or a tow line starts at.
    transformOrigin: Item.Left
    rotation: Math.atan2(line.dy, line.dx) * 180 / Math.PI
  }
}
