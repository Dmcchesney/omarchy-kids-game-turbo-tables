import QtQuick
import "parts"
import "parts/CarMeta.js" as CarMeta
import "parts/CardFx.js" as CardFx

// Looking down the track.
//
// THE ONE PROJECTION, WRITTEN THREE TIMES
//
// The road is drawn by a fragment shader that inverts the camera projection
// per pixel; the karts and the roadside props are ordinary items positioned by
// the same projection in QML; and CanvasRoad.qml draws the same road again for
// machines where the shader will not run. Those three have to agree exactly,
// or a kart floats above the tarmac. The four lines that must match are:
//
//     v(z)      = horizon + focal * camHeight / (2 z)          <- vAt
//     z(v)      = focal * camHeight / (2 (v - horizon))        <- road.frag
//     u(x, z)   = 0.5 + (x + curve z^2) focal / (2 z aspect)   <- uAt
//     pixels(W) = W focal height / (2 z)                       <- sizeAt
//
// The last one is why horizontal and vertical sprite scale are the same
// number: `aspect` cancels against width/height, so a kart is never stretched.
//
// WHAT MOVES. Speed is effective-progress rate, not a throttle: the child does
// not steer and cannot brake, so `speed` is set by Race.qml from how fast the
// engine's effective progress is climbing, a Turbo throws `travel` forward and
// a landed attack pulls the horizon back and stalls the road. The kart itself
// never reverses -- the design is explicit that the road does the telling --
// so `travel` is monotonic and only its rate ever changes.
//
// WHAT IT COSTS. The road renders into a layer at 480 x 270 and is scaled up
// with nearest-neighbour filtering, so the fragment work is an eighth of
// 1080p. The roadside props are drawn once each into fixed-size canvases and
// are moved and scaled by the scene graph after that; the cars are cells of
// baked sheets (CarSprite) and are never drawn at all -- so a frame is one
// shader pass and a couple of dozen textured quads. The kart list is a
// ListModel rather than a JavaScript array on purpose: assigning a new array
// to a Repeater destroys and rebuilds every delegate, and at sixty frames a
// second that would rebuild four sprites sixty times a second.
Item {
  id: view

  property bool reducedMotion: false
  property bool paused: false

  // 0 = stopped, 1 = a good pace. Race.qml drives it from progress rate.
  property real speed: 0.55
  // The child's smoothed effective progress, in questions. Every other kart
  // is placed relative to it.
  property real humanProgress: 0

  // ------------------------------------------------------- camera constants
  readonly property real baseHorizon: 0.400
  readonly property real camHeight: 2.20
  readonly property real baseFocal: 1.20
  readonly property real roadHalf: 1.90
  readonly property real rumbleHalf: 0.30
  readonly property real stripe: 1.4
  readonly property real gridScale: 4.5
  readonly property real drawDistance: 190
  readonly property real nearDistance: 1.25
  // Where the child's kart sits. The two numbers are locked together: a kart's
  // size and its height up the screen are both 1/z, so "low on the screen" and
  // "not enormous" are the same choice. At z = 2.6 with a kart 1.55 world
  // units wide the sprite is about a fifth of the screen width and its roof
  // sits just below the horizon, which leaves the whole upper third free for
  // the fact -- which the design requires, because the fact may never be over
  // the karts.
  readonly property real playerZ: 3.20
  readonly property real kartWorldWidth: 1.36
  // THE SHEET IS NOT THE KART, AND ROUND TWO MEASURED THE SHEET.
  //
  // The v1 sprite drew a kart into a 192 x 128 sheet whose model box was 62 world
  // units across; the kart itself, wheel to wheel, is 37 of them. Scaling the
  // SHEET to `kartWorldWidth` therefore drew a kart 37/62 = 0.60 of the width
  // it claimed to be. Round two's report said "the furthest kart on the road is
  // at z = 41.2 and about 43 px wide, over the ~28 px floor a number plate
  // needs": its own `sizeAt` says 21.4 px of SHEET at that depth, and the
  // rendered green body measured 12 x 6 px. The claim was wrong by 2x against
  // the arithmetic and by 3.5x against the pixels, and it was the second round
  // running that a number was asserted about a picture that did not contain it.
  //
  // So the scale is taken off the kart rather than off the sheet it is drawn
  // in, which is a correction, not a fudge: `kartWorldWidth` now means roughly
  // what it says, and a kart is about 1.36 world units on a 3.80-unit road.
  //
  // ROUGHLY, and the slack is stated rather than hidden. 62/37 is the model
  // box: the sheet spans 62 units and the wheels 37. Rendered, the yaw widens
  // it -- the buggy body measures 124 px of 192 (0.646) on its own sheet, where
  // the model geometry alone predicts 0.597 -- and the six bodies differ from
  // one another besides. So a drawn kart is within about 8% of its nominal
  // width, not exactly on it. Every kart size quoted in the evidence is a
  // pixel measurement of the rendered frame, not this arithmetic.
  readonly property real kartSheetSpan: 62 / 37
  // AND THEN A FLOOR, WHICH IS A DELIBERATE BREAK IN THE PERSPECTIVE.
  //
  // Even corrected, the saturating tail puts the leader of a Grand Prix at
  // z = 41.2 and 21 px wide. A leader that reads is worth more than a leader
  // that scales, so the kart stops shrinking at 2.8% of the window height --
  // 30 px at 1080p, 21 px at 768. Past z = 29 every kart is that size, which is
  // the far tail the distance compression has already crushed together: over
  // that range the sprite's y position moves 11 px, so nothing that was in
  // front of something else stops being in front of it.
  readonly property real kartMinPixels: Math.max(18, height * 0.028)
  // World units per question of effective progress, near the child.
  readonly property real unitsPerQuestion: 4.0
  // How far ahead the compressed distance is allowed to reach. Round one let
  // it run to whatever the gap was, and the two karts actually beating the
  // child came out 17 px and 13 px wide -- the karts you most need to read
  // were the ones you could not. The tail now saturates: `farSpan` is the most
  // any rival can ever be pushed past the four-question near zone, so the
  // furthest kart on the road is 41.2 world units away. What it MEASURES at
  // that depth is in the evidence and not asserted here.
  readonly property real farSpan: 22.0
  readonly property real farSoftness: 13.0

  // ------------------------------------------------------------ the circuit
  // THE TRACK IS A TABLE, NOT A SINE.
  //
  // Design, The view: "the road narrows to a vanishing point, curves swing the
  // horizon ... The track is a closed circuit of twelve sectors, one per
  // lap-table, each with its own landmark."
  //
  // Round one derived `curve` from two sines with amplitudes of 0.00075 and
  // 0.00042. Measured over a whole cycle that moved the far road centre at
  // y=510 by 26 px in 1920 -- 1.4% -- so the road was straight and the
  // concession that "the horizon swings and the road bends" was false.
  //
  // So the circuit is now authored: twelve sectors around a closed loop, each
  // with a corner and a gradient, and both the roadside landmarks and the
  // curve are indexed off the same loop position. Sector 4's roller door is at
  // the same place on the track every lap because the props and the corners
  // are the same table read twice.
  //
  // The two amplitudes are the only knobs. `curveAmplitude` is set from the
  // measurement it controls: the far road centre at y=510 moves
  // 11846 * curve pixels at 1920x1080, so 0.0255 is a +-302 px swing and a
  // 604 px peak-to-peak excursion, 31% of the frame's width.
  readonly property int sectorCount: 12
  readonly property real sectorLength: 36.0
  readonly property real circuitLength: sectorCount * sectorLength
  readonly property real curveAmplitude: 0.0255
  readonly property real hillAmplitude: 0.030

  // Two long straights, one wide left-hand sweep, one tighter right-hander,
  // which is the shape the minimap draws. Positive bends the road right.
  readonly property var sectorCurve: [0.00, 0.10, -0.45, -1.00, -0.80, -0.20,
                                      0.00, 0.55, 1.00, 0.62, 0.15, -0.10]
  readonly property var sectorHill:  [0.00, 0.30, 0.72, 0.40, 0.00, -0.40,
                                      -0.75, -0.35, 0.10, 0.55, 0.25, -0.20]

  // Sampled at sector boundaries and blended with a smoothstep, so the value
  // is continuous and its slope is zero at every boundary: a corner opens and
  // closes rather than switching on.
  function sectorBlend(table, at) {
    var p = at / sectorLength
    var i = Math.floor(p)
    var f = p - i
    var s = f * f * (3 - 2 * f)
    var a = table[((i % sectorCount) + sectorCount) % sectorCount]
    var b = table[(((i + 1) % sectorCount) + sectorCount) % sectorCount]
    return a + (b - a) * s
  }

  function curveAt(at) { return sectorBlend(sectorCurve, at) * curveAmplitude }
  function hillAt(at) { return sectorBlend(sectorHill, at) * hillAmplitude }

  // Which sector of the circuit the camera is in, 0-based. Exposed so a test
  // or a harness can assert that a landmark and its corner arrive together.
  readonly property int sectorNow: {
    var p = Math.floor(travel / sectorLength)
    return ((p % sectorCount) + sectorCount) % sectorCount
  }

  // ----------------------------------------------------------- live camera
  // Not zero: with reduced motion on, nothing ever calls advance() and the
  // still is whatever `travel` starts at. Starting it a third of the way into
  // sector 3 means the reduced-motion picture is a road in a corner rather
  // than a ruler.
  //
  // AND IT IS A MULTIPLE OF `propSpacing`, WHICH IS THE OTHER HALF OF THAT.
  //
  // At 118 the nearest roadside prop sat at z = 3.25, and a 3.0-unit tyre wall
  // at that depth is 1,340 px wide: in motion it is a wall whooshing past, but
  // under reduced motion NOTHING EVER CALLS advance(), so the still a child
  // with that setting on looks at for the whole race had a tyre wall filling
  // the right half of the frame, over the sun. The prop loop is 8 units, so a
  // travel that is a multiple of 8 puts the nearest prop exactly at the near
  // cull -- z = 1.25, culled -- and the next at z = 9.25, which is a roadside
  // rather than a wall. 120 is that, and is still inside sector 3's corner.
  property real travel: 120
  // Derived, not assigned, so it is right on the first frame, right under
  // reduced motion, and cannot fall out of step with `travel`.
  readonly property real curve: curveAt(travel)
  // Impulses, each 0..1 and each decaying. Reduced motion never raises them.
  // Where the car is pointing, in backdrop pixels. The integral of the curve
  // along the track; the far wall parallaxes with it.
  property real heading: 0
  property real lurch: 0
  property real pullback: 0
  property real shake: 0
  property real shakeX: 0
  property real shakeY: 0

  // The horizon swings because the track climbs and falls, which is the other
  // half of what the design means by "curves swing the horizon": the lateral
  // term moves the road, the gradient moves the skyline. Bounded to +-32 px at
  // 1080p so the far wall never reaches the fact.
  // PIECE F. Two of the design's per-card beats are camera moves rather than
  // sprites -- Turbo's "the road stretches (focal length bumps for 400)" and
  // "the horizon dips" -- so they are terms of the same two expressions the
  // lurch and the pull-back already are, and they decay with the cue rather
  // than being assigned anywhere. `fxFocalBump` and `fxHorizonDip` are zero
  // whenever no card is in its impact beat, and zero always under reduced
  // motion.
  readonly property real horizon: baseHorizon + pullback * 0.055 + hillAt(travel) + fxHorizonDip
  readonly property real focal: baseFocal + lurch * 0.16 - pullback * 0.13 + fxFocalBump
  readonly property real aspect: height > 0 ? width / height : 16 / 9

  // ------------------------------------------------------- the projection
  function vAt(z) { return horizon + (focal * camHeight) / (2 * Math.max(0.05, z)) }
  function uAt(x, z) {
    return 0.5 + ((x + curve * z * z) * focal) / (Math.max(0.05, z) * 2 * aspect)
  }
  function sizeAt(worldWidth, z) {
    return worldWidth * focal * height / (2 * Math.max(0.05, z))
  }

  // How wide a kart's SHEET is drawn at depth z: the kart at true perspective
  // scale, floored so it never falls below `kartMinPixels` of actual kart.
  function kartSheetPixels(z) {
    return Math.max(kartMinPixels * kartSheetSpan,
                    sizeAt(kartWorldWidth * kartSheetSpan, z))
  }

  // PIECE C: THE SHEET IS A CELL, AND A CELL IS DRAWN AT A WHOLE NUMBER.
  //
  // A car on the road is one cell of its baked sheet: the `road` camera, the
  // row (192, 96 or 48 px) and the upscale (1, 2 or 3) whose product is
  // nearest the width the projection asks for, and the yaw column nearest the
  // car's heading relative to the camera. So a car steps through seven sizes
  // -- 48, 96, 144, 192, 288, 384, 576 -- rather than scaling continuously,
  // and is never resampled: nearest-neighbour at a whole number is the pixel
  // look and is also free. `CarMeta.fit` is the one place that choice is made.
  function kartCell(z) { return CarMeta.fit(kartSheetPixels(z)) }

  // The car's heading relative to the camera at depth z, in degrees: the
  // road's tangent, since a kart follows the road. `uAt` puts the road centre
  // at x = curve z^2, so its slope is 2 curve z, and a right-hand bend is
  // positive. The child's own car is followed by the camera and always reads
  // square.
  function kartHeadingDeg(z) {
    return Math.atan(2 * curve * z) * 180 / Math.PI
  }

  // Compressed distance for a kart `delta` questions ahead of the child.
  //
  // The first four questions are true scale, so the kart you are actually
  // fighting moves the way it should. Past that the gap is squashed through a
  // saturating exponential rather than a linear 0.30: the leader of a Grand
  // Prix can be seventy questions up the road, and 70 x 4 x 0.30 put it 87
  // world units away. It now saturates at `farSpan`, so the furthest kart on
  // the road is at z = 41.2, and `kartSheetPixels` decides how big that is.
  //
  // A NEGATIVE DELTA RETURNS A z BEHIND THE CAMERA, AND THAT IS CORRECT.
  //
  // `zForDelta(-1)` is 3.2 - 4.0 = -0.8. The camera sits behind the child's
  // kart, so a rival even one question back really is behind the lens and
  // there is no honest place on this road to draw it. Round two stopped there,
  // and the consequence was the whole of the round's remaining gap: with the
  // child answering at a steady pace on seed 42, 1516 of 1875 frames of a
  // thirty-second run -- 81% -- carried NO rival sprite at all, the longest
  // unbroken run being 1217 frames, about nineteen seconds of empty road while
  // a race was going on. The plates went with the karts, so a child in the
  // lead was told nothing about the field at all.
  //
  // The answer is not to drag the kart back onto the road at a depth it is not
  // at. It is the chaser rail at the bottom of this file, which draws the
  // rivals behind the child where they actually are: behind.
  function zForDelta(delta) {
    var a = Math.abs(delta)
    var near = Math.min(a, 4) * unitsPerQuestion
    var extra = a > 4 ? a - 4 : 0
    var far = farSpan * (1 - Math.exp(-extra / farSoftness))
    return playerZ + (delta < 0 ? -1 : 1) * (near + far)
  }

  // Lane offsets by seat, so four karts do not stack on the centre line.
  // Seat 0 is the child's. It is not 0.0: at dead centre the hero sat exactly
  // on the dashed centre line, so it never read as being *in* a lane. It sits
  // a third of a lane off and drifts to the outside of a corner, which is the
  // only steering in a game where the child does not steer.
  //
  // THE LANES WIDENED WHEN THE KARTS DID. Correcting the sprite scale made a
  // kart 1.36 world units wide instead of about 0.8, and on the start line --
  // where all four are at exactly `playerZ` -- lanes 0.98 apart put PISTON
  // almost entirely behind the child's kart, number plate and all. Four karts
  // of 1.36 cannot be four abreast on a 3.80-unit road however they are
  // arranged, so the pack still overlaps; these are the widest lanes that keep
  // every kart's own number plate clear of its neighbour. The hero's drift
  // with the corner is gentler for the same reason: at 13.0 it crossed into
  // PISTON's lane on a hard left.
  //
  // ROUND FOUR: EVERY WHEEL IS ON THE TARMAC.
  //
  // Round three set the outer two to +-1.34 and its comment said "the outer
  // two ride the rumble strip at the start, which is what a four-wide first
  // row looks like." Two critics disagreed, and they were right: a kart is
  // 1.36 world units wide, so a lane centre at 1.34 puts its outer wheels at
  // 2.02 on a road whose edge is `roadHalf` = 1.90 -- 0.12 units, about
  // twenty screen pixels at the start line, of wheel standing on the kerb.
  // A racing game teaching a child that the leaders start half off the track
  // is a picture defect, not a stylistic choice. `laneLimit` is derived from
  // the road and the kart rather than typed, so it cannot fall out of step
  // with either: half the road, less half a kart, less a hand's margin.
  readonly property real laneLimit: roadHalf - kartWorldWidth / 2 - 0.04
  readonly property real heroLane: 0.30 - curve * 8.0
  readonly property var lanes: [0.0, -laneLimit, laneLimit, -0.58]
  function laneOf(seat) {
    var s = ((seat % 4) + 4) % 4
    return s === 0 ? heroLane : lanes[s]
  }

  // ---------------------------------------------------------- the kart list
  ListModel { id: kartModel }

  // Called once, when the race is built.
  function setKarts(list) {
    kartModel.clear()
    fxReset()
    for (var i = 0; i < list.length; i++) {
      var k = list[i]
      if (k.isHuman === true) {
        // PIECE F. The child's own car, remembered here rather than looked up
        // every frame: the afterimage trail on a boost draws three more copies
        // of it, and a Repeater cannot ask a ListModel a question reactively.
        // Nothing about the hero's car changes during a race.
        heroIndex = i
        heroBody = k.body
        heroNumber = k.number
        heroPaint = 0
        for (var q = 0; q < Theme.paints.length; q++)
          if (Qt.colorEqual(Theme.paints[q], k.paint))
            heroPaint = q
      }
      kartModel.append({
        "kartId": k.id,
        "kartName": k.name,
        "kartNumber": k.number,
        "kartBody": k.body,
        "kartSeat": k.seat,
        "kartPaint": String(k.paint),
        "kartProgress": k.progress,
        "kartGap": 0,
        "isHuman": k.isHuman === true,
        "isGhost": k.ghost === true,
        // PIECE F -- the target state, from design v4's grammar table: "the
        // victim kart changes: a smoke sprite pinned to its hood, a wobble in
        // yaw (cycle sprite columns +-1), a bounce in y, a spin (cycle all
        // eight columns), for as long as the effect lasts".
        //
        // Every one of them is a millisecond reading of `fxClock`, not a flag:
        // "" and 0 mean nothing is happening, and a delegate binding compares
        // the clock against the number. A ListModel role is typed by the first
        // value put in it, which is why they are all initialised here and why
        // `fxKind` is a string rather than an enum.
        //
        //   fxKind   "" | "wobble" | "spin" | "bounce" | "jolt"
        //   fxFrom   the fxClock reading the state began at
        //   fxUntil  the reading it ends at
        //   fxSmoke  the reading the hood stops smoking at. The ENGINE keeps
        //            this alive: Race.qml renews it every frame for as long as
        //            `questionsNeededThisLap` is above the clean lap, which is
        //            the design's own definition of when an effect ends.
        //   fxLow    how many pixels the kart rides low (Pothole's aftermath)
        //   fxFlash  the reading a tag flash ends at (Pile-Up's field flash)
        //
        // ROUND 2 -- THE NAME PLATE IS WHERE AN EFFECT READS WHEN THE KART
        // CANNOT. A rival one question up who takes a Wrench is FIVE questions
        // BEHIND the child a moment later, and a first-person camera cannot
        // show a kart behind it; the leader of a Grand Prix saturates at the
        // vanishing point and is thirty pixels wide. In both cases the sparks,
        // the smoke and the floating `+5` land where nobody can read them. Every
        // rival always has a plate on screen, though -- the ahead badge or the
        // chaser rail -- so the effect is mirrored onto it and the child is
        // never told nothing.
        //
        //   fxPlate      the text the plate carries ("+5", "TOWED", "BLOCKED")
        //   fxPlateTone  its colour, as a string
        //   fxPlateBorn  the reading it started carrying it, for the ring
        //   fxPlateUntil the reading the plate stops carrying it
        "fxKind": "",
        "fxFrom": 0,
        "fxUntil": 0,
        "fxSmoke": 0,
        "fxLow": 0,
        "fxFlash": 0,
        "fxPlate": "",
        "fxPlateTone": "#f5a524",
        "fxPlateBorn": 0,
        "fxPlateUntil": 0
      })
    }
  }

  // Called every frame with one number per kart, in the same order. Setting a
  // role leaves the delegate alone and only re-evaluates the bindings that
  // read it, which is the whole reason this is a ListModel.
  //
  // `order`, if given, is the engine's authoritative finishing order as an
  // array of kart ids, first to last -- `Engine.raceOrder(state)`. Pass it and
  // the drawn karts can never contradict a callout. See `orderedProgress`.
  //
  // `exact`, if given, is the UNSMOOTHED effective progress per kart, in the
  // same order -- the integers the engine ranks by, and the ones the minimap's
  // dots and the pass callouts are driven from. The name plates take their gap
  // from it.
  //
  // (These three sentences named "the HUD's ladder" until round five. There is
  // no ladder: the four-rung standings strip was deleted for breaking the
  // design's Fairness rule, `tst_race_keys.qml` has a case that keeps it
  // deleted, and the comment outlived it by two rounds.)
  //
  // A plate shows its gap ONLY when `exact` was supplied. Rounding the smoothed
  // delta instead is wrong on 17% of frames -- measured, 320 of 1875 -- because
  // the smoothing takes about four tenths of a second to cross the next half
  // question, and a plate reading "+3" beside a minimap and a callout built on
  // "2" is two sources of truth for one number. Without `exact` the plate is
  // the name alone, which is still every rival named at every distance.
  property bool haveExact: false

  function setProgress(values, order, exact) {
    var v = order ? orderedProgress(values, order) : values
    var n = Math.min(v.length, kartModel.count)
    haveExact = !!(exact && exact.length >= n)
    var mine = 0
    if (haveExact)
      for (var h = 0; h < n; h++)
        if (kartModel.get(h).isHuman)
          mine = exact[h]
    for (var i = 0; i < n; i++) {
      kartModel.setProperty(i, "kartProgress", v[i])
      if (haveExact)
        kartModel.setProperty(i, "kartGap", Math.round(exact[i] - mine))
      // EVERY DEPTH IS MEASURED FROM THIS NUMBER, SO IT HAS TO BE THE SAME
      // NUMBER THE OTHERS WERE PROJECTED WITH.
      //
      // The caller sets `humanProgress` from the UNPROJECTED value one line
      // before it calls this, and every rival's depth is `kartProgress -
      // humanProgress`. That mixes a projected numerator with an unprojected
      // reference, and in the case the projection exists for -- a rival passing
      // the child, where it is the child's own smoothed value that has to come
      // down -- the two disagree and the rival is drawn behind. Round two's
      // critic forced it once in about fifteen thousand frames, at a magnitude
      // of 5e-5 questions; my own watch forced it once in 1875 on seed 11. It
      // is a seam rather than a defect, and reading the reference back off the
      // array that was just projected closes it without the caller changing.
      if (order && kartModel.get(i).isHuman)
        humanProgress = v[i]
    }
  }

  // What the model actually STORES for kart `index`, and the depth the
  // delegate therefore binds to. Exposed for the same reason `Minimap.drawnT`
  // is: the picture and its inputs came apart once already, and a test that
  // asserts the inputs proves nothing about the frame.
  function drawnProgress(index) {
    return (index >= 0 && index < kartModel.count)
           ? kartModel.get(index).kartProgress : -1
  }
  function drawnZ(index) {
    if (index < 0 || index >= kartModel.count)
      return -1
    var k = kartModel.get(index)
    return k.isHuman ? playerZ : zForDelta(k.kartProgress - humanProgress)
  }

  // WHY THE DRAWN POSITIONS ARE PROJECTED ONTO THE ENGINE'S ORDER.
  //
  // The callouts are fired from the engine's order, which is exact and
  // instantaneous. The karts are drawn from a smoothed copy of effective
  // progress, so that a kart glides between the engine's ten-per-second steps
  // instead of jumping. Those two disagree while the smoothing catches up, and
  // measured over a real race the disagreement ran for 176 consecutive frames
  // -- 2.8 s at the 62.5 fps this build measures, longer than the 1.6 s the
  // callout is on screen. That is a `PASSED GASKET` over a Gasket that is
  // still drawn in front, which is what the round-one critique caught.
  //
  // This is the fix, and it is one line of caller: project the smoothed values
  // onto the true order. Walking from the leader, any kart the engine says is
  // behind is pulled back to at most the position of the kart in front of it.
  // The projection only ever moves a kart backwards, so nothing lurches
  // forward; a kart that has just been passed sits level for a frame or two
  // and then falls away as the smoothing resolves, which is what being passed
  // looks like. With no `order` argument the behaviour is exactly as before.
  function orderedProgress(values, order) {
    if (!order || order.length === 0)
      return values
    var row = ({})
    for (var i = 0; i < kartModel.count; i++)
      row[kartModel.get(i).kartId] = i
    var out = values.slice()
    var cap = Number.POSITIVE_INFINITY
    for (var k = 0; k < order.length; k++) {
      var at = row[order[k]]
      if (at === undefined || at >= out.length)
        continue
      if (out[at] > cap)
        out[at] = cap
      cap = out[at]
    }
    return out
  }

  // ------------------------------------------------------------ the clock
  // Called by Race.qml's FrameAnimation. Nothing in this file starts a timer
  // of its own, so a closed overlay costs the shell nothing.
  function advance(dtMs) {
    if (paused)
      return
    var raw = Math.max(0, Math.min(80, dtMs))

    // PIECE F -- THE EFFECT CLOCK RUNS EVEN WHEN THE WORLD DOES NOT.
    //
    // Two things below hold the world still and neither may hold the effects
    // still with it:
    //
    //   * a hit-stop. Design v4: "the world freezes for 60 to 120 ms at the
    //     moment of impact ... The FrameAnimation delta is held at zero; input
    //     is not." A freeze that also froze the spark burst would be a dropped
    //     frame, not a hit-stop -- the point of the trick is that the impact
    //     plays while the road holds.
    //   * reduced motion, under which nothing about the camera moves at all,
    //     but a flash still has to fade and a `+8` tag still has to appear and
    //     go. Those are exactly the substitutes the design names.
    //
    // So the effect clock is advanced first, unconditionally, and every effect
    // in this file is a pure function of it. That is also what makes a frame
    // strip reproducible: `dev/Harness.qml --strip` steps this clock by a fixed
    // number of milliseconds per frame instead of letting a FrameAnimation
    // sample the wall clock, and the same strip written twice is the same bytes.
    fxClock += raw
    fxAdvance()

    if (reducedMotion) {
      // REDUCED MOTION IS NOT A PAUSE BUTTON.
      //
      // ROUND 2. This used to `return` here, which stopped `travel` -- so a
      // child with the setting on got a racing game in which THE ROAD DOES NOT
      // MOVE. A blind critic measured it on both builds in this run: consecutive
      // road-region frame differences of exactly 0.000 for thirteen of twenty
      // frames. The design's static perspective plane is a PERFORMANCE floor
      // ("if even that is too slow"), not what the setting means, and what the
      // setting means is written a line above it: "reduced motion removes all
      // shake, lurch, and streak lines", and in the power-up section, "replaces
      // hit-stop, shake, and spins with flashes and tag changes". None of those
      // is the road going by. A child with the setting on is still driving.
      //
      // So: the shake, the lurch, the pull-back, the whip and the hit-stop are
      // all gone -- the speed lines, afterimages, spins, bounces and the
      // projectile's flight are gone elsewhere, in `CardFx.reducedOut` -- and
      // the road scrolls at the speed the engine says the child is going.
      lurch = 0
      pullback = 0
      shake = 0
      shakeX = 0
      shakeY = 0
      var still = raw / 1000
      var pace = speed * 26
      travel += pace * still
      heading += curve * pace * still * 118
      if (!shaderMode)
        roadCanvas.requestPaint()
      return
    }

    // The hit-stop itself. The road, the karts, the camera and the shake all
    // hold exactly where they were; `fxClock` above has already moved on, so
    // the impact that caused the freeze is playing over a still world.
    if (fxClock < freezeUntil)
      return

    var dt = raw / 1000
    // Pile-Up's "then 300 at half speed". One multiplier on the world's own
    // delta, so everything the camera does slows together and the effects do
    // not.
    if (fxClock < slowUntil)
      dt *= slowScale

    var rate = speed * 26 + lurch * 90
    rate *= (1 - Math.min(0.95, pullback * 1.05))
    travel += rate * dt
    heading += curve * rate * dt * 118
    // `curve` and `horizon` follow `travel` by binding, from the sector table
    // above. Nothing is assigned here: a corner is a property of where you are
    // on the circuit, not of when this function last ran.

    lurch = Math.max(0, lurch - dt * 1.5)
    pullback = Math.max(0, pullback - dt * 1.35)
    shake = Math.max(0, shake - dt * 2.6)
    // THE CAMERA MOVES BY A FRACTION OF THE SCREEN, NOT BY NINE PIXELS.
    //
    // ROUND 2. These were the constants 9 and 6, in pixels, which is 0.47% of a
    // 1920-wide frame -- and a blind critic looking at the strips reported "no
    // camera work of any kind ... no shake I can detect in the frames". The
    // shake was there and it was below the threshold of a picture. It is a
    // fraction of the frame now, so it is the same shake at every size, and it
    // is about three times what it was.
    if (shake > 0) {
      var phase = travel * 3.1
      shakeX = Math.sin(phase * 6.3) * shake * width * 0.0155
      shakeY = Math.cos(phase * 8.1) * shake * height * 0.0125
    } else {
      shakeX = 0
      shakeY = 0
    }
    // ... and the whip, which is not a shake: one big swing out and back, so a
    // Tow Hook reads as the camera being dragged round to follow the swap.
    // Design, Tow Hook: "the camera whips to follow".
    if (whipNow !== 0) {
      shakeX += whipNow * width * 0.066
      shakeY += Math.abs(whipNow) * height * 0.020
    }

    if (!shaderMode)
      roadCanvas.requestPaint()
  }

  // Design, Motion: "a road lurch on Turbo, a horizon pull-back on being hit".
  function throwForward(strength) {
    if (reducedMotion)
      return
    lurch = Math.min(1, lurch + strength)
    shake = Math.min(1, shake + strength * 0.45)
  }
  function pullBack(strength) {
    if (reducedMotion)
      return
    pullback = Math.min(1, pullback + strength)
    shake = Math.min(1, shake + strength * 0.80)
  }

  // GOLDEN-HOUR PALETTE. Sampled off the bar (plan v2, "Visual direction v3"):
  // near-black purple ground, neon magenta grid, purple-tinted tarmac, the
  // horizon glow and the sun's pink-orange spill. Held here rather than in the
  // shader so both renderers read one set of numbers. The design's themed
  // ground (`Theme.ground`) is not used by the floor.
  readonly property color groundTone: "#3c1228"
  readonly property color gridTone: "#ff4fa3"
  // THE DISTANCE IS THE GLOW, NOT A DEEPER DARK.
  //
  // This was `#3a1032` -- a purple DARKER than the ground it was supposed to
  // be fading the ground into. Design, The view: "The floor is the diagnostic
  // grid in neon over near-black purple, fading into the glow"; plan v2's
  // palette table: "grid lines #ff4fa3 at ~0.35 alpha fading into the glow".
  // The far floor was fading into a hole instead, which is most of why the
  // vanishing point read as nothing at all. `#d75d6b` is the palette table's
  // own horizon-glow stop and is the colour SunsetSky puts on the horizon
  // line, so the floor and the sky now meet in one tone.
  readonly property color fogTone: "#d75d6b"
  readonly property color roadTone: "#221420"
  readonly property color roadToneAlt: "#2c1a2a"
  readonly property color laneTone: Theme.cream
  readonly property color sunTone: "#f0956e"
  // What fraction of the floor's fog density the tarmac and its kerbs take.
  // At 1.0 -- which is what shipped -- the road reached the fog's colour at
  // the same distance the floor did and the two became one number: measured
  // on the shipped 1920x1080 frame, |road - floor| luminance was under 7 from
  // z = 30 outward. At 0.30 the road holds a dark ribbon with bright kerbs
  // out past where the curve carries it off the side of the frame.
  readonly property real surfaceFog: 0.30
  readonly property real sunU: 0.68
  readonly property real gridAlpha: 0.35
  // The road's far-centre offset in plane pixels, for the hills' parallax:
  // `uAt` at the depth of the far road is 0.5 + curve z focal / (2 aspect),
  // which at z = 18.3 on a 480-wide plane is 2963 * curve.
  readonly property real lateralPlanePx: curve * 2963

  // --------------------------------------------------------- shader or not
  // Two ways the shader path is refused, and both have to be handled or the
  // screen is simply black on the machines that hit them:
  //
  //   * the shader fails to compile -- `status` goes to Error, which is the
  //     case the design's fallback exists for;
  //   * there is no shader pipeline at all, which is what a software-rendered
  //     Qt Quick scene graph is. A ShaderEffect there never compiles anything
  //     and never reports an error; it just draws nothing. `GraphicsInfo.api`
  //     is the only thing that says so, and it says so before the first frame.
  property bool shaderFailed: false
  readonly property bool softwareScene: GraphicsInfo.api === GraphicsInfo.Software
                                        || GraphicsInfo.api === GraphicsInfo.Unknown
  // Forces the fallback for a side-by-side comparison. Never set in play.
  property bool forceCanvas: false
  readonly property bool shaderMode: !softwareScene && !shaderFailed && !forceCanvas
  readonly property string roadPath: shaderMode
                                     ? "shader"
                                     : (softwareScene ? "canvas (software scene graph)"
                                        : (shaderFailed ? "canvas (shader refused)" : "canvas (forced)"))

  function noteShaderStatus(status) {
    if (status === ShaderEffect.Error) {
      console.log("TrackView: road shader did not compile, falling back to CanvasRoad\n"
                  + roadShader.log)
      view.shaderFailed = true
    }
  }

  Component.onCompleted: console.log("TrackView: road path = " + roadPath)

  // ------------------------------------------------------------- the road
  clip: true

  Item {
    id: plane
    width: 480
    height: 270
    x: view.shakeX
    y: view.shakeY
    transform: Scale {
      xScale: view.width / 480
      yScale: view.height / 270
    }

    // The layer is what makes the shader's fragment work an eighth of 1080p.
    // It stays on for the canvas fallback too, now that the plane is five
    // items rather than one: composed at 480 x 270 and blitted once, the
    // software renderer measures 63 fps at 1080p on this Mac; with each item
    // scaled up on its own it measured 48. (Before the sky moved in here the
    // layer was off in canvas mode, because one canvas needs no copy.)
    layer.enabled: true
    layer.smooth: false
    layer.textureSize: Qt.size(480, 270)

    // The sky, behind the floor. Inside the plane so it renders at 480 x 270
    // and scales up with the same nearest-neighbour filter as the road.
    SunsetSky {
      anchors.fill: parent
      horizon: view.horizon
      lateral: view.lateralPlanePx
      sunX: view.sunU
    }

    ShaderEffect {
      id: roadShader
      anchors.fill: parent
      visible: view.shaderMode
      // Transparent above the horizon, where the sky item shows through.
      blending: true
      fragmentShader: Qt.resolvedUrl("../shaders/road.frag.qsb")

      property real horizon: view.horizon
      property real camHeight: view.camHeight
      property real focal: view.focal
      property real aspect: view.aspect
      property real travel: view.travel
      property real curve: view.curve
      property real roadHalf: view.roadHalf
      property real rumbleHalf: view.rumbleHalf
      property real stripe: view.stripe
      property real gridScale: view.gridScale
      property real fogDensity: 1.0
      property real surfaceFog: view.surfaceFog
      property real glowAmount: 1.0
      property real gridAlpha: view.gridAlpha
      property real sunU: view.sunU
      property real glowRx: 0.24
      property real glowRy: 0.08

      property color roadColor: view.roadTone
      property color roadAlt: view.roadToneAlt
      property color rumbleColor: Theme.hazard
      property color rumbleAlt: Theme.cream
      property color laneColor: view.laneTone
      property color groundColor: view.groundTone
      property color gridColor: view.gridTone
      property color skyColor: view.fogTone
      property color fogColor: view.fogTone
      property color glowColor: view.sunTone

      onStatusChanged: view.noteShaderStatus(status)
    }

    CanvasRoad {
      id: roadCanvas
      anchors.fill: parent
      visible: !view.shaderMode

      horizon: view.horizon
      camHeight: view.camHeight
      focal: view.focal
      aspect: view.aspect
      travel: view.travel
      curve: view.curve
      roadHalf: view.roadHalf
      rumbleHalf: view.rumbleHalf
      stripe: view.stripe
      gridScale: view.gridScale
      drawDistance: view.drawDistance
      nearDistance: view.nearDistance

      surfaceFog: view.surfaceFog
      glowAmount: 1.0
      gridAlpha: view.gridAlpha
      sunU: view.sunU
      glowRx: 0.24
      glowRy: 0.08

      roadColor: view.roadTone
      roadAlt: view.roadToneAlt
      rumbleColor: Theme.hazard
      rumbleAlt: Theme.cream
      laneColor: view.laneTone
      groundColor: view.groundTone
      gridColor: view.gridTone
      skyColor: view.fogTone
      fogColor: view.fogTone
      glowColor: view.sunTone

      // Under reduced motion nothing calls advance(), so the plane repaints
      // only when the camera itself changes -- which is the static plane the
      // design's floor asks for.
      onHorizonChanged: requestPaint()
      onFocalChanged: requestPaint()
      onWidthChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }
  }

  // ------------------------------------------------------------ the backdrop
  // Was the far wall of the garage. In this prototype the far end of the road
  // is the sunset: SunsetSky, drawn inside the plane above, with the hills
  // standing on the horizon and parallaxing with the curve.

  // ------------------------------------------------------------- streaks
  // Design, Accessibility: "Reduced motion removes all shake, lurch, and
  // streak lines." These are the streak lines: short light trails running out
  // from the vanishing point, fading in with speed and gone entirely when the
  // setting is on.
  Item {
    id: streaks
    anchors.fill: parent
    visible: !view.reducedMotion && view.speed > 0.12
    opacity: Math.max(0, Math.min(0.42, (view.speed - 0.12) * 0.45 + view.lurch * 0.55))
    z: 5

    readonly property real vx: view.uAt(0, 6000) * view.width + view.shakeX
    readonly property real vy: view.horizon * view.height + view.shakeY

    Repeater {
      model: 14

      Rectangle {
        readonly property real ang: (index / 14) * Math.PI * 2 + 0.21
        readonly property real phase: {
          var p = (view.travel * 0.055 + index * 0.137) % 1
          return p < 0 ? p + 1 : p
        }
        readonly property real reach: phase * phase * Math.max(view.width, view.height) * 1.05

        width: Math.max(6, 26 + phase * 96)
        height: Math.max(1, Math.round(1 + phase * 2))
        color: Theme.cream
        opacity: (1 - phase) * 0.85
        antialiasing: false
        transformOrigin: Item.Center
        x: streaks.vx + Math.cos(ang) * reach - width / 2
        y: streaks.vy + Math.sin(ang) * reach * 0.62 - height / 2
        rotation: Math.atan2(Math.sin(ang) * 0.62, Math.cos(ang)) * 180 / Math.PI
      }
    }
  }

  // ---------------------------------------------------------- the props
  // The roadside, indexed off the same circuit the corners are.
  //
  // Design, The view: "a closed circuit of twelve sectors, one per lap-table,
  // each with its own landmark: the twos pass the tire wall, the sevens run
  // under the roller door". So each of the twelve sectors opens with its own
  // signature landmark and then carries two pieces of ordinary furniture, and
  // the loop the props run on is the same 432 units the sector table runs on:
  // the roller door is in sector 4's corner on every lap of every race.
  //
  // Thirty-six items rather than twelve, but the draw cost is unchanged: the
  // draw distance is 190 world units and the spacing is 12, so about sixteen
  // are ever visible and the rest are culled before they reach the scene
  // graph. Each is drawn once into its own canvas at startup and only ever
  // moved and scaled after that.
  //
  // GOLDEN-HOUR PROTOTYPE. The grey lamp posts and the teal diagnostic signs
  // are gone; the roadside is the genre's: sponsor banners, tyre walls, a
  // timing board, the checkered start gantry in sector 0, and the design's
  // roller doors in sectors 4 and 9.
  readonly property var sectorLandmark: ["gantry", "banner", "tireWall", "timingBoard",
                                         "rollerDoor", "tireWall", "banner", "drum",
                                         "timingBoard", "rollerDoor", "banner", "tireWall"]
  readonly property var sectorFiller: ["cone", "banner", "drum", "tireWall",
                                       "banner", "cone"]

  // ARCHES AND THE ANSWER FIELD: THE FIELD IS WHAT YIELDS.
  //
  // Plan v2, Risks: "Arches vs. the fixed answer field | M4': props that span
  // the road cross under the field's line OR THE FIELD YIELDS FOR THE FRAME."
  // Two remedies. Round four took neither: it measured the arches against the
  // FACT -- a different object, further up the screen; on a 1920x1080 race
  // screen the fact's ink ends at y = 286 and the field's box is y 345..443 --
  // reported no overlap with it, and then suppressed the arches. Measured
  // against the object the plan actually names, a crossbar is inside the
  // field's rows at EVERY depth in the draw distance: y 312..389 at z = 10,
  // 375..413 at z = 20, 406..425 at z = 40, 421..431 at z = 80. So the
  // criterion was unmet everywhere, and the two landmarks the design names by
  // name -- "the sevens run under the roller door" -- had been traded away for
  // nothing.
  //
  // The first remedy really is unavailable, and the arithmetic says so rather
  // than an opinion. An arch stands on the road and spans it, so its crossbar
  // is at
  //
  //     yBeam(z) = vAt(z) H - sizeAt(archHeight, z) (1 - archBeamTop)
  //
  // and with the shipped numbers -- a 9.4-unit span on a 320 x 200 sheet, so
  // 5.875 units tall, focal 1.20, camHeight 2.20, H = 1080 -- that is above
  // the field's bottom edge for every depth inside the draw distance at which
  // an arch is legible at all. There is no depth at which a road-spanning arch
  // passes UNDER a box that sits above the horizon.
  //
  // SO THE FIELD YIELDS. `fieldRect` is the answer field's box on this screen,
  // handed down by Race.qml from the item's own geometry rather than assumed
  // here, and `fieldYield` rises to 1 for the second or so in which a
  // road-spanning prop's crossbar is over it. Race.qml fades the field's FACE
  // -- its ground, its border and its sun rim -- and leaves the digits, the
  // caret and the reveal at full strength, so nothing the child typed goes
  // anywhere: the arch is seen through the slab instead of being sliced by it.
  // It is a paint change and not a behaviour change, which is the whole reason
  // this is the remedy the plan offers. A bare TrackView in the harness gets an
  // empty rect and nothing ever yields.
  //
  // AND THE ARCHES ARE BACK. Nothing throttles them at any depth: a child sees
  // the gantry and the roller door come up the road, fill the frame and pass
  // over them, which is what the sector landmarks are for.
  property rect fieldRect: Qt.rect(0, 0, 0, 0)
  // The fact's ink box, for the same reason. The fact does not yield -- it is
  // the pillar the design will not trade -- so what this drives is the ground
  // Race.qml puts UNDER the glyphs for the frames a crossbar is behind them.
  // The fact is drawn over every prop either way; what a chequered beam takes
  // from it is contrast, not visibility, and a ground is the answer to that.
  property rect factRect: Qt.rect(0, 0, 0, 0)
  // The arch sheet is 320 x 200, so an arch is 0.625 of its span tall; the
  // crossbar is drawn between 0.30 and 0.50 of the sheet's height (the
  // gantry's beam and the roller door's lintel, both in ui/parts/PropSprite).
  readonly property real archAspect: 200 / 320
  readonly property real archBeamTop: 0.30
  readonly property real archBeamBottom: 0.50
  readonly property real archSpan: 9.4
  function archTopAt(worldWidth, z) {
    return vAt(z) * height - sizeAt(worldWidth * archAspect, z)
  }

  // Which props on the loop span the road. Computed once: `propKind` is a table
  // lookup and this is read on every frame.
  readonly property var archProps: {
    var out = []
    for (var i = 0; i < propCount; i++) {
      var k = propKind(i)
      if (k === "rollerDoor" || k === "gantry")
        out.push(i)
    }
    return out
  }

  // HOW FAR INTO YIELDING THE FIELD IS: BY HOW MUCH, NOT WHETHER AT ALL.
  //
  // The first cut of this yielded whenever a crossbar touched the box, and
  // measured over the whole circuit that was 40% of a lap: arches converge on
  // the vanishing point and the field's bottom edge sits a few pixels below the
  // horizon, so there is nearly always SOME arch out at z = 80 whose eight-pixel
  // beam clips the field's last few rows. A field that is absent for two fifths
  // of a lap has not yielded, it has been deleted.
  //
  // So the yield is proportional to how much of the field the crossbar is
  // actually behind -- the fraction of the box's AREA it covers -- and reaches
  // 1 at `fieldYieldAt`. A hairline near the horizon moves it by a couple of
  // per cent, which is invisible; the gantry that would be sliced covers a third
  // of the box and takes the face away completely.
  readonly property real fieldYieldAt: 0.25

  // How strongly a road-spanning prop's crossbar is over `box`, 0..1. Every
  // property it reads is live, so a binding written against it re-evaluates
  // with `travel` exactly as the props themselves do.
  function crossingOver(box) {
    if (box.width <= 0 || box.height <= 0)
      return 0
    var worst = 0
    for (var i = 0; i < archProps.length; i++) {
      var raw = (archProps[i] * propSpacing - travel) % propLoop
      var z = (raw < 0 ? raw + propLoop : raw) + nearDistance
      if (z <= nearDistance + 0.2 || z >= drawDistance)
        continue
      var top = archTopAt(archSpan, z)
      var stand = vAt(z) * height
      var beam0 = top + (stand - top) * archBeamTop
      var beam1 = top + (stand - top) * archBeamBottom
      var halfW = sizeAt(archSpan, z) / 2
      var cx = uAt(0, z) * width + shakeX
      var down = Math.min(beam1, box.y + box.height) - Math.max(beam0, box.y)
      var across = Math.min(cx + halfW, box.x + box.width) - Math.max(cx - halfW, box.x)
      if (down <= 0 || across <= 0)
        continue
      var covered = (down / box.height) * (across / box.width)
      worst = Math.max(worst, Math.min(1, covered / fieldYieldAt))
      if (worst >= 1)
        break
    }
    return worst
  }

  readonly property real fieldYield: crossingOver(fieldRect)
  readonly property real factYield: crossingOver(factRect)

  // NEAR PROPS FADE, AND EVERY CLASS OBEYS IT.
  //
  // Round four applied its throttle to `arch` kinds alone, so the two props
  // the design names as landmarks were the ONLY ones ever dimmed while every
  // other class was exempt at any size. A critic measured one 3-unit tyre wall
  // filling x 1250-1920, y 100-730 on a shipped frame -- 35% of it, top edge
  // 336 px ABOVE the horizon -- and round five reproduced it on the SHADER path
  // at t = 18 s: x 1155-1410, y 265-570, top edge 171 px above the horizon,
  // over the sun and the right-hand hills. The prop that was a landmark was
  // suppressed and the prop that wrecked the frame was not.
  //
  // The rule is now on DRAWN SIZE and every roadside class obeys it: a prop
  // dissolves as it sweeps past the lens, from the depth at which it is
  // `nearFadeFrom` of the frame's height to `nearFadeGone` of it. That band is
  // about four tenths of a second of transit at racing speed, which is where a
  // near prop is a blur anyway.
  //
  // Road-spanning props are exempt, and that is the point of them: an arch you
  // pass under is meant to fill the frame, and the road goes through its
  // opening rather than behind it.
  readonly property real propAspect: 176 / 128
  readonly property real nearFadeFrom: 0.45
  readonly property real nearFadeGone: 0.85
  function nearFade(worldWidth, z) {
    var frac = sizeAt(worldWidth * propAspect, z) / Math.max(1, height)
    if (frac <= nearFadeFrom)
      return 1
    if (frac >= nearFadeGone)
      return 0
    return 1 - (frac - nearFadeFrom) / (nearFadeGone - nearFadeFrom)
  }
  // The one place a prop's opacity is decided, so a test can ask the view the
  // same question the delegate asks it.
  function propOpacity(spanning, worldWidth, z) {
    return spanning ? 1 : nearFade(worldWidth, z)
  }
  readonly property var bannerLabels: ["TURBO", "PIT", "BOLT", "PISTON", "GASKET"]
  // Eight units, not twelve: at twelve the roadside read as two thin rows of
  // specks. About twenty-four are visible at once; each is one textured quad.
  readonly property real propSpacing: 8.0
  readonly property int propCount: Math.round(circuitLength / propSpacing)
  readonly property real propLoop: circuitLength

  function propKind(index) {
    var slot = index % 3
    if (slot === 0)
      return sectorLandmark[Math.floor(index / 3) % sectorCount]
    return sectorFiller[index % sectorFiller.length]
  }

  Repeater {
    model: view.propCount

    Item {
      readonly property string myKind: view.propKind(index)
      readonly property bool arch: myKind === "rollerDoor" || myKind === "gantry"
      readonly property real worldWidth: arch ? 9.4
                                         : (myKind === "tireWall" ? 3.0
                                            : (myKind === "banner" ? 3.2
                                               : (myKind === "timingBoard" ? 2.0 : 1.35)))
      readonly property real zed: {
        var raw = (index * view.propSpacing - view.travel) % view.propLoop
        return (raw < 0 ? raw + view.propLoop : raw) + view.nearDistance
      }
      // Alternating sides, at three different distances off the kerb, so the
      // roadside is a place rather than two parallel rows.
      readonly property real lateral: arch
                                      ? 0
                                      : (index % 2 === 0 ? -1 : 1)
                                        * (view.roadHalf + view.rumbleHalf
                                           + [0.75, 1.55, 2.60][index % 3])
      readonly property real sc: view.sizeAt(worldWidth, zed) / furniture.sheetW

      x: view.uAt(lateral, zed) * view.width + view.shakeX
      y: view.vAt(zed) * view.height + view.shakeY
      width: 0
      height: 0
      z: 1000 - zed
      opacity: view.propOpacity(arch, worldWidth, zed)
      visible: zed > view.nearDistance + 0.2 && zed < view.drawDistance
               && sc > 0.010 && x > -view.width * 0.7 && x < view.width * 1.7
               && opacity > 0.004

      PropSprite {
        id: furniture
        kind: parent.myKind
        label: parent.myKind === "gantry" ? "TURBO" : view.bannerLabels[index % view.bannerLabels.length]
        // Three steps of distance dimming, quantised on purpose: `dim` is the
        // one sprite property that repaints the canvas, so it must not be a
        // continuous function of a position that changes every frame.
        dim: Math.max(0.34, Math.round(Math.max(0.34, 1.08 - parent.zed / 120) * 3) / 3)
        x: -sheetW / 2
        y: -sheetH
        scale: parent.sc
      }
    }
  }

  // ---------------------------------------------------------- the karts
  // Back to front by depth, which the scene graph does from `z`, so the
  // drawing order is a property of where the karts are and cannot fall out of
  // step with them.
  Repeater {
    model: kartModel

    Item {
      id: slot
      // The model carries the paint as a string, because a ListModel role is
      // typed by the first value put in it and a colour round-trips through a
      // string safely. The sheet is chosen by paint INDEX, so the string is
      // matched back to the theme's eight paints here; a paint the theme does
      // not know falls back to the first.
      readonly property color paintCol: kartPaint
      readonly property int paintIdx: {
        for (var i = 0; i < Theme.paints.length; i++)
          if (Qt.colorEqual(Theme.paints[i], paintCol))
            return i
        return 0
      }
      readonly property real delta: isHuman ? 0 : (kartProgress - view.humanProgress)
      readonly property real zed: isHuman ? view.playerZ : view.zForDelta(delta)
      readonly property var cellFit: view.kartCell(zed)
      // The child's kart bobs a little with speed: the one thing on screen
      // that says the engine is running while the child is thinking.
      readonly property real bob: (isHuman && !view.reducedMotion)
                                  ? Math.sin(view.travel * 0.62) * (1.2 + view.speed * 2.6)
                                  : 0

      // PIECE F. The target state, read off the model's fx roles. Each is zero
      // whenever the kart is not in that state and zero always under reduced
      // motion, so the delegate is exactly what it was when nothing has landed.
      // `view.kartSheetPixels(zed)` is the scale everything is measured
      // against, so a jolt on a far kart is a jolt at that kart's size.
      readonly property real fxSpan: view.kartSheetPixels(zed)
      readonly property real fxDx: view.fxKartDx(index, fxSpan)
      readonly property real fxDy: view.fxKartDy(index, fxSpan)
      readonly property int fxYaw: view.fxKartYaw(index)

      x: view.uAt(view.laneOf(kartSeat), zed) * view.width + view.shakeX + fxDx
      y: view.vAt(zed) * view.height + view.shakeY + bob + fxDy
      width: 0
      height: 0
      // Depth, with a tie-break, because at the start line all four karts are
      // at exactly `playerZ` and `1000 - zed` is then the same number four
      // times -- an undefined stacking order that can flicker between frames.
      // The child's own kart wins the tie; the rest fall back on their seat.
      z: 1000 - zed + (isHuman ? 0.002 : kartSeat * 0.0004)
      visible: zed > view.nearDistance && zed < view.drawDistance
               && x > -view.width * 0.6 && x < view.width * 1.6

      // The car: a sheet cell at the anchor, which is this item's origin --
      // the point the projection put on the road. A ghost is the same car,
      // translucent. The child's own tail lamps glow with the pull-back a hit
      // causes, from the lamp centres the sheet's meta lists.
      CarSprite {
        id: kartArt
        x: 0
        y: 0
        body: kartBody
        paint: slot.paintIdx
        number: kartNumber
        camera: "road"
        // The base column is the road's own tangent (a kart follows the road);
        // `fxYaw` is the wobble, the jolt's one column and the Pile-Up's full
        // eight-column turn, added on and wrapped by CarSprite's own modulo.
        yaw: (isHuman ? 0 : CarMeta.columnForHeading(view.kartHeadingDeg(slot.zed))) + slot.fxYaw
        sheetScale: slot.cellFit.sheetScale
        pixelScale: slot.cellFit.pixelScale
        lampGlow: isHuman ? Math.min(1, view.pullback * 1.4) : 0
        opacity: isGhost ? 0.55 : 1.0
      }
    }
  }

  // ------------------------------------------------------------- the dust
  // A few warm particles kicked up behind the child's kart on a surge. Eight
  // items, created once; each is a small warm square whose position is a
  // binding on `travel` and `lurch`, so a surge costs no allocation and no
  // repaint -- only the scene graph moving eight quads. Gone under reduced
  // motion, with the lurch that drives it.
  Item {
    id: dust
    anchors.fill: parent
    visible: !view.reducedMotion && view.lurch > 0.03
    opacity: Math.min(1, view.lurch * 1.6)
    // In front of the child's kart: dust kicked up behind it is between the
    // kart and the camera.
    z: 1000 - view.playerZ + 0.003

    readonly property real heroX: view.uAt(view.heroLane, view.playerZ) * view.width + view.shakeX
    readonly property real heroY: view.vAt(view.playerZ) * view.height + view.shakeY
    readonly property real span: view.kartSheetPixels(view.playerZ)

    Repeater {
      model: 8

      Rectangle {
        readonly property real phase: {
          var p = (view.travel * 0.19 + index * 0.137) % 1
          return p < 0 ? p + 1 : p
        }
        readonly property real side: (index % 2 === 0 ? -1 : 1) * (0.30 + (index % 4) * 0.10)
        readonly property real size: Math.max(4, Math.round(dust.span * (0.022 + (index % 3) * 0.009) * (1 + phase)))
        width: size
        height: size
        color: index % 3 === 0 ? "#f0b07a" : "#d75d6b"
        opacity: Math.min(1, (1 - phase) * 1.1)
        antialiasing: false
        // Out from the kart's flanks and up, then falling back and spreading
        // toward the camera as `phase` runs 0..1.
        x: dust.heroX + dust.span * side * (0.45 + phase * 0.8) - width / 2
        y: dust.heroY - dust.span * (0.06 + Math.sin(phase * Math.PI) * (0.14 + (index % 3) * 0.05))
           + phase * dust.span * 0.10
      }
    }
  }

  // ---------------------------------------------------------- the plates
  // Every rival's name and how far ahead it is, drawn in a pass of its own
  // ABOVE the roadside furniture.
  //
  // Round one hung the plate inside the kart's own item, gated on the sprite
  // being over 28 px tall, and depth-sorted with everything else. Three things
  // went wrong at once: the two karts actually beating the child were under
  // the gate and unnamed; the three rivals converge near the vanishing point
  // and their plates landed on top of one another; and a tyre wall nearer than
  // a rival drew straight over its plate. A plate is a statement about the
  // race rather than an object in the garage, so it goes over the scenery, it
  // has a floor on its type, and the three are stacked by seat so they cannot
  // collide with each other.
  //
  // The gap is in questions and comes from the same effective progress the
  // engine ranks by, so a plate can never disagree with the place readout.
  function kartSpriteH(z) { return kartSheetPixels(z) * 128 / 192 }

  // A PLATE THAT IS NOT ATTACHED TO A CAR IS A LABEL FLOATING ON THE ROAD.
  //
  // Two critics said the plates "float under or over far cars", and the
  // measurement behind that is the size ratio: at the far floor a rival's
  // sprite is 51 px of sheet wide and its plate reads `PISTON +8` at the
  // 13 px type floor, which is 86 px -- the label is 1.7 times the width of
  // the thing it names, and two of them stack under a pair of cars eight
  // pixels apart. Shrinking the type is not available; 13 px is already the
  // floor for a child at 1080p.
  //
  // So each plate now carries a leader: a one-pixel line in the rival's own
  // paint from the car's contact point on the road down to the top of its
  // plate. It costs one quad, it is drawn in the same pass as the plate so
  // nothing on the roadside can cover it, and it says which car a name
  // belongs to when three of them are converging on the vanishing point.
  //
  // The plate's own ground is the floor's near-black purple at 0.86 rather
  // than pure black, for the same reason everything else in the game layer is
  // purple: the light rule says shadow is purple, never grey. A plate on the
  // road is game layer, not the chrome the plan exempts (Results, Settings,
  // the picker and the HUD panels, which keep the theme's colours).
  readonly property color plateGround: Qt.rgba(groundTone.r, groundTone.g,
                                               groundTone.b, 0.86)

  Repeater {
    model: kartModel

    Item {
      id: badge
      readonly property color paintCol: kartPaint
      readonly property real delta: isHuman ? 0 : (kartProgress - view.humanProgress)
      readonly property real zed: isHuman ? view.playerZ : view.zForDelta(delta)
      readonly property real spriteH: view.kartSpriteH(zed)
      readonly property int gapQuestions: kartGap
      readonly property int tagSize: Math.max(13, Math.min(19, Math.round(spriteH * 0.16)))

      // Ahead of the child, and only ahead: a rival level with or behind them
      // is on the chaser rail below instead. Round two gated this on
      // `zed > playerZ + 1.0`, which left a rival a fifth of a question ahead
      // with no plate at all while its sprite filled a third of the screen.
      visible: !isHuman && !isGhost && delta > 0 && zed < view.drawDistance
      width: tag.implicitWidth + tagGap.implicitWidth + 14
      height: tag.implicitHeight + 6
      z: 2000

      // How many rivals are further up the road than this one. Reading
      // `kartProgress` first is deliberate: it is what makes this a live
      // binding, since it changes on every frame for every kart.
      readonly property int plateRow: {
        var mine = kartProgress
        var rank = 0
        for (var i = 0; i < kartModel.count; i++) {
          var k = kartModel.get(i)
          if (k.isHuman)
            continue
          if (k.kartProgress > mine
              || (k.kartProgress === mine && k.kartSeat < kartSeat))
            rank += 1
        }
        return rank
      }

      x: view.uAt(view.laneOf(kartSeat), zed) * view.width + view.shakeX - width / 2
      // BELOW the kart, stacked downward, furthest-away first.
      //
      // Above the kart was the obvious place and it was wrong twice. Three
      // rivals converge on the vanishing point on a straight, so one row of
      // clearance each is needed; and the vanishing point rises to y = 408 at
      // the crest of a gradient, so a stack of three above it reaches y = 332
      // and lands behind the answer field, which lives in the sky. Below the
      // kart there is nothing but road all the way down, at every horizon and
      // every gradient, so a plate can never reach the fact or the field.
      //
      // The row is the kart's rank by distance, not its seat. A fixed per-seat
      // offset only separates plates when the karts are at the same depth; at
      // 1366x768 two rivals a row apart in seat and a row apart in depth landed
      // on the same line and read as `PISTONOLT`. Ranking by distance makes the
      // offsets and the depths pull the same way, so the vertical gap between
      // two plates is at least one row however the field is spread.
      readonly property real leader: 3 + plateRow * (height + 3)
      y: view.vAt(zed) * view.height + view.shakeY + leader

      // The leader: from the car's contact point on the road down to this
      // plate. `badge.x` is the car's own projected centre less half the
      // plate's width, so `width / 2` is exactly under the car.
      Rectangle {
        x: Math.round(badge.width / 2)
        y: -badge.leader
        width: 1
        height: badge.leader
        antialiasing: false
        color: Qt.rgba(badge.paintCol.r, badge.paintCol.g, badge.paintCol.b, 0.85)
      }

      Rectangle {
        anchors.fill: parent
        radius: 3
        color: view.plateGround
        border.width: view.fxPlateRing(index) > 0.05 ? 2 : 1
        border.color: view.fxPlateRing(index) > 0.05
                      ? Qt.rgba(1, 1, 1, 0.35 + 0.65 * view.fxPlateRing(index))
                      : Qt.rgba(badge.paintCol.r, badge.paintCol.g, badge.paintCol.b, 0.95)
      }

      Row {
        anchors.centerIn: parent
        spacing: 6

        Text {
          id: tag
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: kartName
          color: Theme.textBright
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: badge.tagSize
          font.letterSpacing: 1
        }

        Text {
          id: tagGap
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          // What the effect did, when there is one, and the gap otherwise. See
          // the `fxPlate` roles: this is the readout a rival keeps when the
          // projection has taken their kart away.
          text: view.fxPlateShowing(index)
                ? fxPlate
                : (badge.gapQuestions > 0 ? "+" + badge.gapQuestions : "")
          color: view.fxPlateShowing(index) ? fxPlateTone : Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: badge.tagSize
        }
      }
    }
  }

  // ------------------------------------------------------- the chaser rail
  //
  // WHO IS BEHIND YOU. The other half of the race, and until now the missing
  // half.
  //
  // The camera sits behind the child's kart, so a rival even one question back
  // is behind the lens: `zForDelta(-1)` is -0.8, below `nearDistance`, and the
  // sprite is culled -- correctly, because there is nowhere on this road that a
  // kart behind the camera honestly goes. Round two left it there, and the
  // whole picture of the race went dark the moment the child took the lead.
  // Measured on the drawn geometry, with the child answering steadily: 1516 of
  // 1875 frames on seed 42 carried no rival at all, 1398 of 1875 on seed 3,
  // 1062 of 1875 on seed 11 -- and the longest unbroken run of empty road was
  // 1217 frames, about nineteen seconds. `PLACE 1st` and an 18 px map were the
  // entire report on three other karts.
  //
  // So the rivals behind are drawn as a rail across the near edge of the road,
  // under the child's own kart, each in its own lane so left and right still
  // mean left and right, closest at the bottom. It is the ahead-plate turned
  // round: the same black plate, the same paint border, the same name, and the
  // gap with its own sign -- `BOLT -3` reads against `PISTON +7` without
  // anything new to learn. The chevron says which way the number points.
  //
  // It is not the deleted standings ladder and it must not become one. It never
  // ranks the field, never says who is last and never labels the child; it
  // states, of one named rival, how far back that rival is -- which is exactly
  // and only what the plate on the road already states for a rival in front.
  readonly property real chaserSize: Math.max(13, Math.round(height * 0.017))

  Repeater {
    model: kartModel

    Item {
      id: chaser
      readonly property color paintCol: kartPaint
      readonly property real delta: isHuman ? 0 : (kartProgress - view.humanProgress)
      readonly property int gapQuestions: kartGap
      // Level counts as behind: a rival that has drawn alongside is one the
      // child cannot see out of the back of their own kart either.
      visible: !isHuman && !isGhost && delta <= 0

      // Closest chaser at the bottom, which is the one arriving. Reading
      // `kartProgress` first is what makes this a live binding, the same
      // reason `plateRow` above reads it first.
      readonly property int chaserRow: {
        var mine = kartProgress
        var rank = 0
        for (var i = 0; i < kartModel.count; i++) {
          var k = kartModel.get(i)
          if (k.isHuman || k.kartProgress > view.humanProgress)
            continue
          if (k.kartProgress > mine
              || (k.kartProgress === mine && k.kartSeat < kartSeat))
            rank += 1
        }
        return rank
      }

      width: chaserRow0.implicitWidth + 14
      height: chaserRow0.implicitHeight + 8
      z: 2000

      // The lane the rival is in, projected at the child's own depth, so a kart
      // coming up the inside is drawn on the inside. Clamped into the view so a
      // wide lane in a hard corner cannot push a plate off the edge.
      x: Math.max(6, Math.min(view.width - width - 6,
                              view.uAt(view.laneOf(kartSeat), view.playerZ) * view.width
                              + view.shakeX - width / 2))
      // Under the child's kart, stacking downward, closest first. The child's
      // kart stands on `vAt(playerZ)` and nothing else is drawn below it.
      y: Math.min(view.height - height - 6,
                  view.vAt(view.playerZ) * view.height + view.shakeY + 10
                  + chaserRow * (height + 4))

      Rectangle {
        anchors.fill: parent
        radius: 3
        color: view.plateGround
        // Two pixels of border when the rival is within one question: the
        // child is about to be passed and the plate says so without a word.
        border.width: (view.fxPlateRing(index) > 0.05
                       || (view.haveExact && chaser.gapQuestions >= -1)) ? 2 : 1
        border.color: view.fxPlateRing(index) > 0.05
                      ? Qt.rgba(1, 1, 1, 0.35 + 0.65 * view.fxPlateRing(index))
                      : Qt.rgba(chaser.paintCol.r, chaser.paintCol.g,
                                chaser.paintCol.b, 0.95)
      }

      Row {
        id: chaserRow0
        anchors.centerIn: parent
        spacing: 6

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "▼"
          color: Qt.rgba(chaser.paintCol.r, chaser.paintCol.g, chaser.paintCol.b, 1)
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: view.chaserSize
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: kartName
          color: Theme.textBright
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: view.chaserSize
          font.letterSpacing: 1
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          // Only when the caller supplied the engine's exact progress. Rounding
          // the smoothed delta instead is wrong on a sixth of frames, and a
          // plate that disagrees with the HUD is two sources of truth for one
          // number -- the same rule the ahead-plate is held to.
          //
          // ... and what the effect did, while there is one. A Wrench sends a
          // rival who was one question up to four behind, where the camera
          // cannot follow them; this rail is where the child reads that it
          // landed. See the `fxPlate` roles.
          text: view.fxPlateShowing(index)
                ? fxPlate
                : (view.haveExact ? String(chaser.gapQuestions) : "")
          color: view.fxPlateShowing(index) ? fxPlateTone : Theme.teal
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: view.chaserSize
        }
      }
    }
  }

  // ==========================================================================
  // PIECE F -- FEEL. The effect layer.
  // ==========================================================================
  //
  // `docs/design.md` v4, "Power-up feel", is the specification for everything
  // below it. The maintainer played the build, said it was fun, and said the
  // power-ups had to feel impactful: every card was strong in the rules and
  // invisible on the screen. This is the screen half of that, and it changes no
  // rule at all -- every effect here is a VIEW of an event `src/engine/` already
  // emits (`cardUsed`, `hit`, `blocked`, `swap`, `handDealt`). Nothing in this
  // block reads a card's delta, decides whether an attack lands, or knows what
  // a Roll Cage does; it is told, by `ui/Race.qml`, and it draws.
  //
  // FIVE TOOLS, from the design's own grammar table, in the mixes it lists per
  // card: hit-stop, a projectile that travels in z along the road, target state
  // on the victim's kart, a world flash and shake, and a HUD echo. Their
  // timings are `ui/parts/CardFx.js`, transcribed from the design once so this
  // file and `ui/Race.qml` cannot drift from it or from each other.
  //
  // NOTHING HERE ANIMATES ITSELF. There is no NumberAnimation, no
  // SequentialAnimation and no Timer in the whole effect layer. Every drawn
  // property is a pure function of `fxClock - born` against the beat table,
  // and `fxClock` is stepped by `advance()`. Three things follow, and the third
  // is why it is written this way:
  //
  //   * a hit-stop can hold the world while the impact plays, because the two
  //     clocks are different clocks;
  //   * reduced motion can take the movement out without taking the event out,
  //     because every substitute is a different function of the same clock;
  //   * a frame strip is REPRODUCIBLE. `dev/Harness.qml --strip` stops the
  //     FrameAnimation, steps this clock by a fixed number of milliseconds and
  //     grabs a frame each time, so the same strip written twice is the same
  //     bytes -- which is the difference between evidence and an anecdote.
  //
  // TWO RULES THAT KEEP IT A KIDS' GAME, and both are enforced here rather than
  // asserted in a report:
  //
  //   * NOTHING EVER COVERS THE FACT. `fxGuardTop` is the one place that is
  //     decided: no effect item's box may enter the answer field's box or the
  //     fact's ink box, and anything that would (a tag over a far kart, the
  //     Pile-Up falling in from the top of the frame) is pushed below them.
  //     Every effect item carries an `objectName`, so `--dump-rects` prints its
  //     box beside the fact's and the two can be shown not to intersect.
  //   * A WRONG ANSWER IS NEVER PUNISHED WITH MOTION. Nothing in this block is
  //     reachable from a `wrong` or a `reveal` event. The design's second
  //     pillar is that a mistake costs the streak and nothing else, and the
  //     500 ms sputter on the field is the whole of what a wrong answer does.

  // ------------------------------------------------------------- the clock
  // Milliseconds since the view was built. Monotonic, stepped by `advance()`,
  // never read from the wall clock or the date -- the same rule the race clock
  // is held to in ui/Race.qml.
  property real fxClock: 0
  // The reading at which a hit-stop lets the world go again.
  property real freezeUntil: 0
  // ... and the same for Pile-Up's "then 300 at half speed".
  property real slowUntil: 0
  property real slowScale: 1.0
  // Exposed so a test can assert the freeze rather than infer it from a
  // position that happened not to change.
  readonly property bool worldFrozen: fxClock < freezeUntil
  readonly property bool worldSlowed: fxClock < slowUntil

  // Design v4: "hit-stop | the world freezes for 60 to 120 ms at the moment of
  // impact ... one property". Reduced motion removes it entirely, which is the
  // design's own substitution rule.
  function fxHold(ms) {
    if (reducedMotion || ms <= 0)
      return
    freezeUntil = Math.max(freezeUntil, fxClock + ms)
  }
  function fxSlowMo(ms, scale) {
    if (reducedMotion || ms <= 0)
      return
    slowUntil = Math.max(slowUntil, fxClock + ms)
    slowScale = scale
  }

  // -------------------------------------------------- the fact's guard band
  //
  // THE ONE PLACE "NOTHING EVER COVERS THE FACT" IS DECIDED.
  //
  // `fieldRect` and `factRect` are handed down by ui/Race.qml from the items'
  // own geometry (they are already used by `crossingOver` for the arches). An
  // effect item that would be drawn over either is pushed down until its top
  // edge clears them, and only when it is horizontally over them at all: a tag
  // on a kart out at the left of the frame is nowhere near the fact and is left
  // where the projection put it.
  //
  // `fxGuardPad` is a hand's margin so the two boxes never touch either.
  readonly property real fxGuardPad: Math.max(8, height * 0.012)

  function fxGuardTop(cx, halfWidth) {
    var top = 0
    var boxes = [fieldRect, factRect]
    for (var i = 0; i < boxes.length; i++) {
      var b = boxes[i]
      if (b.width <= 0 || b.height <= 0)
        continue
      if (cx + halfWidth <= b.x || cx - halfWidth >= b.x + b.width)
        continue
      top = Math.max(top, b.y + b.height + fxGuardPad)
    }
    return top
  }

  // The highest y an effect item of this size may have, given where it is
  // across the frame. Callers clamp with `Math.max(fxTopFor(...), wantedY)`.
  function fxTopFor(cx, halfWidth) { return fxGuardTop(cx, halfWidth) }

  // Does this box enter either guarded box at all? Used by the speed lines,
  // which radiate from the vanishing point and are the one effect that cannot
  // simply be pushed downward -- a line has two ends and both are decided by
  // the geometry. A line that would cross the fact is not drawn; there are
  // sixteen of them and the fan reads the same with two of them missing.
  function fxBoxCrossesGuard(x, y, w, h) {
    var boxes = [fieldRect, factRect]
    for (var i = 0; i < boxes.length; i++) {
      var b = boxes[i]
      if (b.width <= 0 || b.height <= 0)
        continue
      if (x < b.x + b.width + fxGuardPad && x + w > b.x - fxGuardPad
          && y < b.y + b.height + fxGuardPad && y + h > b.y - fxGuardPad)
        return true
    }
    return false
  }

  // ------------------------------------------------------ the karts, by hand
  // The effect layer addresses karts by model index. These four are the only
  // way it ever asks where one is, so a kart that moves takes its smoke, its
  // sparks and its tag with it.
  property int heroIndex: -1
  property int heroBody: 0
  property int heroPaint: 0
  property int heroNumber: 7

  function fxIndexOfId(id) {
    for (var i = 0; i < kartModel.count; i++)
      if (kartModel.get(i).kartId === id)
        return i
    return -1
  }
  function fxKartZ(i) {
    if (i < 0 || i >= kartModel.count)
      return playerZ
    var k = kartModel.get(i)
    return k.isHuman ? playerZ : zForDelta(k.kartProgress - humanProgress)
  }
  function fxKartX(i) {
    if (i < 0 || i >= kartModel.count)
      return width / 2
    return uAt(laneOf(kartModel.get(i).kartSeat), fxKartZ(i)) * width + shakeX
  }
  function fxKartY(i) {
    if (i < 0 || i >= kartModel.count)
      return vAt(playerZ) * height + shakeY
    return vAt(fxKartZ(i)) * height + shakeY
  }
  function fxKartSpan(i) { return kartSheetPixels(fxKartZ(i)) }
  function kartModelSeat(i) {
    return (i >= 0 && i < kartModel.count) ? kartModel.get(i).kartSeat : 0
  }
  // The roof line: where a smoke sprite is pinned and where a tag sits.
  //
  // 0.62 OF THE SHEET, NOT ALL OF IT. `kartSpriteH` is the height of the sheet
  // CELL, and a car does not fill its cell -- the bake leaves headroom above the
  // roof and a contact shadow below the wheels. Hanging a tag a whole cell above
  // the contact point put `+5` a hundred and thirty pixels over an empty piece
  // of sky, which is the first strip this piece took. The fraction is measured
  // off the road-camera cells: the roof line sits at about 0.62 of the cell
  // above the contact point at every yaw.
  readonly property real kartRoofFraction: 0.62
  function fxKartTop(i) {
    return fxKartY(i) - kartSpriteH(fxKartZ(i)) * kartRoofFraction
  }

  // ------------------------------------------------------- the target state
  //
  // Design v4's grammar table: "the victim kart changes: a smoke sprite pinned
  // to its hood, a wobble in yaw (cycle sprite columns +-1), a bounce in y, a
  // spin (cycle all eight columns), for as long as the effect lasts". Each is a
  // pure function of the model's fx roles and the clock, so the kart delegate
  // holds three bindings and no state.
  function fxMark(index, kind, ms) {
    if (index < 0 || index >= kartModel.count || reducedMotion)
      return
    kartModel.setProperty(index, "fxKind", kind)
    kartModel.setProperty(index, "fxFrom", fxClock)
    kartModel.setProperty(index, "fxUntil", fxClock + ms)
  }
  // The hood smokes until the effect ends, which the design defines as the end
  // of the victim's current lap. ui/Race.qml renews this every frame from
  // `questionsNeededThisLap`, so the engine -- not a duration typed here --
  // decides when it stops. The `ms` here is only the floor that carries it
  // through the impact beat and through a harness injection with no engine
  // behind it.
  function fxSmokeFor(index, ms) {
    if (index < 0 || index >= kartModel.count)
      return
    kartModel.setProperty(index, "fxSmoke",
                          Math.max(kartModel.get(index).fxSmoke, fxClock + ms))
  }
  function fxRideLow(index, px, ms) {
    if (index < 0 || index >= kartModel.count || reducedMotion)
      return
    kartModel.setProperty(index, "fxLow", px)
    kartModel.setProperty(index, "fxSmoke",
                          Math.max(kartModel.get(index).fxSmoke, fxClock + ms))
  }
  function fxTagFlash(index, ms) {
    if (index < 0 || index >= kartModel.count)
      return
    kartModel.setProperty(index, "fxFlash", fxClock + ms)
  }

  // Is this rival's name plate carrying an effect readout right now, and how
  // hard is it ringing. Both read `fxClock` FIRST and unconditionally, for the
  // reason `fxKartDx` spells out: a binding depends on what the function
  // actually read, and an early return above the clock leaves the plate frozen
  // at whatever it evaluated to once.
  //
  // Design v4, Pile-Up: "Every other racer's tag flashes once so the field
  // reads the event." Round one wrote `fxFlash` and nothing ever read it, so
  // the field never flashed; the ring below is that line, finally drawn, and
  // it doubles as the ring on the victim's own plate.
  // How many karts the view is holding, and what a kart's plate is carrying.
  // Read by `tests/qml/tst_trackview_fx.qml` so the off-camera readout can be
  // asserted rather than eyeballed; nothing in the picture reads either.
  readonly property int kartCount: kartModel.count
  function kartPlateText(index) {
    if (index < 0 || index >= kartModel.count)
      return ""
    return kartModel.get(index).fxPlate
  }

  function fxPlateShowing(index) {
    var now = fxClock
    if (index < 0 || index >= kartModel.count)
      return false
    var k = kartModel.get(index)
    return k.fxPlate !== "" && now < k.fxPlateUntil
  }
  function fxPlateRing(index) {
    var now = fxClock
    if (index < 0 || index >= kartModel.count)
      return 0
    var k = kartModel.get(index)
    var ring = 0
    if (k.fxFlash > 0 && now < k.fxFlash)
      ring = Math.max(ring, CardFx.bump(1 - (k.fxFlash - now) / CardFx.BEATS.pileUp.fieldFlash))
    // The victim's own plate rings for the first 320 ms it carries a readout,
    // so the eye is taken to it ON the impact rather than after it.
    if (k.fxPlate !== "" && now < k.fxPlateUntil) {
      var age = now - k.fxPlateBorn
      ring = Math.max(ring, age < 320 ? CardFx.bump(age / 320) : 0.18)
    }
    return Math.max(0, Math.min(1, ring))
  }

  // How far a kart is pushed sideways and down by whatever it is in the middle
  // of. Both are in pixels and both are scaled by the kart's own drawn size, so
  // a jolt reads the same on a kart at the vanishing point as on one filling
  // the frame.
  function fxKartDx(index, span) {
    // `now` is read FIRST and unconditionally, because a QML binding only
    // depends on the properties the function actually read while it ran: an
    // early return above this line would leave the delegate bound to nothing
    // and frozen at whatever it evaluated to once.
    var now = fxClock
    if (reducedMotion || index < 0 || index >= kartModel.count)
      return 0
    var k = kartModel.get(index)
    if (k.fxKind === "" || now >= k.fxUntil)
      return 0
    var u = CardFx.phase(now - k.fxFrom, k.fxUntil - k.fxFrom)
    if (k.fxKind === "jolt")
      // Design, Wrench: "the kart jolts sideways one column and back". Out and
      // back once over the beat, which is one half-cycle of the decay.
      return CardFx.decay(u, 0.5) * span * 0.20
    if (k.fxKind === "wobble")
      // Oil Slick: the fishtail. Three lazy swings over the 800 ms.
      return CardFx.decay(u, 3) * span * 0.09
    if (k.fxKind === "bounce")
      return CardFx.decay(u, 1.5) * span * 0.05
    return 0
  }
  function fxKartDy(index, span) {
    var now = fxClock
    if (index < 0 || index >= kartModel.count)
      return 0
    var k = kartModel.get(index)
    var low = reducedMotion ? 0 : k.fxLow
    // The boost squat, which is the child's own kart only: "the kart squats
    // one pixel" (Nitro) / "two pixels" (Turbo), through the telegraph.
    if (k.isHuman)
      low += fxHeroSquat
    if (reducedMotion || k.fxKind === "" || now >= k.fxUntil)
      return low
    var u = CardFx.phase(now - k.fxFrom, k.fxUntil - k.fxFrom)
    if (k.fxKind === "bounce")
      // Pothole: "a two-pixel dip ... the kart bounces twice". Down first,
      // then two decaying bounces up.
      return low + (u < 0.18
                    ? CardFx.easeOut(u / 0.18) * span * 0.07
                    : -Math.abs(CardFx.decay((u - 0.18) / 0.82, 2)) * span * 0.055)
    if (k.fxKind === "wobble")
      return low + Math.abs(CardFx.decay(u, 3)) * span * 0.012
    return low
  }
  // The sprite column offset. `CarSprite` wraps this modulo eight itself.
  function fxKartYaw(index) {
    var now = fxClock
    if (reducedMotion || index < 0 || index >= kartModel.count)
      return 0
    var k = kartModel.get(index)
    if (k.fxKind === "" || now >= k.fxUntil)
      return 0
    var u = CardFx.phase(now - k.fxFrom, k.fxUntil - k.fxFrom)
    if (k.fxKind === "spin")
      // Pile-Up: "the target kart spins a full turn through all eight columns,
      // stops sideways". Eight columns eased out, settling on column 2 -- a
      // kart across the road, which is what "stops sideways" is.
      return Math.round(CardFx.easeOut(u) * 8) + (u >= 1 ? 2 : 0)
    if (k.fxKind === "jolt")
      return CardFx.decay(u, 0.5) > 0.35 ? 1 : (CardFx.decay(u, 0.5) < -0.35 ? -1 : 0)
    if (k.fxKind === "wobble")
      // "cycle sprite columns +-1", exactly as the grammar table says.
      return CardFx.decay(u, 3) > 0.33 ? 1 : (CardFx.decay(u, 3) < -0.33 ? -1 : 0)
    return 0
  }

  // ------------------------------------------------------------- the models
  //
  // Five small ListModels rather than one general one, for the same reason the
  // karts are a ListModel: a delegate is built once and only the bindings that
  // read a changed role are re-evaluated. Everything in them is pruned by
  // `fxAdvance` the frame after it dies, so a whole race allocates a handful of
  // rows and frees them again.
  ListModel { id: fxDecalModel }   // things lying on the road
  ListModel { id: fxFlyerModel }   // things travelling in z
  ListModel { id: fxPuffModel }    // smoke, dust, exhaust
  ListModel { id: fxSparkModel }   // spark bursts
  ListModel { id: fxTagModel }     // +5, +15, TOWED

  // Every spawn takes a life in milliseconds and is dead the moment the clock
  // passes it. Nothing is ever removed by hand.
  function fxDecal(kind, atTravel, lane, worldWidth, life, growMs) {
    fxDecalModel.append({
      "dKind": kind, "dAt": atTravel, "dLane": lane, "dWorld": worldWidth,
      "dBorn": fxClock, "dLife": life, "dGrow": growMs, "dFall": 0, "dFrame": 0
    })
  }
  // The Pile-Up: the same road decal, but it falls in from above first.
  function fxFallingDecal(kind, atTravel, lane, worldWidth, life, fallMs) {
    fxDecalModel.append({
      "dKind": kind, "dAt": atTravel, "dLane": lane, "dWorld": worldWidth,
      "dBorn": fxClock, "dLife": life, "dGrow": 0, "dFall": fallMs, "dFrame": 0
    })
  }
  function fxFlyer(kind, fromKart, toKart, dur, spins, worldWidth, frames) {
    fxFlyerModel.append({
      "yKind": kind, "yFrom": fromKart, "yTo": toKart, "yBorn": fxClock,
      "yDur": dur, "ySpins": spins, "yWorld": worldWidth, "yFrames": frames,
      "yLine": 0, "yArc": 1
    })
  }
  function fxPuff(kart, dx, dy, size, grow, life, tone, rise) {
    fxPuffModel.append({
      "pKart": kart, "pDx": dx, "pDy": dy, "pSize": size, "pGrow": grow,
      "pBorn": fxClock, "pLife": life, "pTone": String(tone), "pRise": rise,
      "pDelay": 0, "pPeak": 0.62
    })
  }
  function fxPuffLater(kart, dx, dy, size, grow, life, tone, rise, delay, peak) {
    fxPuffModel.append({
      "pKart": kart, "pDx": dx, "pDy": dy, "pSize": size, "pGrow": grow,
      "pBorn": fxClock, "pLife": life, "pTone": String(tone), "pRise": rise,
      "pDelay": delay, "pPeak": peak === undefined ? 0.62 : peak
    })
  }
  function fxSparks(kart, count, reach, life, tone, delay) {
    fxSparkModel.append({
      "sKart": kart, "sCount": count, "sReach": reach, "sBorn": fxClock,
      "sLife": life, "sTone": String(tone), "sSeed": fxSparkModel.count,
      "sDelay": delay
    })
  }
  // The HUD echo the design asks for on the victim: "the victim's name tag
  // shows +8 and ticks down". `big` is the large type reserved for Pile-Up.
  function fxTag(kart, text, tone, life, big, delay) {
    fxTagModel.append({
      "gKart": kart, "gText": text, "gTone": String(tone), "gBorn": fxClock,
      "gLife": life, "gBig": big, "gDelay": delay
    })
    // ... and on the victim's name plate, always, whether their kart is drawn
    // or not. See the `fxPlate` roles: this is the one readout an effect has
    // that the projection cannot take away.
    fxPlateFor(kart, text, tone, life + delay)
  }

  function fxPlateFor(kart, text, tone, life) {
    if (kart < 0 || kart >= kartModel.count)
      return
    kartModel.setProperty(kart, "fxPlate", String(text))
    kartModel.setProperty(kart, "fxPlateTone", String(tone))
    kartModel.setProperty(kart, "fxPlateBorn", fxClock)
    kartModel.setProperty(kart, "fxPlateUntil", fxClock + life)
  }

  // --------------------------------------------------------------- the sound
  //
  // Design v4 gives every card a Sound row, and two of them are not one sound
  // but a scheduled few: Oil Slick's "three squeals staggered by 120", and the
  // Pothole's "thud, rattle, hubcap ring". So a cue can be asked for with a
  // delay, and the delay is measured on the EFFECT CLOCK rather than by a
  // Timer -- the same rule everything else in this block obeys, so a cue fires
  // on the frame the picture it belongs to is drawn and a strip that steps the
  // clock steps the sound with it.
  //
  // `ui/parts/Sfx.qml` is the cue table and the seam. It plays nothing today:
  // the multimedia component is piece 6's, at M6', and the reasons are written
  // out in that file. What is built and tested here is the ROUTING -- which cue
  // fires on which beat of which event.
  property var fxSoundQueue: []

  function fxSound(cue, delay) {
    if (!delay || delay <= 0) {
      Sfx.play(cue)
      return
    }
    var queue = fxSoundQueue.slice()
    queue.push({ "cue": cue, "at": fxClock + delay })
    fxSoundQueue = queue
  }

  function fxSoundAdvance() {
    if (fxSoundQueue.length === 0)
      return
    var keep = []
    for (var i = 0; i < fxSoundQueue.length; i++) {
      if (fxClock >= fxSoundQueue[i].at)
        Sfx.play(fxSoundQueue[i].cue)
      else
        keep.push(fxSoundQueue[i])
    }
    fxSoundQueue = keep
  }

  // A new race is a new screen: nothing from the last one may still be in the
  // air. Called by `setKarts`, which is the one thing a new race does here.
  function fxReset() {
    fxDecalModel.clear()
    fxFlyerModel.clear()
    fxPuffModel.clear()
    fxSparkModel.clear()
    fxTagModel.clear()
    cueCard = ""
    cueImpacted = false
    cuePending = []
    hitCard = ""
    freezeUntil = 0
    slowUntil = 0
    flashBorn = -1e9
    boostBorn = -1e9
    bloomBorn = -1e9
    stretchBorn = -1e9
    cageBorn = -1e9
    cageCracked = 0
    cageCount = 0
    towBorn = -1e9
    whipBorn = -1e9
    towKart = -1
    lampChaseBorn = -1e9
    minimapPulseBorn = -1e9
    minimapPulseKart = -1
    heroIndex = -1
    fxSoundQueue = []
  }

  function fxPruneModel(model, bornRole, lifeRole) {
    for (var i = model.count - 1; i >= 0; i--) {
      var row = model.get(i)
      if (fxClock - row[bornRole] > row[lifeRole])
        model.remove(i)
    }
  }

  // ------------------------------------------------------------- the cue
  //
  // ONE CARD AT A TIME, AND THAT IS A PROPERTY OF THE GAME. Using a card spends
  // the whole hand, so the child cannot have two in flight; a rival's card
  // reaches this screen only as the `hit` it causes, which is the separate cue
  // below. Two cues is therefore the whole state machine.
  property string cueCard: ""
  property real cueBorn: 0
  property int cueActor: -1
  property bool cueImpacted: false
  // The victims the engine reported for this card, queued by `fxLandedOn`
  // until the telegraph has run. `cardUsed` and its `hit` events arrive in the
  // same step (see the ordering guarantee in src/engine/events.ts), so without
  // this the victim would react 500 ms before the wrench reached them.
  property var cuePending: []
  readonly property var cueBeats: (cueCard !== "" && CardFx.BEATS[cueCard])
                                  ? CardFx.BEATS[cueCard] : null
  readonly property real cueT: fxClock - cueBorn
  readonly property bool cueTelegraphing: cueBeats !== null && !cueImpacted
  // The impact beat, from the moment it lands until its world reaction is
  // spent. `ui/Race.qml` reads it for two things: how long a kart takes to
  // settle to the position the card gave it, and nothing else.
  readonly property bool cueSettling: cueBeats !== null && cueImpacted
                                      && cueT < cueBeats.telegraph + cueBeats.impact + 420
  // HOW LONG A KART TAKES TO REACH THE POSITION THE ENGINE GAVE IT.
  //
  // 190 ms ordinarily -- about three frames, which is what it takes to glide
  // between the engine's ten-a-second steps instead of stepping. Through a
  // card's impact it is nearly three times that, because the design does not
  // ask for the field to be re-ordered, it asks for a kart to be SHOVED: "the
  // two karts zip past each other", "a Pile-Up visibly shoves a kart
  // backwards", "rivals ahead stream past both sides of the frame as they fall
  // behind". A knock-back that resolves in three frames is a cut. This is the
  // one number that turns it into a move the eye can follow, and it is the
  // reason a Wrench's victim is still on screen while the sparks are on them.
  readonly property real fxSettleMs: cueSettling ? 520 : 190
  // The first victim, for the things that only ever have one (the wrench's
  // flight, the pothole's decal, the pile that falls).
  readonly property int cueTarget: cuePending.length > 0 ? cuePending[0].kart : -1
  property int cueAimed: -1

  // Being hit, which has no telegraph the child could have seen coming.
  property string hitCard: ""
  property real hitBorn: 0
  property int hitFrom: -1
  readonly property real hitT: fxClock - hitBorn
  // 0..1, the red-amber frame at the edges of the screen.
  readonly property real hitEdge: (hitCard === "" || hitT > CardFx.HIT.edgeMs)
                                  ? 0
                                  : CardFx.bump(CardFx.phase(hitT, CardFx.HIT.edgeMs))

  // -------------------------------------------------- what ui/Race.qml calls
  //
  // Five entry points, one per engine event the design's section names. None of
  // them decides anything: the card, the racers and the delta are all read off
  // the event.

  // `cardUsed`, the child's own. Starts the telegraph; the impact follows it by
  // the card's own beat.
  function fxCardUsed(card, actorId, targetId) {
    if (!CardFx.BEATS[card])
      return
    cueCard = card
    cueBorn = fxClock
    cueActor = fxIndexOfId(actorId)
    cueAimed = targetId && targetId.length > 0 ? fxIndexOfId(targetId) : -1
    cueImpacted = false
    cuePending = []
    fxTelegraph()
  }

  // `hit`, where the child is the attacker. Queued behind the telegraph.
  function fxLandedOn(victimId, card, delta) {
    var kart = fxIndexOfId(victimId)
    if (kart < 0)
      return
    var entry = { "kart": kart, "card": card, "delta": delta }
    if (cueCard === card && !cueImpacted) {
      var next = cuePending.slice()
      next.push(entry)
      cuePending = next
      return
    }
    fxLand(entry, 0)
  }

  // `blocked`, where the child is the attacker. Design, Wrench: "the wrench
  // shatters against the target's Roll Cage with a white flash and a ring, the
  // cage outline cracks and vanishes".
  function fxBlockedOn(victimId, card) {
    var kart = fxIndexOfId(victimId)
    if (kart < 0)
      return
    var entry = { "kart": kart, "card": card, "delta": 0, "blocked": true }
    if (cueCard === card && !cueImpacted) {
      var next = cuePending.slice()
      next.push(entry)
      cuePending = next
      return
    }
    fxLand(entry, 0)
  }

  // `hit`, where the child is the victim. Design, "Being hit, from the child's
  // seat": hit-stop 80, a red-amber frame at the edges, a 200 ms shake with
  // decay, then the horizon pull-back with the attacker sweeping past.
  function fxHitMe(card, fromId, delta, stallMs) {
    hitCard = card
    hitBorn = fxClock
    hitFrom = fxIndexOfId(fromId)
    fxHold(CardFx.HIT.hitStop)
    fxSound("hit", 0)
    pullBack(Math.min(1, 0.35 + Math.max(0, delta) / 18))
    shake = reducedMotion ? 0 : Math.min(1, 0.85)
    fxWorldFlash(CardFx.HIT.edgeHot, 0.30, 220)
    if (heroIndex >= 0) {
      // "Your own hood smokes until the effect ends." The floor is the stall
      // the engine reported; Race.qml renews it from the lap requirement.
      fxSmokeFor(heroIndex, Math.max(1400, stallMs))
      if (!reducedMotion)
        fxMark(heroIndex, "bounce", 420)
    }
  }

  function fxBlockedMe(card, fromId) {
    // The child's own cage taking the hit. The white flash and the ring, and
    // the cage cracks and goes.
    fxWorldFlash("#ffffff", 0.42, 160)
    fxSound("block", 0)
    fxHold(60)
    cageCracked = fxClock
    if (heroIndex >= 0)
      fxSparks(heroIndex, 12, fxKartSpan(heroIndex) * 0.5, 420, "#f2e6c4", 0)
  }

  // `swap`. Design, Tow Hook: "the line goes taut and the two karts zip past
  // each other ... the camera whips to follow ... the rival's tag reads TOWED
  // for 1.6 s". The karts themselves move because the ENGINE swapped their
  // progress; what is added here is the whip, the blur and the tag.
  function fxSwapped(aId, bId) {
    var other = fxIndexOfId(aId === "" ? bId : aId)
    if (other < 0)
      return
    // A Tow Hook's `swap` arrives in the SAME STEP as its `cardUsed` -- the
    // engine's ordering guarantee puts the effects of a card straight after the
    // card -- so running it here would trade the two karts 400 ms before the
    // hook the child is watching has reached the rival. It waits behind the
    // telegraph exactly as a `hit` does.
    var entry = { "kart": other, "card": "towHook", "delta": 0, "swap": true }
    if (cueCard === "towHook" && !cueImpacted) {
      var next = cuePending.slice()
      next.push(entry)
      cuePending = next
      return
    }
    fxLand(entry, 0)
  }

  // The latch and the zip past, once the hook has arrived.
  function fxTowLand(other) {
    var b = CardFx.BEATS.towHook
    if (!reducedMotion) {
      // "the camera whips to follow"
      whipBorn = fxClock
      shake = Math.min(1, b.whip * 0.5)
      lurch = Math.min(1, lurch + 0.35)
    }
    towBorn = fxClock
    towKart = other
    fxTag(other, "TOWED", Theme.teal, b.towedMs, false, 0)
  }

  // The engine's own lease on the smoke. ui/Race.qml calls this every frame for
  // every racer whose lap requirement is still above the clean lap, which is
  // the design's definition of an effect still running. Nothing else decides
  // when a hood stops smoking.
  function fxAfflicted(index, on) {
    if (!on || index < 0 || index >= kartModel.count)
      return
    kartModel.setProperty(index, "fxSmoke", fxClock + 500)
  }
  function fxClearLow(index) {
    if (index >= 0 && index < kartModel.count && kartModel.get(index).fxLow !== 0)
      kartModel.setProperty(index, "fxLow", 0)
  }

  // ---------------------------------------------------------- the telegraph
  //
  // The beat the eye has to catch BEFORE the impact. It is what turns a card
  // from a number into a thing that happened.
  function fxTelegraph() {
    var b = cueBeats
    if (!b)
      return
    // The sound the telegraph opens with. Every one is the design's own Sound
    // row for that card, and the cue names are `ui/parts/Sfx.qml`'s table.
    if (cueCard === "nitro" || cueCard === "turbo" || cueCard === "oilSlick"
        || cueCard === "pileUp")
      fxSound(cueCard === "oilSlick" ? "oilslick" : cueCard.toLowerCase(), 0)
    else if (cueCard === "wrench")
      fxSound("wrench-flight", 0)
    else if (cueCard === "towHook")
      fxSound("towhook", 0)

    if (cueCard === "wrench" && cueAimed >= 0 && !reducedMotion) {
      // "a wrench sprite leaves your kart spinning, arcs along the road toward
      // the target with the projection scaling it, trailing two sparks"
      fxFlyer("wrench", cueActor, cueAimed, b.telegraph, b.spins, 1.4, 4)
    } else if (cueCard === "towHook" && cueAimed >= 0 && !reducedMotion) {
      // "a hook and line fire from your kart to the target along the road"
      fxFlyer("towHook", cueActor, cueAimed, b.telegraph, 0, 0.9, 2)
    } else if (cueCard === "oilSlick") {
      // "a black slick sprite drops from the back of your kart and spreads
      // across the road width behind you (a decal that grows for 400 and stays
      // on the road as a prop until it scrolls out of view)"
      fxDecal("oilSlick", travel + playerZ, 0, roadHalf * 2 - 0.2,
              5200, b.decalGrow)
    } else if (cueCard === "pothole" && cueAimed >= 0) {
      // "a pothole decal materialises on the road just ahead of the target"
      // 2.6 world units, not the prop's nominal 1.8: a pothole is a thing a
      // kart falls INTO, so it has to be about a lane wide on the road, and at
      // the depth a rival sits at (z ~ 9) the nominal size drew a 130 x 24 px
      // dark smudge on dark tarmac that the first strip could not find.
      fxDecal("pothole", travel + fxKartZ(cueAimed) + 1.6,
              laneOf(kartModel.count > cueAimed ? kartModel.get(cueAimed).kartSeat : 0),
              2.6, 6000, b.telegraph)
    } else if (cueCard === "pileUp" && cueAimed >= 0) {
      // "a shadow grows on the road ahead of the target, and a stack of tyres,
      // barrels and crates tumbles in from the top of the frame".
      //
      // Under reduced motion the WRECK still arrives -- it is the thing on the
      // road that says what happened, and the design's substitution rule takes
      // out the hit-stop, the shake and the spin, not the event. What goes is
      // the tumble: the fall time is zero, so the pile is simply there.
      fxFallingDecal("pileUp", travel + fxKartZ(cueAimed) + 0.8,
                     laneOf(kartModel.count > cueAimed ? kartModel.get(cueAimed).kartSeat : 0),
                     3.0, 7000, reducedMotion ? 0 : b.telegraph)
    } else if (cueCard === "nitro" || cueCard === "turbo") {
      // "the kart squats one pixel, exhaust flares blue-white" / two pixels.
      // The squat itself is `fxHeroSquat` below; this is the exhaust.
      if (!reducedMotion && heroIndex >= 0) {
        var span = fxKartSpan(heroIndex)
        fxPuff(heroIndex, -span * 0.20, -span * 0.06, span * 0.16, 2.1,
               b.telegraph + 220, b.exhaust, 0.10)
        fxPuff(heroIndex, span * 0.20, -span * 0.06, span * 0.16, 2.1,
               b.telegraph + 220, b.exhaust, 0.10)
      }
    }
  }

  // ------------------------------------------------------------- the impact
  //
  // Fired by `fxAdvance` on the frame the clock crosses the telegraph, so the
  // hit-stop, the flash and the victim's reaction all land together and all
  // land AFTER the wind-up rather than with it.
  function fxImpact() {
    var b = cueBeats
    if (!b)
      return
    fxHold(b.hitStop)

    if (cueCard === "nitro") {
      // "the road throws forward as now but with speed lines from the corners,
      // the sun blooms for 300, the four next lap lamps light in a chase"
      throwForward(0.55)
      boostBorn = fxClock
      boostMs = b.impact + b.aftermath
      boostPower = b.speedLines
      bloomBorn = fxClock
      lampChaseBorn = fxClock
      lampChaseCount = b.lampChase
      lampChaseMs = b.lampChaseMs
      fxWorldFlash(b.tone, 0.16, 200)
    } else if (cueCard === "turbo") {
      // "hit-stop 90, one white frame, then the road stretches ... heavy speed
      // lines, the horizon dips ... Ten lap lamps chase in 500."
      throwForward(1.0)
      boostBorn = fxClock
      boostMs = b.impact + b.aftermath
      boostPower = b.speedLines
      stretchBorn = fxClock
      lampChaseBorn = fxClock
      lampChaseCount = b.lampChase
      lampChaseMs = b.lampChaseMs
      // ROUND 2: 0.62 measured whole-frame mean luma 121.6 against a base of
      // 75.2 -- +62% -- and a blind critic's note on both builds was that a
      // third over the base reads fine and half is more than a child's eyes
      // need. 0.15 measures 104 against 75.2, which is +38%. Every other beat
      // of this card (the edge darken, the stretch, the horizon dip, the speed
      // lines, the ten-lamp chase, the field streaming past) is untouched: the
      // card did not need the brightness, it needed the consequence.
      fxWorldFlash("#ffffff", reducedMotion ? 0.10 : 0.15, 120)
    } else if (cueCard === "rollCage") {
      // "a cage frame draws itself around your kart line by line over 300, then
      // settles to a soft amber pulse that stays as long as it is active"
      // Sound: "four metallic clicks".
      fxSound("rollcage", 0)
      cageBorn = fxClock
      cageCracked = 0
    } else if (cueCard === "towHook") {
      // The latch. The zip past is the engine's `swap`, which arrives in the
      // same step and is handled by `fxSwapped`.
      fxWorldFlash(b.tone, 0.14, 150)
    }

    // The victims, in the order the engine reported them, staggered by the
    // card's own number (Oil Slick's "three squeals staggered by 120", so a
    // child sees three separate hits rather than one).
    var stagger = b.stagger ? b.stagger : 0
    for (var i = 0; i < cuePending.length; i++)
      fxLand(cuePending[i], i * stagger)
    cuePending = []
    // ... and the verdict, which `ui/Race.qml` has been holding since the card
    // was played. Design, Wrench blocked: "the block is the payoff and must be
    // loud" -- and round one printed `ROLL CAGE HELD - BOLT` 480 ms BEFORE the
    // wrench arrived, so beat three landed inside beat one and the payoff
    // spoiled its own punchline. A callout that belongs to an impact is said on
    // the frame the impact happens, which is this one.
    fxImpactFired()
  }

  // Emitted on the frame a card's impact lands, after every victim's reaction
  // has been started. The only listener is `ui/Race.qml`, and the only thing it
  // does with it is release a callout it was holding.
  signal fxImpactFired()

  // What lands on one victim.
  function fxLand(entry, delay) {
    var kart = entry.kart
    var card = entry.card
    var b = CardFx.BEATS[card]
    if (!b || kart < 0)
      return
    var span = fxKartSpan(kart)
    var lane = kartModel.count > kart ? laneOf(kartModel.get(kart).kartSeat) : 0

    if (entry.swap === true) {
      fxTowLand(kart)
      return
    }

    if (entry.blocked === true) {
      // "the wrench shatters against the target's Roll Cage with a white flash
      // and a ring, the cage outline cracks and vanishes"
      fxSparks(kart, 16, span * 0.55, 460, "#ffffff", delay)
      fxSound("block", delay)
      fxWorldFlash("#ffffff", 0.30, 150)
      fxTag(kart, "BLOCKED", Theme.teal, 1200, false, delay)
      return
    }

    if (card === "oilSlick") {
      // "each rival kart fishtails ... and a small slick sprite appears under
      // each of them so the child sees three hits"
      fxMark(kart, "wobble", b.fishtail)
      // "three squeals staggered by 120" -- the stagger is the caller's own
      // `delay`, which is the card's `stagger` times the victim's index.
      fxSound("squeal", delay)
      fxDecal("oilSlick", travel + fxKartZ(kart), lane, 2.2, 4200, 180)
    } else if (card === "wrench") {
      // "a spark burst on the target kart, the kart jolts sideways one column
      // and back"
      fxSparks(kart, b.sparks, span * 0.60, 480, b.tone, delay)
      fxSound("wrench-clang", delay)
      // The burst's own light on the panel it struck. A spark is a chip of
      // metal and reads as a pixel; the flare around it is what says the
      // wrench ARRIVED, and it is the difference between a hit a child sees
      // and fourteen dots on a dark road.
      fxPuffLater(kart, 0, -span * 0.28, span * 0.26, 2.2, 300, "#fffbe8", 0.05, delay, 1.0)
      fxMark(kart, "jolt", b.joltMs)
    } else if (card === "pothole") {
      // "a two-pixel dip, a dust burst, the kart bounces twice, a hubcap sprite
      // flies off and rolls to the verge"
      fxMark(kart, "bounce", b.bounceMs)
      // "thud, rattle, hubcap ring": the first two are one cue, the ring
      // follows the hubcap off the wheel.
      fxSound("pothole", delay)
      fxSound("hubcap", delay + 180)
      fxPuff(kart, -span * 0.32, 0, span * 0.40, 2.6, 700, "#e7c489", 0.18)
      fxPuff(kart, span * 0.32, 0, span * 0.36, 2.6, 700, "#e7c489", 0.18)
      fxPuff(kart, 0, span * 0.04, span * 0.30, 2.4, 520, "#fff0cc", 0.06)
      if (!reducedMotion)
        fxFlyer("hubcap", kart, -1, b.hubcapMs, 4, 0.7, 3)
      // "the kart rides one pixel low with a rattle animation on the wheels
      // until the effect ends"
      fxRideLow(kart, Math.max(1, span * 0.012), 2600)
    } else if (card === "pileUp") {
      // "the target kart spins a full turn through all eight columns, stops
      // sideways, and a smoke column rises. Every other racer's tag flashes
      // once so the field reads the event."
      fxSlowMo(b.impact, b.slowMo)
      fxMark(kart, "spin", b.spinMs)
      for (var s = 0; s < 4; s++)
        fxPuffLater(kart, 0, -span * (0.10 + s * 0.16), span * (0.36 + s * 0.10),
                    1.9, 2200, s === 0 ? "#c9b0a8" : "#8d7480", 0.30, s * 130)
      fxWorldFlash(b.tone, 0.14, 220)
      for (var o = 0; o < kartModel.count; o++)
        if (o !== kart)
          fxTagFlash(o, b.fieldFlash)
      minimapPulseKart = kart
      minimapPulseBorn = fxClock
    }

    // The HUD echo. "the victim's name tag shows +8 and ticks down", and
    // Pile-Up's "callout is in the large type reserved for this card".
    if (entry.delta > 0)
      fxTag(kart, "+" + entry.delta, card === "pileUp" ? Theme.hazard : Theme.amber,
            card === "pileUp" ? 2200 : 1600, card === "pileUp", delay)
    // "smoke from the target's hood until the effect ends"
    if (entry.delta > 0)
      fxSmokeFor(kart, card === "pileUp" ? 3200 : 2400)
  }

  // ------------------------------------------------------ the world singles
  // One flash, one boost, one bloom, one stretch, one cage, one tow, one
  // minimap pulse. Each is a start reading plus a length; none of them is ever
  // more than one at a time, because none of the cards can overlap.
  property real flashBorn: -1e9
  property real flashMs: 0
  property real flashPeak: 0
  property color flashTone: "#ffffff"
  function fxWorldFlash(tone, peak, ms) {
    flashTone = tone
    flashPeak = peak
    flashMs = ms
    flashBorn = fxClock
  }
  readonly property real flashNow: (fxClock - flashBorn) > flashMs
                                   ? 0
                                   : flashPeak * CardFx.bump(CardFx.phase(fxClock - flashBorn, flashMs))

  // ------------------------------------------- HOW MUCH LIGHT IS OVER THE FACT
  //
  // ROUND 2. The design's first hard rule is that nothing ever covers the fact,
  // and round one read that as a GEOMETRY rule: no effect item's box may enter
  // the fact's ink box, proved over eleven hundred boxes. It is also a CONTRAST
  // rule, and round one failed it -- a blind critic measured the cream digits
  // sitting on a cream-to-pale-pink bloom for 120 ms on a Turbo and about 300
  // ms twice on a Pile-Up, surviving on a one-pixel outline. "The largest, most
  // important thing on screen becomes the least legible thing on screen at the
  // exact moment the child is being asked to hold a question in their head."
  //
  // This is the alpha of the full-frame light reaching the middle of the frame,
  // published so `ui/Race.qml` can put the fact's own dark ground up underneath
  // it for exactly as long as the wash lasts and no longer. The two washes that
  // reach the fact are the world flash (Turbo's white frame, Pile-Up's amber
  // sky, a hit's red-amber) and Nitro's sun bloom; the edge frame is four
  // gradient bands at the rim and never touches the middle, and the speed lines
  // are individually guarded by `fxGuardTop`.
  readonly property real fxWashOverFact: Math.min(
      1, Math.max(Math.max(flashNow, fxSkyFlash * fxSkyPeak), bloomNow * 0.55))

  property real boostBorn: -1e9
  property real boostMs: 0
  property real boostPower: 0
  readonly property real boostNow: (reducedMotion || (fxClock - boostBorn) > boostMs)
                                   ? 0
                                   : boostPower * (1 - CardFx.phase(fxClock - boostBorn, boostMs))

  property real bloomBorn: -1e9
  readonly property real bloomNow: {
    var b = CardFx.BEATS.nitro
    var t = fxClock - bloomBorn
    return (reducedMotion || t > b.bloom) ? 0 : CardFx.bump(CardFx.phase(t, b.bloom))
  }

  property real stretchBorn: -1e9
  readonly property real stretchNow: {
    var b = CardFx.BEATS.turbo
    var t = fxClock - stretchBorn
    return (reducedMotion || t > b.impact) ? 0 : (1 - CardFx.phase(t, b.impact))
  }
  // Turbo's two camera moves, and the only two terms this piece adds to the
  // projection.
  readonly property real fxFocalBump: stretchNow * 0.30
  readonly property real fxHorizonDip: -stretchNow * CardFx.BEATS.turbo.horizonDip

  // The squat: "the kart squats one pixel" / "two pixels", through the
  // telegraph of a boost only.
  readonly property real fxHeroSquat: {
    if (reducedMotion || !cueTelegraphing)
      return 0
    if (cueCard !== "nitro" && cueCard !== "turbo")
      return 0
    return CardFx.easeOut(CardFx.phase(cueT, cueBeats.telegraph)) * cueBeats.squatPx
  }
  // Turbo's "the screen edges darken slightly" through its telegraph.
  readonly property real fxEdgeDark: (reducedMotion || cueCard !== "turbo" || !cueTelegraphing)
                                     ? 0
                                     : CardFx.easeOut(CardFx.phase(cueT, cueBeats.telegraph))
                                       * CardFx.BEATS.turbo.edgeDarken
  // Pile-Up's "the sky flashes amber twice" through its 600 ms telegraph.
  //
  // TWICE IN 600 ms IS 3.3 Hz AND THE DESIGN'S CAP IS 3. The accessibility rule
  // -- "nothing flashes faster than 3 Hz" -- is not negotiable against a beat
  // description, so the two flashes are spaced `skyGap` = 340 ms peak to peak,
  // which is 2.94 Hz. The second one runs 20 ms past the telegraph and into the
  // impact, which is where a wind-up wants to end anyway.
  readonly property real fxSkyGap: 340
  // How hard the amber goes. Round one's pair measured +50% on whole-frame mean
  // luma against a base of 81; the design's own accessibility rule is a cap on
  // RATE, but a blind critic's note on both builds was that a third is enough
  // and half is more than a child's eyes need. This is the number that was
  // turned down; see `docs/design.md`, Accessibility.
  readonly property real fxSkyPeak: 0.30
  readonly property real fxSkyFlash: {
    if (cueCard !== "pileUp" || cueBorn <= 0)
      return 0
    var t = cueT
    if (t < 0 || t > fxSkyGap + 280)
      return 0
    var a = (t < 280) ? CardFx.bump(t / 280) : 0
    var b = (t >= fxSkyGap && t < fxSkyGap + 280) ? CardFx.bump((t - fxSkyGap) / 280) : 0
    return Math.max(a, b)
  }

  // The Roll Cage.
  property real cageBorn: -1e9
  property real cageCracked: 0
  readonly property bool cageActive: cageBorn > -1e8 && cageCracked <= 0
  readonly property real cageDraw: CardFx.phase(fxClock - cageBorn, CardFx.BEATS.rollCage.drawMs)
  // "settles to a soft amber pulse". 0.8 Hz, under the 3 Hz cap by a factor of
  // nearly four, and it is a fade rather than a blink.
  readonly property real cagePulse: 0.55 + 0.45 * (0.5 + 0.5 * Math.sin(
      (fxClock - cageBorn) / CardFx.BEATS.rollCage.pulseMs * Math.PI * 2))
  // The crack: 260 ms of the outline breaking up, then gone.
  readonly property real cageCrackT: cageCracked > 0 ? (fxClock - cageCracked) : -1

  // The camera whip. Design, Tow Hook, impact: "the camera whips to follow".
  // One swing out and back over the zip-past, signed, so the frame is dragged
  // one way and snaps the other -- which is what a whip pan looks like and what
  // a decaying shake does not.
  property real whipBorn: -1e9
  readonly property real whipNow: {
    var b = CardFx.BEATS.towHook
    var t = fxClock - whipBorn
    if (reducedMotion || t < 0 || t > b.impact)
      return 0
    return CardFx.decay(t / b.impact, 0.75) * b.whip
  }

  // The tow.
  property real towBorn: -1e9
  property int towKart: -1
  readonly property real towNow: {
    var b = CardFx.BEATS.towHook
    var t = fxClock - towBorn
    return t < 0 || t > b.impact ? 0 : (1 - CardFx.phase(t, b.impact))
  }

  // The HUD echoes ui/Race.qml binds to. Held here rather than signalled, so
  // that a frame drawn at a given clock reading is the same frame however it
  // was reached -- a signal would have to have been received.
  property real lampChaseBorn: -1e9
  property int lampChaseCount: 0
  property real lampChaseMs: 400
  readonly property real lampChase: (fxClock - lampChaseBorn) > lampChaseMs
                                    ? 0
                                    : 1 - CardFx.phase(fxClock - lampChaseBorn, lampChaseMs)
  // "the extra lap lamps you now owe appear as dark lamps added to the row with
  // a rattle". The lamps themselves are the engine's -- `questionsNeededThisLap`
  // went up -- so what is published here is only the rattle, off the same hit
  // the road's shake is off, and it is zero under reduced motion because a
  // rattle is a shake.
  readonly property real lampRattle: (reducedMotion || hitCard === ""
                                      || hitT > CardFx.HIT.rattleMs)
                                     ? 0
                                     : 1 - CardFx.phase(hitT, CardFx.HIT.rattleMs)
  property real minimapPulseBorn: -1e9
  property int minimapPulseKart: -1
  readonly property real minimapPulse: (fxClock - minimapPulseBorn) > 900
                                       ? 0
                                       : 1 - CardFx.phase(fxClock - minimapPulseBorn, 900)

  // --------------------------------------------------------- the fx clock's
  // one job besides counting: fire the impact when the telegraph is over, and
  // free what has died.
  function fxAdvance() {
    if (cueBeats !== null && !cueImpacted && cueT >= cueBeats.telegraph) {
      cueImpacted = true
      fxImpact()
    }
    if (cueBeats !== null && cueT > CardFx.drawnSpan(cueCard)) {
      cueCard = ""
      cueImpacted = false
      cuePending = []
    }
    if (hitCard !== "" && hitT > 3400)
      hitCard = ""
    // A cage that has cracked is gone. Whether another one goes up is the
    // engine's answer, delivered by `fxSetCages` on the next frame.
    fxSoundAdvance()
    if (cageCracked > 0 && fxClock - cageCracked > 300) {
      cageCracked = 0
      cageBorn = -1e9
    }
    fxPruneModel(fxDecalModel, "dBorn", "dLife")
    fxPruneModel(fxFlyerModel, "yBorn", "yDur")
    fxPruneModel(fxPuffModel, "pBorn", "pLife")
    fxPruneModel(fxSparkModel, "sBorn", "sLife")
    fxPruneModel(fxTagModel, "gBorn", "gLife")
    // A decal that has scrolled past the camera is gone whatever its life says.
    for (var i = fxDecalModel.count - 1; i >= 0; i--)
      if (fxDecalModel.get(i).dAt - travel < nearDistance - 0.5)
        fxDecalModel.remove(i)
  }

  // ==========================================================================
  // The drawing. Everything below is a delegate over one of the five models or
  // one of the world singles, and every one of them carries an `objectName` so
  // `dev/Harness.qml --dump-rects` prints its box beside the fact's.
  // ==========================================================================

  // ----------------------------------------------------------- road decals
  // The oil slick, the pothole and the Pile-Up's wreck: kit cells laid flat on
  // the tarmac at a fixed point on the circuit, so they come toward the camera
  // and scroll out exactly as a roadside prop does.
  Repeater {
    model: fxDecalModel

    Item {
      id: decal
      readonly property real zed: dAt - view.travel
      readonly property real age: view.fxClock - dBorn
      // "a decal that grows for 400": across the road, from a fifth of its
      // width to all of it.
      readonly property real grow: dGrow > 0 ? (0.45 + 0.55 * CardFx.easeOut(CardFx.phase(age, dGrow))) : 1
      readonly property real px: view.sizeAt(dWorld, zed) * grow
      // The Pile-Up falls in from above. `fxTopFor` is what keeps it off the
      // fact: where its own column is over the answer field or the fact's ink,
      // the fall starts below them instead of at the top of the frame.
      readonly property real fall: dFall > 0 ? (1 - CardFx.easeIn(CardFx.phase(age, dFall))) : 0
      readonly property real groundY: view.vAt(zed) * view.height + view.shakeY
      readonly property real cx: view.uAt(dLane, zed) * view.width + view.shakeX
      readonly property real halfW: px / 2
      readonly property real topLimit: view.fxTopFor(cx, halfW)
      readonly property real fallFrom: topLimit > 0 ? topLimit + sprite.drawnBoundsHeight / 2
                                                    : -sprite.drawnBoundsHeight
      readonly property real cy: groundY - (groundY - fallFrom) * fall

      objectName: "fx.decal." + dKind
      x: cx - halfW
      y: cy - sprite.drawnBoundsHeight / 2
      width: px
      height: Math.max(1, sprite.drawnBoundsHeight)
      // Under the karts at the same depth: a slick is on the road, not in
      // front of the car standing on it.
      z: 1000 - zed - 0.002
      // Culled a little further out than the karts are: a road decal at the
      // near limit is drawn thousands of pixels wide, almost all of it off the
      // frame, and it has already passed under the camera by then.
      visible: zed > view.nearDistance + 0.55 && zed < view.drawDistance && px > 2
               && sprite.amount > 0.01

      EffectSprite {
        id: sprite
        objectName: "fx.decalArt." + dKind
        x: decal.width / 2
        y: decal.height / 2
        kind: dKind
        frame: dFrame
        boundsWidth: decal.px
        // Fades out over its last second rather than blinking off.
        amount: Math.min(1, (dLife - decal.age) / 900)
      }
    }
  }

  // ------------------------------------------------------------- the flyers
  // The wrench, the tow hook and the pothole's hubcap: kit cells travelling in
  // z along the road with the projection scaling them, which is design v4's
  // second tool -- "the beat that says I did that".
  Repeater {
    model: fxFlyerModel

    Item {
      id: flyer
      readonly property real u: CardFx.phase(view.fxClock - yBorn, yDur)
      readonly property real z0: view.fxKartZ(yFrom) + 0.10
      // A hubcap has no destination kart: it goes to the verge and stays put in
      // world terms, so it falls back toward the camera as the road moves.
      readonly property real z1: yTo >= 0 ? view.fxKartZ(yTo) : (z0 - 0.8)
      readonly property real zed: z0 + (z1 - z0) * CardFx.easeOut(u)
      readonly property real lane0: view.laneOf(view.kartModelSeat(yFrom))
      readonly property real lane1: yTo >= 0 ? view.laneOf(view.kartModelSeat(yTo))
                                             : (lane0 < 0 ? -(view.roadHalf + 0.7) : view.roadHalf + 0.7)
      readonly property real lane: lane0 + (lane1 - lane0) * u
      readonly property real px: view.sizeAt(yWorld, zed)
      readonly property real cx: view.uAt(lane, zed) * view.width + view.shakeX
      // "arcs along the road": up and over, peaking in the middle of the
      // flight, on top of the projection's own vertical travel.
      readonly property real arc: CardFx.bump(u) * view.sizeAt(1.5, zed) * yArc
      readonly property real cy: view.vAt(zed) * view.height + view.shakeY
                                 - view.kartSpriteH(zed) * 0.55 - arc

      objectName: "fx.flyer." + yKind
      x: cx - px / 2
      y: Math.max(view.fxTopFor(cx, px / 2), cy - px / 2)
      width: Math.max(1, px)
      height: Math.max(1, px)
      z: 1000 - zed + 0.5
      visible: zed > view.nearDistance && zed < view.drawDistance && px > 2 && u < 1

      EffectSprite {
        objectName: "fx.flyerArt." + yKind
        x: flyer.width / 2
        y: flyer.height / 2
        kind: yKind
        // The frame cycle: the wrench's four frames spun `ySpins` times over
        // the flight, the hook's two frames latching at the end, the hubcap's
        // three-frame tumble.
        frame: yKind === "towHook"
               ? (flyer.u > 0.86 ? 1 : 0)
               : Math.floor(flyer.u * Math.max(1, ySpins) * yFrames)
        boundsWidth: flyer.px
        spin: yKind === "hubcap" ? flyer.u * 540 : 0
        amount: 1
      }

      // "a hook AND LINE fire from your kart to the target along the road".
      // The line is drawn from the child's kart to wherever the hook has got
      // to, so it pays out as the hook flies -- and it is drawn in QML because
      // both its ends move every frame, which is why `docs/prop-kit.md` lists
      // the tow line among the things that are never baked.
      Line {
        visible: yKind === "towHook"
        x1: view.fxKartX(yFrom) - flyer.x
        y1: view.fxKartY(yFrom) - view.kartSpriteH(view.playerZ) * 0.35 - flyer.y
        x2: flyer.width / 2
        y2: flyer.height / 2
        thickness: Math.max(1, flyer.px * 0.06)
        tone: Theme.teal
        amount: 0.85
      }

      // "trailing two sparks". Two hot chips a little behind the wrench, on
      // the line it has actually flown: the direction is taken from where the
      // wrench is now against where it started, so the trail follows the arc
      // rather than a guess at it.
      Repeater {
        model: yKind === "wrench" ? 2 : 0

        Rectangle {
          readonly property real bx: view.fxKartX(yFrom) - flyer.cx
          readonly property real by: view.fxKartY(yFrom) - flyer.cy
          readonly property real len: Math.max(1, Math.sqrt(bx * bx + by * by))
          readonly property real back: flyer.px * (0.42 + index * 0.40)
          width: Math.max(1, Math.round(flyer.px * (0.12 - index * 0.03)))
          height: width
          antialiasing: false
          color: "#ffd489"
          opacity: 0.80 - index * 0.30
          x: flyer.width / 2 + bx / len * back - width / 2
          y: flyer.height / 2 + by / len * back - height / 2
        }
      }
    }
  }

  // -------------------------------------------------------------- the puffs
  // Smoke from a hood, dust out of a pothole, the exhaust flare on a boost, the
  // column off a Pile-Up. Drawn in QML on purpose (`docs/prop-kit.md`: a
  // hard-edged bake of a soft thing reads as gravel).
  Repeater {
    model: fxPuffModel

    Item {
      readonly property real age: view.fxClock - pBorn - pDelay
      readonly property real u: CardFx.phase(age, Math.max(1, pLife - pDelay))
      readonly property real span: view.fxKartSpan(pKart)
      readonly property real cx: view.fxKartX(pKart) + pDx
      readonly property real cy: view.fxKartY(pKart) + pDy - span * pRise * CardFx.easeOut(u)
      readonly property real d: pSize * (1 + (pGrow - 1) * CardFx.easeOut(u))

      objectName: "fx.puff"
      x: cx - d / 2
      y: Math.max(view.fxTopFor(cx, d / 2), cy - d / 2)
      width: Math.max(1, d)
      height: Math.max(1, d)
      z: 1000 - view.fxKartZ(pKart) + 0.004
      visible: age >= 0 && u < 1 && d > 1

      Puff {
        anchors.centerIn: parent
        tone: pTone
        size: parent.d
        // In fast, out slow, so a puff is a puff and not a fade.
        // In fast, out slow. `pPeak` is the puff's own strength: smoke sits low
        // so it stays smoke against a sunset, and an impact flare is near
        // opaque at its core for the two frames it lives.
        amount: pPeak * Math.min(1, parent.u * 6) * (1 - parent.u)
      }
    }
  }

  // ------------------------------------------------------------- the sparks
  Repeater {
    model: fxSparkModel

    Item {
      readonly property real age: view.fxClock - sBorn - sDelay
      readonly property real u: CardFx.phase(age, Math.max(1, sLife - sDelay))
      readonly property real span: view.fxKartSpan(sKart)
      readonly property real cx: view.fxKartX(sKart)
      readonly property real cy: view.fxKartTop(sKart) + span * 0.06

      objectName: "fx.sparks"
      x: cx - sReach
      y: Math.max(view.fxTopFor(cx, sReach), cy - sReach)
      width: sReach * 2
      height: sReach * 2
      z: 1000 - view.fxKartZ(sKart) + 0.005
      visible: age >= 0 && u < 1

      Sparks {
        x: parent.width / 2
        y: parent.height / 2
        t: parent.u
        count: sCount
        reach: sReach
        grain: Math.max(3, parent.span * 0.055)
        tone: sTone
        seed: sSeed
      }
    }
  }

  // ------------------------------------------------- the smoke on the hood
  // "a smoke sprite pinned to its hood ... for as long as the effect lasts".
  // Not a spawned puff but a standing one, because its life is the engine's:
  // ui/Race.qml renews `fxSmoke` for as long as the victim's lap requirement is
  // above a clean lap. Three staggered plumes rising off the roof line.
  Repeater {
    model: kartModel

    Item {
      id: hood
      readonly property bool smoking: view.fxClock < fxSmoke && !isGhost
      readonly property real zed: !smoking ? view.playerZ
                                  : (isHuman ? view.playerZ
                                             : view.zForDelta(kartProgress - view.humanProgress))
      readonly property real span: smoking ? view.kartSheetPixels(zed) : 1
      readonly property real cx: smoking ? view.uAt(view.laneOf(kartSeat), zed) * view.width + view.shakeX : 0
      readonly property real cy: smoking ? view.vAt(zed) * view.height + view.shakeY
                                           - view.kartSpriteH(zed) * view.kartRoofFraction : 0

      objectName: "fx.hoodSmoke"
      x: cx - span * 0.30
      y: Math.max(view.fxTopFor(cx, span * 0.30), cy - span * 0.62)
      width: span * 0.60
      height: span * 0.62
      z: 1000 - zed + 0.006
      visible: smoking && zed > view.nearDistance && zed < view.drawDistance && span > 8

      Repeater {
        model: hood.smoking ? 3 : 0

        Puff {
          // Under reduced motion the plume is still: the same three puffs at a
          // fixed phase, so the victim is still visibly smoking and nothing
          // moves. That is the design's "flashes and tag changes" rule applied
          // to a thing that is not a flash -- the state stays readable.
          readonly property real ph: view.reducedMotion
                                     ? (0.25 + index * 0.22)
                                     : (((view.fxClock / 900) + index * 0.33) % 1)
          tone: index === 0 ? "#b49aa4" : "#8a7280"
          size: hood.span * (0.16 + ph * 0.26)
          amount: 0.62 * (1 - ph) * Math.min(1, ph * 5)
          x: hood.width / 2 - width / 2 + Math.sin(ph * 3.1 + index) * hood.span * 0.06
          y: hood.height - hood.height * ph - height / 2
        }
      }
    }
  }

  // --------------------------------------------------------------- the tags
  // The HUD echo over the victim: `+5`, `+15`, `TOWED`. It is drawn ABOVE the
  // kart, which is the one place in this view that can reach the fact -- so it
  // is the item `fxTopFor` matters most for, and its box is in the dump.
  Repeater {
    model: fxTagModel

    Item {
      id: tagBox
      readonly property real age: view.fxClock - gBorn - gDelay
      readonly property real u: CardFx.phase(age, Math.max(1, gLife - gDelay))
      readonly property real zed: view.fxKartZ(gKart)
      readonly property real cx: view.fxKartX(gKart)
      // "pops over it": up and out over the first fifth of its life, then held.
      readonly property real pop: CardFx.easeOut(Math.min(1, u * 5))
      // A FLOOR AND A CEILING, BOTH FOR THE SAME REASON.
      //
      // The tag is sized off the victim's own kart so a `+5` on a far kart is a
      // `+5` at that kart's size, and the floor keeps it readable when the kart
      // saturates at the vanishing point. ROUND 2 adds the ceiling: with the
      // engine really running, a Tow Hook drags its victim from up the road to
      // right beside the camera, `kartSpriteH` goes past four hundred pixels,
      // and `TOWED` was drawn a third of the screen wide. The fact is the
      // largest thing on screen at every moment of a race, and that is a rule.
      readonly property real size: Math.max(
          gBig ? 30 : 17,
          Math.min(Math.round(view.height * (gBig ? 0.062 : 0.040)),
                   Math.round(view.kartSpriteH(zed) * (gBig ? 0.46 : 0.26))))

      objectName: "fx.tag"
      x: cx - width / 2
      y: Math.max(view.fxTopFor(cx, width / 2),
                  view.fxKartTop(gKart) + view.kartSpriteH(zed) * 0.14
                  - pop * view.kartSpriteH(zed) * 0.16 - height)
      width: tagText.implicitWidth + 14
      height: tagText.implicitHeight + 8
      z: 1990
      visible: age >= 0 && u < 1 && view.fxKartZ(gKart) < view.drawDistance
      opacity: Math.min(1, (1 - u) * 3.2)
      scale: 0.7 + pop * 0.3

      Rectangle {
        anchors.fill: parent
        radius: 3
        color: view.plateGround
        border.width: gBig ? 2 : 1
        border.color: gTone
      }

      Text {
        id: tagText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: gText
        color: gTone
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: tagBox.size
        font.letterSpacing: 1
      }
    }
  }

  // ------------------------------------------------- the field's tag flash
  // Pile-Up: "Every other racer's tag flashes once so the field reads the
  // event." One ring around each other racer's plate, on the plate's own
  // position, so the flash is on the thing it names.
  Repeater {
    model: kartModel

    Rectangle {
      // Every one of these is short-circuited while the ring is down, for the
      // reason `Puff` gates its rings: four karts x five projections on every
      // frame of a whole race, to draw nothing.
      readonly property real flashLeft: fxFlash - view.fxClock
      readonly property bool live: flashLeft > 0
      readonly property real zed: !live ? view.playerZ
                                  : (isHuman ? view.playerZ
                                             : view.zForDelta(kartProgress - view.humanProgress))
      readonly property real cx: live ? view.uAt(view.laneOf(kartSeat), zed) * view.width + view.shakeX : 0
      readonly property real cy: live ? view.vAt(zed) * view.height + view.shakeY : 0
      readonly property real d: live ? view.kartSheetPixels(zed) * 0.9 : 1

      objectName: "fx.fieldFlash"
      x: cx - d / 2
      y: Math.max(view.fxTopFor(cx, d / 2), cy - d)
      width: d
      height: d
      radius: 4
      color: "transparent"
      border.width: 2
      border.color: Theme.hazard
      opacity: live ? Math.min(1, flashLeft / 400) * 0.85 : 0
      visible: live && opacity > 0.02 && zed > view.nearDistance && zed < view.drawDistance
      z: 1980
    }
  }

  // -------------------------------------------------------- the afterimages
  // "an afterimage trail behind the kart fading out" (Nitro, 700 ms) and
  // "afterimages and a heat shimmer at the exhaust" (Turbo, 1200 ms). Three
  // copies of the child's own car, further down the road and fainter, which is
  // where the car WAS -- the camera is behind it, so behind is further away.
  Repeater {
    model: view.boostNow > 0.02 && view.heroIndex >= 0 ? 3 : 0

    Item {
      readonly property real zed: view.playerZ + (index + 1) * 0.42
      readonly property var fit: view.kartCell(zed)

      objectName: "fx.afterimage"
      x: view.uAt(view.heroLane, zed) * view.width + view.shakeX
      y: view.vAt(zed) * view.height + view.shakeY
      width: 0
      height: 0
      z: 1000 - zed - 0.01
      opacity: view.boostNow * (0.34 - index * 0.09)

      CarSprite {
        body: view.heroBody
        paint: view.heroPaint
        number: view.heroNumber
        camera: "road"
        yaw: 0
        sheetScale: parent.fit.sheetScale
        pixelScale: parent.fit.pixelScale
        showNumber: false
      }
    }
  }

  // ------------------------------------------------------- the speed lines
  // "speed lines from the corners" (Nitro) and "heavy speed lines" (Turbo).
  // Drawn in QML, from the four corners toward the vanishing point, so they
  // read as the frame itself being pulled forward rather than as the streaks
  // that are always there.
  Item {
    id: boostLines
    anchors.fill: parent
    visible: view.boostNow > 0.02 && !view.reducedMotion
    readonly property real washAlpha: visible ? view.boostNow * 0.80 : 0
    z: 2400

    readonly property real vx: view.uAt(0, 6000) * view.width + view.shakeX
    readonly property real vy: view.horizon * view.height + view.shakeY

    Repeater {
      model: boostLines.visible ? 16 : 0

      // Each line is wrapped in an item with the segment's own bounding box, so
      // it is an OBJECT as far as `--dump-rects` and tst_trackview_fx.qml are
      // concerned: its box is printed beside the fact's, and it is not drawn at
      // all where the two would meet.
      Item {
        id: streak
        readonly property real ang: (index / 16) * Math.PI * 2 + 0.11
        readonly property real reach: Math.max(view.width, view.height) * 0.80
        readonly property real inner: reach * (0.30 - view.boostNow * 0.16)
        readonly property real ax: boostLines.vx + Math.cos(ang) * inner
        readonly property real ay: boostLines.vy + Math.sin(ang) * inner * 0.62
        readonly property real bx: boostLines.vx + Math.cos(ang) * reach
        readonly property real by: boostLines.vy + Math.sin(ang) * reach * 0.62

        objectName: "fx.speedLine"
        x: Math.min(ax, bx)
        y: Math.min(ay, by)
        width: Math.max(1, Math.abs(bx - ax))
        height: Math.max(1, Math.abs(by - ay))
        visible: !view.fxBoxCrossesGuard(x, y, width, height)

        Line {
          x1: streak.ax - streak.x
          y1: streak.ay - streak.y
          x2: streak.bx - streak.x
          y2: streak.by - streak.y
          thickness: 2 + view.boostNow * 4
          tone: Theme.cream
          amount: view.boostNow * 0.80
        }
      }
    }
  }

  // ---------------------------------------------------------- the sun bloom
  // Nitro: "the sun blooms for 300". A soft disc on the sun's own place in the
  // sky, over the plane rather than inside it, so it is not quantised by the
  // 480 x 270 layer.
  Puff {
    objectName: "fx.sunBloom"
    visible: view.bloomNow > 0.01
    tone: Theme.duskSun
    size: view.height * 0.62
    amount: view.bloomNow * 0.55
    readonly property real washAlpha: visible ? amount : 0
    x: view.sunU * view.width - width / 2
    y: view.horizon * view.height - height / 2
    z: 4
  }

  // ------------------------------------------------------------ the tow line
  // "a hook and line fire from your kart to the target ... the line goes taut".
  // Two lines: one during the flight, from the child's kart to the hook, and
  // one taut one while the karts trade places.
  Line {
    objectName: "fx.towLine"
    readonly property int other: view.towKart
    visible: view.towNow > 0.01 && other >= 0 && !view.reducedMotion
    x1: view.fxKartX(view.heroIndex)
    y1: view.fxKartY(view.heroIndex) - view.kartSpriteH(view.playerZ) * 0.45
    x2: view.fxKartX(other)
    y2: view.fxKartY(other) - view.kartSpriteH(view.fxKartZ(other)) * 0.45
    thickness: 2
    tone: Theme.teal
    amount: view.towNow * 0.9
    z: 1970
  }

  // --------------------------------------------------------- the Roll Cage
  // "a cage frame draws itself around your kart line by line over 300, then
  // settles to a soft amber pulse that stays as long as it is active."
  //
  // Eight lines around the child's own car, each starting a little after the
  // one before it so the cage is built rather than switched on. Drawn in QML
  // for the reason the kit lists it as not-baked: it is an outline around a
  // thing whose size changes every frame.
  Item {
    id: cage
    objectName: "fx.rollCage"
    // THE CAGE IS AROUND THE CAR, NOT BESIDE IT.
    //
    // ROUND 2. `span` was 0.52 of the sheet, which made the box 1.04 SHEETS
    // wide -- and a car is about 0.60 to 0.65 of its own sheet, because the
    // bake leaves margin on both sides. `tall` was 0.92 of the cell measured up
    // from the contact point, and the cell's roof line is at 0.62, so the top
    // rail floated a third of a car above the roof. A blind critic called it
    // "an oversized plain rectangle offset to the right of the kart, floating
    // in the road rather than around the car", and it was two of those three.
    //
    // The numbers now come off the car: 0.35 of the sheet either side of the
    // contact point (a shade wider than the widest body at any yaw, so it
    // clears the wheels), from just above `kartRoofFraction` down to just
    // below the tyres.
    // The two numbers are measured off the rendered frame rather than off the
    // sheet's nominal geometry, because the sheet is not the car and this file
    // has been caught by that before (see `kartSheetSpan`). At `playerZ` the
    // sheet draws 400 px wide, the quantised cell 384, and the rear-view body
    // 208 -- so 0.29 of the sheet either side is a cage about a tenth wider
    // than the car it is around. The roof of the tallest body sits about 0.39
    // of the cell height above the contact point (`kartRoofFraction`'s 0.62 is
    // where a TAG hangs, which is deliberately clear of the roof), so the hoop
    // goes at 0.50 and the sill just under the tyres.
    readonly property real span: view.kartSheetPixels(view.playerZ) * 0.29
    readonly property real tall: view.kartSpriteH(view.playerZ) * 0.54
    readonly property real cx: view.uAt(view.heroLane, view.playerZ) * view.width + view.shakeX
    readonly property real cy: view.vAt(view.playerZ) * view.height + view.shakeY
    // The crack: the outline breaks up over 260 ms and goes.
    readonly property real crack: view.cageCrackT < 0 ? 0
                                  : CardFx.phase(view.cageCrackT, 260)
    readonly property real amount: view.cageBorn <= -1e8 ? 0
                                   : (crack > 0 ? Math.max(0, 1 - crack) * (crack < 0.5 ? 1 : 0.4)
                                                : view.cagePulse)

    // A ROLL CAGE, NOT A LADDER. Round one drew a grid: two horizontals, two
    // verticals and four more uprights, evenly spaced. What a roll cage is, is
    // a main hoop over the driver, two tapered uprights down to the sill, a
    // waist rail, a front hoop and a diagonal cross-brace -- and the brace is
    // the line that makes the shape read as a cage rather than as a box.
    //
    // Each entry is [x1, y1, x2, y2, start] in the item's own 0..1 box, and
    // `start` is where in the 300 ms draw that member begins, so the frame
    // assembles hoop-first the way one is welded.
    readonly property var spec: [
      // the main hoop, over the roof
      [0.10, 0.06, 0.90, 0.06, 0.00],
      // its two uprights, tapering out to the sill
      [0.10, 0.06, 0.03, 1.00, 0.18],
      [0.90, 0.06, 0.97, 1.00, 0.18],
      // the sill, along the bottom of the doors
      [0.03, 1.00, 0.97, 1.00, 0.40],
      // the waist rail, at the window line
      [0.05, 0.60, 0.95, 0.60, 0.52],
      // the cross-brace: the line that says cage
      [0.10, 0.06, 0.97, 1.00, 0.64],
      [0.90, 0.06, 0.03, 1.00, 0.72],
      // the front hoop
      [0.20, 0.30, 0.80, 0.30, 0.84]
    ]

    x: cx - span
    y: Math.max(view.fxTopFor(cx, span), cy - tall * 0.926)
    width: span * 2
    height: tall
    z: 1000 - view.playerZ + 0.007
    visible: amount > 0.02 && view.cageCrackT < 260

    // top, bottom, left, right, and the four uprights, each with its own start
    // in the 300 ms draw so the frame assembles.
    Repeater {
      model: cage.visible ? cage.spec : 0

      Line {
        readonly property real begin: modelData[4]
        readonly property real g: view.reducedMotion
                                  ? 1
                                  : Math.max(0, Math.min(1, (view.cageDraw - begin) / 0.20))
        x1: modelData[0] * cage.width
        y1: modelData[1] * cage.height
        x2: modelData[2] * cage.width
        y2: modelData[3] * cage.height
        thickness: 2
        tone: Theme.amber
        grow: cage.crack > 0 ? Math.max(0, 1 - cage.crack * (1 + begin)) : g
        amount: cage.amount
      }
    }
  }

  // ------------------------------------------------ the world flash and edges
  // The last of the design's five tools. One rectangle for the flash -- Turbo's
  // white frame, a hit's red-amber, Pile-Up's amber sky -- and four gradient
  // bands for the edges: Turbo's telegraph darkening and the "red-amber frame
  // at the edges" of being hit.
  //
  // NEITHER EVER COVERS THE FACT, and neither has to be clamped to do it: they
  // are inside TrackView, which ui/Race.qml declares BEFORE the fact and the
  // field, so both are drawn over these however bright they get. The flash's
  // own peak is 0.78 for one white frame and 0.30 or less for everything else.
  Rectangle {
    objectName: "fx.worldFlash"
    anchors.fill: parent
    z: 2600
    visible: opacity > 0.004
    color: view.flashTone
    // ROUND 2: the sky flash is no longer folded in here. It used to be
    // `Math.max(flashNow, fxSkyFlash * 0.32)` on a rectangle whose colour is
    // `flashTone` -- the tone of the last flash that FIRED -- and the Pile-Up's
    // sky flashes happen in its telegraph, BEFORE any flash has fired, so they
    // were painted in whatever was left over (white, by default). The design
    // says amber, twice, and a blind critic measured "a whole-screen
    // desaturating wash, not an amber sky". It has its own item below now, it
    // is amber, and it is the sky.
    opacity: view.flashNow
    // THE ALPHA THE PIXEL ACTUALLY GETS, published for the test.
    //
    // Three of the four washes are containers whose CHILDREN carry the paint --
    // the edge frame's four gradient bands, the sixteen speed lines, the sun
    // bloom's rings -- so an `item.opacity` read off the container measures 1
    // and says nothing. `washAlpha` is each wash's own strongest paint, so
    // `tst_trackview_fx.qml` can bound what the fact has to be read against
    // rather than bounding a number that was always one.
    readonly property real washAlpha: opacity
  }

  // ------------------------------------------------------- the amber sky
  // Pile-Up, telegraph: "the sky flashes amber twice". THE SKY. It is a band
  // from the top of the frame down to the horizon, with a short fall-off below
  // it so the light lands on the land rather than stopping on a line, and it is
  // the card's own amber. Nothing about the road, the karts or the tarmac is
  // touched: a full-screen wash desaturates the whole picture, which is the
  // failure this project has a standing memory of -- darkness, and light, are
  // achromatic fill when they are applied to everything at once.
  Item {
    id: skyFlash
    objectName: "fx.skyFlash"
    x: 0
    y: 0
    width: view.width
    height: Math.round(view.horizon * view.height * 1.16)
    z: 2590
    readonly property real amount: view.fxSkyFlash * view.fxSkyPeak
    readonly property real washAlpha: amount
    visible: amount > 0.004

    // The card's own amber, full strength down to the horizon and gone a
    // sixth of the sky's height below it.
    readonly property color tone: CardFx.BEATS.pileUp.tone

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop {
          position: 0.0
          color: Qt.rgba(skyFlash.tone.r, skyFlash.tone.g, skyFlash.tone.b,
                         skyFlash.amount)
        }
        GradientStop {
          position: 0.862
          color: Qt.rgba(skyFlash.tone.r, skyFlash.tone.g, skyFlash.tone.b,
                         skyFlash.amount)
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(skyFlash.tone.r, skyFlash.tone.g, skyFlash.tone.b, 0)
        }
      }
    }
  }

  Item {
    id: edgeFrame
    objectName: "fx.edges"
    anchors.fill: parent
    z: 2500
    // Turbo's telegraph darkening, and the red-amber frame of being hit. The
    // hit wins where both are up, because it is the one that is telling the
    // child something happened TO them.
    readonly property real dark: view.fxEdgeDark
    readonly property real hot: view.hitEdge
    readonly property color tone: hot > dark ? CardFx.HIT.edgeTone : "#1a0612"
    readonly property real amount: Math.max(dark * 0.55, hot * 0.62)
    readonly property real washAlpha: amount
    visible: amount > 0.004

    Repeater {
      model: 4

      Rectangle {
        readonly property bool vertical: index < 2
        readonly property bool atEnd: index === 1 || index === 3
        width: vertical ? Math.round(edgeFrame.width * 0.16) : edgeFrame.width
        height: vertical ? edgeFrame.height : Math.round(edgeFrame.height * 0.16)
        x: index === 1 ? edgeFrame.width - width : 0
        y: index === 3 ? edgeFrame.height - height : 0
        gradient: Gradient {
          orientation: vertical ? Gradient.Horizontal : Gradient.Vertical
          GradientStop {
            position: 0.0
            color: atEnd ? "transparent"
                         : Qt.rgba(edgeFrame.tone.r, edgeFrame.tone.g,
                                   edgeFrame.tone.b, edgeFrame.amount)
          }
          GradientStop {
            position: 1.0
            color: atEnd ? Qt.rgba(edgeFrame.tone.r, edgeFrame.tone.g,
                                   edgeFrame.tone.b, edgeFrame.amount)
                         : "transparent"
          }
        }
      }
    }
  }

  // ------------------------------------------------------- the cage's count
  // The HUD carries one shield per held Roll Cage already (ui/Race.qml); this
  // is the cage on the CAR, and it is up exactly while the engine says the
  // child holds one. Race.qml calls this every frame off `human.rollCages`, so
  // a cage that is spent -- by blocking, or by the race ending -- takes its
  // outline with it without anything here counting.
  property int cageCount: 0
  function fxSetCages(n) {
    if (n > 0 && cageBorn <= -1e8) {
      cageBorn = fxClock
      cageCracked = 0
    }
    // A grace, and it is not cosmetic. The harness can inject `cardUsed:rollCage`
    // at a screen whose engine holds no cage, and without this the outline would
    // be cleared on the very next frame by a count that never moved -- so the
    // one card whose whole effect IS the outline would have no strip. In play the
    // engine has already incremented `rollCages` by the time this runs, so the
    // grace never fires; when a cage is spent, the crack above removes it.
    if (n <= 0 && cageCracked <= 0 && cageBorn > -1e8
        && fxClock - cageBorn > CardFx.BEATS.rollCage.drawMs + 1400)
      cageBorn = -1e9
    cageCount = n
  }

  // How many effect items are alive. Exposed for the tests and for the
  // harness's strip report; nothing in the picture reads it.
  readonly property int fxLiveCount: fxDecalModel.count + fxFlyerModel.count
                                     + fxPuffModel.count + fxSparkModel.count
                                     + fxTagModel.count
}
