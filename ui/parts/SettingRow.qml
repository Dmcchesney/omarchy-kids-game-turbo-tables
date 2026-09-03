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
  property int labelSize: 16
  property int valueSize: 24
  property int labelWidth: 190
  property alias buttonFocus: change.activeFocus

  signal stepped(int delta)

  readonly property Item focusItem: change

  implicitHeight: 62

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
    color: Theme.textLabel
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
    activeFocusOnTab: row.changeable

    Accessible.role: Accessible.Button
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
      color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.05)
      border.width: 1
      border.color: Theme.lineStrong
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: row.changeable ? "CHANGE" : row.fixedLabel
      // A row that cannot change still has to say why, and be read while it
      // says it: disabled means "not actionable", not "invisible".
      color: row.changeable ? Theme.text : Theme.textDisabled
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.round(row.labelSize * 0.92)
      font.letterSpacing: 1
    }

    FocusRing { on: change.activeFocus }
  }
}
