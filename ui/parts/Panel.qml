import QtQuick
import "../"

// A card. Every region of the garage sits on one of these: the page itself,
// the policy rail, the stall, each roster slot, each of the three bottom
// panels. Fill and hairline both come from the theme, so a themed desktop
// retints the whole screen.
Rectangle {
  id: panel

  property alias title: heading.text
  property color titleColor: Theme.textLabel
  property int titleSize: 15
  property real titleSpacing: 2
  property int pad: 0

  // ROUND-8. A card is an object in the room, and the room has one key: the
  // sun through the roller door. `litSide` is the edge of this card that
  // faces the opening -- "left" for the columns right of the bay, "top" for
  // the band under it -- and when it is set the card takes a wash of the sun's
  // own tone falling off across `litReach` of its width or height, and a warm
  // hairline on that edge. Default "none" draws neither, so every screen that
  // does not set it renders exactly as it did.
  property string litSide: "none"
  property color litColor: Theme.duskSurfaceLit
  property real litReach: 0.55
  property real litStrength: 0.62

  color: Theme.panel
  radius: Theme.cornerRadius
  border.width: 1
  border.color: Theme.line

  Item {
    anchors.fill: parent
    visible: panel.litSide === "left" || panel.litSide === "top"
    clip: true

    Rectangle {
      id: wash
      readonly property bool sideways: panel.litSide === "left"
      x: 0
      y: 0
      width: sideways ? Math.round(panel.width * panel.litReach) : panel.width
      height: sideways ? panel.height : Math.round(panel.height * panel.litReach)
      gradient: Gradient {
        orientation: wash.sideways ? Gradient.Horizontal : Gradient.Vertical
        GradientStop {
          position: 0.0
          color: Qt.rgba(panel.litColor.r, panel.litColor.g, panel.litColor.b,
                         panel.litStrength)
        }
        GradientStop {
          position: 0.45
          color: Qt.rgba(panel.litColor.r, panel.litColor.g, panel.litColor.b,
                         panel.litStrength * 0.34)
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(panel.litColor.r, panel.litColor.g, panel.litColor.b, 0)
        }
      }
    }

    // The edge itself, where the sun grazes it.
    Rectangle {
      x: 0
      y: 0
      width: panel.litSide === "left" ? 2 : panel.width
      height: panel.litSide === "left" ? panel.height : 2
      color: Theme.duskLitEdge
    }
  }

  Text {
    id: heading
    textFormat: Text.PlainText
    visible: text.length > 0
    x: panel.pad
    y: panel.pad
    color: panel.titleColor
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: panel.titleSize
    font.letterSpacing: panel.titleSpacing
  }
}
