import QtQuick
import "../"

// One line of the results stats block: a label on the left, its value on the
// right of a fixed rail.
//
// The design's Results wireframe sets two of these side by side --
// `TIME  8:41   LAPS  12 / 12` -- so what a row has to guarantee is that the
// label column and the value column line up down the whole block whatever the
// values are. That is why the label has a fixed width and the value starts at
// its right edge rather than after it: a longer label never shoves its own
// value out of the column, and the eye reads two straight rails instead of a
// ragged pair.
//
// Not a control. Nothing here is focusable and nothing here can be typed into.
Item {
  id: statRow

  property string label: ""
  property string value: ""
  property color valueColor: Theme.cream
  property int labelSize: 16
  property int valueSize: 24
  property int labelWidth: 190
  // A value long enough to need the whole row -- the POWER-UPS line, which
  // grows a card at a time as the child spends hands -- says so, and is allowed
  // to run onto a second line instead of being cut off with an ellipsis. A
  // results screen that hides the last power-up the child spent is the one
  // thing this row must not do.
  property bool wide: false

  implicitHeight: wide ? Math.round(reading.implicitHeight + valueSize * 0.85)
                       : Math.round(valueSize * 1.85)
  height: implicitHeight

  Accessible.role: Accessible.StaticText
  Accessible.name: statRow.label + ", " + statRow.value

  Text {
    id: name
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    x: 0
    width: statRow.labelWidth
    text: statRow.label
    color: Theme.textLabel
    font.family: Theme.mono
    font.pixelSize: statRow.labelSize
    font.letterSpacing: 1.4
    elide: Text.ElideRight
  }

  Text {
    id: reading
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    x: statRow.labelWidth
    width: statRow.width - statRow.labelWidth
    text: statRow.value
    color: statRow.valueColor
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: statRow.valueSize
    font.letterSpacing: 0.8
    lineHeight: 1.2
    wrapMode: statRow.wide ? Text.WordWrap : Text.NoWrap
    elide: statRow.wide ? Text.ElideNone : Text.ElideRight
  }
}
