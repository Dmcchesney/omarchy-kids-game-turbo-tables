import QtQuick
import "../"

// A bezelled readout: the garage's gauge face. Used for the offline chip in
// the title bar and for the kart number in the stall. Rivets in the corners,
// because the design's motif list asks for them, and a sunken face so a value
// reads as instrumentation rather than as a button.
Item {
  id: readout

  property string value: ""
  property color valueColor: Theme.cream
  property color faceColor: Theme.panelSunken
  property color bezelColor: Theme.lineStrong
  property int valueSize: 30
  property real valueSpacing: 2
  property bool rivets: true
  property bool bold: true
  property real rivetInset: 5
  property real rivetSize: 2

  implicitWidth: label.implicitWidth + valueSize * 1.4
  implicitHeight: valueSize * 1.7

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: readout.faceColor
    border.width: 1
    border.color: readout.bezelColor
  }

  Repeater {
    model: readout.rivets ? 4 : 0
    Rectangle {
      width: readout.rivetSize * 2
      height: readout.rivetSize * 2
      radius: readout.rivetSize
      color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.28)
      x: (index % 2 === 0) ? readout.rivetInset : readout.width - readout.rivetInset - width
      y: (index < 2) ? readout.rivetInset : readout.height - readout.rivetInset - height
    }
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: readout.value
    color: readout.valueColor
    font.family: Theme.mono
    font.bold: readout.bold
    font.pixelSize: readout.valueSize
    font.letterSpacing: readout.valueSpacing
  }
}
