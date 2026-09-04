import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../engine/engine.mjs" as Engine

// The countdown: the four beats, and the type that must not cross the gantry.
//
// The plan's piece-5 row leaves one defect on this screen -- "the numeral covers
// the gantry's board on beats 3-1" -- and a screenshot is a poor guard for it,
// because the frame a builder happens to shoot is one beat, at one size, at one
// instant of the pulse. This file guards it at three sizes, on all four beats,
// and at the top of the pulse as well as at rest.
//
// WHAT IS SET UP AND WHAT IS PLAYED. `beat` is the countdown's own clock and is
// set directly in the geometry and picture cases, because a case that waited
// three real seconds for `3` to become `1` would be measuring a `Timer`; the
// picture cases go through `holdTheBeat`, which stops the ticker first for the
// reason written beside it. `test_09` to `test_11` do run the real ticker, at a
// shortened `beatMs`, and every key in them is a real `keyClick()`.
//
// ================================================ ROUND 6: TESTS THAT LOOK
//
// Round 5's critic deleted `ctx.fillText("TURBO TABLES", ...)` outright in a
// copy of `ui/parts/CountdownScene.qml` and this whole file stayed green --
// including `test_04_the_board_carries_the_words_it_is_cleared_for`, whose
// name is a claim about words and whose body only asserted that the board had
// a POSITION. A round spent clearing a sponsor board passed its own suite with
// the sponsor board blank.
//
// WHY that could happen is worth writing down, because it is the third weak
// test found in this tree in two rounds. Every case in here read the screen
// through published properties -- `gantryBoardTopY`, `beatInkBottomAtPulse` --
// which are `ui/Countdown.qml`'s and `CountdownScene.qml`'s OWN arithmetic. A
// property is the cheapest thing to assert on and the only thing this file
// knew how to reach, so every case drifted toward geometry the code computes
// about itself, and a name could promise a picture while the body checked a
// number. `tests/qml/tst_carsprite.qml:31-35` says outright that "QtTest's
// grabImage cannot be used for this -- under the offscreen platform it returns
// the window's blank background", and that belief -- which is FALSE for
// grabbing an Item, and this file now depends on it being false -- is what
// closed the door. Measured on this Mac: `grabImage(countdown)` returns the
// real 1920 x 1080 picture in 2 ms, and scanning 20,000 of its pixels takes
// about 1 ms. Looking was never expensive. It was believed impossible.
//
// So the six cases marked THE PICTURE below -- `test_04` through `test_08b` --
// read the rendered frame. They are the ones that die when a painted thing
// stops being painted, and ten mutations in an isolated copy say so: deleting
// the board's `fillText`, cutting it to one letter, blanking it to spaces,
// putting the board's ink back to round 5's `skyMid`, putting the sun's cut
// lines back on round 5's fixed rhythm, moving the type's floor back over the
// board, deleting the contour, deleting the warm rim, deleting both (which is
// round 5's type exactly), and painting the contour in cream instead of ink.
// Ten mutations, ten deaths, no survivors. The table is in
// `PREFIX/evidence/piece5-r6-ours.md`.
//
// Run it:
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
//     qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml
Item {
  id: root
  width: 1920
  height: 1080

  Countdown {
    id: countdown
    anchors.fill: parent
    seed: 42
  }

  property int finishes: 0
  property int aborts: 0

  Connections {
    target: countdown
    function onFinished() { root.finishes += 1 }
    function onAbortRequested() { root.aborts += 1 }
  }

  TestCase {
    id: tc
    name: "CountdownBoard"
    when: windowShown

    // The three sizes the evidence is shot at. 1366 x 768 is the one a child is
    // most likely to be playing at and is the tightest fit.
    readonly property var sizes: [ { "w": 1366, "h": 768 },
                                   { "w": 1920, "h": 1080 },
                                   { "w": 2560, "h": 1440 } ]

    function sizeTo(w, h) {
      root.width = w
      root.height = h
      // Bindings run on assignment in QML, so the geometry below is already
      // the geometry of this size. The wait is for the scene's Canvas, which
      // repaints the board on a size change and is what `boardTopY` describes.
      tc.wait(30)
    }

    function cleanupTestCase() {
      root.width = 1920
      root.height = 1080
    }

    // ------------------------------------------------------------- the beats
    function test_00_the_four_beats_are_the_designs() {
      compare(countdown.beatMs, 1000, "design, Motion: 1 s countdown beats")
      compare(countdown.beatWords.length, 4)
      compare(countdown.beatWords[0], "3")
      compare(countdown.beatWords[1], "2")
      compare(countdown.beatWords[2], "1")
      compare(countdown.beatWords[3], "GO")
    }

    // The defect, guarded. The numeral's ink -- not its line box, which is
    // mostly air -- plus the drop shadow under it, must finish above the top
    // edge of the gantry's sponsor board, at the widest moment of the pulse.
    function test_01_the_numeral_never_crosses_the_board() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        for (var b = 0; b < 4; b++) {
          countdown.beat = b
          var label = tc.sizes[s].w + "x" + tc.sizes[s].h + " beat " + countdown.beatWord
          var floor = countdown.gantryBoardTopY
          verify(countdown.beatInkBottomAtPulse + countdown.beatShadowDrop <= floor,
                 label + ": the numeral's ink and its shadow end at "
                 + Math.round(countdown.beatInkBottomAtPulse + countdown.beatShadowDrop)
                 + " and the gantry board starts at " + Math.round(floor))
          verify(countdown.beatInkTopY >= 0,
                 label + ": the numeral is not clipped by the top of the frame, ink top "
                 + Math.round(countdown.beatInkTopY))
        }
      }
      countdown.beat = 0
    }

    // Design, Race format: "the first fact readable behind GO". Readable means
    // clear of the only other words in the picture.
    function test_02_the_first_fact_never_crosses_the_board() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        countdown.beat = 3
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        verify(countdown.factInkBottomY + countdown.factShadowDrop
               <= countdown.gantryBoardTopY,
               label + ": the fact's ink and shadow end at "
               + Math.round(countdown.factInkBottomY + countdown.factShadowDrop)
               + ", the board starts at " + Math.round(countdown.gantryBoardTopY))
        verify(countdown.factInkTopY > countdown.beatInkBottomY,
               label + ": GO sits above the fact and does not touch it")
      }
      countdown.beat = 0
    }

    // Clearing the board is worth nothing if it were bought by shrinking the
    // numeral into the chrome. Two floors, both from the documents: the plan
    // calls the number "huge", and the design's accessibility section fixes the
    // fact at "never smaller than a tenth of the screen height".
    function test_03_the_type_is_still_the_size_the_documents_ask_for() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        for (var b = 0; b < 3; b++) {
          countdown.beat = b
          var ink = countdown.beatInkBottomY - countdown.beatInkTopY
          verify(ink >= root.height * 0.38,
                 label + " beat " + countdown.beatWord + ": the numeral's ink is "
                 + Math.round(ink) + " px, which is "
                 + (100 * ink / root.height).toFixed(1) + "% of the frame")
        }
        countdown.beat = 3
        var factInk = countdown.factInkBottomY - countdown.factInkTopY
        verify(factInk >= root.height * 0.10,
               label + ": the fact's ink is " + Math.round(factInk) + " px, and a tenth"
               + " of the frame is " + Math.round(root.height * 0.10))
      }
      countdown.beat = 0
    }

    // ============================================================ THE PICTURE
    //
    // Everything from here to the keyboard section reads the rendered frame.

    // Is the pixel at (x, y) this colour, within `tol` per channel on 0..255?
    function isTone(img, x, y, c, tol) {
      return Math.abs(img.red(x, y) - Math.round(c.r * 255)) <= tol
          && Math.abs(img.green(x, y) - Math.round(c.g * 255)) <= tol
          && Math.abs(img.blue(x, y) - Math.round(c.b * 255)) <= tol
    }

    // How many pixels of `c` are inside the rectangle, and how many separate
    // columns hold at least one of them. The column count is what tells twelve
    // letters apart from one solid block of paint.
    function countTone(img, x0, y0, x1, y1, c, tol) {
      var n = 0
      var columns = 0
      for (var x = x0; x < x1; x++) {
        var inColumn = false
        for (var y = y0; y < y1; y++)
          if (tc.isTone(img, x, y, c, tol)) {
            n += 1
            inColumn = true
          }
        if (inColumn)
          columns += 1
      }
      return { "count": n, "columns": columns }
    }

    // Hold the beat still. The ticker is a real `Timer` and it does not care
    // that a case has set `beat` by hand: at the design's 1 s it will step the
    // screen on under any case that grabs more than one frame, and a probe run
    // of this file caught exactly that -- three consecutive measurements
    // labelled "beat 1", "beat 1", "beat GO", all of them taken of whatever the
    // ticker had moved to. `done` is the screen's own name for "the ticker has
    // finished"; it stops the `Timer` and changes nothing that is painted, so
    // the pulse, the fade and the type are all still the shipping ones.
    function holdTheBeat(b) {
      countdown.done = true
      countdown.beat = b
    }

    // THE PICTURE. The board is only worth clearing if it says something, and
    // for three rounds nothing checked that it did: round 5's critic deleted
    // the `fillText` and this case, under this exact name, stayed green because
    // it only asserted that the board had a position. It now reads the board's
    // own rectangle out of the rendered frame and counts the ink.
    //
    // `TURBO TABLES` is twelve characters at 9 layer pixels, drawn once per
    // size, so the counts below are large and the margins are wide: deleting
    // the text takes the ink to zero and every one of the four checks with it.
    function test_04_the_board_carries_the_words_it_is_cleared_for() {
      tc.holdTheBeat(0)
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        var img = grabImage(countdown)
        // The board's own rect, from the scene that paints it. Two rows in from
        // the top edge, which is the gantry's warm rim line and not the board.
        var x0 = Math.round(countdown.gantryBoardLeftX)
        var x1 = Math.round(countdown.gantryBoardRightX)
        var y0 = Math.round(countdown.gantryBoardTopY) + 2
        var y1 = Math.round(countdown.gantryBoardBottomY)
        verify(x1 - x0 > 40 && y1 - y0 > 4,
               label + ": the board's rect is " + (x1 - x0) + "x" + (y1 - y0))

        var ink = tc.countTone(img, x0, y0, x1, y1, countdown.gantryBoardInk, 10)
        var fill = tc.countTone(img, x0, y0, x1, y1, countdown.gantryBoardFill, 10)
        verify(ink.count > 200,
               label + ": the board carries " + ink.count + " pixels of its own"
               + " ink; a blank board carries none")
        verify(ink.columns >= 20,
               label + ": the ink stands in " + ink.columns + " separate columns"
               + " of the board -- twelve characters, not one block")
        verify(fill.count > ink.count,
               label + ": the board is still mostly board -- " + fill.count
               + " pixels of fill against " + ink.count + " of ink")
        // And the words are where the words go: inside the middle of the board,
        // not crowded against one end.
        var mid = tc.countTone(img, Math.round(x0 + (x1 - x0) * 0.4),
                               y0, Math.round(x0 + (x1 - x0) * 0.6), y1,
                               countdown.gantryBoardInk, 10)
        verify(mid.count > 0, label + ": there is type across the middle of the board")
      }
    }

    // THE PICTURE. The design's contrast floor, read off the frame rather than
    // off the palette: the two colours the board is actually painted in.
    //
    // Round 5 drew the words in `skyMid` on `signage` -- 3.62:1, AA for large
    // text only, and the glyphs are about 25 screen pixels tall at 1366 x 768.
    // Nothing measured it, in the round whose whole subject was that board.
    function test_05_the_boards_words_clear_the_contrast_floor() {
      function channel(v) {
        var f = v / 255.0
        return f <= 0.04045 ? f / 12.92 : Math.pow((f + 0.055) / 1.055, 2.4)
      }
      function luminance(c) {
        return 0.2126 * channel(c.r * 255) + 0.7152 * channel(c.g * 255)
             + 0.0722 * channel(c.b * 255)
      }
      tc.holdTheBeat(0)
      tc.sizeTo(1920, 1080)
      var img = grabImage(countdown)
      var x0 = Math.round(countdown.gantryBoardLeftX)
      var x1 = Math.round(countdown.gantryBoardRightX)
      var y0 = Math.round(countdown.gantryBoardTopY) + 2
      var y1 = Math.round(countdown.gantryBoardBottomY)
      // Both colours must be the ones actually on screen, not the ones the
      // scene says it uses, or this measures a pair of properties.
      var ink = tc.countTone(img, x0, y0, x1, y1, countdown.gantryBoardInk, 6)
      var fill = tc.countTone(img, x0, y0, x1, y1, countdown.gantryBoardFill, 6)
      verify(ink.count > 200 && fill.count > 200,
             "both of the board's colours are on the screen: ink " + ink.count
             + ", fill " + fill.count)
      var li = luminance(countdown.gantryBoardInk)
      var lf = luminance(countdown.gantryBoardFill)
      var ratio = (Math.max(li, lf) + 0.05) / (Math.min(li, lf) + 0.05)
      verify(ratio >= 4.5,
             "the board's ink on the board's fill is " + ratio.toFixed(2)
             + ":1, and WCAG AA for normal text is 4.5:1")
    }

    // THE PICTURE. Round 5's achievement, guarded where it was claimed: not one
    // pixel of the type's cream inside the board's own rows, on every beat and
    // at every size. `test_01` asserts the same thing from the file's own
    // arithmetic and so cannot catch an error in that arithmetic; this looks.
    // Part B sweeps the beat pulse, which is where round 5's evidence stopped:
    // it asserted the worst case arithmetically and never photographed it. With
    // the ticker stopped (`done`) and `beatMs` short, the pulse animation loops
    // every 260 ms with no pause, so a dozen grabs across a third of a second
    // land all over it, top included.
    function creamInsideTheBoard(img) {
      return tc.countTone(img, 0, Math.round(countdown.gantryBoardTopY),
                          root.width, Math.round(countdown.gantryBoardBottomY),
                          Theme.cream, 14).count
    }

    function test_06_no_cream_of_the_type_falls_inside_the_board() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        for (var b = 0; b < 4; b++) {
          tc.holdTheBeat(b)
          // The fact fades in over 220 ms on GO and a half-faded fact would
          // make this pass for the wrong reason.
          tc.wait(b === 3 ? 300 : 20)
          var cream = tc.creamInsideTheBoard(grabImage(countdown))
          compare(cream, 0,
                  tc.sizes[s].w + "x" + tc.sizes[s].h + " beat " + countdown.beatWord
                  + ": " + cream + " cream pixels inside the board's rows "
                  + Math.round(countdown.gantryBoardTopY) + ".."
                  + (Math.round(countdown.gantryBoardBottomY) - 1))
        }
      }

      // Part B: the same count, photographed right across the pulse.
      tc.holdTheBeat(0)
      countdown.beatMs = 40          // no pause between the pulse's loops
      var worst = 0
      var frames = 0
      for (var t = 0; t < 12; t++) {
        tc.wait(28)
        worst = Math.max(worst, tc.creamInsideTheBoard(grabImage(countdown)))
        frames += 1
      }
      countdown.beatMs = 1000
      countdown.done = false
      compare(worst, 0, "across " + frames + " frames of the beat pulse the worst"
              + " cream count inside the board was " + worst)
    }

    // THE PICTURE. The genre's signature, and the reference's defining feature:
    // the sun is cut by horizontal bands. Ours drew seven and the hills ate all
    // but one of the four that cleared the horizon -- 208 unbroken rows of flat
    // `#efcb72` down the disc's centre column, with a single 4-row stripe.
    //
    // This walks that column from the top of the disc to the first hill pixel
    // and counts the bands a child can actually see.
    function test_07_the_sun_is_banded_where_the_hills_leave_it() {
      tc.holdTheBeat(0)
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        var img = grabImage(countdown)
        var x = Math.round(countdown.sunCentreX)
        var top = Math.round(countdown.sunTopY)
        var floor = Math.round(countdown.sunSkylineY)
        verify(floor - top > 20, label + ": the sun's visible arc is "
               + (floor - top) + " rows")
        // A run of core-yellow ends wherever a band interrupts it. Count both.
        var core = Qt.color("#efcb72")
        var bands = 0
        var longestFlat = 0
        var flat = 0
        var wasCore = false
        for (var y = top; y < floor; y++) {
          var isCore = tc.isTone(img, x, y, core, 16)
          if (isCore) {
            flat += 1
            longestFlat = Math.max(longestFlat, flat)
          } else {
            flat = 0
            if (wasCore)
              bands += 1
          }
          wasCore = isCore
        }
        verify(bands >= 5,
               label + ": only " + bands + " cut lines break the sun above the"
               + " hills; the reference's sun is banded, not a flat dome")
        verify(longestFlat < (floor - top) * 0.62,
               label + ": the longest unbroken run of flat sun is " + longestFlat
               + " rows of a " + (floor - top) + "-row visible arc")
        compare(countdown.sunCutsAboveSkyline >= 5, true,
                label + ": the stack fits " + countdown.sunCutsAboveSkyline
                + " cuts above the skyline")
      }
    }

    // THE PICTURE. The GO beat's fact stands on the sun, and cream on the sun's
    // own `#efcb72` is 1.26:1. It used to sit there directly -- 89 cream pixels
    // of the shipped 1920 x 1080 frame touched the disc, held up by a cast
    // shadow thrown away from the sun and so useless on the edge nearest it.
    //
    // The contour is what must hold this at zero, and this case proves it is
    // the contour and not the shadow: it looks at every cream pixel in the
    // frame and asks whether any of them borders the disc.
    //
    // IT DID NOT, AT FIRST, AND THE MUTATION SAID SO. The first version of this
    // case knew only about `sunCore`, the flat `#efcb72` centre. Setting
    // `inkContour: 0` in an isolated copy -- deleting the very thing the comment
    // above says carries the fix -- left the whole suite green, because the disc
    // is a GRADIENT: `sunCore` out to 72% of the radius and `sunEdge` `#f0956e`
    // at the rim, and it is the rim the fact's outermost glyphs sit against.
    // Rendered with the contour gone: 0 and 1 cream pixels on the core at
    // 1920 x 1080 and 1366 x 768, but 28 and 15 on the edge, at 1.83:1.
    //
    // That is the same failure this whole round is about, one layer in -- a
    // guard whose name says "the sun" and whose body knew one of the sun's two
    // colours. It now counts both, and asserts each is on the screen before it
    // counts, so a palette that moved cannot make the count vacuously zero.
    //
    // The window scanned is the disc's own bounding box, clipped at the board's
    // top edge -- below that line the cream is the gantry's checkers and the
    // road's markings, which are not type and are nowhere near the sun.
    //
    // A PIXEL COUNTS AS THE SUN ONLY IF IT IS ALSO INSIDE THE DISC, and that
    // clause was not free. Ten stray pixels in the GO word's own rim-to-cream
    // antialiasing, four hundred rows above the sun, fall inside `sunEdge` plus
    // or minus 16 -- so a tone test alone reported the type touching a sun that
    // was nowhere near it, and the count wobbled by one or two between runs for
    // that reason and no other. The disc is geometry the scene publishes, so
    // the clause costs nothing and removes the whole class.
    //
    // Two measurements come back, not one. `touching` is contact, which must be
    // zero. `within2` is CLEARANCE -- cream with a disc pixel within two, in
    // any of the eight directions -- and that is the one with a margin: on the
    // shipped frames it is 6 and 8, with the contour gone it is 399, and with
    // round 5's shadow-only type it is 660. Contact alone nearly cannot tell
    // the second of those apart from the shipped picture, because a one-pixel
    // warm rim covers a boundary just as well as a six-pixel keyline does; it
    // is the clearance that says which one is a keyline.
    function sunContacts(img, tones) {
      var cx = countdown.sunCentreX
      var cy = countdown.sunCentreY
      var rx = Math.max(1, countdown.sunRadiusX)
      var ry = Math.max(1, countdown.sunRadiusY)
      var x0 = Math.max(2, Math.floor(cx - rx) - 2)
      var x1 = Math.min(root.width - 2, Math.ceil(cx + rx) + 2)
      var y0 = Math.max(2, Math.floor(cy - ry) - 2)
      var y1 = Math.min(Math.round(countdown.gantryBoardTopY), Math.ceil(cy + ry) + 2)
      function discTone(x, y) {
        var ex = (x - cx) / rx
        var ey = (y - cy) / ry
        if (ex * ex + ey * ey > 1.0)
          return -1
        for (var t = 0; t < tones.length; t++)
          if (tc.isTone(img, x, y, tones[t].c, 16))
            return t
        return -1
      }
      var out = { "touching": [0, 0], "present": [0, 0], "firstAt": ["", ""],
                  "onTheDisc": 0, "within2": 0 }
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          var here = discTone(x, y)
          if (here >= 0)
            out.present[here] += 1
          if (!tc.isTone(img, x, y, Theme.cream, 10))
            continue
          var ex = (x - cx) / rx
          var ey = (y - cy) / ry
          if (ex * ex + ey * ey < 0.85)
            out.onTheDisc += 1
          for (var u = 0; u < tones.length; u++) {
            if (discTone(x + 1, y) === u || discTone(x - 1, y) === u
                || discTone(x, y + 1) === u || discTone(x, y - 1) === u) {
              out.touching[u] += 1
              if (out.firstAt[u] === "")
                out.firstAt[u] = " (first at " + x + "," + y + ")"
            }
          }
          var near = false
          for (var dy = -2; dy <= 2 && !near; dy++)
            for (var dx = -2; dx <= 2 && !near; dx++)
              if (discTone(x + dx, y + dy) >= 0)
                near = true
          if (near)
            out.within2 += 1
        }
      }
      return out
    }

    function test_08_no_cream_of_the_type_sits_straight_on_the_sun() {
      var tones = [ { "c": countdown.sunCoreTone, "name": "the sun's core #efcb72 at 1.26:1" },
                    { "c": countdown.sunEdgeTone, "name": "the sun's rim #f0956e at 1.83:1" } ]
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        tc.holdTheBeat(3)
        countdown.beatMs = 40     // no pause between the pulse's loops
        tc.wait(300)              // and the fact fades in over 220 ms
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        // GO pulses. Four grabs across a third of a second land all over that
        // pulse, so this is the widest the word ever gets and not one instant
        // of it -- the gap round 5's evidence was caught leaving open.
        var worst = { "touching": [0, 0], "present": [0, 0], "firstAt": ["", ""],
                      "onTheDisc": 0, "within2": 0 }
        for (var f = 0; f < 4; f++) {
          if (f > 0)
            tc.wait(70)
          var r = tc.sunContacts(grabImage(countdown), tones)
          worst.onTheDisc = Math.max(worst.onTheDisc, r.onTheDisc)
          worst.within2 = Math.max(worst.within2, r.within2)
          for (var w = 0; w < tones.length; w++) {
            worst.present[w] = Math.max(worst.present[w], r.present[w])
            if (r.touching[w] > worst.touching[w]) {
              worst.touching[w] = r.touching[w]
              worst.firstAt[w] = r.firstAt[w]
            }
          }
        }
        countdown.beatMs = 1000
        // Zero would be trivially true if the fact had simply moved off the
        // sun, and the design puts it there on purpose: "the first fact
        // readable behind GO", over the disc. So it has to be standing on the
        // sun AND not touching it.
        verify(worst.onTheDisc > 150,
               label + ": only " + worst.onTheDisc + " cream pixels of the type"
               + " stand within the sun's disc -- the fact is supposed to be on it")
        // The keyline, measured rather than assumed. Six pixels of contour put
        // the type's cream that far from the disc; a one-pixel rim does not.
        // Read by this case on the shipping build: 7 at 1366 x 768, 4 at
        // 1920 x 1080, 6 at 2560 x 1440, stable across runs. Read by this case
        // with `inkContour: 0`: 297. With the contour AND the rim gone, which
        // is round 5's type exactly: 275. The floor is 40 -- five times the
        // shipped worst case and a seventh of either mutant.
        verify(worst.within2 <= 40,
               label + ": " + worst.within2 + " cream pixels of the type come"
               + " within two pixels of the sun's disc, and the floor is 40."
               + " The shipping build reads 4 to 7; deleting the contour reads"
               + " 297, and round 5's shadow-only type 275")
        for (var v = 0; v < tones.length; v++) {
          // Zero contacts against a tone that is not being painted proves
          // nothing, so the tone has to be on the screen first.
          verify(worst.present[v] > 400,
                 label + ": only " + worst.present[v] + " pixels of " + tones[v].name
                 + " are on the screen at all, so a count of contacts against it"
                 + " would mean nothing")
          compare(worst.touching[v], 0,
                  label + ": " + worst.touching[v] + " cream pixels of the type border "
                  + tones[v].name + worst.firstAt[v])
        }
      }
      countdown.beat = 0
    }

    // THE PICTURE. The other half of the claim `ui/Countdown.qml` makes about
    // the big type: not just that it clears the sun, but that it is LIT from
    // where the plan says the light is -- "one key, the sun, low and
    // behind-right of the subject. Every object has a warm rim on its sun
    // side." Round 5's type had a cast shadow and nothing else, which is why
    // the fact survived on the disc by one trick thrown the wrong way.
    //
    // This exists because the mutation said it had to. Setting `inkRimOffset`
    // to 0 -- deleting the warm rim outright -- left every other case in this
    // file green, so the round would have shipped a paragraph about the light
    // rule with nothing behind it. Every rim pixel that borders the type's
    // cream is counted and sorted by which side of the glyph it is on: cream
    // below or to its left means the rim pixel is up and to the right, on the
    // sun side. Measured on the shipped frames, 246 sun-side against 6 at
    // 1920 x 1080 beat 3 and 418 against 6 on GO.
    //
    // A SINGLE GRAB IS NOT A MEASUREMENT HERE, and the first draft of this case
    // was one. The numeral pulses, and counting pixels of an exact tone on a
    // glyph being scaled mid-animation is a coin toss: ten consecutive grabs at
    // 1920 x 1080 on beat 1 gave 425, 93, 425, 425, 425, 425, 425, 425, 425,
    // 425 -- and at 2560 x 1440 on beat 1, one of the ten was 0. Half a
    // resampled 3-pixel band matches no exact tone at all. The draft passed on
    // this Mac and would have failed on someone else's for no reason but phase.
    //
    // So six grabs are taken across a fifth of a second and the BEST is the
    // measurement, which is the honest statistic for "the rim is there": a rim
    // that has been deleted is zero on all six, and was, when the mutation
    // `inkRimOffset: 0` was run against this case. The shadow-side count is the
    // one from the same frame as the best, so the pair is one photograph.
    function test_08b_the_big_type_carries_its_rim_on_the_sun_side() {
      var rim = countdown.inkRim
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        for (var b = 0; b < 4; b++) {
          tc.holdTheBeat(b)
          tc.wait(b === 3 ? 300 : 30)
          var word = countdown.beatWord
          var bestSun = 0
          var itsShadow = 0
          for (var f = 0; f < 6; f++) {
            if (f > 0)
              tc.wait(37)
            var img = grabImage(countdown)
            var y1 = Math.round(countdown.gantryBoardTopY)
            var sunSide = 0
            var shadowSide = 0
            for (var y = 1; y < y1; y++) {
              for (var x = 1; x < root.width - 1; x++) {
                if (!tc.isTone(img, x, y, rim, 12))
                  continue
                var lit = tc.isTone(img, x, y + 1, Theme.cream, 12)
                       || tc.isTone(img, x - 1, y, Theme.cream, 12)
                var dark = tc.isTone(img, x, y - 1, Theme.cream, 12)
                        || tc.isTone(img, x + 1, y, Theme.cream, 12)
                if (lit && !dark)
                  sunSide += 1
                else if (dark && !lit)
                  shadowSide += 1
              }
            }
            if (sunSide > bestSun) {
              bestSun = sunSide
              itsShadow = shadowSide
            }
          }
          var label = tc.sizes[s].w + "x" + tc.sizes[s].h + " beat " + word
          verify(bestSun > 100,
                 label + ": the best of six frames carries only " + bestSun
                 + " warm rim pixels on the type's sun side; the plan gives every"
                 + " object in this scene a warm rim there")
          verify(itsShadow * 8 < bestSun,
                 label + ": on that frame " + itsShadow + " rim pixels are on the"
                 + " SHADOW side against " + bestSun + " on the sun side -- the"
                 + " light has no single direction")
        }
      }
      countdown.beat = 0
    }

    // ------------------------------------------------- the run, with real keys
    //
    // The ticker, sped up, and every keystroke below is a real key event.
    function test_09_the_go_beat_takes_the_keys_and_hands_them_on() {
      countdown.beatMs = 40
      countdown.visible = false
      countdown.visible = true
      countdown.forceActiveFocus()
      root.finishes = 0
      root.aborts = 0
      // Wait for GO, and not past the beat that ends it.
      tryCompare(countdown, "go", true, 2000)
      keyClick(Qt.Key_7)
      keyClick(Qt.Key_2)
      keyClick(Qt.Key_Backspace)
      keyClick(Qt.Key_9)
      compare(countdown.typedAhead.length, 2, "two digits stand after the backspace")
      compare(countdown.typedAhead[0], 7)
      compare(countdown.typedAhead[1], 9)
      tryCompare(root, "finishes", 1, 2000)
      compare(countdown.typedAhead.length, 2,
              "and they are still there for the race to take when finished() fires")
      countdown.beatMs = 1000
    }

    function test_10_escape_goes_back_from_every_beat() {
      countdown.beatMs = 1000
      for (var b = 0; b < 4; b++) {
        countdown.visible = false
        countdown.visible = true
        countdown.beat = b
        countdown.forceActiveFocus()
        root.aborts = 0
        verify(countdown.activeFocus, "the countdown holds the keyboard")
        keyClick(Qt.Key_Escape)
        compare(root.aborts, 1, "Escape on beat " + countdown.beatWord + " goes back once")
      }
      countdown.beat = 0
    }

    // Nothing is typed before GO. The footer says GET READY and the screen
    // means it, which is the round-2 finding this file keeps.
    function test_11_nothing_is_typed_before_go() {
      countdown.visible = false
      countdown.visible = true
      countdown.beat = 0
      countdown.forceActiveFocus()
      keyClick(Qt.Key_5)
      keyClick(Qt.Key_6)
      compare(countdown.typedAhead.length, 0, "the counted beats take no digits")
      countdown.beat = 3
      keyClick(Qt.Key_5)
      compare(countdown.typedAhead.length, 1, "and GO does")
      countdown.beat = 0
    }

    // The fact behind GO is the deck's, not a sample. The same call the screen
    // makes, made here, must name the same fact.
    function test_12_the_fact_behind_go_is_the_first_of_the_deck() {
      var deck = Engine.lapDeck(countdown.seed, 0, countdown.firstTable)
      verify(deck.length > 0)
      compare(countdown.factText, Engine.factLabel(deck[0]),
              "the fact drawn behind GO is the question the race asks first")
    }
  }
}
