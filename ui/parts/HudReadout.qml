import QtQuick
import "../"

// One instrument on the race HUD: a small caption over a large value, on the
// garage's sunken gauge face with rivets in the corners.
//
// The race HUD is read at a glance while a child is typing, so every number on
// it is the same object with the same bezel and the same caption position, and
// the only thing that changes between the lap counter, the place and the clock
// is how wide the face is and what colour the value is.
Item {
  id: readout

  property string label: ""
  property string value: ""
  property color tone: Theme.cream
  property color faceColor: Theme.panelSunken
  property int labelSize: 13
  property int valueSize: 34
  property real valueSpacing: 2
  property bool rivets: true
  // Extra room on either side of the value, for a face that must not resize as
  // its digits change -- a clock that jitters is worse than a wide clock.
  property real padX: 18

  implicitWidth: Math.max(caption.implicitWidth, number.implicitWidth) + padX * 2
  implicitHeight: caption.implicitHeight + valueSize * 1.30 + 12

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: readout.faceColor
    border.width: 1
    border.color: Theme.lineStrong
  }

  Repeater {
    model: readout.rivets ? 4 : 0
    Rectangle {
      width: 4
      height: 4
      radius: 2
      color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.30)
      x: (index % 2 === 0) ? 5 : readout.width - 9
      y: (index < 2) ? 5 : readout.height - 9
    }
  }

  Text {
    id: caption
    textFormat: Text.PlainText
    visible: readout.label.length > 0
    text: readout.label
    x: readout.padX
    y: 7
    color: Theme.textLabel
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: readout.labelSize
    font.letterSpacing: 2
  }

  Text {
    id: number
    textFormat: Text.PlainText
    text: readout.value
    color: readout.tone
    x: readout.padX
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 5
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: readout.valueSize
    font.letterSpacing: readout.valueSpacing
  }
}
