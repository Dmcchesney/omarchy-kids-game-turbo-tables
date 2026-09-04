import QtQuick
import "parts"
import "parts/CarMeta.js" as CarMeta

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
  property real travel: 118
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
  readonly property real horizon: baseHorizon + pullback * 0.055 + hillAt(travel)
  readonly property real focal: baseFocal + lurch * 0.16 - pullback * 0.13
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
  // arranged, so the pack still overlaps; these numbers are the widest that
  // keep every kart's own number plate clear of its neighbour, and the outer
  // two ride the rumble strip at the start, which is what a four-wide first
  // row looks like. The hero's drift with the corner is gentler for the same
  // reason: at 13.0 it crossed into PISTON's lane on a hard left.
  readonly property real heroLane: 0.30 - curve * 8.0
  readonly property var lanes: [0.0, -1.34, 1.34, -0.60]
  function laneOf(seat) {
    var s = ((seat % 4) + 4) % 4
    return s === 0 ? heroLane : lanes[s]
  }

  // ---------------------------------------------------------- the kart list
  ListModel { id: kartModel }

  // Called once, when the race is built.
  function setKarts(list) {
    kartModel.clear()
    for (var i = 0; i < list.length; i++) {
      var k = list[i]
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
        "isGhost": k.ghost === true
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
  // same order -- the integers the engine ranks by and the HUD's ladder prints.
  // The name plates take their gap from it. Without it the plate has to round
  // the smoothed value, which is one question out for a fraction of a second
  // after every answer, and a plate that says "+3" beside a ladder that says
  // "2" is two sources of truth for one number.
  // A plate shows its gap ONLY when `exact` was supplied. Rounding the smoothed
  // delta instead is wrong on 17% of frames -- measured, 320 of 1875 -- because
  // the smoothing takes about four tenths of a second to cross the next half
  // question, and a plate reading "+3" beside a HUD ladder reading "2" is two
  // sources of truth for one number. Without `exact` the plate is the name
  // alone, which is still every rival named at every distance.
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
    var dt = Math.max(0, Math.min(80, dtMs)) / 1000

    if (reducedMotion) {
      // The design's reduced-motion floor: a static perspective plane with
      // sprites. No scroll, no shake, no lurch, no streaks.
      lurch = 0
      pullback = 0
      shake = 0
      shakeX = 0
      shakeY = 0
      return
    }

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
    if (shake > 0) {
      var phase = travel * 3.1
      shakeX = Math.sin(phase * 6.3) * shake * 9
      shakeY = Math.cos(phase * 8.1) * shake * 6
    } else {
      shakeX = 0
      shakeY = 0
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

  // GOLDEN-HOUR PROTOTYPE PALETTE. Sampled off the bar (see DIRECTION.md):
  // near-black purple ground, neon magenta grid, purple-tinted tarmac, a
  // dusk fog and the sun's pink-orange spill. Held here rather than in the
  // shader so both renderers read one set of numbers. The design's themed
  // ground (`Theme.ground`) is not used by the floor in this prototype.
  readonly property color groundTone: "#3c1228"
  readonly property color gridTone: "#ff4fa3"
  readonly property color fogTone: "#3a1032"
  readonly property color roadTone: "#221420"
  readonly property color roadToneAlt: "#2c1a2a"
  readonly property color laneTone: Theme.cream
  readonly property color sunTone: "#f0956e"
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
      visible: zed > view.nearDistance + 0.2 && zed < view.drawDistance
               && sc > 0.010 && x > -view.width * 0.7 && x < view.width * 1.7

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

      x: view.uAt(view.laneOf(kartSeat), zed) * view.width + view.shakeX
      y: view.vAt(zed) * view.height + view.shakeY + bob
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
        yaw: isHuman ? 0 : CarMeta.columnForHeading(view.kartHeadingDeg(slot.zed))
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
      y: view.vAt(zed) * view.height + view.shakeY + 3 + plateRow * (height + 3)

      Rectangle {
        anchors.fill: parent
        radius: 3
        color: Qt.rgba(0, 0, 0, 0.80)
        border.width: 1
        border.color: Qt.rgba(badge.paintCol.r, badge.paintCol.g, badge.paintCol.b, 0.95)
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
          text: badge.gapQuestions > 0 ? "+" + badge.gapQuestions : ""
          color: Theme.amber
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
        color: Qt.rgba(0, 0, 0, 0.80)
        // Two pixels of border when the rival is within one question: the
        // child is about to be passed and the plate says so without a word.
        border.width: (view.haveExact && chaser.gapQuestions >= -1) ? 2 : 1
        border.color: Qt.rgba(chaser.paintCol.r, chaser.paintCol.g,
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
          text: view.haveExact ? String(chaser.gapQuestions) : ""
          color: Theme.teal
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: view.chaserSize
        }
      }
    }
  }
}
