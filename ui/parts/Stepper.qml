import QtQuick
import "../"

// The arrows-and-face control: one focus stop, two visible arrows, left and
// right to step. Used for the kart body and for the kart number.
//
// One stop rather than two buttons on purpose. Left and Right are already how
// a child moves along a row, the arrows on screen show which keys do it, and
// a number that runs from 1 to 99 must never need a text field -- the design
// forbids free text anywhere in this game, and this is the control that would
// otherwise have wanted it.
Item {
  id: stepper

  property string value: ""
  property string name: ""
  property string hint: "Left and right change it."
  property int valueSize: 30
  property real valueSpacing: 2
  property color valueColor: Theme.cream
  property int arrowWidth: 34
  property bool wide: false
  // The face behind the value. Defaults to Readout's own default, so a screen
  // that does not set it is unchanged.
  property color faceColor: Theme.panelSunken

  signal stepped(int delta)

  activeFocusOnTab: true

  Accessible.role: Accessible.SpinBox
  Accessible.name: stepper.name + ", " + stepper.value
  Accessible.description: stepper.hint
  Accessible.focusable: true

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Left) {
      stepper.stepped(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right) {
      stepper.stepped(1)
      event.accepted = true
    }
  }

  implicitHeight: Math.round(valueSize * 1.75)

  Row {
    anchors.fill: parent
    spacing: Math.round(stepper.arrowWidth * 0.24)

    Rectangle {
      id: left
      width: stepper.arrowWidth
      height: parent.height
      radius: Theme.cornerRadiusSmall
      color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.05)
      border.width: 1
      border.color: stepper.activeFocus ? Theme.lineStrong : Theme.line

      PixelIcon {
        anchors.centerIn: parent
        width: Math.round(parent.height * 0.46)
        height: width
        mirror: true
        art: Glyphs.chevron
        color: stepper.activeFocus ? Theme.accent : Theme.text
      }
    }

    Readout {
      width: parent.width - stepper.arrowWidth * 2 - Math.round(stepper.arrowWidth * 0.48)
      height: parent.height
      value: stepper.value
      faceColor: stepper.faceColor
      valueSize: stepper.valueSize
      valueSpacing: stepper.valueSpacing
      valueColor: stepper.valueColor
      rivetInset: Math.max(3, Math.round(parent.height * 0.14))
      rivetSize: Math.max(1.5, parent.height * 0.045)
    }

    Rectangle {
      width: stepper.arrowWidth
      height: parent.height
      radius: Theme.cornerRadiusSmall
      color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.05)
      border.width: 1
      border.color: stepper.activeFocus ? Theme.lineStrong : Theme.line

      PixelIcon {
        anchors.centerIn: parent
        width: Math.round(parent.height * 0.46)
        height: width
        art: Glyphs.chevron
        color: stepper.activeFocus ? Theme.accent : Theme.text
      }
    }
  }

  FocusRing { on: stepper.activeFocus }
}
