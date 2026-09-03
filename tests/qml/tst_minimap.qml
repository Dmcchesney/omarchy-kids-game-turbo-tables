import QtQuick
import QtTest
import qs.Commons
import "../../ui"

// The minimap has to draw the race the engine is running.
//
// Round two threaded the engine's order into `TrackView.setProgress` and not
// into `Minimap.setProgress`, and nothing caught it, because every test and
// every self-report measured the values that went IN. Measured on the laid-out
// dots instead, the map contradicted `Engine.raceOrder` on 55.0% of frames on
// seed 42, 30.3% on seed 3 and 9.7% on seed 11 over thirty seconds each, while
// the track view and the callouts were correct on all three.
//
// So every case below asserts `drawnT` -- the parameter a dot is DRAWN at,
// after the projection, the tie-break and the de-collision -- or the pixel
// distance between two drawn points. None of them asserts an input.
//
// Run it:
//   qmltestrunner -input tests/qml -import ui -import dev/imports
Item {
  id: root
  width: 400
  height: 300

  // Four racers in a fixed list order. The engine's order is a separate thing
  // and is passed per frame, which is the whole point.
  readonly property var field: [
    { "progress": 0.0, "color": "#e0483a", "number": 7,  "isHuman": true },
    { "progress": 0.0, "color": "#f2c93c", "number": 21, "isHuman": false },
    { "progress": 0.0, "color": "#3f7fe0", "number": 34, "isHuman": false },
    { "progress": 0.0, "color": "#6dc94a", "number": 55, "isHuman": false }
  ]

  Minimap {
    id: map
    width: 260
    height: 170
    dotSize: 18
  }

  // A second one at the size a 1366x768 window asks for, which is where the
  // dots were clipping.
  Minimap {
    id: small
    width: 202
    height: 116
    dotSize: 12
  }

  function separation(m, a, b) {
    var pa = m.pointAt(m.drawnT(a))
    var pb = m.pointAt(m.drawnT(b))
    return Math.sqrt((pa.x - pb.x) * (pa.x - pb.x) + (pa.y - pb.y) * (pa.y - pb.y))
  }

  function tightest(m, n) {
    var worst = Number.POSITIVE_INFINITY
    for (var a = 0; a < n; a++)
      for (var b = a + 1; b < n; b++)
        worst = Math.min(worst, separation(m, a, b))
    return worst
  }

  TestCase {
    name: "Minimap"
    when: windowShown

    function init() {
      map.setRacers(root.field)
      small.setRacers(root.field)
    }

    // ------------------------------------------------------------ the order
    function test_order_from_the_engine_wins_over_the_smoothed_values() {
      // The smoothed copy has BOLT (index 1) in front of the child (index 0),
      // which is what a lagging smooth looks like just after the child passes.
      // The engine says the child is in front.
      var values = [0.40, 0.44, 0.30, 0.20]
      var order = [0, 1, 2, 3]        // you, bolt, piston, gasket
      map.setProgress(values, order)
      verify(map.drawnT(0) > map.drawnT(1),
             "the child must be drawn in front of BOLT: you=" + map.drawnT(0)
             + " bolt=" + map.drawnT(1))
      verify(map.drawnT(1) > map.drawnT(2))
      verify(map.drawnT(2) > map.drawnT(3))
    }

    function test_without_an_order_the_old_behaviour_is_unchanged() {
      var values = [0.40, 0.44, 0.30, 0.20]
      map.setProgress(values)
      verify(map.drawnT(1) > map.drawnT(0),
             "with no order the smoothed values still decide")
    }

    // The projection makes the capped racer EQUAL to the one in front, and
    // equal values are exactly what the de-collision has to break apart. Break
    // them apart in list order and the map still contradicts the engine --
    // which it did on 31.8% of frames on seed 42 when only the projection had
    // been added.
    function test_ties_are_broken_by_the_engine_and_not_by_the_list() {
      var values = [0.30, 0.30, 0.30, 0.30]
      map.setProgress(values, [3, 2, 1, 0])   // gasket, piston, bolt, you
      verify(map.drawnT(3) > map.drawnT(2), "gasket leads")
      verify(map.drawnT(2) > map.drawnT(1), "piston second")
      verify(map.drawnT(1) > map.drawnT(0), "bolt third, the child last")
    }

    function test_every_order_is_drawn_in_that_order() {
      var orders = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2], [2, 0, 3, 1]]
      for (var k = 0; k < orders.length; k++) {
        var o = orders[k]
        map.setProgress([0.51, 0.50, 0.52, 0.49], o)
        for (var i = 1; i < o.length; i++)
          verify(map.drawnT(o[i - 1]) > map.drawnT(o[i]),
                 "order " + JSON.stringify(o) + ": " + o[i - 1] + " must lead " + o[i])
      }
    }

    // ------------------------------------------------------- de-collision
    // Every racer starts on the start line, so every dot starts at the same
    // place. Round two clamped each spread dot onto the loop separately, which
    // put two or three of them on the same pixel: measured on the laid-out
    // dots, the closest pair was 0.0 px apart on 1250 of 1250 frames of a
    // twenty-second run at both window sizes.
    function test_the_start_line_does_not_stack_the_field() {
      map.setProgress([0, 0, 0, 0], [0, 1, 2, 3])
      var gap = tightest(map, 4)
      verify(gap >= map.dotPx,
             "dots must be at least one dot apart at the start: " + gap
             + " px against a " + map.dotPx + " px dot")
    }

    function test_the_finish_line_does_not_stack_the_field() {
      map.setProgress([1, 1, 1, 1], [0, 1, 2, 3])
      var gap = tightest(map, 4)
      verify(gap >= map.dotPx, "same at the far end of the loop: " + gap)
    }

    // The loop is a kidney and `pointAt` is nowhere near arc-length
    // parameterised, so a separation measured in `t` is not a separation in
    // pixels. This walks the whole loop and asserts the gap in PIXELS.
    function test_separation_holds_everywhere_on_the_loop() {
      for (var s = 0; s < 40; s++) {
        var at = s / 40
        map.setProgress([at, at, at, at], [0, 1, 2, 3])
        var gap = tightest(map, 4)
        verify(gap >= map.dotPx * 0.92,
               "bunched at t=" + at.toFixed(3) + ": closest pair " + gap.toFixed(1)
               + " px against a " + map.dotPx + " px dot")
      }
    }

    // ------------------------------------------------------- the small panel
    function test_the_dot_has_a_floor_and_the_loop_gives_way() {
      compare(small.dotPx, 16, "a 12 px dot is floored to 16")
      verify(small.padX >= 16 * 0.9, "the padding follows the floored dot")
    }

    function test_the_small_panel_does_not_clip_a_dot() {
      for (var s = 0; s < 40; s++) {
        var at = s / 40
        small.setProgress([at, at, at, at], [0, 1, 2, 3])
        var gap = tightest(small, 4)
        verify(gap >= small.dotPx * 0.92,
               "1366x768 panel, t=" + at.toFixed(3) + ": closest pair "
               + gap.toFixed(1) + " px against a " + small.dotPx + " px dot")
      }
    }

    // ------------------------------------------------------------ the tarmac
    // Round two's `panelRaised` loop measured 1.07:1 against its own panel.
    function test_the_loop_is_visible_against_the_panel() {
      compare(ratio(map.trackColor, map.panelColor) >= 3.0, true,
              "the tarmac must clear 3:1 against the panel, measured "
              + ratio(map.trackColor, map.panelColor).toFixed(2) + ":1")
    }

    function channel(c) {
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }
    function luminance(col) {
      return 0.2126 * channel(col.r) + 0.7152 * channel(col.g)
             + 0.0722 * channel(col.b)
    }
    function ratio(a, b) {
      var la = luminance(a)
      var lb = luminance(b)
      return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
  }
}
