import QtQuick
import "parts"
import "parts/CarMeta.js" as CarMeta

// The garage: the screen the child lands on, and the only place a race is
// configured.
//
// It follows the Garage Room mock's composition -- title bar, policy rail,
// stall on the left, roster on the right, settings, signals and the ready
// control along the bottom -- and drops what the mock's multiplayer content
// implies. There is no invite code, no approved-friend key, no
// device-verified mark, because this plugin has no network code at all; a
// RACE A FRIEND tile stands where they were and says what would be needed.
// And there is no field to type into anywhere on this screen: no name, no
// number entry, no search. The kart number runs 1 to 99 on arrows.
//
// Everything scales from one factor against a 1920 x 1080 reference, so the
// composition is identical at 1366 x 768 and at 2560 x 1440 and only the
// pixel sizes change.
//
// ===================================================================== ROUND 10
//
// THE MAINTAINER PLAYED IT AND SAID THREE THINGS ABOUT THIS SCREEN.
//
//   "The menus there are still too busy and last I used them did not let a
//    mouse click the buttons. Declutter the menu, make everything clickable
//    and make the page an exciting, polished, and professional hook to reflect
//    the game well and get kids excited to start their first race."
//
// The middle one is the interesting one, because it is FALSE and it is still a
// defect. Piece M landed after he last played: this screen has twenty-seven
// live click targets, both steppers, all eight swatches and every settings row
// on both the row and its chip, and `dev/Harness.qml --print-controls` prints
// the parity table in both directions and exits non-zero if any of it is a lie.
// He could not tell, and a control a child cannot tell is pressable is a
// control they will not press. So half this round is not making clicking work.
// It is making it OBVIOUS, before the pointer arrives:
//
//   1. The screen says so, first, in the band a reader reads first:
//      `CLICK  ANYTHING THAT LIGHTS UP`, ahead of the four keys. Until this
//      round the only sentence about input on the garage was a keyboard legend,
//      on a screen where every single thing is clickable.
//   2. A pressable face is drawn PROUD of the card it sits on, at rest, with a
//      lit top edge (`Theme.duskPressFace` / `duskPressEdge`). The stepper
//      arrows and the CHANGE chips were 5 % of a border tone on a hairline.
//   3. Things that are NOT pressable stop borrowing a control's clothes: the
//      two fixed rows lose the cream value the three live ones keep, so the
//      loud rows are exactly the rows that do something.
//   4. Something visibly happens the moment a child clicks a paint or a body:
//      the car lifts and settles and the turntable pings. See `celebrate()`.
//
// AND THE DECLUTTER, ITEM BY ITEM. A previous critic counted 299 drawn items
// and 39 translucent rounded rectangles on this screen. What went:
//
//   * the `OFFLINE` badge -- `docs/open-questions.md` §5.4, the maintainer's
//     own list: it reads as broken, and the rail already says THIS COMPUTER
//     ONLY, which is the same fact in words a parent and a child both parse.
//   * the policy rail itself. It was a second full-width band under the title
//     carrying three chips, one of which (`SOLO GARAGE`) says what THIS
//     COMPUTER ONLY says and one of which (`PRESET SIGNALS`) named a panel
//     that names itself. One fact and the legend survive, in the title band,
//     and 70 px of room comes back to the bay.
//   * the PRESET SIGNALS board -- a 500 x 268 panel, a heading, four tiles and
//     a two-line paragraph, in the centre of the bottom edge, about a thing
//     that happens in a race the child has not started yet. The catalogue the
//     design asks for is still here, as one strip in the footer of the board
//     the race is set up on, which is where it belongs: it is a note about the
//     race, not a third region of the screen.
//   * three boards became one. The kart card and the settings board were two
//     cards of different widths stacked with a gap; they are one board now,
//     ruled into YOUR KART / THE RACE / the signal strip, so the left of the
//     screen is one object in the room instead of three.
//   * `RACE A FRIEND` went from a 602 x 112 block with a 27 px heading to one
//     quiet line. It is a notice about something that does not exist yet, and
//     it was the third loudest thing in the frame.
//   * the three rival seats are drawn at 0.86 of the child's own seat. Nothing
//     is removed from them -- the design lists kart, colour, number, lamp and
//     level badge, and `tst_garage_keyboard.qml` checks all four karts are
//     drawn at full strength -- but the child's row is now visibly the row
//     about the child.
//
// What that bought went to the two things a child is here for: the car, which
// now has the whole middle and bottom of the frame with nothing standing in
// it, and READY UP, which is 1.6x taller than it was and is the only large
// filled object on the screen.
FocusScope {
  id: garage

  // The overlay hands focus here; the harness does the same.
  readonly property Item focusTarget: stops.length > 0 ? stops[0] : null

  signal raceRequested()
  signal leaveRequested()

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  // ROUND 12: the floor is 9, not 8. At 1024 x 600 the scale factor is 0.533,
  // so a 14 px label lands on 7.5 and a 13 px caption on 6.9 -- both of which
  // the old floor rounded up to 8, and a critic reading the shipped frame called
  // the whole left column "an unreadable grey texture" for 7 to 11 year olds.
  // Nine is what the narrowest strip on this screen (the four signal captions,
  // which have to fit `GOOD GAME` into a quarter of the board) will take without
  // overflowing, and it is checked by rendering, not by arithmetic. The rest of
  // the answer is fewer strings: `1 OF 1`, `FIXED`, `CHANGE` twice and the
  // privacy notice are gone this round.
  function fs(v) { return Math.max(9, Math.round(v * s)) }

  // ------------------------------------------------------------ race setup
  readonly property var modeNames: ["PRACTICE", "TIME TRIAL", "GHOST", "GRAND PRIX"]
  readonly property var setNames: ["TIMES TABLES 2-5", "TIMES TABLES 2-10", "TIMES TABLES 1-12"]
  readonly property var setLaps: [4, 9, 12]
  // §5.4, in the maintainer's own words: "`MIDNIGHT GARAGE` for a sunset
  // track. `GOLDEN HOUR`, or `THE PIT`." The whole art direction of this build
  // is called Golden Hour, the sky behind this room is a sunset, and the
  // terminal on the wall already says WELCOME TO THE PIT -- so the track takes
  // the first of the two and the room keeps the second.
  readonly property string circuit: "GOLDEN HOUR"

  readonly property int bodyIndex: Store.setting("kartBody")
  readonly property int paintIndex: Store.setting("kartPaint")
  readonly property int kartNumber: Store.setting("kartNumber")
  readonly property int rivalLevel: Store.setting("rivalLevel")
  readonly property int raceMode: Store.setting("raceMode")
  readonly property int mathSet: Store.setting("mathSet")
  readonly property bool rivalsRace: raceMode === 3
  readonly property bool reducedMotion: Store.setting("reducedMotion") === true

  function cycle(key, delta, count) {
    Store.setSetting(key, ((Store.setting(key) + delta) % count + count) % count)
  }

  function stepNumber(delta) {
    var next = Store.setting("kartNumber") + delta
    if (next > 99)
      next = 1
    if (next < 1)
      next = 99
    Store.setSetting("kartNumber", next)
  }

  // ------------------------------------------------- the car answers a press
  //
  // The complaint this round exists to answer is "clicking things did not do
  // much", and on this screen the honest reading of it is that the RESULT of a
  // press was a two-pixel tick on a swatch and a repaint of a 411 px car that
  // is already there. A child pressing a colour should see the garage react.
  //
  // It is called from the three controls that change the car -- not from the
  // property changing -- so that loading a save file, seeding the harness or
  // reloading the store does not fire a celebration nobody caused. Every one
  // of the three is the same function the key handler calls, so the click and
  // the arrow key celebrate identically; `test_29` crosses the two routes over
  // and would fail if they did not.
  //
  // Reduced motion switches it off entirely, by the design's Accessibility
  // rule ("Reduced motion removes all shake, lurch, and streak lines"), and
  // the ping is not drawn at all when it is not running, so at rest this costs
  // one comparison against zero.
  property real heroLift: 0
  property real ping: 0

  function celebrate() {
    if (garage.reducedMotion)
      return
    flourish.restart()
  }

  SequentialAnimation {
    id: flourish

    PropertyAction { target: garage; property: "ping"; value: 1 }
    ParallelAnimation {
      NumberAnimation {
        target: garage; property: "heroLift"
        from: 0; to: -garage.px(9); duration: 70; easing.type: Easing.OutQuad
      }
    }
    ParallelAnimation {
      NumberAnimation {
        target: garage; property: "heroLift"
        to: 0; duration: 190; easing.type: Easing.OutQuad
      }
      NumberAnimation {
        target: garage; property: "ping"
        to: 0; duration: 230; easing.type: Easing.InQuad
      }
    }
  }

  // THE CONTROL THIS SCREEN EXISTS FOR, PUBLISHED BY NAME.
  //
  // ROUND 12. `ui/Game.qml` used to find it by scanning `stops` for a spoken
  // name beginning with "READY", falling back to the first stop. That is a
  // string match on a label a designer is free to change, and this round changed
  // it: the button now says START THE RACE, and under the old matcher every
  // arrival on the garage -- including the one straight after a race -- would
  // silently have landed on the kart-body stepper instead. The screen names its
  // own primary control; nothing outside has to guess.
  readonly property Item startStop: readyButton

  // ---------------------------------------------------------- focus chain
  // The same items, in the same order, that Tab walks. Kept as a list so the
  // arrow keys, the harness and the keyboard test all agree on what "the next
  // control" means.
  // Reading order, left to right and top to bottom, and nothing else in it.
  // Round one ran centre -> far right -> far left -> centre -> far right and
  // crossed the screen three times, because the chain followed the order the
  // items happen to be declared in rather than the order they are laid out.
  // The stall's own controls come first (body on the left of the bay, then
  // paint and number on the right of it), then the bottom band from left to
  // right: the settings rows, the four signals, and the two actions.
  //
  // RACE A FRIEND is not here. It was stop 03, between the stall and the
  // settings, and it is a sign that can never do anything: focusing it spent
  // a Tab stop and a child's attention on a control with no action behind it.
  //
  // ROUND-4: nor are the four signal tiles, which were stops 06 to 09. The
  // panel's own caption says what it is -- "These are the only signals in a
  // race. The rivals send them too." -- and a legend is not a control. Four
  // non-actionable display tiles between the settings and the ready control
  // were four dead presses for a child and four focusable objects with no
  // action for a screen reader. The panel keeps its heading and its caption
  // and reads as one region; the chain is twelve stops minus those four.
  readonly property var stops: [bodyStepper, paintGrid, numberStepper,
                                modeRow.focusItem, mathRow.focusItem, rivalRow.focusItem,
                                readyButton, leaveButton]

  function stopIndex() {
    for (var i = 0; i < stops.length; i++)
      if (stops[i] && stops[i].activeFocus)
        return i
    return -1
  }

  function moveFocus(delta) {
    var current = stopIndex()
    var count = stops.length
    var next = current < 0 ? (delta > 0 ? 0 : count - 1)
                           : ((current + delta) % count + count) % count
    stops[next].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason)
  }

  function focusStop(index) {
    var count = stops.length
    stops[((index % count) + count) % count].forceActiveFocus(Qt.TabFocusReason)
  }

  // The screen-reader name of a stop, read back off the control itself so the
  // keyboard walkthrough reports what a screen reader would actually say
  // rather than a second list that could drift from it.
  function focusName(index) {
    var item = stops[index]
    if (!item)
      return ""
    try {
      return String(item.Accessible.name)
    } catch (error) {
      return ""
    }
  }

  // The stop that currently has focus, as a name. Empty when focus is
  // somewhere the garage does not own.
  function focusedName() {
    var index = stopIndex()
    return index < 0 ? "" : focusName(index)
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Garage"
  Accessible.description: "Set up your kart and the race, then ready up. Click anything, or Tab moves, arrows change, Enter chooses, Escape leaves."

  // Escape backs out; Tab, Backtab, Up and Down all walk `stops`.
  //
  // ROUND-8: AND UNTIL THIS ROUND THIS BLOCK WAS UNREACHABLE.
  //
  // Round six added the Tab branch below and round seven reported, honestly,
  // that making it unreachable (`false &&`) still left all twenty keyboard
  // tests passing. A critic then found a second mutation of the same class --
  // `var back = false`, Shift+Tab always forward -- also leaving twenty
  // green, and called it a user-visible regression the suite could not see.
  //
  // ROUND-9 CORRECTION. Round eight wrote here that this was "neither a test
  // weakness nor a regression", and both halves of that were too strong. The
  // code was dead AND `test_03_shift_tab_walks_it_backwards` could not tell
  // the product from the environment: those are one fact seen from two sides,
  // not a refutation of one by the other. And "not a regression" held only
  // while every stop stayed in Qt's implicit chain -- the moment anything took
  // them out, which is exactly what round eight then did, `var back = false`
  // became a live user-visible regression that round seven's suite still could
  // not have seen. The round-seven critic's sentence and the round-eight
  // diagnosis are both true.
  //
  // The diagnosis itself stands. Instrumenting this
  // handler shows it is entered ZERO times in the whole twenty-test run:
  // Qt Quick delivers a key to the focused item, and when that item has
  // `activeFocusOnTab` set and ignores Tab, the delivery agent runs its own
  // focus-chain navigation and consumes the event THERE -- before it can
  // bubble to this ancestor. Key_Shift, which is not a navigation key, does
  // arrive here; Key_Tab never does. So both mutations were mutations of dead
  // code, no test could kill them, and Tab was in fact being walked by Qt's
  // implicit chain, which happened to agree with `stops` because the
  // declaration order happened to match the layout order.
  //
  // The fix is in the product, not in the tests. Every stop now carries
  // `activeFocusOnTab: false`, so nothing swallows Tab on the way up and this
  // handler is the ONE thing that moves focus on this screen -- 63 entries in
  // the same run, counted the same way. With that, `false &&` fails four tests
  // and `var back = false` fails three.
  // `tests/qml/tst_garage_keyboard.qml` also asserts the
  // invariant directly, so a stop that quietly rejoins Qt's chain -- and
  // silently kills this code again -- fails a test rather than passing one.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      garage.leaveRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      // Shift+Tab arrives as Key_Backtab on some platforms and as Key_Tab
      // with the Shift modifier on others, so both are read here rather than
      // trusting whichever one this machine happens to send.
      var back = event.key === Qt.Key_Backtab
                 || (event.modifiers & Qt.ShiftModifier) !== 0
      garage.moveFocus(back ? -1 : 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      garage.moveFocus(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      garage.moveFocus(-1)
      event.accepted = true
    }
  }

  // ROUND-9: THE ROOM IS THE PAGE.
  //
  // Round seven painted this page a warm near-black and round eight put a
  // Canvas on it that FAKED the room's light -- a radial keyed on the door
  // opening's centre, a floor bounce along the bottom edge, a corner falling
  // away. It measured well (32.2 % of the frame, 1.58x at the opening falling
  // to 1.21x across it) and it was still a gradient standing in for a room,
  // because the room itself was a 1226 x 530 picture in the top-left quadrant
  // with a 400 x 290 door cut in it.
  //
  // The stall is now the page. `GarageStall` fills this card, the sunset is
  // the backdrop of the whole screen, and every panel here -- the title, the
  // kart card, the roster, the board along the bottom -- is an object standing
  // in that room. The faked light is deleted: what falls on this page is the
  // room's own sky, hills, threshold and floor, drawn once.
  //
  // The card itself is therefore transparent. A 0.30 film of `duskSurface`
  // over the sunset is the same mistake the page light was, one layer up.
  Panel {
    id: page
    anchors.fill: parent
    anchors.margins: garage.px(16)
    color: "transparent"
    border.color: Theme.lineStrong
    clip: true

    GarageStall {
      id: stall
      objectName: "garageStall"
      anchors.fill: parent
      cornerRadius: Theme.cornerRadius

      // ROUND 11: THE WALL ENDS WHERE THE BOARD ENDS.
      //
      // The room draws a jamb -- a warm hairline and a dark return -- down the
      // right edge of its left wall, and the board below leans on that wall.
      // While the wall's edge was a constant (300 view-box units) and the
      // board's width was another constant (560 px), the two agreed at no
      // window size at all: at 1920 x 1080 the board's right edge stood at
      // x = 595 and the jamb at x = 488, so the board crossed out of the room's
      // dark wall zone into the lit bay, the jamb ran into the board's top edge
      // and never came out, and the board's own edge was against masonry for
      // 256 px and against the floor grid for the next 325 px.
      //
      // `stall` is anchored to `page` and `board` is a child of `page`, so both
      // are in the same coordinate space and one division converts. The wall's
      // right edge and the board's right edge are now the same line by
      // construction. Nothing here can loop: `unit` is a function of the page's
      // size only, and the board's x and width are functions of `garage.s`.
      // ROUND 12: AND THE BOARD IS INSET FROM IT, BY THE SAME GUTTER IT HAS ON
      // THE OTHER SIDE.
      //
      // Round eleven made the jamb and the board's right edge ONE LINE, which
      // fixed the board standing out in the open bay -- and created the defect a
      // critic then measured: the wall's lit rim highlight runs down the masonry
      // from y = 118 and STOPS DEAD at y = 466, where the board's top-left
      // corner reaches it, and never comes out below. Under that line the
      // board's own flat unlit edge became the wall's edge, so the wall visibly
      // changed material two thirds of the way down its own height. The gutters
      // said the same thing: 22 px of wall showing on the board's left, 1 px on
      // its right. Nothing was inset; the board was simply shoved until it was
      // flush with the lit edge.
      //
      // The wall now ends one gutter PAST the board, and that gutter is the
      // board's own left margin, so the board is a board leaning on a wall with
      // the same air on both sides and the room's brightest warm line runs
      // uninterrupted from the door head to the floor. It also moves the tyre
      // stack, which is placed at `wallX + 6`, off the board's edge: a critic
      // measured it crowding the panel at all three sizes, never touching and
      // never clearing.
      wallX: stall.unit > 0
             ? (board.x + board.width + page.contentX) / stall.unit : 368

      // AND THE DOOR HEAD IS THE TITLE BAND'S FLOOR.
      //
      // The title band has no panel under it -- round ten took the policy rail
      // away and gave the room back, which was right -- so its strings sit
      // straight on the room. The sky's top stop was picked for exactly that
      // ("5.8:1 against this", `GarageStall.qml`). But the masonry ran up past
      // the door head to the top of the frame, so the left third of the band
      // sat on WALL, and `GARAGE` -- drawn in the theme accent, which this game
      // may not restate -- measured 1.58:1 against the jamb the moment the wall
      // moved to meet the board. Under the old constants it cleared that jamb
      // by one pixel, and round ten's 69-of-69 was read off that pixel.
      //
      // Binding the head to the title's own hairline makes the band's ground
      // one thing across its whole width: rolled slats and the beam under them,
      // with the beam's trim landing on the rule. The wall starts below it.
      doorTop: stall.unit > 0
               ? (titleBar.y + titleBar.height - stall.originY) / stall.unit
               : -84
    }

    readonly property int pad: garage.px(20)
    readonly property int contentX: pad
    readonly property int contentW: width - pad * 2

    // =====================================================  title band
    //
    // ONE BAND, NOT TWO. Round nine had a title bar and, 14 px below it, a
    // full-width policy rail: two horizontal chrome objects across the top of
    // a picture whose subject is a sunset. The rail carried three chips and a
    // legend; of the three, SOLO GARAGE said what THIS COMPUTER ONLY says and
    // PRESET SIGNALS named a panel two feet below it that named itself. What a
    // parent glancing at this screen wants is the one fact -- nothing here
    // leaves this computer -- and what the child wants is to know they can
    // click. Both fit beside the title, and the rail's 56 px plus its 14 px of
    // gap go back to the room.
    Item {
      id: titleBar
      x: page.contentX
      y: page.pad
      width: page.contentW
      height: garage.px(78)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: garage.px(16)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "TURBO TABLES"
          color: Theme.cream
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: garage.fs(46)
          font.letterSpacing: garage.px(4)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "//"
          // ROUND 10, AND IT WAS ALREADY BELOW THE FLOOR BEFORE THIS ROUND
          // TOUCHED IT. Round eight took it from 0.6 alpha to full strength for
          // exactly this reason -- "a floor that has an exception is not a
          // floor" -- and full-strength accent was still 4.01:1 at 981f535,
          // because these two glyphs land on the bay's own lit threshold and
          // the accent is a mid-value blue. Measured on the shipped frame, not
          // on the surface it is nominally over. Cream reads 9:1 on the same
          // pixels and the accent keeps the two places the design gives it --
          // the focus ring and the thing the pointer is on -- plus GARAGE,
          // which lands further into the bay and measures clear.
          color: Theme.cream
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: garage.fs(34)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "GARAGE"
          color: Theme.accent
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: garage.fs(34)
          font.letterSpacing: garage.px(3)
        }
      }

      Column {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: garage.px(9)

        // The one policy fact. §5.4 retires the `OFFLINE` chip that used to
        // stand in the opposite corner saying the same thing in a word a child
        // reads as "broken"; this is the sentence that survives, and it is now
        // the only place the fact is said.
        Row {
          anchors.right: parent.right
          spacing: garage.px(10)

          PixelIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: garage.px(22)
            height: width
            art: Glyphs.monitor
            color: Theme.accent
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "THIS COMPUTER ONLY"
            color: Theme.accent
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: garage.fs(17)
            font.letterSpacing: garage.px(2)
          }
        }

        // PIECE M -- THIS IS A LEGEND, NOT A ROW OF CONTROLS.
        //
        // Every printed key hint in this game is a control except the ones in a
        // rail like this: it states the whole screen's input from the title
        // band rather than offering an action at the place the action happens,
        // and there is no honest mouse equivalent of "TAB moves" other than
        // pointing at the thing you want, which is what the mouse already does.
        // An on-screen Tab key would be a second way to do everything and a
        // control a child could press that changes nothing they were looking
        // at. So: no box, no border, no fill -- see ui/parts/KeyLegend.qml,
        // which declares itself as the one exemption in the game so the check
        // that forbids a dead printed key can name it rather than not see it.
        //
        // ROUND 10 -- AND IT LEADS WITH THE MOUSE NOW.
        //
        // This screen's every control has been clickable since piece M and the
        // only sentence about input on it was four keyboard hints. The
        // maintainer played it and reported that a mouse could not click the
        // buttons. `CLICK  ANYTHING THAT LIGHTS UP` is the rule the whole
        // hover grammar is built on, said once, in the first band a reader
        // reads, in the same caption voice as the keys beside it. It is not a
        // key, so it is not a promise about a keycap and the printed-key check
        // has nothing to catch: it is the promise the pointer makes.
        KeyLegend {
          anchors.right: parent.right
          gap: garage.px(18)
          textSize: garage.fs(15)
          letterSpacing: garage.px(1)
          // MEASURED. The legend used to sit on the policy rail's own sunken
          // fill; with the rail gone it sits on the room, whose wall runs from
          // #541648 to #6a2448 across the band. `textLabel` is 0.80 alpha and
          // measured 4.13:1 on the brightest of that, so both halves are full
          // strength here and the key is told from the action by weight and by
          // hue instead of by alpha.
          keyColor: Theme.cream
          actionColor: Theme.text
          groups: [ { key: "CLICK", what: "ANYTHING THAT LIGHTS UP" },
                    { key: "TAB", what: "MOVE" },
                    { key: "ARROWS", what: "CHANGE" },
                    { key: "ENTER", what: "CHOOSE" },
                    { key: "ESC", what: "LEAVE" } ]
        }
      }

      // The band ends somewhere. One hairline instead of a second filled bar.
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.lineStrong
      }
    }

    // =====================================================  main geometry
    readonly property int mainY: titleBar.y + titleBar.height + garage.px(14)
    readonly property int bottomEdge: height - pad
    // The right-hand column: the four seats, the friend notice, and the two
    // actions, as ONE column running the height of the page. Round nine had
    // the seats in the main row and the actions in the bottom band, which made
    // the bottom of the screen three regions wide and pinned READY UP to the
    // height the settings board happened to be.
    readonly property int rightW: garage.px(556)
    readonly property int rightX: contentX + contentW - rightW

    // The turntable's answer to a press. Declared BEFORE the car, because it
    // is paint on the ground and the car is standing on the ground: a ring of the work light's own tone
    // running out across the plinth and fading. Not drawn at all unless it is
    // running, so the idle cost of it is one comparison; not drawn at all
    // under reduced motion, because `celebrate()` never starts it there.
    Rectangle {
      id: pingRing
      visible: garage.ping > 0
      readonly property real grow: 1.0 + 0.34 * (1 - garage.ping)
      width: Math.round(stall.vs(stall.daisRadius) * 2 * grow)
      height: Math.round(stall.vs(stall.daisRy) * 2 * grow)
      x: Math.round(stall.vx(stall.daisX) - width / 2)
      y: Math.round(stall.vy(stall.daisCy) - height / 2)
      radius: height / 2
      color: "transparent"
      border.width: Math.max(1, garage.px(3))
      border.color: Theme.amberGlow
      opacity: garage.ping * 0.7
    }

    // ------------------------------------------------- the kart on the dais
    // PIECE C: the car on the turntable is a cell of its baked sheet -- the
    // stall camera, yaw 0, the 1.0 row at a whole-number upscale -- stood on
    // the dais by its contact point. The same sheet draws the roster row
    // below, the countdown and the race, so the car the child builds here is
    // the car everywhere else, not a resemblance of it.
    //
    // ROUND-9, AND IT IS A CAP, NOT A CHOICE. The plan's Composition line
    // wants the hero "low-centre, large" and the bar has it at 48 % x 41 % of
    // the frame; ours is 411 x 195 px, 21 % x 18 %, and it was 21 % x 18 % in
    // round seven and round eight too. That is not this piece declining to
    // grow it. `CarMeta.fit` clamps the whole-number upscale to 3
    // (`ui/parts/CarMeta.js`), `CarSprite` clamps it again to 3
    // (`ui/parts/CarSprite.qml`), and the 1.0 row's cell is 192 px wide -- so
    // 576 px of cell, of which the coupe at yaw 6 inks 411, is the largest a
    // car can be drawn ANYWHERE in this game at any screen size. Both files
    // are piece C's, both are outside piece 3's scope, and
    // `tests/qml/tst_carsprite.qml` asserts `pixelScale === 3` on this very
    // item. What piece 3 CAN do is put the hero low and centre, against the
    // glow, with a plinth sized to it, and CLEAR THE FRAME AROUND IT -- which
    // is what round ten's declutter spends its winnings on: the middle and the
    // bottom-centre of this screen now hold the car, the plinth and the floor
    // and nothing else at all. The width is piece C's to give.
    // The sun's edge on the hero, UNDER it: see `parts/CarLight.qml`, `pass`.
    Loader {
      id: heroRim
      x: heroKart.x
      y: heroKart.y
      source: "parts/CarLight.qml"
      onLoaded: {
        item.host = heroKart
        item.pass = "rim"
      }
    }

    CarSprite {
      id: heroKart
      objectName: "heroCar"
      readonly property var fit: CarMeta.fit(stall.vs(stall.kartWidth))
      x: Math.round(stall.vx(stall.daisX))
      // `heroLift` is 0 except during the 260 ms after the child changes the
      // paint or the body, so at rest this is the same expression, to the
      // pixel, that `tst_carsprite.qml` compares against `stall.vy(daisY)`.
      y: Math.round(stall.vy(stall.daisY) + garage.heroLift)
      body: garage.bodyIndex
      paint: garage.paintIndex
      number: garage.kartNumber
      camera: "stall"
      // Not the rear. Column 0 is the car's back to the lens, which on the
      // dais showed the deck and the tail and almost none of the car. Column 6
      // is the same baked cell budget seen from the front-left quarter, where
      // the glasshouse, the door panel and a lit headlamp are all in view, and
      // the number lands on the door.
      yaw: 6
      sheetScale: 1.0
      pixelScale: fit.pixelScale

      // ROUND 12 -- THE CAR IS IN THE ROOM NOW, AND THESE FOUR NUMBERS ARE HOW.
      //
      // A critic measured this sprite against the room it stands in and found
      // no light of any kind on it: the body was `rgb(224,72,58)`, which is
      // byte-for-byte `Theme.paints[0]`, the colour of the red chip in the
      // swatch grid on the other side of the screen -- so the hero wore its own
      // UI colour, at UI chroma, in a lit scene. Its darks measured
      // `rgb(107,114,145)` and `rgb(26,27,38)`: a blue-grey at saturation 0.26,
      // in a room whose floor and wall shadows measure S = 0.69 and 0.70 purple
      // and whose stated rule is *shadow is purple, never grey*. And nothing
      // darkened under the wheels, so it floated.
      //
      // `washAmount` is the dusk `CarWash.qml` was written for, used here for
      // the room's ambient rather than the track's hour: one lerp of every tone
      // toward the bay's own purple, which is what drags the sheet's cold darks
      // into this room's palette and takes the body off the swatch's exact
      // bytes. `shadeAmount` is the same file's second half -- the bake's
      // contact shadow is an absolute `#5f255e` at half cover, a MID purple that
      // over this dais composites to something lighter than the dais, which is
      // why there appeared to be no contact shadow at all. Two passes in the
      // plinth's own deep tone put it back.
      //
      // What puts light BACK is `parts/CarLight.qml` below.
      washAmount: 0.14
      washColor: "#3a0f34"
      shadeAmount: 0.92
      shadeColor: "#190616"
    }

    // The key and the rim, over the wash and under nothing. A Loader for the
    // reason `CarSprite` loads `CarWash` through one: `ColorImage` lives in
    // `QtQuick.Controls.impl`, a Qt-internal module, and an import of it at the
    // top of this screen would let a Qt build without it take the whole garage
    // down instead of one lighting pass.
    Loader {
      id: heroLight
      x: heroKart.x
      y: heroKart.y
      source: "parts/CarLight.qml"
      onLoaded: item.host = heroKart
    }

    // =====================================================  the left board
    //
    // ONE BOARD, LEANING AGAINST THE ONE WALL THE ROOM HAS LEFT.
    //
    // Round nine had three cards down the left and centre: the kart card, the
    // settings board and the PRESET SIGNALS board. They are one object now,
    // ruled into three sections in the order a child needs them -- the car
    // they are making, the race they are about to run, and the note about what
    // rivals say during it -- so the left of the screen is one thing to read
    // instead of three things to choose between, and the centre-bottom, where
    // the signals board used to sit under the car's own nose, is floor.
    Panel {
      id: board
      x: page.contentX
      width: garage.px(560)
      height: boardColumn.height + garage.px(26)
      y: page.bottomEdge - height
      color: Theme.duskSurface
      // The opening is above and right of this board, so the sun lands on its
      // top edge.
      litSide: "top"

      Column {
        id: boardColumn
        x: garage.px(18)
        y: garage.px(14)
        width: parent.width - garage.px(36)
        spacing: garage.px(8)

        // ------------------------------------------------ section one: the car
        Text {
          textFormat: Text.PlainText
          text: "YOUR KART"
          color: Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: garage.fs(16)
          font.letterSpacing: garage.px(3)
        }

        Row {
          id: kartRow
          spacing: garage.px(16)
          readonly property int colW: Math.floor((boardColumn.width - garage.px(16)) / 2)

          Column {
            width: kartRow.colW
            spacing: garage.px(8)

            Text {
              textFormat: Text.PlainText
              text: "BODY   " + (garage.bodyIndex + 1) + " / 6"
              // Full strength, not the 0.92 step: these three labels sit in the
              // board's own lit wash (#6a2448 at its brightest), where 0.92
              // measured 4.53:1 -- inside the floor by three hundredths.
              color: Theme.text
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(14)
              font.letterSpacing: garage.px(2)
            }

            Stepper {
              id: bodyStepper
              width: parent.width
              height: garage.px(50)
              arrowWidth: garage.px(46)
              valueSize: garage.fs(21)
              valueSpacing: garage.px(2)
              faceColor: Theme.duskSurfaceSunken
              // ROUND 10. The resting look of a thing a child may press. See
              // `Theme.duskPressFace`.
              restFill: Theme.duskPressFace
              restBorder: Theme.duskPressEdge
              value: Theme.bodyName(garage.bodyIndex)
              name: "Kart body"
              hint: "Six bodies. Click an arrow, or press left and right."
              onStepped: function (delta) {
                garage.cycle("kartBody", delta, 6)
                garage.celebrate()
              }
            }

            Item { width: 1; height: garage.px(2) }

            Text {
              textFormat: Text.PlainText
              text: "NUMBER"
              color: Theme.text
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(14)
              font.letterSpacing: garage.px(3)
            }

            Stepper {
              id: numberStepper
              width: parent.width
              height: garage.px(50)
              arrowWidth: garage.px(46)
              valueSize: garage.fs(25)
              valueSpacing: garage.px(3)
              faceColor: Theme.duskSurfaceSunken
              restFill: Theme.duskPressFace
              restBorder: Theme.duskPressEdge
              value: String(garage.kartNumber)
              name: "Kart number"
              hint: "One to ninety-nine. Click an arrow, or press left and right."
              onStepped: function (delta) {
                garage.stepNumber(delta)
                garage.celebrate()
              }
            }
          }

          Column {
            width: kartRow.colW
            spacing: garage.px(8)

            Text {
              textFormat: Text.PlainText
              text: "COLOR"
              color: Theme.text
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(14)
              font.letterSpacing: garage.px(3)
            }

            PaintGrid {
              id: paintGrid
              width: parent.width
              height: garage.px(96)
              gap: garage.px(5)
              inset: garage.px(5)
              plate: Theme.duskSurfaceSunken
              plateBorder: Theme.line
              // Measured: at rest the eight chips were the highest-chroma
              // object on the screen and the first thing a squint found. 0.72
              // of value, hue untouched.
              rest: 0.72
              selected: garage.paintIndex
              onPicked: function (index) {
                Store.setSetting("kartPaint", index)
                garage.celebrate()
              }
            }
          }
        }

        // ROUND 12: `Colors and numbers are visible to all racers.` is gone. It
        // was written for a parent, it is a privacy notice on a screen whose
        // only other racers are three bots on this computer, and at 1024 x 600
        // it rendered at eight pixels -- a grey texture under the one control a
        // child came here to play with. THIS COMPUTER ONLY, in the title band,
        // is the same fact in words a parent and a child both parse.

        // ----------------------------------------------- section two: the race
        Rectangle {
          width: parent.width
          height: 1
          color: Theme.line
        }

        Text {
          textFormat: Text.PlainText
          text: "THE RACE"
          color: Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: garage.fs(16)
          font.letterSpacing: garage.px(3)
        }

        // Five rows, written out rather than repeated over a model: the values
        // change as the child cycles them, and a model that changes rebuilds
        // its delegates, which would destroy the very control the child has
        // focus on. Explicit rows keep focus where the child put it.
        //
        // ROUND 10 -- THREE OF THE FIVE DO SOMETHING, AND NOW THEY LOOK LIKE
        // IT. TRACK and GOAL are fixed by the design and always were; they
        // carried the same cream value at the same size as the three rows that
        // change, so the only thing separating them was a word in a 100 px
        // column at the far right of a row the child reads at the left. They
        // keep their place, their icon and their reason -- a fixed row that
        // vanished would be a question a child cannot answer -- and they lose
        // the value tone that says "this is the thing you are choosing".
        Column {
          id: settingsColumn
          width: parent.width
          spacing: 0

          // ROUND 10 -- THE ROWS THAT DO SOMETHING ARE THE BIGGER ROWS, AND
          // THAT CLOSES A MEASURED HOLE PIECE M HANDED THIS PIECE.
          //
          // `tst_mouse_parity.qml` test_44 measures every live control at
          // 1024 x 600 against the WCAG 2.2 AA 24 px floor -- which is the
          // number for an adult, and this game is for a seven-year-old. Six
          // controls were under it and all six were these rows: 23 px, stacked
          // flush, so piece M could not grow the hit area without two rows
          // sharing pixels. Its own note says so and hands the fix here: "A
          // pixel of room between three rows is the GARAGE's layout, which is
          // piece 3's and not this one's."
          //
          // The fix is the hierarchy this section already wanted. A row that
          // can be changed is 50 px and a row that is a fact is 38, so the
          // three the child can press clear the floor at every size the game is
          // played at, the two they cannot are smaller as well as quieter, and
          // the column is shorter than it would be with five rows at 50.
          readonly property int rowH: garage.px(50)
          readonly property int labelPx: garage.fs(14)
          readonly property int valuePx: garage.fs(20)
          readonly property int labelWidthPx: garage.px(126)

          SettingRow {
            id: modeRow
            width: parent.width
            height: parent.rowH
            labelColor: Theme.text
            art: Glyphs.clock
            label: "MODE"
            spokenName: "Race mode"
            value: garage.modeNames[garage.raceMode]
            labelSize: parent.labelPx
            valueSize: parent.valuePx
            labelWidth: parent.labelWidthPx
            chipFill: Theme.duskPressFace
            chipBorder: Theme.duskPressEdge
            onStepped: function (delta) { garage.cycle("raceMode", delta, 4) }
          }
          SettingRow {
            id: mathRow
            width: parent.width
            height: parent.rowH
            separator: true
            labelColor: Theme.text
            art: Glyphs.times
            label: "MATH SET"
            spokenName: "Math set"
            value: garage.setNames[garage.mathSet]
            labelSize: parent.labelPx
            valueSize: parent.valuePx
            labelWidth: parent.labelWidthPx
            chipFill: Theme.duskPressFace
            chipBorder: Theme.duskPressEdge
            onStepped: function (delta) { garage.cycle("mathSet", delta, 3) }
          }
          SettingRow {
            id: rivalRow
            width: parent.width
            height: parent.rowH
            separator: true
            labelColor: Theme.text
            art: Glyphs.wheel
            label: "RIVALS"
            spokenName: "Rivals"
            value: Theme.levelNames[garage.rivalLevel]
            labelSize: parent.labelPx
            valueSize: parent.valuePx
            labelWidth: parent.labelWidthPx
            chipFill: Theme.duskPressFace
            chipBorder: Theme.duskPressEdge
            onStepped: function (delta) { garage.cycle("rivalLevel", delta, 3) }
          }
        }

        // ROUND 12 -- THE TWO ROWS THAT COULD NEVER BE PRESSED ARE A SENTENCE
        // NOW, AND THAT IS THE POINT.
        //
        // TRACK and GOAL were laid out as settings rows: same icon, same label
        // column, same value column, same chip column, same height give or take
        // twelve pixels as the three rows that DO something. Round ten's answer
        // was to dim them, and a critic measured what that came to -- alpha
        // 0.922 against 1.000, a 7.8 % dimming, invisible -- on a screen whose
        // title band promises `CLICK ANYTHING THAT LIGHTS UP`. A child clicks
        // GOLDEN HOUR, nothing happens, twice, in the first minute.
        //
        // A fact is not a disabled control, and the fix is not a better disabled
        // state: it is to stop drawing a fact as a control. Both facts survive
        // -- a child who wonders what track this is and how long a race lasts
        // gets both answers -- as one line of prose in the caption voice, with
        // no icon, no columns, no row height and nothing to press. It also
        // spends two fewer of the five cool-blue glyphs this warm room was
        // importing for decoration.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "ONE TRACK, " + garage.circuit + ". FINISH ALL "
                + garage.setLaps[garage.mathSet] + " LAPS TO WIN."
          color: Theme.text
          font.family: Theme.mono
          font.pixelSize: garage.fs(15)
          lineHeight: 1.25
        }

        // -------------------------------------------- section three: signals
        //
        // The design's "four-signal catalog shown so the child learns them
        // before racing rivals who use them" -- as a footnote to the race it
        // is about, which is what it is. Round nine gave it a 500 x 268 board
        // of its own with a heading, four bordered-height tiles and a two-line
        // paragraph, dead centre of the bottom edge, in front of the car. The
        // vocabulary is unchanged and every tile is still a declared sign
        // (`isSign`, `tst_mouse_parity.qml` test_22): they take no click,
        // because no key sends a signal from the garage and a click with no key
        // behind it is the mouse-only path the design forbids.
        Rectangle {
          width: parent.width
          height: 1
          color: Theme.line
        }

        Item {
          id: signalStrip
          width: parent.width
          height: garage.px(44)

          Accessible.role: Accessible.Grouping
          Accessible.name: "Signals in a race"
          Accessible.description: "These are the only signals in a race. The rivals send them too. Nice run, ready, rematch, good game."

          Text {
            id: signalCaption
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            width: garage.px(80)
            text: "SIGNALS"
            color: Theme.amber
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: garage.fs(13)
            font.letterSpacing: garage.px(1)
          }

          Row {
            id: signalRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - signalCaption.width - garage.px(8)
            height: parent.height
            spacing: garage.px(6)

            readonly property real tileW: (width - spacing * 3) / 4

            SignalTile {
              id: signal0
              width: signalRow.tileW
              height: parent.height
              art: Glyphs.thumbUp
              caption: "NICE RUN"
              // ROUND 12 -- FOUR TONES BECOME ONE, BECAUSE FOUR TONES WAS THE
              // TILES CLAIMING TO BE CONTROLS.
              //
              // Round eight gave each tile a hue of the room: cream, amber,
              // deep amber, neon pink. It is a legend -- there is no key that
              // sends a signal from the garage, so a click here would be the
              // mouse-only path the design forbids, and that decision stands.
              // But a critic put it exactly: they were "bright, click-shaped,
              // and take no click", four labelled colour tiles immediately left
              // of the loudest button on a screen that prints CLICK ANYTHING
              // THAT LIGHTS UP. Four different colours is how a row of buttons
              // is drawn; one quiet tone, the same tone as every other caption
              // on this board, is how a list is. The vocabulary and the icons
              // are untouched -- the child still learns the four signals.
              tone: Theme.text
              captionSize: garage.fs(13)
            }
            SignalTile {
              id: signal1
              width: signalRow.tileW
              height: parent.height
              art: Glyphs.flag
              caption: "READY"
              tone: Theme.text
              captionSize: garage.fs(13)
            }
            SignalTile {
              id: signal2
              width: signalRow.tileW
              height: parent.height
              art: Glyphs.rematch
              caption: "REMATCH?"
              tone: Theme.text
              captionSize: garage.fs(13)
            }
            SignalTile {
              id: signal3
              width: signalRow.tileW
              height: parent.height
              art: Glyphs.hand
              caption: "GOOD GAME"
              tone: Theme.text
              captionSize: garage.fs(13)
            }
          }
        }
      }
    }

    // =====================================================  the right column
    //
    // The grid, then the way on to it -- as ONE BOARD, which is the same kind of
    // object as the board on the left of the room, so the screen has two panels
    // standing in a bay rather than a panel on the left and a scatter of loose
    // cards on the right.
    //
    // ROUND 12, AND IT IS THE OTHER HALF OF THE "TWO DESIGNS SHARING A SCREEN"
    // FINDING. Round nine's cards floated free on the room. A critic measured
    // what was between them: the four seats ended at y = 600 and READY UP began
    // at y = 731, and in that 131 px gap the raw landscape ran straight through
    // the middle of the menu column -- mountains, a horizon, a dozen light lines
    // and the floor's yellow hazard chevron, dead level, reading as a strip of
    // tape stuck across the UI. At 1024 x 600 it was five stacked stripes of
    // unrelated background art inside a menu.
    //
    // A column is a surface with things on it. The gap between the roster and
    // the action is now BOARD -- deliberate air inside one object, which is what
    // the space between a list and its confirm button is in any interface -- and
    // the gaps are computed from what is left over rather than fixed, so the
    // column is evenly spread at every window size instead of butted to the top
    // with the remainder falling out of the bottom.
    Item {
      id: rightColumn
      x: page.rightX
      y: page.mainY
      width: page.rightW
      height: page.bottomEdge - page.mainY

      // The way out stands under the board, on the room's own floor, at a
      // sixth of the primary action's height. It is not on the board because it
      // is not part of setting up a race.
      ActionButton {
        id: leaveButton
        width: parent.width
        height: garage.px(66)
        y: parent.height - height
        art: Glyphs.exit
        tone: "quit"
        variant: "secondary"
        mutedColor: Theme.text
        label: "LEAVE"
        sublabel: "ESCAPE DOES IT TOO"
        labelSize: garage.fs(25)
        sublabelSize: garage.fs(15)
        iconSize: garage.px(28)
        Accessible.name: "Leave"
        Accessible.description: "Back to the garage home. Escape does it too."
        onActivated: garage.leaveRequested()
      }

      Panel {
        id: rightBoard
        width: parent.width
        height: leaveButton.y - garage.px(11)
        color: Theme.duskSurface
        // The opening is above and LEFT of this board, so the sun lands on its
        // top edge, the same way it lands on the left board's.
        litSide: "top"

        readonly property int pad: garage.px(14)
        readonly property int innerW: width - pad * 2
        readonly property int youH: garage.px(104)
        readonly property int rivalH: garage.px(92)
        readonly property int friendH: garage.px(52)
        readonly property int readyH: garage.px(196)
        readonly property int stackH: youH + 3 * rivalH + friendH
        // Five gaps: three between the four seats, one to the friend notice, one
        // to the action. `px(9)` is the floor, so a short window packs rather than
        // overlapping.
        readonly property int gap: Math.max(garage.px(9),
                                            Math.floor((height - pad * 2 - stackH
                                                        - readyH) / 5))

        RosterSlot {
          id: youSlot
          objectName: "rosterYou"
          width: rightBoard.innerW
          x: rightBoard.pad
          height: rightBoard.youH
          y: rightBoard.pad
          scaleUnit: garage.s
          surface: Theme.duskSurfaceRaised
          sunkenSurface: Theme.duskSurfaceSunken
          name: "YOU"
          number: garage.kartNumber
          paintIndex: garage.paintIndex
          bodyIndex: garage.bodyIndex
          level: -1
          ready: false
          statusText: "YOUR KART"
        }

        // ROUND 10 -- THE THREE RIVALS ARE A SMALLER VERSION OF THE SAME ROW.
        //
        // Four identical 100 px seats meant the child's own row -- the one row on
        // this screen that changes as they build their car -- carried a quarter
        // of the roster's weight. Nothing is taken out of a rival seat: the
        // design lists kart, colour, number, ready lamp and level badge, and
        // `tst_garage_keyboard.qml` test_18 checks all four karts are drawn at
        // full strength in every race mode. The whole seat is drawn at 0.86 of
        // the child's, through the scale unit the component already takes, so
        // the hierarchy is size and nothing is dimmed or dropped.
        Repeater {
          model: 3

          RosterSlot {
            width: rightBoard.innerW
            x: rightBoard.pad
            height: rightBoard.rivalH
            y: rightBoard.pad + rightBoard.youH + rightBoard.gap
               + index * (rightBoard.rivalH + rightBoard.gap)
            scaleUnit: garage.s * 0.86
            surface: Theme.duskSurfaceRaised
            sunkenSurface: Theme.duskSurfaceSunken
            name: Theme.rivalNames[index]
            number: Theme.rivalNumbers[index]
            paintIndex: Theme.rivalPaints[index]
            bodyIndex: index + 1
            level: garage.rivalLevel
            ready: true
            // ROUND-7: the row's chrome dims, the kart keeps its paint.
            inRace: garage.rivalsRace
          }
        }

        // Where the mock's approved-friend and device-verified legend sits.
        // A sign, not a control: no fill, no border, and out of the Tab chain.
        //
        // ROUND 10: one line, not a block. It was 602 x 112 with a 27 px heading
        // and a lock glyph the size of the settings icons -- the third loudest
        // object in a frame whose subject is a car, about a thing that cannot be
        // done and will not exist until a platform does. It says exactly what it
        // said, quietly, where a footnote goes.
        ActionButton {
          id: friendTile
          width: rightBoard.innerW
          x: rightBoard.pad
          height: rightBoard.friendH
          y: rightBoard.pad + rightBoard.youH
             + 3 * (rightBoard.rivalH + rightBoard.gap) + rightBoard.gap
          art: Glyphs.lock
          tone: "off"
          variant: "sign"
          surface: Theme.duskSurfaceSunken
          offTone: Theme.text
          mutedColor: Theme.text
          focusable: false
          label: "RACE A FRIEND"
          sublabel: "Ask a parent to install Kids Play"
          labelSize: garage.fs(19)
          sublabelSize: garage.fs(14)
          iconSize: garage.px(20)
          Accessible.name: "Race a friend, not available"
          Accessible.description: "Ask a parent to install Kids Play. This game races the three rivals on this computer only."
        }

        // The primary action is filled, is more than three times the height of
        // the way out, and carries the only 54 px word on the screen after the
        // title. Round one gave the two the same outline, the same layout and
        // nearly the same footprint, so a child scanning this column saw two
        // equal buttons one of which quits.
        //
        // ROUND-9: STILL THE LOUDEST CONTROL, NO LONGER THE BRIGHTEST OBJECT IN
        // THE PICTURE.
        //
        // Round seven's charge was a lime slab bigger than the sky. Round eight
        // recoloured it to the design's amber, which moved the green metric 23x
        // and the composition not at all: at `#f5a524` it carried 23.8 % of the
        // frame's luminous mass on 4.8 % of its area -- twice the whole sky and
        // 6.8x the sun disc -- so a control out-shone the light source this
        // whole direction is built on, in the sun's own hue family.
        //
        // The fix is value, not hue, and not making it hard to find. The FILL
        // drops to the amber's own deep ember; the amber itself stays, on the
        // border, on the flag and in the focus state, where it costs a few
        // thousand pixels instead of a hundred thousand; and the label goes to
        // cream, which on the ember measures HIGHER than the dark ink measured
        // on the amber. Focus still brightens the fill and thickens the border,
        // never pales it. `goFill` and `goInk` default to the old behaviour, so
        // Results and Settings are byte-identical.
        //
        // ROUND 10: 148 px becomes 236, because the room to do it came out of
        // the friend notice and the rival seats and there is nothing else in
        // this column competing for it. This is the screen's one exciting thing
        // and it should read as the exciting thing, not as one more row.
        //
        // ROUND 12: 236 BECOMES 216, AND IT SAYS WHAT IT DOES.
        //
        // At 556 x 236 this was 131,000 px of flat brown -- about 2.7 times the
        // car's painted silhouette, the single biggest object on a screen whose
        // subject is a car -- and a critic squint-testing the frame at 16:1 found
        // it FOURTH in the eye order, ahead of the hero. Taking a fifth of its
        // area off while the hero gains a rim, a key and a shadow is most of that
        // gap closed; sitting on a board instead of on open landscape is the rest,
        // because a filled slab on a surface reads as a button and the same slab
        // on a sunset reads as a hole.
        //
        // AND THE WORDS. "READY UP" is lobby-shooter jargon; a seven-year-old does
        // not use it, and "rivals" is not a Year 3 word either. Worse, the word
        // RACE appeared three times on this screen -- THE RACE, RACE MODE, RACE A
        // FRIEND -- every one of them a label on something that is NOT the go
        // button, so the verb the child came for was spent three times on
        // furniture and never once on the control that does it. The button takes
        // the verb back, and the line under it is what happens next in the four
        // words a child already knows.
        ActionButton {
          id: readyButton
          width: rightBoard.innerW
          x: rightBoard.pad
          height: rightBoard.readyH
          y: rightBoard.height - rightBoard.pad - height
          art: Glyphs.flag
          tone: "go"
          goTone: Theme.amber
          // ROUND 12: one step under `Theme.emberDeep`. At the ember itself
          // this slab was the warmest large field in the frame after the sky,
          // and the hierarchy this screen needs is car first, button second.
          // The amber border, the flag and the cream label are untouched, so
          // the control is no harder to find -- it is the FILL that shouted.
          goFill: "#7a3313"
          goInk: Theme.cream
          variant: "primary"
          label: "START THE RACE"
          sublabel: "3 . 2 . 1 . GO!"
          labelSize: garage.fs(44)
          sublabelSize: garage.fs(20)
          iconSize: garage.px(46)
          Accessible.name: "Start the race"
          Accessible.description: "Starts the countdown. " + garage.modeNames[garage.raceMode]
                                  + ", " + garage.setNames[garage.mathSet] + "."
          onActivated: garage.raceRequested()
        }
      }
    }
  }

  // Round three had a Callout here that the four signal tiles fired when they
  // were pressed. The tiles are a legend now and nothing on this screen sends
  // a signal, so the callout has no sender and is gone rather than left
  // behind as a control that can never speak. ui/parts/Callout.qml stays for
  // the race screen, which is where a signal is actually sent.

}
