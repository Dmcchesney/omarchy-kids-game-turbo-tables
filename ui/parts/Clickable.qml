import QtQuick
import "../"

// PIECE M. ONE CLICK TARGET, AND THE ONLY KIND THERE IS.
//
// The maintainer said it twice -- "clicking things did not do much", and then,
// having watched everything else improve, "the mouse still doesn't work". The
// cause was total and is recorded in `docs/open-questions.md` §5.1: no screen
// under `ui/` had a `MouseArea`, a `TapHandler` or a `HoverHandler` anywhere,
// so the only two click areas in the whole plugin were the overlay's dismiss
// scrim and the bar button. The design said "every screen operates with the
// keyboard alone" and the build read that as *keyboard only*; design v4.1
// corrects it to **keyboard first, mouse always**.
//
// WHY ONE COMPONENT RATHER THAN A `MouseArea` PER CONTROL. The gate for this
// piece is parity proved in BOTH directions -- nothing reachable by click and
// not by key, nothing reachable by key and not by click -- and proved by
// ENUMERATION rather than by assertion, so that a control which exists but was
// forgotten cannot pass unnoticed. That is only possible if "what can be
// clicked in this game" is a question the item tree can answer. It is: every
// click target in `ui/` is one of these and nothing else in `ui/` declares a
// mouse handler at all, so `dev/Harness.qml --print-controls` can walk any
// screen, find every one of them by `isClickTarget`, and print the table. A
// second `MouseArea` written by hand somewhere would be a click target the
// walk cannot see, which is exactly the class of defect the gate is against.
//
// WHAT A CLICK MEANS HERE, and it is one rule for the whole game:
//
//   a click is the Tab that lands on this control and the Enter that fires it,
//   in one press.
//
// So `onClicked` focuses `stop` -- the item the screen's own `stops` list
// names, the very item Tab lands on -- and then emits `acted()`, which every
// caller wires to the SAME function its key handler calls. Not a copy of it: a
// click on READY UP calls `activated()`, which is what Enter calls; a click on
// a paint swatch calls `picked(index)`, which is what Left and Right call. Two
// code paths that merely agree today are two code paths that disagree later.
//
// A click that focused nothing would be a mouse-only path -- the child would
// click a control, the keyboard would still be standing somewhere else, and
// the next Tab would jump away from what they just touched. Every target
// therefore names its stop, and a target on something that is not a stop
// (`stop: null`) is a control the keyboard reaches by a key rather than by
// Tab: `key` says which, and the enumeration prints it.
MouseArea {
  id: hit

  // The focus stop this target belongs to: what Tab lands on, and what a click
  // focuses before it acts. Null only where the control is not a Tab stop and
  // is reached by a named key instead -- a card in the hand, the pit crew, the
  // way out of the countdown -- in which case `key` is what the parity table
  // reads.
  property Item stop: null

  // The control's name, in the words already on it or already spoken by it.
  // The harness matches `--do click:<text>` against this, case-insensitively
  // and by substring, so a drive script reads as English.
  property string label: ""

  // What one click does, said the way the key does it.
  property string does: ""

  // The key or keys that do the same thing from the keyboard. This is the
  // parity column, and it may not be empty: a click target with no key behind
  // it is a mouse-only path, which the design forbids as squarely as the
  // keyboard-only ones this piece exists to remove. `--print-controls` fails
  // the screen when it finds one.
  property string key: ""

  // The duck-type the harness's walk finds. QML has no `instanceof` for a
  // component here, and the walk must not have to know this file's name.
  readonly property bool isClickTarget: true

  // Is the pointer over this control? Callers paint their hover state off this
  // rather than off `containsMouse`, so a disabled target never lights.
  readonly property bool hovered: hit.containsMouse && hit.enabled

  signal acted()

  anchors.fill: parent
  hoverEnabled: true
  // Left only. A right-click is the desktop's, not the game's, and a middle
  // click on a child's trackpad is usually an accident.
  acceptedButtons: Qt.LeftButton
  cursorShape: Qt.PointingHandCursor

  onClicked: {
    if (hit.stop)
      hit.stop.forceActiveFocus(Qt.MouseFocusReason)
    hit.acted()
  }
}
