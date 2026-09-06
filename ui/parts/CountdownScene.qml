import QtQuick
import "../"

// The start-line backdrop behind the countdown.
//
// ================================ PIECE 5: THE SECOND SKY AND THE FLAT GANTRY
//
// This file used to paint its own sunset. Sky gradient, cloud bands, banded
// sun, three sine-wave ridges, neon floor, road, start line and a gantry, all
// into one 480 x 270 canvas -- and `ui/parts/SunsetSky.qml` painted a DIFFERENT
// sunset for the race view and the garage door. Plan v3's piece-5 row says what
// this file is supposed to be in five words: "`CountdownScene.qml` on
// `SunsetSky` and the sheets". It was not, for one honest reason recorded in
// round 6's own note -- the shared sky knew nothing about a road, a gantry or a
// floor, and taking it over from a screen that needed all three was a piece of
// work nobody owned.
//
// Piece T owns it now. `SunsetSky` grew the hour, drifting parallax clouds,
// terrain-stepped ridges and the first stars, and `ui/parts/KitProp.qml` draws
// one cell of the frozen prop kit -- which has a `gantry`: a steel truss arch
// with a checkered beam, lamps, two chequered flags that flap, and TURBO TABLES
// baked on its header board. So the two things this screen was faking are now
// parts, and this file stops faking them:
//
//   * THE SKY IS THE RACE'S SKY. One `SunsetSky` at `nightfall` 0, which is
//     lap 1, which is the lap the child is one second away from starting. The
//     cut lines, the ridge line, the cloud streaks and the halo are the ones
//     the race opens on, because they are the same object.
//   * THE GANTRY IS THE KIT'S. A `KitProp` standing on the road at the world
//     scale the race stands it at, flags flapping at the circuit's own three a
//     second. It is the FIRST landmark of the circuit -- `Circuit.js` puts a
//     `gantry` at s = 3.5, over the start grid -- so the arch the child counts
//     down under is the arch they drive under.
//
// WHAT IS STILL PAINTED HERE, AND WHY. The ground. The race's floor is
// `shaders/road.frag` and `ui/CanvasRoad.qml`, both of which are piece 4's and
// both of which need a moving camera, a circuit and a terrain to say anything;
// this screen is one still frame of a road that is not moving yet. So the floor,
// the grid, the tarmac, the start grid and the kart's cast shadow are a canvas,
// as they were -- painted once, never repainted while the countdown runs.
//
// THE LIGHT IS THE PLAN'S: one key, the sun, low and behind-right of the
// subject; every object a silhouette with a warm rim on its sun side; shadows
// long, toward the camera. The gantry gets that from `Circuit.TINT`'s own
// numbers for a gantry rather than from a second opinion invented here.
Item {
  id: scene

  // The layer resolution. 480 x 270 is where the design puts the game's art,
  // and it is what `ui/TrackView.qml` draws its own sky and road into, so the
  // two screens share a pixel size as well as a sky.
  property int layerW: 480
  property int layerH: 270

  // Composition, as fractions of the frame.
  property real horizon: 0.575
  property real sunX: 0.66
  property real vanishX: 0.52        // where the road and the grid converge

  // Where the kart stands, so its long shadow can be laid on the floor.
  property real kartFootX: 0.44
  property real kartFootY: 0.905
  property real kartFootW: 0.28

  // Seconds. The two things in this scene that move are bound to it: the
  // gantry's flags and the cloud drift. The countdown drives it, and stops
  // driving it under reduced motion, which is why neither is an animation
  // declared down here.
  property real clock: 0

  // ---------------------------------------------------------------- the sky
  //
  // THE PALETTE IS NOT DECLARED IN THIS FILE ANY MORE. Sixteen colours used to
  // be, and eight of them were a second copy of `SunsetSky`'s -- which is how
  // the two skies drifted in the first place. What is left is the four tones
  // the GROUND is painted in, which the shared sky has no opinion about.
  readonly property color floorTone: "#3c1228"
  readonly property color neon: "#ff4fa3"
  readonly property color tarmac: "#1c0a18"
  readonly property color cream: "#f2e6c4"

  // What the sky says its colours are, republished so the screen above and the
  // spec can read them from one place. `sunCore` and `sunEdge` are the disc's
  // two tones and the type has to clear both; the three hill tones are how a
  // test finds the skyline without re-deriving `SunsetSky`'s ridge arithmetic,
  // which is the copied-number mistake this whole file is a correction of.
  readonly property color sunCore: sunset.sunCore
  readonly property color sunEdge: sunset.sunEdge
  readonly property color hillFar: sunset.hillFar
  readonly property color hillMid: sunset.hillMid
  readonly property color hillNear: sunset.hillNear
  readonly property color skyLow: sunset.skyLow

  // The disc, in this item's own coordinates, from the sky's own numbers.
  // `SunsetSky` puts the sun's centre `sunLift` of a radius above the horizon
  // and draws a true circle in plane pixels, so it is an ellipse here whenever
  // the frame is not 16:9 -- hence two radii.
  readonly property real layerSunR: sunset.sunRadius * scene.layerH
  readonly property real layerSunY: scene.layerHorizonY
                                    - scene.layerSunR * (sunset.sunLift * 2 - 1)
  readonly property real sunCentreX: scene.frameX(Math.round(scene.sunX * scene.layerW))
  readonly property real sunCentreY: scene.frameY(scene.layerSunY)
  readonly property real sunRadiusX: scene.frameX(scene.layerSunR)
  readonly property real sunRadiusY: scene.frameY(scene.layerSunR)
  readonly property real sunTopY: scene.frameY(scene.layerSunY - scene.layerSunR)
  // The line the hills stand on. A test walking the sun's centre column stops
  // at the first hill TONE above this, not at this line: the ridges rise above
  // the horizon and how far is `SunsetSky`'s business.
  readonly property real horizonYPx: scene.frameY(scene.layerHorizonY)

  readonly property real layerHorizonY: Math.round(scene.layerH * scene.horizon)
  readonly property real layerDepth: scene.layerH - scene.layerHorizonY

  // ------------------------------------------------------------- the road
  // The road's convergence, hoisted out of paint(): the gantry stands on the
  // road, so where the road is at the gantry's depth is what decides how big
  // the gantry is and where its posts land.
  readonly property real layerVanishX: Math.round(scene.layerW * scene.vanishX)
  readonly property real layerRoadL: scene.layerW * 0.14
  readonly property real layerRoadR: scene.layerW * 0.78
  function layerEdgeL(y) {
    return scene.layerVanishX + (scene.layerRoadL - scene.layerVanishX)
           * (y - scene.layerHorizonY) / Math.max(1, scene.layerDepth)
  }
  function layerEdgeR(y) {
    return scene.layerVanishX + (scene.layerRoadR - scene.layerVanishX)
           * (y - scene.layerHorizonY) / Math.max(1, scene.layerDepth)
  }

  // Layer pixels to this item's pixels, which are the frame's.
  function frameX(lx) { return scene.width * lx / Math.max(1, scene.layerW) }
  function frameY(ly) { return scene.height * ly / Math.max(1, scene.layerH) }

  // ====================================================== THE KIT'S GANTRY
  //
  // How far down the depth the arch stands, as a fraction. It is the one number
  // that trades the size of the countdown's numeral against the size of the
  // words on the board, and both of those are things the plan asks for by name
  // ("the number is enormous"; "the numeral covers the gantry's board"), so it
  // is declared here with the trade written next to it rather than buried.
  //
  //   the arch is 10.46 world units across its opaque box and 5.30 tall, on a
  //   road 3.80 wide (`TrackView.roadHalf` = 1.90). The flat gantry this file
  //   used to draw was 0.57 road-widths tall. The kit's is 1.39. So the real
  //   arch takes more of the frame than the drawn one did at the same distance,
  //   and standing it where the drawn one stood would put its board at 30% of
  //   the frame height and leave the numeral a quarter of the picture.
  //
  // The value below is the one the round's frames were chosen from; see the
  // report's table of `gantryFoot` against the numeral's ink and the board's
  // type height.
  property real gantryFoot: 0.135

  readonly property real layerGantryFootY: scene.layerHorizonY
                                           + scene.layerDepth * scene.gantryFoot
  // The road's width at that depth, in this frame's own pixels, and the world
  // scale that follows from it. `KitProp` wants screen pixels per world unit
  // and nothing else: hand it the road's own, and the arch comes out at the
  // size the race draws it at, because on the track it is the same division.
  readonly property real gantryRoadPx: scene.frameX(scene.layerEdgeR(scene.layerGantryFootY))
                                       - scene.frameX(scene.layerEdgeL(scene.layerGantryFootY))
  readonly property real roadWorldWidth: 3.80
  readonly property real gantryPxPerUnit: scene.gantryRoadPx
                                          / Math.max(0.1, scene.roadWorldWidth)

  // WHERE THE SPONSOR PLATE IS ON THE SHEET, measured off `assets/props/
  // gantry.png` and expressed as fractions of the prop's own opaque box, so it
  // survives every scale step and every frame size.
  //
  // The plate is cell pixels x 405..1058, y 142..241, identical in `C0` and
  // `C1` -- only the flags move between the two frames -- and the `C0` opaque
  // box is (104, 50) to (1387, 700). The four fractions below are those two
  // rectangles divided.
  //
  // IT IS THE PLATE AND NOT THE WHOLE HEADER BAND, and the difference is the
  // whole evidence. The beam's chequers run at the same HEIGHT as the plate, to
  // its left and its right, and they are cream: over the plate's own rows the
  // full width of the arch carries 10,482 cream pixels, of which 10,444 are
  // chequers. The guard that says "no cream of the numeral falls inside the
  // board" counts cream, so a rect that swallowed the chequers would either be
  // permanently red or would have to be given a tolerance wide enough to hide
  // the numeral as well. Inside x 405..1058 the bake carries 0 cream, 5,236
  // pixels of amber ink in 336 columns and 56,051 of plate.
  readonly property real boardBoxL: (405 - 104) / 1283
  readonly property real boardBoxR: (1059 - 104) / 1283
  readonly property real boardBoxT: (142 - 50) / 650
  readonly property real boardBoxB: (242 - 50) / 650

  // The board's two colours, as the bake made them: `#f5a524` amber type on the
  // `#1a1b26` plate. A contrast figure is a claim about a PAIR, so the pair is
  // named in one place. They are not this file's choice -- they are the kit's,
  // and the kit is frozen art.
  //
  // Neither is cream, and that matters for the same reason it mattered when the
  // board was painted here: the evidence for "the numeral no longer covers the
  // board" is a count of CREAM pixels inside the board's rows, and cream type on
  // the board would make the count meaningless. `#f5a524` and `#1a1b26` are both
  // far outside the +/- 14 per channel that count allows around `#f2e6c4`.
  readonly property color boardInk: "#f5a524"
  readonly property color boardFill: "#1a1b26"

  // The board's rectangle in this item's own coordinates, from the prop's own
  // drawn box. `KitProp.boxLeft/boxTop/boxWidth/boxHeight` are the opaque box
  // relative to the contact point, which is where the item is standing.
  readonly property real boardLeftX: gantry.x + gantry.boxLeft
                                     + scene.boardBoxL * gantry.boxWidth
  readonly property real boardRightX: gantry.x + gantry.boxLeft
                                      + scene.boardBoxR * gantry.boxWidth
  readonly property real boardTopY: gantry.y + gantry.boxTop
                                    + scene.boardBoxT * gantry.boxHeight
  readonly property real boardBottomY: gantry.y + gantry.boxTop
                                       + scene.boardBoxB * gantry.boxHeight
  // The whole arch's box, which is what the type above actually has to clear:
  // the flags stand a little higher than the board and they are art too.
  readonly property real gantryTopY: gantry.y + gantry.boxTop
  readonly property real gantryLeftX: gantry.x + gantry.boxLeft
  readonly property real gantryRightX: gantry.x + gantry.boxLeft + gantry.boxWidth

  // ------------------------------------------------------------- the plane
  //
  // Sky and ground, drawn at 480 x 270 and scaled up with nearest-neighbour, so
  // both share one pixel size with the race's own picture. `layer.enabled` is
  // the same measurement `ui/TrackView.qml` records: with eight items in here
  // each scaled up on its own the software renderer pays for eight upscales a
  // frame; composed once at 480 x 270 and blitted, it pays for one.
  Item {
    id: plane
    width: scene.layerW
    height: scene.layerH
    transform: Scale {
      xScale: scene.width / Math.max(1, scene.layerW)
      yScale: scene.height / Math.max(1, scene.layerH)
    }
    layer.enabled: true
    layer.smooth: false
    layer.textureSize: Qt.size(scene.layerW, scene.layerH)

    // `SunsetSky`'s gradient dome is 0.56 of `unitH` tall, and this scene's
    // horizon is at 0.575 of the frame -- three plane rows lower than the dome
    // reaches. This is the gradient's own top stop filling those three rows, so
    // the top of the frame is the colour the sky starts at rather than the void
    // behind the scene. Nothing else is ever visible through it.
    Rectangle {
      anchors.fill: parent
      color: sunset.skyTop
    }

    SunsetSky {
      id: sunset
      anchors.fill: parent
      horizon: scene.horizon
      unitH: scene.layerH
      sunX: scene.sunX
      // Lap 1. The countdown is the second before lap 1 and the hour has not
      // started passing yet, so this is the golden hour the race opens on and
      // the same hour the garage door looks out onto.
      nightfall: 0
      stars: 0
      lateral: 0
      // The clouds drift. It is the only thing in the backdrop that moves, and
      // it is what stops a four-second screen reading as a photograph. Same
      // rate the track drives them at.
      drift: scene.clock * 1.6
    }

    // ------------------------------------------------------------ the ground
    // Floor, grid, tarmac, start grid and the kart's long shadow: one canvas,
    // painted when the geometry changes and never while the countdown runs.
    Canvas {
      id: ground
      x: 0
      y: scene.layerHorizonY
      width: scene.layerW
      height: scene.layerH - scene.layerHorizonY
      renderStrategy: Canvas.Immediate
      renderTarget: Canvas.Image
      smooth: false
      antialiasing: false

      function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

      onPaint: {
        var ctx = getContext("2d")
        var W = width
        var depth = height
        // The canvas starts AT the horizon, so a row `y` here is
        // `scene.layerHorizonY + y` in the plane. Everything below works in
        // plane rows and subtracts the offset once, at the draw.
        var yH = scene.layerHorizonY
        function py(y) { return y - yH }
        ctx.reset()
        ctx.clearRect(0, 0, W, depth)

        // ---------------------------------------------------------- floor
        ctx.fillStyle = scene.floorTone
        ctx.fillRect(0, 0, W, depth)

        // The diagnostic grid, neon, converging on the vanishing point.
        var vx = scene.layerVanishX
        ctx.strokeStyle = ground.rgba(scene.neon, 0.24)
        ctx.lineWidth = 1
        var rows = 13
        for (var r = 1; r <= rows; r++) {
          var t = r / rows
          var gy = Math.round(depth * t * t) + 0.5
          ctx.beginPath()
          ctx.moveTo(0, gy)
          ctx.lineTo(W, gy)
          ctx.stroke()
        }
        for (var gx = -W; gx <= W * 2; gx += 34) {
          ctx.beginPath()
          ctx.moveTo(vx + 0.5, 0)
          ctx.lineTo(gx + 0.5, depth)
          ctx.stroke()
        }

        // The floor fades up into the horizon glow, and the grid with it. The
        // tone is the sky's own bottom stop, so the ground meets the sky in one
        // colour -- which is what `TrackView.fogTone` is bound to for exactly
        // the same reason.
        var haze = ctx.createLinearGradient(0, 0, 0, depth * 0.36)
        haze.addColorStop(0, ground.rgba(scene.skyLow, 0.85))
        haze.addColorStop(0.45, ground.rgba(scene.skyLow, 0.32))
        haze.addColorStop(1, ground.rgba(scene.skyLow, 0))
        ctx.fillStyle = haze
        ctx.fillRect(0, 0, W, depth * 0.36)

        // ----------------------------------------------------------- road
        var roadL = scene.layerRoadL
        var roadR = scene.layerRoadR
        var H = scene.layerH
        function edgeL(y) { return scene.layerEdgeL(y) }
        function edgeR(y) { return scene.layerEdgeR(y) }
        ctx.fillStyle = scene.tarmac
        ctx.beginPath()
        ctx.moveTo(vx, 0)
        ctx.lineTo(roadR, depth)
        ctx.lineTo(roadL, depth)
        ctx.closePath()
        ctx.fill()
        ctx.strokeStyle = ground.rgba(scene.cream, 0.85)
        ctx.lineWidth = 1.5
        ctx.beginPath()
        ctx.moveTo(vx, 2)
        ctx.lineTo(roadL, depth)
        ctx.moveTo(vx, 2)
        ctx.lineTo(roadR, depth)
        ctx.stroke()

        // The dashed centre line, which is what the race's road carries and
        // this one did not. Dashes in perspective: each one is a quad between
        // two depths, so they shorten and narrow toward the vanishing point the
        // way the road does.
        ctx.fillStyle = ground.rgba(scene.cream, 0.72)
        for (var d = 0; d < 9; d++) {
          var u0 = Math.pow(d / 9, 1.7)
          var u1 = Math.pow((d + 0.52) / 9, 1.7)
          var da = yH + scene.layerDepth * u0
          var db = yH + scene.layerDepth * u1
          var ha = Math.max(0.4, (edgeR(da) - edgeL(da)) * 0.012)
          var hb = Math.max(0.4, (edgeR(db) - edgeL(db)) * 0.012)
          var ca = (edgeL(da) + edgeR(da)) / 2
          var cb = (edgeL(db) + edgeR(db)) / 2
          ctx.beginPath()
          ctx.moveTo(ca - ha, py(da))
          ctx.lineTo(ca + ha, py(da))
          ctx.lineTo(cb + hb, py(db))
          ctx.lineTo(cb - hb, py(db))
          ctx.closePath()
          ctx.fill()
        }

        // Tarmac takes the glow too, or the road is a black wedge cut out of
        // a sunset.
        var roadHaze = ctx.createLinearGradient(0, 0, 0, depth * 0.5)
        roadHaze.addColorStop(0, ground.rgba(scene.skyLow, 0.60))
        roadHaze.addColorStop(1, ground.rgba(scene.skyLow, 0))
        ctx.fillStyle = roadHaze
        ctx.beginPath()
        ctx.moveTo(vx, 0)
        ctx.lineTo(edgeR(yH + scene.layerDepth * 0.5), depth * 0.5)
        ctx.lineTo(edgeL(yH + scene.layerDepth * 0.5), depth * 0.5)
        ctx.closePath()
        ctx.fill()

        // THE START GRID, AND IT IS THE RACE'S. The road under the gantry in
        // `ui/TrackView.qml` is a wide chequer of six columns and four rows,
        // cream against the road's own dark. This drew ten columns and two
        // rows, which at 1920 x 1080 is a thin band of small squares -- a
        // different marking on a different road from the one the child is on a
        // second later.
        var lineY0 = yH + scene.layerDepth * 0.50
        var lineY1 = yH + scene.layerDepth * 0.66
        var cols = 6
        var gridRows = 4
        for (var row = 0; row < gridRows; row++) {
          var ya = lineY0 + (lineY1 - lineY0) * row / gridRows
          var yb = lineY0 + (lineY1 - lineY0) * (row + 1) / gridRows
          var la = edgeL(ya), ra = edgeR(ya)
          var lb = edgeL(yb), rb = edgeR(yb)
          for (var c = 0; c < cols; c++) {
            if ((c + row) % 2 !== 0)
              continue
            ctx.fillStyle = scene.cream
            ctx.beginPath()
            ctx.moveTo(la + (ra - la) * c / cols, py(ya))
            ctx.lineTo(la + (ra - la) * (c + 1) / cols, py(ya))
            ctx.lineTo(lb + (rb - lb) * (c + 1) / cols, py(yb))
            ctx.lineTo(lb + (rb - lb) * c / cols, py(yb))
            ctx.closePath()
            ctx.fill()
          }
        }

        // ------------------------------------------------ the kart's shadow
        // Long, toward the camera and a little left, because the sun is ahead
        // and to the right. It widens as it comes, which is what a shadow on a
        // floor seen from low down does.
        var fx = W * scene.kartFootX
        var fy = H * scene.kartFootY
        var fw = W * scene.kartFootW
        var len = Math.min(H - 1 - fy, scene.layerDepth * 0.44)
        var drift = -fw * 0.95
        var sh = ctx.createLinearGradient(0, py(fy), 0, py(fy + len))
        sh.addColorStop(0, Qt.rgba(0.06, 0.02, 0.05, 0.72))
        sh.addColorStop(1, Qt.rgba(0.06, 0.02, 0.05, 0.10))
        ctx.fillStyle = sh
        ctx.beginPath()
        ctx.moveTo(fx - fw * 0.60, py(fy - 4))
        ctx.lineTo(fx + fw * 0.40, py(fy - 4))
        ctx.lineTo(fx + fw * 0.70 + drift, py(fy + len))
        ctx.lineTo(fx - fw * 0.90 + drift, py(fy + len))
        ctx.closePath()
        ctx.fill()
      }
    }
  }

  // ====================================================== THE ARCH, ON TOP
  //
  // OUTSIDE THE PLANE, and that is deliberate rather than an oversight. The kit
  // is baked at FINE = 4 times the karts' pixels per world unit, so a prop
  // drawn at its projected size is already at or above the frame's resolution;
  // drawing it into a 480 x 270 plane would throw three quarters of that away
  // and then upscale the remains four times. `ui/TrackView.qml` draws its whole
  // roadside outside the plane for the same reason.
  KitProp {
    id: gantry
    kind: "gantry"
    // Two frames at three a second: `Circuit.frameOf`'s "flag" animation, which
    // is what the same arch does on the track. Held on frame 0 under reduced
    // motion, because a two-frame alternation is motion and the design's
    // accessibility section says what to do about motion.
    viewIndex: scene.clock > 0 ? (Math.floor(scene.clock * 3) % 2) : 0
    pxPerUnit: scene.gantryPxPerUnit
    x: scene.frameX((scene.layerEdgeL(scene.layerGantryFootY)
                     + scene.layerEdgeR(scene.layerGantryFootY)) / 2)
    y: scene.frameY(scene.layerGantryFootY)
    z: 2
    clarity: 1.0
    // The hour, on the kit, at lap 1 -- `Circuit.TINT`'s own row for a gantry
    // (`[0.40, 0.70, 0.54, 0.018]`: wash at lap 1, wash at lap 12, key at lap 1,
    // reach) with `nightfall` at 0. The numbers are the circuit's because how
    // much of the sun a steel truss takes is a property of the truss, and this
    // screen is not the place to hold a second opinion about it.
    washColor: "#7d1a5e"
    washAmount: 0.40
    keyColor: "#f0b07a"
    keyAmount: 0.54
    keyReach: 0.018
  }

  onWidthChanged: ground.requestPaint()
  onHeightChanged: ground.requestPaint()
  onKartFootXChanged: ground.requestPaint()
  onKartFootYChanged: ground.requestPaint()
  onKartFootWChanged: ground.requestPaint()
}
