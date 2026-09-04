import QtQuick
import QtTest
import qs.Commons
import "../../ui"

// The three picture rules piece 4 round four added to the road, asserted on
// the view's OWN functions -- the ones the delegates and the shader uniforms
// bind to -- rather than on a second copy of the arithmetic.
//
// Each name is a claim, and each case is written so that undoing the change it
// names makes it fail: put `surfaceFog` back to 1.0 and the far road case
// fails; widen `lanes` back to +-1.34 and the kerb case fails; return
// `archOpacity` to a constant 1 and the arch case fails.
//
// Run it:
//   qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml
Item {
  id: root
  width: 1920
  height: 1080

  TrackView {
    id: view
    anchors.fill: parent
    // A dead straight, so `uAt` is symmetric about the centre and a lane's
    // distance from the road edge is the lane number itself.
    travel: 216
  }

  TestCase {
    name: "TrackViewRoad"
    when: windowShown

    // ------------------------------------------------ every wheel on tarmac
    //
    // Two critics said lane 0 puts a car's wheels on the kerb at the start
    // line. At the start every kart is at `playerZ`, so the test is a world-
    // space one: the outermost lane centre plus half a kart must be inside
    // `roadHalf`. `kartWorldWidth` is the view's own nominal kart width and is
    // about 8% wider than the drawn body, so this is the conservative side.
    function test_every_lane_keeps_a_whole_kart_inside_the_road_edge() {
      for (var seat = 0; seat < 4; seat++) {
        var lane = Math.abs(view.laneOf(seat))
        var outer = lane + view.kartWorldWidth / 2
        verify(outer <= view.roadHalf,
               "seat " + seat + " lane " + lane.toFixed(3)
               + " puts a kart edge at " + outer.toFixed(3)
               + ", outside roadHalf " + view.roadHalf)
      }
    }

    // The hero drifts with the corner, so check it at both extremes of the
    // circuit's curve rather than only on the straight.
    function test_the_hero_lane_stays_inside_the_road_through_every_corner() {
      var worst = 0
      for (var t = 0; t < view.circuitLength; t += 1.0) {
        view.travel = t
        var outer = Math.abs(view.laneOf(0)) + view.kartWorldWidth / 2
        if (outer > worst)
          worst = outer
      }
      view.travel = 216
      verify(worst <= view.roadHalf,
             "the hero reaches " + worst.toFixed(3) + " > roadHalf " + view.roadHalf)
    }

    // -------------------------------------------- the far road stays legible
    //
    // The tarmac must fog slower than the floor, or the two reach the fog's
    // colour together and the road stops existing at the vanishing point --
    // which is what shipped. This asserts the RATIO the two renderers are
    // driven by, and that it leaves the road with real contrast at z = 40.
    function test_the_tarmac_fogs_slower_than_the_floor() {
      verify(view.surfaceFog > 0 && view.surfaceFog < 1,
             "surfaceFog is " + view.surfaceFog)
      var z = 40
      var floor = Math.exp(-z * z * 0.0011)
      var road = Math.exp(-view.surfaceFog * z * z * 0.0011)
      verify(road - floor > 0.15,
             "at z = 40 the road keeps " + road.toFixed(3)
             + " of its own tone and the floor " + floor.toFixed(3)
             + "; the gap is " + (road - floor).toFixed(3))
    }

    // And the distance is the glow, not a deeper dark: the fog colour must be
    // BRIGHTER than the ground it is fading, which `#3a1032` was not.
    function test_the_floor_fades_into_the_glow_and_not_into_a_hole() {
      function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
      verify(luma(view.fogTone) > luma(view.groundTone),
             "fogTone luma " + luma(view.fogTone).toFixed(3)
             + " is not brighter than groundTone " + luma(view.groundTone).toFixed(3))
    }

    // ------------------------------------------- an arch never crosses the fact
    //
    // `factFloorY` is the lowest row the fact's ink reaches. An arch whose top
    // has risen to that line must be drawn at zero, and an arch far enough
    // away that its top is well below it must be drawn in full -- otherwise
    // the fix is "no arches", which is not a fix.
    function test_an_arch_is_gone_before_its_top_reaches_the_fact() {
      view.factFloorY = 274
      var span = 9.4
      var crossed = 0
      var full = 0
      for (var z = 2; z < 160; z += 0.25) {
        var top = view.archTopAt(span, z)
        var op = view.archOpacity(span, z)
        if (top <= view.factFloorY) {
          crossed += 1
          compare(op, 0, "an arch at z = " + z.toFixed(2) + " has its top at y = "
                  + top.toFixed(1) + ", at or above the fact's floor "
                  + view.factFloorY + ", and is drawn at " + op.toFixed(3))
        }
        if (op >= 0.999)
          full += 1
      }
      verify(crossed > 0, "no sampled arch ever reached the fact's floor")
      verify(full > 0, "no sampled arch was ever drawn at full opacity")
      view.factFloorY = 0
    }

    // With no ceiling set -- a bare TrackView in the harness -- nothing fades.
    function test_no_ceiling_means_no_arch_ever_fades() {
      view.factFloorY = 0
      for (var z = 2; z < 60; z += 0.5)
        compare(view.archOpacity(9.4, z), 1,
                "an arch faded at z = " + z.toFixed(2) + " with no ceiling set")
    }
  }
}
