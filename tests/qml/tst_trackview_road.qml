import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts/Circuit.js" as Circuit
import "../../ui/parts/PropMeta.js" as PropMeta

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
    // PIECE T: and the claim is narrower and more honest than it was. An arch
    // is exempt from the NEAR FADE -- passing under one is meant to fill the
    // frame -- but not from the haze, because an arch a hundred units away is
    // as far into the dusk as anything else at that distance. So the case is
    // that no arch is ever throttled by SIZE, which is what round four did.
    function test_no_road_spanning_prop_is_ever_dimmed_by_its_size() {
      var tall = view.propWorldHeight("gantry")
      for (var z = view.nearDistance; z < view.drawDistance; z += 0.25)
        compare(view.propOpacity(true, tall, z), view.hazeClarity(z),
                "a road-spanning prop was throttled by its size at z = " + z.toFixed(2))
      // A MUTATION GUARD, because the case above passes trivially if `nearFade`
      // has been reduced to a constant 1 for everything. The gantry is 5.24
      // world units tall, so at z = 3 it is drawn at 105% of the frame height
      // and a prop that is not exempt would be gone.
      verify(view.nearFade(tall, 3) <= 0.001,
             "nearFade does not engage at all: a 5.24-unit prop at z = 3 keeps "
             + view.nearFade(tall, 3).toFixed(3) + " of its opacity")
      compare(view.propOpacity(true, tall, 3), view.hazeClarity(3),
              "the exemption did not survive the depth the fade bites at")
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
          // EXACTLY zero, not "under a thousandth". `crossingOver` divides the
          // covered fraction by `fieldYieldAt`, so a coverage of 0.02% comes
          // back as 0.0008 -- which a 0.001 threshold called "untouched" while
          // a crossbar was measurably over the box. The claim in this case's
          // last line is that the field never sits still under a crossbar AT
          // ALL, and 0.0008 is not nothing.
          if (y <= 0) {
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
    // now. Written out here from the CIRCUIT TABLE and the KIT'S OWN meta
    // rather than called on the view, so the case above is not asserting
    // `crossingOver` against itself.
    function beamCoverage(box) {
      var worst = 0
      for (var i = 0; i < Circuit.PLACEMENTS.length; i++) {
        var place = Circuit.PLACEMENTS[i]
        var beam = view.archBeams[place.kind]
        if (!place.spans || beam === undefined)
          continue
        var raw = (place.s - view.travel) % view.propLoop
        var z = raw < 0 ? raw + view.propLoop : raw
        if (z <= view.nearDistance + 0.2 || z >= view.drawDistance)
          continue
        var meta = PropMeta.forProp(place.kind)
        var stand = view.vAt(z) * view.height
        var tall = view.sizeAt(meta.world[1], z)
        var top = stand - tall
        var beam0 = top + tall * beam[0]
        var beam1 = top + tall * beam[1]
        var halfW = view.sizeAt(meta.world[0], z) / 2
        var cx = view.uAt(place.x, z) * view.width
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
    // PIECE T: EVERY KIND THE CIRCUIT ACTUALLY PLACES, at its own baked
    // height. The rule used to be checked against four hand-typed widths
    // multiplied by one nominal aspect, which was the right rule measured on
    // the wrong object: the kit's twenty-five props are baked at their own
    // proportions -- a pine is 1.8 by 5.28 world units, a hay bale 1.35 by
    // 0.75 -- so a width-times-constant is wrong by a factor of two in both
    // directions. This walks the kinds `ui/parts/Circuit.js` puts on the
    // ground and reads each one's height out of the kit's meta.
    function test_every_roadside_class_fades_before_it_fills_the_frame() {
      var kinds = Circuit.kindsUsed()
      var checked = 0
      for (var i = 0; i < kinds.length; i++) {
        var meta = PropMeta.forProp(kinds[i])
        verify(meta !== null, kinds[i] + " is not a prop in the kit")
        if (view.archBeams[kinds[i]] !== undefined)
          continue                     // an arch is meant to fill the frame
        checked += 1
        var tall = meta.world[1]
        var worstDrawn = 0
        for (var z = view.nearDistance + 0.2; z < view.drawDistance; z += 0.05) {
          if (view.propOpacity(false, tall, z) <= 0.004)
            continue
          var drawn = view.sizeAt(tall, z) / view.height
          if (drawn > worstDrawn)
            worstDrawn = drawn
        }
        verify(worstDrawn <= view.nearFadeGone + 0.001,
               "a " + kinds[i] + " is still drawn at "
               + (worstDrawn * 100).toFixed(0) + "% of the frame height")
      }
      verify(checked >= 12, "only " + checked + " roadside kinds were checked")
    }

    // ... and the rule leaves ordinary roadside furniture alone: at an ordinary
    // distance a prop's only loss is the haze, which is the design's own
    // atmospheric perspective and not a throttle.
    function test_a_prop_at_an_ordinary_distance_is_only_dimmed_by_the_haze() {
      var tall = PropMeta.forProp("banner").world[1]
      for (var z = 6; z < view.drawDistance; z += 0.5)
        compare(view.propOpacity(false, tall, z), view.hazeClarity(z),
                "a banner at z = " + z.toFixed(1) + " lost more than the haze")
    }

    // ---------------------------------------------- and each sector is a place
    //
    // The gate on this piece is that "a stranger shown the twelve frames
    // unlabelled should be able to tell them apart". That is a judgement, but
    // one half of it is arithmetic and belongs here: every sector has to have
    // something authored in it, and the twelve landmark props the design names
    // by name have to be where the design puts them.
    function test_every_sector_has_a_landmark_and_furniture() {
      var counts = Circuit.countBySector()
      for (var i = 0; i < counts.length; i++)
        verify(counts[i] >= 8,
               "sector " + (i + 1) + " (" + Circuit.SECTOR_NAMES[i] + ") has only "
               + counts[i] + " roadside objects")
      var wanted = { "gantry": 0, "banner": 1, "waterTower": 2, "rockWall": 3,
                     "jetty": 4, "bridge": 5, "rollerDoor": 6, "overpass": 8,
                     "scrapyard": 9, "billboard": 10 }
      for (var kind in wanted) {
        var found = false
        for (var p = 0; p < Circuit.PLACEMENTS.length; p++) {
          var place = Circuit.PLACEMENTS[p]
          if (place.kind === kind
              && Math.floor(place.s / Circuit.SECTOR_LENGTH) === wanted[kind])
            found = true
        }
        verify(found, "the design puts a " + kind + " in sector "
                      + (wanted[kind] + 1) + " and the circuit has none there")
      }
    }

    // NO PROP IS DRAWN IN CODE. Every object on the roadside has to be a cell
    // of a sheet under assets/props/, and the view has to be able to find that
    // cell -- a typo in a view name would otherwise draw nothing at all and
    // look exactly like a prop that is simply far away.
    function test_every_roadside_object_is_a_cell_of_the_frozen_kit() {
      for (var i = 0; i < Circuit.PLACEMENTS.length; i++) {
        var place = Circuit.PLACEMENTS[i]
        var meta = PropMeta.forProp(place.kind)
        verify(meta !== null, "placement " + i + " names " + place.kind
                              + ", which is not in the kit")
        // Every frame the animation can reach has to exist in the sheet.
        for (var c = 0; c < 40; c++) {
          var name = Circuit.viewAt(place, c * 0.05)
          verify(meta.views.indexOf(name) >= 0,
                 place.kind + " has no view " + name
                 + " (placement " + i + ", " + place.anim + ")")
          verify(PropMeta.cellRect(place.kind, name, 0) !== null,
                 place.kind + " " + name + " has no cell")
        }
      }
    }

    // AND NO TWO CROWDS ARE IN PHASE. The design asks for "a wave of jumps and
    // raised arms rolling along the rail; never two crowds in phase". Measured
    // over a second of world clock, no two crowd placements may ever show the
    // same frame at the same moment for the whole of it.
    function test_no_two_crowds_are_ever_in_step() {
      var crowds = []
      for (var i = 0; i < Circuit.PLACEMENTS.length; i++)
        if (Circuit.PLACEMENTS[i].anim === "crowd")
          crowds.push(Circuit.PLACEMENTS[i])
      verify(crowds.length >= 6, "only " + crowds.length + " crowds on the circuit")
      for (var a = 0; a < crowds.length; a++) {
        for (var b = a + 1; b < crowds.length; b++) {
          var same = 0
          var samples = 0
          for (var t = 0; t < 1.0; t += 0.02) {
            samples += 1
            if (Circuit.viewAt(crowds[a], t) === Circuit.viewAt(crowds[b], t))
              same += 1
          }
          verify(same < samples,
                 "two crowds are on the same frame for a whole second")
        }
      }
    }
  }
}
