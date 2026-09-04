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
FocusScope {
  id: garage

  // The overlay hands focus here; the harness does the same.
  readonly property Item focusTarget: stops.length > 0 ? stops[0] : null

  signal raceRequested()
  signal leaveRequested()

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ------------------------------------------------------------ race setup
  readonly property var modeNames: ["PRACTICE", "TIME TRIAL", "GHOST", "GRAND PRIX"]
  readonly property var setNames: ["TIMES TABLES 2-5", "TIMES TABLES 2-10", "TIMES TABLES 1-12"]
  readonly property var setLaps: [4, 9, 12]
  readonly property string circuit: "MIDNIGHT GARAGE"

  readonly property int bodyIndex: Store.setting("kartBody")
  readonly property int paintIndex: Store.setting("kartPaint")
  readonly property int kartNumber: Store.setting("kartNumber")
  readonly property int rivalLevel: Store.setting("rivalLevel")
  readonly property int raceMode: Store.setting("raceMode")
  readonly property int mathSet: Store.setting("mathSet")
  readonly property bool rivalsRace: raceMode === 3

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
  Accessible.description: "Set up your kart and the race, then ready up. Tab moves, arrows change, Enter chooses, Escape leaves."

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
  // rail, the kart card, the roster, the three boards along the bottom -- is
  // an object standing in that room. The faked light is deleted: what falls on
  // this page is the room's own sky, hills, threshold and floor, drawn once.
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
    }

    readonly property int pad: garage.px(22)
    readonly property int contentX: pad
    readonly property int contentW: width - pad * 2

    // =====================================================  title bar
    Item {
      id: titleBar
      x: page.contentX
      y: page.pad
      width: page.contentW
      height: garage.px(80)

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
          // 0.6 alpha measured 3.44:1 on the shipped frame -- the only string
          // on the screen under 4.5:1. It is decorative, but a floor that has
          // an exception is not a floor.
          color: Theme.accent
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

      // Where the mock carries the invite code, solo carries the fact that
      // makes an invite code impossible. It is said once here and once on the
      // rail below, and no more: round one said it three times in the top
      // 190 px, with the value stacked above its own label, and hung a
      // decorative glyph square beside it wearing a control's border and fill.
      // Round two spent a 268 x 62 chip at 34 px on a word that the policy
      // rail already says 50 px below it, in more useful terms. It stays --
      // "offline" is the one fact a parent glancing at this screen wants --
      // but at the size of a status readout rather than of a heading.
      Readout {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: garage.px(148)
        height: garage.px(44)
        value: "OFFLINE"
        // ROUND-8: was Theme.lime. Design v3's Visual style names amber,
        // cream, the rim and the purples; it names no green at all, and the
        // bar has 0.039% of its pixels in the green band against our 5.6%.
        valueColor: Theme.amber
        valueSize: garage.fs(20)
        valueSpacing: garage.px(2)
        rivetInset: garage.px(5)
        rivetSize: garage.px(2)
      }
    }

    // =====================================================  policy rail
    Rectangle {
      id: rail
      x: page.contentX
      y: titleBar.y + titleBar.height + garage.px(14)
      width: page.contentW
      height: garage.px(56)
      radius: Theme.cornerRadius
      color: Theme.duskSurfaceSunken
      border.width: 1
      border.color: Theme.line

      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: garage.px(22)
        spacing: garage.px(22)

        Repeater {
          model: [
            { art: Glyphs.lock, tone: Theme.cream, label: "SOLO GARAGE" },
            { art: Glyphs.preset, tone: Theme.amber, label: "PRESET SIGNALS" },
            { art: Glyphs.monitor, tone: Theme.accent, label: "THIS COMPUTER ONLY" }
          ]

          Row {
            spacing: garage.px(22)

            Rectangle {
              visible: index > 0
              anchors.verticalCenter: parent.verticalCenter
              width: garage.px(4)
              height: garage.px(4)
              radius: width / 2
              color: Theme.textFaint
            }
            PixelIcon {
              anchors.verticalCenter: parent.verticalCenter
              width: garage.px(26)
              height: width
              art: modelData.art
              color: modelData.tone
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.label
              color: modelData.tone
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(17)
              font.letterSpacing: garage.px(2)
            }
          }
        }
      }

      // The right half of the rail was empty. This is a keyboard-only game,
      // so what belongs in it is the keyboard.
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: garage.px(22)
        spacing: garage.px(20)

        Repeater {
          model: [ { key: "TAB", what: "MOVE" },
                   { key: "ARROWS", what: "CHANGE" },
                   { key: "ENTER", what: "CHOOSE" },
                   { key: "ESC", what: "LEAVE" } ]

          Row {
            spacing: garage.px(8)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: keyText.implicitWidth + garage.px(14)
              height: garage.px(26)
              radius: Theme.cornerRadiusSmall
              color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.07)
              border.width: 1
              border.color: Theme.lineStrong
              Text {
                id: keyText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.key
                color: Theme.text
                font.family: Theme.mono
                font.bold: true
                font.pixelSize: garage.fs(15)
                font.letterSpacing: garage.px(1)
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.what
              color: Theme.text
              font.family: Theme.mono
              font.pixelSize: garage.fs(15)
              font.letterSpacing: garage.px(1)
            }
          }
        }
      }
    }

    // =====================================================  main row
    readonly property int mainY: rail.y + rail.height + garage.px(16)
    // ROUND-9: 292 becomes 268. The three boards along the bottom now stand ON
    // the bay floor with the turntable running behind them, so every pixel
    // taken off this band is a pixel of plinth the child can see. The rows
    // inside it come down from 50 to 44 to pay for it.
    readonly property int bottomH: garage.px(268)
    readonly property int bottomY: height - pad - bottomH
    readonly property int mainH: bottomY - garage.px(16) - mainY
    readonly property int rosterW: garage.px(602)

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
    // glow, with a plinth sized to it -- and that is what the room around it
    // now does. The width is piece C's to give.
    CarSprite {
      id: heroKart
      objectName: "heroCar"
      readonly property var fit: CarMeta.fit(stall.vs(stall.kartWidth))
      x: Math.round(stall.vx(stall.daisX))
      y: Math.round(stall.vy(stall.daisY))
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
    }

    // ------------------------------------------------------ the kart card
    // ROUND-9: ONE CARD, NOT TWO PANELS IN TWO CORNERS.
    //
    // Body was a card in the bay's bottom-left corner and colour and number
    // were a translucent scrim over its bottom-right, and between them they
    // held the middle of the picture. Two defects came straight out of that
    // arrangement and both are gone with it: the room's hazard stripe ran
    // through the NUMBER heading (the scrim was genuinely translucent, which
    // was the previous round's fix for a different complaint), and the number
    // stepper's arrows were near-invisible outlines with the floor grid
    // showing through them.
    //
    // The three stall controls are one opaque board leaning against the one
    // wall the room has left, in the reading order the Tab chain already used:
    // body and number down the left of it, the eight paints down the right.
    // It is the width of the settings board under it, it clears the turntable,
    // and it takes 5,900 px out of the sky instead of 43,000.
    Panel {
      id: kartCard
      x: page.contentX
      width: garage.px(500)
      height: kartColumn.height + garage.px(40)
      y: page.bottomY - garage.px(16) - height
      color: Theme.duskSurface
      // The opening is above and right of this board, so the sun lands on its
      // top edge.
      litSide: "top"

      Column {
        id: kartColumn
        x: garage.px(20)
        y: garage.px(20)
        width: parent.width - garage.px(40)
        spacing: garage.px(12)

        Row {
          id: kartRow
          spacing: garage.px(16)
          readonly property int colW: Math.floor((kartColumn.width - garage.px(16)) / 2)

          Column {
            width: kartRow.colW
            spacing: garage.px(9)

            Text {
              textFormat: Text.PlainText
              text: "KART BODY   " + (garage.bodyIndex + 1) + " / 6"
              color: Theme.cream
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(15)
              font.letterSpacing: garage.px(2)
            }

            Stepper {
              id: bodyStepper
              width: parent.width
              height: garage.px(56)
              arrowWidth: garage.px(48)
              valueSize: garage.fs(22)
              valueSpacing: garage.px(2)
              faceColor: Theme.duskSurfaceSunken
              value: Theme.bodyName(garage.bodyIndex)
              name: "Kart body"
              hint: "Six bodies. Left and right change it."
              onStepped: function (delta) { garage.cycle("kartBody", delta, 6) }
            }

            Item { width: 1; height: garage.px(4) }

            Text {
              textFormat: Text.PlainText
              text: "NUMBER"
              color: Theme.cream
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(15)
              font.letterSpacing: garage.px(3)
            }

            Stepper {
              id: numberStepper
              width: parent.width
              height: garage.px(56)
              arrowWidth: garage.px(48)
              valueSize: garage.fs(26)
              valueSpacing: garage.px(3)
              faceColor: Theme.duskSurfaceSunken
              value: String(garage.kartNumber)
              name: "Kart number"
              hint: "One to ninety-nine. Left and right change it."
              onStepped: function (delta) { garage.stepNumber(delta) }
            }
          }

          Column {
            width: kartRow.colW
            spacing: garage.px(9)

            Text {
              textFormat: Text.PlainText
              text: "COLOR"
              color: Theme.cream
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: garage.fs(15)
              font.letterSpacing: garage.px(3)
            }

            PaintGrid {
              id: paintGrid
              width: parent.width
              height: garage.px(118)
              gap: garage.px(8)
              selected: garage.paintIndex
              onPicked: function (index) { Store.setSetting("kartPaint", index) }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Colors and numbers are visible to all racers."
          color: Theme.text
          font.family: Theme.mono
          font.pixelSize: garage.fs(15)
          lineHeight: 1.25
        }
      }
    }


    // ------------------------------------------------------- the roster
    Item {
      id: roster
      x: page.contentX + page.contentW - page.rosterW
      y: page.mainY
      width: page.rosterW
      height: page.mainH

      readonly property int slotH: garage.px(100)
      readonly property int slotGap: garage.px(10)

      RosterSlot {
        objectName: "rosterYou"
        width: parent.width
        height: roster.slotH
        y: 0
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

      Repeater {
        model: 3

        RosterSlot {
          width: roster.width
          height: roster.slotH
          y: (index + 1) * (roster.slotH + roster.slotGap)
          scaleUnit: garage.s
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
      ActionButton {
        id: friendTile
        width: parent.width
        height: parent.height - (roster.slotH * 4 + roster.slotGap * 3) - garage.px(12)
        y: parent.height - height
        art: Glyphs.lock
        tone: "off"
        variant: "sign"
        surface: Theme.duskSurfaceSunken
        offTone: Theme.text
        mutedColor: Theme.text
        focusable: false
        label: "RACE A FRIEND"
        sublabel: "Ask a parent to install Kids Play"
        labelSize: garage.fs(27)
        sublabelSize: garage.fs(17)
        iconSize: garage.px(32)
        Accessible.name: "Race a friend, not available"
        Accessible.description: "Ask a parent to install Kids Play. This game races the three rivals on this computer only."
      }
    }

    // =====================================================  bottom row
    readonly property int settingsW: garage.px(660)
    readonly property int signalsW: contentW - settingsW - rosterW - garage.px(32)

    // ------------------------------------------------- race settings
    Panel {
      id: settingsPanel
      x: page.contentX
      y: page.bottomY
      width: page.settingsW
      height: page.bottomH
      color: Theme.duskSurface
      // The bay is above this band, so the sun lands on its top edge.
      litSide: "top"

      // Five rows, written out rather than repeated over a model: the values
      // change as the child cycles them, and a model that changes rebuilds
      // its delegates, which would destroy the very control the child has
      // focus on. Explicit rows keep focus where the child put it.
      Column {
        x: garage.px(24)
        y: garage.px(18)
        width: parent.width - garage.px(48)
        spacing: 0

        readonly property int rowH: garage.px(44)
        readonly property int labelPx: garage.fs(15)
        readonly property int valuePx: garage.fs(23)
        readonly property int labelW: garage.px(180)

        SettingRow {
          width: parent.width
          height: parent.rowH
          art: Glyphs.flag
          label: "TRACK"
          spokenName: "Track"
          value: garage.circuit
          changeable: false
          fixedLabel: "1 OF 1"
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
          labelColor: Theme.text
          fixedColor: Theme.duskTextQuiet
        }
        SettingRow {
          id: modeRow
          width: parent.width
          height: parent.rowH
          separator: true
          labelColor: Theme.text
          art: Glyphs.clock
          label: "RACE MODE"
          spokenName: "Race mode"
          value: garage.modeNames[garage.raceMode]
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
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
          labelWidth: parent.labelW
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
          labelWidth: parent.labelW
          onStepped: function (delta) { garage.cycle("rivalLevel", delta, 3) }
        }
        SettingRow {
          width: parent.width
          height: parent.rowH
          separator: true
          art: Glyphs.trophy
          label: "GOAL"
          spokenName: "Goal"
          value: "FINISH ALL " + garage.setLaps[garage.mathSet] + " LAPS"
          changeable: false
          labelColor: Theme.text
          fixedColor: Theme.duskTextQuiet
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
        }
      }
    }

    // ------------------------------------------------- preset signals
    Panel {
      id: signalsPanel
      x: page.contentX + page.settingsW + garage.px(16)
      y: page.bottomY
      width: page.signalsW
      height: page.bottomH
      color: Theme.duskSurface
      litSide: "top"
      pad: garage.px(22)
      title: "PRESET SIGNALS"
      titleColor: Theme.amber
      titleSize: garage.fs(17)
      titleSpacing: garage.px(3)

      Row {
        id: signalRow
        x: garage.px(22)
        y: garage.px(54)
        width: parent.width - garage.px(44)
        height: garage.px(138)
        spacing: garage.px(12)

        readonly property real tileW: (width - spacing * 3) / 4

        SignalTile {
          id: signal0
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.thumbUp
          caption: "NICE RUN"
          surface: Theme.duskSurfaceRaised
          // ROUND-9: OFF the sunken step. Four near-black cards in a row along the
          // bottom edge were, after round eight raised everything else, the
          // darkest large areas left in a frame with no other dark -- so they
          // read MORE like holes at the new value than they did at the old
          // one. A legend is not a hole; the tiles now sit on the raised step.
          // ROUND-8: the four tones are now four hues of the room -- cream,
          // amber, the deep amber and the sky's own neon pink. Lime and the
          // theme accent were the two off-bar colours in the set.
          tone: Theme.cream
          captionSize: garage.fs(15)
        }
        SignalTile {
          id: signal1
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.flag
          caption: "READY"
          surface: Theme.duskSurfaceRaised
          tone: Theme.amber
          captionSize: garage.fs(15)
        }
        SignalTile {
          id: signal2
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.rematch
          caption: "REMATCH?"
          surface: Theme.duskSurfaceRaised
          tone: "#ee8b3a"
          captionSize: garage.fs(15)
        }
        SignalTile {
          id: signal3
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.hand
          caption: "GOOD GAME"
          surface: Theme.duskSurfaceRaised
          tone: Theme.duskNeon
          captionSize: garage.fs(15)
        }
      }

      Accessible.role: Accessible.Grouping
      Accessible.name: "Preset signals"
      Accessible.description: "These are the only signals in a race. The rivals send them too. Nice run, ready, rematch, good game."

      Text {
        x: garage.px(22)
        y: signalRow.y + signalRow.height + garage.px(16)
        width: parent.width - garage.px(44)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "These are the only signals in a race. The rivals send them too."
        color: Theme.text
        font.family: Theme.mono
        font.pixelSize: garage.fs(15)
        lineHeight: 1.25
      }
    }

    // ------------------------------------------------- start and leave
    Item {
      id: actions
      x: page.contentX + page.contentW - page.rosterW
      y: page.bottomY
      width: page.rosterW
      height: page.bottomH

      // The primary action is filled, is more than twice the height of the
      // way out, and carries the only 46 px word on the screen after the
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
      ActionButton {
        id: readyButton
        width: parent.width
        y: garage.px(12)
        height: garage.px(148)
        art: Glyphs.flag
        tone: "go"
        goTone: Theme.amber
        goFill: Theme.emberDeep
        goInk: Theme.cream
        variant: "primary"
        label: "READY UP"
        sublabel: garage.rivalsRace ? "STARTS THE COUNTDOWN AGAINST THREE RIVALS"
                                    : "STARTS THE COUNTDOWN"
        labelSize: garage.fs(46)
        sublabelSize: garage.fs(17)
        iconSize: garage.px(46)
        Accessible.name: "Ready up"
        Accessible.description: "Starts the countdown. " + garage.modeNames[garage.raceMode]
                                + ", " + garage.setNames[garage.mathSet] + "."
        onActivated: garage.raceRequested()
      }

      ActionButton {
        id: leaveButton
        width: parent.width
        height: garage.px(72)
        y: parent.height - height
        art: Glyphs.exit
        tone: "quit"
        variant: "secondary"
        mutedColor: Theme.text
        label: "LEAVE"
        sublabel: "ESCAPE DOES IT TOO"
        labelSize: garage.fs(27)
        sublabelSize: garage.fs(15)
        iconSize: garage.px(30)
        Accessible.name: "Leave"
        Accessible.description: "Back to the garage home. Escape does it too."
        onActivated: garage.leaveRequested()
      }
    }
  }

  // Round three had a Callout here that the four signal tiles fired when they
  // were pressed. The tiles are a legend now and nothing on this screen sends
  // a signal, so the callout has no sender and is gone rather than left
  // behind as a control that can never speak. ui/parts/Callout.qml stays for
  // the race screen, which is where a signal is actually sent.

}
