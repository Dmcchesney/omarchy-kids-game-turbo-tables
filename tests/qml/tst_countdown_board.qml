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
// ================================================== ROUND 3: ONE RENDERER
//
// The countdown is `ui/TrackView.qml` held still at `Circuit.START_TRAVEL`
// now -- the camera the race opens on -- so the sky, the ground, the road, the
// roadside and the arch are the race's own and not a second painting of them.
// Three things follow for this file, and each is written beside the case it
// changed:
//
//   * clearing the board is HORIZONTAL. That camera's horizon is 40.3% of the
//     frame and an arch stands on the road, so no travel puts the board low
//     enough for a huge numeral to hang above it; the numeral stands in the sky
//     to the left of the arch instead, and `test_01` measures the gap;
//   * the sun-banding case is gone. It was a sky test on a screen that painted
//     its own sky, and the sky belongs to `SunsetSky` and `TrackView` now. What
//     stands in its place is the claim only this screen can make -- that the
//     place it shows is the place the race opens on -- measured by
//     `tst_race_start.qml`'s own chequer reading, run against this frame;
//   * the fact does not stand on the sun any more. It stands where
//     `ui/Race.qml` draws it, on the arch's crossbar, with the race's own
//     `factGround` plate under it, and `test_08` reads that off the picture.
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

    // THE DEFECT, GUARDED -- AND ROUND 3 CHANGED WHAT CLEARING IT MEANS.
    //
    // The countdown is `ui/TrackView.qml` held still at `Circuit.START_TRAVEL`
    // now, which is the camera the race opens on, and that camera decides where
    // the arch can be: its horizon is 40.3% of the frame and an arch stands on
    // the road, so the board can never be lower in the frame than the horizon.
    // At the start line the board's top edge is at 25.1% of the frame; a numeral
    // hung between a 4.5% ceiling and a 3% clearance above it can be at most
    // 20.1% of the frame in ink, which is smaller than the GO word already was.
    //
    // So the numeral does not clear the board VERTICALLY any more. It stands in
    // the sky to the LEFT of the whole arch, and the clearance this case asserts
    // is horizontal and is the width of the arch rather than three per cent of
    // the frame. The arch's own drawn box is what bounds it -- flags included,
    // because the flags are art too -- so it is bounded by the picture and not
    // by a fraction somebody chose.
    //
    // Measured on the shipped frames, the gap from the numeral's rightmost cream
    // pixel to the arch's opaque box -- which is the flags' own edge and not the
    // transparent margin of the cell they are baked in:
    //
    //                  `3`     `1`      GO
    //   1024 x  600   112 px  100 px   42 px
    //   1366 x  768   156 px  141 px   57 px
    //   1920 x 1080   225 px  204 px   86 px
    //
    // GO is the tight one at every size because it is two glyphs wide, and it is
    // the one fitted by the column's width rather than by the sky's height.
    function test_01_the_numeral_never_crosses_the_arch() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        for (var b = 0; b < 4; b++) {
          countdown.beat = b
          var label = tc.sizes[s].w + "x" + tc.sizes[s].h + " beat " + countdown.beatWord
          verify(countdown.gantryRightX - countdown.gantryLeftX > 40,
                 label + ": the arch is on the screen and is "
                 + Math.round(countdown.gantryRightX - countdown.gantryLeftX)
                 + " px across, so a clearance measured against it means something")
          verify(countdown.beatInkRightX <= countdown.gantryLeftX,
                 label + ": the numeral's widest cream, at the top of its pulse,"
                 + " ends at " + Math.round(countdown.beatInkRightX)
                 + " and the arch's box begins at "
                 + Math.round(countdown.gantryLeftX))
          verify(countdown.beatInkLeftX >= 0,
                 label + ": the numeral is not clipped by the left of the frame,"
                 + " ink left " + Math.round(countdown.beatInkLeftX))
          verify(countdown.beatInkTopY >= 0,
                 label + ": the numeral is not clipped by the top of the frame, ink top "
                 + Math.round(countdown.beatInkTopY))
          // The plan's line is "the number huge in cream over the SKY", and the
          // horizon is where the sky stops. Below it the numeral would be
          // standing on the crowd and the tyre walls.
          verify(countdown.beatInkBottomAtPulse + countdown.beatShadowDrop
                 <= countdown.horizonY,
                 label + ": the numeral's ink and its shadow end at "
                 + Math.round(countdown.beatInkBottomAtPulse + countdown.beatShadowDrop)
                 + " and the camera's horizon is at "
                 + Math.round(countdown.horizonY))
        }
      }
      countdown.beat = 0
    }

    // Design, Race format: "the first fact readable behind GO". Readable means
    // clear of the only other words in the picture -- and the fact is now drawn
    // where `ui/Race.qml` draws it, so this is also the guard on the claim that
    // the fact does not move across the cut: it clears the board's top edge
    // there for the same reason and by the same arithmetic.
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
        // The two words on the GO beat stand in two different parts of the
        // frame now -- GO in the sky column, the fact in the middle -- so what
        // has to hold is that they do not overlap each other.
        verify(countdown.beatInkRightX <= countdown.factInkRect.x,
               label + ": GO's cream ends at " + Math.round(countdown.beatInkRightX)
               + " and the fact's ink begins at " + Math.round(countdown.factInkRect.x))
      }
      countdown.beat = 0
    }

    // Clearing the board is worth nothing if it were bought by shrinking the
    // numeral into the chrome. Two floors, both from the documents: the plan
    // calls the number "huge", and the design's accessibility section fixes the
    // fact at "never smaller than a tenth of the screen height".
    //
    // THE NUMERAL'S FLOOR MOVED AGAIN IN ROUND 3, AND IT IS THE CAMERA THAT
    // MOVED IT. Lowering a guard is the cheapest way to make a suite lie, so
    // what moved it is written here rather than in a commit message.
    //
    // The floor was 0.29 against a shipped 33.6%, on a screen whose own horizon
    // was at 57.4% of the frame -- 57.4% of sky to hang a numeral in. The
    // countdown is the race's own view now, and that camera's horizon is 40.3%.
    // A numeral standing in the sky can therefore be at most about 0.36 of the
    // frame before its shadow crosses the skyline, and it is fitted to the
    // narrower of that band and the sky column left of the arch.
    //
    // Measured on the shipped frames, the numeral's cream, above the horizon and
    // left of the arch:
    //
    //                  `3`      `2`      `1`      GO
    //   1024 x  600   26.7 %   28.2 %   29.5 %   26.8 %
    //   1366 x  768   26.8 %   28.3 %   29.6 %   28.9 %
    //   1920 x 1080   26.7 %   28.3 %   29.4 %   28.8 %
    //
    // Two things in that table are the point of the round. The build is intact
    // -- each counted beat is larger than the one before it -- and GO IS NO
    // LONGER THE QUIETEST FRAME OF THE FOUR: it was 15.1% of the frame in ink
    // before round 2 and 21.7% after it, and it is 28.8% here, within half a
    // point of the `1` that precedes it, because the fact no longer has to fit
    // underneath it.
    //
    // TWO FLOORS, AND THE SECOND ONE IS ABOUT THE FACE. The counted beats are
    // one glyph and are fitted by the SKY's height; GO is two and is fitted by
    // the COLUMN's width, so how wide the shell's face lays `GO` out decides how
    // tall it can be. The table above is Menlo, which is what this Mac hands
    // down and what the shipped frames are shot in. This runner gets the
    // fallback family (`Theme.fontFamily` is "monospace", which this Mac does
    // not have), which lays the same two letters out wider: GO measures 22.9% of
    // the frame here at 1366 x 768 against 28.9% on the shipped frame. Both are
    // over round 2's 21.7%, which is the number this had to keep. So the counted
    // beats are floored at 0.25 and GO at 0.20, and the gap between the two
    // floors is a face, not a slack.
    function test_03_the_type_is_still_the_size_the_documents_ask_for() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        var last = 0
        for (var b = 0; b < 4; b++) {
          countdown.beat = b
          var ink = countdown.beatInkBottomY - countdown.beatInkTopY
          var floor = (b === 3) ? 0.20 : 0.25
          verify(ink >= root.height * floor,
                 label + " beat " + countdown.beatWord + ": the numeral's ink is "
                 + Math.round(ink) + " px, which is "
                 + (100 * ink / root.height).toFixed(1) + "% of the frame, and the"
                 + " floor is " + (100 * floor).toFixed(0) + "%")
          // The beats build. `1` is the tallest of the three counted beats and
          // each one before it is smaller, which is the thing that made three
          // seconds of one frozen picture into three different ones.
          if (b > 0 && b < 3)
            verify(ink > last,
                   label + " beat " + countdown.beatWord + ": " + Math.round(ink)
                   + " px of ink against " + Math.round(last) + " on the beat before"
                   + " it -- a countdown builds")
          last = ink
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
    // it only asserted that the board had a position.
    //
    // THE BOARD IS NOT PAINTED HERE ANY MORE. It is the header plate of the
    // prop kit's `gantry`, baked once with `TURBO TABLES` on it, and this
    // screen places, scales and tints that sprite. So the two tones to count
    // are not the two the scene declares -- the scene declares the tones the
    // BAKE carries, and by the time a pixel reaches the frame the kit's light
    // rule has been over it: `Circuit.TINT`'s gantry row washes the sprite with
    // `#7d1a5e` at 0.40 and lights its sun edge with `#f0b07a` at 0.54, which
    // takes `#f5a524` on `#1a1b26` to `#c66e3b` on `#421a3c`.
    //
    // Hard-coding that pair here would be hard-coding the output of somebody
    // else's light rule, which is a number that drifts the moment the hour or
    // the tint table moves. So the pair is READ OFF THE FRAME: the most common
    // tone inside the plate's rect is the plate, the second most common is the
    // type, and every claim below is about those two. Blank the board and the
    // second tone is a stray, its column count collapses, and four checks die.
    function boardTones(img, x0, y0, x1, y1) {
      // A coarse histogram: 5 bits per channel is 32,768 buckets, which is more
      // than enough to keep a plate and its type apart and few enough to gather
      // the bake's own dither back into one bucket.
      var hist = {}
      for (var x = x0; x < x1; x++) {
        for (var y = y0; y < y1; y++) {
          var k = ((img.red(x, y) >> 3) << 10) | ((img.green(x, y) >> 3) << 5)
                  | (img.blue(x, y) >> 3)
          hist[k] = (hist[k] || 0) + 1
        }
      }
      // The bucket's CENTRE, not its floor: a five-bit bucket spans eight
      // values, so the floor can be seven away from every pixel in it and a
      // count taken at a tolerance of six then finds none of them. That is
      // exactly what happened to `test_05` when the arch came closer and the
      // board's plate spread across more buckets: it reported "fill 0" of a
      // plate that fills two thirds of the board.
      function unpack(k) {
        return Qt.rgba((((k >> 10) & 31) * 8 + 4) / 255, ((((k >> 5) & 31) * 8) + 4) / 255,
                       (((k & 31) * 8) + 4) / 255, 1)
      }
      var best = -1, bn = 0
      for (var key in hist) {
        if (hist[key] > bn) { best = parseInt(key, 10); bn = hist[key] }
      }
      // THE INK IS THE COMMONEST TONE THAT IS A DIFFERENT COLOUR FROM THE
      // PLATE, and not simply the second commonest. The board is drawn much
      // larger now that the arch stands where the race stands -- 394 x 63 px at
      // 1920 x 1080 against 189 x 30 before -- so the plate's own dither spills
      // into neighbouring buckets and the second commonest bucket was another
      // shade of plate. A contrast claim is a claim about two DIFFERENT
      // colours, so that is what is picked.
      var fill = unpack(best)
      var second = -1, sn = 0
      for (var k2 in hist) {
        var c = unpack(parseInt(k2, 10))
        var apart = Math.abs(c.r - fill.r) + Math.abs(c.g - fill.g) + Math.abs(c.b - fill.b)
        if (apart > 0.35 && hist[k2] > sn) { second = parseInt(k2, 10); sn = hist[k2] }
      }
      return { "fill": fill, "fillCount": bn,
               "ink": second >= 0 ? unpack(second) : fill, "inkCount": sn }
    }

    function test_04_the_board_carries_the_words_it_is_cleared_for() {
      tc.holdTheBeat(0)
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        tc.wait(40)
        var img = grabImage(countdown)
        // The plate's own rect, from the scene that stands the arch. Two rows
        // in from the top edge, which is the plate's warm rim line.
        var x0 = Math.round(countdown.gantryBoardLeftX)
        var x1 = Math.round(countdown.gantryBoardRightX)
        var y0 = Math.round(countdown.gantryBoardTopY) + 2
        var y1 = Math.round(countdown.gantryBoardBottomY)
        verify(x1 - x0 > 40 && y1 - y0 > 4,
               label + ": the board's rect is " + (x1 - x0) + "x" + (y1 - y0))

        var pair = tc.boardTones(img, x0, y0, x1, y1)
        var ink = tc.countTone(img, x0, y0, x1, y1, pair.ink, 10)
        var fill = tc.countTone(img, x0, y0, x1, y1, pair.fill, 10)
        verify(ink.count > 120,
               label + ": the board carries " + ink.count + " pixels of type"
               + " against its plate; a blank board carries none")
        verify(ink.columns >= 20,
               label + ": the ink stands in " + ink.columns + " separate columns"
               + " of the board -- twelve characters, not one block")
        verify(fill.count > ink.count,
               label + ": the board is still mostly board -- " + fill.count
               + " pixels of plate against " + ink.count + " of type")
        // And the words are where the words go: inside the middle of the board,
        // not crowded against one end.
        var mid = tc.countTone(img, Math.round(x0 + (x1 - x0) * 0.4),
                               y0, Math.round(x0 + (x1 - x0) * 0.6), y1,
                               pair.ink, 10)
        verify(mid.count > 0, label + ": there is type across the middle of the board")
        // Neither of the board's two tones may be cream, or `test_06`'s count of
        // cream inside the board is measuring the board and not the numeral.
        verify(!tc.isTone3(pair.ink, Theme.cream, 14)
               && !tc.isTone3(pair.fill, Theme.cream, 14),
               label + ": the board's own tones are not cream, so a cream count"
               + " inside it is a count of the type above")
      }
    }

    // Is this colour that colour, within `tol` per channel on 0..255?
    function isTone3(a, b, tol) {
      return Math.abs(a.r * 255 - b.r * 255) <= tol
          && Math.abs(a.g * 255 - b.g * 255) <= tol
          && Math.abs(a.b * 255 - b.b * 255) <= tol
    }

    function channelLin(v) {
      var f = v / 255.0
      return f <= 0.04045 ? f / 12.92 : Math.pow((f + 0.055) / 1.055, 2.4)
    }
    function luminanceOf(c) {
      return 0.2126 * tc.channelLin(c.r * 255) + 0.7152 * tc.channelLin(c.g * 255)
           + 0.0722 * tc.channelLin(c.b * 255)
    }
    function contrastOf(a, b) {
      var la = tc.luminanceOf(a)
      var lb = tc.luminanceOf(b)
      return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }

    // THE PICTURE, AND A FINDING THAT IS NOT THIS SCREEN'S TO FIX.
    //
    // Round 6 raised this board from 3.62:1 to 5.83:1 by choosing its two
    // colours, and the kit's bake does better still: `#f5a524` on `#1a1b26` is
    // 8.37:1 straight off the sheet, and the first half of this case asserts
    // that, because it is the number the FROZEN ART carries and it should not
    // be allowed to rot.
    //
    // What lands on the frame is 3.91:1. The circuit's light rule washes every
    // neutral-ramp prop with `#7d1a5e` at 0.40 -- the gantry, the rock walls,
    // the overpass, the roller door -- and a wash that dark over an 8:1 pair
    // closes it. This screen inherits that because it now draws the arch the
    // race draws; measured on `ui/TrackView.qml`'s own frame at travel 0, the
    // race's board reads `#c66e3b` on `#421b3d` at 3.91:1, which is the same
    // number to two decimal places. It is `ui/parts/Circuit.js`'s `TINT` table
    // and `ui/TrackView.qml`'s wash that decide it, and both belong to other
    // pieces, so this case records the measurement and holds the AA floor for
    // LARGE text (3.0:1) rather than quietly tinting one gantry differently
    // from every other one in the game. The report says so in as many words.
    function test_05_the_boards_words_clear_the_contrast_floor() {
      // The bake's own pair, before any light lands on it.
      var baked = tc.contrastOf(countdown.gantryBoardInk, countdown.gantryBoardFill)
      verify(baked >= 4.5,
             "the kit bakes the board at " + baked.toFixed(2) + ":1, and WCAG AA"
             + " for normal text is 4.5:1")

      tc.holdTheBeat(0)
      tc.sizeTo(1920, 1080)
      tc.wait(40)
      var img = grabImage(countdown)
      var x0 = Math.round(countdown.gantryBoardLeftX)
      var x1 = Math.round(countdown.gantryBoardRightX)
      var y0 = Math.round(countdown.gantryBoardTopY) + 2
      var y1 = Math.round(countdown.gantryBoardBottomY)
      var pair = tc.boardTones(img, x0, y0, x1, y1)
      var ink = tc.countTone(img, x0, y0, x1, y1, pair.ink, 6)
      var fill = tc.countTone(img, x0, y0, x1, y1, pair.fill, 6)
      verify(ink.count > 120 && fill.count > 120,
             "both of the board's colours are on the screen: ink " + ink.count
             + ", fill " + fill.count)
      var ratio = tc.contrastOf(pair.ink, pair.fill)
      verify(ratio >= 3.0,
             "on the frame, after the circuit's own wash, the board's type on"
             + " its plate is " + ratio.toFixed(2) + ":1. WCAG AA for large text"
             + " is 3.0:1; for normal text it is 4.5:1, and the bake clears that"
             + " at " + baked.toFixed(2) + ":1 before the wash. The race's own"
             + " gantry measures 3.91:1 on the same pair.")
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
    //
    // THE WINDOW IS THE BOARD AND NOT THE BOARD'S ROWS, and round 3 had to move
    // it. It used to run the full width of the frame at the board's rows, which
    // was sound while nothing else in the picture was up there: the countdown
    // painted its own thin gantry on an empty plain. The countdown is the
    // race's own frame now, and the board's rows cross the arch's BEAM, whose
    // chequers are cream by the bake -- 4,160 of them at 1366 x 768. Counting
    // those would be counting the frozen art and calling it the type.
    //
    // So the window is the plate itself, which is where the claim lives: inside
    // cell x 405..1058 the bake carries zero cream, 5,236 pixels of amber ink in
    // 336 columns and 56,051 of plate (`ui/Countdown.qml`, `boardBox*`). Any
    // cream in there is the type over the board, which is the defect.
    function creamInsideTheBoard(img) {
      return tc.countTone(img, Math.round(countdown.gantryBoardLeftX),
                          Math.round(countdown.gantryBoardTopY),
                          Math.round(countdown.gantryBoardRightX),
                          Math.round(countdown.gantryBoardBottomY),
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
      //
      // THE PULSE IS ON THE BEAT NOW, so this no longer has to shorten `beatMs`
      // and hope the grabs land somewhere useful. The surge starts when the beat
      // changes and runs 260 ms; setting a beat and grabbing straight away walks
      // it from its widest to its rest, deterministically, on any machine.
      tc.holdTheBeat(2)
      tc.wait(30)
      countdown.beat = 0             // a beat change, so a surge from the top
      var worst = 0
      var frames = 0
      for (var t = 0; t < 10; t++) {
        worst = Math.max(worst, tc.creamInsideTheBoard(grabImage(countdown)))
        frames += 1
        tc.wait(30)
      }
      countdown.done = false
      compare(worst, 0, "across " + frames + " frames of the beat pulse the worst"
              + " cream count inside the board was " + worst)
    }
    // THE PICTURE. THE COUNTDOWN IS STANDING ON THE CIRCUIT'S START GRID.
    //
    // What this replaces, and why. The case that stood here walked down the
    // sun's centre column counting the cut lines that band the disc. It was a
    // sky test on a screen that painted its own sky, and it was already half
    // obsolete when round 2 gave the two screens one `SunsetSky`. Round 3
    // finishes that: the sky, the ground, the road and the roadside are all
    // `ui/TrackView.qml`'s now, and `tests/qml/tst_trackview_road.qml` and
    // `tests/qml/tst_race_start.qml` are where the picture that renderer draws
    // is guarded. Keeping a copy of it here would be this file holding a second
    // opinion about somebody else's frame, which is the shape of the defect the
    // whole round is about.
    //
    // What belongs here instead is the claim this screen makes and no other
    // file can check: THAT THE PLACE THE COUNTDOWN SHOWS IS THE PLACE THE RACE
    // OPENS ON. The measurement is `tst_race_start.qml`'s own, run against this
    // screen's frame -- the fraction of the road ahead of the field that is
    // cream, and how many times a scanline crosses it. The start grid is six
    // columns by four rows of chequer and fills the road; the rock quarry a
    // race used to open in measures 2.3% of the same band and alternates twice.
    // If this screen were painting a road of its own again, or standing
    // anywhere but the line, this is the case that would die.
    function isLight(img, x, y) {
      // The chequer's cream squares as the hour's tint leaves them at lap 1,
      // and nothing else on this road: the tarmac reads about (26, 11, 22) and
      // the floor's grid about (60, 18, 40).
      return img.red(x, y) > 150 && img.green(x, y) > 130 && img.blue(x, y) > 95
    }

    function test_07_the_countdown_stands_on_the_circuits_start_grid() {
      tc.holdTheBeat(0)
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        tc.wait(40)
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        var img = grabImage(countdown)
        var x0 = Math.round(root.width * 0.38)
        var x1 = Math.round(root.width * 0.64)
        var y0 = Math.round(root.height * 0.50)
        var y1 = Math.round(root.height * 0.64)
        var lit = 0
        var best = 0
        for (var y = y0; y < y1; y++) {
          var last = -1
          var alt = 0
          for (var x = x0; x < x1; x++) {
            var on = tc.isLight(img, x, y) ? 1 : 0
            lit += on
            if (last >= 0 && on !== last)
              alt += 1
            last = on
          }
          if (alt > best)
            best = alt
        }
        var frac = lit / Math.max(1, (x1 - x0) * (y1 - y0))
        verify(frac >= 0.07,
               label + ": the road ahead of the field is " + (frac * 100).toFixed(1)
               + "% cream. The start grid measures about 17%; the rock quarry a"
               + " race used to open in measures 2.3%")
        verify(best >= 5,
               label + ": the cream ahead alternates " + best + " times across the"
               + " road, so it is a chequer and not a centre line")
      }
    }

    // THE PICTURE. THE FACT IS READABLE BEHIND GO, AND WHAT MAKES IT READABLE
    // IS THE SAME TWO THINGS THAT MAKE IT READABLE IN THE RACE.
    //
    // What this replaces. The case that stood here counted cream pixels of the
    // fact touching the sun's disc, because on the old composition the fact
    // stood on the sun and cream on `#efcb72` is 1.26:1. It does not stand
    // there any more: the fact is drawn where `ui/Race.qml` draws it -- centred,
    // at `px(118)`, at a tenth of the frame in ink -- and at the start line
    // what it stands on is the sky and the ARCH'S CROSSBAR, whose chequers are
    // cream. That is the same disturbance the race answers with `factGround`,
    // and this screen now answers it with the same plate, driven by the same
    // `TrackView.factYield`.
    //
    // So the two halves of the claim are: the plate is up (because the arch
    // really is behind the fact), and no cream of the fact borders the arch's
    // own cream. Both are read off the frame.
    //
    // The floor on the plate is 0.5 and not 0.86 because `factYield` ramps with
    // how much of the fact's box the crossbar covers; at the start line it is
    // saturated and the plate reads 0.86, and a camera that moved a little
    // would lower it before it made the fact unreadable.
    function test_08_the_fact_is_read_off_the_races_own_ground() {
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        tc.holdTheBeat(3)
        tc.wait(320)              // the fact and its plate fade in over 220 ms
        var label = tc.sizes[s].w + "x" + tc.sizes[s].h
        verify(countdown.factGroundAlpha >= 0.5,
               label + ": the arch's crossbar is behind the fact and the plate"
               + " under it is at " + countdown.factGroundAlpha.toFixed(2)
               + ". `TrackView.factYield` is what decides it, and it is the same"
               + " expression `ui/Race.qml` uses one second later")

        var img = grabImage(countdown)
        // The fact's own ink box, from the screen, grown by two pixels: every
        // cream pixel of the fact is inside it, and what is asked is whether any
        // of them borders a cream pixel that is NOT the fact's -- which at this
        // camera means the arch's chequer.
        var r = countdown.factInkRect
        var x0 = Math.max(1, Math.floor(r.x) - 2)
        var x1 = Math.min(root.width - 1, Math.ceil(r.x + r.width) + 2)
        var y0 = Math.max(1, Math.floor(r.y) - 2)
        var y1 = Math.min(root.height - 1, Math.ceil(r.y + r.height) + 2)
        var creamIn = tc.countTone(img, x0, y0, x1, y1, Theme.cream, 14)
        verify(creamIn.count > 400,
               label + ": only " + creamIn.count + " cream pixels stand in the"
               + " fact's own ink box, so a measurement about them means nothing")
        // The ink's keyline is the body tone, and the claim is that it is
        // unbroken: every cream pixel on the box's own border rows and columns
        // would be a glyph running out of its plate. The plate is 22 px wider
        // than the ink at 1920 x 1080 and the keyline six of those.
        var edge = tc.countTone(img, x0, y0, x1, y0 + 1, Theme.cream, 14).count
                 + tc.countTone(img, x0, y1 - 1, x1, y1, Theme.cream, 14).count
        compare(edge, 0,
                label + ": " + edge + " cream pixels of the fact touch the top or"
                + " bottom row of its own box, which would be a glyph with no"
                + " keyline between it and whatever is behind it")
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
    // THE PHASE IS NO LONGER A LOTTERY. The surge is started by the beat rather
    // than looping alongside it (see `beatGlyph.surge` in `ui/Countdown.qml`),
    // so a case that sets a beat and waits 300 ms is photographing a glyph at
    // rest, on any machine, every time. The proof that this mattered is in this
    // round: with the free-running loop and a heavier backdrop under it, the
    // same six grabs came back with a best of 13 rim pixels at 1920 x 1080 beat
    // 1 where the frame carries hundreds -- the window had drifted into the
    // surge. Three grabs are still taken and the BEST is still the measurement,
    // because a rim that has been deleted is zero on all three and was, when
    // the mutation `inkRimOffset: 0` was run against this case. The shadow-side
    // count is the one from the same frame as the best, so the pair is one
    // photograph.
    // Is there a cream pixel within `reach` steps of (x, y) in direction
    // (dx, dy)? The rim is `rimOffset` pixels wide, so this is how far the
    // face can be from a rim pixel that belongs to the type.
    function creamWithin(img, x, y, dx, dy, reach) {
      for (var k = 1; k <= reach; k++)
        if (tc.isTone(img, x + dx * k, y + dy * k, Theme.cream, 12))
          return true
      return false
    }

    function test_08b_the_big_type_carries_its_rim_on_the_sun_side() {
      var rim = countdown.inkRim
      for (var s = 0; s < tc.sizes.length; s++) {
        tc.sizeTo(tc.sizes[s].w, tc.sizes[s].h)
        for (var b = 0; b < 4; b++) {
          tc.holdTheBeat(b)
          tc.wait(300)              // the surge is 260 ms and the fade is 220
          var word = countdown.beatWord
          var reach = Math.max(1, countdown.inkRimOffset)
          var bestSun = 0
          var itsShadow = 0
          for (var f = 0; f < 3; f++) {
            if (f > 0)
              tc.wait(37)
            var img = grabImage(countdown)
            // LEFT OF THE ARCH, WHICH IS WHERE THE NUMERAL IS AND WHERE THE
            // ARCH IS NOT. The window used to be the rows above the arch's box,
            // because the kit's gantry carries the same warm rim tone on its own
            // sun-facing edges -- it is `Circuit.TINT`'s `keyColor` -- and its
            // flags stand beside cream chequers, which is a rim pixel next to a
            // cream pixel and would be counted as the type's. That window worked
            // while the numeral hung above the arch. It stands beside it now, so
            // most of the numeral was BELOW the old window's floor and the count
            // collapsed to 68 where the frame carries hundreds. Cutting on x
            // instead of y excludes the whole prop rather than most of the type.
            var x1 = Math.round(countdown.gantryLeftX)
            var sunSide = 0
            var shadowSide = 0
            for (var y = 1; y < root.height - 1; y++) {
              for (var x = 1; x < x1; x++) {
                if (!tc.isTone(img, x, y, rim, 12))
                  continue
                // THE REACH IS THE RIM'S OWN WIDTH, AND IT IS NOT SLACK.
                // `LitWord` draws the rim as the word offset up and right by
                // `rimOffset` and then paints the cream face over it, so what
                // shows is a band exactly `rimOffset` pixels wide -- 2 px at
                // 1366 x 768 and 3 px at 1920 x 1080. A one-pixel adjacency
                // test therefore sees only the innermost row of it, and at
                // 1920 x 1080 on the beat `1` it saw NONE: 1,520 rim pixels on
                // the frame, 25,635 cream pixels, and zero pairs. Looking as far
                // as the rim is wide is looking at the whole rim.
                var lit = tc.creamWithin(img, x, y, 0, 1, reach)
                       || tc.creamWithin(img, x, y, -1, 0, reach)
                var dark = tc.creamWithin(img, x, y, 0, -1, reach)
                        || tc.creamWithin(img, x, y, 1, 0, reach)
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
          // THE FLOOR SCALES WITH THE FRAME, because the rim does: it is
          // `rimOffset` pixels wide along the type's up-and-right edges, and
          // both the offset and the edges are fractions of the window. It also
          // depends on the GLYPH -- `2` presents far less up-right edge than `1`
          // or `GO`. Measured on the shipped frames, left of the arch, over the
          // four beats:
          //
          //     1024 x  600     86 /  70 / 157 / 253
          //     1366 x  768    123 /  64 / 190 / 303
          //     1920 x 1080    185 / 230 / 419 / 538
          //
          // The floor is 4% of the frame height -- 31 rows at 768, 43 at 1080 --
          // which is half the worst of those and is not a number a rim can reach
          // by accident: the mutation `inkRimOffset: 0`, which deletes the rim
          // outright, reads 0 on every frame at every size.
          var floor = Math.max(25, root.height * 0.04)
          verify(bestSun > floor,
                 label + ": the best of three frames carries only " + bestSun
                 + " warm rim pixels on the type's sun side, and the floor is "
                 + Math.round(floor) + "; the plan gives every object in this"
                 + " scene a warm rim there. The window scanned was x 1.."
                 + Math.round(countdown.gantryLeftX) + ", the numeral's ink ran x "
                 + Math.round(countdown.beatInkLeftX) + ".."
                 + Math.round(countdown.beatInkRightX) + " and its size was "
                 + countdown.beatPixelSize + " px")
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
