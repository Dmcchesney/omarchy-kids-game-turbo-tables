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
// ROUND 3 -- THE WALK ASKS THE COMPONENT, AND NEVER READS THE WORDS.
//
// Round two's oracle read the rendered STRINGS and decided from their shape
// whether each one was a hint. A critic demonstrated in the running game that
// it was wrong in both directions and always would be: `3  CORRECT`, `7  LAPS`
// and `2  TO GO` -- scoreboard copy for a maths racing game -- were flagged as
// dead key hints, while `PAUSE  P`, a two-line `H\nPIT CREW`, a one-space
// `ESC BACK` and every glyph and word outside a hard-coded table were invisible
// to it. A rule that guesses intent from appearance cannot be made right by
// widening the table; each widening buys a false negative back at the price of
// a false positive somewhere else.
//
// So a hint is a hint because it SAYS SO. `isKeyHint` is the duck-type the walk
// finds, exactly as `isClickTarget` is on `Clickable`, and nothing anywhere
// parses a label any more. The other half of that -- what stops the next
// builder printing a key with a plain `Text` again -- is `npm run
// check:keyhints`, which is a rule about what may be WRITTEN rather than a
// guess about what a string means, runs on the source, and is inside `npm run
// check` where the QML suite is not.
//
// THE KEY LEGEND, and it needs no exemption any more. The garage and the
// settings screen carry a rail in the title band -- `TAB  ↑ ↓  MOVE`,
// `ESC  BACK` -- which states the whole screen's keyboard rather than offering
// an action at the place the action happens. It is drawn as a keycap beside a
// word, in two items, with no literal that pairs them: it is not a `KeyHint`,
// so the walk never lists it, and it is not a written hint string, so the source
// check never sees it. Round two needed a `keyLegend: true` flag on the rail to
// excuse it from a rule that should never have applied; the flag is gone.
//
// The child-visible rule is unchanged and is the one a child can actually
// learn: if it lights up when you point at it, you can press it.
Item {
  id: hint

  // The duck-type the walk finds. QML has no `instanceof` for a component here,
  // and neither the harness nor the suite may have to know this file's name.
  readonly property bool isKeyHint: true

  // The keys, as they are printed: "ESC", "⏎", "◀ ▶", "1 2 3".
  property string keys: ""
  // What they do, in the words already on the screen: "LEAVE", "USE IT".
  property string action: ""
  // PIECE F ROUND 7 -- A KEY CAP, THE WAY THE GARAGE DRAWS ONE.
  //
  // Design v4.1, Accessibility: "Key hints in the race are drawn as key caps,
  // the way the garage draws them: `[H] PIT CREW · shows the answer`". The
  // garage's `S  SETTINGS AND RESETS` door (`ui/Game.qml`) is a bordered,
  // filled cap with the key in it beside the word in the label tone; with
  // `cap` on, this component draws the same construction, so the race's two
  // hints and the hand panel's footer are the garage's idiom and not a second
  // one. The words, the hover, the role and the click target are unchanged:
  // a cap is how the line is DRAWN, and `text` still reads `H  PIT CREW`.
  //
  // `sub` is the quiet clause after the mid-dot -- `shows the answer` -- and it
  // is part of the printed line, so `text` carries it for the walk.
  property bool cap: false
  property string sub: ""

  // The whole printed line. Two spaces between the keys and the action is the
  // game's own hint grammar and it is what the harness's oracle reads.
  readonly property string text: hint.keys + "  " + hint.action
                                 + (hint.sub.length > 0 ? "  ·  " + hint.sub : "")

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
  // ROUND 4. The presses that reach this hint's own state, when they are not
  // one press of the first key `key` names. See `ui/parts/Clickable.qml`.
  property var keyRoute: null
  property string keyGap: ""
  property bool destructive: false
  // ROUND 4. The action this hint performs, so that two controls doing the same
  // destructive thing share one guard and a key handler doing it is refused by
  // the same press. See `ui/parts/Actions.qml`.
  property var guards: []
  property Item stop: null
  property string help: ""

  signal tapped()

  readonly property bool hovered: hintHit.hovered
  readonly property int refusedRepeats: hintHit.refusedRepeats
  // ROUND 3. Is this control still inside the double-click interval of a press
  // it accepted? A screen's own KEY handler reads this so that the guard is not
  // one-sided. See the note beside the Escape branch in `ui/Race.qml`.
  readonly property bool guarding: hintHit.guarding

  implicitWidth: (hint.cap ? capRow.implicitWidth : line.implicitWidth) + hint.padWidth
  implicitHeight: (hint.cap ? capRow.implicitHeight : line.implicitHeight) + hint.padHeight
  width: implicitWidth
  height: implicitHeight

  // WHAT A SCREEN READER SAYS, AND IT IS NOT THE PRINTED WORD.
  //
  // The printed line is upper case because every hint in this game is, and a
  // reader handed `BACK TO THE GARAGE` may spell it out. `name` is the control's
  // own name in ordinary words, written by the caller in ordinary case -- and it
  // is the SAME string the parity table prints and the drive scripts match on,
  // which they do case-insensitively, so there is one name per control and no
  // second copy of it. Round one's countdown said "Back to the garage" and it
  // still does.
  //
  // Assembled from nothing: `check:readme` forbids building a name a character
  // at a time in a plugin file, and it is right to -- a name that is spelled at
  // runtime is a name nobody read.
  Accessible.role: Accessible.Button
  Accessible.name: hint.name.length > 0 ? hint.name : hint.action
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
    visible: !hint.cap
    textFormat: Text.PlainText
    text: hint.text
    color: hintHit.hovered ? hint.liveColor : hint.idleColor
    font.family: Theme.mono
    font.bold: hint.bold
    font.pixelSize: hint.textSize
    font.letterSpacing: hint.letterSpacing
  }

  // The cap: the keys in a bordered box, the action beside it, the clause after
  // a mid-dot in the quieter tone. The same fill, border and brightening the
  // garage door uses, so one rule -- if it lights up when you point at it, you
  // can press it -- is drawn one way across the game.
  Row {
    id: capRow
    anchors.centerIn: parent
    visible: hint.cap
    spacing: Math.max(6, Math.round(hint.textSize * 0.5))

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: capKeys.implicitWidth + Math.max(10, Math.round(hint.textSize * 0.8))
      height: Math.max(20, Math.round(hint.textSize * 1.55))
      radius: Theme.cornerRadiusSmall
      color: hintHit.hovered
             ? Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.18)
             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.07)
      border.width: 1
      border.color: hintHit.hovered ? Theme.hoverRing : Theme.lineStrong

      Text {
        id: capKeys
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: hint.keys
        color: hintHit.hovered ? Theme.textBright : Theme.text
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: hint.textSize
        font.letterSpacing: hint.letterSpacing
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: hint.action
      color: hintHit.hovered ? hint.liveColor : hint.idleColor
      font.family: Theme.mono
      font.bold: hint.bold
      font.pixelSize: hint.textSize
      font.letterSpacing: hint.letterSpacing
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: hint.sub.length > 0
      textFormat: Text.PlainText
      text: "·  " + hint.sub
      color: hintHit.hovered ? hint.liveColor : Theme.textLabel
      font.family: Theme.mono
      font.bold: false
      font.pixelSize: hint.textSize
      font.letterSpacing: hint.letterSpacing
    }
  }

  Clickable {
    id: hintHit
    objectName: "clickKeyHint"
    // ROUND 5. THE FLOOR, AND WHY IT IS HERE RATHER THAN ON EVERY TARGET.
    //
    // A printed key hint is the small-type idiom of this game -- it is the
    // pit crew, the way out of a race, the way out of a countdown, the chip that
    // spends a hand and the line that answers the one question -- and at
    // 1024 x 600 they were the smallest things on every screen: 14 to 22 px
    // tall, against a WCAG 2.2 AA floor of 24 for an adult. The hit area is 24
    // square at minimum, centred on the words, and the words do not move.
    //
    // Not on `Clickable` itself, because the other targets in this game are rows
    // and cards that are already larger and are stacked with small gaps: a
    // blanket floor there would grow neighbours into each other, which puts the
    // wrong control under the pointer.
    minWidth: 24
    minHeight: 24
    stop: hint.stop
    label: hint.name.length > 0 ? hint.name : hint.action.toLowerCase()
    does: hint.does
    key: hint.key
    keyRoute: hint.keyRoute
    keyGap: hint.keyGap
    destructive: hint.destructive
    guards: hint.guards
    onActed: hint.tapped()
  }
}
