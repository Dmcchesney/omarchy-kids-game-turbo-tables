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

  color: Theme.panel
  radius: Theme.cornerRadius
  border.width: 1
  border.color: Theme.line

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
