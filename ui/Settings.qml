import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

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
  // A save file in the engine's own shape, assembled from what the Store holds.
  // The settings half is deliberately left at the engine's defaults: none of
  // the three operations reads it -- `resetSettings` replaces it outright and
  // the other two do not touch it -- so filling it in would be ceremony that
  // could only be wrong. Records and fact history are carried across because a
  // reset of one must leave the others provably alone, and this is the object
  // that gets to prove it.
  function saveFileFromStore() {
    var file = Engine.emptySave()
    try {
      if (Store.records && typeof Store.records === "object")
        file.records = Store.records
      if (Store.facts instanceof Array)
        file.facts = Store.facts
    } catch (error) {
      // A file the engine cannot read is a file this screen still has to be
      // able to clear. The empty one it started with does that.
      console.warn("Settings: the save file could not be read for a reset: " + error)
    }
    return file
  }

  // ROUND 2 -- ONE WRITE, AND IT SAYS SO WHEN THERE WAS NONE.
  //
  // Two things were wrong with the version this replaces and both were found by
  // watching the file rather than the screen's own view of it.
  //
  //   - A confirmed RESET SETTINGS patched nine keys through `Store.setSetting`,
  //     and every one of those flushes the whole save file. Nine atomic writes
  //     for one button press, and each of the eight intermediate ones left a
  //     half-reset settings object on disk. The new settings object is built in
  //     full here and written once, which is what the other two resets already
  //     did.
  //   - `Store.setSetting` refuses every write while `Store.loaded` is false,
  //     which `TurboTables.qml` documents as a real outcome for a save file it
  //     cannot read. The old code ignored the return value and the banner said
  //     SETTINGS ARE BACK TO HOW THEY STARTED over a file that had not changed.
  //     Every path now returns whether anything was written, and `answer()`
  //     says NOTHING WAS CHANGED when the answer is no.
  //
  // Returns true when the save file was actually written.
  function applyReset(which) {
    if (!Store.loaded)
      return false
    var file = saveFileFromStore()
    if (which === "settings") {
      var fresh = Engine.resetSettings(file).settings
      // Back into the Store's own key names. The engine counts the kart body
      // and paint from one and names the rival level; the garage indexes both
      // from zero, which is the seam `migrateLegacyGarageSettings` crosses in
      // the other direction.
      var next = {}
      for (var key in Store.settings)
        next[key] = Store.settings[key]
      next["sound"] = fresh.sound
      next["reducedMotion"] = fresh.reducedMotion
      next["scanlines"] = fresh.scanlines
      next["kartBody"] = fresh.kart - 1
      next["kartPaint"] = fresh.paint - 1
      next["kartNumber"] = fresh.number
      next["rivalLevel"] = Math.max(0, Engine.RIVAL_LEVEL_ORDER.indexOf(fresh.rivalLevel))
      // Race mode and math set are the garage's two choices and the engine's
      // settings shape has no column for them, so their reset value is the
      // Store's own default rather than something invented here.
      next["raceMode"] = Store.defaultSettings["raceMode"]
      next["mathSet"] = Store.defaultSettings["mathSet"]
      Store.settings = next
      Store.flush()
      Store.changed()
      return true
    }
    if (which === "records") {
      Store.records = Engine.resetRecords(file).records
      Store.flush()
      Store.changed()
      return true
    }
    Store.facts = Engine.resetFacts(file).facts
    Store.flush()
    Store.changed()
    return true
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
    return "FACT HISTORY CLEARED"
  }

  readonly property string askQuestion: {
    if (pending === "settings")
      return "RESET SETTINGS?"
    if (pending === "records")
      return "RESET GARAGE RECORDS?"
    if (pending === "facts")
      return "RESET FACT HISTORY?"
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
    return ""
  }

  // ---------------------------------------------------------- focus chain
  // Reading order, top to bottom and left to right: the five rows that can
  // change, then the three resets, then the way out. The TIMER row is not in
  // it, for the same reason the garage's TRACK and GOAL rows are not: a stop
  // that cannot act is a dead press.
  readonly property var stops: [soundRow.focusItem, motionRow.focusItem, scanRow.focusItem,
                                rivalRow.focusItem,
                                resetSettingsButton, resetRecordsButton, resetFactsButton,
                                backButton]

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
      }

      Text {
        x: settings.px(22)
        width: parent.width - settings.px(44)
        y: parent.height - settings.px(24) - height
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "This computer keeps one file: what you chose, your best times, "
              + "and how each fact has gone. Each reset above clears its own part "
              + "and leaves the other two alone."
        color: Theme.textLabel
        font.family: Theme.mono
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
    confirmLabel: "RESET"
    cancelLabel: "KEEP"
    onConfirmed: settings.answer(true)
    onCancelled: settings.answer(false)
  }
}
