import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts"
import "../../dev"
import "../../dev/KeyHints.js" as KeyHints
import "../../engine/engine.mjs" as Engine

// PIECE M. THE MOUSE, WITH REAL MOUSE EVENTS, AND THE PARITY AS A GATE.
//
// `tst_garage_keyboard.qml` opens with "no mouse event is sent anywhere in this
// file, and there is no mouse handler in the garage to send one to". That was
// the whole defect: the maintainer said twice that clicking did nothing, and
// `docs/open-questions.md` §5.1 found the cause -- no screen under `ui/` had a
// `MouseArea`, a `TapHandler` or a `HoverHandler` anywhere. This file is the
// other half of that sentence. Every assertion below is made by moving and
// clicking a real pointer through `mouseClick` and `mouseMove`, which post the
// same events a hand on a mouse posts.
//
// Two kinds of test, and the second kind is the one that matters most:
//
//   the drives     click a control, assert the state moved; press the key that
//                  does the same thing, assert it moved the same way. A pair of
//                  paths that merely agree today is a pair that disagrees later,
//                  so these assert the SAME observable after each.
//   the walk       walk the item tree and hold the whole screen to the parity
//                  rule, in both directions, WITHOUT A LIST OF CONTROLS IN THIS
//                  FILE. A hand-written list is exactly what cannot catch the
//                  defect this piece exists for: the failure was never "this
//                  control is wrong", it was "nobody thought about this control
//                  at all", and a list is written by the same person who did not
//                  think about it. So the walk generates its own subject from
//                  the live tree, three ways -- click targets, items whose
//                  `Accessible.role` declares them controls, and the screen's own
//                  `stops` array -- and a control added tomorrow is tested
//                  tomorrow without anybody adding a line here.
//
// Run it:
//   qmltestrunner -platform offscreen -import dev/imports -input tests/qml
Item {
  id: root
  width: 1920
  height: 1080

  MemoryStore { id: memory }

  // Somewhere for the keyboard to stand that is not a control, so a pixel sweep
  // can ask what HOVER alone draws. `ui/parts/ActionButton.qml` suppresses hover
  // on a control that already has focus -- the focus picture wins, which is the
  // rule -- so a sweep run with the keyboard parked on READY UP would report
  // that READY UP does not light. `dev/Harness.qml --focus -1` does the same
  // thing for the same reason.
  Item {
    id: focusPark
    width: 0
    height: 0
    activeFocusOnTab: false
  }

  // ROUND 4 -- ONE PIXEL, AND WHY IT SAVES HALF A MINUTE.
  //
  // `settleFrame()` renders synchronously to force a polish pass, because a
  // click measured on the same turn as a state change goes to where the control
  // WAS. It did that by grabbing the whole 1920 x 1080 root, which rasterises
  // two million pixels every time -- and `test_29` needs a settle before every
  // one of its two hundred and forty drives. The polish pass is what is wanted;
  // the pixels are not. Grabbing this instead runs the same synchronous render
  // and hands back four bytes.
  Item {
    id: onePixel
    width: 1
    height: 1
  }

  // ONE FOCUS RING, IN ITS TWO STATES, OVER THE SAME PIXELS.
  //
  // `test_21` reads hover and focus off a real control, which is the right
  // subject for the claim -- and a control draws more than its ring, so a
  // mutation that made the RING alone stop telling the two apart was still
  // caught by the button's own fill. That is a pass for the wrong reason: the
  // ring is the affordance every control in this game shares, and it has to
  // carry the distinction on its own.
  //
  // So the ring is also photographed by itself, in one place, switched between
  // its two states with nothing else on the screen changing. Nothing here is
  // for the test's convenience: it is `ui/parts/FocusRing.qml` with `hover`
  // true and `hover` false, which is exactly the pair of pictures the component
  // exists to draw.
  property bool ringHover: false

  Item {
    id: ringLab
    anchors.fill: parent
    visible: root.showing === "rings"

    Rectangle {
      anchors.fill: parent
      color: Theme.panel
    }

    Item {
      x: 300
      y: 300
      width: 400
      height: 120

      Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.panelSunken
      }

      FocusRing {
        on: true
        hover: root.ringHover
      }
    }
  }

  // Every screen that has a control on it, alive at once. They are laid out on
  // top of each other and only one is visible at a time: a click is delivered by
  // position, so two visible screens would race for the same pixel.
  property string showing: "garage"

  Garage {
    id: garage
    anchors.fill: parent
    visible: root.showing === "garage"
  }

  Settings {
    id: settings
    anchors.fill: parent
    visible: root.showing === "settings"
  }

  Results {
    id: results
    anchors.fill: parent
    visible: root.showing === "results"
  }

  Picker {
    id: picker
    anchors.fill: parent
    visible: root.showing === "picker"
  }

  Countdown {
    id: countdown
    anchors.fill: parent
    visible: root.showing === "countdown"
  }

  // ROUND 3 -- THE SCREEN THE CHILD ACTUALLY PLAYS ON.
  //
  // A critic counted it: this file was the only one in the repository that
  // posted a mouse event at all, and it never instantiated `Race`. The busiest
  // screen in the game -- the pit crew, the answer box, the in-race hand, the
  // aim tags, and the one control in the whole game whose MEANING changes under
  // the pointer -- was covered by the static walk and by nothing that clicks.
  //
  // It is also the only screen that closes the hole in the repeat sweep, and
  // that is not a coincidence. Every other destructive control in this game
  // STOPS EXISTING when it acts -- the picker's `⏎  USE IT` goes with the hand
  // it spent, the question's `⏎  ANSWER` goes with the question -- so the
  // second press of a double-click never reaches the control that refused it
  // and the guard's refusal branch was never once entered by this file.
  // `ui/Race.qml`'s `ESC` hint stays exactly where it is and changes what it
  // MEANS: `BACK` while a card is chosen, `LEAVE` otherwise. It is the one
  // destructive control a double-click can land on twice, and so it is the one
  // that can be asked what the second press did.
  //
  // The rivals are frozen (`rivals: null`, the same set-up
  // `tests/qml/tst_race_keys.qml` uses and for the same reason): an AI kart's
  // Wrench is a two-second field lock, and a lock arriving mid-sweep would make
  // these cases say something about the rivals rather than about the pointer.
  Race {
    id: race
    anchors.fill: parent
    visible: root.showing === "race"
    mode: "grandPrix"
    preset: "1-12"
    seed: 42
  }

  property int raceLeaves: 0
  Connections {
    target: race
    function onLeaveRequested() { root.raceLeaves += 1 }
  }

  property int countdownAborts: 0
  Connections {
    target: countdown
    function onAbortRequested() { root.countdownAborts += 1 }
  }

  property int raceRequests: 0
  property int leaveRequests: 0
  Connections {
    target: garage
    function onRaceRequested() { root.raceRequests += 1 }
    function onLeaveRequested() { root.leaveRequests += 1 }
  }

  property int againRequests: 0
  property int garageRequests: 0
  Connections {
    target: results
    function onRaceAgainRequested() { root.againRequests += 1 }
    function onGarageRequested() { root.garageRequests += 1 }
  }

  property int cardsUsed: 0
  Connections {
    target: picker
    function onCardUsed() { root.cardsUsed += 1 }
  }

  TestCase {
    id: suite
    name: "MouseParity"
    when: windowShown

    function applyTheme() {
      Theme.background = Color.background
      Theme.foreground = Color.foreground
      Theme.accent = Color.accent
      Theme.urgent = Color.urgent
      Theme.muted = Color.muted
      Theme.menuBackground = Color.menu.background
      Theme.menuText = Color.menu.text
      Theme.menuBorder = Color.menu.border
      Theme.fontFamily = Style.font.family
      Theme.resolvedFontFamily = Style.font.resolvedFamily
      Theme.fontBaseSize = Style.font.baseSize
      Theme.shellCornerRadius = Style.cornerRadius
      Theme.spacingScale = Style.spacing.scale
    }

    function initTestCase() {
      applyTheme()
      Store.backend = memory
    }

    function init() {
      memory.reset()
      Store.reload()
      // The repeat guard is shared and outlives a screen, so a case that armed
      // it would eat the first press of the next one.
      Actions.clear()
      // `test_29` stops the race's clock to compare two states; every other case
      // wants the real one back.
      race.externalClock = false
      root.showing = "garage"
      root.raceRequests = 0
      root.leaveRequests = 0
      root.againRequests = 0
      root.garageRequests = 0
      root.cardsUsed = 0
      root.countdownAborts = 0
      // The picker keeps two pieces of state a host would normally clear for
      // it. `slamBorn` is the one that bites: `confirm()` sets it to `fxNow`,
      // which is zero on a panel standing on its own with no race driving its
      // clock, so `slamming` stays true for ever and every later click on a
      // card is refused as a click on a card that is already flying off. In the
      // game the clock advances and the beat ends; here nothing advances it.
      suite.resetScreens()
      // The pointer starts in the top-left corner, off every control on every
      // screen in this game: each keeps a page margin and a title band above
      // anything pressable. A pointer left on a control from the previous test
      // is a hover state leaking between tests.
      mouseMove(root, 0, 0)
    }

    /**
     * Put every screen back to the state it opens in.
     *
     * The picker keeps two pieces of state a host would normally clear for it.
     * `slamBorn` is the one that bites: `confirm()` sets it to `fxNow`, which is
     * zero on a panel standing on its own with no race driving its clock, so
     * `slamming` stays true for ever and every later click on a card is refused
     * as a click on a card that is already flying off. In the game the clock
     * advances and the beat ends; here nothing advances it.
     *
     * ROUND 2 adds the settings screen's open question, for the same class of
     * reason and a sharper edge: a state list that DRIVES a screen into a state
     * leaves it there, and an open reset question switches the whole settings
     * page off underneath it -- so a question left open by one state made every
     * control on that screen unclickable for the next.
     */
    function resetScreens() {
      picker.clearChoice()
      picker.slamBorn = -1e9
      // ROUND 4, and the same class again. `clearChoice()` raises the one-beat
      // line that says a card went back -- `CARD PUT BACK · ALL THREE STILL
      // YOURS` -- and a wall-clock Timer takes it down. In the game that beat
      // belongs to the child's own press; in a state list it is a leftover of
      // the reset, and a comparison of two states photographed milliseconds
      // apart cannot be about a line that is on its way out. Put down here,
      // after the clear that raised it, rather than excluded from the reading.
      picker.letGoShowing = false
      settings.pending = ""
      // ROUND 3, and it is the same class of leak as the two above. The one
      // question in the game goes on swallowing POINTER presses over its own
      // extent for one double-click interval after it closes -- that is what
      // stops the second half of a double-click on `⏎  ANSWER` landing on the
      // row underneath. A case that answered a question therefore leaves that
      // window open into the next case, where it eats the first click. Waited
      // out rather than reached into: the window is real and the next case has
      // to start after it, exactly as a child's second click does.
      suite.waitOutTheModalTail()

    }

    /**
     * Is the question's extent still swallowing presses? Read off the tree
     * rather than off a property of the screen, and deliberately NOT through
     * `usable()`: the settings screen itself is usually hidden at this point,
     * and what is being asked about is the question's own lifetime, not the
     * screen's.
     */
    property var theBarrier: null
    function modalTailRunning() {
      // ROUND 4 -- FOUND ONCE, NOT ON EVERY CALL. This runs from `resetScreens`,
      // which runs from every `enter`, which `test_29` calls twice per control:
      // a full walk of the settings tree each time was a fifth of that case's
      // clock. The barrier is one item and it does not move.
      if (suite.theBarrier === null) {
        var targets = suite.clickTargetsIn(settings)
        for (var i = 0; i < targets.length; i++) {
          if (targets[i].barrier === true)
            suite.theBarrier = targets[i]
        }
      }
      // The question publishes its own lifetime as `consuming`. Read from there
      // rather than from the barrier's `visible`, which is QML's EFFECTIVE
      // visibility and therefore false whenever the settings screen is not the
      // screen on show -- which, in `init()`, it never is.
      return suite.theBarrier !== null && suite.theBarrier.parent
             && suite.theBarrier.parent.consuming === true
    }

    /**
     * Twelve correct answers in a row deals a hand of three, which is the
     * design's rule and the only way into the state this file needs. Typed, in
     * real key events, exactly as `tests/qml/tst_race_keys.qml` does it -- the
     * hand cannot be poked into place without the test stopping being about
     * what a child can reach.
     */
    function dealRaceHand() {
      var guard = 0
      while (race.hand.length === 0 && guard < 40) {
        var answer = String(Engine.factAnswer(race.human.currentFact))
        for (var i = 0; i < answer.length; i++)
          keyClick(Qt.Key_0 + Number(answer.charAt(i)))
        keyClick(Qt.Key_Return)
        guard += 1
      }
      compare(race.hand.length, 3, "a hand of three is held")
    }

    function waitOutTheModalTail() {
      var guard = 0
      while (guard < 60 && suite.modalTailRunning()) {
        wait(16)
        guard += 1
      }
      verify(!suite.modalTailRunning(),
             "the question's extent is still swallowing presses a second after the"
             + " question closed; the tail is not a double-click interval any more")
    }

    // ------------------------------------------------------------------
    // The walk. Nothing below names a control.
    // ------------------------------------------------------------------

    function visit(node, seen) {
      if (!node)
        return
      seen.push(node)
      var kids = node.children
      if (!kids)
        return
      for (var i = 0; i < kids.length; i++)
        suite.visit(kids[i], seen)
    }

    function itemsUnder(node) {
      var seen = []
      suite.visit(node, seen)
      return seen
    }

    /** Drawn at all: an invisible ancestor hides a visible child. */
    function drawn(item, screen) {
      var node = item
      while (node && node !== screen.parent) {
        if (!node.visible || node.opacity <= 0)
          return false
        node = node.parent
      }
      return true
    }

    /**
     * Switched on at all. `item.enabled` reads the item's OWN flag, not the
     * effective one, so a row under `ui/Settings.qml`'s `enabled:
     * !settings.confirming` page went on reporting `enabled: true` while the
     * reset question was open and nothing could click it. Round one's tables
     * were wrong about that in both the harness and here.
     */
    function switchedOn(item, screen) {
      var node = item
      while (node && node !== screen.parent) {
        if (!node.enabled)
          return false
        node = node.parent
      }
      return true
    }

    /** Drawn, and switched on: a path a child could actually take right now. */
    function usable(item, screen) {
      return suite.drawn(item, screen) && suite.switchedOn(item, screen)
    }

    /**
     * THE BOX A HOVER STATE IS ALLOWED TO PAINT IN: the whole of the control,
     * which is every click target that reaches the same focus stop.
     *
     * A stepper is one stop with two arrows and an inert face on it, so its
     * three targets are one control 228 px wide and the 48 px arrow lighting all
     * of it is the control saying "this is me" -- the arrow's own fill is what
     * says which half you are about to press. A settings row is one stop with a
     * 612 px row target and a 101 px CHANGE chip on it, and the chip lights the
     * row for the same reason. A target with no stop -- a card, a printed key
     * hint -- is its own control and answers for its own box.
     *
     * Defined off the stop rather than off `Accessible.role` because the role is
     * on the CHIP in `ui/parts/SettingRow.qml` while the control a child sees is
     * the row; the stop is what both targets agree on.
     */
    function controlBoxOf(hit, screen, pad) {
      if (!hit.stop)
        return suite.boxAround(hit, pad)
      var box = suite.boxAround(hit, pad)
      var targets = suite.clickTargetsIn(screen)
      for (var i = 0; i < targets.length; i++) {
        if (targets[i].stop !== hit.stop || !suite.usable(targets[i], screen))
          continue
        var other = suite.boxAround(targets[i], pad)
        box = { "x": Math.min(box.x, other.x), "y": Math.min(box.y, other.y),
                "right": Math.max(box.right, other.right),
                "bottom": Math.max(box.bottom, other.bottom) }
      }
      return box
    }

    /**
     * The first click target at or above this item.
     *
     * ROUND 3. A barrier is not one: `ui/parts/Confirm.qml`'s extent is an
     * ancestor of every word on the question's sheet, and if it counted here a
     * dead key hint inside the one dialog in the game would report a click
     * target for ever.
     */
    function clickTargetOver(item, screen) {
      var node = item
      while (node) {
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) {
          if (kids[i].isClickTarget === true && kids[i].barrier !== true
              && suite.usable(kids[i], screen))
            return kids[i]
        }
        node = node.parent
      }
      return null
    }

    /**
     * Connect `bump` to `acted()` on every destructive target under `screen`
     * that is not already in `armed`, and remember it there.
     */
    function armDestructive(screen, armed, bump) {
      var targets = suite.clickTargetsIn(screen)
      for (var i = 0; i < targets.length; i++) {
        if (!targets[i].destructive || armed.indexOf(targets[i]) >= 0)
          continue
        targets[i].acted.connect(bump)
        armed.push(targets[i])
      }
    }

    function clickTargetsIn(screen) {
      var found = []
      var all = suite.itemsUnder(screen)
      for (var i = 0; i < all.length; i++) {
        if (all[i].isClickTarget === true)
          found.push(all[i])
      }
      return found
    }

    function roleOf(item) {
      try {
        var role = item.Accessible.role
        return role === undefined ? -1 : role
      } catch (error) {
        return -1
      }
    }

    function declaredControlsIn(screen) {
      var found = []
      var all = suite.itemsUnder(screen)
      for (var i = 0; i < all.length; i++) {
        var role = suite.roleOf(all[i])
        if (role === Accessible.Button || role === Accessible.SpinBox
            || role === Accessible.ComboBox || role === Accessible.CheckBox
            || role === Accessible.RadioButton || role === Accessible.Slider)
          found.push(all[i])
      }
      return found
    }

    function hasClickTargetUnder(item, screen) {
      var targets = suite.clickTargetsIn(item)
      for (var i = 0; i < targets.length; i++) {
        if (targets[i].barrier !== true && suite.usable(targets[i], screen))
          return true
      }
      return false
    }

    // ------------------------------------------------------------------
    // THE STATES, NOT ONLY THE SCREENS.
    //
    // ROUND 2, and it is the same class of hole as the quarantined reset round
    // one named honestly: a control only reachable in a state the harness never
    // seeds is in no table at all. The picker's `⏎  USE IT` and `ESC  BACK`
    // exist only once a card is CHOSEN; the confirm sheet's three answers exist
    // only once a reset has been asked for. Every gate below therefore walks a
    // list of STATES, each one reached by driving the screen into it with the
    // mouse, and not a list of screens in whatever state they happen to open in.
    //
    // `prepare` is a drive, not a poke: it clicks its way in, so a state that
    // cannot be reached with a mouse cannot be walked either.
    function states() {
      return [{ "name": "Garage", "item": garage, "showing": "garage" },
              { "name": "Settings", "item": settings, "showing": "settings" },
              { "name": "Settings, reset asked", "item": settings, "showing": "settings",
                "prepare": "RESET SETTINGS" },
              { "name": "Results", "item": results, "showing": "results" },
              { "name": "Picker", "item": picker, "showing": "picker" },
              { "name": "Picker, card chosen", "item": picker, "showing": "picker",
                "prepare": "card 1" },
              { "name": "Picker, aiming", "item": picker, "showing": "picker",
                "prepare": "card 3" },
              { "name": "Countdown", "item": countdown, "showing": "countdown" },
              { "name": "Race", "item": race, "showing": "race" }]
    }

    /** Show the state's screen and drive it into the state. */
    function enter(state) {
      suite.resetScreens()
      root.showing = state.showing
      suite.settleFrame()
      if (state.prepare !== undefined) {
        suite.clickNamed(state.item, state.prepare)
        suite.settleFrame()
      }
      // ROUND 4. THE PRESSES THAT DROVE US HERE ARE NOT THE CHILD'S.
      //
      // The repeat guard is shared across controls now (`ui/parts/Actions.qml`)
      // and it is real state that outlives a screen. A state list that clicks
      // its way in therefore arms it, and the very next press -- the one the
      // case is actually about -- was refused as the tail of a click nobody in
      // the case made. Measured: three clicks on the picker's `⏎  USE` did
      // nothing at all, because the previous state's own drive had armed
      // `handFooter` less than 400 ms earlier.
      Actions.clear()
    }

    // DIRECTION ONE: nothing is reachable by click and not by key.
    //
    // Every click target names the key that does the same thing. A target with
    // an empty `key` is a mouse-only path, which the design forbids exactly as
    // squarely as the keyboard-only ones this piece removes.
    function test_01_no_click_target_is_a_mouse_only_path() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var targets = suite.clickTargetsIn(list[s].item)
        verify(targets.length > 0, list[s].name + " has no click target at all")
        for (var i = 0; i < targets.length; i++) {
          var hit = targets[i]
          if (!suite.usable(hit, list[s].item))
            continue
          // ROUND 3. A BARRIER IS NOT A PATH IN EITHER DIRECTION and is not
          // asked for a key: it exists to swallow a press, which is what makes
          // `ui/parts/Confirm.qml` modal. It is enumerated in the harness's
          // click table with `barrier` in the kind column.
          if (hit.barrier)
            continue
          checked += 1
          // ROUND 3. The one declared exception, and it was missing here while
          // the harness's own walk had carried it since round one: a FOCUS-ONLY
          // target takes no action at all -- the stepper's inert centre face,
          // the race's answer box -- so there is no key for it to be the
          // equivalent of. What it must have instead is a stop to put the
          // keyboard on. The race screen is the first state in this list that
          // has one, and adding the race is what found the gap.
          if (hit.focusOnly) {
            verify(hit.stop !== null,
                   list[s].name + ": \"" + hit.label + "\" takes no action and puts"
                   + " the keyboard nowhere, so a click on it does nothing at all")
            verify(String(hit.label).length > 0,
                   list[s].name + ": a click target with no label cannot be named in a"
                   + " parity table")
            continue
          }
          verify(String(hit.key).length > 0,
                 list[s].name + ": the click target \"" + hit.label
                 + "\" names no key, so it is reachable by mouse and not by keyboard")
          verify(String(hit.label).length > 0,
                 list[s].name + ": a click target with no label cannot be named in a"
                 + " parity table")
        }
      }
      verify(checked >= 20, "only " + checked + " live click targets were found across"
             + " five screens; the walk is not seeing the tree")
    }

    // DIRECTION ONE, THE OTHER HALF: the key column is a list of KEYS.
    //
    // ROUND 2, and a critic named it exactly: round one's gate asked only that
    // `Clickable.key` was non-empty, so `key: "banana"` passed -- on the column
    // that IS the claim of this direction. Every name in it is now parsed
    // against the same table `dev/Harness.qml --do key:<name>` posts events
    // from, so a key column can no longer name a key no keyboard has. It is not
    // proof that the key does the same thing; tests 10 to 17 and the harness's
    // drive pairs are that. It is the difference between a column of keys and a
    // column of prose.
    //
    // The exception is declared and narrow: a FOCUS-ONLY target takes no action
    // at all -- the stepper's inert centre face, the race's answer box -- so
    // there is no key for it to be equivalent to. What it must have instead is a
    // stop to put the keyboard on, and that is checked here rather than waved
    // through.
    function test_05_every_key_column_names_keys_that_exist() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var targets = suite.clickTargetsIn(list[s].item)
        for (var i = 0; i < targets.length; i++) {
          var hit = targets[i]
          if (!suite.usable(hit, list[s].item) || hit.barrier)
            continue
          checked += 1
          if (hit.focusOnly) {
            verify(hit.stop !== null,
                   list[s].name + ": \"" + hit.label + "\" takes no action and puts"
                   + " the keyboard nowhere, so a click on it does nothing at all")
            continue
          }
          verify(KeyHints.pressable(hit.key),
                 list[s].name + ": the click target \"" + hit.label + "\" names \""
                 + hit.key + "\" as the key that does the same thing, and that is not"
                 + " a key this game can press")
        }
      }
      verify(checked >= 20, "only " + checked + " live click targets were checked")
    }

    // ==================================================================
    // ROUND 4. THE KEY COLUMN, CHECKED FOR BEING TRUE.
    // ==================================================================
    //
    // A critic set `ui/parts/ActionButton.qml`'s `key: "Enter or Space"` to
    // `key: "Escape"` -- READY UP, LEAVE, RACE AGAIN, GARAGE, BACK and all
    // three RESETs now declaring that Escape is the key that does what a click
    // does -- and this file reported 27 passed, 0 failed while
    // `--print-controls` went on printing `parity verdict PASS`.
    //
    // The column was checked for being non-empty (test_01) and for naming keys
    // a keyboard has (test_05). It was never checked for naming the key that
    // DOES THE THING, which is the one claim the whole piece rests on. Seven
    // hand-written drive pairs (tests 10 to 18) asserted it on seven controls
    // out of sixty-odd, and a hand-written list is exactly what cannot catch
    // this: the column that lies is the one nobody wrote a pair for.
    //
    // So the two drive routes are crossed over EVERY control, generated from
    // the tree like everything else here:
    //
    //   1. enter the state, put the keyboard where the control's own stop is,
    //      CLICK the target, take the pointer off, photograph the screen;
    //   2. enter the same state again, put the keyboard in the same place,
    //      PRESS THE KEYS THE COLUMN NAMES, photograph the screen;
    //   3. the two photographs must be identical.
    //
    // The photograph is `fingerprint()` -- every drawn string with its box,
    // every named item with its box, every click target with its label and
    // whether it is live, the whole save file, and every signal the screens
    // have emitted. It is the same comparison `dev/Harness.qml --do ...
    // --dump-text` makes between a click-only and a key-only drive, which a
    // critic already accepted as evidence, widened from the strings to the tree
    // and run over every control instead of over one route.
    //
    // WHAT A KEY ROUTE IS, and why it is not a hand-written list coming back.
    // Almost every control's route is "the first key the column names, once",
    // computed here from `key` with no help from anybody. The exceptions are
    // controls that PICK a member of a set the keys STEP through -- a paint
    // swatch, a rival tag, an answer on the question -- where the honest
    // statement is "Right, that many times", and `ui/parts/Clickable.qml`'s
    // `keyRoute` says so at the control, in presses, next to the `key` column
    // that says the same thing in the words the child reads. A control that
    // cannot be crossed over at all declares `keyGap` with the reason, and this
    // test prints every one it found rather than passing over it in silence.
    function test_29_the_declared_key_does_what_the_click_does() {
      var list = suite.states()
      var checked = 0
      var stepped = 0
      var gaps = []
      for (var s = 0; s < list.length; s++) {
        suite.freshState(list[s])
        var count = suite.clickTargetsIn(list[s].item).length
        for (var i = 0; i < count; i++) {
          // ------------------------------------------------- the click route
          suite.freshState(list[s])
          var screen = list[s].item
          var targets = suite.clickTargetsIn(screen)
          if (i >= targets.length)
            break
          var hit = targets[i]
          if (hit.barrier === true || !suite.usable(hit, screen))
            continue
          var label = String(hit.label)
          var keySpec = String(hit.key)
          if (String(hit.keyGap).length > 0) {
            gaps.push(list[s].name + ": \"" + label + "\" -- " + hit.keyGap)
            continue
          }
          var route = suite.routeFor(hit)
          // A route of NO presses is a real answer and is only ever a declared
          // one: the swatch whose paint is already on, the answer already armed,
          // a focus-only target whose whole equivalent is the keyboard standing
          // on its stop. An UNDECLARED empty route means the key column named
          // nothing pressable, which is a hole rather than a claim.
          verify(route.length > 0 || hit.focusOnly === true
                 || (hit.keyRoute !== null && hit.keyRoute !== undefined),
                 list[s].name + ": \"" + label + "\" names \"" + keySpec + "\" as the"
                 + " key that does what a click does, and no press can be made from it."
                 + " Either name a key, or declare `keyGap` with the reason.")
          if (route.length > 1)
            stepped += 1
          suite.armKeyboard(screen, hit)
          var at = suite.centreOf(hit)
          mouseMove(root, at.x, at.y)
          mouseClick(root, at.x, at.y)
          wait(1)
          mouseMove(root, 0, 0)
          suite.settleFrame()
          var afterClick = suite.settledFingerprint(screen)

          // ------------------------------------------------- the key route
          suite.freshState(list[s])
          var again = suite.clickTargetsIn(screen)
          verify(i < again.length && String(again[i].label) === label,
                 list[s].name + ": the tree came back a different shape at target " + i
                 + " (\"" + label + "\" became \"" + (i < again.length ? again[i].label : "nothing")
                 + "\"), so the two routes are not being compared on the same control")
          suite.armKeyboard(screen, again[i])
          for (var k = 0; k < route.length; k++) {
            var code = suite.keyCodeFor(route[k])
            verify(code >= 0, list[s].name + ": \"" + label + "\" names the key \""
                   + route[k] + "\", which this game cannot press")
            keyClick(code)
          }
          mouseMove(root, 0, 0)
          suite.settleFrame()
          var afterKey = suite.settledFingerprint(screen)
          checked += 1

          // `verify` rather than `compare`, because a fingerprint is thousands
          // of characters and two of them printed side by side is not a message
          // anybody reads. `firstDifference` says the one line that differs.
          verify(afterKey === afterClick,
                  list[s].name + ": the click target \"" + label + "\" says \"" + keySpec
                  + "\" is the key that does the same thing, and it is not. Pressing "
                  + JSON.stringify(route) + " left the screen "
                  + suite.firstDifference(afterClick, afterKey) + ". The key column is"
                  + " the whole claim of this piece -- that no path is mouse-only --"
                  + " and until this case existed it was a string nobody verified: a"
                  + " critic set every button's key to Escape and the suite stayed"
                  + " green.")
        }
      }
      verify(checked >= 40, "only " + checked + " controls had their key column crossed"
             + " over against their click; the walk is not seeing the tree")
      verify(stepped >= 8, "not one control declared a stepping key route, so the"
             + " swatches and the aim tags -- the controls whose keys step through a"
             + " set a click lands in -- were not really crossed over")
      // THE CASE'S OWN TEETH. A comparison that cannot tell two states apart
      // passes every control, so it is pointed at a key that is NOT the one the
      // column names -- the exact mutation that survived round three -- and it
      // has to see the difference.
      suite.freshState(list[0])
      var ready = suite.targetNamed(garage, "READY UP")
      verify(ready !== null, "the garage has no READY UP to prove this case with")
      suite.armKeyboard(garage, ready)
      var readyAt = suite.centreOf(ready)
      mouseMove(root, readyAt.x, readyAt.y)
      mouseClick(root, readyAt.x, readyAt.y)
      wait(1)
      mouseMove(root, 0, 0)
      suite.settleFrame()
      var pressed = suite.settledFingerprint(garage)
      suite.freshState(list[0])
      suite.armKeyboard(garage, suite.targetNamed(garage, "READY UP"))
      keyClick(Qt.Key_Escape)
      mouseMove(root, 0, 0)
      suite.settleFrame()
      verify(suite.settledFingerprint(garage) !== pressed,
             "Escape and a click on READY UP leave this screen in states this case"
             + " cannot tell apart, so the comparison above is blind and every control"
             + " it passed was passed for nothing. This is the mutation that survived"
             + " round three: every button's key set to Escape, 27 tests green.")
      if (gaps.length > 0)
        console.log("key column, declared gaps:\n  " + gaps.join("\n  "))
    }

    /**
     * The fingerprint once the screen has stopped moving.
     *
     * Two states reached by two routes are photographed a few milliseconds
     * apart, and this game has things that ARRIVE: the settings banner fades in
     * over 180 ms, the question's extent goes on swallowing presses for one
     * double-click interval after the sheet has gone. The first run of this
     * case reported the KEEP answer's key column a liar because one route was
     * photographed on the frame before `NOTHING WAS CHANGED` was drawn and the
     * other on the frame after.
     *
     * Two identical reads in a row is the stop condition, so a still screen
     * costs one turn of the loop and a moving one costs as long as it moves.
     * Bounded, because a screen that never settles has to fail loudly on the
     * comparison rather than hang here.
     */
    function settledFingerprint(screen) {
      var last = suite.fingerprint(screen)
      for (var i = 0; i < 64; i++) {
        wait(16)
        // AND A FRAME IS DRAWN, or nothing arrives at all. On this offscreen
        // software backend `wait()` turns the event loop without rendering, and
        // a `Behavior on opacity` that no frame has advanced stays at zero for
        // ever -- so two reads in a row agreed that the banner was not there,
        // the loop stopped, and the case failed on a state that was still
        // arriving. `grabImage` renders synchronously; it is the same trick
        // `settleFrame` uses and for the same reason.
        grabImage(root)
        var now = suite.fingerprint(screen)
        if (now === last)
          return now
        last = now
      }
      return last
    }


    /**
     * The state, from the beginning, twice over.
     *
     * `enter()` shows a screen and drives it into its state; it does not put
     * the WORLD back, and the crossover needs that. The two routes have to
     * start from the same save file, the same race and the same signal counts,
     * or the second one is measuring what the first one left behind: the first
     * run of this case clicked the kart body down from body 5 and then pressed
     * Left from body 4, and reported the key column a liar on the one control
     * where it was telling the truth.
     */
    property string pristineWorld: ""
    function storeState() {
      return JSON.stringify(Store.settings) + "|" + JSON.stringify(Store.records)
    }
    function freshState(state) {
      // THE SAVE FILE IS ONLY PUT BACK WHEN A DRIVE MOVED IT. A reload rebinds
      // every one of the seven screens standing in this file at once, which is a
      // third of a second the crossover pays two hundred and fifty times over
      // for the controls that never touch the file -- a printed key hint, a
      // card, the pit crew.
      if (suite.storeState() !== suite.pristineWorld) {
        memory.reset()
        Store.reload()
        Store.setSetting("reducedMotion", true)
        suite.pristineWorld = suite.storeState()
      }
      // AND THE GUARD COMES DOWN. It is shared, it outlives a screen being
      // rebuilt, and that is the whole point of it -- which is also how it leaks
      // between two runs meant to be comparable: the click half of this pair
      // clicked `ESC  LEAVE` and armed `escape`, and the key half then pressed
      // an Escape that was correctly refused as the tail of it.
      Actions.clear()
      // AND THE WORLD STOPS MOVING, by the design's own switch. `ui/Countdown.qml`
      // pulses its numeral on an infinite animation and never stops, so the two
      // photographs caught the same `3` eight pixels apart and the case failed on
      // a screen doing exactly what it should. There is no `externalClock` there
      // to stop; there IS reduced motion, which is the accessibility switch the
      // design already specifies for "nothing pulses, nothing slides", and it
      // changes no control, no key, no action and no state -- only whether a
      // thing arrives over 220 ms or at once. It is part of the pristine world
      // above, so a settings row that toggles it is put back before the next run.
      root.raceRequests = 0
      root.leaveRequests = 0
      root.againRequests = 0
      root.garageRequests = 0
      root.cardsUsed = 0
      root.countdownAborts = 0
      root.raceLeaves = 0
      // AND THE CLOCK STOPS, for the reason `dev/Harness.qml` stops it before a
      // drive: the race screen's lap drum, its road and its readouts are bound
      // to a FrameAnimation, so two states photographed a few milliseconds apart
      // differ in a lap drum that has rolled on, and the diff is noise on every
      // line. `externalClock` is the screen's own answer and it is already
      // trusted for the piece F strips. Set before `buildRace`, so the race is
      // built under the clock it will run on.
      if (state.item.hasOwnProperty("externalClock"))
        state.item.externalClock = true
      if (typeof state.item.buildRace === "function")
        state.item.buildRace()
      suite.enter(state)
    }

    /**
     * The presses that reach a control's own state from the keyboard.
     *
     * The default is the first key the parity column names, once, which is true
     * of every control in this game but the ones that pick a member of a set the
     * keys step through. Those declare `keyRoute` themselves -- see
     * `ui/parts/Clickable.qml` -- and a FOCUS-ONLY target takes no action at
     * all, so its whole route is the keyboard being on its stop, which
     * `armKeyboard` has already done.
     */
    function routeFor(hit) {
      var declared = hit.keyRoute
      if (declared !== undefined && declared !== null) {
        var out = []
        for (var i = 0; i < declared.length; i++)
          out.push(String(declared[i]))
        return out
      }
      if (hit.focusOnly === true)
        return []
      var names = KeyHints.keyNames(hit.key)
      return names.length > 0 ? [names[0]] : []
    }

    /**
     * Put the keyboard exactly where BOTH routes need it, so the two states
     * being compared differ by the input device and by nothing else.
     *
     * A click is the Tab that lands on the control and the Enter that fires it,
     * so the key half of the pair has to start from the stop the click would
     * have moved to -- otherwise the arrow that steps a stepper reaches whatever
     * the keyboard happened to be standing on. A target with no stop is reached
     * by a named key from the screen itself (a card, a printed hint, the pit
     * crew), so the screen's own catcher gets the keyboard and the click does
     * not move it either.
     */
    function armKeyboard(screen, hit) {
      screen.forceActiveFocus()
      if (screen.focusTarget)
        screen.focusTarget.forceActiveFocus(Qt.TabFocusReason)
      if (hit && hit.stop)
        hit.stop.forceActiveFocus(Qt.MouseFocusReason)
    }

    readonly property var keyCodes: ({
      "tab": Qt.Key_Tab, "backtab": Qt.Key_Backtab, "up": Qt.Key_Up,
      "down": Qt.Key_Down, "left": Qt.Key_Left, "right": Qt.Key_Right,
      "enter": Qt.Key_Return, "return": Qt.Key_Return, "space": Qt.Key_Space,
      "esc": Qt.Key_Escape, "escape": Qt.Key_Escape, "backspace": Qt.Key_Backspace
    })

    function keyCodeFor(name) {
      var key = String(name).toLowerCase()
      if (suite.keyCodes.hasOwnProperty(key))
        return suite.keyCodes[key]
      if (key.length === 1 && key >= "0" && key <= "9")
        return Qt.Key_0 + (key.charCodeAt(0) - 48)
      if (key.length === 1 && key >= "a" && key <= "z")
        return Qt.Key_A + (key.charCodeAt(0) - 97)
      return -1
    }

    /**
     * EVERYTHING THE SCREEN IS, IN ONE STRING.
     *
     * Every drawn string with its box, every named item with its box, every
     * click target with its label and whether it is live, the whole save file,
     * and the count of every signal the screens have emitted. Nothing here is a
     * list somebody maintains: it is the same depth-first walk the rest of this
     * file uses, so a control added tomorrow is inside the comparison tomorrow.
     *
     * Not a pixel diff, and on purpose. `grabImage` plus a full-frame compare
     * costs about six tenths of a second (test_23 is 29 s of this file for that
     * reason), and it is also the wrong instrument here: two states reached at
     * different points of a fade differ in pixels for a reason that has nothing
     * to do with which key was pressed. This reads what the screen SAYS and
     * where it says it, which is the comparison the harness's own two-drive
     * evidence has always been made on.
     */
    function fingerprint(screen) {
      var out = []
      var all = suite.itemsUnder(screen)
      for (var i = 0; i < all.length; i++) {
        var item = all[i]
        // A TRANSIENT IS LEFT OUT, and it says so itself (`ui/parts/Callout.qml`).
        // The settings banner fades in over 180 ms and leaves after 1.6 s, so
        // whether it is on the screen when a photograph is taken is a fact about
        // the shutter and not about the press. What it reports -- that settings
        // were reset, or were not -- is compared through the save file below.
        if (suite.underTransient(item, screen))
          continue
        if (typeof item.text === "string" && item.font !== undefined
            && item.textFormat !== undefined && item.horizontalAlignment !== undefined) {
          if (!suite.drawn(item, screen) || item.text.length === 0)
            continue
          var p = item.mapToItem(root, 0, 0)
          out.push("text|" + Math.round(p.x) + "|" + Math.round(p.y) + "|"
                   + String(item.text).replace(/\n/g, " "))
          continue
        }
        if (item.isClickTarget === true) {
          out.push("hit|" + item.label + "|" + (suite.usable(item, screen) ? 1 : 0)
                   + "|" + item.key)
          continue
        }
        // A named item is recorded as PRESENT OR NOT, and not by its box. The
        // garage's stall is a turntable: the kart's own plate and digits sit a
        // pixel or two from where they sat a frame ago, for ever, whatever the
        // child pressed. A box would make every comparison on that screen a
        // coin toss; whether a thing is on the screen at all is the fact this
        // is here for, and the strings above carry the layout.
        if (String(item.objectName).length > 0)
          out.push("item|" + item.objectName + "|" + (suite.drawn(item, screen) ? 1 : 0))
      }
      out.push("settings|" + JSON.stringify(Store.settings))
      out.push("records|" + JSON.stringify(Store.records))
      if (typeof screen.stopIndex === "function")
        out.push("stop|" + screen.stopIndex())
      out.push("signals|" + root.raceRequests + "|" + root.leaveRequests + "|"
               + root.againRequests + "|" + root.garageRequests + "|" + root.cardsUsed
               + "|" + root.countdownAborts + "|" + root.raceLeaves)
      return out.join("\n")
    }

    /** Is this item inside something that says a thing and then stops saying it? */
    function underTransient(item, screen) {
      var node = item
      while (node && node !== screen.parent) {
        if (node.isTransient === true)
          return true
        node = node.parent
      }
      return false
    }

    /** The first line the two states disagree on, said in one sentence. */
    function firstDifference(a, b) {
      var left = String(a).split("\n")
      var right = String(b).split("\n")
      for (var i = 0; i < Math.max(left.length, right.length); i++) {
        var l = i < left.length ? left[i] : "(nothing)"
        var r = i < right.length ? right[i] : "(nothing)"
        if (l !== r)
          return "showing " + JSON.stringify(r) + " where the click left it showing "
                 + JSON.stringify(l)
      }
      return "in a state this comparison cannot tell from the click's"
    }

    // DIRECTION TWO, ORACLE THREE: A PRINTED KEY IS A PROMISE.
    //
    // The hole round one's gate could not see, and the one the critic found by
    // reading the screens instead of the tables. The two oracles below can only
    // find items that DECLARE themselves -- an `Accessible.role`, or a place in
    // a screen's `stops` array -- and a label declares neither, so the picker's
    // `ESC  BACK` and the confirm sheet's `ESC  KEEP` were invisible to every
    // check in the piece while the race's identical `ESC  LEAVE` was a control.
    //
    // ROUND 3. This used to read the STRINGS on the screen and decide from
    // their shape which ones were promises about a key. A critic demonstrated
    // that wrong in both directions on this build -- `3  CORRECT`, `7  LAPS`
    // and `2  TO GO` flagged as dead hints, `PAUSE  P`, `H\nPIT CREW` and
    // `ESC BACK` invisible -- so a hint now says what it is (`isKeyHint` on
    // `ui/parts/KeyHint.qml`) and this asks the component. The rule that a
    // printed key may not be written as a plain string at all is checked on the
    // SOURCE, by `npm run check:keyhints`, which is inside `npm run check`.
    //
    // The key-legend exemption is gone with the grammar that needed it: the
    // title rails draw a keycap beside a word in two items and are not hints,
    // so there is no longer a screen on which `ESC` in the title bar and `Esc`
    // in the footer are both listed here and only one of them works.
    function test_06_every_printed_key_hint_is_a_control() {
      var list = suite.states()
      var hints = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var all = suite.itemsUnder(list[s].item)
        for (var i = 0; i < all.length; i++) {
          var item = all[i]
          if (item.isKeyHint !== true || !suite.usable(item, list[s].item))
            continue
          hints += 1
          verify(suite.clickTargetOver(item, list[s].item) !== null,
                 list[s].name + ": \"" + String(item.text).replace(/\n/g, " | ")
                 + "\" is printed as a key hint and a click on it does nothing."
                 + " The same idiom is a control on the other screens, and a child"
                 + " who learns it there will press it here.")
          verify(KeyHints.pressable(item.key),
                 list[s].name + ": the key hint \"" + String(item.text) + "\" names \""
                 + item.key + "\" as its key, and that is not a key this game can press")
        }
      }
      verify(hints >= 4, "only " + hints + " printed key hints were found across every"
             + " state; the walk is not seeing the tree")
    }

    // DIRECTION TWO, ORACLE ONE: nothing is reachable by key and not by click.
    //
    // Every item whose `Accessible.role` says it is a control has a click target
    // inside it. This oracle is INDEPENDENT of the click list -- it asks the
    // accessibility tree what the controls are, so a control that was forgotten
    // when the mouse was added is a failure here rather than an absence nobody
    // notices. It caught two on its first run: TRACK and GOAL announced
    // themselves as buttons that could not be pressed or focused.
    function test_02_every_declared_control_can_be_clicked() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var controls = suite.declaredControlsIn(list[s].item)
        for (var i = 0; i < controls.length; i++) {
          var control = controls[i]
          if (!suite.usable(control, list[s].item))
            continue
          checked += 1
          var name = ""
          try {
            name = String(control.Accessible.name)
          } catch (error) {
            name = "(unnamed)"
          }
          verify(suite.hasClickTargetUnder(control, list[s].item),
                 list[s].name + ": the control \"" + name + "\" declares itself"
                 + " pressable and has no click target, so it is reachable by"
                 + " keyboard and not by mouse")
        }
      }
      verify(checked >= 15, "only " + checked + " drawn controls were found; the"
             + " accessibility walk is not seeing the tree")
    }

    // DIRECTION TWO, ORACLE TWO: every Tab stop can be clicked.
    //
    // A screen's `stops` array is not a description of its Tab chain, it IS the
    // Tab chain: `moveFocus` walks that exact array. So a stop with no click
    // target under it is a control the keyboard reaches by Tab and the mouse
    // cannot reach at all.
    function test_03_every_focus_stop_can_be_clicked() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        var screen = list[s].item
        if (screen.stops === undefined || screen.stops === null)
          continue
        suite.enter(list[s])
        for (var i = 0; i < screen.stops.length; i++) {
          // A stop the keyboard cannot reach right now -- every one of them
          // while the reset question is open, because the settings page is
          // switched off underneath it -- is not a keyboard path the mouse is
          // missing. `enabled` reads the item's own flag, so the ancestors are
          // walked.
          if (!suite.usable(screen.stops[i], screen))
            continue
          checked += 1
          verify(suite.hasClickTargetUnder(screen.stops[i], screen),
                 list[s].name + ": Tab stop " + i + " (" + screen.focusName(i)
                 + ") has no click target under it")
        }
      }
      verify(checked >= 15, "only " + checked + " focus stops were walked")
    }

    // THE PREMISE THE OTHER THREE REST ON.
    //
    // Tests 01 to 03 all find controls by looking for `isClickTarget`, which is
    // only a complete answer while `ui/parts/Clickable.qml` is the only mouse
    // handler in `ui/`. A raw `MouseArea` added somewhere would be a click
    // target none of them can see, and all three would go on passing while the
    // thing they enumerate had a hole in it. Checked on the tree rather than on
    // the source, so it is true of what is running: a MouseArea is duck-typed on
    // the three properties only it has together.
    function test_04_the_only_mouse_handler_in_the_game_is_the_click_target() {
      var list = suite.states()
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var all = suite.itemsUnder(list[s].item)
        for (var i = 0; i < all.length; i++) {
          var item = all[i]
          if (item.containsMouse === undefined || item.hoverEnabled === undefined
              || item.pressedButtons === undefined)
            continue
          verify(item.isClickTarget === true,
                 list[s].name + ": a mouse handler that is not a Clickable"
                 + " (objectName \"" + item.objectName + "\"). Every click target"
                 + " in this game is a Clickable, because that is what makes"
                 + " \"what can be clicked\" a question the item tree can answer.")
        }
      }
    }

    // ------------------------------------------------------------------
    // The drives. Real pointer, real keys, the same observable after each.
    // ------------------------------------------------------------------

    function centreOf(item) {
      var box = item.mapToItem(root, 0, 0, item.width, item.height)
      return Qt.point(Math.round(box.x + box.width / 2),
                      Math.round(box.y + box.height / 2))
    }

    /**
     * Draw a frame, so a position read afterwards is a position something was
     * drawn at.
     *
     * ROUND 2, and it cost an hour of a round to find: the picker's footer is a
     * `Flow` of key hints now, so a state change re-flows the panel and moves
     * the dock's whole contents. `wait(1)` turns the event loop once, which is
     * not a polish pass, so a click measured on the same turn as the state
     * change went 161 px from where the control was drawn -- and silently,
     * because a click that lands on nothing is not an error.
     *
     * `grabImage` is the cheap way to force one: it renders synchronously, and
     * `waitForRendering` on this offscreen software backend waits out its whole
     * five-second timeout whenever no frame happens to be scheduled, which took
     * the suite from 1.6 seconds to 72.
     */
    function settleFrame() {
      wait(1)
      grabImage(onePixel)
    }

    /** The first drawn, enabled click target on `screen` whose label contains
     *  `text`. Named rather than indexed so a reordered screen fails loudly. */
    function targetNamed(screen, text) {
      var wanted = String(text).toLowerCase()
      var targets = suite.clickTargetsIn(screen)
      for (var i = 0; i < targets.length; i++) {
        var hit = targets[i]
        if (!suite.usable(hit, screen))
          continue
        if (String(hit.label).toLowerCase().indexOf(wanted) >= 0)
          return hit
      }
      return null
    }

    function clickNamed(screen, text) {
      // THE FRAME HAS TO HAVE BEEN DRAWN BEFORE A POSITION IS READ OFF IT.
      //
      // ROUND 2, and it cost an hour: the picker's footer is a `Flow` of key
      // hints now, so a state change re-flows the panel and the dock's height
      // with it. `wait(1)` turns the event loop once, which is not a polish
      // pass, so a click measured on the same turn as the state change went to
      // where the control had been -- 161 px from where it was drawn, and
      // silently, because a miss is not an error. Every click a test makes is
      // now measured on a frame that exists.
      suite.settleFrame()
      var hit = suite.targetNamed(screen, text)
      verify(hit !== null, "no click target named \"" + text + "\"")
      var at = suite.centreOf(hit)
      mouseMove(root, at.x, at.y)
      mouseClick(root, at.x, at.y)
      wait(1)
    }

    // ------------------------------------------------------------------
    function test_10_the_stepper_arrows_step_the_way_the_arrow_keys_do() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(0)

      var start = Store.setting("kartBody")
      suite.clickNamed(garage, "kart body up")
      var afterClick = Store.setting("kartBody")
      compare(afterClick, (start + 1) % 6, "a click on the right arrow did not step")

      keyClick(Qt.Key_Right)
      compare(Store.setting("kartBody"), (start + 2) % 6,
              "the Right key and the right arrow do not step the same way")

      suite.clickNamed(garage, "kart body down")
      compare(Store.setting("kartBody"), (start + 1) % 6)
      keyClick(Qt.Key_Left)
      compare(Store.setting("kartBody"), start,
              "the Left key and the left arrow do not step the same way")
    }

    // A click is the Tab that lands on the control and the Enter that fires it,
    // in one press. Without the first half the keyboard would be left standing
    // somewhere else and the child's next Tab would jump away from the thing
    // they just touched.
    function test_11_a_click_moves_the_keyboard_onto_the_control() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(0)
      compare(garage.focusedName(), "Kart body, COUPE")

      suite.clickNamed(garage, "LEAVE")
      compare(garage.stopIndex(), 7, "a click did not move the keyboard onto LEAVE")
      compare(root.leaveRequests, 1, "the click did not fire the control")

      // ... and Tab now walks on from where the mouse put it, rather than from
      // where the keyboard had been.
      garage.moveFocus(1)
      compare(garage.stopIndex(), 0)
    }

    function test_12_a_swatch_paints_the_kart_the_way_the_arrows_do() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(1)
      compare(Store.setting("kartPaint"), 0)

      suite.clickNamed(garage, "paint " + Theme.paintName(5))
      compare(Store.setting("kartPaint"), 5, "clicking a swatch did not paint the kart")
      compare(garage.stopIndex(), 1, "clicking a swatch did not leave the keyboard on it")

      keyClick(Qt.Key_Right)
      compare(Store.setting("kartPaint"), 6,
              "the arrow key does not move on from where the click left it")
    }

    function test_13_a_settings_row_changes_the_way_enter_does() {
      root.showing = "settings"
      settings.forceActiveFocus()
      settings.focusStop(0)
      // Read rather than assumed: the screen's own rule is `sound !== false`,
      // and a fixture that starts with no key at all is still "on".
      var before = settings.sound

      // The row itself, not only the CHANGE chip: the chip is about a tenth of
      // the row's width and everything the child is reading is in the rest.
      suite.clickNamed(settings, "Sound row")
      compare(settings.sound, !before, "clicking the row did not toggle sound")
      suite.clickNamed(settings, "Sound row")
      compare(settings.sound, before, "clicking the row twice did not put it back")

      keyClick(Qt.Key_Return)
      compare(settings.sound, !before,
              "Enter on the row's own stop does not do what a click on the row does")
    }

    function test_14_the_results_buttons_press() {
      root.showing = "results"
      results.forceActiveFocus()
      results.focusStop(0)

      suite.clickNamed(results, "GARAGE")
      compare(root.garageRequests, 1)
      compare(results.stopIndex(), 1, "the click did not move the keyboard")

      keyClick(Qt.Key_Return)
      compare(root.garageRequests, 2, "Enter on the stop the click left does something else")
    }

    // Design v4.1 names "the picker's cards" first among the things the mouse
    // must reach. A click on a card is the card's own key: it CHOOSES it, and
    // that is all it can ever do.
    //
    // ROUND 2. This test used to be called "...and used by clicking again", and
    // the behaviour it named is the defect a critic found: two clicks sixteen
    // milliseconds apart spent the whole hand, where the same key twice did
    // nothing. A double-click is what children do with a mouse and there is no
    // undo in this plugin. Now the card chooses and the footer's `⏎  USE IT`
    // spends -- two different controls, exactly as the keyboard has always had
    // two different keys.
    function test_15_a_card_is_chosen_by_clicking_it_and_clicking_it_again_cannot_spend_it() {
      root.showing = "picker"
      picker.forceActiveFocus()
      compare(picker.chosen, -1)

      // Card 1 of the first hand is Nitro, which needs no target.
      suite.clickNamed(picker, "card 1")
      compare(picker.chosen, 0, "clicking a card did not choose it")
      compare(root.cardsUsed, 0, "one click spent the hand")

      // The gesture that spent the hand in round one, five times over, as fast
      // as the test framework can post it.
      for (var i = 0; i < 5; i++)
        suite.clickNamed(picker, "card 1")
      compare(root.cardsUsed, 0,
              "clicking a chosen card spent the hand -- a double-click on a card"
              + " must never be able to")
      compare(picker.chosen, 0, "and the card is still the one that was chosen")

      // The keyboard's own repeat, for the comparison the critic drew: `1`,
      // `1` leaves the card chosen and spends nothing. So does the mouse now.
      keyClick(Qt.Key_1)
      keyClick(Qt.Key_1)
      compare(root.cardsUsed, 0)
      compare(picker.chosen, 0)
    }

    // The control that CAN spend a hand, and what a second press on it does.
    function test_18_the_hand_is_spent_by_the_footer_key_that_says_so() {
      root.showing = "picker"
      picker.forceActiveFocus()

      suite.clickNamed(picker, "card 1")
      compare(picker.chosen, 0)
      // The panel prints the key that spends it, and the printed line is a
      // control: this is the same string `footerText` publishes.
      verify(picker.footerText.indexOf("⏎  USE IT") >= 0,
             "the panel does not print the key that spends the hand: "
             + JSON.stringify(picker.footerText))
      var use = suite.targetNamed(picker, "use the card")
      verify(use !== null, "the printed `⏎  USE IT` is not a click target")
      verify(use.destructive, "the control that spends a hand is not marked destructive")

      suite.clickNamed(picker, "use the card")
      compare(root.cardsUsed, 1, "clicking USE IT did not use the card")
    }

    // THE CLASS OF CHECK ROUND ONE DID NOT HAVE: what does a REPEAT do?
    //
    // Neither direction of the parity walk can see a defect in a repeat, because
    // both paths exist and both are reachable. So every destructive target on
    // every screen is pressed three times as fast as the framework can post the
    // events, and must do exactly what one press did. The list is generated from
    // the tree -- `Clickable.destructive` -- so a destructive control added
    // tomorrow is tested tomorrow without a line being added here.
    //
    // ==================================================================
    // ROUND 3. THIS TEST PASSED WITH THE GUARD IT IS NAMED FOR DELETED.
    // ==================================================================
    //
    // A critic set `Clickable.guardMs` to a constant 0 -- the double-click guard
    // removed outright -- and this file reported 23 passed, 0 failed. They
    // instrumented the refusal branch and it never fired once. Measured again
    // here, at five presses instead of three, with the guard deleted: every
    // destructive target in the round-2 state list still did exactly one
    // destructive thing.
    //
    // The reason is not the number of presses, and the fourth press does not
    // help. It is that EVERY destructive control in the round-2 list stops
    // taking presses the moment it acts:
    //
    //   the picker's `⏎  USE IT`   spends the hand, and `footerAct` then refuses
    //                              everything while the hand is flying off
    //   the question's `⏎  ANSWER` answers, and the question is not on the screen
    //                              for the second press to land on
    //
    // So the second press never reached the control that was supposed to refuse
    // it, `refusedRepeats` stayed 0 on every target in every state, and the
    // guard was pinned by nothing at all. A rule tested only where it cannot
    // fire is a rule the next builder deletes on a green suite.
    //
    // Two things fix it, and the second is the one that bites:
    //
    //   the RACE is in the state list now (see the `Race` above), and its `ESC`
    //   hint is the one destructive control in this game that STAYS under the
    //   pointer after it acts -- so the second press actually arrives at it;
    //
    //   the refusal is now ASSERTED where it can be seen, off the target's own
    //   `refusedRepeats`, and the test fails if no destructive control anywhere
    //   in the game kept its place long enough for the refusal to be observed
    //   even once. That last clause is what stops this test quietly going back
    //   to testing nothing.
    function test_19_no_destructive_control_acts_twice_on_a_double_click() {
      var list = suite.states()
      var checked = 0
      var refusalsSeen = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var targets = suite.clickTargetsIn(list[s].item)
        for (var i = 0; i < targets.length; i++) {
          var hit = targets[i]
          if (!hit.destructive || !suite.usable(hit, list[s].item))
            continue
          checked += 1
          var at = suite.centreOf(hit)
          var label = hit.label
          // COUNTED ON THE SIGNAL, NOT ON A PROPERTY READ AFTERWARDS. A
          // destructive control usually STOPS EXISTING when it acts -- the
          // picker's `⏎  USE IT` goes with the hand it spent -- so a count read
          // off the tree after the clicks reads zero and calls that a pass.
          //
          // Re-armed between presses, because the interesting failure is the
          // repeat that WALKS: press one spends the hand, the footer turns back
          // into `1 2 3  CHOOSE A CARD` under the same pixel, press two chooses
          // a card, and press three lands on a brand-new `⏎  USE IT`. Every
          // destructive control that exists at each press is counted.
          var acts = 0
          var armed = []
          var bump = function () { acts += 1 }
          suite.armDestructive(list[s].item, armed, bump)
          mouseMove(root, at.x, at.y)
          mouseClick(root, at.x, at.y)
          suite.armDestructive(list[s].item, armed, bump)
          mouseClick(root, at.x, at.y)
          suite.armDestructive(list[s].item, armed, bump)
          mouseClick(root, at.x, at.y)
          var before = 0
          var after = acts
          // THE REFUSAL ITSELF, WHERE IT CAN BE SEEN. `acts` is one either way
          // when the second press landed on nothing -- which is every
          // destructive control in this game except the race's `ESC` hint. Where
          // the target IS still under the pointer and still taking presses, the
          // guard has to have refused the two that followed, and saying so is
          // the difference between "the screen did not change" and "the press
          // was refused".
          if (hit !== null && suite.usable(hit, list[s].item) && hit.destructive) {
            verify(hit.refusedRepeats >= 1,
                   list[s].name + ": \"" + label + "\" was still under the pointer for"
                   + " the second and third press and refused none of them. It accepted "
                   + hit.actedCount + " presses.")
            refusalsSeen += 1
          }
          // ONE. Not "at most one": the first press has to work, because the
          // maintainer's standing complaint is a power-up that had to be
          // triggered several times and a guard that swallowed the first press
          // would be that bug. And not more than one, whatever the second and
          // third presses landed on -- the count is over EVERY destructive
          // target on the screen, so a repeat that walks through a changing
          // panel and reaches a second destructive control is caught too.
          compare(after - before, 1,
                  list[s].name + ": three clicks on \"" + label + "\", 16 ms apart,"
                  + " did " + (after - before) + " destructive things. A double-click"
                  + " is what a child does with a mouse and there is no undo in this game.")
          // AND THE COUNTER IS PUT AWAY. `var` is function-scoped in this
          // dialect, so `acts` and `bump` are ONE variable across every turn of
          // this loop: a connection left behind by an earlier target went on
          // incrementing the counter the current one is read from. It never
          // showed until round four made the question's two answers destructive
          // -- two destructive controls on one screen, both of which survive
          // their own press -- and then one click on RESET counted as two.
          for (var d = 0; d < armed.length; d++)
            armed[d].acted.disconnect(bump)
          suite.enter(list[s])
        }
      }
      verify(checked >= 3, "only " + checked + " destructive controls were found across"
             + " every state; the walk is not seeing them")
      // AND THE GUARD WAS ACTUALLY EXERCISED. Round two's version of this test
      // passed with the guard deleted because no press ever reached a control
      // that could refuse it: every destructive target vanished, or froze its
      // own panel, on the press that acted. A sweep that never enters the
      // refusal branch is a sweep that is not testing the guard, and it must
      // say so rather than report a pass.
      verify(refusalsSeen >= 1,
             "not one destructive control in any state stayed under the pointer long"
             + " enough to refuse a second press, so the double-click guard was never"
             + " entered and nothing here tested it. This is exactly the state this"
             + " test was in when a critic deleted the guard and it still passed.")
    }

    // ==================================================================
    // ROUND 3. THE OTHER CHANGE ROUND 2 MADE THAT NOTHING TESTED.
    // ==================================================================
    //
    // The second survivor a critic found: `ui/Settings.qml`'s page carried
    // `enabled: !settings.confirming && !settings.justAnswered`, a 400 ms window
    // after every answered question in which the screen behind took nothing --
    // and the whole suite passed with that clause deleted, because `init()`
    // calls `resetScreens()`, which sets `justAnswered` back to false before
    // every case. The suite stepped around the behaviour it was meant to hold.
    //
    // What the clause was for is real and is measurable: the question's own
    // `⏎  ANSWER` line is a 104 x 26 target that sits ON TOP OF the RIVALS row,
    // which is 976 x 106 and comes back to life the instant the question
    // closes. Three clicks 16 ms apart at that one point answered the question
    // with the first and, with the clause deleted, changed the rival level with
    // the two nobody meant to send.
    //
    // So the rule is stated here as the child meets it, on the observable the
    // child would see changed, and it does not touch `justAnswered` or any other
    // implementation of it: a double-click on a modal's control must not reach
    // the screen behind that modal. `resetScreens()` cannot help this case --
    // the state it would clear is created inside the case, by the click.
    function test_25_a_double_click_on_the_question_cannot_reach_the_screen_behind() {
      root.showing = "settings"
      settings.forceActiveFocus()
      suite.settleFrame()

      suite.clickNamed(settings, "RESET GARAGE RECORDS")
      suite.settleFrame()
      verify(settings.confirming, "the reset question did not open")

      var answer = suite.targetNamed(settings, "Give the armed answer")
      verify(answer !== null, "the question prints no `⏎  ANSWER` line to click")
      verify(answer.destructive, "the line that answers the question is not guarded")
      var at = suite.centreOf(answer)

      // THE OVERLAP, ASSERTED RATHER THAN ASSUMED. If the question's footer ever
      // stops standing on a live control, this case is no longer about anything
      // and has to say so instead of passing.
      var behind = null
      var targets = suite.clickTargetsIn(settings)
      for (var i = 0; i < targets.length; i++) {
        var t = targets[i]
        if (t === answer || suite.usable(t, settings))
          continue
        var box = suite.boxAround(t, 0)
        if (at.x >= box.x && at.x <= box.right && at.y >= box.y && at.y <= box.bottom)
          behind = t
      }
      verify(behind !== null,
             "the question's `⏎  ANSWER` line does not stand on any control of the"
             + " screen behind it, so this case tests nothing")

      var rivalsBefore = Store.setting("rivalLevel")
      var soundBefore = Store.setting("sound")
      var motionBefore = Store.setting("reducedMotion")
      var scanlinesBefore = Store.setting("scanlines")

      mouseMove(root, at.x, at.y)
      mouseClick(root, at.x, at.y)
      mouseClick(root, at.x, at.y)
      mouseClick(root, at.x, at.y)

      verify(!settings.confirming, "the first click did not answer the question")
      compare(Store.setting("rivalLevel"), rivalsBefore,
              "three clicks 16 ms apart on the question's own `⏎  ANSWER` line changed"
              + " the rival level. The line stands on the \"" + behind.label + "\","
              + " which comes back to life the moment the question closes, so the half"
              + " of the double-click nobody meant to send landed on a setting. There"
              + " is no undo in this game.")
      compare(Store.setting("sound"), soundBefore, "a setting behind the question changed")
      compare(Store.setting("reducedMotion"), motionBefore,
              "a setting behind the question changed")
      compare(Store.setting("scanlines"), scanlinesBefore,
              "a setting behind the question changed")
    }

    // ==================================================================
    // ROUND 3. AND THE KEYBOARD DOES NOT PAY FOR IT.
    // ==================================================================
    //
    // The other half of the case above, and the reason round two's fix had to
    // go. That fix switched the whole settings page off for 400 ms after every
    // answer, which took the keyboard with it. Measured by a critic on the
    // shipped build: a Down 16 ms after answering was not delayed, it was
    // DROPPED -- the same Down 700 ms later worked -- and for the whole window
    // `focusedName()` was empty, so the focus ring was off the screen
    // altogether. Four tenths of a second of nothing, after every confirmation,
    // with no ring to say where the keyboard was.
    //
    // A mouse hazard must not be paid for by the other input device. This case
    // is the one that fails if anyone ever pays for it that way again: the
    // question is answered WITH THE MOUSE, and the very next keystroke, on the
    // same turn of the event loop, has to move the focus the way it always does.
    function test_26_the_keyboard_is_not_frozen_by_answering_a_question() {
      root.showing = "settings"
      settings.forceActiveFocus()
      settings.focusStop(0)
      suite.settleFrame()

      suite.clickNamed(settings, "RESET GARAGE RECORDS")
      suite.settleFrame()
      verify(settings.confirming, "the reset question did not open")

      suite.clickNamed(settings, "Give the armed answer")
      verify(!settings.confirming, "the click on `⏎  ANSWER` did not answer the question")

      // THE RING IS SOMEWHERE. `--focus -1` exists to photograph the state in
      // which nothing on a screen holds focus, and `ui/Settings.qml`'s own
      // comment calls it a state no child should ever be in. Round two left the
      // child in it for 400 ms after every answer.
      verify(settings.stopIndex() >= 0,
             "nothing on the settings screen holds the keyboard the instant a question"
             + " is answered, so there is no focus ring anywhere on the screen")
      var landed = settings.stopIndex()
      compare(settings.focusedName(), settings.focusName(landed))

      keyClick(Qt.Key_Down)
      verify(settings.stopIndex() !== landed,
             "a Down pressed straight after answering a question moved nothing. The"
             + " keystroke was not delayed, it was dropped: this screen used to switch"
             + " itself off for 400 ms after every answer to keep the second half of a"
             + " double-click off the rows behind the question, and a keyboard user paid"
             + " for a mouse defect.")
      keyClick(Qt.Key_Up)
      compare(settings.stopIndex(), landed,
              "Up did not come back to the stop the question left the keyboard on")
    }

    // ==================================================================
    // ROUND 3. A SCREEN THAT PRINTS A KEY HAS TO HONOUR IT.
    // ==================================================================
    //
    // A keyboard defect, in a file about the mouse, and that is the honest
    // place for it: the instrument that found it is this piece's own. Round two
    // gave this repository the ability to post a real `Key_Tab` through the
    // harness (`--do key:tab`, `dev/Pointer.qml`) and then did not point it at
    // the screens whose parity it was certifying. A critic did:
    //
    //   --screen Settings --do key:tab   x9 -> Sound, ON, change   every time
    //   --screen Results  --do key:tab   x2 -> Race again          every time
    //
    // Neither screen had a `Key_Tab` branch, and every stop on both carries
    // `activeFocusOnTab: false` (see the long note in `ui/Garage.qml`, which
    // got this fix in its round 8), so Qt's implicit chain had nothing to walk
    // either. Meanwhile the settings title band prints `TAB  ↑ ↓   MOVE` and
    // its screen-reader description promises that Tab moves. A screen that
    // prints a key it does not honour is worse than one that prints nothing.
    //
    // The check is generated from the tree, like everything else in this file:
    // every state whose screen keeps a `stops` array -- the array its own
    // handler walks, which IS this game's definition of "what the keyboard can
    // reach by Tab" -- must move on Tab and back on Shift+Tab. A screen added
    // tomorrow is checked tomorrow with no line added here.
    function test_27_every_screen_with_focus_stops_honours_tab() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var screen = list[s].item
        if (screen.stops === undefined || screen.stops === null
            || screen.stops.length < 2)
          continue
        if (typeof screen.focusStop !== "function"
            || typeof screen.stopIndex !== "function")
          continue
        // A screen whose stops are switched off right now -- every one of them
        // while the reset question is open -- is not a screen the keyboard is
        // failing to walk. Skipped, and the count below says how many states
        // were really asked.
        if (!suite.usable(screen.stops[0], screen))
          continue
        screen.forceActiveFocus()
        screen.focusStop(0)
        suite.settleFrame()
        compare(screen.stopIndex(), 0, list[s].name + ": the keyboard did not start"
                + " on the first stop")
        checked += 1

        keyClick(Qt.Key_Tab)
        compare(screen.stopIndex(), 1,
                list[s].name + ": Tab moved nothing. This screen keeps a list of"
                + " focus stops and its own title band tells the child that Tab"
                + " walks them; a key printed on a screen is a promise.")
        keyClick(Qt.Key_Tab, Qt.ShiftModifier)
        compare(screen.stopIndex(), 0,
                list[s].name + ": Shift+Tab did not walk back")
      }
      verify(checked >= 3, "only " + checked + " screens with focus stops were asked"
             + " whether they honour Tab; the walk is not seeing them")
    }

    // ==================================================================
    // ROUND 3. THE GUARD WAS ONE-SIDED, AND THE RACE IS WHERE THAT BITES.
    // ==================================================================
    //
    // `ui/parts/Clickable.qml` refuses the second press of a double-click on a
    // destructive control, and a critic pointed out that `guard.running` was
    // consulted in exactly one place -- the click handler. So click->click was
    // guarded, click->key was not, and they named the screen where it matters:
    // `ui/Race.qml`'s `ESC` hint is the one control in this game whose MEANING
    // changes under the pointer. `BACK` while a card is chosen, `LEAVE`
    // without. A click puts the card back and arms the guard; an Escape 100 ms
    // later finds the card already back, takes the other branch, and leaves the
    // race. There is no undo, and it is a race the child was in the middle of.
    //
    // They could not drive it end to end -- the harness cannot get from the
    // countdown into a live race under an external clock -- and reported it as
    // a code-level finding. This file can: it holds a real `Race`, it deals a
    // real hand by answering real facts, and it posts a real click and a real
    // keystroke.
    function test_28_a_click_that_puts_a_card_back_does_not_arm_escape_to_leave() {
      root.showing = "race"
      race.rivals = null
      race.forceActiveFocus()
      suite.settleFrame()
      verify(race.focusTarget.activeFocus,
             "the race screen's key catcher lost active focus, so nothing below this"
             + " line is a statement about anything. Run this spec headless.")

      suite.dealRaceHand()
      root.raceLeaves = 0

      // Chosen with the MOUSE, put back with the MOUSE, and then the keyboard.
      suite.clickNamed(race.handPanel, "card 1")
      compare(race.handPanel.chosen, 0, "clicking a card in the race did not choose it")

      // The race and the hand panel BOTH print a control called "put the card
      // back" while a card is chosen -- the screen's own `ESC` line and the
      // panel's footer -- and they are not the same control. The one this case
      // is about is the guarded one: the line that says BACK now and LEAVE the
      // moment the card is back. (The panel's footer is the other half of this
      // hazard and is not guarded; see the report.)
      var escape = null
      var inRace = suite.clickTargetsIn(race)
      for (var i = 0; i < inRace.length; i++) {
        if (String(inRace[i].label).toLowerCase().indexOf("put the card back") >= 0
            && inRace[i].destructive && suite.usable(inRace[i], race))
          escape = inRace[i]
      }
      verify(escape !== null,
             "with a card chosen the race's own ESC line is not a guarded control that"
             + " says it puts the card back")
      var at = suite.centreOf(escape)
      mouseMove(root, at.x, at.y)
      mouseClick(root, at.x, at.y)
      compare(race.handPanel.chosen, -1, "the click did not put the card back")
      compare(root.raceLeaves, 0, "the click that put the card back left the race")

      keyClick(Qt.Key_Escape)
      compare(root.raceLeaves, 0,
              "an Escape 16 ms after a CLICK on the same control left the race. The"
              + " control changed its meaning under the pointer -- it said BACK when it"
              + " was clicked and LEAVE by the time the key arrived -- and the guard was"
              + " consulted only by the click handler, so the half of the repeat that"
              + " came from the other input device was not refused.")

      // And a DELIBERATE Escape still leaves. A guard that stayed up would be
      // the maintainer's other complaint -- a control that has to be pressed
      // several times -- pointing the other way.
      wait(450)
      keyClick(Qt.Key_Escape)
      compare(root.raceLeaves, 1,
              "an Escape after the double-click interval did not leave the race")
    }

    // ==================================================================
    // ROUND 4. A DESTRUCTIVE CONTROL WITH NO GUARD IS A GUARD NOBODY SET.
    // ==================================================================
    //
    // `H  PIT CREW` was destructive in every sense a child meets -- it spends
    // one of their questions and there is no undo -- and it carried no
    // `destructive` flag, so `test_19`, which walks that flag, did not merely
    // fail to test it: the control was outside the test's subject. Three clicks
    // burned three questions with `refusedRepeats` at zero.
    //
    // The flag is still a hand-set boolean and this case cannot make it
    // otherwise. What it can do is close the other half: now that the guard is a
    // property of the action, "declared destructive" and "actually guarded" are
    // two different statements, and a control that makes the first without the
    // second is the shape of a guard somebody meant to add. Generated from the
    // tree, so a destructive control added tomorrow is checked tomorrow.
    function test_30_every_destructive_control_names_the_guard_it_shares() {
      var list = suite.states()
      var checked = 0
      var names = []
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var targets = suite.clickTargetsIn(list[s].item)
        for (var i = 0; i < targets.length; i++) {
          var hit = targets[i]
          if (!hit.destructive || !suite.usable(hit, list[s].item))
            continue
          checked += 1
          verify(hit.guards !== null && hit.guards !== undefined && hit.guards.length > 0,
                 list[s].name + ": \"" + hit.label + "\" says it does something a child"
                 + " cannot take back and names no guard, so nothing refuses the second"
                 + " half of a double-click on it. See ui/parts/Actions.qml.")
          for (var g = 0; g < hit.guards.length; g++)
            if (names.indexOf(String(hit.guards[g])) < 0)
              names.push(String(hit.guards[g]))
        }
      }
      verify(checked >= 5, "only " + checked + " destructive controls were found across"
             + " every state; the walk is not seeing them")
      // AND THE GUARDS ARE SHARED, which is the whole change. If every
      // destructive control invented a name of its own we would be back to a
      // guard per control under a different spelling, and the four defects that
      // caused this round would all come back.
      verify(names.length < checked,
             "every destructive control names a guard nobody else names ("
             + JSON.stringify(names) + " across " + checked + " controls), so the guard"
             + " is a property of the control again and two controls that do the same"
             + " destructive thing cannot refuse each other's repeat.")
    }

    // ==================================================================
    // ROUND 4. THE FOUR ONE-SIDED CASES, DRIVEN.
    // ==================================================================
    //
    // Round three guarded the pointer's half of one hazard and left three more.
    // A critic measured all four in the running game; each one is a paragraph
    // below and each one is driven here with real events, on a real race, with a
    // real hand dealt by answering real facts.
    //
    // They are four presses of the same idea: the guard belongs to the ACTION.
    // What differs is only which route each half of the repeat came by and which
    // control it landed on.
    function test_31_a_guarded_action_is_refused_whichever_hand_repeats_it() {
      root.showing = "race"
      race.rivals = null
      race.forceActiveFocus()
      suite.settleFrame()
      verify(race.focusTarget.activeFocus,
             "the race screen's key catcher lost active focus, so nothing below this"
             + " line is a statement about anything. Run this spec headless.")
      suite.dealRaceHand()

      // ---------------------------------------------------------------- D1
      // `H  PIT CREW` stays exactly where it is after it acts, so the second and
      // third presses of a double-click always arrive at it. Measured by a
      // critic on the shipped build: answers shown 0 -> 1 -> 3, refused 0.
      Actions.clear()
      var pit = suite.targetNamed(race, "Pit crew")
      verify(pit !== null, "the race prints no pit crew line to click")
      verify(pit.destructive,
             "the pit crew spends one of the child's questions and there is no undo,"
             + " and it does not say it is destructive")
      var pitAt = suite.centreOf(pit)
      var shownBefore = race.state.racers[0].pitCrewCount
      mouseMove(root, pitAt.x, pitAt.y)
      mouseClick(root, pitAt.x, pitAt.y)
      mouseClick(root, pitAt.x, pitAt.y)
      mouseClick(root, pitAt.x, pitAt.y)
      compare(race.state.racers[0].pitCrewCount - shownBefore, 1,
              "three clicks on `H  PIT CREW` 16 ms apart showed "
              + (race.state.racers[0].pitCrewCount - shownBefore) + " answers. Each one"
              + " is a question the child does not get back, the results screen prints"
              + " the total as ANSWERS SHOWN, and there is no undo.")
      verify(pit.refusedRepeats >= 2,
             "the pit crew was under the pointer for all three presses and refused none"
             + " of them as repeats; it accepted " + pit.actedCount)

      // ---------------------------------------------------------------- D4
      // Escape first, then a click on the race's own ESC line 16 ms later. The
      // key armed nothing at all in round three, because only the click handler
      // armed, so this left the race.
      Actions.clear()
      mouseMove(root, 0, 0)
      suite.clickNamed(race.handPanel, "card 1")
      compare(race.handPanel.chosen, 0, "clicking a card in the race did not choose it")
      root.raceLeaves = 0
      keyClick(Qt.Key_Escape)
      compare(race.handPanel.chosen, -1, "Escape did not put the card back")
      var escLine = suite.guardedEscapeLine()
      verify(escLine !== null,
             "with the card back the race's own ESC line is not a guarded control")
      var escAt = suite.centreOf(escLine)
      mouseMove(root, escAt.x, escAt.y)
      mouseClick(root, escAt.x, escAt.y)
      compare(root.raceLeaves, 0,
              "a CLICK on the race's ESC line 16 ms after an ESCAPE left the race. The"
              + " key put the card back and armed nothing, so the pointer's half of the"
              + " repeat found the line meaning LEAVE and took it.")

      // ---------------------------------------------------------------- D2
      // The hand panel's own `ESC  BACK` chip, clicked, then Escape. Two
      // controls performing the same back-out gesture; in round three they had
      // one guard each and the key had none. The chip is the one with the word
      // ESC printed next to the cards the child is looking at.
      Actions.clear()
      mouseMove(root, 0, 0)
      suite.clickNamed(race.handPanel, "card 1")
      compare(race.handPanel.chosen, 0)
      root.raceLeaves = 0
      suite.clickNamed(race.handPanel, "put the card back")
      compare(race.handPanel.chosen, -1, "the chip did not put the card back")
      keyClick(Qt.Key_Escape)
      compare(root.raceLeaves, 0,
              "the child clicked the words `ESC  BACK` on the hand panel, the card went"
              + " back, they pressed the Escape those words had just told them about,"
              + " and the race ended. Two controls, one gesture, and in round three one"
              + " guard each.")

      // ---------------------------------------------------------------- D3
      // The same chip, double-clicked. The first press puts the card back; the
      // footer instantly redraws as `1 2 3  CHOOSE A CARD` at the same pixel and
      // the second press CHOSE CARD 1. That is round two's walking-repeat
      // defect, one control to the left of where round two fixed it, and it is
      // unguarded precisely because the target that acts second is a different,
      // non-destructive control -- which is why "the list is generated from the
      // tree" does not save you and why the guard had to leave the control.
      Actions.clear()
      mouseMove(root, 0, 0)
      suite.clickNamed(race.handPanel, "card 1")
      compare(race.handPanel.chosen, 0)
      root.raceLeaves = 0
      var chip = suite.targetNamed(race.handPanel, "put the card back")
      verify(chip !== null, "the hand panel prints no `ESC  BACK` chip")
      var chipAt = suite.centreOf(chip)
      mouseMove(root, chipAt.x, chipAt.y)
      mouseClick(root, chipAt.x, chipAt.y)
      mouseClick(root, chipAt.x, chipAt.y)
      compare(race.handPanel.chosen, -1,
              "a double-click on the panel's `ESC  BACK` chip put the card back and then"
              + " chose card " + (race.handPanel.chosen + 1) + " at the same pixel: the"
              + " footer redraws as `1 2 3  CHOOSE A CARD` under the pointer between the"
              + " two presses.")
      compare(root.raceLeaves, 0, "the double-click on the chip left the race")
    }

    /** The race's own ESC line, as a guarded control that can leave the race. */
    function guardedEscapeLine() {
      var inRace = suite.clickTargetsIn(race)
      for (var i = 0; i < inRace.length; i++) {
        if (String(inRace[i].label).toLowerCase().indexOf("leave the race") >= 0
            && inRace[i].destructive && suite.usable(inRace[i], race))
          return inRace[i]
      }
      return null
    }

    function test_16_a_rival_tag_is_aimed_at_by_clicking_it() {
      root.showing = "picker"
      picker.forceActiveFocus()

      // Card 3 of the first hand is the Wrench, which is targeted.
      suite.clickNamed(picker, "card 3")
      compare(picker.chosen, 2)
      verify(picker.targeting, "the wrench did not open the aim")
      compare(picker.targetIndex, 0)

      suite.clickNamed(picker, "aim " + picker.rivals[2].name)
      compare(picker.targetIndex, 2, "clicking a rival tag did not aim at it")

      keyClick(Qt.Key_Left)
      compare(picker.targetIndex, 1,
              "the arrow key does not step on from where the click left the aim")
    }

    function test_17_the_countdown_can_be_left_by_clicking_the_line_that_says_esc() {
      root.showing = "countdown"
      countdown.forceActiveFocus()
      compare(root.countdownAborts, 0)

      suite.clickNamed(countdown, "back to the garage")
      compare(root.countdownAborts, 1, "clicking the ESC line did not leave")
    }

    // ------------------------------------------------------------------
    // Hover. A child moving a mouse has to see that a thing is a control
    // BEFORE pressing it.
    // ------------------------------------------------------------------

    // ==================================================================
    // ROUND 2: THESE TWO TESTS READ PIXELS, BECAUSE THEIR NAMES ARE CLAIMS
    // ABOUT PIXELS.
    // ==================================================================
    //
    // The repository's rule: a test's name is a claim, and a test that passes
    // under mutation of the rule it names is a defect. A critic mutated
    // `ui/parts/FocusRing.qml` so hover drew the focus ring, the focus fill,
    // the full border and the outer halo -- hover and focus one state -- and
    // all seventeen tests passed. They then set `ActionButton`'s `hovered` to
    // constant false, so READY UP, LEAVE, RACE AGAIN, GARAGE and all three
    // RESET buttons painted no hover at all, and all seventeen passed again.
    //
    // Both tests read `Clickable.hovered`, which is the raw `MouseArea` state,
    // and never a painted pixel. The "hover is visible" half of this piece's
    // gate was held up by four PNG crops a human looked at once.
    //
    // So they grab the frame. `grabImage` renders the item synchronously on
    // this offscreen software backend and a full 1920 x 1080 comparison costs
    // about half a second, which is affordable for the two tests in this file
    // whose subject is what the screen LOOKS like.

    /**
     * How many pixels differ, and the box they are in. Every pixel of the frame
     * unless `only` names a box, in which case only that box -- which is what a
     * comparison of two frames that differ ELSEWHERE for a legitimate reason
     * needs: the keyboard has to be somewhere, so a frame with the focus on one
     * control and a frame with it on another differ in two places by design.
     */
    function diff(a, b, only) {
      var count = 0
      var minX = a.width, minY = a.height, maxX = -1, maxY = -1
      var fromY = only ? Math.max(0, Math.floor(only.y)) : 0
      var toY = only ? Math.min(a.height, Math.ceil(only.bottom)) : a.height
      var fromX = only ? Math.max(0, Math.floor(only.x)) : 0
      var toX = only ? Math.min(a.width, Math.ceil(only.right)) : a.width
      for (var y = fromY; y < toY; y++) {
        for (var x = fromX; x < toX; x++) {
          if (a.red(x, y) === b.red(x, y) && a.green(x, y) === b.green(x, y)
              && a.blue(x, y) === b.blue(x, y))
            continue
          count += 1
          if (x < minX) minX = x
          if (y < minY) minY = y
          if (x > maxX) maxX = x
          if (y > maxY) maxY = y
        }
      }
      return { "count": count, "x": minX, "y": minY,
               "right": maxX, "bottom": maxY }
    }

    /** The control's own box in root coordinates, grown by `pad` on every side. */
    function boxAround(item, pad) {
      var b = item.mapToItem(root, 0, 0, item.width, item.height)
      return { "x": b.x - pad, "y": b.y - pad,
               "right": b.x + b.width + pad, "bottom": b.y + b.height + pad }
    }

    function inside(box, outer) {
      return box.x >= outer.x && box.y >= outer.y
             && box.right <= outer.right && box.bottom <= outer.bottom
    }

    function boxText(box) {
      return "(" + box.x + "," + box.y + ")-(" + box.right + "," + box.bottom + ")"
    }

    // The pointer's answer to "is this a control", read off the frame: something
    // inside the control changes, and NOTHING anywhere else on the screen does.
    //
    // The ring is drawn outside the control's own edge -- `FocusRing` uses a
    // gap of 5 and a thickness of 3 on a primary button -- so the allowance is
    // 12 px, which is the ring plus its halo and nothing like a neighbour.
    function test_20_a_control_lights_under_the_pointer_and_only_that_control() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(0)
      suite.settleFrame()

      var ready = suite.targetNamed(garage, "READY UP")
      var leave = suite.targetNamed(garage, "LEAVE")
      verify(ready !== null && leave !== null)
      verify(!ready.hovered && !leave.hovered, "something is hovered before the pointer moved")

      mouseMove(root, 0, 0)
      suite.settleFrame()
      var idle = grabImage(garage)

      var at = suite.centreOf(ready)
      mouseMove(root, at.x, at.y)
      verify(ready.hovered, "READY UP does not light under the pointer")
      verify(!leave.hovered, "LEAVE lights when the pointer is on READY UP")
      suite.settleFrame()
      var lit = grabImage(garage)

      var changed = suite.diff(idle, lit)
      verify(changed.count > 200,
             "the pointer on READY UP changed " + changed.count + " pixels. A control"
             + " that does not light under the pointer is a control a child cannot"
             + " find with a mouse -- and this is the assertion a critic broke by"
             + " setting ActionButton's `hovered` to constant false, with every"
             + " test still passing.")
      var allowed = suite.boxAround(ready, 12)
      verify(suite.inside(changed, allowed),
             "the pointer on READY UP changed pixels at " + suite.boxText(changed)
             + ", outside its own box " + suite.boxText(allowed)
             + ": hover is leaking onto something the pointer is not on")

      var elsewhere = suite.centreOf(leave)
      mouseMove(root, elsewhere.x, elsewhere.y)
      verify(!ready.hovered, "READY UP stays lit after the pointer left it")
      verify(leave.hovered)
      suite.settleFrame()
      var moved = suite.diff(idle, grabImage(garage))
      verify(moved.count > 200, "LEAVE does not light under the pointer")
      verify(suite.inside(moved, suite.boxAround(leave, 12)),
             "with the pointer on LEAVE, pixels changed at " + suite.boxText(moved)
             + " -- READY UP did not go back to how it was drawn before")

      mouseMove(root, 0, 0)
      verify(!ready.hovered && !leave.hovered,
             "a control is still lit with the pointer in the corner")
      suite.settleFrame()
      compare(suite.diff(idle, grabImage(garage)).count, 0,
              "the screen does not go back to its idle frame when the pointer leaves")
    }

    // Hover is not focus and must not read as it. The two states are drawn by
    // the same ring at two strengths, and a control that is both must draw the
    // focus one: the keyboard's position is the more important fact.
    //
    // ROUND 2: all four of those clauses are now read off the frame, on ONE
    // control, in the four states it can be in. The old version asserted that
    // hovering did not move the keyboard, which is true of a build where hover
    // and focus are drawn identically -- and that is the mutation a critic made
    // to `FocusRing`, with every test still passing.
    function test_21_hover_and_focus_are_two_states_not_three() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(6)
      suite.settleFrame()

      var ready = suite.targetNamed(garage, "READY UP")
      var leave = suite.targetNamed(garage, "LEAVE")
      verify(ready.stop.activeFocus, "READY UP is not stop 6")

      mouseMove(root, 0, 0)
      suite.settleFrame()
      var plain = grabImage(garage)

      var at = suite.centreOf(leave)
      mouseMove(root, at.x, at.y)
      verify(leave.hovered, "LEAVE is not hovered")
      verify(!leave.stop.activeFocus, "hovering moved the keyboard")
      verify(ready.stop.activeFocus, "hovering took focus off READY UP")
      suite.settleFrame()
      var hovered = grabImage(garage)

      mouseMove(root, 0, 0)
      garage.focusStop(7)
      verify(leave.stop.activeFocus, "LEAVE is not stop 7")
      suite.settleFrame()
      var focused = grabImage(garage)

      mouseMove(root, at.x, at.y)
      verify(leave.hovered && leave.stop.activeFocus, "LEAVE is not both at once")
      suite.settleFrame()
      var both = grabImage(garage)

      var box = suite.boxAround(leave, 12)

      // Hovering LEAVE, with the keyboard left where it was, changes LEAVE and
      // changes nothing else on the screen.
      var hoverChange = suite.diff(plain, hovered)
      verify(hoverChange.count > 100, "hovering LEAVE draws nothing")
      verify(suite.inside(hoverChange, box),
             "hovering LEAVE changed pixels at " + suite.boxText(hoverChange)
             + ", outside its own box " + suite.boxText(box))

      // Focusing it changes it too. Read inside LEAVE's box only: moving the
      // keyboard from READY UP to LEAVE takes a ring OFF READY UP as well, and
      // that difference is the feature working.
      verify(suite.diff(plain, focused, box).count > 100, "focusing LEAVE draws nothing")

      // THE CLAIM IN THE NAME: two states, and they do not look the same.
      var difference = suite.diff(hovered, focused, box)
      verify(difference.count > 100,
             "hover and focus are drawn the same: " + difference.count + " pixels"
             + " differ inside LEAVE's own box. This is the assertion a critic broke"
             + " by making FocusRing ignore `hover`, with every test still passing --"
             + " and a child who cannot tell where the keyboard is from where the"
             + " pointer is has three states drawn as one.")

      // AND NOT A THIRD STATE. Both at once is the focus picture, exactly.
      compare(suite.diff(focused, both).count, 0,
              "a control that is focused AND hovered is drawn as a third thing")
    }

    // AND THE SAME QUESTION OF EVERY CONTROL, ENUMERATED.
    //
    // Tests 20 and 21 read the frame, and they read it on two named controls.
    // This one asks the same thing of every click target the tree has, on the
    // two densest screens in the game -- 27 targets in the garage, 17 in the
    // settings screen -- so a control whose hover was never drawn, or whose
    // hover paints something 500 px away, fails without anybody adding a line
    // here. It is the pixel half of the piece's own doctrine: enumeration
    // rather than assertion, because the failure is never "this control is
    // wrong", it is "nobody thought about this control at all".
    function test_23_every_control_lights_under_the_pointer_and_lights_only_itself() {
      // ==================================================================
      // ROUND 4. THE SWEEP MOVED TO WHERE THE RISK IS, AND PAID FOR IT.
      // ==================================================================
      //
      // Round three's version walked the Garage and the Settings screen -- 47
      // controls, 29.5 seconds, 65 % of this file and 19 % of every QML second
      // in the repository -- and those are the two screens in the game with ZERO
      // printed key hints on them. A critic set `ui/parts/KeyHint.qml`'s hover
      // wash to `visible: false`, so every printed hint in the game stopped
      // lighting under the pointer, and all 27 cases passed. The hover promise
      // was enforced everywhere it does not live and nowhere it does.
      //
      // It walks the hints now: the race, the hand panel with a card chosen and
      // with the aim open, the countdown, and the question's own sheet -- plus
      // the garage, which is the screen the maintainer opens first and the
      // densest in the game. The Settings screen loses the PIXEL sweep and keeps
      // the cheap one (`test_32`), which is the trade this file can afford: its
      // rows are the same `SettingRow` component the garage draws, and its
      // buttons the same `ActionButton`.
      //
      // AND IT IS SWEPT AT 1280 x 720. The claim -- something inside the control
      // changes, nothing outside it does -- is about the picture and not about
      // the pixel count, and the cost of this case is two grabs and a full-frame
      // compare per control in JavaScript, which is quadratic in nothing but the
      // resolution. 1280 x 720 is 2.25 times fewer pixels than 1920 x 1080 and is
      // a size a child's machine actually is; it buys five more screens for
      // about the money the two cost. The window goes back afterwards.
      var wasWidth = root.width
      var wasHeight = root.height
      root.width = 1280
      root.height = 720
      // AND THE WORLD HOLDS STILL WHILE IT IS PHOTOGRAPHED. This case compares a
      // whole frame against a whole frame and calls any difference outside the
      // control's own box a hover leak, so a screen that moves on its own reports
      // a leak the size of the window: the race's road and karts did exactly
      // that. Three switches, all of them the screens' own -- the race's
      // `externalClock` (already trusted for the piece F strips), the countdown's
      // own beat length, and reduced motion, which is the design's accessibility
      // switch for "nothing pulses, nothing slides". None of them changes a
      // control, a key or an action.
      Store.setSetting("reducedMotion", true)
      race.externalClock = true
      var wasBeat = countdown.beatMs
      countdown.beatMs = 600000
      suite.settleFrame()
      var list = [{ "name": "Garage", "item": garage, "showing": "garage" },
                  { "name": "Countdown", "item": countdown, "showing": "countdown" },
                  { "name": "Race", "item": race, "showing": "race" },
                  { "name": "Picker, card chosen", "item": picker, "showing": "picker",
                    "prepare": "card 1" },
                  { "name": "Picker, aiming", "item": picker, "showing": "picker",
                    "prepare": "card 3" },
                  { "name": "Settings, reset asked", "item": settings, "showing": "settings",
                    "prepare": "RESET SETTINGS" }]
      var checked = 0
      var hintsSwept = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var screen = list[s].item
        focusPark.forceActiveFocus(Qt.OtherFocusReason)
        mouseMove(root, 0, 0)
        suite.settleFrame()
        var idle = grabImage(screen)
        var targets = suite.clickTargetsIn(screen)
        for (var i = 0; i < targets.length; i++) {
          var hit = targets[i]
          if (!suite.usable(hit, screen))
            continue
          // A BARRIER IS NOT A CONTROL AND MUST NOT LIGHT. It exists to swallow
          // a press -- it is the thing that makes the one question in the game
          // modal -- and a scrim that lit up under the pointer would be telling
          // the child the opposite of what the question is telling them.
          // `test_22` holds the same rule for a sign.
          if (hit.barrier === true)
            continue
          checked += 1
          if (hit.objectName === "clickKeyHint")
            hintsSwept += 1
          var at = suite.centreOf(hit)
          mouseMove(root, at.x, at.y)
          suite.settleFrame()
          var changed = suite.diff(idle, grabImage(screen))
          verify(changed.count > 0,
                 list[s].name + ": the pointer on \"" + hit.label + "\" changes"
                 + " nothing on the screen. A control a child cannot see with a"
                 + " mouse is a control they will not press.")
          var allowed = suite.controlBoxOf(hit, screen, 12)
          verify(suite.inside(changed, allowed),
                 list[s].name + ": the pointer on \"" + hit.label + "\" changed"
                 + " pixels at " + suite.boxText(changed) + ", outside its control's box "
                 + suite.boxText(allowed))
          mouseMove(root, 0, 0)
          suite.settleFrame()
        }
      }
      root.width = wasWidth
      root.height = wasHeight
      countdown.beatMs = wasBeat
      race.externalClock = false
      suite.settleFrame()
      verify(checked >= 40, "only " + checked + " controls were swept; the walk is not"
             + " seeing the tree")
      // AND THE HINTS WERE IN IT. The whole reason this case moved is that the
      // printed key hints -- the idiom whose own file promises "if it lights up
      // when you point at it, you can press it" -- were on none of the screens it
      // used to walk. A state list that drifted back to the two screens with no
      // hints on them has to fail here rather than go on reporting a green sweep
      // of the wrong thing.
      verify(hintsSwept >= 8,
             "only " + hintsSwept + " printed key hints were swept for their hover."
             + " A critic made every hint in the game stop lighting under the pointer"
             + " and this case passed, because it walked the two screens that have"
             + " none.")
    }

    // ==================================================================
    // ROUND 4. THE CHEAP HALF OF THE HOVER PROMISE, ON EVERY SCREEN.
    // ==================================================================
    //
    // `test_23` reads PIXELS, which is the only way to catch a hover that is
    // drawn 500 px away or not drawn at all, and it costs about a third of a
    // second per control -- so it walks six states and not nine, and the
    // Settings screen is one of the three it no longer walks.
    //
    // This is the half that costs nothing: every live click target on EVERY
    // state, asked whether the pointer on it turns its own hover flag on, and
    // whether it turns anybody else's on. It cannot see whether the flag is
    // PAINTED -- that is what the pixel sweep is for, and a critic broke exactly
    // that assertion once by making `ActionButton.hovered` constant false -- but
    // it does hold every screen to the wiring, and it is what stops the pixel
    // sweep's shorter state list from being a hole.
    function test_32_every_control_knows_the_pointer_is_on_it_on_every_screen() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var screen = list[s].item
        focusPark.forceActiveFocus(Qt.OtherFocusReason)
        var targets = suite.clickTargetsIn(screen)
        for (var i = 0; i < targets.length; i++) {
          var hit = targets[i]
          if (hit.barrier === true || !suite.usable(hit, screen))
            continue
          checked += 1
          var at = suite.centreOf(hit)
          mouseMove(root, at.x, at.y)
          verify(hit.hovered,
                 list[s].name + ": the pointer is on \"" + hit.label + "\" and the"
                 + " control does not know it. Everything a screen paints for hover"
                 + " reads this flag, so a control that never sets it can never light.")
          // AND NOBODY ELSE THINKS SO. A target that reports the pointer while
          // the pointer is somewhere else paints a hover state a child cannot
          // explain, and it is the shape of a control wired to the wrong box.
          for (var o = 0; o < targets.length; o++) {
            if (targets[o] === hit || !targets[o].hovered)
              continue
            // Two targets of ONE control -- a stepper is one stop with two
            // arrows and an inert face on it -- are allowed to answer together
            // for the same pointer. Two controls are not.
            verify(targets[o].stop !== null && targets[o].stop === hit.stop,
                   list[s].name + ": the pointer is on \"" + hit.label + "\" and \""
                   + targets[o].label + "\" reports it too, and they are not two"
                   + " targets of one control.")
          }
          mouseMove(root, 0, 0)
          verify(!hit.hovered,
                 list[s].name + ": \"" + hit.label + "\" still reports the pointer with"
                 + " the pointer in the corner of the window")
        }
      }
      verify(checked >= 60, "only " + checked + " controls were asked; the walk is not"
             + " seeing the tree")
    }

    // The ring itself: two states, two pictures. See the note on `ringLab`.
    function test_24_the_focus_ring_draws_hover_and_focus_differently() {
      root.showing = "rings"
      root.ringHover = false
      suite.settleFrame()
      var focusRing = grabImage(ringLab)

      root.ringHover = true
      suite.settleFrame()
      var hoverRing = grabImage(ringLab)

      var changed = suite.diff(focusRing, hoverRing)
      verify(changed.count > 50,
             "FocusRing draws its hover state and its focus state identically: "
             + changed.count + " pixels differ between the two. Hover and focus are"
             + " two facts -- where the pointer is, and where the keyboard is -- and"
             + " a child who cannot tell them apart has lost the second one. This is"
             + " the assertion a critic broke by making the component ignore `hover`,"
             + " with every test in this file still passing.")

      root.ringHover = false
      root.showing = "garage"
    }

    // A sign is not a control. RACE A FRIEND has no key and no Tab stop because
    // it can never act, and it must not become pressable just because it looks
    // like the two buttons under it -- a child pressing something that does
    // nothing is the same defect this piece is fixing, pointing the other way.
    //
    // ROUND 3. This named ONE sign, and a critic counted four more the garage
    // has -- the preset-signal tiles -- among the things "still unclickable",
    // with no way to tell a display that was decided from a control that was
    // forgotten. Every sign in the game declares `isSign` now, so this walks
    // them instead of naming one, and the four tiles and the four roster seats
    // are held to the rule with the card that was already here.
    //
    // WHY THEY ARE NOT MADE CONTROLS, since that is the other way to answer the
    // complaint. There is no key that sends a preset signal from the garage and
    // none that acts on a seat, so a click on either would be a MOUSE-ONLY path
    // -- which the design forbids exactly as squarely as the keyboard-only ones
    // this piece removes, and `test_01` would fail on it. Round three made the
    // tiles into controls and a critic had it taken out again, for the reason in
    // `ui/parts/SignalTile.qml`: four dead presses in the keyboard chain between
    // the settings and READY UP.
    function test_22_a_sign_takes_no_click_and_no_hover() {
      var list = suite.states()
      var checked = 0
      for (var s = 0; s < list.length; s++) {
        suite.enter(list[s])
        var screen = list[s].item
        var all = suite.itemsUnder(screen)
        for (var i = 0; i < all.length; i++) {
          var sign = all[i]
          if (sign.isSign !== true || !suite.drawn(sign, screen))
            continue
          checked += 1
          var targets = suite.clickTargetsIn(sign)
          for (var t = 0; t < targets.length; t++) {
            verify(!suite.usable(targets[t], screen),
                   list[s].name + ": the sign \"" + sign.signLabel + "\" accepts a"
                   + " click. It is laid out like a control and cannot act, and there"
                   + " is no key that does what pressing it would do, so a click on it"
                   + " would be a mouse-only path.")
            var at = suite.centreOf(targets[t])
            mouseMove(root, at.x, at.y)
            verify(!targets[t].hovered,
                   list[s].name + ": the sign \"" + sign.signLabel + "\" lights under"
                   + " the pointer as though it were a control")
            mouseMove(root, 0, 0)
          }
        }
      }
      verify(checked >= 9, "only " + checked + " signs were found across every state;"
             + " the walk is not seeing them")
    }
  }
}
