import QtQuick
import "../"

// PIECE M ROUND 2. A PRINTED KEY HINT THAT IS ALSO THE CONTROL.
//
// This game prints its keyboard on the screen -- `ESC  LEAVE`, `H  PIT CREW`,
// `⏎  USE IT      ESC  BACK` -- and round one made three of those lines
// clickable and left the rest as paint. A critic found the consequence and it
// is the right one to worry about: a child who learns that the little ESC line
// is pressable on one screen will press it on the next, and on two of the four
// screens that print it nothing happened. The hint idiom had become a promise
// the game kept in some places and broke in others.
//
// It is one component now, so the promise cannot be half-kept. Everything a
// key hint is -- the words, the padding, the wash under the pointer, the
// brightening of the text, the `Accessible.role` that makes it a control to a
// screen reader, and the click target that carries the parity columns -- is
// here, once. A screen that prints a key hint gets all of it or writes a plain
// `Text`, and `dev/Harness.qml --print-controls` reads the STRINGS on the
// screen and fails any hint-shaped one with no click target over it. That is
// the third oracle, and it exists because the other two are structurally blind
// to a label: a hint never declares `Accessible.role` on its own and never
// appears in a `stops` array, so nothing in round one's gate could see it.
//
// THE ONE EXCEPTION, AND IT IS ENUMERATED. The garage and the settings screen
// carry a key LEGEND in the title band -- `TAB  ↑ ↓  MOVE`, `ESC  BACK` -- which
// states the whole screen's keyboard rather than offering an action at the
// place the action happens. Those are marked `keyLegend` on the rail that holds
// them, the walk prints them as `legend`, and they never light under the
// pointer. The child-visible rule is the one a child can actually learn: if it
// lights up when you point at it, you can press it.
Item {
  id: hint

  // The keys, as they are printed: "ESC", "⏎", "◀ ▶", "1 2 3".
  property string keys: ""
  // What they do, in the words already on the screen: "LEAVE", "USE IT".
  property string action: ""
  // The whole printed line. Two spaces between the keys and the action is the
  // game's own hint grammar and it is what the harness's oracle reads.
  readonly property string text: hint.keys + "  " + hint.action

  property int textSize: 17
  property real letterSpacing: 2
  property bool bold: true
  property color idleColor: Theme.textLabel
  property color liveColor: Theme.textBright
  // The box around the words. Named as the whole extra, not as one side, so a
  // caller porting an existing hint can keep its exact geometry.
  property real padWidth: 16
  property real padHeight: 9

  // The parity columns, straight through to the click target.
  property string name: ""
  property string does: ""
  property string key: ""
  property bool destructive: false
  property Item stop: null
  property string help: ""

  signal tapped()

  readonly property bool hovered: hintHit.hovered
  readonly property int refusedRepeats: hintHit.refusedRepeats

  implicitWidth: line.implicitWidth + hint.padWidth
  implicitHeight: line.implicitHeight + hint.padHeight
  width: implicitWidth
  height: implicitHeight

  Accessible.role: Accessible.Button
  Accessible.name: hint.action
  Accessible.description: hint.help.length > 0
                          ? hint.help
                          : (hint.does + ". The " + hint.keys + " key does it too.")
  Accessible.onPressAction: hint.tapped()

  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    visible: hintHit.hovered
    color: Theme.hoverFill
    border.width: 1
    border.color: Theme.hoverRing
  }

  Text {
    id: line
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: hint.text
    color: hintHit.hovered ? hint.liveColor : hint.idleColor
    font.family: Theme.mono
    font.bold: hint.bold
    font.pixelSize: hint.textSize
    font.letterSpacing: hint.letterSpacing
  }

  Clickable {
    id: hintHit
    objectName: "clickKeyHint"
    stop: hint.stop
    label: hint.name.length > 0 ? hint.name : hint.action.toLowerCase()
    does: hint.does
    key: hint.key
    destructive: hint.destructive
    onActed: hint.tapped()
  }
}
