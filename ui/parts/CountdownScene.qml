import QtQuick
import "../"

// PROTOTYPE (proto/golden-hour): the start-line backdrop behind the countdown.
//
// One canvas, painted once at the design's 480x270 layer and scaled up with
// nearest-neighbour, so the sky, the sun, the hills, the neon floor, the road
// and the gantry share one pixel size with the race's own sprites. Everything
// in it is a gradient, a silhouette or a flat fill: the bar is palette, light
// and composition, not brushwork.
//
// The light is the one key the direction names: the sun, low, ahead and to the
// right of the camera. Every prop in here is a silhouette against it with a
// warm rim on its sun side, and the child's kart (a CarSprite cell drawn on
// top of this) throws its shadow toward the camera, across this floor -- that
// shadow is drawn here because the floor is here.
//
// NOTE, CORRECTED IN ROUND 6. `ui/parts/SunsetSky.qml` DOES exist -- 213
// lines of it -- and `ui/TrackView.qml:594` draws the race view's sky with it.
// The note that stood here said the opposite, and it was written before the
// part landed. So this file is a second sky, and the two have drifted: this
// one paints sky, sun, hills, floor, grid, road, start line, gantry and the
// kart's cast shadow into ONE canvas at 480 x 270 and never repaints while the
// countdown runs; SunsetSky paints sky and hills into four canvases that
// parallax against a `lateral` the track drives, and knows nothing about a
// road, a gantry or a floor. Plan v2 wants one part shared by TrackView, the
// garage door and this screen.
//
// Adopting it is a real piece of work -- SunsetSky would have to grow the
// horizon-and-below half, or this file would have to split -- and the part is
// shared and unowned, so round 6 did not take it unilaterally. What round 6
// did do is fix the defect the divergence was hiding: both suns draw the
// genre's cut lines and both had them eaten by their own hills. The fit below
// (`layerSkylineY`) is the recipe SunsetSky needs too.
Item {
  id: scene

  // The layer resolution. 480x270 is where the design puts the game's art;
  // doubling it is the one knob to turn if the maintainer wants finer hills.
  property int layerW: 480
  property int layerH: 270

  // Composition, as fractions of the frame.
  property real horizon: 0.575
  property real sunX: 0.66
  property real sunRadius: 0.20      // of frame height
  property real vanishX: 0.52        // where the road and the grid converge

  // Where the kart stands, so its long shadow can be laid on the floor.
  property real kartFootX: 0.44
  property real kartFootY: 0.905
  property real kartFootW: 0.28

  // The palette the direction sampled off the bar.
  readonly property color skyTop: "#5e1a50"
  readonly property color skyHigh: "#a4337b"
  readonly property color skyMid: "#c24073"
  readonly property color glow: "#d75d6b"
  readonly property color sunCore: "#efcb72"
  readonly property color sunEdge: "#f0956e"
  readonly property color hillFar: "#bc405f"
  readonly property color hillMid: "#8e2c50"
  readonly property color hillNear: "#5e1a50"
  readonly property color floor: "#3c1228"
  readonly property color neon: "#ff4fa3"
  readonly property color tarmac: "#1c0a18"
  readonly property color signage: "#280e27"
  readonly property color rim: "#f0b07a"
  readonly property color cream: "#f2e6c4"

  // The sponsor board's own two colours, named here because a contrast figure
  // is a claim about a PAIR and the pair should be legible in one place.
  //
  // ROUND 6. Round 5 drew the words in `skyMid` on `signage`: 3.62:1, which
  // passes WCAG AA for large text and fails it for normal text -- and these
  // glyphs are 9 layer pixels tall, which at 1366 x 768 is about 25 screen
  // pixels, right on the boundary. The board's own neon against the same
  // near-black is 5.83:1 and passes AA for normal text outright. It is also
  // what the bar does: the `quattro` board in `docs/golden-hour-reference.png`
  // is hot pink type on near-black, not a darker pink on it.
  //
  // It must not be cream. The evidence for "the numeral no longer covers the
  // board" is a count of CREAM pixels inside the board's own rows, and cream
  // type on the board would make that count meaningless. `#ff4fa3` is 54 and
  // 74 away from `#f2e6c4` in green and blue, well outside the +/-14 per
  // channel that count allows.
  readonly property color boardFill: scene.signage
  readonly property color boardInk: scene.neon

  // ------------------------------------------------------ the gantry board
  //
  // ROUND 5. The sponsor board over the road carries the only words in this
  // painting, and for three rounds the countdown's numeral was drawn straight
  // through them: at 1920 x 1080 the `3` covered the middle of `TURBO TABLES`
  // on every one of beats 3, 2 and 1, and the board only became legible on GO,
  // when the numeral shrank and moved. The plan lists that as this piece's
  // remaining defect.
  //
  // The screen above cannot keep its type off the board unless it knows where
  // the board is, and a number copied into two files is a number that drifts.
  // So the geometry the painter uses is declared here, once, in the layer's own
  // pixels -- and `boardTopY` republishes it in this item's pixels, which are
  // the frame's. `paint()` reads these properties rather than recomputing them,
  // so the published edge and the painted edge cannot disagree.
  readonly property real layerHorizonY: Math.round(scene.layerH * scene.horizon)
  readonly property real layerDepth: scene.layerH - scene.layerHorizonY
  readonly property real layerGantryFootY: scene.layerHorizonY + scene.layerDepth * 0.30
  readonly property int gantryPostH: 40
  readonly property int gantryPostW: 4
  readonly property int gantryBoardH: 12
  readonly property real layerBeamY: Math.round(scene.layerGantryFootY - scene.gantryPostH)
  readonly property real layerBoardTopY: scene.layerBeamY - scene.gantryBoardH

  // The road's own convergence, hoisted out of paint() for the same reason:
  // the gantry stands on the road's edges, so the board's left and right are
  // the road's, and a test that wants to look at the board's pixels needs to
  // be told where they are rather than re-deriving them.
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
  readonly property real layerBoardLeftX: Math.round(scene.layerEdgeL(scene.layerGantryFootY)) - 8
  readonly property real layerBoardRightX: Math.round(scene.layerEdgeR(scene.layerGantryFootY))
                                           + 4 + scene.gantryPostW

  // Layer pixels to this item's pixels, which are the frame's.
  function frameX(lx) { return scene.width * lx / Math.max(1, scene.layerW) }
  function frameY(ly) { return scene.height * ly / Math.max(1, scene.layerH) }

  // The board's rectangle in this item's own coordinates. Type above the scene
  // keeps its ink above `boardTopY`; a test that wants to read the words off
  // the picture reads the whole rect.
  readonly property real boardTopY: scene.frameY(scene.layerBoardTopY)
  readonly property real boardBottomY: scene.frameY(scene.layerBeamY)
  readonly property real boardLeftX: scene.frameX(scene.layerBoardLeftX)
  readonly property real boardRightX: scene.frameX(scene.layerBoardRightX)

  // ------------------------------------------------------------ the hills
  //
  // The three silhouettes, far to near, as data rather than as three closures
  // inside paint(). `ridgeBase` is how far above the horizon each one stands
  // before its own undulation; `ridgeWave` is that undulation. They are up
  // here because the sun's cut lines have to be fitted to the arc the hills
  // LEAVE, and a ridge line copied into two places is a ridge line that
  // drifts -- which is exactly how the sun lost its bands.
  readonly property var ridgeBase: [14, 7, 2]
  function ridgeWave(i, x) {
    var W = scene.layerW
    if (i === 0)
      return 10 * Math.sin(x * 0.021 + 1.2) + 5 * Math.sin(x * 0.053 + 0.4)
           + 3 * Math.sin(x * 0.13) + 9 * (1 - x / W)
    if (i === 1)
      return 6 * Math.sin(x * 0.030 + 2.6) + 3 * Math.sin(x * 0.080)
           + 2 * Math.sin(x * 0.19 + 0.9)
    return 3 * Math.sin(x * 0.045 + 0.7) + 2 * Math.sin(x * 0.11 + 1.9)
  }
  function ridgeTopY(x) {
    var top = scene.layerHorizonY
    for (var i = 0; i < scene.ridgeBase.length; i++)
      top = Math.min(top, scene.layerHorizonY - scene.ridgeBase[i] - scene.ridgeWave(i, x))
    return top
  }

  // -------------------------------------------------------------- the sun
  readonly property real layerSunX: Math.round(scene.layerW * scene.sunX)
  readonly property real layerSunR: Math.round(scene.layerH * scene.sunRadius)
  readonly property real layerSunY: scene.layerHorizonY
                                    - Math.round(scene.layerSunR * 0.62)

  // The highest any ridge reaches anywhere across the sun's own width. A cut
  // line drawn above this row is visible right across the disc; one drawn
  // below it may be behind a hill at some column.
  //
  // ROUND 6, and this is the whole fix. The cut lines are the genre's
  // signature and the reference's defining feature, and ours were laid from
  // `sy + R * 0.10` downward on a fixed rhythm -- which put four of the seven
  // above the horizon and three of THOSE four behind the ridge. A column
  // through the disc's centre gave 208 unbroken rows of flat `#efcb72` and one
  // 4-row band: a flat yellow dome with a stripe. So the stack is now FITTED
  // to `layerSkylineY`, computed from the same ridge data that draws the
  // hills, and the sun is banded everywhere a child can see it.
  readonly property real layerSkylineY: {
    var top = scene.layerHorizonY
    var x0 = Math.floor(scene.layerSunX - scene.layerSunR)
    var x1 = Math.ceil(scene.layerSunX + scene.layerSunR)
    for (var x = x0; x <= x1; x++)
      top = Math.min(top, scene.ridgeTopY(x))
    return top
  }
  // Where the banding begins: a little above the disc's own centre, so the top
  // of the sun stays a solid dome the way the reference's does, and everything
  // below it is cut.
  readonly property real layerSunBandTopY: Math.round(scene.layerSunY
                                                      - scene.layerSunR * 0.55)
  // Each entry is (how far down the banded span the cut starts, how thick it
  // is in layer pixels). Thin at the top, thickening downward, gaps closing:
  // the shape the reference's sun has.
  readonly property var sunCutStack: [[0.00, 1], [0.15, 1], [0.30, 2], [0.45, 2],
                                      [0.62, 3], [0.79, 3], [0.94, 4]]
  // What a test can read back without knowing the arithmetic: how many of the
  // stack's cuts land in the arc the hills leave uncovered.
  readonly property int sunCutsAboveSkyline: {
    var n = 0
    var span = scene.layerSkylineY - 1 - scene.layerSunBandTopY
    for (var i = 0; i < scene.sunCutStack.length; i++)
      if (Math.round(scene.layerSunBandTopY + span * scene.sunCutStack[i][0])
          < scene.layerSkylineY)
        n += 1
    return n
  }
  // The disc, in this item's own coordinates. It is drawn as a circle in layer
  // pixels and then scaled, so it is an ellipse here whenever the frame is not
  // 16:9 -- hence two radii.
  readonly property real sunCentreX: scene.frameX(scene.layerSunX)
  readonly property real sunCentreY: scene.frameY(scene.layerSunY)
  readonly property real sunRadiusX: scene.frameX(scene.layerSunR)
  readonly property real sunRadiusY: scene.frameY(scene.layerSunR)
  readonly property real sunTopY: scene.frameY(scene.layerSunY - scene.layerSunR)
  readonly property real skylineY: scene.frameY(scene.layerSkylineY)

  Canvas {
    id: layer
    width: scene.layerW
    height: scene.layerH
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
    antialiasing: false
    transform: Scale {
      xScale: scene.width / Math.max(1, scene.layerW)
      yScale: scene.height / Math.max(1, scene.layerH)
    }

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) {
      return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                     a.b + (b.b - a.b) * t, 1)
    }

    onPaint: {
      var ctx = getContext("2d")
      var W = width
      var H = height
      var yH = Math.round(H * scene.horizon)
      ctx.reset()
      ctx.clearRect(0, 0, W, H)

      // ------------------------------------------------------------ sky
      var sky = ctx.createLinearGradient(0, 0, 0, yH)
      sky.addColorStop(0.00, scene.skyTop)
      sky.addColorStop(0.35, scene.skyHigh)
      sky.addColorStop(0.70, scene.skyMid)
      sky.addColorStop(1.00, scene.glow)
      ctx.fillStyle = sky
      ctx.fillRect(0, 0, W, yH + 1)

      // Streaky cloud bands: three soft horizontal shapes, each a shade off
      // the sky behind it, fading out at both ends.
      var bands = [
        { y: 0.16, h: 7, x0: 0.05, x1: 0.70, c: scene.skyMid, a: 0.55 },
        { y: 0.27, h: 5, x0: 0.30, x1: 0.98, c: scene.skyTop, a: 0.35 },
        { y: 0.40, h: 9, x0: 0.00, x1: 0.62, c: scene.glow, a: 0.45 },
        { y: 0.47, h: 4, x0: 0.45, x1: 1.00, c: scene.skyHigh, a: 0.50 }
      ]
      for (var b = 0; b < bands.length; b++) {
        var bd = bands[b]
        var bx0 = W * bd.x0, bx1 = W * bd.x1
        var bg = ctx.createLinearGradient(bx0, 0, bx1, 0)
        bg.addColorStop(0, rgba(bd.c, 0))
        bg.addColorStop(0.35, rgba(bd.c, bd.a))
        bg.addColorStop(0.75, rgba(bd.c, bd.a))
        bg.addColorStop(1, rgba(bd.c, 0))
        ctx.fillStyle = bg
        var by = Math.round(yH * bd.y)
        ctx.fillRect(bx0, by, bx1 - bx0, bd.h)
        ctx.fillRect(bx0 + (bx1 - bx0) * 0.18, by + bd.h + 2, (bx1 - bx0) * 0.6, Math.max(1, bd.h * 0.4))
      }

      // ------------------------------------------------------------ sun
      var sx = scene.layerSunX
      var R = scene.layerSunR
      var sy = scene.layerSunY
      var halo = ctx.createRadialGradient(sx, sy, R * 0.6, sx, sy, R * 3.4)
      halo.addColorStop(0.00, rgba(scene.glow, 0.95))
      halo.addColorStop(0.30, rgba(scene.glow, 0.55))
      halo.addColorStop(0.65, rgba(scene.glow, 0.18))
      halo.addColorStop(1.00, rgba(scene.glow, 0))
      ctx.fillStyle = halo
      ctx.fillRect(0, 0, W, H)

      var disc = ctx.createRadialGradient(sx, sy - R * 0.2, R * 0.15, sx, sy, R)
      disc.addColorStop(0.00, scene.sunCore)
      disc.addColorStop(0.72, scene.sunCore)
      disc.addColorStop(1.00, scene.sunEdge)
      ctx.fillStyle = disc
      ctx.beginPath()
      ctx.arc(sx, sy, R, 0, Math.PI * 2)
      ctx.fill()

      // The genre's signature: cut lines through the disc, thin near the top
      // and thickening downward, in the colour of the sky they let through.
      //
      // The stack is fitted between `layerSunBandTopY` and the skyline, not
      // laid on a fixed rhythm from the disc's centre -- see the long note by
      // `layerSkylineY`. Below the skyline it carries on at the rhythm it ends
      // on, so a column where the ridge happens to be low shows banded sun and
      // not a flat foot.
      ctx.save()
      ctx.beginPath()
      ctx.arc(sx, sy, R, 0, Math.PI * 2)
      ctx.clip()
      ctx.fillStyle = scene.glow
      var bandTop = scene.layerSunBandTopY
      var bandSpan = scene.layerSkylineY - 1 - bandTop
      var stack = scene.sunCutStack
      for (var i = 0; i < stack.length; i++)
        ctx.fillRect(sx - R, Math.round(bandTop + bandSpan * stack[i][0]),
                     R * 2, stack[i][1])
      var tailY = Math.round(bandTop + bandSpan * stack[stack.length - 1][0])
                  + stack[stack.length - 1][1]
      var tailH = 5
      while (tailY < sy + R) {
        ctx.fillRect(sx - R, tailY, R * 2, tailH)
        tailY += tailH + 3
        tailH += 1
      }
      ctx.restore()

      // ---------------------------------------------------------- hills
      // Three silhouette layers, lighter with distance, heavier on the left
      // the way the bar's are, all standing on the floor line. The ridge line
      // is `scene.ridgeTopY`'s -- the same one the sun's bands were fitted to.
      var ridgeTone = [scene.hillFar, scene.hillMid, scene.hillNear]
      for (var rr = 0; rr < ridgeTone.length; rr++) {
        ctx.fillStyle = ridgeTone[rr]
        ctx.beginPath()
        ctx.moveTo(0, yH + 1)
        for (var rx = 0; rx <= W; rx++)
          ctx.lineTo(rx, yH - scene.ridgeBase[rr] - scene.ridgeWave(rr, rx))
        ctx.lineTo(W, yH + 1)
        ctx.closePath()
        ctx.fill()
      }

      // ---------------------------------------------------------- floor
      ctx.fillStyle = scene.floor
      ctx.fillRect(0, yH, W, H - yH)

      // The diagnostic grid, neon, converging on the vanishing point.
      var vx = scene.layerVanishX
      var depth = scene.layerDepth
      ctx.strokeStyle = rgba(scene.neon, 0.28)
      ctx.lineWidth = 1
      var rows = 13
      for (var r = 1; r <= rows; r++) {
        var t = r / rows
        var gy = Math.round(yH + depth * t * t) + 0.5
        ctx.beginPath()
        ctx.moveTo(0, gy)
        ctx.lineTo(W, gy)
        ctx.stroke()
      }
      for (var gx = -W; gx <= W * 2; gx += 34) {
        ctx.beginPath()
        ctx.moveTo(vx + 0.5, yH)
        ctx.lineTo(gx + 0.5, H)
        ctx.stroke()
      }

      // The floor fades up into the horizon glow, and the grid with it.
      var haze = ctx.createLinearGradient(0, yH, 0, yH + depth * 0.36)
      haze.addColorStop(0, rgba(scene.glow, 0.80))
      haze.addColorStop(0.45, rgba(scene.glow, 0.30))
      haze.addColorStop(1, rgba(scene.glow, 0))
      ctx.fillStyle = haze
      ctx.fillRect(0, yH, W, depth * 0.36)

      // ----------------------------------------------------------- road
      // Dark tarmac from the bottom edge to the vanishing point, with the
      // cream edge lines the design gives the road.
      var roadL = scene.layerRoadL
      var roadR = scene.layerRoadR
      function edgeL(y) { return scene.layerEdgeL(y) }
      function edgeR(y) { return scene.layerEdgeR(y) }
      ctx.fillStyle = scene.tarmac
      ctx.beginPath()
      ctx.moveTo(vx, yH)
      ctx.lineTo(roadR, H)
      ctx.lineTo(roadL, H)
      ctx.closePath()
      ctx.fill()
      ctx.strokeStyle = rgba(scene.cream, 0.85)
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(vx, yH + 2)
      ctx.lineTo(roadL, H)
      ctx.moveTo(vx, yH + 2)
      ctx.lineTo(roadR, H)
      ctx.stroke()
      // Tarmac takes the glow too, or the road is a black wedge cut out of
      // a sunset.
      var roadHaze = ctx.createLinearGradient(0, yH, 0, yH + depth * 0.5)
      roadHaze.addColorStop(0, rgba(scene.glow, 0.55))
      roadHaze.addColorStop(1, rgba(scene.glow, 0))
      ctx.fillStyle = roadHaze
      ctx.beginPath()
      ctx.moveTo(vx, yH)
      ctx.lineTo(edgeR(yH + depth * 0.5), yH + depth * 0.5)
      ctx.lineTo(edgeL(yH + depth * 0.5), yH + depth * 0.5)
      ctx.closePath()
      ctx.fill()

      // The start line: two rows of checkers across the road, just ahead of
      // the kart's nose.
      var lineY0 = yH + depth * 0.52
      var lineY1 = yH + depth * 0.60
      var cols = 10
      for (var row = 0; row < 2; row++) {
        var ya = lineY0 + (lineY1 - lineY0) * row / 2
        var yb = lineY0 + (lineY1 - lineY0) * (row + 1) / 2
        for (var c = 0; c < cols; c++) {
          ctx.fillStyle = ((c + row) % 2 === 0) ? scene.cream : scene.signage
          ctx.beginPath()
          ctx.moveTo(edgeL(ya) + (edgeR(ya) - edgeL(ya)) * c / cols, ya)
          ctx.lineTo(edgeL(ya) + (edgeR(ya) - edgeL(ya)) * (c + 1) / cols, ya)
          ctx.lineTo(edgeL(yb) + (edgeR(yb) - edgeL(yb)) * (c + 1) / cols, yb)
          ctx.lineTo(edgeL(yb) + (edgeR(yb) - edgeL(yb)) * c / cols, yb)
          ctx.closePath()
          ctx.fill()
        }
      }

      // ---------------------------------------------------------- gantry
      // A checkered start gantry over the road, between the kart and the sun,
      // silhouetted with one warm rim on its sun side.
      // The four numbers below are the scene's published ones, so the board a
      // child sees is at the line `boardTopY` names.
      var postW = scene.gantryPostW
      var postH = scene.gantryPostH
      var pL = scene.layerBoardLeftX
      var pR = scene.layerBoardRightX - postW
      var beamY = scene.layerBeamY
      ctx.fillStyle = scene.signage
      ctx.fillRect(pL, beamY, postW, postH)
      ctx.fillRect(pR, beamY, postW, postH)
      ctx.fillStyle = scene.rim
      ctx.fillRect(pL + postW - 1, beamY, 1, postH)
      ctx.fillRect(pR + postW - 1, beamY, 1, postH)
      // the beam, checkered
      var cell = 6
      var beamH = cell * 2
      for (var bx = pL; bx < pR + postW; bx += cell) {
        for (var brow = 0; brow < 2; brow++) {
          var odd = (Math.floor((bx - pL) / cell) + brow) % 2 === 0
          ctx.fillStyle = odd ? scene.cream : scene.signage
          ctx.fillRect(bx, beamY + brow * cell, Math.min(cell, pR + postW - bx), cell)
        }
      }
      // the sponsor board above it: period type, hot pink on near-black, the
      // way the bar's own `quattro` board is. `boardInk`/`boardFill` name the
      // pair -- see the note beside them for the 3.62:1 this replaces.
      var boardH = scene.gantryBoardH
      ctx.fillStyle = scene.boardFill
      ctx.fillRect(pL, beamY - boardH, pR + postW - pL, boardH)
      ctx.fillStyle = scene.rim
      ctx.fillRect(pL, beamY - boardH, pR + postW - pL, 1)
      ctx.fillStyle = scene.boardInk
      ctx.font = "bold 9px monospace"
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillText("TURBO TABLES", (pL + pR + postW) / 2, beamY - boardH / 2 + 0.5)

      // ------------------------------------------------ the kart's shadow
      // Long, toward the camera and a little left, because the sun is ahead
      // and to the right. It widens as it comes, which is what a shadow on a
      // floor seen from low down does.
      var fx = W * scene.kartFootX
      var fy = H * scene.kartFootY
      var fw = W * scene.kartFootW
      var len = Math.min(H - 1 - fy, depth * 0.44)
      var drift = -fw * 0.95
      var sh = ctx.createLinearGradient(0, fy, 0, fy + len)
      sh.addColorStop(0, Qt.rgba(0.06, 0.02, 0.05, 0.72))
      sh.addColorStop(1, Qt.rgba(0.06, 0.02, 0.05, 0.10))
      ctx.fillStyle = sh
      ctx.beginPath()
      ctx.moveTo(fx - fw * 0.60, fy - 4)
      ctx.lineTo(fx + fw * 0.40, fy - 4)
      ctx.lineTo(fx + fw * 0.70 + drift, fy + len)
      ctx.lineTo(fx - fw * 0.90 + drift, fy + len)
      ctx.closePath()
      ctx.fill()
    }
  }

  onWidthChanged: layer.requestPaint()
  onHeightChanged: layer.requestPaint()
  onKartFootXChanged: layer.requestPaint()
  onKartFootYChanged: layer.requestPaint()
  onKartFootWChanged: layer.requestPaint()
}
