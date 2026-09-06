import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts/Circuit.js" as Circuit
import "../../ui/parts/Terrain.js" as Terrain

// WHERE A RACE OPENS -- ASKED OF THE RACE'S OWN FIRST FRAME.
//
// THE DEFECT THIS FILE EXISTS FOR. `ui/TrackView.qml` declares `property real
// travel: 120` -- a good reduced-motion STILL, a third of the way into sector
// 3's left-hander -- `advance()` only ever adds to it, and `ui/Race.qml` never
// assigned it: the word did not appear anywhere in that file. So every race in
// this build opened MID-CORNER IN THE ROCK QUARRY, polygonal walls both sides,
// a `200` distance board, no gantry, no chequer, no crowd, with the clock
// reading `TIME 0:00`, one frame after a countdown that had just painted a
// start line under a chequered arch.
//
// It shipped that way through six rounds of this piece and four of the race
// view. WHY nobody saw it is the part worth keeping: every frame anybody ever
// rendered of the track was rendered through `dev/Harness.qml --screen
// TrackView --travel <n>`, and the harness assigns `travel` itself. The one
// frame no tool in this repository produced was the frame a child actually
// gets. A spec that reads properties would not have caught it either -- the
// property was correct for what it is, and the bug was that nothing set it.
//
// So this file does the one thing that could not have missed it: it puts a
// `Race` on the screen, lets it build itself exactly as the flow does, and
// looks at the picture.
//
// Run it:
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
//     qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml
Item {
  id: root
  width: 1920
  height: 1080

  Race {
    id: race
    anchors.fill: parent
    mode: "grandPrix"
    preset: "1-12"
    seed: 42
  }

  TestCase {
    id: tc
    name: "RaceOpensAtTheStartLine"
    when: windowShown
    width: root.width
    height: root.height

    function sizeTo(w, h) {
      root.width = w
      root.height = h
      tc.wait(120)
    }

    function cleanupTestCase() {
      root.width = 1920
      root.height = 1080
    }

    // -------------------------------------------------------- the assignment

    // The camera is where the screen says it is, and the screen said something.
    // `TrackView`'s own default is 120 and it is a still's number, not a
    // start's; a race that opens on it is a race that opens in sector 3.
    function test_00_the_race_assigns_the_camera_a_place_to_start() {
      // Read on the frame the race is built, before `advance()` has moved it:
      // `travel` is monotonic and the road is already running by the time a
      // later case looks, so the only honest moment to compare the two is the
      // one `buildRace()` returns on. A new seed rebuilds the race exactly as
      // opening the screen does.
      race.seed = 4242
      compare(race.trackTravel, race.startTravel,
              "buildRace() puts the camera at startTravel; if these differ the"
              + " assignment is missing and TrackView's own default is what"
              + " ships")
      verify(Math.abs(race.trackTravel - 120) > 1,
             "120 is TrackView's reduced-motion still -- a third of the way"
             + " into sector 3's left-hander -- and a race that opens there"
             + " opens in the rock quarry: trackTravel is " + race.trackTravel)
      race.seed = 42
      compare(race.trackTravel, race.startTravel,
              "and every race after the first: RACE AGAIN rebuilds through the"
              + " same path and must open at the same line")
    }

    // The start arch is the first landmark of the circuit and it stands over
    // the start grid. A race opens looking at it.
    function test_01_the_start_arch_is_ahead_of_the_camera() {
      var loop = Terrain.CIRCUIT_LENGTH
      var first = -1
      for (var i = 0; i < Circuit.PLACEMENTS.length; i++) {
        var place = Circuit.PLACEMENTS[i]
        if (place.kind !== "gantry")
          continue
        if (first < 0 || place.s < first)
          first = place.s
      }
      verify(first >= 0, "the circuit has a start gantry")
      var z = ((first - race.trackTravel) % loop + loop) % loop
      verify(z > 2 && z < 20,
             "the start arch stands " + z.toFixed(2) + " units up the road from"
             + " the opening camera. Under 2 it is overhead and its board is off"
             + " the top of the frame; over 20 it is a speck and this is not the"
             + " start line")
    }

    // ============================================================ THE PICTURE
    //
    // Everything below reads the rendered frame, for the reason at the top of
    // this file: the defect was invisible to every property in the tree.

    function isLight(img, x, y) {
      // The chequer's cream squares as the hour's tint leaves them at lap 1,
      // and nothing else on this road: the tarmac reads about (26, 11, 22) and
      // the floor's grid about (60, 18, 40).
      return img.red(x, y) > 150 && img.green(x, y) > 130 && img.blue(x, y) > 95
    }

    // THE PICTURE. The road ahead of the field is chequered.
    //
    // A band across the middle of the road, well below the horizon and well
    // above the karts, measured as the fraction of it that is cream. The start
    // grid is six columns by four rows of it and fills the road; sector 3's
    // quarry, which is what this screen used to open on, has a dashed centre
    // line and two edge lines in the same band and nothing else.
    //
    // Measured on the shipped 1920 x 1080 first frames: 17.4% of the band is
    // cream at the start line against 2.3% in the quarry, so the floor below is
    // three times the old picture and half the new one.
    function chequerFraction(img) {
      var x0 = Math.round(root.width * 0.38)
      var x1 = Math.round(root.width * 0.64)
      var y0 = Math.round(root.height * 0.50)
      var y1 = Math.round(root.height * 0.64)
      var n = 0
      for (var y = y0; y < y1; y++)
        for (var x = x0; x < x1; x++)
          if (tc.isLight(img, x, y))
            n += 1
      return n / Math.max(1, (x1 - x0) * (y1 - y0))
    }

    // ... and it is a CHEQUER and not a stripe: a scanline across it crosses
    // the cream and comes back several times over.
    function bestAlternations(img) {
      var x0 = Math.round(root.width * 0.38)
      var x1 = Math.round(root.width * 0.64)
      var y0 = Math.round(root.height * 0.50)
      var y1 = Math.round(root.height * 0.64)
      var best = 0
      for (var y = y0; y < y1; y += 2) {
        var last = -1
        var alt = 0
        for (var x = x0; x < x1; x++) {
          var lit = tc.isLight(img, x, y) ? 1 : 0
          if (last >= 0 && lit !== last)
            alt += 1
          last = lit
        }
        if (alt > best)
          best = alt
      }
      return best
    }

    function test_02_the_first_frame_is_the_start_line() {
      var sizes = [[1920, 1080], [1366, 768], [1024, 600]]
      for (var i = 0; i < sizes.length; i++) {
        tc.sizeTo(sizes[i][0], sizes[i][1])
        var label = sizes[i][0] + "x" + sizes[i][1]
        var img = grabImage(race)
        var frac = tc.chequerFraction(img)
        var alt = tc.bestAlternations(img)
        verify(frac >= 0.07,
               label + ": the road ahead of the field is " + (frac * 100).toFixed(1)
               + "% cream. The start grid measures about 17%; the rock quarry"
               + " this screen used to open on measures 2.3%")
        verify(alt >= 5,
               label + ": the cream ahead alternates " + alt + " times across the"
               + " road, so it is a chequer and not a centre line")
      }
    }

    // The other half of the same claim, and the one a moved camera cannot fake:
    // the crowd is at the start line and nowhere else on the circuit. `Circuit`
    // puts `crowdStand` placements along the start straight; if the opening
    // frame holds none of them the camera is somewhere else.
    function test_03_the_crowd_is_at_the_line() {
      tc.sizeTo(1920, 1080)
      var loop = Terrain.CIRCUIT_LENGTH
      var near = 0
      for (var i = 0; i < Circuit.PLACEMENTS.length; i++) {
        var place = Circuit.PLACEMENTS[i]
        if (place.kind !== "crowd")
          continue
        var z = ((place.s - race.trackTravel) % loop + loop) % loop
        if (z > 1 && z < 30)
          near += 1
      }
      verify(near >= 2,
             "only " + near + " crowds are within 30 units of the opening"
             + " camera. The design's sector-1 landmark row is 'gantry, tyre"
             + " walls, pit boards, the grid floor, a silhouetted crowd with"
             + " flags', and a race opens on it")
    }
  }
}
