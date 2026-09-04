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

  // ============================================ TYPE THAT SURVIVES THE SUN
  //
  // ROUND 6. The cast shadow above was the ONLY thing keeping the GO beat's
  // fact off the sun, and it is thrown down and to the LEFT -- which is where
  // a sun low and behind-right puts a shadow, and therefore the one direction
  // that does no work at all on the edge nearest the disc. Measured on the
  // shipped 1920 x 1080 GO frame: 89 cream pixels touched the sun's own
  // `#efcb72` directly, at 1.26:1. Readable in the frame a builder shot, one
  // palette change from not being readable at all.
  //
  // So a big word here is now built the way the plan's light rule builds every
  // other object in this scene -- "one key, the sun, low and behind-right of
  // the subject. Every object has a warm rim on its sun side and a cool purple
  // body; shadows run long toward the camera":
  //
  //   the cast shadow   near-black purple, down and left, long -- unchanged;
  //   the body contour  the same purple, opaque, all the way round, so no
  //                     cream pixel ever borders the sun. 14.3:1 against the
  //                     cream it holds and 11.4:1 against the disc it sits on;
  //   the sun-side rim  `#f0b07a`, the palette's rim light, up and to the
  //                     right, inside the contour, so the word is lit from
  //                     where everything else in the frame is lit from.
  //
  // The contour is what fixes the contrast; the rim is what makes the word
  // belong to the light. Both are in `LitWord` below, once, because the
  // numeral and the fact were two copies of the same two Texts and the round
  // that gave them a third and a fourth would have made four.
  readonly property color inkBody: "#280e27"
  readonly property color inkRim: "#f0b07a"
  // At 1920 x 1080 this is 6 px of contour around a numeral whose ink is over
  // 400 px tall: a keyline, not an outline drawing.
  readonly property int inkContour: Math.max(2, countdown.px(6))
  readonly property int inkRimOffset: Math.max(1, Math.round(countdown.inkContour * 0.55))

  // One big word in this light: cast shadow, contour, rim, face. `drop` is the
  // cast shadow's throw and `contour` the keyline's width, both already in
  // frame pixels; the caller owns them because the caller is what fits the
  // word to the board.
  component LitWord: Item {
    id: word
    property string words: ""
    property int size: 10
    property int spacing: 0
    property int drop: 0
    property int contour: 0
    property int rimOffset: 0
    property color faceTone: "#f2e6c4"
    property color shadowTone: "#000000"
    property color bodyTone: "#000000"
    property color rimTone: "#f0b07a"

    width: wordFace.implicitWidth
    height: wordFace.implicitHeight

    // The cast shadow: long, down and toward the camera, away from the sun.
    Text {
      textFormat: Text.PlainText
      text: word.words
      color: word.shadowTone
      font: wordFace.font
      x: -word.drop
      y: word.drop
    }
    // The body contour: the same word, opaque, offset one keyline out around a
    // CIRCLE. This is the pair the contrast figure is measured on.
    //
    // The circle is the whole point and the first draft did not have it. Eight
    // copies at the four axes and the four corners is a square dilation: the
    // diagonal copies land 1.41 keylines out, so every convex corner of a glyph
    // grows a square step, and on a diagonal stroke -- the `x` of `6 x 12`, at
    // 1920 x 1080 -- the ring stairsteps visibly against the sky. Sixteen
    // copies on a circle of one keyline put the diagonals where they belong and
    // the edge reads as a drawn line instead of a staircase.
    readonly property var contourRing: {
      var ring = []
      for (var i = 0; i < 16; i++) {
        var a = i * Math.PI / 8
        ring.push([Math.round(Math.cos(a) * word.contour),
                   Math.round(Math.sin(a) * word.contour)])
      }
      return ring
    }
    Repeater {
      model: word.contourRing
      Text {
        required property var modelData
        textFormat: Text.PlainText
        text: word.words
        color: word.bodyTone
        font: wordFace.font
        x: modelData[0]
        y: modelData[1]
      }
    }
    // The warm rim, on the sun side: up and to the right, inside the contour.
    Text {
      textFormat: Text.PlainText
      text: word.words
      color: word.rimTone
      font: wordFace.font
      x: word.rimOffset
      y: -word.rimOffset
    }
    Text {
      id: wordFace
      textFormat: Text.PlainText
      text: word.words
      color: word.faceTone
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: word.size
      font.letterSpacing: word.spacing
    }
  }

  // ============================================ TYPE THAT CLEARS THE BOARD
  //
  // ROUND 5. The one thing the prototype left on this screen: "the numeral
  // covers the gantry's board on beats 3-1". It did, exactly: the `3` was
  // placed by its LINE BOX at 10% of the frame height and sized at 58% of it,
  // and a line box is mostly air -- a digit sits a quarter of the box down from
  // its top and fills three quarters of it -- so the ink ran from 21% to 64% of
  // the frame and the board sits at 51%. `TURBO TABLES` lost its middle on
  // every counted beat and only came back on GO, when the numeral shrank.
  //
  // Three things are wrong with fixing that by nudging a fraction:
  //
  //  - the numeral would still be placed by a box whose relationship to the ink
  //    depends on the face the child's shell hands down, which is not this
  //    file's to choose;
  //  - the board's position lives in `parts/CountdownScene.qml`, so the
  //    fraction would be a copy of somebody else's number;
  //  - the beat pulse grows the numeral by a tenth about its own centre, and a
  //    frame that clears the board at rest can still cross it 100 ms later.
  //
  // So the type is placed by its INK, measured with `tightBoundingRect` in the
  // face the shell actually handed down; the floor it may not cross is bound to
  // `scene.boardTopY`, which is the line the painter draws the board at; and
  // the fit subtracts the pulse's own overshoot before it chooses a size, and
  // (round 6) the contour's keyline as well.
  //
  // ROUND 6 CORRECTS THE NUMBER THAT STOOD HERE. It read "the numeral is still
  // enormous -- 43% of the frame height in ink at 1920 x 1080, against 43%
  // before, so this costs the picture nothing", and it was wrong in the
  // direction that flattered the change. Measured off the shipped PNGs: 43.9%
  // before round 5, 40.0% after -- which is what round 5's own report said in
  // its section 1.2 while this comment beside the code said otherwise. Round 6
  // takes the contour out of the same band, and the shipped 1920 x 1080 PNGs
  // now read 39.5% on beat 3, 39.4% on beat 2 and 39.1% on beat 1 (39.5% on
  // beat 3 at 1366 x 768 and at 2560 x 1440 as well). Clearing the board and
  // lifting the type off the sun cost the numeral about a tenth of its ink,
  // 43.9% to 39.5%. It is still by far the largest thing in the frame, and the
  // cost is real; the comment that said it was nothing was the round's own
  // evidence contradicted at the line it was written on.
  FontMetrics {
    id: typeProbe
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: 100
  }

  // Ink box of a word, as fractions of the font's pixel size: `top` is how far
  // below the Text item's own top the ink starts, `height` is how tall the ink
  // is. `box` is the line box, which is what the item's height actually is and
  // what the pulse scales about.
  function inkOf(word) {
    var rect = typeProbe.tightBoundingRect(word)
    var ascent = typeProbe.ascent
    var descent = typeProbe.descent
    return { "top": (ascent + rect.top) / 100,
             "height": rect.height / 100,
             "box": (ascent + descent) / 100 }
  }
  readonly property var beatInk: countdown.inkOf(countdown.beatWord)
  readonly property var factInk: countdown.inkOf(countdown.factText)

  // The pulse, named once so the animation and the fit cannot disagree about
  // how much bigger the numeral gets.
  readonly property real beatPulse: 1.10

  // The floor. `scene.boardTopY` is the board's top edge in this frame's own
  // pixels; the clear air above it is 3% of the frame height, which is 32 px at
  // 1080 and 23 px at 768.
  readonly property real typeFloorY: scene.boardTopY - countdown.height * 0.030
  // Where the ink starts. GO keeps the ceiling the prototype's GO frame had --
  // that frame was never the defect -- and the counted beats take the whole sky
  // above the board.
  readonly property real typeCeilingY: countdown.height * (countdown.go ? 0.100 : 0.045)

  readonly property int beatShadowDrop: countdown.px(countdown.go ? 8 : 16)
  readonly property int factShadowDrop: countdown.px(8)

  // The lowest dark pixel a word can put on the frame, below its own ink: the
  // cast shadow's throw, and the contour's keyline under that. Both the fit and
  // the spec use this, so the contour cannot quietly eat the clearance the
  // round-5 work bought.
  readonly property int beatFootDrop: countdown.beatShadowDrop + countdown.inkContour
  readonly property int factFootDrop: countdown.factShadowDrop + countdown.inkContour

  // The counted beats fill the band; GO is the size the prototype had, because
  // the fact has to fit under it.
  //
  // The pulse scales the Text item about its centre, so the ink's bottom swings
  // down by (its distance from that centre) x (pulse - 1). Subtracting that
  // here is what makes the clearance true of every frame of the animation and
  // not only of the one a screenshot catches.
  readonly property real beatSwing: Math.max(0, countdown.beatInk.top
                                                + countdown.beatInk.height
                                                - countdown.beatInk.box / 2)
                                    * (countdown.beatPulse - 1)
  readonly property int beatPixelSize: countdown.go
      ? Math.round(countdown.height * 0.24)
      : Math.max(8, Math.floor((countdown.typeFloorY - countdown.typeCeilingY
                                - countdown.beatFootDrop)
                               / Math.max(0.05, countdown.beatInk.height + countdown.beatSwing)))
  // Place by the ink: the item's top is as far above the ceiling as the ink is
  // below the item's top.
  readonly property int beatY: Math.round(countdown.typeCeilingY
                                          - countdown.beatInk.top * countdown.beatPixelSize)

  // The fact is drawn at the size the race draws it -- "never smaller than a
  // tenth of the screen height", and this is nearly a fifth -- and hangs from
  // the same floor the numeral respects, so on GO the fact sits above the board
  // rather than across it.
  readonly property int factPixelSize: Math.round(countdown.height * 0.19)
  readonly property int factY: Math.round(countdown.typeFloorY - countdown.factFootDrop
                                          - (countdown.factInk.top + countdown.factInk.height)
                                            * countdown.factPixelSize)

  // What the spec reads back: the line the board is painted at, and where this
  // screen's ink actually landed against it. `tests/qml/tst_countdown_board.qml`
  // asserts the relation at three window sizes and on all four beats -- AND,
  // since round 6, reads the same thing back off the rendered pixels with
  // `grabImage`, because every property below is this file's own arithmetic and
  // a spec built only on them cannot catch an error in the arithmetic.
  readonly property real gantryBoardTopY: scene.boardTopY
  readonly property real gantryBoardBottomY: scene.boardBottomY
  readonly property real gantryBoardLeftX: scene.boardLeftX
  readonly property real gantryBoardRightX: scene.boardRightX
  readonly property color gantryBoardInk: scene.boardInk
  readonly property color gantryBoardFill: scene.boardFill
  readonly property real sunCentreX: scene.sunCentreX
  readonly property real sunCentreY: scene.sunCentreY
  readonly property real sunRadiusX: scene.sunRadiusX
  readonly property real sunRadiusY: scene.sunRadiusY
  readonly property real sunTopY: scene.sunTopY
  readonly property real sunSkylineY: scene.skylineY
  readonly property int sunCutsAboveSkyline: scene.sunCutsAboveSkyline
  // The disc is a gradient, not one colour: `sunCoreTone` out to 72% of the
  // radius and `sunEdgeTone` at the rim. BOTH are named here because the type
  // has to clear both -- cream is 1.26:1 on the core and 1.83:1 on the edge,
  // and a guard that knew only about the core let a mutation through. The spec
  // asserts each tone is actually on the screen before it counts contacts, so
  // a palette that moved cannot make the guard vacuous.
  readonly property color sunCoreTone: scene.sunCore
  readonly property color sunEdgeTone: scene.sunEdge
  readonly property real beatInkTopY: beatGlyph.inkTopY
  readonly property real beatInkBottomY: beatGlyph.inkBottomY
  readonly property real beatInkBottomAtPulse: beatGlyph.inkBottomAtPulse
  readonly property real factInkTopY: factGlyph.inkTopY
  readonly property real factInkBottomY: factGlyph.inkBottomY

  // The counted beats: 3, 2, 1, enormous, over the sky. On GO the word steps
  // up to the top third and shrinks to make room for the fact.
  Item {
    id: beatGlyph
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.beatY
    width: beatFace.width
    height: beatFace.height
    z: 4

    // What a critic can read back without measuring pixels: where this glyph's
    // ink actually starts and ends in the frame, at rest and at the top of the
    // pulse. `tests/qml/tst_countdown_board.qml` asserts the second one against
    // `scene.boardTopY`.
    readonly property real inkTopY: beatGlyph.y
                                    + countdown.beatInk.top * countdown.beatPixelSize
    readonly property real inkBottomY: beatGlyph.inkTopY
                                       + countdown.beatInk.height * countdown.beatPixelSize
    readonly property real inkBottomAtPulse: beatGlyph.inkBottomY
                                             + countdown.beatSwing * countdown.beatPixelSize

    LitWord {
      id: beatFace
      words: countdown.beatWord
      size: countdown.beatPixelSize
      spacing: countdown.go ? countdown.px(20) : 0
      drop: countdown.beatShadowDrop
      contour: countdown.inkContour
      rimOffset: countdown.inkRimOffset
      faceTone: Theme.cream
      shadowTone: countdown.inkShadow
      bodyTone: countdown.inkBody
      rimTone: countdown.inkRim
    }

    // One pulse per beat, and nothing at all under reduced motion, which the
    // design's accessibility section asks for by name.
    transformOrigin: Item.Center
    scale: 1.0
    SequentialAnimation on scale {
      running: countdown.visible && !countdown.reducedMotion
      loops: Animation.Infinite
      NumberAnimation {
        from: countdown.beatPulse; to: 1.0
        duration: 260; easing.type: Easing.OutCubic
      }
      PauseAnimation { duration: Math.max(0, countdown.beatMs - 260) }
    }
  }

  // -------------------------------------------------------- the first fact
  //
  // Drawn at the size the race draws it, over the sun, from the GO beat. The
  // design's type rule is that "the fact is never smaller than a tenth of the
  // screen height"; this is nearly a fifth. It hangs from the same floor the
  // numeral respects -- see TYPE THAT CLEARS THE BOARD above -- so the words on
  // the gantry stay readable behind GO too.
  Item {
    id: factGlyph
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.factY
    width: factFace.width
    height: factFace.height
    z: 3

    readonly property real inkTopY: factGlyph.y
                                    + countdown.factInk.top * countdown.factPixelSize
    readonly property real inkBottomY: factGlyph.inkTopY
                                       + countdown.factInk.height * countdown.factPixelSize
    opacity: countdown.go ? 1.0 : 0.0
    Behavior on opacity {
      enabled: !countdown.reducedMotion
      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    LitWord {
      id: factFace
      words: countdown.factText
      size: countdown.factPixelSize
      spacing: countdown.px(8)
      drop: countdown.factShadowDrop
      contour: countdown.inkContour
      rimOffset: countdown.inkRimOffset
      faceTone: Theme.cream
      shadowTone: countdown.inkShadow
      bodyTone: countdown.inkBody
      rimTone: countdown.inkRim
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
