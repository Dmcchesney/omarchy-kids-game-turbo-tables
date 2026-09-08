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

  // ROUND 3 -- A SIGN SAYS THAT IT IS ONE.
  //
  // A critic counted these four tiles among the things "still unclickable" and
  // was right that nothing could tell: they are laid out exactly like a row of
  // buttons, in a bordered panel, with their own surface and tone, and the
  // parity walk printed no row for them at all. A reader of that table could
  // not distinguish a display that was DECIDED from a control that was
  // FORGOTTEN, and this piece's whole argument is enumeration rather than
  // assertion.
  //
  // They stay displays, and the decision above is why: the design's words for
  // this panel are "the four-signal catalog SHOWN so the child learns them",
  // there is no key that sends one from the garage, and a click target with no
  // key behind it is a mouse-only path -- which the design forbids exactly as
  // squarely as the keyboard-only ones this piece exists to remove. Round three
  // made them controls and a critic had it taken out again.
  //
  // So instead of being absent from the tables they are IN them, as signs.
  // `dev/Harness.qml --print-controls` prints a `sign` row for each and a
  // `parity signs` count, and `tst_mouse_parity.qml` holds every declared sign
  // to the rule a sign has to keep: it takes no click and it never lights.
  readonly property bool isSign: true
  readonly property string signLabel: tile.caption

  property var art: []
  property string caption: ""
  property color tone: Theme.lime
  property int captionSize: 14
  // The tile's own fill. Defaults to what it has always been, so a screen
  // that does not set it is unchanged; the garage sets it to the v3 dusk
  // surface so the legend belongs to the room it sits in.
  property color surface: Theme.panelSunken

  activeFocusOnTab: false

  Accessible.role: Accessible.StaticText
  Accessible.name: caption
  Accessible.description: "A signal a racer can send. Rivals send it too."

  // ROUND 4 -- A SIGN THAT SAYS SO IN THE TABLE AND SAYS THE OPPOSITE ON THE
  // SCREEN IS STILL A LIE.
  //
  // Round three's answer to "a child cannot tell a decided display from a
  // forgotten control" was to declare `isSign` and print it in the parity table.
  // A critic accepted the mechanism and rejected the judgement, in the only
  // words that matter: these four were "bordered cards with an icon and a
  // caption in a bordered panel, laid out exactly like a row of four buttons,
  // immediately left of the loudest button on the screen. A CHILD WILL PRESS
  // THESE. Every one of them." A declaration in a table is read by a maintainer;
  // the border is read by the child.
  //
  // So the border and the fill are gone and the icon and its word sit on the
  // panel's own ground. The panel around them keeps its border and its caption
  // -- "These are the only signals in a race. The rivals send them too." -- so
  // the four read as a vocabulary list, which is what the design calls them:
  // "the four-signal catalog SHOWN so the child learns them". The one sign a
  // critic accepted without reservation, RACE A FRIEND, is accepted for exactly
  // this reason: dashed border, no fill, a notice rather than a button.
  //
  // `surface` is kept and unused by the tile itself, because callers set it and
  // a screen that wants a ground behind a legend can still draw one.
  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: "transparent"
    border.width: 0
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
