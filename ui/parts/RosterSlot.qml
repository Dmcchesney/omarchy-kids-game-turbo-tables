import QtQuick
import "../"

// One of the four seats on the grid: the child, then Bolt, Piston and Gasket.
//
// What is here is what the design lists for a solo roster -- kart preview,
// colour, number, a ready lamp, and a level badge for the rivals. What is not
// here is everything the multiplayer lobby needs and solo does not: no invite
// state, no approved-friend key, no device-verified mark, and above all no
// name. The child's seat is labelled YOU, which is the only label a game with
// no name field can honestly give it.
Item {
  id: slot

  property int number: 7
  property string name: "YOU"
  property int paintIndex: 0
  property int bodyIndex: 0
  // -1 for the child; 0, 1, 2 for Rookie, Pro, Champion.
  property int level: -1
  property bool ready: false
  property string statusText: ""
  property real scaleUnit: 1.0

  readonly property color paintColor: Theme.paint(paintIndex)
  // The paint, lifted for type. Purple measures 4.01:1 against this row at
  // full strength and blue 4.59:1; lifting the value by a quarter puts the
  // worst of the eight at 5.47:1, so no choice of paint can make a racer's
  // own name the least readable thing in their row.
  readonly property color inkColor: Qt.lighter(paintColor, 1.25)
  readonly property bool isChild: level < 0

  function u(v) { return Math.round(v * scaleUnit) }

  implicitHeight: u(100)

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: slot.isChild
           ? Qt.rgba(Theme.accent.r * 0.16, Theme.accent.g * 0.16, Theme.accent.b * 0.2, 0.6)
           : Theme.panelRaised
    border.width: 1
    border.color: slot.isChild
                  ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                  : Theme.line
  }

  // ---------------------------------------------------------- number badge
  Rectangle {
    id: badge
    x: slot.u(14)
    y: slot.u(12)
    width: slot.u(46)
    height: slot.u(38)
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(slot.paintColor.r * 0.22, slot.paintColor.g * 0.22, slot.paintColor.b * 0.22, 0.8)
    border.width: Math.max(1, slot.u(2))
    border.color: slot.paintColor

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: String(slot.number)
      color: slot.inkColor
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: slot.u(23)
    }
  }

  Text {
    id: racerName
    textFormat: Text.PlainText
    x: badge.x + badge.width + slot.u(14)
    y: badge.y + slot.u(2)
    text: slot.name
    color: slot.inkColor
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: slot.u(27)
    font.letterSpacing: slot.u(2)
  }

  // ------------------------------------------------------ level / identity
  // Three bars, filled to the rival's level. Shape carries the meaning; the
  // word beside it repeats it for anyone the shape does not reach.
  Row {
    id: levelMeter
    x: badge.x
    y: badge.y + badge.height + slot.u(10)
    spacing: slot.u(3)
    visible: !slot.isChild

    Repeater {
      model: 3
      Rectangle {
        width: slot.u(5)
        height: slot.u(6) + index * slot.u(4)
        anchors.bottom: parent.bottom
        radius: 1
        color: index <= slot.level ? Theme.amber : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    x: slot.isChild ? badge.x : levelMeter.x + levelMeter.width + slot.u(9)
    y: badge.y + badge.height + slot.u(11)
    text: slot.isChild ? slot.statusText : Theme.levelNames[Math.max(0, Math.min(2, slot.level))]
    color: slot.isChild ? Theme.textLabel : Theme.amber
    font.family: Theme.mono
    font.bold: !slot.isChild
    font.pixelSize: slot.u(15)
    font.letterSpacing: slot.u(1)
  }

  // ----------------------------------------------------------- kart preview
  // PIECE C: the same sheet cell the turntable shows, at the 0.5 row, so the
  // car in the child's row is the car on the dais and not a second drawing
  // of it. One pixel per sheet pixel at the design's base size; two once
  // the row is tall enough to hold them. The number is left to CarSprite's
  // own legibility floor: at this size the roundel is a few pixels and the
  // row's own badge already carries the number legibly.
  CarSprite {
    id: preview
    objectName: "carPreview"
    // The cell centred in the row; the anchor is the contact point, so the
    // cell's own centre is half a cell up and along from it.
    x: lamp.x - slot.u(10) - drawnWidth + anchorDx
    y: Math.round(slot.height / 2 - drawnHeight / 2 + anchorDy)
    body: slot.bodyIndex
    paint: slot.paintIndex
    number: slot.number
    camera: "stall"
    yaw: 0
    sheetScale: 0.5
    pixelScale: slot.scaleUnit >= 1.5 ? 2 : 1
    opacity: slot.ready ? 1.0 : 0.86
  }

  // ------------------------------------------------------------- ready lamp
  Rectangle {
    id: lamp
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: slot.u(14)
    width: slot.u(102)
    height: slot.u(74)
    radius: Theme.cornerRadiusSmall
    color: Theme.panelSunken
    border.width: 1
    border.color: Theme.line

    Text {
      id: lampLabel
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      y: slot.u(11)
      text: slot.ready ? "READY" : "IN STALL"
      color: slot.ready ? Theme.lime : Theme.textLabel
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: slot.u(15)
      font.letterSpacing: slot.u(1)
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: lampLabel.y + lampLabel.height + slot.u(8)
      width: slot.u(26)
      height: width
      radius: width / 2
      color: slot.ready ? Theme.lime : "#141821"
      border.width: Math.max(1, slot.u(2))
      border.color: slot.ready
                    ? Qt.lighter(Theme.lime, 1.3)
                    : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.3)

      Rectangle {
        visible: slot.ready
        anchors.centerIn: parent
        width: parent.width * 0.42
        height: width
        radius: width / 2
        color: "#e8ffdd"
      }
    }
  }
}
