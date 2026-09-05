import QtQuick
import "../"

// The focus ring. One implementation, used by every control in the garage,
// so keyboard focus looks the same everywhere.
//
// Drawn in the theme accent, which is the design's rule for chrome: the ring
// belongs to the child's Omarchy rather than to the game. Three rings of
// falling opacity outside the control's own edge, so the ring reads against
// both a filled tile and bare panel, and a faint accent wash inside so the
// focused control is legible even where the ring runs off a clipped edge.
// PIECE M -- THE SAME RING, ONE STEP QUIETER, IS HOVER.
//
// The mouse needs its own answer to "is this a control", and the cheapest
// honest one is the affordance the game already has. `hover` draws this ring in
// `Theme.hoverRing` at one ring instead of three and drops the outer halo, so
// a pointer moving across a screen says "control, control, control" without
// eight things looking focused at once. Focus wins wherever both are true: the
// keyboard's position is the more important of the two facts, and a control
// that is both focused and hovered must not read as a third state.
Item {
  id: ring

  property bool on: false
  property int radius: Theme.cornerRadiusSmall
  property real gap: 3
  property real thickness: 2
  property bool wash: true
  // Draw the quiet variant. Callers set it to `hovered && !activeFocus`, so it
  // is never on at the same time as the focus ring.
  property bool hover: false

  readonly property color ringColor: ring.hover ? Theme.hoverRing : Theme.focusRing
  readonly property color fillColor: ring.hover ? Theme.hoverFill : Theme.focusFill

  anchors.fill: parent
  visible: on
  z: 40

  Rectangle {
    anchors.fill: parent
    radius: ring.radius
    color: ring.wash ? ring.fillColor : "transparent"
  }
  Rectangle {
    anchors.fill: parent
    anchors.margins: -ring.gap
    radius: ring.radius + ring.gap
    color: "transparent"
    border.width: ring.hover ? Math.max(1, ring.thickness - 1) : ring.thickness
    border.color: ring.ringColor
  }
  Rectangle {
    // The outer halo is what makes the focus ring read from across a room, and
    // it is the half of the ring hover does not get.
    visible: !ring.hover
    anchors.fill: parent
    anchors.margins: -(ring.gap + ring.thickness + 1)
    radius: ring.radius + ring.gap + ring.thickness + 1
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(Theme.focusRing.r, Theme.focusRing.g, Theme.focusRing.b, 0.38)
  }
}
