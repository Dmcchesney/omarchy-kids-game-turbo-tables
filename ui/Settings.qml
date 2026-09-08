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

  // PIECE M ROUND 3 -- THE 400 ms LOCKOUT IS GONE, AND THE DEFECT IT WAS
  // HIDING IS FIXED WHERE IT LIVES.
  //
  // Round two found a real thing: three clicks 16 ms apart at the question's
  // own `⏎  ANSWER` line answered the question with the first and, with the two
  // nobody meant to send, changed the RIVALS row underneath -- because the
  // question's footer stands on top of that row and the row comes back to life
  // the instant the question closes.
  //
  // Round two's fix was here, and it was the wrong place and the wrong input
  // device: this page carried `enabled: !settings.confirming &&
  // !settings.justAnswered`, so for 400 ms after every answer the whole screen
  // took nothing at all. A critic measured what that cost: a Down 16 ms after
  // answering was not delayed, it was DROPPED, and for the length of the window
  // no item on this screen held focus -- `focusedName()` was empty, the focus
  // ring was off the screen entirely, which is the state the comment three
  // lines below `--focus -1` calls one no child should ever be in. A keyboard
  // user was paying for a mouse defect. The 400 ms timer that put the keyboard
  // back afterwards was repairing damage this page had done to itself.
  //
  // The hazard is a MODAL hazard: a modal whose own controls overlap live
  // controls behind it. `parts/Confirm.qml` now consumes pointer presses over
  // its whole extent, for as long as it is up and for one double-click interval
  // after it closes, which is exactly the window in which a press cannot have
  // been meant for the screen behind. The rule is the modal's, so any screen
  // that asks a question gets it; this page has nothing left to do about it and
  // is switched off only while the question is actually up.
  //
  // What the child gets back: the keyboard, immediately. `answer()` puts the
  // focus on the stop they were on before the question opened, on the same turn
  // as the answer, and it stays there -- there is no window in which this screen
  // has no focus ring and no window in which it drops a keystroke.

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
    // from. Nothing else in the plugin calls
    // `Store.discardQuarantinedFile()`.
    //
    // The two halves say opposite things because the two halves DO opposite
    // things, and for a round this screen said the read-side sentence to both.
    //
    //   read side   nothing in this session was ever read off that file, so
    //               what the write puts there is the defaults, and every best
    //               time and every fact on the disk goes. That is the truth,
    //               and it is why the question is asked at all.
    //   write side  the file read perfectly and could not be written to, so
    //               the session is still holding the child's records and their
    //               fact history and that is exactly what gets written.
    //               Measured on the way out of a write-side quarantine: 1
    //               record and 48 facts kept, which is what
    //               `test_46_recovering_from_a_write_side_quarantine_keeps_the_session`
    //               asserts. Telling a parent they will lose everything on the
    //               one screen with no undo makes KEEP the sensible answer, and
    //               keeps a family locked for nothing.
    if (pending === "discard")
      return settings.writeSide
          ? "The save file on this computer could not be written to, so nothing since then "
            + "has been saved. Nothing you have done today is lost: saying yes writes what "
            + "this game is holding right now -- today's best times and fact history "
            + "included -- over the file that could not be written to. Saying no keeps the "
            + "file exactly as it is. There is no undo."
          : "The save file on this computer cannot be read, so it has been left alone and "
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

  // Which half of the rule stopped the file, so this screen names the right
  // one. A critic filled a disk in the VM, watched the file read perfectly and
  // the write fail, and read "THE SAVE FILE COULD NOT BE READ" off this screen
  // -- a parent sent to look at a file that is fine, and offered a button that
  // proposed to overwrite it. The Store now says which it was.
  readonly property bool writeSide: Store.quarantineKind === "write"
  readonly property string quarantineHeadline: settings.writeSide
        ? "THE SAVE FILE COULD NOT BE WRITTEN TO."
        : "THE SAVE FILE COULD NOT BE READ."

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
  // ROUND 5. This sentence used to read "Tab moves, arrows change", which is the
  // half-true map round three's defect #7 found on the garage: on this screen
  // Up and Down MOVE (see `Keys.onPressed` below) and only Left and Right
  // change a value, which is exactly what the key rail in the title bar prints.
  // A screen-reader user was given a different key map from the one on screen,
  // and the wrong half of it was the half that says how to get around.
  Accessible.description: "Sound, motion, scanlines and rivals, and the three resets. "
                          + "Tab and the up and down arrows move, left and right change, "
                          + "Enter chooses, Escape goes back."

  Keys.onPressed: function (event) {
    if (settings.confirming)
      return
    if (event.key === Qt.Key_Escape) {
      settings.leaveRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      // ROUND 3 -- THIS SCREEN PRINTED A KEY IT DID NOT HONOUR.
      //
      // The garage got this in its round 8 and this screen never did. Its own
      // title band prints `TAB  ↑ ↓   MOVE` and its screen-reader description
      // says "Tab and the up and down arrows move", and Tab moved nothing:
      // there was no branch for it here, and every stop carries
      // `activeFocusOnTab: false` (see the note in `ui/Garage.qml`) so Qt's
      // implicit chain had nothing to walk either. A screen that prints a key
      // it does not honour is worse than one that prints nothing, because the
      // child who reads it presses it and learns that reading the screen does
      // not help.
      //
      // Shift+Tab arrives as Key_Backtab on some platforms and as Key_Tab with
      // the Shift modifier on others, so both are read rather than trusting
      // whichever one this machine happens to send.
      var back = event.key === Qt.Key_Backtab
                 || (event.modifiers & Qt.ShiftModifier) !== 0
      settings.moveFocus(back ? -1 : 1)
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

  // PIECE M -- THE ONE ALPHA BLEND THAT COST HALF THIS SCREEN.
  //
  // This filled the window at `Qt.rgba(Theme.panel..., 0.55)` over the
  // `Theme.ground` rectangle above and nothing else, so at 1080p it was a
  // 1888 x 1048 antialiased rounded rectangle with a per-pixel alpha blend --
  // and a translucent fill loses the software renderer's opaque fast path
  // entirely. The colour it produced never varied, because the only thing
  // behind it is a constant.
  //
  // `Theme.panelOnGround` is that composite, worked out once (see the note
  // there). The pixels are identical -- proved by a frame diff of the whole
  // 1920 x 1080 window, not asserted -- and the measured cost is in this
  // round's report with its load average beside it.
  //
  // `ui/parts/Panel.qml` is NOT changed. It is shared with the garage, whose
  // cards are translucent over a room that is genuinely drawn behind them; the
  // shortcut is true of these two full-window instances and of nothing else.
  Panel {
    id: page
    anchors.fill: parent
    anchors.margins: settings.px(16)
    color: Theme.panelOnGround
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

      // A key LEGEND, not a row of controls, and after round 4 it does not look
      // like one either: no box, no border, no fill, because the four keycaps
      // that used to be here were drawn exactly like the live `S  SETTINGS AND
      // RESETS` keycap in the garage's title band. See ui/parts/KeyLegend.qml.
      KeyLegend {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        gap: settings.px(18)
        textSize: settings.fs(14)
        letterSpacing: 0
        // One arrow contract across every screen of the flow: Tab and the up and
        // down arrows move, left and right change a value where the stop has
        // one. `ARROWS CHANGE` was true of four rows on this screen and false of
        // the other four, and it disagreed with the results screen, where left
        // and right moved.
        groups: [ { key: "TAB  ↑ ↓", what: "MOVE" },
                  { key: "◀ ▶", what: "CHANGE" },
                  { key: "ENTER", what: "CHOOSE" },
                  { key: "ESC", what: "BACK" } ]
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
        id: resetColumn
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
          Accessible.description: (settings.writeSide
                                   ? "The save file on this computer could not be written to."
                                   : "The save file on this computer cannot be read and has been"
                                     + " left alone.")
                                  + " This writes over it and starts again."
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
        // Bottom-aligned, with a floor. It grows upward as the sentence gets
        // longer, and the file layer's own sentence about a save file this
        // computer will not let the game write to is four lines wide in this
        // column -- long enough, measured in the VM, to climb over the START A
        // NEW SAVE FILE button it is about and make both unreadable. The floor
        // is the column above it: this paragraph may take the space under the
        // buttons and no more.
        y: Math.max(resetColumn.y + resetColumn.height + settings.px(14),
                    parent.height - settings.px(24) - height)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: settings.quarantined
              // The strip in ui/Game.qml already says the file is untouched, on
              // this screen and every other. What only this screen can say is
              // why the three buttons above it are dead.
              ? (settings.quarantineHeadline + "  " + settings.quarantineReason
                 + "  ·  The three resets above cannot run until it is dealt with.")
              : ("This computer keeps one file: what you chose, your best times, "
                 + "and how each fact has gone. Each reset above clears its own part "
                 + "and leaves the other two alone.")
        color: settings.quarantined ? Theme.urgent : Theme.textLabel
        font.family: Theme.mono
        font.bold: settings.quarantined
        // A step smaller while quarantined: this is the one paragraph on the
        // screen that has to fit whatever the file layer had to say.
        font.pixelSize: settings.quarantined ? settings.fs(14) : settings.fs(15)
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
    // `asking` rather than `visible`: the question has to outlive itself by one
    // double-click interval to swallow the rest of a double-click aimed at its
    // own footer, and only it knows how long that is. See the note at the top of
    // `parts/Confirm.qml`.
    asking: settings.confirming
    scaleUnit: settings.s
    question: settings.askQuestion
    detail: settings.askDetail
    confirmLabel: settings.pending === "discard" ? "START OVER" : "RESET"
    cancelLabel: "KEEP"
    onConfirmed: settings.answer(true)
    onCancelled: settings.answer(false)
  }
}
