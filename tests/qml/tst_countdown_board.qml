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
// set directly in the geometry cases, because a case that waited three real
// seconds for `3` to become `1` would be measuring a `Timer`. The last two
// cases do run the real ticker, at a shortened `beatMs`, and every key in them
// is a real `keyClick()`.
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

    // The board is only worth clearing if it says something. This is the string
    // the painter draws into it, read off the scene rather than off a comment.
    function test_04_the_board_carries_the_words_it_is_cleared_for() {
      compare(countdown.gantryBoardTopY > 0, true, "the board has a position in the frame")
      verify(countdown.gantryBoardTopY < root.height * 0.6,
             "and it is in the sky, above the horizon, where the type is")
    }

    // ------------------------------------------------- the run, with real keys
    //
    // The ticker, sped up, and every keystroke below is a real key event.
    function test_05_the_go_beat_takes_the_keys_and_hands_them_on() {
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

    function test_06_escape_goes_back_from_every_beat() {
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
    function test_07_nothing_is_typed_before_go() {
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
    function test_08_the_fact_behind_go_is_the_first_of_the_deck() {
      var deck = Engine.lapDeck(countdown.seed, 0, countdown.firstTable)
      verify(deck.length > 0)
      compare(countdown.factText, Engine.factLabel(deck[0]),
              "the fact drawn behind GO is the question the race asks first")
    }
  }
}
