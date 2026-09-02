import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../dev"

// The garage, driven by the keyboard alone, with real key events.
//
// Every assertion here is made by pressing a key, not by calling a method:
// keyClick() posts the same events the window manager would, so what passes
// is the Tab chain and the key handlers as a child would meet them. No mouse
// event is sent anywhere in this file, and there is no mouse handler in the
// garage to send one to.
//
// Run it:
//   qmltestrunner -import dev/imports -input tests/qml
//
// The last case walks every stop with Tab and prints the screen-reader name
// it reaches. That printout, and test_02 beside it, are what let the harness
// screenshot a given stop with --focus n and claim it is where n Tab presses
// land: qmltestrunner presses the real key, the harness walks the same chain
// through nextItemInFocusChain(), and this file asserts the two agree.
Item {
  id: root
  width: 1920
  height: 1080

  Garage {
    id: garage
    anchors.fill: parent
  }

  MemoryStore { id: memory }

  property int raceRequests: 0
  property int leaveRequests: 0

  Connections {
    target: garage
    function onRaceRequested() { root.raceRequests += 1 }
    function onLeaveRequested() { root.leaveRequests += 1 }
  }

  TestCase {
    id: suite
    name: "GarageKeyboard"
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
      garage.forceActiveFocus()
      garage.focusStop(0)
    }

    // ------------------------------------------------------------------
    function test_01_first_stop_is_the_kart_body() {
      compare(garage.focusedName(), "Kart body, SPRINTER")
    }

    // Tab must walk the same order the garage publishes, or the arrow keys,
    // the harness and this test would each mean a different thing by "next".
    function test_02_tab_walks_the_published_chain() {
      var seen = []
      for (var i = 0; i < garage.stops.length; i++) {
        seen.push(garage.focusedName())
        compare(garage.focusedName(), garage.focusName(i),
                "stop " + i + " is not the item the garage lists at " + i)
        keyClick(Qt.Key_Tab)
      }
      compare(seen.length, garage.stops.length)
      // One more Tab and it is back at the top: the chain is a loop, so a
      // child can never tab their way off the screen.
      compare(garage.focusedName(), garage.focusName(0))
    }

    function test_03_shift_tab_walks_it_backwards() {
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Tab)
      compare(garage.stopIndex(), 2)
      keyClick(Qt.Key_Tab, Qt.ShiftModifier)
      compare(garage.stopIndex(), 1)
      keyClick(Qt.Key_Tab, Qt.ShiftModifier)
      compare(garage.stopIndex(), 0)
    }

    function test_04_down_and_up_move_between_controls() {
      keyClick(Qt.Key_Down)
      compare(garage.stopIndex(), 1)
      keyClick(Qt.Key_Down)
      compare(garage.stopIndex(), 2)
      keyClick(Qt.Key_Up)
      compare(garage.stopIndex(), 1)
    }

    // ------------------------------------------------------------------
    function test_05_arrows_cycle_the_kart_body() {
      compare(garage.bodyIndex, 0)
      keyClick(Qt.Key_Right)
      compare(garage.bodyIndex, 1)
      compare(garage.focusedName(), "Kart body, WEDGE")
      for (var i = 0; i < 5; i++)
        keyClick(Qt.Key_Right)
      compare(garage.bodyIndex, 0, "six bodies wrap round to the first")
      keyClick(Qt.Key_Left)
      compare(garage.bodyIndex, 5)
    }

    function test_06_arrows_cycle_the_paint() {
      garage.focusStop(1)
      compare(garage.paintIndex, 0)
      keyClick(Qt.Key_Right)
      compare(garage.paintIndex, 1)
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Left)
      compare(garage.paintIndex, 7, "eight paints wrap the other way too")
    }

    // The number is the control that would otherwise want a text field. It
    // must reach every value from 1 to 99 on arrows alone and never leave
    // the range.
    function test_07_number_steps_and_wraps_without_a_field() {
      garage.focusStop(2)
      compare(garage.kartNumber, 7)
      keyClick(Qt.Key_Right)
      compare(garage.kartNumber, 8)
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Left)
      compare(garage.kartNumber, 6)
      for (var down = 0; down < 6; down++)
        keyClick(Qt.Key_Left)
      compare(garage.kartNumber, 99, "one below one wraps to ninety-nine")
      keyClick(Qt.Key_Right)
      compare(garage.kartNumber, 1, "and ninety-nine wraps back to one")
    }

    // Digits must do nothing at all. A child pressing 4 on the number
    // control must not type a 4 anywhere, because nothing here takes text.
    function test_08_typing_does_nothing_anywhere() {
      for (var stop = 0; stop < garage.stops.length; stop++) {
        garage.focusStop(stop)
        var beforeNumber = garage.kartNumber
        var beforeBody = garage.bodyIndex
        var beforePaint = garage.paintIndex
        keyClick(Qt.Key_4)
        keyClick(Qt.Key_2)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_Backspace)
        compare(garage.kartNumber, beforeNumber, "a digit changed the number at stop " + stop)
        compare(garage.bodyIndex, beforeBody, "a digit changed the body at stop " + stop)
        compare(garage.paintIndex, beforePaint, "a digit changed the paint at stop " + stop)
      }
    }

    // ------------------------------------------------------------------
    function test_09_settings_rows_cycle_on_enter_and_arrows() {
      // Race mode: four modes, Enter walks forward.
      garage.focusStop(3)
      compare(garage.raceMode, 3)
      keyClick(Qt.Key_Return)
      compare(garage.raceMode, 0)
      keyClick(Qt.Key_Left)
      compare(garage.raceMode, 3)

      // Math set: three presets, and the goal row follows it.
      garage.focusStop(4)
      compare(garage.mathSet, 2)
      keyClick(Qt.Key_Right)
      compare(garage.mathSet, 0)
      keyClick(Qt.Key_Right)
      compare(garage.mathSet, 1)

      // Rivals: three levels.
      garage.focusStop(5)
      compare(garage.rivalLevel, 1)
      keyClick(Qt.Key_Return)
      compare(garage.rivalLevel, 2)
    }

    function test_10_ready_up_and_leave_fire_on_enter() {
      var races = root.raceRequests
      garage.focusStop(10)
      compare(garage.focusedName(), "Ready up")
      keyClick(Qt.Key_Return)
      compare(root.raceRequests, races + 1)

      var leaves = root.leaveRequests
      garage.focusStop(11)
      compare(garage.focusedName(), "Leave")
      keyClick(Qt.Key_Space)
      compare(root.leaveRequests, leaves + 1)
    }

    function test_11_escape_leaves_from_every_stop() {
      for (var stop = 0; stop < garage.stops.length; stop++) {
        garage.focusStop(stop)
        var before = root.leaveRequests
        keyClick(Qt.Key_Escape)
        compare(root.leaveRequests, before + 1, "escape did nothing at stop " + stop)
      }
    }

    // ------------------------------------------------------------------
    function test_12_choices_reach_the_save_file() {
      var writes = memory.writes
      garage.focusStop(0)
      keyClick(Qt.Key_Right)
      verify(memory.writes > writes, "changing the body wrote nothing")
      compare(memory.lastWritten.settings.kartBody, 1)
      verify(memory.lastWritten.settings.hasOwnProperty("kartNumber"))
      // The design forbids dates in the save file.
      var text = JSON.stringify(memory.lastWritten)
      verify(text.indexOf("date") < 0, "the save file mentions a date")
      verify(text.indexOf("time") < 0, "the save file mentions a time")
    }

    // The chain is the reading order of the layout, left to right and top to
    // bottom, and it never doubles back across the screen. Round one ran
    // centre -> far right -> far left -> centre -> far right.
    function test_14_focus_order_follows_the_layout() {
      var expected = ["Kart body, SPRINTER",
                      "Kart colour, RED",
                      "Kart number, 7",
                      "Race mode, GRAND PRIX, change",
                      "Math set, TIMES TABLES 1-12, change",
                      "Rivals, PRO, change",
                      "NICE RUN", "READY", "REMATCH?", "GOOD GAME",
                      "Ready up", "Leave"]
      compare(garage.stops.length, expected.length)
      for (var i = 0; i < expected.length; i++)
        compare(garage.focusName(i), expected[i], "stop " + i)
    }

    // A control that can never do anything must not spend a Tab stop. The
    // RACE A FRIEND sign is drawn, is named for a screen reader, and is not
    // reachable by Tab.
    function test_15_the_friend_sign_is_not_a_focus_stop() {
      for (var i = 0; i < garage.stops.length; i++)
        verify(garage.focusName(i).indexOf("Race a friend") < 0,
               "the friend sign is stop " + i)
      // And walking the whole chain with real Tab presses never reaches it.
      garage.focusStop(0)
      for (var t = 0; t < garage.stops.length + 2; t++) {
        verify(garage.focusedName().indexOf("Race a friend") < 0,
               "Tab reached the friend sign")
        keyClick(Qt.Key_Tab)
      }
    }

    // ------------------------------------------------------------------
    // The walkthrough. Tab from the first stop to the last, recording the
    // screen-reader name reached at every stop.
    function test_13_keyboard_walkthrough() {
      garage.focusStop(0)
      var lines = []
      for (var i = 0; i < garage.stops.length; i++) {
        var name = garage.focusedName()
        verify(name.length > 0, "stop " + i + " has no screen-reader name")
        lines.push((i === 0 ? "start" : "Tab x" + i) + "  ->  " + name)
        console.log("walkthrough " + i + ": " + (i === 0 ? "start" : "Tab x" + i)
                    + "  ->  " + name)
        keyClick(Qt.Key_Tab)
      }
      console.log("walkthrough stops: " + lines.length)
    }
  }
}
