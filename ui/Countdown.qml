import QtQuick
import "parts"
import "parts/Circuit.js" as Circuit
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
  // The same digits as the line draws them: `5`, `56`, `560`. Built by
  // appending one small integer at a time, which is what the answer slot's
  // `LitWord` takes.
  readonly property string typedText: {
    var text = ""
    for (var i = 0; i < countdown.typedAhead.length; i++)
      text += countdown.typedAhead[i]
    return text
  }

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
  // ROUND 3 PUT THE LAP AND THE TABLE IN HERE, because the printed header they
  // used to be went. It stood top left, which is where the numeral now stands,
  // and putting it anywhere else would have been one more thing that moves
  // across the cut -- the race prints `LAP 1 / 12` and the table name top left
  // a second later, in its own HUD. Nothing is lost for a screen-reader user:
  // the two strings are in this sentence.
  Accessible.description: "Lap 1 of " + countdown.tables.length + ", "
                          + Engine.tableName(countdown.firstTable)
                          + ". The race starts in " + countdown.beatWord
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
  // ROUND 3: ONE RENDERER FOR THE PLACE, AS THERE IS ONE RENDERER FOR THE CAR.
  //
  // Everything above this line is the countdown the design specifies and is
  // unchanged: four beats, `finished()`, Escape, the GO-beat type-ahead.
  //
  // WHAT WAS WRONG. `ui/parts/CountdownScene.qml` painted a start line: its own
  // horizon at 57.5% of the frame, its own road converging on its own vanishing
  // point, its own neon floor, its own start grid and the kit's gantry stood on
  // it by its own arithmetic. `ui/TrackView.qml` renders the same place a
  // second later -- terrain by sector, the road's crown and markings, the whole
  // roadside from `Circuit.js`, the hour, the contact shadows -- with its
  // horizon at 40.3%. Round 2 gave the two the same sky, the same arch and the
  // same lit car and they still did not stand in the same place, because the
  // ground, the horizon and the projection were separately authored. A cut
  // between them moved the horizon 184 px and the sun 132 px in one frame.
  //
  // Piece C settled this once for the car -- "one renderer for the car; no
  // screen draws its own" -- and it was right. The place gets the same rule.
  // This screen IS `TrackView`, parked at `Circuit.START_TRAVEL` with the
  // camera still and the field on the grid, so the cut into the race changes
  // the HUD and nothing else: same renderer, same camera, same travel, one
  // frozen and then released.
  //
  // WHAT IT COST THE NUMERAL, MEASURED, BECAUSE IT IS THE ONE REAL PRICE.
  // `TrackView`'s horizon is 40.3% of the frame and the start arch stands on
  // the road, so the arch's board can never be lower in the frame than the
  // horizon. At `START_TRAVEL` the board's top edge is at 25.1% of the frame
  // and `TrackView.archBeams` puts the crossbar band's top at 20.3%; sweeping
  // the camera back to -30 moves the board only to 35.0%, by which point the
  // arch is at 0.39 clarity and `TURBO TABLES` is unreadable. A numeral placed
  // between a 4.5% ceiling and a 3% clearance above that board can be at most
  // 20.1% of the frame in ink -- SMALLER than the 21.7% the GO word already
  // is. So a numeral centred in this camera's frame cannot be huge and clear
  // of the board at the same time, at any travel, and that is a fact about the
  // camera rather than about a layout.
  //
  // SO THE NUMERAL MOVED SIDEWAYS RATHER THAN GETTING SMALLER. It stands in
  // the sky to the LEFT of the arch, where the frame is 572 px wide and 435 px
  // tall at 1920 x 1080 and there is nothing in it -- clear of the board by the
  // whole width of the arch rather than by three per cent of the frame, and on
  // plain sky rather than on the sun. The plan's line for this screen is "the
  // number huge in cream over the sky ... numeral clear of the gantry", and
  // both halves are more true of this frame than of the one it replaces. What
  // it costs is the symmetry, and a blind critic of round 1 asked for exactly
  // that: "the eye goes to the numeral and has nowhere to go next ... the bar's
  // picture ROUTES the eye. This one parks it."
  //
  // WHAT IT COST IN FRAMES: NOTHING, AND IT GAVE BACK. A countdown is a STILL,
  // so the whole view composes once into a cached layer and every frame after
  // that is one textured quad. Measured with `npm run perf` at 1920 x 1080 --
  // the numbers and their load averages are in the round's report --
  // `dev/StillTrack` (this arrangement, nothing over it) is 0.336 wall and
  // 0.672 cpu ms/frame against a bare `--screen TrackView`'s 2.754 and 3.795.
  // What it buys is 8.3 MB of offscreen texture, which is stated rather than
  // hidden and is the reason the layer is worth arguing about at all.

  // The kart is the one the garage settings describe, so the kart on the line
  // is the kart the child just built -- and it is now the same kart the race
  // draws, at the same size, in the same lane, because it is drawn by the same
  // renderer from the same list.
  readonly property int kartBody: Store.setting("kartBody")
  readonly property int kartPaint: Store.setting("kartPaint")
  readonly property int kartNumber: Store.setting("kartNumber")

  // Which race is about to be run, handed down by the flow. A Grand Prix
  // stands three rivals on the grid beside the child; the solo modes stand
  // none -- which is what the race itself shows a second later, and a countdown
  // that guessed would add or remove three cars across the cut.
  property string mode: "grandPrix"

  // ------------------------------------------------------------- the place
  //
  // THE STILL IS CACHED AND THAT IS THE WHOLE PERFORMANCE STORY. Nothing
  // inside this item moves: `travel` is a constant, `speed` is 0 and nothing
  // ever calls `advance()`, so `TrackView.fxClock` stays at 0 and every
  // clock-driven binding in it -- the cloud drift, the flags, the shimmer, the
  // dust -- evaluates once. Qt re-renders a layer when its subtree changes and
  // blits the texture otherwise, so the 890 drawn items in there are rasterised
  // once and the countdown pays one quad a frame after that. The beat lamps,
  // the light they put on the road and the type are all OUTSIDE it, so a beat
  // does not dirty the cache; the brake lights are inside it, and step without
  // a fade for exactly that reason -- four repaints in the life of the screen
  // rather than forty.
  Item {
    id: still
    anchors.fill: parent
    z: 0
    layer.enabled: true
    layer.smooth: false

    TrackView {
      id: place
      anchors.fill: parent

      // WHERE A RACE OPENS, from the circuit rather than from this file. See
      // `Circuit.START_TRAVEL`: `ui/Race.qml` reads the same constant, so the
      // camera the child counts down at and the camera the race opens at are
      // the same number by construction and not by two files agreeing.
      travel: Circuit.START_TRAVEL
      lap: 1
      lapCount: Math.max(1, countdown.tables.length)
      // Standing still on the grid. Nothing drives this and nothing calls
      // `advance()`, which is what makes the whole view a still.
      speed: 0
      reducedMotion: countdown.reducedMotion

      // A CAR HELD ON THE BRAKES, WITH THE REVS COMING UP. Dim on `3`, brighter
      // on `2`, hard on `1` and OUT on GO, which is a foot coming off a pedal.
      // `TrackView.brakeHold` is added to the human kart's own tail-lamp term,
      // so a race -- which never writes it -- is unchanged to the bit.
      brakeHold: countdown.go ? 0.0
                              : [0.34, 0.62, 0.95][Math.max(0, Math.min(2, countdown.beat))]

      // The fact's ink, handed to the view for the same reason `ui/Race.qml`
      // hands it: a road-spanning crossbar behind the fact is a contrast
      // problem, and `factYield` is the view's own measurement of how much of
      // one there is. The plate below reads it, so the countdown and the race
      // put the same ground under the same glyphs on the same frame.
      factRect: countdown.lineGuardRect
    }
  }

  // The field, stood on the grid once. Progress is zero for everybody, which
  // is what a start line is: four cars abreast, the child's in the middle.
  function standTheGrid() {
    var list = [{
      "id": "you", "name": "YOU", "number": countdown.kartNumber,
      "body": countdown.kartBody, "seat": 0,
      "paint": Theme.paint(countdown.kartPaint),
      "progress": 0, "isHuman": true, "ghost": false
    }]
    if (countdown.mode === "grandPrix") {
      // The engine's own three, in the engine's own seat order. Which car each
      // one is comes from `Theme.rivalFace`, which `ui/Race.qml` also reads --
      // the round that gave this screen its own copy of `(seat + 1) % 6` is the
      // round its ground came from.
      var ids = ["bolt", "piston", "gasket"]
      for (var i = 0; i < ids.length; i++) {
        var face = Theme.rivalFace(i + 1)
        list.push({
          "id": ids[i], "name": face.name, "number": face.number,
          "body": face.body, "seat": i + 1, "paint": face.paint,
          "progress": 0, "isHuman": false, "ghost": false
        })
      }
    }
    place.setKarts(list)
    place.humanProgress = 0
    var zeros = []
    for (var z = 0; z < list.length; z++)
      zeros.push(0)
    place.setProgress(zeros)
  }
  Component.onCompleted: countdown.standTheGrid()

  // ------------------------------------------------------- what is where
  //
  // Every number below is read off the running view rather than assumed, and
  // that is the point of the round: there is one camera and it is asked.
  readonly property rect archBox: place.startArchBox
  readonly property bool archStands: countdown.archBox.width > 8
                                     && countdown.archBox.height > 8

  // WHERE THE SPONSOR PLATE IS ON THE SHEET, measured off `assets/props/
  // gantry.png` and expressed as fractions of the prop's own opaque box, so it
  // survives every scale step and every frame size.
  //
  // The plate is cell pixels x 405..1058, y 142..241, identical in `C0` and
  // `C1` -- only the flags move between the two frames -- and the `C0` opaque
  // box is (104, 50) to (1387, 700). The four fractions below are those two
  // rectangles divided.
  //
  // IT IS THE PLATE AND NOT THE WHOLE HEADER BAND, and the difference is the
  // whole evidence. The beam's chequers run at the same HEIGHT as the plate, to
  // its left and its right, and they are cream: over the plate's own rows the
  // full width of the arch carries 10,482 cream pixels, of which 10,444 are
  // chequers. The guard that says "no cream of the numeral falls inside the
  // board" counts cream, so a rect that swallowed the chequers would either be
  // permanently red or would have to be given a tolerance wide enough to hide
  // the numeral as well. Inside x 405..1058 the bake carries 0 cream, 5,236
  // pixels of amber ink in 336 columns and 56,051 of plate.
  readonly property real boardBoxL: (405 - 104) / 1283
  readonly property real boardBoxR: (1059 - 104) / 1283
  readonly property real boardBoxT: (142 - 50) / 650
  readonly property real boardBoxB: (242 - 50) / 650

  // The board's two colours, as the bake made them: `#f5a524` amber type on the
  // `#1a1b26` plate. A contrast figure is a claim about a PAIR, so the pair is
  // named in one place. They are not this file's choice -- they are the kit's,
  // and the kit is frozen art. Neither is cream, and that matters: the evidence
  // for "the numeral no longer covers the board" is a count of CREAM pixels
  // inside the board's rows, and both are far outside the +/- 14 per channel
  // that count allows around `#f2e6c4`.
  readonly property color gantryBoardInk: "#f5a524"
  readonly property color gantryBoardFill: "#1a1b26"

  readonly property real gantryBoardLeftX: countdown.archBox.x
                                           + countdown.boardBoxL * countdown.archBox.width
  readonly property real gantryBoardRightX: countdown.archBox.x
                                            + countdown.boardBoxR * countdown.archBox.width
  readonly property real gantryBoardTopY: countdown.archBox.y
                                          + countdown.boardBoxT * countdown.archBox.height
  readonly property real gantryBoardBottomY: countdown.archBox.y
                                             + countdown.boardBoxB * countdown.archBox.height
  // The whole arch's box, flags and all, which is what the type has to clear.
  readonly property real gantryTopY: countdown.archBox.y
  readonly property real gantryLeftX: countdown.archBox.x
  readonly property real gantryRightX: countdown.archBox.x + countdown.archBox.width

  // The camera's horizon, in this frame's own pixels, from the view that owns
  // it. Everything above it is sky; the numeral stands in the sky.
  readonly property real horizonY: place.horizon * countdown.height
  // Republished so a spec can read the two cameras back off the running screens
  // and compare them rather than compare two source constants.
  readonly property real cameraTravel: place.travel
  readonly property real cameraHorizon: place.horizon

  // ------------------------------------------------------------- the type
  //
  // Cream over a sky that is pink: without a keyline the numeral would sink
  // into the ridge line it stands over. Every big word here carries the frame's
  // own light -- cast shadow down and left, opaque contour all the way round,
  // warm rim up and right -- and that treatment is `ui/parts/LitWord.qml`,
  // which the race draws the fact with too.
  readonly property color inkShadow: Qt.rgba(0.235, 0.07, 0.157, 0.82)
  readonly property color inkBody: "#280e27"
  readonly property color inkRim: "#f0b07a"
  readonly property int inkContour: Math.max(2, countdown.px(6))
  readonly property int inkRimOffset: Math.max(1, Math.round(countdown.inkContour * 0.55))

  FontMetrics {
    id: typeProbe
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: 100
  }

  // Ink box of a word, as fractions of the font's pixel size: `top` is how far
  // below the Text item's own top the ink starts, `height` is how tall the ink
  // is, `box` is the line box the pulse scales about, `advance` is how wide the
  // word lays out. Placing type by its LINE BOX is what put the numeral over
  // the gantry's board in the first place -- a digit sits a quarter of the box
  // down from its top and fills three quarters of it -- so nothing here is
  // placed or fitted by anything but the ink.
  function inkOf(word) {
    var rect = typeProbe.tightBoundingRect(word)
    var ascent = typeProbe.ascent
    var descent = typeProbe.descent
    return { "top": (ascent + rect.top) / 100,
             "height": rect.height / 100,
             "box": (ascent + descent) / 100,
             "advance": typeProbe.advanceWidth(word) / 100 }
  }
  readonly property var beatInk: countdown.inkOf(countdown.beatWord)

  // The pulse, named once so the animation and the fit cannot disagree about
  // how much bigger the numeral gets.
  readonly property real beatPulse: 1.10

  // ================================ THE COLUMN OF SKY THE NUMERAL STANDS IN
  //
  // Left of the arch, inset by a margin, from the ceiling down to the horizon.
  // The arch's own box is what bounds it on the right, so a window shape that
  // makes the arch wider takes the numeral's column with it instead of letting
  // the two overlap. When the arch is not on the screen at all -- which is only
  // ever a harness with no circuit under it -- the column is the left half of
  // the frame and nothing is claimed about clearance.
  readonly property real typeMargin: countdown.px(30)
  readonly property real typeColumnL: countdown.typeMargin
  // ROUND 8: AND THE LINE'S PLATE BOUNDS IT TOO. The countdown draws the whole
  // line now -- `7 × 8 = ▮`, the fact through a slot the width of the widest
  // answer -- centred where the race centres it, and that line is wider than
  // the fact alone by the slot: 616 px at 1366 x 768 against 350. Its left
  // edge therefore stands 53 px INSIDE the column GO was fitted to at that
  // size (77 at 1920 x 1080, 44 at 1024 x 600), and on the GO beat the two
  // words overlapped. The line cannot move: where it stands is the claim
  // this screen makes about the cut. So GO is fitted to the sky left of
  // whichever is nearer, the arch's box or the line's plate, with a `px(12)`
  // gap to the plate's edge (the arch keeps its `typeMargin`, which is for the
  // flags' art). The counted beats are single glyphs fitted by height and do
  // not reach either bound; GO is fitted by width and is smaller for it --
  // 18% of the frame in this runner's face against 23% before, which is
  // still over the 21.7% round 2 shipped; `tests/qml/tst_countdown_board.qml`
  // carries the arithmetic under `test_03`.
  readonly property real linePlateLeftX: countdown.lineGuardRect.x - countdown.px(22)
  readonly property real typeColumnR: Math.min((countdown.archStands
                                                ? countdown.gantryLeftX
                                                : countdown.width * 0.5) - countdown.typeMargin,
                                               countdown.linePlateLeftX - countdown.px(12))
  readonly property real typeColumnW: Math.max(24, countdown.typeColumnR - countdown.typeColumnL)
  readonly property real typeColumnX: (countdown.typeColumnL + countdown.typeColumnR) / 2

  // The band: the ceiling is 4.5% of the frame and the floor is the horizon,
  // less a clearance, because below the horizon is ground and the plan's line
  // is "the number huge in cream over the SKY".
  readonly property real typeCeilingY: countdown.height * 0.045
  readonly property real typeFloorY: countdown.horizonY - countdown.height * 0.020

  readonly property int beatShadowDrop: countdown.px(countdown.go ? 8 : 16)
  // The lowest dark pixel a word can put on the frame below its own ink: the
  // cast shadow's throw, and the contour's keyline under that.
  readonly property int beatFootDrop: countdown.beatShadowDrop + countdown.inkContour
  // The letters of GO are spaced; a single numeral has nothing to space.
  readonly property int beatSpacing: countdown.go ? countdown.px(20) : 0

  // The pulse scales the item about its centre, so the ink's bottom swings down
  // by (its distance from that centre) x (pulse - 1). Subtracting that here is
  // what makes the clearance true of every frame of the animation and not only
  // of the one a screenshot catches.
  readonly property real beatSwing: Math.max(0, countdown.beatInk.top
                                                + countdown.beatInk.height
                                                - countdown.beatInk.box / 2)
                                    * (countdown.beatPulse - 1)

  // ==================================================== THE BEATS GET BIGGER
  //
  // `3`, `2` and `1` were the same size to within half a pixel, so the only
  // thing that changed between one second and the next was WHICH numeral it
  // was. Each numeral now takes more of the band than the one before it, ending
  // at the whole band on `1`. GO takes the whole band too -- for the first time
  // it is the size of the beats that led up to it, because the fact no longer
  // has to fit underneath it: the fact stands where the race will draw it,
  // which is the middle of the frame, and the two are not competing for one
  // column any more.
  readonly property var beatFill: [0.90, 0.95, 1.00, 1.00]
  readonly property real beatShare: countdown.beatFill[Math.max(0, Math.min(3, countdown.beat))]

  // TWO CEILINGS, AND THE WORD TAKES THE LOWER. The band is what the sky
  // leaves; the column is what the arch leaves. A single numeral is never the
  // one that runs out of width and `GO` at 1024 x 600 always is, so both are
  // computed and the smaller wins -- which is why GO is a little shorter than
  // `1` at every size rather than by a rule somebody wrote down.
  readonly property int beatFitByHeight: {
    var band = countdown.typeFloorY - countdown.typeCeilingY - countdown.beatFootDrop
    return Math.floor(band / Math.max(0.05, countdown.beatInk.height + countdown.beatSwing))
  }
  readonly property int beatFitByWidth: {
    var room = countdown.typeColumnW - countdown.beatSpacing * Math.max(0, countdown.beatWord.length - 1)
    return Math.floor(room / Math.max(0.05, countdown.beatInk.advance * countdown.beatPulse))
  }
  readonly property int beatPixelSize: Math.max(8, Math.floor(
      Math.min(countdown.beatFitByHeight * countdown.beatShare, countdown.beatFitByWidth)))

  // Centred in the band, so the three of them grow about one point rather than
  // dropping toward the horizon as they get bigger.
  readonly property real beatInkHeightPx: countdown.beatInk.height * countdown.beatPixelSize
  readonly property real beatInkTopWanted: countdown.typeCeilingY
      + ((countdown.typeFloorY - countdown.beatFootDrop - countdown.typeCeilingY)
         - countdown.beatInkHeightPx * (1 + countdown.beatSwing / countdown.beatInk.height)) / 2
  readonly property int beatY: Math.round(countdown.beatInkTopWanted
                                          - countdown.beatInk.top * countdown.beatPixelSize)

  // ================================ THE FACT IS WHERE THE RACE WILL DRAW IT
  //
  // Not "the size the race draws it" -- the PLACE the race draws it, which is a
  // stronger claim and a cheaper one. `ui/Race.qml` puts its fact column at
  // `px(118)` from the top, centred, at a size that is a tenth of the frame
  // height in ink; those three lines are copied here on purpose and the round's
  // report measures the two boxes against each other on the shipped frames. A
  // child reading `1 x 6` through the cut sees it not move at all.
  // ROUND 8: the widest LINE, not the widest fact -- `ui/Race.qml`'s own
  // probe string -- because the countdown draws the whole line now.
  TextMetrics {
    id: factWidest
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: 200
    text: "12 × 12 = 144"
  }
  readonly property real factInkRatio: factWidest.tightBoundingRect.height > 0
                                       ? factWidest.tightBoundingRect.height / 200
                                       : 0.73
  readonly property int factPixelSize: {
    // A tenth of the screen height in ink, with a hair over it so rounding
    // never lands under the floor.
    var wanted = Math.ceil((countdown.height * 0.105) / Math.max(0.25, countdown.factInkRatio))
    // ... and never so wide that the widest fact runs off the screen.
    var widest = factWidest.advanceWidth > 0
                 ? Math.floor((countdown.width - countdown.px(120)) * 200 / factWidest.advanceWidth)
                 : wanted
    return Math.max(countdown.fs(118), Math.min(wanted, widest))
  }
  readonly property int factTopY: countdown.px(118)

  // The fact's ink as it is on the screen now, in this screen's coordinates.
  // `tightBoundingRect` is measured from the BASELINE, so its `y` is negative
  // for anything above it and the item's own top is `ascent` above that.
  TextMetrics {
    id: factInkNow
    font: factWord.faceFont
    text: factWord.words
  }
  FontMetrics {
    id: factFaceMetrics
    font: factWord.faceFont
  }
  readonly property rect factInkRect: {
    var r = factInkNow.tightBoundingRect
    return Qt.rect(factGlyph.x + line.x + factWord.x + r.x,
                   factGlyph.y + line.y + factWord.y + factFaceMetrics.ascent + r.y,
                   r.width, r.height)
  }
  // The whole line's ink AS DRAWN -- the fact through the caret or the last
  // typed digit -- and its RESERVE, the fact through the full answer slot.
  // The same two boxes `ui/Race.qml` publishes, for the same two readers: the
  // plate under the line answers for the ink, and the view's `factRect` keeps
  // the reserve clear.
  readonly property rect lineInkRect: Qt.rect(countdown.factInkRect.x, countdown.factInkRect.y,
                                              (factGlyph.x + line.x + answerSlot.x
                                               + Math.max(caretMark.x + caretMark.width,
                                                          answerWord.width))
                                              - countdown.factInkRect.x,
                                              countdown.factInkRect.height)
  readonly property rect lineGuardRect: Qt.rect(countdown.factInkRect.x, countdown.factInkRect.y,
                                                (factGlyph.x + line.x + answerSlot.x + answerSlot.width)
                                                - countdown.factInkRect.x,
                                                countdown.factInkRect.height)
  // THE LINE, AS IT READS: `7 × 8 = ▮` on the GO beat, `7 × 8 = 5▮` once a
  // digit has been typed ahead. The same construction as `Race.lineText`, so
  // the line the child is told to TYPE THE ANSWER on is the line they type on.
  readonly property string lineText: factWord.words + " " + answerWord.words
                                     + (caretMark.visible ? "▮" : "")

  // What the spec reads back: where this screen's ink actually landed, and the
  // lines it had to clear. `tests/qml/tst_countdown_board.qml` asserts the
  // relations at three window sizes and on all four beats, and reads the same
  // things back off the rendered pixels with `grabImage`, because every
  // property here is arithmetic and a spec built only on arithmetic cannot
  // catch an error in the arithmetic.
  readonly property real beatInkTopY: beatGlyph.inkTopY
  readonly property real beatInkBottomY: beatGlyph.inkBottomY
  readonly property real beatInkBottomAtPulse: beatGlyph.inkBottomAtPulse
  readonly property real beatInkLeftX: beatGlyph.inkLeftX
  readonly property real beatInkRightX: beatGlyph.inkRightX
  readonly property real factInkTopY: countdown.factInkRect.y
  readonly property real factInkBottomY: countdown.factInkRect.y + countdown.factInkRect.height
  readonly property real factShadowDrop: countdown.px(6)
  readonly property real factGroundAlpha: factPlate.opacity

  // ------------------------------------------------------------ the lamps
  //
  // WHAT THIS ANSWERS. Measured frame against frame on the round-1 build,
  // 2.06% of the picture changed between `3` and `2` and 2.11% between `2` and
  // `1` -- and that change was the numeral and a drifting cloud. For three of
  // the four seconds before the thing a child is excited about, 97.9% of the
  // screen was frozen.
  //
  // The arch has six lamps baked into the underside of its beam and they sit
  // there unlit. This lights them, two per beat, from the outside in: the pair
  // at the ends on `3`, the next pair on `2`, all six on `1`, and on GO all six
  // at full with the halo up. NOTHING IS REDRAWN -- the six rectangles are at
  // the housings' own positions, measured off `assets/props/gantry.png` and
  // expressed as fractions of the prop's `C0` opaque box, exactly as the board
  // above is. The housings are palette index 22, `#ffd489`, in six clusters of
  // about 40 x 20 cell pixels along the beam.
  //
  // AND IT IS A LAMP CHANGE, SO IT SURVIVES REDUCED MOTION. The design's line
  // is "reduced motion replaces shakes and lurches with gauge and LAMP
  // changes"; what reduced motion turns off here is the 140 ms fade, not the
  // lamp.
  readonly property color lampTone: "#ffd489"
  readonly property var lampBoxes: [
    [0.0912, 0.1239, 0.2862, 0.3185],
    [0.2447, 0.2759, 0.2877, 0.3185],
    [0.3983, 0.4279, 0.2877, 0.3185],
    [0.5511, 0.5807, 0.2877, 0.3185],
    [0.7030, 0.7350, 0.2877, 0.3185],
    [0.8550, 0.8885, 0.2862, 0.3185]
  ]
  readonly property var lampsLit: [
    [1, 0, 0, 0, 0, 1],
    [1, 1, 0, 0, 1, 1],
    [1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1]
  ]

  Repeater {
    id: startLamps
    model: countdown.archStands ? countdown.lampBoxes.length : 0

    Item {
      required property int index
      readonly property var box: countdown.lampBoxes[index]
      readonly property real lit: countdown.lampsLit[Math.max(0, Math.min(3, countdown.beat))][index]
      readonly property real lx: countdown.archBox.x + box[0] * countdown.archBox.width
      readonly property real rx: countdown.archBox.x + box[1] * countdown.archBox.width
      readonly property real ty: countdown.archBox.y + box[2] * countdown.archBox.height
      readonly property real by: countdown.archBox.y + box[3] * countdown.archBox.height

      x: lx
      y: ty
      width: Math.max(1, rx - lx)
      height: Math.max(1, by - ty)
      z: 2
      opacity: lit
      visible: opacity > 0.01
      Behavior on opacity {
        enabled: !countdown.reducedMotion
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      // The halo, banded rather than blurred, for the same reason `CarLight`'s
      // key is banded: this is a pixel-art frame and a soft gradient laid over
      // it reads as a photograph. Two rectangles, no gradient, no shader.
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * (countdown.go ? 3.2 : 2.2)
        height: parent.height * (countdown.go ? 3.2 : 2.2)
        color: countdown.lampTone
        opacity: countdown.go ? 0.26 : 0.16
        antialiasing: false
      }
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * (countdown.go ? 1.7 : 1.4)
        height: parent.height * (countdown.go ? 1.7 : 1.4)
        color: countdown.lampTone
        opacity: countdown.go ? 0.55 : 0.40
        antialiasing: false
      }
      Rectangle {
        anchors.fill: parent
        color: countdown.go ? "#fff6dd" : "#ffe6ad"
        antialiasing: false
      }
    }
  }

  // ---------------------------------------------- what the lamps land on
  //
  // THE OTHER HALF OF THE ARCH'S LAMPS, AND THE ONE WITH AREA IN IT. Six lamps
  // coming on over a start line light the tarmac under them, and the
  // measurement that sent this piece at the countdown was about area. Six lit
  // rectangles on a beam are the right device and they are 0.3% of the frame;
  // this is the same device with the road in it.
  //
  // The road's shape is the VIEW'S: `place.uAt` and `place.vAt` are the
  // projection the tarmac under it was painted by, so the pool lies on the road
  // rather than near it. It is painted into a 480 x 270 canvas -- the size the
  // design puts this game's art at, and the size the view's own road plane is
  // -- so the wash is 11,000 pixels of blending rather than 184,000, and it is
  // repainted on a beat rather than on a frame.
  //
  // It stops at 0.14 on GO on purpose: the race opens on this same tarmac one
  // second later with no light on it, and a countdown that ended with the road
  // glowing would hand over to a frame where it is not.
  readonly property real lampWash: [0.00, 0.06, 0.11, 0.14][Math.max(0, Math.min(3, countdown.beat))]

  Item {
    id: washPlane
    anchors.fill: parent
    z: 1
    visible: countdown.lampWash > 0

    Canvas {
      id: wash
      width: 480
      height: 270
      renderStrategy: Canvas.Immediate
      renderTarget: Canvas.Image
      smooth: false
      antialiasing: false
      transform: Scale {
        xScale: countdown.width / 480
        yScale: countdown.height / 270
      }

      // The road, in this canvas's own pixels, from the view's projection. Ten
      // slices rather than one quad because the road is allowed to curve and
      // the pool has to curve with it.
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, 480, 270)
        if (countdown.lampWash <= 0 || countdown.width <= 0 || countdown.height <= 0)
          return
        var pool = ctx.createLinearGradient(0, place.horizon * 270, 0, 270)
        pool.addColorStop(0, Qt.rgba(1, 0.831, 0.537, countdown.lampWash * 0.35))
        pool.addColorStop(0.42, Qt.rgba(1, 0.831, 0.537, countdown.lampWash))
        pool.addColorStop(1, Qt.rgba(1, 0.831, 0.537, countdown.lampWash * 0.30))
        ctx.fillStyle = pool
        // Near to far up the left edge, far to near back down the right one.
        var slices = 10
        var zNear = place.playerZ * 0.55
        var zFar = 26
        ctx.beginPath()
        for (var i = 0; i <= slices; i++) {
          var z = zNear + (zFar - zNear) * Math.pow(i / slices, 2)
          var v = place.vAt(z) * 270
          var u = place.uAt(-place.roadHalf, z) * 480
          if (i === 0)
            ctx.moveTo(u, v)
          else
            ctx.lineTo(u, v)
        }
        for (var j = slices; j >= 0; j--) {
          var z2 = zNear + (zFar - zNear) * Math.pow(j / slices, 2)
          ctx.lineTo(place.uAt(place.roadHalf, z2) * 480, place.vAt(z2) * 270)
        }
        ctx.closePath()
        ctx.fill()
      }
    }
  }
  onLampWashChanged: wash.requestPaint()
  onWidthChanged: wash.requestPaint()
  onHeightChanged: wash.requestPaint()

  // ------------------------------------------------------- the first fact
  //
  // Drawn from the GO beat, at the race's own size, in the race's own place,
  // with the race's own ground under it. The design's line is "the first fact
  // readable behind GO"; this is that, and it is also the object the design
  // says has to carry across the cut, so the cut is where it is measured.
  Rectangle {
    id: factPlate
    z: 3
    visible: opacity > 0.004
    // The same expression `ui/Race.qml`'s `factGround` uses for the same
    // reason, driven by the same view: the arch's crossbar is a cream-and-ink
    // chequer and the fact is cream, so for the frames a crossbar is behind the
    // ink the fact gets a ground.
    opacity: (countdown.go ? 1 : 0) * place.factYield * 0.86
    Behavior on opacity {
      enabled: !countdown.reducedMotion
      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    x: countdown.lineInkRect.x - countdown.px(22)
    y: countdown.lineInkRect.y - countdown.px(14)
    width: countdown.lineInkRect.width + countdown.px(44)
    height: countdown.lineInkRect.height + countdown.px(28)
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(0.235, 0.071, 0.157, 0.80)
  }

  // ROUND 8: THE LINE, NOT THE FACT. Round 7 drew `7 × 8` here with no
  // `= ▮`, while the prompt bottom-left said TYPE THE ANSWER and the race a
  // second later drew `7 × 8 = ▮` -- so the line the child was told to type on
  // was not yet the line. This is the race's own construction (`ui/Race.qml`,
  // "the line is one Row"): the fact with its equals sign, then a slot the
  // width of the widest answer holding the typed-ahead digits and a block
  // caret, in the fact's own type and treatment. The digits a child types on
  // the GO beat land in the slot, exactly where they will be a second later.
  Item {
    id: factGlyph
    anchors.horizontalCenter: parent.horizontalCenter
    y: countdown.factTopY
    width: line.width
    height: line.height
    z: 4

    // One expression on every beat rather than two: before GO the fact is drawn
    // at zero opacity, and a fade that starts at a different size from the one
    // it lands at is a fade and a resize at once.
    opacity: countdown.go ? 1.0 : 0.0
    Behavior on opacity {
      enabled: !countdown.reducedMotion
      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Row {
      id: line
      objectName: "factColumn"
      x: 0
      y: 0
      spacing: countdown.px(28)

      LitWord {
        id: factWord
        words: countdown.factText + " ="
        // The four numbers `ui/Race.qml` hands the same part, at this screen's
        // scale, so the glyphs on either side of the cut are the same glyphs.
        size: countdown.factPixelSize
        spacing: countdown.px(6)
        drop: countdown.px(6)
        contour: Math.max(2, countdown.px(5))
        rimOffset: Math.max(1, Math.round(Math.max(2, countdown.px(5)) * 0.55))
        faceTone: Theme.cream
        shadowTone: countdown.inkShadow
        bodyTone: countdown.inkBody
        rimTone: countdown.inkRim
      }

      // The slot: three digits and a caret, whatever is typed, so `7 × 8 =`
      // never slides as digits arrive.
      Item {
        id: answerSlot
        objectName: "answerField"
        width: answerProbe.advanceWidth + caretMark.width + countdown.px(8)
        height: factWord.height
        anchors.verticalCenter: parent.verticalCenter

        TextMetrics {
          id: answerProbe
          font: factWord.faceFont
          text: "144"
        }
        TextMetrics {
          id: answerCap
          font: factWord.faceFont
          text: "8"
        }

        LitWord {
          id: answerWord
          x: 0
          y: 0
          words: countdown.typedText
          size: countdown.factPixelSize
          spacing: countdown.px(6)
          drop: countdown.px(6)
          contour: Math.max(2, countdown.px(5))
          rimOffset: Math.max(1, Math.round(Math.max(2, countdown.px(5)) * 0.55))
          faceTone: Theme.amberGlow
          shadowTone: countdown.inkShadow
          bodyTone: countdown.inkBody
          rimTone: countdown.inkRim
        }

        // The block caret, as the race draws it, blinking at the race's 1.25 Hz
        // from the GO beat; a steady block under reduced motion.
        Rectangle {
          id: caretMark
          objectName: "caret"
          x: answerWord.width + (countdown.typedAhead.length > 0 ? countdown.px(10) : 0)
          y: factFaceMetrics.ascent + answerCap.tightBoundingRect.y
          width: Math.max(6, Math.round(countdown.factPixelSize * 0.16))
          height: Math.max(8, Math.round(answerCap.tightBoundingRect.height))
          radius: 2
          color: Theme.amberGlow
          visible: caretBlink.on && countdown.typedAhead.length < 3
          border.width: Math.max(1, countdown.px(2))
          border.color: countdown.inkBody
        }
        Timer {
          id: caretBlink
          property bool on: true
          interval: 400
          repeat: true
          running: countdown.visible && countdown.go && !countdown.reducedMotion
          onRunningChanged: if (!running) caretBlink.on = true
          onTriggered: caretBlink.on = !caretBlink.on
        }
      }
    }
  }

  // ------------------------------------------------------------ the beats
  //
  // 3, 2, 1, enormous, in the sky beside the arch. On GO the word is the same
  // size the counted beats were: nothing about the release is quieter than the
  // beats that led to it any more.
  Item {
    id: beatGlyph
    x: Math.round(countdown.typeColumnX - width / 2)
    y: countdown.beatY
    width: beatFace.width
    height: beatFace.height
    z: 5

    // What a critic can read back without measuring pixels: where this glyph's
    // ink actually starts and ends in the frame, at rest and at the top of the
    // pulse.
    readonly property real inkTopY: beatGlyph.y
                                    + countdown.beatInk.top * countdown.beatPixelSize
    readonly property real inkBottomY: beatGlyph.inkTopY
                                       + countdown.beatInk.height * countdown.beatPixelSize
    readonly property real inkBottomAtPulse: beatGlyph.inkBottomY
                                             + countdown.beatSwing * countdown.beatPixelSize
    // The ink's own columns, which is what "clear of the arch" is measured
    // against. The pulse widens it about its centre, so the widest the word
    // ever is is the resting advance times the pulse.
    readonly property real inkWidePx: countdown.beatInk.advance * countdown.beatPixelSize
                                      * countdown.beatPulse
                                      + countdown.beatSpacing
                                        * Math.max(0, countdown.beatWord.length - 1)
    readonly property real inkLeftX: countdown.typeColumnX - beatGlyph.inkWidePx / 2
                                     - countdown.beatShadowDrop - countdown.inkContour
    readonly property real inkRightX: countdown.typeColumnX + beatGlyph.inkWidePx / 2
                                      + countdown.inkContour + countdown.inkRimOffset

    LitWord {
      id: beatFace
      words: countdown.beatWord
      size: countdown.beatPixelSize
      spacing: countdown.beatSpacing
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

    // ONE PULSE PER BEAT, DRIVEN BY THE BEAT AND NOT ALONGSIDE IT. A free
    // running loop and the `Timer` are two clocks with nothing keeping them in
    // step, so the numeral swelled while the number was standing still and
    // stood still as it changed -- and a picture case grabbing frames a few
    // tens of milliseconds apart photographed an arbitrary phase. Nothing at
    // all under reduced motion, which the design's accessibility section asks
    // for by name.
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
    Component.onCompleted: beatGlyph.surge()
    Connections {
      target: countdown
      function onBeatChanged() { beatGlyph.surge() }
      function onVisibleChanged() { beatGlyph.surge() }
    }
  }

  // ROUND 8: the type-ahead readout that stood here -- a row of boxed digits
  // under the fact -- is gone. The digits are drawn in the line's own answer
  // slot (`answerWord` above), which is where the race draws them a second
  // later.

  // ------------------------------------------------------------ the footer
  //
  // THE TWO STRINGS THAT HAD NO KEYLINE NOW HAVE ONE. Round 1's verdict, 6c:
  // "these two strings are the only words on the screen carrying no shadow and
  // no keyline -- every other word got the full treatment and these did not",
  // measured at 1.86 : 1 against the lightest ground under them and the word
  // `BACK` lost at two window sizes. `LitWord` costs one cached texture now, so
  // giving them the frame's own light is affordable, and they stand bottom left
  // over the dark verge rather than centred over the road's own cream markings.
  //
  // The prompt warms to full cream on GO instead of turning lime: lime is the
  // garage's, and there is no lime in this light.
  LitWord {
    id: prompt
    x: countdown.px(48)
    y: countdown.height - countdown.px(108)
    z: 5
    words: countdown.go ? "TYPE THE ANSWER" : "GET READY"
    size: countdown.fs(26)
    spacing: countdown.px(4)
    drop: Math.max(2, countdown.px(3))
    contour: Math.max(2, countdown.px(3))
    rimOffset: Math.max(1, countdown.px(2))
    faceTone: countdown.go
              ? Theme.cream
              : Qt.rgba(Theme.cream.r, Theme.cream.g, Theme.cream.b, 0.82)
    shadowTone: countdown.inkShadow
    bodyTone: countdown.inkBody
    rimTone: countdown.inkRim
  }

  // PIECE M. The countdown's one action, and it was already printed here: the
  // line that says ESC is now the thing you press. No new chrome and no new
  // words -- the screen already told the child what the key was, and this makes
  // the sentence a control. It stands where the race puts `ESC LEAVE`, so the
  // one control that survives the cut does not move across it.
  //
  // The other keys of this screen are the type-ahead digits, which belong to
  // the answer and not to any control on it. See the report's "what is not
  // covered": there is no on-screen keypad anywhere in this game.
  KeyHint {
    id: countdownBack
    x: countdown.px(48)
    y: countdown.height - countdown.px(62)
    z: 5

    keys: "ESC"
    action: "BACK TO THE GARAGE"
    textSize: countdown.fs(16)
    letterSpacing: countdown.px(2)
    bold: false
    idleColor: Qt.rgba(Theme.cream.r, Theme.cream.g, Theme.cream.b, 0.72)
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
