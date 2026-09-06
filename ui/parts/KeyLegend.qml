import QtQuick
import "../"

// PIECE M ROUND 4. THE ONE THING IN THIS GAME THAT PRINTS A KEY AND IS NOT A
// CONTROL, AND IT NO LONGER LOOKS LIKE ONE.
//
// The garage and the settings screen carry a rail in the title band -- `TAB
// MOVE · ARROWS CHANGE · ENTER CHOOSE · ESC LEAVE` -- which states the whole
// screen's keyboard rather than offering an action at the place the action
// happens. There is nothing for it to do: an on-screen Tab key would be a
// second way to do everything and a control a child could press that changes
// nothing they were looking at.
//
// WHAT WAS WRONG WITH IT, and it shipped for three rounds. Both rails drew each
// key as a WORD INSIDE A BORDERED, FILLED BOX -- and seven hundred pixels to the
// left, on the same title band, `ui/Game.qml`'s `S  SETTINGS AND RESETS` is
// drawn with the identical construction, the identical fill and the identical
// border, and it lights under the pointer and it opens the settings. Two
// identically-drawn keycap-plus-word constructs on one screen, one live and one
// dead. A child who presses the live one learns the rule; the four beside it
// teach the opposite, and the rule the whole piece rests on -- IF IT LIGHTS UP
// WHEN YOU POINT AT IT, YOU CAN PRESS IT -- only works in the direction a child
// uses it if the things that never light do not look like the things that do.
//
// Round three's note celebrated deleting the `keyLegend: true` flag that used to
// excuse the rails from a rule about printed keys. A critic pointed out what
// that bought: it removed the contradiction from the CODE and left it on the
// SCREEN, and the exemption became implicit in the construction, so the next
// builder does not even have to know they are taking one.
//
// So: no box, no border, no fill. A legend is a caption -- the keys in the
// screen's own type, the actions in the quieter label tone, joined by the
// mid-dot this game already uses to join clauses -- and it declares itself
// (`isKeyLegend`) so that the check which forbids a dead printed key can name
// the one exception instead of not seeing it. `dev/Harness.qml
// --print-controls` prints a `legend` row per group, so the exemption is on the
// evidence a reader is handed rather than in a comment somewhere.
Row {
  id: legend

  // The duck-type. One declared exemption, findable from the tree, exactly as
  // `isClickTarget` and `isKeyHint` are.
  readonly property bool isKeyLegend: true

  // `[{ key: "TAB", what: "MOVE" }, ...]`, in the order they are read.
  property var groups: []

  property int textSize: 15
  property real letterSpacing: 1
  property real gap: 20
  property color keyColor: Theme.text
  property color actionColor: Theme.textLabel

  // What the rail says, as one string, so a caller or a walk can read the whole
  // legend without re-joining the groups the way it draws them.
  readonly property string legendText: {
    var line = ""
    for (var i = 0; i < legend.groups.length; i++) {
      if (i > 0)
        line += "  ·  "
      line += legend.groups[i].key + "  " + legend.groups[i].what
    }
    return line
  }

  // A caption, not a control: nothing here is announced as pressable, and the
  // screen's own description already tells a reader what its keys do.
  Accessible.role: Accessible.StaticText
  Accessible.name: legend.legendText

  spacing: legend.gap

  Repeater {
    model: legend.groups

    Row {
      spacing: Math.round(legend.gap * 0.4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: modelData.key
        color: legend.keyColor
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: legend.textSize
        font.letterSpacing: legend.letterSpacing
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: modelData.what
        color: legend.actionColor
        font.family: Theme.mono
        font.pixelSize: legend.textSize
        font.letterSpacing: legend.letterSpacing
      }
    }
  }
}
