pragma Singleton
import QtQuick

// PIECE M ROUND 4. THE REPEAT GUARD BELONGS TO THE ACTION, NOT TO THE CONTROL.
//
// Round two put a 400 ms guard on `ui/parts/Clickable.qml`: a destructive target
// refused a second PRESS inside the interval a double-click lands in. Round
// three found it one-sided -- consulted only by the click handler -- and patched
// the one place that hurt by having `ui/Race.qml`'s Escape branch read
// `leaveHint.guarding`. Round three's own note said what the real fix was and
// deferred it. A critic then measured what the deferral cost, and it was four
// separate defects with one cause:
//
//   D1  three clicks on `H  PIT CREW` burned three of the child's questions.
//       The control was not marked destructive, so it had no guard at all.
//   D2  a click on the hand panel's `ESC  BACK` chip, then Escape, LEFT THE
//       RACE. Two controls performing the same "back out" gesture, each with
//       its own guard, and the key with none.
//   D3  a double-click on that same chip put the card back and then CHOSE CARD
//       1, because the footer redraws as `1 2 3  CHOOSE A CARD` at the same
//       pixel. The second press landed on a different, unguarded control.
//   D4  Escape, then a click on the race's own ESC line 16 ms later, left the
//       race. The key armed nothing, because only the click handler armed.
//
// A guard that lives on a control can only ever refuse a press that arrives at
// THAT control, from THAT device. A child's second click arrives at a PIXEL,
// and their next press may come from either hand. So the guard lives here,
// once, and what it is keyed on is the ACTION:
//
//   `guards` on a click target, and the same list passed to `take()` by a key
//   handler, is the set of names this action belongs to. Taking an action
//   refuses it when any of its names is armed, and arms all of them.
//
// Two names, and both are earned by one of the defects above:
//
//   "escape"      the back-out gesture, wherever it is performed from: the
//                 race's own `ESC` line, the hand panel's `ESC  BACK` chip, and
//                 the Escape key itself. One gesture, one guard, three routes.
//                 This is D2 and D4.
//   "handFooter"  the hand panel's footer, which REPLACES ITS OWN CHIPS under
//                 the pointer the instant one of them acts. Everything in it
//                 that changes the footer shares this, so the half of a
//                 double-click nobody meant to send cannot land on the chip
//                 that took the place of the one they pressed. This is D3, and
//                 it is the round-two walking-repeat defect one control to the
//                 left of where round two fixed it.
//
// WHAT IS DELIBERATELY NOT GUARDED, because the maintainer's other standing
// complaint is a power-up that had to be pressed several times. A control that
// merely CHOOSES -- a card, a paint swatch, a stepper arrow, the footer's
// `◀ ▶  RIVAL` -- declares no guard at all, so a child hammering it gets
// exactly what they asked for, every press. The guard is for the presses that
// cannot be taken back.
//
// ONE ARMED SET, NOT ONE TIMER PER ACTION. Only the most recent press can be
// the first half of a double-click, so "what is armed" is one list and one
// timer. 400 ms is Qt's own default `mouseDoubleClickInterval` and it is what a
// double-click means; a number rather than a read of `styleHints` on purpose,
// so the guard is the same in a test, in the harness and on the child's machine.
QtObject {
  id: actions

  readonly property int guardMs: 400

  // The names armed by the last press that took an action, or empty.
  property var armed: []

  // How many presses have been refused as repeats, and how many taken. Here so
  // a test can assert the refusal HAPPENED rather than infer it from a state
  // that did not change -- the two are different when the state would not have
  // changed anyway.
  property int refusedRepeats: 0
  property int takenCount: 0

  // A timer rather than two readings of a clock: `npm run check:readme` forbids
  // a plugin file reading the wall clock at all, because this game stores no
  // dates anywhere. A timer needs no clock to subtract from, and "is the guard
  // up" is then a property a test reads instead of a difference it reconstructs.
  property Timer expiry: Timer {
    interval: actions.guardMs
    repeat: false
    onTriggered: actions.armed = []
  }

  /** Is any of these action names inside the double-click interval of a press? */
  function guarding(names) {
    if (!names || names.length === 0 || !actions.expiry.running)
      return false
    for (var i = 0; i < names.length; i++)
      if (actions.armed.indexOf(String(names[i])) >= 0)
        return true
    return false
  }

  /**
   * Take the action these names belong to.
   *
   * False means this press is the tail of a press already taken and the caller
   * must do nothing at all -- focus included, because a control that moved the
   * keyboard on a press it did not act on would be half a press. An action with
   * no names is never guarded and always taken, which is every choosing control
   * in the game.
   */
  function take(names) {
    if (actions.guarding(names)) {
      actions.refusedRepeats += 1
      return false
    }
    if (names && names.length > 0) {
      var copy = []
      for (var i = 0; i < names.length; i++)
        copy.push(String(names[i]))
      actions.armed = copy
      actions.expiry.restart()
    }
    actions.takenCount += 1
    return true
  }

  /**
   * Put the guard down. For a test that drives the same control twice from a
   * clean world: the guard is real state and it outlives a screen being rebuilt,
   * which is the point of it and is also how it leaks between two runs that are
   * meant to be comparable.
   */
  function clear() {
    actions.expiry.stop()
    actions.armed = []
  }
}
