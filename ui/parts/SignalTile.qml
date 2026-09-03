import QtQuick
import "../"

// One card of the four-signal catalog.
//
// A LEGEND, NOT A CONTROL. The design's own words for this panel are "the
// four-signal catalog SHOWN so the child learns them before racing rivals who
// use them", and the panel's caption on the screen says the same: "These are
// the only signals in a race. The rivals send them too."
//
// Round three made each tile a Tab stop with an Enter action that previewed
// the signal. A critic called it correctly: that puts four non-actionable
// display tiles between the settings and the ready control -- four dead
// presses for a child working the keyboard, and four focusable objects with
// no action for a screen reader. The tiles are now static: no focus, no key
// handling, and one accessible name each so a reader still reads the
// vocabulary out when it walks the panel.
Item {
  id: tile

  property var art: []
  property string caption: ""
  property color tone: Theme.lime
  property int captionSize: 14

  activeFocusOnTab: false

  Accessible.role: Accessible.StaticText
  Accessible.name: caption
  Accessible.description: "A signal a racer can send. Rivals send it too."

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: Theme.panelSunken
    border.width: 1
    border.color: Theme.line
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
}
