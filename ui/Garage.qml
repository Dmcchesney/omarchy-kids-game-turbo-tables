import QtQuick
import "parts"

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
  readonly property var stops: [bodyStepper, paintGrid, numberStepper,
                                modeRow.focusItem, mathRow.focusItem, rivalRow.focusItem,
                                signal0, signal1, signal2, signal3,
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

  // Escape backs out; up and down walk the same chain Tab walks. Both only
  // run when the focused control has not already used the key, because key
  // events reach an ancestor only after the focused item ignores them.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      garage.leaveRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      garage.moveFocus(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      garage.moveFocus(-1)
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.ground
  }

  // The page: one card with everything on it, exactly as the mock frames it.
  Panel {
    id: page
    anchors.fill: parent
    anchors.margins: garage.px(16)
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.55)
    border.color: Theme.lineStrong

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
          color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)
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
        valueColor: Theme.lime
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
      color: Theme.panelSunken
      border.width: 1
      border.color: Theme.line

      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: garage.px(22)
        spacing: garage.px(22)

        Repeater {
          model: [
            { art: Glyphs.lock, tone: Theme.lime, label: "SOLO GARAGE" },
            { art: Glyphs.broadcast, tone: Theme.amber, label: "PRESET SIGNALS" },
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
              color: Theme.textLabel
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
    readonly property int bottomH: garage.px(292)
    readonly property int bottomY: height - pad - bottomH
    readonly property int mainH: bottomY - garage.px(16) - mainY
    readonly property int rosterW: garage.px(602)
    readonly property int stallW: contentW - rosterW - garage.px(16)

    // ------------------------------------------------- the kart stall
    Panel {
      id: stallPanel
      x: page.contentX
      y: page.mainY
      width: page.stallW
      height: page.mainH
      color: Theme.ground
      clip: true

      GarageStall {
        id: stall
        anchors.fill: parent
        cornerRadius: Theme.cornerRadius
      }

      KartSprite {
        id: heroKart
        // Sized so the whole kart stands on the plinth. At 536 the nose's
        // lower corner fell outside the dais ellipse and crossed the amber
        // rim; the fit is checked against the ellipse, not by eye.
        width: stall.vs(486)
        height: width * vbH / vbW
        x: stall.vx(stall.daisX) - width / 2
        y: stall.vy(stall.daisY) - height * groundFraction
        body: garage.bodyIndex
        paint: Theme.paint(garage.paintIndex)
        number: garage.kartNumber
      }

      // The body selector. It has its own opaque card in the bottom-left
      // corner of the bay, on bare floor: round one dropped the bare control
      // on top of the turntable and the dais stroke reappeared four pixels
      // from its edge. The turntable was moved right and taken in to make
      // this corner empty rather than to make the collision smaller.
      Rectangle {
        id: bodyCard
        x: garage.px(22)
        y: parent.height - height - garage.px(22)
        width: garage.px(304)
        height: bodyColumn.height + garage.px(34)
        radius: Theme.cornerRadius
        color: Theme.panel
        border.width: 1
        border.color: Theme.lineStrong

        Column {
          id: bodyColumn
          x: garage.px(17)
          y: garage.px(17)
          width: parent.width - garage.px(34)
          spacing: garage.px(9)

          Text {
            textFormat: Text.PlainText
            text: "KART BODY   " + (garage.bodyIndex + 1) + " / 6"
            color: Theme.textLabel
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: garage.fs(15)
            font.letterSpacing: garage.px(2)
          }

          Stepper {
            id: bodyStepper
            width: parent.width
            height: garage.px(58)
            arrowWidth: garage.px(52)
            valueSize: garage.fs(23)
            valueSpacing: garage.px(2)
            value: Theme.bodyName(garage.bodyIndex)
            name: "Kart body"
            hint: "Six bodies. Left and right change it."
            onStepped: function (delta) { garage.cycle("kartBody", delta, 6) }
          }
        }
      }

      // Paint and number, over the right of the bay, as in the mock.
      Rectangle {
        id: paintPanel
        width: garage.px(296)
        height: paintColumn.height + garage.px(36)
        x: parent.width - width - garage.px(22)
        y: parent.height - height - garage.px(22)
        radius: Theme.cornerRadius
        // Opaque. At 90 % the wall poster behind it showed through the top
        // swatch row: a text collision on the most saturated element of the
        // screen. Nothing behind a panel may be legible through it.
        color: Theme.panel
        border.width: 1
        border.color: Theme.lineStrong

        Column {
          id: paintColumn
          x: garage.px(18)
          y: garage.px(18)
          width: parent.width - garage.px(36)
          spacing: garage.px(9)

          Text {
            textFormat: Text.PlainText
            text: "COLOR"
            color: Theme.cream
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: garage.fs(17)
            font.letterSpacing: garage.px(3)
          }

          PaintGrid {
            id: paintGrid
            width: parent.width
            height: garage.px(112)
            gap: garage.px(8)
            selected: garage.paintIndex
            onPicked: function (index) { Store.setSetting("kartPaint", index) }
          }

          Item { width: 1; height: garage.px(7) }

          Text {
            textFormat: Text.PlainText
            text: "NUMBER"
            color: Theme.cream
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: garage.fs(17)
            font.letterSpacing: garage.px(3)
          }

          Stepper {
            id: numberStepper
            width: parent.width
            height: garage.px(58)
            arrowWidth: garage.px(52)
            valueSize: garage.fs(27)
            valueSpacing: garage.px(3)
            value: String(garage.kartNumber)
            name: "Kart number"
            hint: "One to ninety-nine. Left and right change it."
            onStepped: function (delta) { garage.stepNumber(delta) }
          }

          Item { width: 1; height: garage.px(3) }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Colors and numbers are visible to all racers."
            color: Theme.textLabel
            font.family: Theme.mono
            font.pixelSize: garage.fs(15)
            lineHeight: 1.25
          }
        }
      }
    }

    // ------------------------------------------------------- the roster
    Item {
      id: roster
      x: page.contentX + page.stallW + garage.px(16)
      y: page.mainY
      width: page.rosterW
      height: page.mainH

      readonly property int slotH: garage.px(100)
      readonly property int slotGap: garage.px(10)

      RosterSlot {
        width: parent.width
        height: roster.slotH
        y: 0
        scaleUnit: garage.s
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
          name: Theme.rivalNames[index]
          number: Theme.rivalNumbers[index]
          paintIndex: Theme.rivalPaints[index]
          bodyIndex: index + 1
          level: garage.rivalLevel
          ready: true
          opacity: garage.rivalsRace ? 1.0 : 0.45
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

      // Five rows, written out rather than repeated over a model: the values
      // change as the child cycles them, and a model that changes rebuilds
      // its delegates, which would destroy the very control the child has
      // focus on. Explicit rows keep focus where the child put it.
      Column {
        x: garage.px(24)
        y: garage.px(22)
        width: parent.width - garage.px(48)
        spacing: 0

        readonly property int rowH: garage.px(50)
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
        }
        SettingRow {
          id: modeRow
          width: parent.width
          height: parent.rowH
          separator: true
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
      pad: garage.px(22)
      title: "PRESET SIGNALS"
      titleColor: Theme.amber
      titleSize: garage.fs(17)
      titleSpacing: garage.px(3)

      Row {
        id: signalRow
        x: garage.px(22)
        y: garage.px(60)
        width: parent.width - garage.px(44)
        height: garage.px(160)
        spacing: garage.px(12)

        readonly property real tileW: (width - spacing * 3) / 4

        SignalTile {
          id: signal0
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.thumbUp
          caption: "NICE RUN"
          tone: Theme.lime
          captionSize: garage.fs(15)
          onActivated: story.say("NICE RUN", Theme.lime)
        }
        SignalTile {
          id: signal1
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.flag
          caption: "READY"
          tone: Theme.amber
          captionSize: garage.fs(15)
          onActivated: story.say("READY", Theme.amber)
        }
        SignalTile {
          id: signal2
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.rematch
          caption: "REMATCH?"
          tone: "#ee8b3a"
          captionSize: garage.fs(15)
          onActivated: story.say("REMATCH?", "#ee8b3a")
        }
        SignalTile {
          id: signal3
          width: signalRow.tileW
          height: parent.height
          art: Glyphs.hand
          caption: "GOOD GAME"
          tone: Theme.accent
          captionSize: garage.fs(15)
          onActivated: story.say("GOOD GAME", Theme.accent)
        }
      }

      Text {
        x: garage.px(22)
        y: signalRow.y + signalRow.height + garage.px(16)
        width: parent.width - garage.px(44)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "These are the only signals in a race. The rivals send them too."
        color: Theme.textLabel
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
      ActionButton {
        id: readyButton
        width: parent.width
        height: garage.px(190)
        art: Glyphs.flag
        tone: "go"
        variant: "primary"
        label: "READY UP"
        sublabel: garage.rivalsRace ? "STARTS THE COUNTDOWN AGAINST THREE RIVALS"
                                    : "STARTS THE COUNTDOWN"
        labelSize: garage.fs(46)
        sublabelSize: garage.fs(17)
        iconSize: garage.px(54)
        Accessible.name: "Ready up"
        Accessible.description: "Starts the countdown. " + garage.modeNames[garage.raceMode]
                                + ", " + garage.setNames[garage.mathSet] + "."
        onActivated: garage.raceRequested()
      }

      ActionButton {
        id: leaveButton
        width: parent.width
        height: garage.px(76)
        y: parent.height - height
        art: Glyphs.exit
        tone: "quit"
        variant: "secondary"
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

  // The two messages that have nowhere else to live.
  Callout {
    id: story
    anchors.horizontalCenter: parent.horizontalCenter
    y: page.y + page.bottomY - garage.px(34) - height
    width: garage.px(560)
    height: garage.px(62)
    reducedMotion: Store.setting("reducedMotion") === true
  }

}
