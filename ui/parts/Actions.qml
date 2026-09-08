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
// PIECE F ROUND 7. Design v4.1 took the back-out gesture away -- Escape only
// ever leaves, and there is no `ESC  BACK` chip -- so the two names now mean:
//
//   "escape"      leaving the race, from the Escape key or the race's own
//                 `ESC  LEAVE` line.
//   "handFooter"  firing the highlighted card, from the space bar or the hand
//                 panel's `SPACE  USE IT` line. The panel goes with the hand it
//                 spent, so the second half of a double-click lands on whatever
//                 the race draws there next; the name is what refuses it.
//
// The history above is kept because the routes it describes -- click then
// key, key then click, click then click -- are still the three the guard is
// for, and `tests/qml/tst_mouse_parity.qml` still drives all three per name.
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
//
// =========================================================================
// ROUND 5 -- THE GUARD IS CROSS-ROUTE ONLY. KEY -> KEY IS NOT GUARDED, AND
// ROUND 4 SHOULD NEVER HAVE MADE IT SO.
// =========================================================================
//
// Round four made `take()` blind to the route, so a second Escape 16 ms after
// the first was refused. Its argument was that the race's `ESC` line means BACK
// with a card chosen and LEAVE without, so a child tapping Escape twice cannot
// have meant the second meaning.
//
// `docs/design.md:89` (v4.1) has already deleted that overload: "Enter is only
// ever the answer key, **Escape only ever leaves the race**." The ambiguity the
// lockout defends against is not a state this game is supposed to have. So the
// lockout was protecting a phantom, and it was charging a real price for it: a
// critic measured Escape refused for ~300 ms with NOTHING drawn, said or played
// to explain it -- and `grep` over `ui/` finds no renderer for `refusedRepeats`
// or `guarding` anywhere, so a refused press is indistinguishable from a broken
// one. The maintainer's standing complaint is a control he had to press several
// times; a build that deliberately ignores the second press earns that sentence
// a third time. It was also applied on two screens of six, so the rule it stated
// was not even the rule the game had.
//
// WHAT A ROUTE IS, AND WHY THE OTHER THREE PAIRS STAY GUARDED. The hazard is a
// SINGLE GESTURE that produces two presses. There are three of those and this
// keeps all three:
//
//   click -> click   the second half of a double-click, landing on the control
//                    that took the place of the one that was pressed. Round
//                    two's defect and round four's D1 and D3.
//   click -> key     a pixel and a key arriving on the same action inside one
//                    interval. Round four's D2.
//   key -> click     the same, the other way round. Round four's D4, and the
//                    mirror a critic drove in round five (an Escape, then a
//                    click on the hand footer 16 ms later, choosing card 1).
//
// The fourth pair is not a gesture. A child pressing the SAME KEY twice pressed
// it twice, on purpose, with two deliberate movements of one finger; there is no
// pixel under them that changed and no second control to walk onto. Round three
// wrote that rule down where it was made and round four reversed it without a
// measurement behind the reversal. `tests/qml/tst_race_keys.qml` -- the keyboard
// piece's own spec -- says a second Escape leaves the race, and it says so again.
QtObject {
  id: actions

  readonly property int guardMs: 400

  // The names armed by the last press that took an action, or empty.
  property var armed: []

  // WHICH HAND ARMED THEM: "click", "key", or "" when nothing is armed. This is
  // the only thing the guard needs to know about a route, and it is the whole of
  // the round-five change: a press is refused when its names are armed AND the
  // pair is not key-after-key.
  property string armedRoute: ""

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
    onTriggered: {
      actions.armed = []
      actions.armedRoute = ""
    }
  }

  /**
   * Is any of these action names inside the double-click interval of a press
   * that came by a DIFFERENT route -- or by the pointer, twice?
   *
   * `route` is "click" or "key". Anything else is read as "click", which is the
   * guarded reading: a caller that forgets to say gets the stricter answer
   * rather than the quieter one.
   */
  function guarding(names, route) {
    if (!names || names.length === 0 || !actions.expiry.running)
      return false
    // KEY AFTER KEY IS NOT A REPEAT. See the block at the top of this file: two
    // presses of one key are two presses, and the design's Escape has one
    // meaning to press twice.
    if (String(route) === "key" && actions.armedRoute === "key")
      return false
    for (var i = 0; i < names.length; i++)
      if (actions.armed.indexOf(String(names[i])) >= 0)
        return true
    return false
  }

  /**
   * Take the action these names belong to, from this route.
   *
   * False means this press is the tail of a press already taken and the caller
   * must do nothing at all -- focus included, because a control that moved the
   * keyboard on a press it did not act on would be half a press. An action with
   * no names is never guarded and always taken, which is every choosing control
   * in the game.
   *
   * A press that is TAKEN always arms, whichever route it came by, because the
   * next press may come from the other hand: it is the arming that makes
   * key -> click refusable at all.
   */
  function take(names, route) {
    if (actions.guarding(names, route)) {
      actions.refusedRepeats += 1
      return false
    }
    actions.arm(names, route)
    actions.takenCount += 1
    return true
  }

  /**
   * ROUND 5. Record that a press MOVED WHAT IS UNDER THE CHILD'S HAND, without
   * asking permission first.
   *
   * A choosing press -- a card, a swatch, `1 2 3  CHOOSE A CARD` -- may never be
   * refused: a child hammering it means it every time, and that is the
   * maintainer's other standing complaint. But choosing a card REPLACES THE
   * FOOTER at the pixel that was pressed, and the chip that takes its place
   * spends the whole hand, so the press has to arm even though it does not ask.
   *
   * `take` is "may I, and then I did"; this is the second half on its own. A
   * press that ignored `take`'s answer and acted anyway would say the same thing
   * with a lie in the middle of it.
   */
  function arm(names, route) {
    if (!names || names.length === 0)
      return
    var copy = []
    for (var i = 0; i < names.length; i++)
      copy.push(String(names[i]))
    actions.armed = copy
    actions.armedRoute = (String(route) === "key") ? "key" : "click"
    actions.expiry.restart()
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
    actions.armedRoute = ""
  }
}
