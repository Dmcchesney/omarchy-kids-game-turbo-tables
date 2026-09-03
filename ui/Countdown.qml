import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

// The start of a race: four beats on the terminal readout, and the first fact
// already on screen behind them.
//
// Design, Race format: "the garage, then a countdown on the terminal readout,
// `3` `2` `1` `GO`, with the first fact readable behind `GO`." Two things in
// that sentence do work. The countdown is on a readout -- a gauge face in the
// middle of the screen, not a number filling it -- and the fact is *behind* it,
// which means the fact is drawn first, at the size the race will draw it, and
// the readout sits over it and gets out of the way as GO lands. A child who
// reads `7 x 8` during GO starts the race already thinking about it, which is
// the whole reason the design puts it there.
//
// The fact is real. It comes out of the engine's own lap deck for this seed and
// this lap, so what stands behind GO is the question the race asks first and
// not a sample.
//
// ROUND 2 -- THE GO BEAT TAKES THE KEYS IT ASKS FOR. The footer flips to
// `TYPE THE ANSWER` on the GO beat and the race does not take over until the
// beat after it, so for a full second this screen invited input and dropped it:
// two digits typed on the GO beat, zero accepted, measured. A child who reads
// the first fact behind GO and starts typing is doing exactly what the design
// put the fact there for, and the screen was throwing it away. So the GO beat
// now buffers digits and Backspace, and `finished()` hands them over -- the
// keys land in the race in the order they were pressed. Before GO nothing is
// typed and nothing is chosen: the footer says GET READY and means it.
//
// Escape puts the child back in the garage, on every beat.
FocusScope {
  id: countdown

  // The overlay and the harness hand focus here.
  readonly property Item focusTarget: countdown

  signal finished()
  signal abortRequested()

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ------------------------------------------------------------- the race
  property int seed: 42
  // The preset the garage is set to, as the Store holds it: 0 is 2-5, 1 is
  // 2-10, 2 is the full 1-12 Grand Prix.
  readonly property int mathSet: Store.setting("mathSet")
  readonly property var presetIds: ["2-5", "2-10", "1-12"]
  readonly property string preset: presetIds[Math.max(0, Math.min(2, mathSet))]
  readonly property var tables: Engine.tablesForPreset(countdown.preset)
  readonly property int firstTable: countdown.tables.length > 0 ? countdown.tables[0] : 1

  // The host may hand the real question down once a race exists; until then
  // the deck says what it is. Both roads end at the same fact for a given
  // seed, because the deck is the deck.
  property int fact: -1
  readonly property int shownFact: {
    if (countdown.fact >= 0)
      return countdown.fact
    var deck = Engine.lapDeck(countdown.seed, 0, countdown.firstTable)
    return deck.length > 0 ? deck[0] : Engine.packFact(countdown.firstTable, 1)
  }
  readonly property string factText: Engine.factLabel(countdown.shownFact)

  readonly property bool reducedMotion: Store.setting("reducedMotion") === true

  // ------------------------------------------------------------- the beats
  // Design, Motion: "1 s countdown beats".
  property int beatMs: 1000
  // 0, 1, 2 are 3, 2, 1; 3 is GO. It stays on GO when the beat after it has
  // run, so a screen with nothing listening still shows the last frame of the
  // countdown rather than an empty stage.
  property int beat: 0
  readonly property var beatWords: ["3", "2", "1", "GO"]
  readonly property string beatWord: beatWords[Math.max(0, Math.min(3, beat))]
  readonly property bool go: beat >= 3
  property bool done: false

  // The digits pressed on the GO beat, in the order they were pressed. Held as
  // an array of small integers rather than as text so nothing here builds a
  // string, and read by the flow the instant `finished()` fires.
  property var typedAhead: []

  function restart() {
    countdown.beat = 0
    countdown.done = false
    countdown.typedAhead = []
  }

  // The countdown counts while it is the screen the child is looking at, and
  // starts over whenever it becomes that screen again. A beat that ran while
  // the screen was hidden would mean a race that started before the child saw
  // it, and a second race that opened on GO.
  onVisibleChanged: if (visible) countdown.restart()

  Timer {
    id: ticker
    interval: countdown.beatMs
    repeat: true
    running: countdown.visible && !countdown.done
    onTriggered: {
      if (countdown.beat < 3) {
        countdown.beat += 1
        return
      }
      // The GO beat has had its second. The race takes over from here, and
      // `done` is what stops the timer.
      countdown.done = true
      countdown.finished()
    }
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Countdown"
  Accessible.description: "The race starts in " + countdown.beatWord
                          + ". The first question is " + countdown.factText
                          + (countdown.go ? ". You can start typing the answer now." : "")
                          + " Escape goes back to the garage."

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      ticker.stop()
      countdown.abortRequested()
      event.accepted = true
      return
    }
    // Only on the GO beat, which is the only beat that asks for an answer.
    if (!countdown.go)
      return
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
      // The longest answer in the 1-12 tables is three digits, so three is all
      // a child can usefully have typed before the race arrives.
      if (countdown.typedAhead.length < 3) {
        var next = countdown.typedAhead.slice()
        next.push(event.key - Qt.Key_0)
        countdown.typedAhead = next
      }
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Backspace) {
      if (countdown.typedAhead.length > 0) {
        var shorter = countdown.typedAhead.slice()
        shorter.pop()
        countdown.typedAhead = shorter
      }
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.ground
  }

  // The diagnostic grid the garage floor carries, faint, so the countdown
  // stands in the same room as the screen before it.
  Item {
    anchors.fill: parent
    opacity: 0.16

    Repeater {
      model: Math.max(1, Math.floor(countdown.height / Math.max(1, countdown.px(48))))
      Rectangle {
        y: index * countdown.px(48)
        width: countdown.width
        height: 1
        color: Theme.teal
      }
    }
    Repeater {
      model: Math.max(1, Math.floor(countdown.width / Math.max(1, countdown.px(48))))
      Rectangle {
        x: index * countdown.px(48)
        width: 1
        height: countdown.height
        color: Theme.teal
      }
    }
  }

  // ------------------------------------------------------------ the header
  Row {
    id: header
    x: countdown.px(48)
    y: countdown.px(40)
    spacing: countdown.px(18)

    Text {
      textFormat: Text.PlainText
      text: "LAP 1 / " + countdown.tables.length
      color: Theme.amber
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: countdown.fs(26)
      font.letterSpacing: countdown.px(3)
    }
    Text {
      textFormat: Text.PlainText
      text: Engine.tableName(countdown.firstTable)
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: countdown.fs(26)
      font.letterSpacing: countdown.px(3)
    }
  }

  // -------------------------------------------------------- the first fact
  //
  // Drawn at the size the race draws it, in the middle of the screen, from the
  // very first beat. The design's type rule is that "the fact is never smaller
  // than a tenth of the screen height"; this is a fifth of it, because during
  // the countdown there is nothing else on screen competing for the space.
  Text {
    id: factText
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: countdown.factText
    color: Theme.cream
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: Math.round(countdown.height * 0.19)
    font.letterSpacing: countdown.px(8)
    z: 2
    // The readout owns the frame for the three counted beats; the fact takes it
    // over on GO, which is the beat the design says it has to be readable on.
    opacity: countdown.go ? 1.0 : 0.0
    Behavior on opacity {
      enabled: !countdown.reducedMotion
      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
  }

  // ---------------------------------------------------- the terminal readout
  //
  // The gauge the beats are counted on. It is sized around the fact rather than
  // to a fixed box, so `12 x 11` never hangs out of its own bezel, and it thins
  // out to almost nothing on GO.
  //
  // On the last beat the word GO steps up out of the readout to the rail above
  // it and the fact is left alone inside the frame at full strength. That is
  // what "the first fact readable behind GO" has to mean in practice: at the
  // GO beat the child reads both, and a lime GO stamped across the middle of
  // `1 x 6` would leave them reading neither. It was drawn that way first and a
  // screenshot settled it.
  Item {
    id: terminal
    anchors.centerIn: parent
    width: Math.min(countdown.width - countdown.px(96),
                    factText.implicitWidth + countdown.px(140))
    height: Math.min(countdown.height - countdown.px(300),
                     factText.implicitHeight + countdown.px(90))

    Rectangle {
      id: bezel
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g, Theme.panelSunken.b,
                     countdown.go ? 0.18 : 0.93)
      border.width: 2
      border.color: countdown.go ? Theme.lime : Theme.amberDeep

      Behavior on color {
        enabled: !countdown.reducedMotion
        ColorAnimation { duration: 200 }
      }
    }

    // Rivets, the design's gauge motif.
    Repeater {
      model: 4
      Rectangle {
        width: countdown.px(7)
        height: width
        radius: width / 2
        color: Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.30)
        x: (index % 2 === 0) ? countdown.px(12) : terminal.width - countdown.px(12) - width
        y: (index < 2) ? countdown.px(12) : terminal.height - countdown.px(12) - height
      }
    }

    Text {
      id: beatGlyph
      anchors.horizontalCenter: parent.horizontalCenter
      y: countdown.go ? -(height + countdown.px(26))
                      : Math.round((terminal.height - height) / 2)
      z: 3
      textFormat: Text.PlainText
      text: countdown.beatWord
      color: countdown.go ? Theme.lime : Theme.amber
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: countdown.go ? countdown.fs(104)
                                   : Math.round(terminal.height * 0.74)
      font.letterSpacing: countdown.go ? countdown.px(14) : 0

      // One pulse per beat, and nothing at all under reduced motion, which the
      // design's accessibility section asks for by name.
      scale: 1.0
      SequentialAnimation on scale {
        // Off while the screen is not on screen: an infinite animation on a
        // hidden item is a repaint the game is paying for and nobody is
        // watching.
        running: countdown.visible && !countdown.reducedMotion
        loops: Animation.Infinite
        NumberAnimation { from: 1.14; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
        PauseAnimation { duration: Math.max(0, countdown.beatMs - 260) }
      }
    }
  }

  // ------------------------------------------------ the type-ahead readout
  //
  // What the child has typed on the GO beat, drawn where the race will draw the
  // answer field, so the keys visibly land instead of vanishing. Empty until
  // something is pressed, so a child who waits sees nothing new.
  Row {
    id: aheadRow
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(countdown.height * 0.68)
    spacing: countdown.px(10)
    visible: countdown.go && countdown.typedAhead.length > 0
    z: 4

    Repeater {
      model: countdown.typedAhead

      Rectangle {
        width: countdown.px(52)
        height: countdown.px(70)
        radius: Theme.cornerRadiusSmall
        color: Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g, Theme.panelSunken.b, 0.94)
        border.width: 2
        border.color: Theme.lime

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(modelData)
          color: Theme.cream
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: countdown.fs(48)
        }
      }
    }
  }

  // ------------------------------------------------------------ the footer
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.height - countdown.px(96)
    textFormat: Text.PlainText
    text: countdown.go ? "TYPE THE ANSWER" : "GET READY"
    color: countdown.go ? Theme.lime : Theme.textLabel
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: countdown.fs(24)
    font.letterSpacing: countdown.px(4)
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.height - countdown.px(56)
    textFormat: Text.PlainText
    text: "ESC  BACK TO THE GARAGE"
    color: Theme.textLabel
    font.family: Theme.mono
    font.pixelSize: countdown.fs(16)
    font.letterSpacing: countdown.px(2)
  }
}
