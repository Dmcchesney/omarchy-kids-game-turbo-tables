import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

// PROTOTYPE (proto/golden-hour): the readout below is now a start-line scene
// -- see THE FRAME further down. The four beats, the type-ahead and Escape
// are the design's and are unchanged; the comment that follows describes them.
//
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

  // ============================================================ THE FRAME
  //
  // PROTOTYPE (proto/golden-hour). Everything below this line is the visual
  // proposal; everything above it is the countdown the design specifies and
  // is unchanged: four beats, `finished()`, Escape, the GO-beat type-ahead.
  //
  // The composition is the bar's: the child's kart on the start line, seen
  // from behind-right and low; the sun huge behind it, straddling the horizon;
  // hills; the neon grid floor; a checkered gantry ahead. The number is
  // enormous and cream, over the sky. On GO the word steps up and the first
  // fact stands where the number stood, over the sun, readable -- which is
  // what the design's sentence asks for.
  //
  // The kart is the one the garage settings describe, so the kart on the line
  // is the kart the child just built.
  readonly property int kartBody: Store.setting("kartBody")
  readonly property int kartPaint: Store.setting("kartPaint")
  readonly property int kartNumber: Store.setting("kartNumber")

  // Where the kart stands, as fractions of the frame; the scene lays the long
  // shadow from the same numbers.
  // PIECE C: the car is placed by its wheels' contact point, and the baked
  // cell carries its own contact shadow below that point, so the foot sits
  // higher than the v1 sprite's did: the wheels on the line, the shadow
  // running on down the road under the footer.
  readonly property real kartFootX: 0.44
  readonly property real kartFootY: 0.875

  CountdownScene {
    id: scene
    anchors.fill: parent
    kartFootX: countdown.kartFootX
    kartFootY: countdown.kartFootY
    kartFootW: 0.27
  }

  // PIECE C: the car on the line is a cell of its sheet -- the road camera,
  // rear square to us, at three times its pixels -- stood on the start line
  // by its contact point, which is the point the scene's long shadow is laid
  // from.
  CarSprite {
    id: hero
    x: Math.round(countdown.width * countdown.kartFootX)
    y: Math.round(countdown.height * countdown.kartFootY)
    body: countdown.kartBody
    paint: countdown.kartPaint
    number: countdown.kartNumber
    camera: "road"
    yaw: 0
    sheetScale: 1.0
    pixelScale: 3
    z: 1
  }

  // ------------------------------------------------------------ the header
  // Where it was: the lap and the table, top left.
  Row {
    id: header
    x: countdown.px(48)
    y: countdown.px(40)
    spacing: countdown.px(18)
    z: 5

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

  // ------------------------------------------------------------- the type
  //
  // Cream over a sky that is pink and a sun that is cream: without a shadow
  // the `1` would vanish into the disc on the beat it matters most. So every
  // big word here carries the long shadow the rest of the frame carries --
  // the same near-black purple, thrown down and left, the way the kart's is.
  readonly property color inkShadow: Qt.rgba(0.235, 0.07, 0.157, 0.82)

  // The counted beats: 3, 2, 1, enormous, over the sky. On GO the word steps
  // up to the top third and shrinks to make room for the fact.
  Item {
    id: beatGlyph
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.go ? Math.round(countdown.height * 0.04)
                    : Math.round(countdown.height * 0.10)
    width: beatFace.implicitWidth
    height: beatFace.implicitHeight
    z: 4

    Text {
      textFormat: Text.PlainText
      text: countdown.beatWord
      color: countdown.inkShadow
      font: beatFace.font
      x: -countdown.px(countdown.go ? 8 : 16)
      y: countdown.px(countdown.go ? 8 : 16)
    }
    Text {
      id: beatFace
      textFormat: Text.PlainText
      text: countdown.beatWord
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: countdown.go ? Math.round(countdown.height * 0.24)
                                   : Math.round(countdown.height * 0.58)
      font.letterSpacing: countdown.go ? countdown.px(20) : 0
    }

    // One pulse per beat, and nothing at all under reduced motion, which the
    // design's accessibility section asks for by name.
    transformOrigin: Item.Center
    scale: 1.0
    SequentialAnimation on scale {
      running: countdown.visible && !countdown.reducedMotion
      loops: Animation.Infinite
      NumberAnimation { from: 1.10; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
      PauseAnimation { duration: Math.max(0, countdown.beatMs - 260) }
    }
  }

  // -------------------------------------------------------- the first fact
  //
  // Drawn at the size the race draws it, over the sun, from the GO beat. The
  // design's type rule is that "the fact is never smaller than a tenth of the
  // screen height"; this is nearly a fifth.
  Item {
    id: factText
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(countdown.height * 0.31)
    width: factFace.implicitWidth
    height: factFace.implicitHeight
    z: 3
    opacity: countdown.go ? 1.0 : 0.0
    Behavior on opacity {
      enabled: !countdown.reducedMotion
      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Text {
      textFormat: Text.PlainText
      text: countdown.factText
      color: countdown.inkShadow
      font: factFace.font
      x: -countdown.px(8)
      y: countdown.px(8)
    }
    Text {
      id: factFace
      textFormat: Text.PlainText
      text: countdown.factText
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.round(countdown.height * 0.19)
      font.letterSpacing: countdown.px(8)
    }
  }

  // ------------------------------------------------ the type-ahead readout
  //
  // What the child has typed on the GO beat, under the fact, so the keys
  // visibly land instead of vanishing. Empty until something is pressed.
  Row {
    id: aheadRow
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(countdown.height * 0.60)
    spacing: countdown.px(10)
    visible: countdown.go && countdown.typedAhead.length > 0
    z: 4

    Repeater {
      model: countdown.typedAhead

      Rectangle {
        width: countdown.px(52)
        height: countdown.px(70)
        radius: Theme.cornerRadiusSmall
        color: Qt.rgba(0.157, 0.055, 0.153, 0.94)
        border.width: 2
        border.color: Theme.cream

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
  // Where it was. The prompt warms to cream on GO instead of lime: lime is the
  // garage's, and there is no lime in this light.
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.height - countdown.px(96)
    textFormat: Text.PlainText
    text: countdown.go ? "TYPE THE ANSWER" : "GET READY"
    color: countdown.go ? Theme.cream : Qt.rgba(Theme.cream.r, Theme.cream.g, Theme.cream.b, 0.70)
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: countdown.fs(24)
    font.letterSpacing: countdown.px(4)
    z: 5
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.height - countdown.px(56)
    textFormat: Text.PlainText
    text: "ESC  BACK TO THE GARAGE"
    color: Qt.rgba(Theme.cream.r, Theme.cream.g, Theme.cream.b, 0.55)
    font.family: Theme.mono
    font.pixelSize: countdown.fs(16)
    font.letterSpacing: countdown.px(2)
    z: 5
  }
}
