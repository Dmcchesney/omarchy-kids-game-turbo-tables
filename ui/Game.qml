import QtQuick

// The flow. One screen at a time, and the only file that decides which.
//
// ---------------------------------------------------------------------------
// WHY THIS FILE EXISTS
// ---------------------------------------------------------------------------
//
// Round one shipped four finished screens that nothing instantiated. The
// overlay hosted `ui/Garage.qml` and ended there -- `onRaceRequested: {}` -- so
// the countdown, the race and the results were dead code, and `ui/Settings.qml`
// and the three save-file resets could not be reached by any key, any click or
// any other means. Every keyboard claim made about those screens was a claim
// about the development harness. This file is the seam that was missing: it is
// what makes them part of the game.
//
// ---------------------------------------------------------------------------
// THE STATE GRAPH
// ---------------------------------------------------------------------------
//
//                  READY UP / ⏎                 last beat
//     ┌── garage ─────────────────► countdown ─────────────► race ──┐
//     │     ▲ ▲                        │  Esc                  │ Esc│  finished
//     │     │ └────────────────────────┘                       │    ▼
//     │     │                                                  └► results
//     │     │            Esc / GARAGE                                │
//     │     └────────────────────────────────────────────────────────┤
//     │     │                                       ⏎ / RACE AGAIN   │
//     │     │                                  ┌─────────────────────┘
//     │     │                                  ▼
//     │     └──── Esc ──── settings        countdown
//     │  S                    ▲
//     └───────────────────────┘
//
// Escape means one thing everywhere in it: back one. From the garage it is back
// out of the game, which is what `leaveRequested` carries to the overlay.
//
// ---------------------------------------------------------------------------
// ONE KEY FROM THE OVERLAY TO PLAYING
// ---------------------------------------------------------------------------
//
// The bar this game is measured against -- the Lode Runner plugin -- is one key
// from opening the overlay to playing, and it blinks the key on the title
// screen. Round one was seven: the garage handed focus to `stops[0]`, the kart
// body, so a child had to press Tab six times to reach READY UP and then Enter,
// and the Enter went nowhere.
//
// The garage's own `focusTarget` is still `stops[0]`, and that is right for a
// screen that stands on its own. It is not right for a summon. The one thing a
// child opened this game to do is race, the kart and the race setup are already
// in the save file from the last time they chose them, and READY UP is the only
// verb on the screen -- so the flow hands focus to READY UP and the count from
// the overlay to the countdown is ONE key. Everything else on the garage is one
// Tab or one Up away, in the same chain, in the same order it always was; the
// child who wants to repaint the kart has lost nothing but the default.
//
// The stop is found by name rather than by index, so it follows the garage's
// chain if that chain is ever reordered.
//
// ---------------------------------------------------------------------------
// THE SETTINGS DOOR, AND WHAT IS TEMPORARY ABOUT IT
// ---------------------------------------------------------------------------
//
// `ui/Garage.qml` declares two signals, `raceRequested` and `leaveRequested`,
// and has no SETTINGS control. It belongs to another builder and is frozen this
// round, so this file cannot add a stop to its focus chain. What it can do is
// own the key itself: `S` on the garage opens the settings screen, and the flow
// prints the key on the garage's own title band so it is not a secret. That is
// a real door -- the resets are reachable by keyboard now, which they were not
// -- but it is the flow reaching over the garage's shoulder, and the right fix
// is a stop in the garage's chain. The exact change is written into this
// round's report so the garage's builder can make it, and when it lands the
// hint and the key below come out.
FocusScope {
  id: game

  // The overlay and the harness hand focus here, and then straight down to the
  // screen that is up. Nothing in this file is a focus stop of its own.
  readonly property Item focusTarget: {
    if (game.screen === "countdown")
      return countdownLoader.item ? countdownLoader.item.focusTarget : null
    if (game.screen === "race")
      return raceLoader.item ? raceLoader.item.focusTarget : null
    if (game.screen === "results")
      return resultsLoader.item ? resultsLoader.item.focusTarget : null
    if (game.screen === "settings")
      return settingsLoader.item ? settingsLoader.item.focusTarget : null
    return game.garageStart
  }

  // The screen that is up, as an item. The flow itself never needs it -- every
  // transition below is a signal from the screen that is leaving -- but a
  // keyboard walkthrough has to be able to ask what it is looking at, and a
  // walkthrough that reads the loaders directly would be testing the loaders.
  readonly property Item currentItem: {
    if (game.screen === "countdown")
      return countdownLoader.item
    if (game.screen === "race")
      return raceLoader.item
    if (game.screen === "results")
      return resultsLoader.item
    if (game.screen === "settings")
      return settingsLoader.item
    return garage
  }

  // The one signal out. The overlay turns it into `dismiss()`, which is what
  // tells the shell the game closed itself.
  signal leaveRequested()

  // The quarantine notice, read back off the notice itself rather than off a
  // second copy of its text. A walkthrough that asserted its own string would
  // not be checking the screen, and "a screen says so" is exactly the claim
  // four rounds of review could not verify because nothing said anything.
  readonly property bool noticeVisible: quarantineNotice.visible
  readonly property string noticeSays: noticeText.text
  readonly property string noticeWhy: noticeWhy_.text

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ---------------------------------------------------------- the screens
  // "garage", "countdown", "race", "results" or "settings".
  property string screen: "garage"

  // The race seed. A race has to differ from the one before it, and this game
  // has no clock and no dates anywhere -- the design's Data table forbids them
  // in the save file and `ui/Race.qml` runs off a monotonic animation clock for
  // the same reason -- so the seed is a counter that steps once per race
  // started. Two races in a session are different races; the first race of a
  // session is the same first race every time, which is a property and not a
  // defect: a child can be shown the same race twice, and a bug report can be
  // reproduced from a fresh save file.
  property int seed: 42

  // The finished `RaceState` the results screen reads. Held here rather than in
  // the results screen so the race can be destroyed the moment it is over.
  property var finishedRace: null

  // ---------------------------------------------------------- the save seam
  //
  // This file is the only thing in `ui/` that owns a race from start to flag,
  // so it is the only thing that can honestly bank one. Design, Data: `records`
  // and `facts` are the two keys a race writes, and `src/engine/save.ts` is the
  // only code allowed to decide what goes into them -- so the flow calls
  // `Store.factHistoryForRace()` on the way in and `Store.commit()` on the way
  // out, and never assembles a record or a fact count itself.
  //
  // The engine's rule, and it is why the two calls are a pair:
  // `commitRace` refuses any commit whose declared baseline is not the file it
  // is being folded into. `Store` remembers the array it handed out and
  // declares that one, and re-points it at the file after every commit -- so
  // committing the same race twice is refused by construction rather than
  // doubling a child's counts, and there is no path here that can pass the
  // wrong baseline because there is no path here that chooses one.
  //
  // The commit happens once, at the flag, before the results screen is built.
  // Not on leaving results, not on RACE AGAIN: those are the second calls the
  // engine would have to refuse, and a screen that has to be refused to be
  // correct is a screen waiting for its refusal to regress.
  property var lastCommit: null

  // The array the running race was seeded with, read fresh from the save file
  // at the countdown rather than held across races.
  property var raceFactHistory: []

  function seedRace() {
    game.raceFactHistory = Store.factHistoryForRace()
  }

  function bankRace(state, timeline) {
    game.lastCommit = Store.commit(state, timeline)
    return game.lastCommit
  }
  // Digits the child typed on the countdown's GO beat, carried into the race.
  property var carriedDigits: []
  // Where to put focus when the garage comes back. -1 means READY UP, which is
  // what a child wants after a race as well as before one; leaving the settings
  // screen restores the stop they were standing on instead.
  property int garageResume: -1

  // The garage setup, in the words the engine uses. The same three tables
  // `ui/Results.qml` reads, kept identical on purpose.
  readonly property var presetIds: ["2-5", "2-10", "1-12"]
  readonly property var modeIds: ["practice", "timeTrial", "ghost", "grandPrix"]
  readonly property var levelIds: ["rookie", "pro", "champion"]
  readonly property string preset: presetIds[Math.max(0, Math.min(2, Store.setting("mathSet")))]
  readonly property string mode: modeIds[Math.max(0, Math.min(3, Store.setting("raceMode")))]
  readonly property string level: levelIds[Math.max(0, Math.min(2, Store.setting("rivalLevel")))]

  // -------------------------------------------------------------- focus
  //
  // READY UP, found by the name the garage gives it rather than by an index, so
  // a reordered chain moves this with it and a renamed one falls back to the
  // garage's own first stop rather than to a wrong control.
  readonly property Item garageStart: {
    var stops = garage.stops
    for (var i = 0; i < stops.length; i++) {
      if (String(garage.focusName(i)).toUpperCase().indexOf("READY") === 0)
        return stops[i]
    }
    return garage.focusTarget
  }

  function pushFocus() {
    // Coming back from the settings screen puts the child on the stop they left
    // the garage from; every other arrival on the garage lands on READY UP.
    if (game.screen === "garage" && game.garageResume >= 0) {
      garage.focusStop(game.garageResume)
      game.garageResume = -1
      return
    }
    var target = game.focusTarget
    if (target)
      target.forceActiveFocus(Qt.TabFocusReason)
  }

  // Every transition hands focus to the incoming screen, and it is the only
  // place that does, so no screen can be shown without one.
  onScreenChanged: Qt.callLater(game.pushFocus)

  // The name of the stop focus is on, for the keyboard walkthrough. Empty when
  // the screen up does not keep a chain.
  function focusedName() {
    if (game.screen === "garage")
      return garage.focusedName()
    var item = game.focusTarget
    if (!item)
      return ""
    try {
      return String(item.Accessible.name)
    } catch (error) {
      return ""
    }
  }

  // ---------------------------------------------------------- transitions
  //
  // Every one of these is called from a signal handler of the screen it is
  // leaving, and a `Loader` going inactive destroys that screen -- so the
  // change is always deferred by one turn of the event loop. Destroying an item
  // from inside its own emitting signal handler is how a router crashes.
  function go(next) {
    Qt.callLater(function () { game.screen = next })
  }

  function startRace() {
    game.carriedDigits = []
    game.lastCommit = null
    // Seeded here rather than in the race screen: the array the race is created
    // with has to be the same array the commit declares as its baseline, and
    // the Store is what holds that. Reading it at the countdown means a reset
    // made on the settings screen a moment ago is already in it.
    game.seedRace()
    game.go("countdown")
  }

  function raceIsOn() {
    var counted = countdownLoader.item
    game.carriedDigits = counted ? counted.typedAhead : []
    game.go("race")
  }

  function raceIsOver(board, timeline) {
    game.finishedRace = board
    // Banked once, here, before the results screen exists. The ghost timeline
    // comes off the race that recorded it; `recordFromRace` is what turns the
    // two into a record, and `commitRace` is what decides whether the design
    // allows one -- Grand Prix never does.
    game.bankRace(board, timeline)
    game.go("results")
  }

  function backToGarage(stop) {
    game.garageResume = stop
    game.seed += 1
    game.go("garage")
  }

  function raceAgain() {
    game.seed += 1
    game.startRace()
  }

  function openSettings() {
    game.garageResume = garage.stopIndex()
    game.go("settings")
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Turbo Tables"
  // The `S` door has to be ANNOUNCED, not only drawn. Round two: the only way
  // to Settings and the three save-file resets was a key printed for a sighted
  // reader and named to nobody, so for a screen-reader user the resets were
  // exactly as unreachable as they were in round one.
  Accessible.description: game.screen === "garage"
                          ? "Press S for settings and resets. Escape leaves the garage."
                          : "Escape goes back one screen."

  // The one key this file owns. Everything else belongs to the screen that is
  // up: a key reaches here only when the focused control and its screen both
  // ignored it. Escape is not taken here -- each screen answers its own, and
  // the garage's becomes `leaveRequested` below.
  Keys.onPressed: function (event) {
    if (game.screen === "garage" && event.key === Qt.Key_S) {
      game.openSettings()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.ground
  }

  // ------------------------------------------------------------ the garage
  //
  // Not in a `Loader`. The manifest sets `keepLoaded: true` so that "the garage
  // a child left is the garage they come back to", and a garage that is rebuilt
  // on every return is a different promise. It is the one screen that is always
  // alive; an invisible item cannot hold focus, so nothing else has to be done
  // to keep it out of the way.
  Garage {
    id: garage
    anchors.fill: parent
    visible: game.screen === "garage"
    focus: true

    onRaceRequested: game.startRace()
    onLeaveRequested: game.leaveRequested()
  }

  // ---------------------------------------------------------- the countdown
  Loader {
    id: countdownLoader
    anchors.fill: parent
    active: game.screen === "countdown"
    visible: active
    sourceComponent: Component {
      Countdown {
        seed: game.seed
        onFinished: game.raceIsOn()
        onAbortRequested: game.backToGarage(-1)
      }
    }
    onLoaded: Qt.callLater(game.pushFocus)
  }

  // --------------------------------------------------------------- the race
  Loader {
    id: raceLoader
    anchors.fill: parent
    active: game.screen === "race"
    visible: active
    sourceComponent: Component {
      Race {
        id: liveRace
        seed: game.seed
        mode: game.mode
        preset: game.preset
        rivalLevel: game.level
        // The child's saved per-fact record, straight from the save file. It
        // has to be the array the Store handed out, because that is the one the
        // commit will declare as its baseline.
        factHistory: game.raceFactHistory
        // `finished(var board)` already hands out the live `RaceState`, which
        // is exactly what `Results.raceState` wants. No conversion, no second
        // copy of the numbers. The ghost timeline is read off the race that
        // recorded it, in the same breath, so the two cannot come from
        // different runs.
        onFinished: function (board) { game.raceIsOver(board, liveRace.ghostTimeline) }
        onLeaveRequested: game.backToGarage(-1)
      }
    }
    onLoaded: {
      // The keys the child pressed on the GO beat, in order.
      item.typeAhead(game.carriedDigits)
      game.carriedDigits = []
      Qt.callLater(game.pushFocus)
    }
  }

  // ------------------------------------------------------------ the results
  Loader {
    id: resultsLoader
    anchors.fill: parent
    active: game.screen === "results"
    visible: active
    sourceComponent: Component {
      Results {
        seed: game.seed
        raceState: game.finishedRace
        // What the save file did with the race that just ended, handed down
        // rather than recomputed: the results screen must not be able to
        // disagree with the file about whether a record was set.
        commitResult: game.lastCommit
        onRaceAgainRequested: game.raceAgain()
        onGarageRequested: game.backToGarage(-1)
      }
    }
    onLoaded: Qt.callLater(game.pushFocus)
  }

  // ----------------------------------------------------------- the settings
  Loader {
    id: settingsLoader
    anchors.fill: parent
    active: game.screen === "settings"
    visible: active
    sourceComponent: Component {
      Settings {
        onLeaveRequested: game.go("garage")
      }
    }
    onLoaded: Qt.callLater(game.pushFocus)
  }

  // ------------------------------------------------- the quarantine notice
  //
  // A quarantine used to be invisible. `Store` kept the child's file safe on
  // disk and ran the session from memory, which is right -- and nothing in
  // `ui/` read `quarantined`, so what the child saw was a garage that looked
  // factory-reset and whose every change silently failed to stick, forever,
  // with the only explanation on stderr. Four review rounds went past that.
  //
  // This is the screen half of it, and it is here rather than on one screen
  // because the condition is not a property of any one of them: the file is
  // unreadable for the whole session, so the notice is up for the whole
  // session. Two lines, in the order the two readers need them:
  //
  //   the child   one sentence they can act on -- fetch a grown-up. No jargon,
  //               no path, no error number. It does not say "corrupt": nothing
  //               of theirs has been lost, and the file is still on the disk.
  //   the parent  `Store.quarantineReason`, the schema's own `path: problem`
  //               line, which is the sentence that tells them what to look at.
  //
  // It needs no keystroke, takes no focus stop and is never dismissible: a
  // notice a child can close is a notice the parent never sees. It is hidden
  // during the countdown and the race, where nothing is being written anyway
  // and a banner over the question would be a fairness problem, and it comes
  // straight back on the results screen.
  Rectangle {
    id: quarantineNotice
    visible: Store.quarantined
             && (game.screen === "garage" || game.screen === "results"
                 || game.screen === "settings")
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: noticeText.implicitHeight + noticeWhy_.implicitHeight + game.px(30)
    color: Qt.rgba(Theme.urgent.r, Theme.urgent.g, Theme.urgent.b, 0.16)
    border.width: Math.max(1, game.px(2))
    border.color: Theme.urgent

    Accessible.role: Accessible.StaticText
    Accessible.name: "Your garage is safe but locked"
    Accessible.description: noticeText.text + " " + noticeWhy_.text

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: game.px(26)
      anchors.rightMargin: game.px(26)
      anchors.verticalCenter: parent.verticalCenter
      spacing: game.px(5)

      Text {
        id: noticeText
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "YOUR GARAGE IS SAFE BUT LOCKED  ·  ask a grown-up. "
              + "Nothing you have won has been lost, and today's changes will not be kept."
        color: Theme.cream
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: Math.max(13, game.fs(19))
        font.letterSpacing: game.px(1)
      }

      // For the grown-up the child fetches. It is the schema's own words,
      // unedited, because a reworded error is one a maintainer cannot search
      // for.
      Text {
        id: noticeWhy_
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "For a grown-up: " + Store.quarantineReason
              + "  ·  The save file has been left exactly as it is. "
              + "Press S for settings to start a new one."
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: Math.max(11, game.fs(15))
      }
    }
  }

  // ------------------------------------------------------- the settings key
  //
  // Drawn by the flow, on the garage's own title band, in the garage's own
  // keycap style. It is here and not in `ui/Garage.qml` because that file is
  // another builder's and frozen this round -- see the note at the top. A key
  // a child cannot find is not a door, so as long as the flow owns the key it
  // owns saying what the key is.
  Row {
    id: settingsHint
    visible: game.screen === "garage"

    // Named, so the door is a door for a screen reader too. It is a readout and
    // not a stop in the Tab chain: `S` works from every one of the garage's
    // eight stops, so putting a ninth stop in front of the child would add a Tab
    // press to reach the race and change nothing about who can find the key.
    Accessible.role: Accessible.StaticText
    Accessible.name: "S, settings and resets"
    Accessible.description: "Press S to open settings, where sound, motion, the rival level and the three resets are."
    anchors.horizontalCenter: parent.horizontalCenter
    y: game.px(38) + Math.round((game.px(80) - height) / 2)
    spacing: game.px(9)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: hintKey.implicitWidth + game.px(15)
      height: game.px(28)
      radius: Theme.cornerRadiusSmall
      color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.07)
      border.width: 1
      border.color: Theme.lineStrong

      Text {
        id: hintKey
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "S"
        color: Theme.text
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: Math.max(13, game.fs(17))
        font.letterSpacing: game.px(1)
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "SETTINGS AND RESETS"
      color: Theme.textLabel
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.max(13, game.fs(17))
      font.letterSpacing: game.px(2)
    }
  }
}
