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
//
// PIECE M -- AND THE TWO ARROWS WERE ALREADY DRAWN AS BUTTONS.
//
// This control has looked clickable since round one: two arrow keys either side
// of a gauge face, which is the shape of a spin box on every desktop a child
// has ever used. It was not clickable, and design v4.1 names it first among the
// things that must be ("including the garage's steppers and swatches"). The two
// arrows now click, and each one emits `stepped()` with the same delta its key
// sends -- the left arrow is Left, the right arrow is Right. The face between
// them takes a click too, and that click only takes focus: there is no third
// thing a stepper does, and a face that silently stepped in one direction would
// be a control whose behaviour depends on where inside it you pressed.
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

  // ROUND-8: NOT in Qt's implicit tab chain, and that is what makes the
  // screen's own Tab handler reachable. Qt Quick delivers a key to the focused
  // item first; when that item has `activeFocusOnTab` set and ignores Tab, the
  // delivery agent runs focus-chain navigation and CONSUMES the event there,
  // so a screen's Keys.onPressed never sees Tab at all. Two rounds of Tab code
  // in Garage.qml were dead for exactly that reason, and two mutations of it
  // left twenty tests green. Focus on these controls is moved by the screen
  // that owns them, through its published `stops` list. `Accessible.focusable`
  // is unchanged, so a screen reader still sees a focusable control.
  activeFocusOnTab: false

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
      // PIECE M. The arrow lights under the pointer, in the accent wash the
      // focus ring uses, so a child sweeping across the control can see which
      // half of it they are about to press.
      color: leftHit.hovered
             ? Theme.hoverFill
             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.05)
      border.width: 1
      border.color: leftHit.hovered ? Theme.hoverRing
                                    : (stepper.activeFocus ? Theme.lineStrong : Theme.line)

      PixelIcon {
        anchors.centerIn: parent
        width: Math.round(parent.height * 0.46)
        height: width
        mirror: true
        art: Glyphs.chevron
        color: (stepper.activeFocus || leftHit.hovered) ? Theme.accent : Theme.text
      }

      Clickable {
        id: leftHit
        objectName: "clickStepDown"
        stop: stepper
        label: stepper.name + " down"
        does: "step " + stepper.name + " back one"
        key: "Left"
        onActed: stepper.stepped(-1)
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

      // The face is not a third action. Clicking it puts the keyboard on this
      // control and stops there, which is what clicking the middle of a spin
      // box does everywhere else; a face that stepped would make the meaning of
      // a press depend on which pixel it landed on.
      Clickable {
        id: faceHit
        objectName: "clickStepFace"
        stop: stepper
        label: stepper.name
        does: "put the keyboard on " + stepper.name
        key: "Tab"
      }
    }

    Rectangle {
      id: right
      width: stepper.arrowWidth
      height: parent.height
      radius: Theme.cornerRadiusSmall
      color: rightHit.hovered
             ? Theme.hoverFill
             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.05)
      border.width: 1
      border.color: rightHit.hovered ? Theme.hoverRing
                                     : (stepper.activeFocus ? Theme.lineStrong : Theme.line)

      PixelIcon {
        anchors.centerIn: parent
        width: Math.round(parent.height * 0.46)
        height: width
        art: Glyphs.chevron
        color: (stepper.activeFocus || rightHit.hovered) ? Theme.accent : Theme.text
      }

      Clickable {
        id: rightHit
        objectName: "clickStepUp"
        stop: stepper
        label: stepper.name + " up"
        does: "step " + stepper.name + " on one"
        key: "Right"
        onActed: stepper.stepped(1)
      }
    }
  }

  FocusRing {
    on: stepper.activeFocus || leftHit.hovered || faceHit.hovered || rightHit.hovered
    hover: !stepper.activeFocus
  }
}
