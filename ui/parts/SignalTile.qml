import QtQuick
import "../"

// One card of the four-signal catalog. The catalog is on the garage so the
// child meets the vocabulary before a rival uses it mid-race; Enter previews
// the signal so meeting it is not just reading it.
Item {
  id: tile

  property var art: []
  property string caption: ""
  property color tone: Theme.lime
  property int captionSize: 14

  signal activated()

  activeFocusOnTab: true

  Accessible.role: Accessible.Button
  Accessible.name: caption
  Accessible.description: "A preset signal. Enter shows it the way a rival sends it."
  Accessible.focusable: true
  Accessible.onPressAction: tile.activated()

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      tile.activated()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: Theme.panelSunken
    border.width: 1
    border.color: tile.activeFocus ? Theme.lineStrong : Theme.line
  }

  Column {
    anchors.centerIn: parent
    spacing: Math.round(tile.captionSize * 0.75)

    PixelIcon {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.round(tile.height * 0.46)
      height: width
      art: tile.art
      color: tile.tone
      // "B" and "o" are holes: the checkered flag's dark squares and the
      // notches that separate a thumb from its fist and a fist from its cuff.
      inks: ({ "A": tile.tone, "B": "transparent", "o": "transparent" })
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: tile.caption
      color: tile.tone
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: tile.captionSize
      font.letterSpacing: 0.6
    }
  }

  FocusRing { on: tile.activeFocus }
}
