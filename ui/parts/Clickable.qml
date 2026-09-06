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

  // ------------------------------------------------------------- ROUND 4
  //
  // THE KEY COLUMN IS CHECKED FOR BEING *TRUE*, AND THIS IS WHAT MAKES THAT
  // POSSIBLE.
  //
  // A critic set `ui/parts/ActionButton.qml`'s `key: "Enter or Space"` to
  // `key: "Escape"` -- so READY UP, LEAVE, RACE AGAIN, GARAGE, BACK and all
  // three RESETs declared that Escape was the key that does what a click does
  // -- and the whole suite stayed green and `--print-controls` went on printing
  // `parity verdict PASS`. The column was checked for being NON-EMPTY (test_01)
  // and for naming keys a keyboard has (test_05, `dev/KeyHints.js`). Nothing
  // anywhere checked that the named key DID THE NAMED THING. That is the
  // central promise of this piece -- a click does what its key does -- and it
  // was carried by a string nobody verified.
  //
  // `test_29` now crosses the two drive routes over EVERY control: it clicks
  // the target and photographs the screen, re-enters the same state, presses
  // the keys from the keyboard, and requires the two states to be identical.
  // `keyRoute` is what makes that mechanical rather than hand-written.
  //
  //   [] (the default)  press the FIRST key `key` names, once. True of almost
  //                     every control in this game: a button, a settings row, a
  //                     stepper arrow, a card, a printed key hint.
  //
  //   a list of names   the presses that reach this control's own state, in
  //                     order, in the vocabulary `dev/KeyHints.js` parses and
  //                     `dev/Pointer.qml` posts: ["right"], ["right", "enter"],
  //                     eight "right"s for the eighth paint.
  //
  // The second form is not an escape hatch, it is the honest shape of a control
  // that PICKS a member of a set the keys STEP through. A click on the eighth
  // paint swatch is one press; the keys reach that same swatch in eight, and
  // the check presses eight and then demands the same screen. `key` goes on
  // saying what a child reads -- "Left, Right" -- and this says what a machine
  // presses, so neither has to lie to satisfy the other.
  //
  // `null` is "not declared": the default route above. A declared EMPTY list
  // is a route of no presses at all -- the swatch that is already painted, the
  // answer that is already armed -- and the two are different claims, so they
  // are different values.
  property var keyRoute: null

  // A control whose key route cannot be walked, and WHY, in words that go in
  // the parity table rather than in a report. Non-empty is a declared gap:
  // `test_29` counts them and prints them, and the harness's click table shows
  // the reason in the key column, so a hole is visible on the evidence a reader
  // is handed rather than absent from it.
  property string keyGap: ""

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

  // ------------------------------------------------------------- ROUND 4
  //
  // THE GUARD IS NOT HERE ANY MORE, AND THAT IS THE FIX.
  //
  // Round two's guard was a `Timer` on this file, keyed on nothing but this
  // target: a second press was refused when it arrived at THIS control, from
  // THE POINTER. A critic measured what that misses, and it was four defects
  // with one cause -- a control the child cannot press twice is not the same
  // thing as an ACTION the child cannot do twice, and the second half of a
  // double-click lands on a pixel rather than on a name. See the whole story in
  // `ui/parts/Actions.qml`.
  //
  // `guards` names the action this target performs. Two controls that perform
  // the same one share a name and therefore share a guard; a KEY handler that
  // performs it passes the same names to `Actions.take` and is refused by the
  // same press. A destructive target with no name is a guard nobody set, and
  // `test_30` fails the build on one.
  property var guards: []

  // How many presses this target has refused as repeats. Here so a test can
  // assert the refusal HAPPENED rather than infer it from a state that did not
  // change -- the two are different when the state would not have changed
  // anyway. The count is per target; the guard it comes from is shared.
  property int refusedRepeats: 0
  readonly property bool guarding: Actions.guarding(hit.guards, "click")

  // How many presses this target has ACCEPTED. The repeat check reads this
  // rather than a screen state, because "did the second press act" and "did the
  // screen change" are different questions and only the first one is the rule.
  property int actedCount: 0

  // A target that only puts the keyboard somewhere: the stepper's centre face,
  // the race's answer box. It takes no action, so there is nothing for a key to
  // be the equivalent of; what it must have instead is a `stop`, and the walk
  // checks for that rather than accepting an empty key column.
  property bool focusOnly: false

  // ------------------------------------------------------------- ROUND 3
  //
  // A BARRIER: A TARGET THAT EXISTS TO SWALLOW A PRESS.
  //
  // The third kind, and it is not a control at all. `ui/parts/Confirm.qml` is
  // the one modal in the game, and what makes a modal modal is that it consumes
  // the pointer over its WHOLE extent -- not only over the sheet, and not only
  // by whatever the screen behind happens to have done about switching itself
  // off. Round two left that to the caller: `ui/Settings.qml` disabled its own
  // page, which worked, and then disabled it for 400 ms LONGER than the
  // question was up, which took the keyboard with it. A modal's own rule
  // belongs to the modal.
  //
  // A barrier takes the press and stops. It does not act, it does not move the
  // keyboard, it never lights under the pointer, and it does not offer the hand
  // a pointing finger. It is not a path to anything, so the parity walk does not
  // ask it for a key or a stop -- but it IS printed in the click table, with
  // `barrier` in the kind column, because a thing that eats presses must be
  // enumerated somewhere a reader can find it.
  property bool barrier: false

  // The duck-type the harness's walk finds. QML has no `instanceof` for a
  // component here, and the walk must not have to know this file's name.
  readonly property bool isClickTarget: true

  // Is the pointer over this control? Callers paint their hover state off this
  // rather than off `containsMouse`, so a disabled target never lights. A
  // barrier is not a control and never lights: the child is being told that the
  // question in front of it is the only thing on the screen, and a scrim that
  // lit up under the pointer would be saying the opposite.
  readonly property bool hovered: hit.containsMouse && hit.enabled && !hit.barrier

  signal acted()

  anchors.fill: parent
  // ROUND 4 -- A BARRIER EATS PRESSES, AND IT MAY NOT EAT THE POINTER.
  //
  // `ui/parts/Confirm.qml`'s extent outlives the question by one double-click
  // interval, so the second half of a double-click on the question's own footer
  // cannot land on the row behind it. With `hoverEnabled` on, that extent also
  // swallowed HOVER over the whole window for those 400 ms: a critic measured a
  // settings row that hovers at rest reading `hovered = false` under a
  // stationary pointer, with the scrim and the sheet already invisible and
  // nothing on the screen to explain it. Four tenths of a second of dead
  // pointer over 1920 x 1080 is a smaller version of the complaint this whole
  // piece exists to answer. A barrier takes presses; nothing else.
  hoverEnabled: !hit.barrier
  // Left only. A right-click is the desktop's, not the game's, and a middle
  // click on a child's trackpad is usually an accident.
  acceptedButtons: Qt.LeftButton
  cursorShape: hit.barrier ? Qt.ArrowCursor : Qt.PointingHandCursor

  onClicked: {
    // The press dies here. A barrier is the modal saying that nothing behind it
    // is reachable, so it neither acts nor moves the keyboard, and it does not
    // count the press as a refused repeat either -- the press was not a repeat
    // of anything this target did.
    if (hit.barrier)
      return
    // The whole press is refused, focus included: a control that moved the
    // keyboard on a press it did not act on would be half a press. The guard
    // that refuses it belongs to the ACTION, so this is the same refusal a key
    // handler performing the same action gets, and the same one the control
    // that REPLACES this one under the pointer gets.
    if (!Actions.take(hit.guards, "click")) {
      hit.refusedRepeats += 1
      return
    }
    hit.actedCount += 1
    if (hit.stop)
      hit.stop.forceActiveFocus(Qt.MouseFocusReason)
    hit.acted()
  }
}
