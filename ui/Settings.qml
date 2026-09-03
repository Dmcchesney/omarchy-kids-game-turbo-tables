import QtQuick
import "parts"

// Settings, and the three doors out of the save file.
//
// The plan's layer-2 list for this screen is "sound, reduced motion, scanlines,
// timer, rival level, resets with one confirmation each", and the design's Data
// table is what decides which of those are stored and which are read: the
// `settings` key holds "sound, reduced motion, scanlines, kart, paint, number,
// rival level, streak threshold if exposed" and nothing else. There is no timer
// among them, and the Modes table already fixes the clock per mode -- Practice
// has none, the other three have one. So TIMER is on this screen as a status
// row that says what the chosen mode does about the clock, and it is not a
// switch, because a switch would be a tenth key in a file whose contents the
// design lists exhaustively. It is called out here rather than quietly dropped.
//
// THE RESETS. Design, Data, the "Reset by" column: settings are reset by
// Settings, records by "Reset garage records", fact history by "Reset fact
// history". Three separate operations, one per key. This screen does not write
// its own version of any of them: it hands a save file to the engine's
// `resetSettings`, `resetRecords` and `resetFacts`, each of which touches
// exactly its own key and returns a new file, and then writes back the one key
// that changed. A child who wants a clean leaderboard keeps the mastery the
// fact history holds, and that separation is the engine's to guarantee rather
// than this screen's to remember.
//
// EVERY RESET ASKS ONCE. `parts/Confirm.qml` is the question, it opens on KEEP,
// and it swallows every key while it is up. Nothing here is recoverable.
FocusScope {
  id: settings

  readonly property Item focusTarget: confirming ? asker : (stops.length > 0 ? stops[0] : null)

  signal leaveRequested()

  // The last thing the screen told the child, read back off the banner itself.
  // A reset is invisible when it works, so what the screen said about it is the
  // only observable the child has -- and a walkthrough that asserted a second
  // copy of that string would not be checking the screen.
  readonly property string bannerText: banner.text

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ------------------------------------------------------------- the state
  readonly property bool sound: Store.setting("sound") !== false
  readonly property bool reducedMotion: Store.setting("reducedMotion") === true
  readonly property bool scanlines: Store.setting("scanlines") === true
  readonly property int rivalLevel: Store.setting("rivalLevel")
  readonly property int raceMode: Store.setting("raceMode")
  readonly property var modeNames: ["PRACTICE", "TIME TRIAL", "GHOST", "GRAND PRIX"]

  function onOff(value) { return value ? "ON" : "OFF" }
  function toggle(key) { Store.setSetting(key, Store.setting(key) !== true) }

  // "" while nothing is being asked; otherwise the key a yes would reset.
  property string pending: ""
  readonly property bool confirming: pending.length > 0

  // The stop the child was on when the question opened, so an answer of either
  // kind puts them back where they were rather than at the top of the screen.
  property int resumeStop: 0

  // ------------------------------------------------------------ the resets
  //
  // ROUND 3 -- THE RESETS ARE THE ENGINE'S, AND THIS SCREEN ONLY ASKS.
  //
  // This screen used to assemble a save file by hand, call the engine on it,
  // and then write the one key it thought had changed back into the Store
  // itself. Every version of that is a second copy of the rule "a reset touches
  // exactly its own key" -- and the whole reason the design's Data table has a
  // "Reset by" column is that a child clearing a leaderboard must not lose the
  // mastery the fact history holds. A second copy of a rule is a rule that can
  // drift, and it drifted twice already.
  //
  // So the three operations are now `Store.resetSettings()`,
  // `Store.resetRecords()` and `Store.resetFacts()`, each of which calls
  // `save.ts`'s own reset of the same name, takes *every* key back off the file
  // that came out of it, and writes once. Nothing here builds a settings object,
  // touches `Store.records`, or knows the engine's vocabulary. The arithmetic
  // is `npm test`'s; the confirmation is this screen's.
  //
  // Each returns true only when the save file was actually written -- false
  // while the Store has not loaded, and false while the file is quarantined,
  // which is a real outcome and not a theoretical one. `answer()` says NOTHING
  // WAS CHANGED for both, because a banner that claims a reset over a file that
  // did not change is the one lie this screen must never tell.
  function applyReset(which) {
    if (which === "settings")
      return Store.resetSettings()
    if (which === "records")
      return Store.resetRecords()
    if (which === "discard")
      return Store.discardQuarantinedFile()
    return Store.resetFacts()
  }

  function ask(which) {
    settings.resumeStop = Math.max(0, settings.stopIndex())
    settings.pending = which
    Qt.callLater(function () { asker.ask() })
  }

  function answer(yes) {
    var which = settings.pending
    settings.pending = ""
    var done = (yes && which.length > 0) ? settings.applyReset(which) : false
    settings.focusStop(settings.resumeStop)
    // The banner reports what happened to the file, not what was asked for. A
    // save file that could not be read is a save file that cannot be reset, and
    // saying so is the only honest thing this screen can do about it.
    banner.say(done ? settings.resetDone(which) : "NOTHING WAS CHANGED",
               done ? Theme.amber : Theme.lime)
  }

  function resetDone(which) {
    if (which === "settings")
      return "SETTINGS ARE BACK TO HOW THEY STARTED"
    if (which === "records")
      return "GARAGE RECORDS CLEARED"
    if (which === "discard")
      return "A NEW SAVE FILE HAS BEEN STARTED"
    return "FACT HISTORY CLEARED"
  }

  readonly property string askQuestion: {
    if (pending === "settings")
      return "RESET SETTINGS?"
    if (pending === "records")
      return "RESET GARAGE RECORDS?"
    if (pending === "facts")
      return "RESET FACT HISTORY?"
    if (pending === "discard")
      return "START A NEW SAVE FILE?"
    return ""
  }
  readonly property string askDetail: {
    if (pending === "settings")
      return "Sound, reduced motion, scanlines, the kart, its colour and number, "
             + "the rival level and the race setup all go back to how they started. "
             + "Records and fact history are not touched."
    if (pending === "records")
      return "Every best time, and the ghost that came with it, is cleared. "
             + "Settings and fact history are not touched. There is no undo."
    if (pending === "facts")
      return "Every fact goes back to never attempted and the mastery lamps go out. "
             + "Settings and records are not touched. There is no undo."
    // The one way out of a quarantine, and the only place it can be reached
    // from. It names what is lost, because what is lost is everything: the
    // unreadable file is still on the disk right now, and saying yes writes
    // over it with this session's defaults. Nothing else in the plugin calls
    // `Store.discardQuarantinedFile()`.
    if (pending === "discard")
      return "The save file on this computer cannot be read, so it has been left alone and "
             + "nothing has been written to it. Saying yes writes over it: every best time "
             + "and every fact in it goes, and the game starts a new file from today's "
             + "settings. Saying no keeps it exactly as it is. There is no undo."
    return ""
  }

  // -------------------------------------------------------- the quarantine
  //
  // Design, Data: the file is "human-readable, so a parent can see exactly what
  // is kept". When it cannot be read at all, that promise turns into this
  // screen's job -- say so where a parent will look, in the schema's own words,
  // and offer exactly one action behind the same question the resets ask.
  readonly property bool quarantined: Store.quarantined
  readonly property string quarantineReason: Store.quarantineReason

  // ---------------------------------------------------------- focus chain
  // Reading order, top to bottom and left to right: the five rows that can
  // change, then the three resets, then the way out. The TIMER row is not in
  // it, for the same reason the garage's TRACK and GOAL rows are not: a stop
  // that cannot act is a dead press.
  //
  // START A NEW SAVE FILE is in the chain only while there is a quarantine to
  // act on. A stop that cannot do anything is a dead press -- the same rule
  // that keeps the TIMER row out -- and a permanent button offering to
  // overwrite a save file that is perfectly fine is worse than dead.
  readonly property var stops: {
    var list = [soundRow.focusItem, motionRow.focusItem, scanRow.focusItem,
                rivalRow.focusItem,
                resetSettingsButton, resetRecordsButton, resetFactsButton]
    if (settings.quarantined)
      list.push(discardButton)
    list.push(backButton)
    return list
  }

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

  function focusedName() {
    var index = stopIndex()
    return index < 0 ? "" : focusName(index)
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Settings"
  Accessible.description: "Sound, motion, scanlines and rivals, and the three resets. "
                          + "Tab moves, arrows change, Enter chooses, Escape goes back."

  Keys.onPressed: function (event) {
    if (settings.confirming)
      return
    if (event.key === Qt.Key_Escape) {
      settings.leaveRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      settings.moveFocus(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      settings.moveFocus(-1)
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.ground
  }

  Panel {
    id: page
    anchors.fill: parent
    anchors.margins: settings.px(16)
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.55)
    border.color: Theme.lineStrong
    enabled: !settings.confirming

    readonly property int pad: settings.px(30)
    readonly property int contentX: pad
    readonly property int contentW: width - pad * 2

    // =====================================================  title bar
    Item {
      id: titleBar
      x: page.contentX
      y: page.pad
      width: page.contentW
      height: settings.px(74)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: settings.px(14)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "TURBO TABLES"
          color: Theme.cream
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: settings.fs(42)
          font.letterSpacing: settings.px(4)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "//"
          color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: settings.fs(30)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "SETTINGS"
          color: Theme.accent
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: settings.fs(30)
          font.letterSpacing: settings.px(3)
        }
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        spacing: settings.px(18)

        Repeater {
          // One arrow contract across every screen of the flow: Tab and the up
          // and down arrows move, left and right change a value where the stop
          // has one. `ARROWS CHANGE` was true of four rows on this screen and
          // false of the other four, and it disagreed with the results screen,
          // where left and right moved.
          model: [ { key: "TAB  ↑ ↓", what: "MOVE" },
                   { key: "◀ ▶", what: "CHANGE" },
                   { key: "ENTER", what: "CHOOSE" },
                   { key: "ESC", what: "BACK" } ]

          Row {
            spacing: settings.px(7)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: keyText.implicitWidth + settings.px(13)
              height: settings.px(25)
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
                font.pixelSize: settings.fs(14)
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.what
              color: Theme.textLabel
              font.family: Theme.mono
              font.pixelSize: settings.fs(14)
            }
          }
        }
      }
    }

    // =====================================================  the two columns
    readonly property int columnsY: titleBar.y + titleBar.height + settings.px(16)
    readonly property int leftW: Math.round(contentW * 0.56)
    readonly property int rightW: contentW - leftW - settings.px(16)
    // Capped rather than stretched to the bottom rail: five rows and three
    // buttons do not fill 900 px, and a panel that is mostly empty fill reads
    // as a screen with something missing from it.
    readonly property int columnsH: Math.min(height - pad - columnsY - settings.px(112),
                                             settings.px(724))

    // ------------------------------------------------------- the switches
    Panel {
      id: gamePanel
      x: page.contentX
      y: page.columnsY
      width: page.leftW
      height: page.columnsH
      pad: settings.px(22)
      title: "THE GAME"
      titleColor: Theme.amber
      titleSize: settings.fs(17)
      titleSpacing: settings.px(3)

      Column {
        x: settings.px(24)
        y: settings.px(64)
        width: parent.width - settings.px(48)
        spacing: 0

        readonly property int rowH: settings.px(106)
        readonly property int labelPx: settings.fs(16)
        readonly property int valuePx: settings.fs(26)
        readonly property int labelW: settings.px(250)

        SettingRow {
          id: soundRow
          width: parent.width
          height: parent.rowH
          art: Glyphs.preset
          label: "SOUND"
          spokenName: "Sound"
          value: settings.onOff(settings.sound)
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
          onStepped: settings.toggle("sound")
        }
        SettingRow {
          id: motionRow
          width: parent.width
          height: parent.rowH
          separator: true
          art: Glyphs.rematch
          label: "REDUCED MOTION"
          spokenName: "Reduced motion"
          value: settings.onOff(settings.reducedMotion)
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
          onStepped: settings.toggle("reducedMotion")
        }
        SettingRow {
          id: scanRow
          width: parent.width
          height: parent.rowH
          separator: true
          art: Glyphs.monitor
          label: "SCANLINES"
          spokenName: "Scanlines"
          value: settings.onOff(settings.scanlines)
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
          onStepped: settings.toggle("scanlines")
        }
        // Not a switch, and the row says why. Design, Modes: Practice has no
        // timer; Time trial, Ghost and Grand Prix have the race clock.
        SettingRow {
          id: timerRow
          width: parent.width
          height: parent.rowH
          separator: true
          art: Glyphs.clock
          label: "TIMER"
          spokenName: "Timer"
          value: settings.raceMode === 0 ? "NO CLOCK IN PRACTICE" : "RACE CLOCK RUNS"
          changeable: false
          fixedLabel: "BY MODE"
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
        }
        SettingRow {
          id: rivalRow
          width: parent.width
          height: parent.rowH
          separator: true
          art: Glyphs.wheel
          label: "RIVALS"
          spokenName: "Rivals"
          value: Theme.levelNames[settings.rivalLevel]
          labelSize: parent.labelPx
          valueSize: parent.valuePx
          labelWidth: parent.labelW
          onStepped: function (delta) {
            var count = Theme.levelNames.length
            Store.setSetting("rivalLevel",
                             ((settings.rivalLevel + delta) % count + count) % count)
          }
        }
      }

      Text {
        x: settings.px(24)
        width: parent.width - settings.px(48)
        y: parent.height - settings.px(24) - height
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "The race mode and the math set are chosen in the garage, "
              + "beside the kart they belong to."
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: settings.fs(15)
        lineHeight: 1.3
      }
    }

    // ---------------------------------------------------------- the resets
    Panel {
      id: resetPanel
      x: page.contentX + page.leftW + settings.px(16)
      y: page.columnsY
      width: page.rightW
      height: page.columnsH
      pad: settings.px(22)
      title: "RESET"
      titleColor: Theme.urgent
      titleSize: settings.fs(17)
      titleSpacing: settings.px(3)

      Column {
        x: settings.px(22)
        y: settings.px(64)
        width: parent.width - settings.px(44)
        spacing: settings.px(22)

        ActionButton {
          id: resetSettingsButton
          width: parent.width
          height: settings.px(122)
          art: Glyphs.rematch
          tone: "quit"
          variant: "secondary"
          label: "RESET SETTINGS"
          sublabel: "ASKS FIRST"
          labelSize: settings.fs(23)
          sublabelSize: settings.fs(14)
          iconSize: settings.px(28)
          Accessible.name: "Reset settings"
          Accessible.description: "Puts sound, motion, scanlines, the kart and the rivals back"
                                  + " to how they started. It asks before it does it."
          onActivated: settings.ask("settings")
        }
        ActionButton {
          id: resetRecordsButton
          width: parent.width
          height: settings.px(122)
          art: Glyphs.trophy
          tone: "quit"
          variant: "secondary"
          label: "RESET GARAGE RECORDS"
          sublabel: "ASKS FIRST"
          labelSize: settings.fs(23)
          sublabelSize: settings.fs(14)
          iconSize: settings.px(28)
          Accessible.name: "Reset garage records"
          Accessible.description: "Clears every best time and its ghost."
                                  + " It asks before it does it."
          onActivated: settings.ask("records")
        }
        ActionButton {
          id: resetFactsButton
          width: parent.width
          height: settings.px(122)
          art: Glyphs.times
          tone: "quit"
          variant: "secondary"
          label: "RESET FACT HISTORY"
          sublabel: "ASKS FIRST"
          labelSize: settings.fs(23)
          sublabelSize: settings.fs(14)
          iconSize: settings.px(28)
          Accessible.name: "Reset fact history"
          Accessible.description: "Clears every fact's attempts and puts the mastery lamps out."
                                  + " It asks before it does it."
          onActivated: settings.ask("facts")
        }

        // Only while there is a quarantine. See `stops` above.
        ActionButton {
          id: discardButton
          visible: settings.quarantined
          width: parent.width
          height: visible ? settings.px(122) : 0
          art: Glyphs.exit
          tone: "quit"
          variant: "secondary"
          label: "START A NEW SAVE FILE"
          sublabel: "ASKS FIRST"
          labelSize: settings.fs(23)
          sublabelSize: settings.fs(14)
          iconSize: settings.px(28)
          Accessible.name: "Start a new save file"
          Accessible.description: "The save file on this computer cannot be read and has been"
                                  + " left alone. This writes over it and starts again."
                                  + " It asks before it does it."
          onActivated: settings.ask("discard")
        }
      }

      // What this screen has to say about the file itself. On a healthy file it
      // is the design's own promise in the child's words; on a quarantined one
      // it is the schema's own sentence, unedited, for the grown-up who came to
      // look -- and it is the only place in the plugin that sentence is written
      // down for a reader rather than for stderr.
      Text {
        x: settings.px(22)
        width: parent.width - settings.px(44)
        y: parent.height - settings.px(24) - height
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: settings.quarantined
              ? ("THE SAVE FILE COULD NOT BE READ.  " + settings.quarantineReason
                 + "  ·  It is still on this computer, exactly as it was, and nothing has been"
                 + " written to it. The three resets above cannot run until it is dealt with.")
              : ("This computer keeps one file: what you chose, your best times, "
                 + "and how each fact has gone. Each reset above clears its own part "
                 + "and leaves the other two alone.")
        color: settings.quarantined ? Theme.urgent : Theme.textLabel
        font.family: Theme.mono
        font.bold: settings.quarantined
        font.pixelSize: settings.fs(15)
        lineHeight: 1.3
      }
    }

    // ------------------------------------------------------------ the exit
    ActionButton {
      id: backButton
      x: page.contentX
      y: page.height - page.pad - height
      width: settings.px(420)
      height: settings.px(84)
      art: Glyphs.exit
      tone: "quit"
      variant: "secondary"
      label: "BACK"
      sublabel: "Esc"
      labelSize: settings.fs(26)
      sublabelSize: settings.fs(15)
      iconSize: settings.px(30)
      Accessible.name: "Back"
      Accessible.description: "Back to the garage. Escape does it too."
      onActivated: settings.leaveRequested()
    }

    // What just happened, for the child who answered the question. It is the
    // only feedback a reset gives, because a reset that succeeds looks exactly
    // like a screen that ignored you.
    Callout {
      id: banner
      x: page.contentX + settings.px(440)
      y: page.height - page.pad - settings.px(84)
      height: settings.px(56)
      width: implicitWidth
      reducedMotion: settings.reducedMotion
      tone: Theme.amber
    }
  }

  // ------------------------------------------------------- the one question
  Confirm {
    id: asker
    anchors.fill: parent
    visible: settings.confirming
    scaleUnit: settings.s
    question: settings.askQuestion
    detail: settings.askDetail
    confirmLabel: settings.pending === "discard" ? "START OVER" : "RESET"
    cancelLabel: "KEEP"
    onConfirmed: settings.answer(true)
    onCancelled: settings.answer(false)
  }
}
