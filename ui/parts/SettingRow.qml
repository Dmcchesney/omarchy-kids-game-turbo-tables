import QtQuick
import "../"

// One row of the race settings panel: icon, label, value, and the control
// that changes it. The row itself is not focusable; the CHANGE button is, so
// Tab lands somewhere that does something.
//
// A row whose value is fixed by the design -- Goal is the only one -- keeps
// the control's shape and reads FIXED, rather than disappearing or greying
// out into ambiguity. Enter cycles the value forward; Left and Right step it
// backward and forward, which is what makes a five-option list reachable
// without hunting.
//
// PIECE M -- THE WHOLE ROW IS THE TARGET, NOT ONLY THE CHIP.
//
// Design v4.1 names "the settings rows" among the things that must be
// clickable, and it says rows rather than buttons for a reason a child's hand
// makes obvious: the CHANGE chip is about 100 px wide at the right-hand edge of
// a row 900 px long, and everything a child is looking at while they decide --
// the icon, the word RIVALS, the value PRO -- is in the other 800. So the row
// itself takes the click and cycles the value forward, which is what Enter on
// the chip does; the chip is still a target of its own and still the thing that
// lights, so what a press will do is drawn where the eye already is.
//
// A row that cannot change takes no click at all. TRACK, GOAL and TIMER are out
// of the Tab chain by the rule that a stop which cannot act is a dead press,
// and a click that does nothing is the same dead press with a mouse.
Item {
  id: row

  property var art: []
  property color artColor: Theme.accent
  property string label: ""
  property string value: ""
  property bool changeable: true
  // What the control on the right reads when the row cannot change. Goal is
  // fixed by the design; Track has one circuit in this version.
  property string fixedLabel: "FIXED"
  // A hairline above the row. Rows carry their own rule so the panel can be
  // a plain column with no spacing arithmetic.
  property bool separator: false
  // How a screen reader should say this row's name. The visible label is set
  // in capitals for the gauge look; a reader should not have to shout it.
  property string spokenName: ""
  // The label and the non-affordance's own colours. Defaults are the shared
  // 0.80 and 0.72 alpha roles, so Settings renders exactly as it did; the
  // garage passes full-strength text, because on the brighter v3 surfaces
  // this round introduces 0.80 measures 4.30:1 and 0.72 measures 3.32:1.
  property color labelColor: Theme.textLabel
  property color fixedColor: Theme.textDisabled
  property int labelSize: 16
  property int valueSize: 24
  property int labelWidth: 190
  property alias buttonFocus: change.activeFocus

  signal stepped(int delta)

  readonly property Item focusItem: change

  // PIECE M. The pointer is somewhere on this row, on either target.
  readonly property bool hovered: row.changeable && (rowHit.hovered || changeHit.hovered)

  implicitHeight: 62

  // The row's own hover wash, under everything the row draws. A rectangle at
  // the bottom of the stacking order rather than a border, because the rows sit
  // flush against each other in a Column and a ring around one would collide
  // with the hairline the next row draws.
  Rectangle {
    anchors.fill: parent
    anchors.topMargin: row.separator ? 1 : 0
    radius: Theme.cornerRadiusSmall
    visible: row.hovered
    color: Theme.hoverFill
  }

  Rectangle {
    visible: row.separator
    width: parent.width
    height: 1
    color: Theme.line
  }

  PixelIcon {
    id: icon
    anchors.verticalCenter: parent.verticalCenter
    x: 0
    // Round-one drew these at 14 px, where the critic read them as smudges.
    width: Math.round(row.valueSize * 1.35)
    height: width
    art: row.art
    color: row.artColor
    inks: ({ "A": row.artColor, "B": "transparent" })
  }

  Text {
    id: name
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    x: icon.x + icon.width + Math.round(row.valueSize * 0.7)
    width: row.labelWidth
    text: row.label
    color: row.labelColor
    font.family: Theme.mono
    font.pixelSize: row.labelSize
    font.letterSpacing: 1.4
    elide: Text.ElideRight
  }

  Text {
    id: readValue
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    x: name.x + name.width
    width: change.x - x - Math.round(row.valueSize * 0.5)
    text: row.value
    color: Theme.cream
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: row.valueSize
    font.letterSpacing: 0.8
    elide: Text.ElideRight
  }

  Item {
    id: change
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    width: Math.round(row.valueSize * 4.4)
    height: Math.round(row.valueSize * 1.5)
    // See ActionButton: a stop in Qt's implicit tab chain swallows Tab before
    // the screen that owns it can act on it. `Accessible.focusable` below is
    // still driven by `changeable`.
    activeFocusOnTab: false

    // PIECE M -- A ROW THAT CANNOT CHANGE IS NOT A BUTTON, AND SAID IT WAS.
    //
    // TRACK, GOAL and TIMER carried `Accessible.role: Accessible.Button` and
    // `Accessible.focusable: false`, which is a control that announces itself as
    // pressable and cannot be pressed or reached. Nothing noticed for five
    // rounds; the control walk this piece is gated on noticed on its first run,
    // because it reads the role to find controls the click list might have
    // missed and found two "buttons" with nothing behind them. They are status
    // readouts and now say so. The role is the only thing that changes: the
    // name, the description, the FIXED chip and the missing focus stop were all
    // already right.
    Accessible.role: row.changeable ? Accessible.Button : Accessible.StaticText
    readonly property string spoken: row.spokenName.length > 0 ? row.spokenName : row.label
    Accessible.name: row.changeable ? (spoken + ", " + row.value + ", change")
                                    : (spoken + ", " + row.value + ", fixed")
    Accessible.description: row.changeable
                            ? "Enter changes it. Left and right step through the choices."
                            : "This one is set by the game and cannot change."
    Accessible.focusable: row.changeable
    Accessible.onPressAction: if (row.changeable) row.stepped(1)

    Keys.onPressed: function (event) {
      if (!row.changeable)
        return
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Right) {
        row.stepped(1)
        event.accepted = true
      } else if (event.key === Qt.Key_Left) {
        row.stepped(-1)
        event.accepted = true
      }
    }

    // A button looks like a button and a status chip does not. Round two gave
    // `1 OF 1` and `FIXED` the same pill, border, radius and size as the three
    // CHANGE buttons at the same x, so a child had to read the words to find
    // out which two of the five rows they could not touch. The status rows now
    // carry no fill and no border at all -- they are plain text in the column
    // where the buttons are.
    Rectangle {
      visible: row.changeable
      anchors.fill: parent
      radius: Theme.cornerRadiusSmall
      color: row.hovered
             ? Theme.hoverFill
             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.05)
      border.width: 1
      border.color: row.hovered ? Theme.hoverRing : Theme.lineStrong
    }

    // ROUND-4: the right rail is one line. A chip has no box, so centring its
    // text in the button's footprint ended it 24 to 29 px short of the
    // buttons' right edge and left the column ragged. The chips are now
    // right-aligned on the same rail the button boxes end at, which is the
    // edge the eye actually reads down.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.horizontalCenter: row.changeable ? parent.horizontalCenter : undefined
      anchors.right: row.changeable ? undefined : parent.right
      textFormat: Text.PlainText
      text: row.changeable ? "CHANGE" : row.fixedLabel
      // A row that cannot change still has to say why, and be read while it
      // says it: disabled means "not actionable", not "invisible".
      color: row.changeable ? Theme.text : row.fixedColor
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.round(row.labelSize * 0.92)
      font.letterSpacing: 1
    }

    FocusRing {
      on: change.activeFocus || row.hovered
      hover: !change.activeFocus
    }

    Clickable {
      id: changeHit
      objectName: "clickSettingChange"
      enabled: row.changeable
      stop: row.changeable ? change : null
      label: row.spokenName.length > 0 ? row.spokenName : row.label
      does: "change " + (row.spokenName.length > 0 ? row.spokenName : row.label)
      key: "Enter, or Left and Right"
      onActed: row.stepped(1)
    }
  }

  // The row itself, declared LAST so it is the bottom of the input stack: the
  // CHANGE chip above it takes the presses that land on the chip, and this one
  // takes everything else. Both call `row.stepped(1)`, which is what the chip's
  // own Enter calls, so there is one behaviour and two places to reach it.
  Clickable {
    id: rowHit
    objectName: "clickSettingRow"
    // ROUND 5 OF PIECE M, AND WHAT IS *NOT* DONE HERE, MEASURED.
    //
    // At 1024 x 600 the GARAGE's three rows render 23 px tall -- one pixel under
    // the WCAG 2.2 AA floor, which is the floor for an adult and not for the
    // seven-year-old this game is for. (The Settings screen's rows are 57 px;
    // this is the garage's denser layout.) Flooring the hit area at 24 here was
    // tried and `test_44` refused it: the rows are stacked with no gap left at
    // that size, so each grown target overlapped its neighbour by a pixel, and
    // the control under the pointer would not be the one the child is reading.
    //
    // A pixel of room between three rows is the GARAGE's layout, which is piece
    // 3's and not this one's. It is left measured rather than fixed: `test_44`
    // prints all six of these by name at 1024 x 600 and holds the count where it
    // is, so it can come down and cannot go up.
    enabled: row.changeable
    stop: row.changeable ? change : null
    label: (row.spokenName.length > 0 ? row.spokenName : row.label) + " row"
    does: "change " + (row.spokenName.length > 0 ? row.spokenName : row.label)
    key: "Enter, or Left and Right"
    onActed: row.stepped(1)
    z: -1
  }
}
