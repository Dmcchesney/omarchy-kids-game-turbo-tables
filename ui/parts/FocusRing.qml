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
Item {
  id: ring

  property bool on: false
  property int radius: Theme.cornerRadiusSmall
  property real gap: 3
  property real thickness: 2
  property bool wash: true

  anchors.fill: parent
  visible: on
  z: 40

  Rectangle {
    anchors.fill: parent
    radius: ring.radius
    color: ring.wash ? Theme.focusFill : "transparent"
  }
  Rectangle {
    anchors.fill: parent
    anchors.margins: -ring.gap
    radius: ring.radius + ring.gap
    color: "transparent"
    border.width: ring.thickness
    border.color: Theme.focusRing
  }
  Rectangle {
    anchors.fill: parent
    anchors.margins: -(ring.gap + ring.thickness + 1)
    radius: ring.radius + ring.gap + ring.thickness + 1
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(Theme.focusRing.r, Theme.focusRing.g, Theme.focusRing.b, 0.38)
  }
}
