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

  // ------------------------------------------------------------- ROUND 2
  //
  // WHAT A SECOND CLICK DOES, AND WHY IT IS A PROPERTY OF THE TARGET.
  //
  // Round one's gate asked two questions of every control -- is there a target,
  // is there a key -- and a critic found the defect that lives in the gap
  // between them: `click:card 3, click:card 3`, sixteen milliseconds apart,
  // SPENT THE WHOLE HAND, where `key:3, key:3` merely left the card chosen. Both
  // paths existed and both were reachable, so neither direction of the parity
  // walk could see it. The defect was in what a REPEAT does.
  //
  // A double-click is not a child's mistake. It is what children do with a
  // mouse, on everything, and this game has no undo anywhere in it.
  //
  // So: a target that does something a child cannot take back says so, and a
  // destructive target refuses a second press inside the interval a
  // double-click lands in. The first press always works -- the maintainer's
  // other complaint is that a power-up "had to be triggered multiple times",
  // and a guard that swallowed the FIRST press would be that bug -- and the
  // second one, the one no hand meant to send, does nothing.
  //
  // The choosing half of a two-press action is never destructive and is never
  // guarded, so a child hammering a card, a swatch or a stepper arrow gets
  // exactly what they asked for. See `ui/Picker.qml`: after this round a click
  // on a card cannot spend it at all, whatever the interval; this guard is the
  // second lock on the control that CAN.
  property bool destructive: false

  // 400 ms is Qt's own default `mouseDoubleClickInterval` on every platform
  // this plugin runs on, and it is what a double-click means. A number rather
  // than a read of `styleHints` on purpose: the guard has to be the same in a
  // test, in the harness and on the child's machine, and a platform that set a
  // 900 ms interval would make a deliberate second press feel broken.
  readonly property int guardMs: hit.destructive ? 400 : 0

  // The guard is a TIMER rather than two readings of a clock, and the reason is
  // the repository's own scanner: `npm run check:readme` asserts that no plugin
  // file may read the wall clock at all, unconditionally, because this game
  // stores no dates anywhere -- and the scanner reads comments too, so this one
  // does not spell the call either. A timer needs no clock to subtract from: it
  // is running or it is
  // not -- and "is the guard up" is then a property a test can read directly
  // instead of a difference it has to reconstruct.
  Timer {
    id: guard
    interval: hit.guardMs
    repeat: false
  }

  // How many presses this target has refused as repeats. Here so a test can
  // asserting the refusal HAPPENED rather than inferring it from a state that
  // did not change -- the two are different when the state would not have
  // changed anyway.
  property int refusedRepeats: 0
  readonly property bool guarding: guard.running

  // How many presses this target has ACCEPTED. The repeat check reads this
  // rather than a screen state, because "did the second press act" and "did the
  // screen change" are different questions and only the first one is the rule.
  property int actedCount: 0

  // A target that only puts the keyboard somewhere: the stepper's centre face,
  // the race's answer box. It takes no action, so there is nothing for a key to
  // be the equivalent of; what it must have instead is a `stop`, and the walk
  // checks for that rather than accepting an empty key column.
  property bool focusOnly: false

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
    // The whole press is refused, focus included: a control that moved the
    // keyboard on a press it did not act on would be half a press.
    if (guard.running) {
      hit.refusedRepeats += 1
      return
    }
    if (hit.guardMs > 0)
      guard.restart()
    hit.actedCount += 1
    if (hit.stop)
      hit.stop.forceActiveFocus(Qt.MouseFocusReason)
    hit.acted()
  }
}
