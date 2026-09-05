import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts"
import "../../dev"
import "../../dev/KeyHints.js" as KeyHints

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
      settings.pending = ""
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
        if (suite.usable(targets[i], screen))
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
              { "name": "Countdown", "item": countdown, "showing": "countdown" }]
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
          checked += 1
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
      grabImage(root)
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
    function test_19_no_destructive_control_acts_twice_on_a_double_click() {
      var list = suite.states()
      var checked = 0
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
          suite.enter(list[s])
        }
      }
      verify(checked >= 3, "only " + checked + " destructive controls were found across"
             + " every state; the walk is not seeing them")
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

    function test_20_a_control_lights_under_the_pointer_and_only_that_control() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(0)

      var ready = suite.targetNamed(garage, "READY UP")
      var leave = suite.targetNamed(garage, "LEAVE")
      verify(ready !== null && leave !== null)
      verify(!ready.hovered && !leave.hovered, "something is hovered before the pointer moved")

      var at = suite.centreOf(ready)
      mouseMove(root, at.x, at.y)
      verify(ready.hovered, "READY UP does not light under the pointer")
      verify(!leave.hovered, "LEAVE lights when the pointer is on READY UP")

      var elsewhere = suite.centreOf(leave)
      mouseMove(root, elsewhere.x, elsewhere.y)
      verify(!ready.hovered, "READY UP stays lit after the pointer left it")
      verify(leave.hovered)

      mouseMove(root, 0, 0)
      verify(!ready.hovered && !leave.hovered,
             "a control is still lit with the pointer in the corner")
    }

    // Hover is not focus and must not read as it. The two states are drawn by
    // the same ring at two strengths, and a control that is both must draw the
    // focus one: the keyboard's position is the more important fact.
    function test_21_hover_and_focus_are_two_states_not_three() {
      root.showing = "garage"
      garage.forceActiveFocus()
      garage.focusStop(6)

      var ready = suite.targetNamed(garage, "READY UP")
      var leave = suite.targetNamed(garage, "LEAVE")
      verify(ready.stop.activeFocus, "READY UP is not stop 6")

      var at = suite.centreOf(leave)
      mouseMove(root, at.x, at.y)
      verify(leave.hovered, "LEAVE is not hovered")
      verify(!leave.stop.activeFocus, "hovering moved the keyboard")
      verify(ready.stop.activeFocus, "hovering took focus off READY UP")
    }

    // A sign is not a control. RACE A FRIEND has no key and no Tab stop because
    // it can never act, and it must not become pressable just because it looks
    // like the two buttons under it -- a child pressing something that does
    // nothing is the same defect this piece is fixing, pointing the other way.
    function test_22_a_sign_takes_no_click_and_no_hover() {
      root.showing = "garage"
      garage.forceActiveFocus()

      var targets = suite.clickTargetsIn(garage)
      var sign = null
      for (var i = 0; i < targets.length; i++) {
        if (String(targets[i].label).toLowerCase().indexOf("race a friend") >= 0)
          sign = targets[i]
      }
      verify(sign !== null, "the sign's click target is not in the tree at all")
      verify(!sign.enabled, "the RACE A FRIEND sign accepts a click")

      var at = suite.centreOf(sign)
      mouseMove(root, at.x, at.y)
      verify(!sign.hovered, "the sign lights under the pointer as though it were a control")
    }
  }
}
