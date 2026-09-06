import QtQuick
import "parts"
import "parts/CarMeta.js" as CarMeta
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
  //
  // ROUND 2 PUTS IT IN THE LANE. It stood at 0.44 while the road's centre AT
  // THE KART'S OWN DEPTH is 0.478 -- the painted road converges on 0.52 at the
  // horizon and opens out below it, so the middle of the road down where the
  // car is standing is not the vanishing point's fraction. Measured from
  // `CountdownScene`'s own edge functions at `kartFootY`: the road runs 0.252
  // to 0.704 of the frame there and its centre is 0.478. At 0.44 the car was
  // parked a third of a lane left of the lane, off the start grid it is
  // supposed to be standing on.
  readonly property real kartFootX: 0.478
  readonly property real kartFootY: 0.875

  // ============================================ THE CAR SCALES WITH THE WINDOW
  //
  // It did not, and this was the plainest craft failure on the screen. The
  // sprite was `sheetScale: 1.0, pixelScale: 3` -- a fixed 576 x 384 cell --
  // and `--dump-rects` reported that box BYTE-IDENTICAL at 1024 x 600, 1366 x
  // 768, 1920 x 1080 and 2560 x 1440, while everything else in the frame
  // scaled: the gantry ran 278 -> 371 -> 521 -> 695 px over the same range.
  // At 1024 x 600 that is a car 56% of the frame wide whose cell runs to y =
  // 603 on a 600 px window -- clipped by the frame -- and at 2560 x 1440 it is
  // 22.5% of the width standing on a painted shadow 691 px across, 115 px
  // WIDER than the car casting it.
  //
  // `CarMeta.fit` is the piece-C function that answers exactly this: hand it a
  // target width and it returns the sheet row and the whole-number upscale
  // whose cell is nearest to it. `ui/Garage.qml` sizes its hero with the same
  // call. The target is 30% of the frame's width, and what comes back is
  //
  //     1024 -> 384 (37.5% of the width, 42.7% of the height, and it fits)
  //     1366 -> 384 (28.1%)
  //     1920 -> 576 (30.0%)
  //     2560 -> 576 (22.5%)
  //
  // 576 is a ceiling and not a choice: `CarMeta.fit` clamps the upscale to 3
  // and `CarSprite` clamps it again, so 576 px of cell is the largest a car
  // can be drawn ANYWHERE in this game at any screen size. Both files are
  // piece C's. What this screen can do is stop being the one place that
  // ignores the window, and it now does.
  readonly property var kartFit: CarMeta.fit(countdown.width * 0.30)

  CountdownScene {
    id: scene
    anchors.fill: parent
    kartFootX: countdown.kartFootX
    kartFootY: countdown.kartFootY
    // THE SHADOW IS THE CAR'S WIDTH, NOT A CONSTANT. It was 0.27 of the frame
    // at every size, against a car that was 576 px at every size: at 1920 the
    // car was WIDER than its own shadow (576 against 518) and at 2560 the
    // shadow was 115 px wider than the car. One number now, taken off the cell
    // the sprite actually draws, so the two cannot disagree at any size. The
    // 1.03 is the shadow's spread at its head -- a shadow is a little wider
    // than the thing standing in it, and never 20% wider.
    kartFootW: hero.drawnWidth * 1.03 / Math.max(1, countdown.width)
    clock: countdown.sceneClock
    // The gantry's lamps count the beats down; see `startLamps` in the scene.
    beat: countdown.beat
    reducedMotion: countdown.reducedMotion
  }

  // THE ONLY CLOCK IN THE BACKDROP, AND IT IS DECLARED HERE SO ONE THING CAN
  // TURN IT OFF.
  //
  // Two things in the scene move: the gantry's flags, which flap at the
  // circuit's own three a second, and the cloud drift. Both read `scene.clock`
  // and nothing else, so reduced motion is this animation not running -- there
  // is no second switch anywhere and no way for one of them to keep going.
  //
  // It is a `NumberAnimation` on a plain real rather than a `FrameAnimation`
  // because the two consumers are a modulo and a translation: neither needs the
  // frame's own timestamp, and a screen that lives for four seconds should not
  // own a frame driver. Stopped when the screen is not visible, for the reason
  // written on the ticker above -- hidden work is work the child never sees.
  property real sceneClock: 0
  NumberAnimation on sceneClock {
    running: countdown.visible && !countdown.reducedMotion
    loops: Animation.Infinite
    from: 0
    to: 600
    duration: 600000
  }

  // PIECE C: the car on the line is a cell of its sheet -- the road camera,
  // rear square to us -- stood on the start line by its contact point, which
  // is the point the scene's long shadow is laid from.
  //
  // THE SUN'S EDGE ON THE CAR, UNDER IT. `parts/CarLight.qml` is the other half
  // of `CarWash.qml`: the wash takes value away, this puts light back, and a
  // screen wanting both declares the rim pass BEFORE the sprite and the key
  // pass after. See that file's `pass`. The garage does exactly this on its
  // turntable; the countdown, which is the same car one screen later under a
  // sun instead of a work light, did not, so the kart on the line was the raw
  // sheet at UI chroma pasted into a lit scene.
  Loader {
    id: heroRim
    x: hero.x
    y: hero.y
    z: 1
    source: "parts/CarLight.qml"
    onLoaded: {
      item.host = hero
      item.pass = "rim"
      // The frame's own rim tone, and the sun is low and behind-right of the
      // car, so the light lands on its top-right corner. Stronger than the
      // garage's because there is a SUN behind this car and a work light
      // behind that one.
      item.rimColor = countdown.inkRim
      item.rimStrength = 0.85
      item.rimDx = 2
      item.rimDy = -2
    }
  }

  CarSprite {
    id: hero
    x: Math.round(countdown.width * countdown.kartFootX)
    y: Math.round(countdown.height * countdown.kartFootY)
    body: countdown.kartBody
    paint: countdown.kartPaint
    number: countdown.kartNumber
    camera: "road"
    yaw: 0
    sheetScale: countdown.kartFit.sheetScale
    pixelScale: countdown.kartFit.pixelScale
    z: 2

    // THE CAR HAD NO FOOT, IT HAD A HOLE. The bake's contact shadow is
    // `#5f255e` at alpha 128 -- the design's mid purple, painted at noon -- and
    // over this screen's tarmac (`#1c0a18`) it composites BRIGHTER than the
    // road it falls on, so what sat under the wheels was a hard pale ellipse
    // that swallowed the bottom of every tyre. `CarWash.qml` carries the
    // arithmetic and the two-pass answer; the tone is this floor's own deep
    // end, so the shadow is darker than the road rather than lighter.
    washAmount: 0
    shadeAmount: 0.72
    shadeColor: "#12040f"

    // THE BRAKE LIGHTS, AND THEY COUNT DOWN. The road camera is the one the
    // bake lists tail lamps for, and this is a car held on the brakes with the
    // revs coming up: dim on `3`, brighter on `2`, hard on `1`, and OUT on GO,
    // which is a foot coming off a brake pedal. It is four Rectangles at the
    // lamp centres `meta.json` gives, so it costs nothing, and it is one of the
    // things that makes the four beats different pictures from each other.
    lampGlow: countdown.go ? 0.0 : [0.34, 0.62, 0.95][Math.max(0, Math.min(2, countdown.beat))]
    Behavior on lampGlow {
      enabled: !countdown.reducedMotion
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
  }

  // The key and the fill, over the sprite: the sun on the roof and the floor's
  // purple coming up into the underside, banded, because this is a pixel-art
  // sheet and a gradient laid over it reads as a photograph.
  Loader {
    id: heroLight
    x: hero.x
    y: hero.y
    z: 3
    source: "parts/CarLight.qml"
    onLoaded: {
      item.host = hero
      item.keyColor = countdown.inkRim
      item.keyStrength = 0.30
      item.keyReach = 0.46
      item.fillColor = "#5f255e"
      item.fillStrength = 0.30
      item.fillReach = 0.30
    }
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

  // One big word in this light -- cast shadow, keyline, rim, face -- is
  // `ui/parts/LitWord.qml` now, and it is a file rather than a `component`
  // here for two reasons the round found together:
  //
  //   THE RACE DRAWS THE SAME STRING one second later and drew it as a plain
  //   cream `Text`. A component private to this screen cannot be what makes two
  //   screens agree, and the fact is the one object the design says has to
  //   carry across that cut;
  //
  //   THE KEYLINE COST 45% OF THIS SCREEN. Twenty `Text` items per word, forty
  //   on the GO beat. Measured with `npm run perf` at 1920 x 1080: 5.90 cpu
  //   ms/frame with the sixteen-copy contour ring, 3.22 with it deleted. The
  //   part draws the same keyline as one `strokeText` in one `Canvas`, painted
  //   on a beat rather than on a frame. The file carries the arithmetic.

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
  // ROUND 2 CORRECTS THE NUMBER THAT STOOD HERE, FOR THE THIRD TIME, AND THIS
  // TIME THE NUMBER CAME OFF THE SCREEN.
  //
  // Round 6's note read: "the shipped 1920 x 1080 PNGs now read 39.5% on beat
  // 3, 39.4% on beat 2 and 39.1% on beat 1", and used 39.5% to argue that
  // clearing the board had cost the numeral only about a tenth of its ink,
  // 43.9% down to 39.5%. A blind critic could not reproduce 39.5% by any
  // definition and measured 33.6% for the cream face and 35.8% for the whole
  // mark. The critic is right. Asked of the running screen's own published
  // `beatInkBottomY - beatInkTopY`, on the build that comment was written for:
  //
  //     1920 x 1080   33.6%   1366 x 768   33.8%
  //     1024 x  600   34.3%   2560 x 1440  33.8%
  //
  // on all three counted beats, and 15.1% on GO. 39.5% is nobody's measurement
  // of anything; it is 4 points of ink that never existed, quoted in a comment
  // beside the code and then used as evidence.
  //
  // DOES THE ARGUMENT IT SUPPORTED STILL HOLD? The argument was that clearing
  // the gantry's board was affordable because the numeral stayed enormous. It
  // holds, and it holds on a smaller margin than was claimed: the cost was
  // 43.9% to 33.6%, not to 39.5% -- the numeral lost about a QUARTER of its
  // ink, not a tenth. It is still by a long way the largest thing in the frame
  // (the fact, the next largest, is 10.5%), the board is legible behind it,
  // and this round spends part of what is left on making the four beats
  // different sizes from each other. But "this cost the picture almost
  // nothing" was said three times about this one change and was not true any
  // of the three times, and a number that cannot be reproduced from the screen
  // is not a measurement.
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
  // Where the ink starts, and it is the same line on all four beats now.
  //
  // GO USED TO START AT 0.100 AND THE COUNTED BEATS AT 0.045 -- 59 px of empty
  // sky at 1080, kept because "that frame was never the defect". It was: `3`
  // measured 33.6% of the frame height in ink and GO 15.1%, so the release was
  // drawn at 45% of the height of the beats leading up to it and the loudest
  // moment of the countdown was its quietest picture. The band above the board
  // is the same band on every beat; what differs is that on GO the fact shares
  // it.
  readonly property real typeCeilingY: countdown.height * 0.045

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
  // ==================================== THE GO BEAT NOW FITS RATHER THAN SITS
  //
  // Both sizes used to be constants -- 0.24 of the frame for the word, 0.19 for
  // the fact -- and the two of them plus the gap between them happened to fit
  // above a board that the flat painted gantry put at 51% of the frame. The
  // kit's arch is a real one: 5.30 world units tall on a 3.80-unit road against
  // the drawn gantry's 2.2, so at any distance where its baked board is legible
  // it stands higher in the frame, and at the distance chosen here the board's
  // top edge is at 42%. Rendered with the two constants: GO's ink ended at 297
  // and the fact's began at 291, so the word sat ON the fact -- which is the
  // same defect as the numeral on the board, one object along.
  //
  // So the GO beat's two words are FITTED to the band the arch leaves, in the
  // order the design ranks them:
  //
  //   the fact first, and it is floored, not fitted. "The fact is never smaller
  //   than a tenth of the screen height" is the design's accessibility rule and
  //   the only hard number in this paragraph. It is capped at the 0.19 it has
  //   always had, so nothing about a frame with room to spare changes;
  //   then GO takes what is left, down to the 0.24 it has always had.
  //
  // Written this way round because a screen too short for both must not shrink
  // the thing a child has to READ. If the band ever cannot hold the pair, GO is
  // what gives -- and `tests/qml/tst_countdown_board.qml` asserts the fact's
  // tenth at three sizes, so a band that got too tight fails loudly there.
  readonly property real goGap: countdown.height * 0.015
  // Everything in the band that is not ink: the two cast shadows with their
  // keylines, and the air between the word and the fact.
  readonly property real goBand: countdown.typeFloorY - countdown.typeCeilingY
                                 - countdown.beatFootDrop - countdown.factFootDrop
                                 - countdown.goGap
  // The fact's em box at the design's floor of a tenth of the frame IN INK.
  readonly property real factFloorEm: countdown.height * 0.105
                                      / Math.max(0.2, countdown.factInk.height)

  // ==================================================== THE BEATS GET BIGGER
  //
  // `3`, `2` and `1` were the same size to within half a pixel -- 33.6, 33.6
  // and 33.6 per cent of the frame in ink -- so the only thing that changed
  // between one second and the next was WHICH numeral it was. Measured frame
  // against frame, 2.06% of the picture changed across `3` to `2` and 2.11%
  // across `2` to `1`.
  //
  // A countdown builds. Each numeral now takes more of the band than the one
  // before it, ending at the whole band on `1`, which is the size all three
  // used to be: nothing shrinks the last counted beat, and the first two step
  // back from it. The design's floor for the numeral is the plan's "the number
  // is enormous" and `tst_countdown_board`'s own case, which requires 29% of
  // the frame in ink on every counted beat -- the smallest of the three lands
  // at 30.2% at 1920 x 1080, so the build happens above the floor rather than
  // through it.
  readonly property var beatFill: [0.90, 0.95, 1.00, 1.00]
  readonly property real beatShare: countdown.beatFill[Math.max(0, Math.min(3, countdown.beat))]

  readonly property int beatPixelSize: {
    if (!countdown.go) {
      var band = countdown.typeFloorY - countdown.typeCeilingY - countdown.beatFootDrop
      var full = band / Math.max(0.05, countdown.beatInk.height + countdown.beatSwing)
      return Math.max(8, Math.floor(full * countdown.beatShare))
    }
    var left = countdown.goBand - countdown.factPixelSize * countdown.factInk.height
    var fitted = left / Math.max(0.05, countdown.beatInk.height + countdown.beatSwing)
    return Math.max(8, Math.floor(fitted))
  }
  // Place by the ink. GO hangs from the ceiling, because the fact hangs from
  // the floor and the gap between them is the design's. A counted beat is
  // CENTRED in the band instead, so the three of them grow about one point
  // rather than dropping toward the gantry as they get bigger.
  readonly property real beatInkHeightPx: countdown.beatInk.height * countdown.beatPixelSize
  readonly property real beatInkTopWanted: countdown.go
      ? countdown.typeCeilingY
      : countdown.typeCeilingY
        + ((countdown.typeFloorY - countdown.beatFootDrop - countdown.typeCeilingY)
           - countdown.beatInkHeightPx * (1 + countdown.beatSwing / countdown.beatInk.height)) / 2
  readonly property int beatY: Math.round(countdown.beatInkTopWanted
                                          - countdown.beatInk.top * countdown.beatPixelSize)

  // ============================== THE FACT IS THE SIZE THE RACE DRAWS IT AT
  //
  // The comment here said so and it was not true. The race sizes the fact from
  // one rule -- `ui/Race.qml`'s `factPixelSize`: "a tenth of the screen height
  // in ink, with a hair over it so rounding never lands under the floor",
  // which is the design's accessibility line and is 0.105 of the frame. This
  // screen fitted the fact to whatever was left of the band and capped it at
  // 0.19 of the frame in EM, which landed it at 12.0% of the frame in ink at
  // 1920 x 1080 against the race's 10.5%. Same sentence, same second, two
  // sizes, and the screen that claimed to be matching the other one was the
  // one that had drifted.
  //
  // So on GO the fact is the floor exactly, by the same arithmetic, which is
  // `factFloorEm`. Everything the change frees goes to GO -- 16 px at 1080 --
  // and the two screens now print the first fact at the same height, so a
  // child reading it through the cut sees one object and not two.
  //
  // It is one expression on every beat rather than two: before GO the fact is
  // drawn at zero opacity, and a fade that starts at a different size from the
  // one it lands at is a fade and a resize at once.
  readonly property int factPixelSize: Math.max(8, Math.round(countdown.factFloorEm))
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
  // The line the hills stand on. It is NOT the skyline: `SunsetSky`'s ridges
  // rise above it by their own relief, and how far is the sky part's business.
  // A test walking the sun's centre column stops at the first HILL TONE, which
  // is why the three of them are republished rather than a row number -- the
  // round that computed a skyline in this file from a copy of the ridge
  // arithmetic is the round this file's second sky came from.
  readonly property real horizonY: scene.horizonYPx
  readonly property color hillFarTone: scene.hillFar
  readonly property color hillMidTone: scene.hillMid
  readonly property color hillNearTone: scene.hillNear
  readonly property real gantryTopY: scene.gantryTopY
  readonly property real gantryLeftX: scene.gantryLeftX
  readonly property real gantryRightX: scene.gantryRightX
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
      // The cached ink is a texture, and for the 260 ms of the surge it is
      // being scaled. Filtered while that is true, nearest for the rest of the
      // beat, which is when the texture is composited at exactly 1:1 and a
      // nearest blit is the cheap path on a software renderer.
      inkSmooth: beatGlyph.scale !== 1.0
    }

    // ONE PULSE PER BEAT, AND NOW IT IS ACTUALLY ON THE BEAT.
    //
    // This was an infinite loop -- 260 ms of scale, then a pause of
    // `beatMs - 260` -- started when the screen became visible and never
    // referred to the clock again. Two things followed from that, and both are
    // fixed by driving it from the beat instead of alongside it:
    //
    //   the picture: the loop and the `Timer` are two clocks, and nothing kept
    //   them in step. Any latency between them -- a slow first frame, a screen
    //   shown a moment before its first tick -- put the surge somewhere in the
    //   middle of a beat, so the numeral swelled while the number was standing
    //   still and stood still as it changed. "One pulse per beat" is what the
    //   comment claimed and what nothing enforced;
    //
    //   the evidence: `tests/qml/tst_countdown_board.qml`'s picture cases grab
    //   a handful of frames a few tens of milliseconds apart, and a free
    //   running pulse put that window at an arbitrary phase. Its own comment
    //   records ten consecutive grabs reading 425, 93, 425, 425 ... and one
    //   zero -- half a resampled band matches no exact tone -- and a case that
    //   passed on this Mac would have failed on another for no reason but
    //   phase. A pulse tied to the beat is at rest for the rest of the beat, so
    //   a case that sets a beat and waits out the surge photographs the same
    //   frame every time, on every machine.
    //
    // Nothing at all under reduced motion, which the design's accessibility
    // section asks for by name.
    transformOrigin: Item.Center
    scale: 1.0

    NumberAnimation {
      id: beatSurge
      target: beatGlyph
      property: "scale"
      from: countdown.beatPulse
      to: 1.0
      duration: 260
      easing.type: Easing.OutCubic
    }
    function surge() {
      if (countdown.reducedMotion || !countdown.visible) {
        beatSurge.stop()
        beatGlyph.scale = 1.0
        return
      }
      beatSurge.restart()
    }
    // The three places a beat begins: the first one, every one after it, and
    // the screen coming back. `restart()` from the top each time, so a beat
    // that arrives while the last surge is still running does not compound.
    Component.onCompleted: beatGlyph.surge()
    Connections {
      target: countdown
      function onBeatChanged() { beatGlyph.surge() }
      function onVisibleChanged() { beatGlyph.surge() }
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

  // PIECE M. The countdown's one action, and it was already printed here: the
  // line that says ESC is now the thing you press. No new chrome and no new
  // words -- the screen already told the child what the key was, and this makes
  // the sentence a control.
  //
  // The other keys of this screen are the type-ahead digits, which belong to
  // the answer and not to any control on it. See the report's "what is not
  // covered": there is no on-screen keypad anywhere in this game.
  KeyHint {
    id: countdownBack
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.height - countdown.px(62)
    z: 5

    keys: "ESC"
    action: "BACK TO THE GARAGE"
    textSize: countdown.fs(16)
    letterSpacing: countdown.px(2)
    bold: false
    idleColor: Qt.rgba(Theme.cream.r, Theme.cream.g, Theme.cream.b, 0.55)
    liveColor: Theme.cream
    padWidth: countdown.px(20)
    padHeight: countdown.px(11)

    name: "Back to the garage"
    does: "stop the countdown and go back to the garage"
    key: "Escape"
    help: "Stops the countdown. The Escape key does it too."
    // The Escape branch, exactly: stop the beats, then say so.
    onTapped: {
      ticker.stop()
      countdown.abortRequested()
    }
  }
}
