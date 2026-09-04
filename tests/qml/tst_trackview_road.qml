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
// `propOpacity` to a throttle on arches and the arch case fails.
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
    id: tc
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

    // ------------------------------------------------- the arches came back
    //
    // Round four suppressed the two props the design names as landmarks --
    // "the sevens run under the roller door" -- to keep them off the FACT, and
    // in doing so met a criterion the plan did not set while leaving the one it
    // did set (the answer field) unmet. Nothing throttles an arch now, at any
    // depth, and this is what keeps that true.
    function test_no_road_spanning_prop_is_ever_dimmed() {
      for (var z = view.nearDistance; z < view.drawDistance; z += 0.25)
        compare(view.propOpacity(true, view.archSpan, z), 1,
                "a road-spanning prop was dimmed at z = " + z.toFixed(2))
    }

    // ------------------------------------------------ and the field yields
    //
    // The plan's second remedy, measured against the object the plan names.
    // At a travel where a crossbar is over the field's box the yield must be
    // full; at a travel where no arch is anywhere near it, zero. Both are read
    // off the view's own `crossingOver`, which is what `Race.qml` binds the
    // field's face to.
    function test_the_field_yields_exactly_when_a_crossbar_is_over_it() {
      // The answer field's box on a 1920x1080 race screen, read off
      // `dev/Harness.qml --dump-text` rather than assumed.
      var box = Qt.rect(853, 345, 214, 98)
      var yielded = 0
      var clear = 0
      var worstCoveredWhileClear = 0
      var worstCoveredWhileNotFull = 0
      for (var t = 0; t < view.circuitLength; t += 0.5) {
        view.travel = t
        var y = view.crossingOver(box)
        var covered = tc.beamCoverage(box)
        if (y >= 0.999)
          yielded += 1
        else {
          if (covered > worstCoveredWhileNotFull)
            worstCoveredWhileNotFull = covered
          if (y <= 0.001) {
            clear += 1
            if (covered > worstCoveredWhileClear)
              worstCoveredWhileClear = covered
          }
        }
      }
      view.travel = 216
      var samples = Math.ceil(view.circuitLength / 0.5)
      console.log("YIELD|full on " + (100 * yielded / samples).toFixed(1)
                  + "% of the circuit, untouched on " + (100 * clear / samples).toFixed(1)
                  + "%, partway on the rest; worst coverage while not fully yielded "
                  + (100 * worstCoveredWhileNotFull).toFixed(1) + "% of the box")
      verify(yielded > 0, "the field never yielded anywhere on the circuit")
      verify(clear > 0, "the field yielded everywhere on the circuit, which is not a yield")
      // A face that is absent for most of a lap has not yielded, it has been
      // deleted. This is what the first cut of the rule did, at 40%.
      verify(yielded / samples < 0.20,
             "the field is fully yielded on " + (100 * yielded / samples).toFixed(1)
             + "% of the circuit, which is a field that mostly is not there")
      // THE CRITERION: no crossbar ever covers more than a quarter of the
      // answer field without the field being fully out of the way. Coverage is
      // recomputed here rather than read off `crossingOver`, so the case is not
      // asserting that function against itself.
      verify(worstCoveredWhileNotFull <= view.fieldYieldAt + 1e-6,
             "a crossbar covered " + (100 * worstCoveredWhileNotFull).toFixed(1)
             + "% of the answer field on a frame where the field had not fully yielded")
      verify(worstCoveredWhileClear <= 1e-9,
             "a crossbar covered " + (100 * worstCoveredWhileClear).toFixed(2)
             + "% of the answer field on a frame where the field had not moved at all")
    }

    // What fraction of `box` a road-spanning prop's crossbar is behind right
    // now. Written out here rather than called on the view, so the case above
    // is not asserting `crossingOver` against itself.
    function beamCoverage(box) {
      var worst = 0
      for (var i = 0; i < view.archProps.length; i++) {
        var raw = (view.archProps[i] * view.propSpacing - view.travel) % view.propLoop
        var z = (raw < 0 ? raw + view.propLoop : raw) + view.nearDistance
        if (z <= view.nearDistance + 0.2 || z >= view.drawDistance)
          continue
        var top = view.archTopAt(view.archSpan, z)
        var stand = view.vAt(z) * view.height
        var beam0 = top + (stand - top) * view.archBeamTop
        var beam1 = top + (stand - top) * view.archBeamBottom
        var halfW = view.sizeAt(view.archSpan, z) / 2
        var cx = view.uAt(0, z) * view.width
        var down = Math.min(beam1, box.y + box.height) - Math.max(beam0, box.y)
        var across = Math.min(cx + halfW, box.x + box.width) - Math.max(cx - halfW, box.x)
        if (down <= 0 || across <= 0)
          continue
        var covered = (down / box.height) * (across / box.width)
        if (covered > worst)
          worst = covered
      }
      return worst
    }

    // An empty rect -- a bare TrackView in the harness -- yields nothing ever.
    function test_no_box_means_nothing_ever_yields() {
      compare(view.fieldYield, 0, "an unset field rect yielded")
      compare(view.factYield, 0, "an unset fact rect yielded")
      for (var t = 0; t < view.circuitLength; t += 3.0) {
        view.travel = t
        compare(view.crossingOver(Qt.rect(0, 0, 0, 0)), 0,
                "an empty box yielded at travel " + t)
      }
      view.travel = 216
    }

    // ------------------------------------- no roadside prop fills the frame
    //
    // Round four's throttle was on `arch` kinds only, so a 3-unit tyre wall was
    // exempt at any size and one of them measured x 1250-1920, y 100-730 on a
    // shipped frame -- 35% of it, top edge 336 px above the horizon, over the
    // sun. The rule is now on drawn size and every roadside class obeys it.
    function test_every_roadside_class_fades_before_it_fills_the_frame() {
      var widths = [3.0, 3.2, 2.0, 1.35]   // tyre wall, banner, timing board, drum/cone
      for (var i = 0; i < widths.length; i++) {
        var worstDrawn = 0
        for (var z = view.nearDistance + 0.2; z < view.drawDistance; z += 0.05) {
          var op = view.propOpacity(false, widths[i], z)
          if (op <= 0.004)
            continue
          var drawn = view.sizeAt(widths[i] * view.propAspect, z) / view.height
          if (drawn > worstDrawn)
            worstDrawn = drawn
        }
        verify(worstDrawn <= view.nearFadeGone + 0.001,
               "a " + widths[i] + "-unit roadside prop is still drawn at "
               + (worstDrawn * 100).toFixed(0) + "% of the frame height")
      }
    }

    // ... and the rule leaves ordinary roadside furniture alone.
    function test_a_prop_at_an_ordinary_distance_is_never_dimmed() {
      for (var z = 6; z < view.drawDistance; z += 0.5)
        compare(view.propOpacity(false, 3.2, z), 1,
                "a banner at z = " + z.toFixed(1) + " was dimmed")
    }
  }
}
