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
// NOTE: ui/parts/SunsetSky.qml did not exist when this was written, so the
// sky, sun and hills are built here. If SunsetSky lands, the sky half of
// paint() is the part to replace with it.
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
  readonly property int gantryBoardH: 12
  readonly property real layerBeamY: Math.round(scene.layerGantryFootY - scene.gantryPostH)
  readonly property real layerBoardTopY: scene.layerBeamY - scene.gantryBoardH

  // The top edge of the board, in this item's own coordinates. Type above the
  // scene keeps its ink above this line.
  readonly property real boardTopY: scene.height * scene.layerBoardTopY
                                    / Math.max(1, scene.layerH)

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
      var sx = Math.round(W * scene.sunX)
      var R = Math.round(H * scene.sunRadius)
      var sy = yH - Math.round(R * 0.62)
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

      // The genre's signature: cut lines through the lower half of the disc,
      // thickening downward, in the colour of the sky they let through.
      ctx.save()
      ctx.beginPath()
      ctx.arc(sx, sy, R, 0, Math.PI * 2)
      ctx.clip()
      ctx.fillStyle = scene.glow
      var cy = sy + R * 0.10
      for (var i = 0; i < 7; i++) {
        var th = 1 + i * 0.55
        ctx.fillRect(sx - R, Math.round(cy), R * 2, Math.round(th))
        cy += th + Math.max(2, 7 - i * 0.7)
      }
      ctx.restore()

      // ---------------------------------------------------------- hills
      // Three silhouette layers, lighter with distance, heavier on the left
      // the way the bar's are, all standing on the floor line.
      function ridge(colour, base, f) {
        ctx.fillStyle = colour
        ctx.beginPath()
        ctx.moveTo(0, yH + 1)
        for (var x = 0; x <= W; x++)
          ctx.lineTo(x, yH - base - f(x))
        ctx.lineTo(W, yH + 1)
        ctx.closePath()
        ctx.fill()
      }
      ridge(scene.hillFar, 14, function (x) {
        return 10 * Math.sin(x * 0.021 + 1.2) + 5 * Math.sin(x * 0.053 + 0.4)
             + 3 * Math.sin(x * 0.13) + 9 * (1 - x / W)
      })
      ridge(scene.hillMid, 7, function (x) {
        return 6 * Math.sin(x * 0.030 + 2.6) + 3 * Math.sin(x * 0.080)
             + 2 * Math.sin(x * 0.19 + 0.9)
      })
      ridge(scene.hillNear, 2, function (x) {
        return 3 * Math.sin(x * 0.045 + 0.7) + 2 * Math.sin(x * 0.11 + 1.9)
      })

      // ---------------------------------------------------------- floor
      ctx.fillStyle = scene.floor
      ctx.fillRect(0, yH, W, H - yH)

      // The diagnostic grid, neon, converging on the vanishing point.
      var vx = Math.round(W * scene.vanishX)
      var depth = H - yH
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
      var roadL = W * 0.14
      var roadR = W * 0.78
      function edgeL(y) { return vx + (roadL - vx) * (y - yH) / depth }
      function edgeR(y) { return vx + (roadR - vx) * (y - yH) / depth }
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
      var gy0 = scene.layerGantryFootY
      var postW = 4
      var postH = scene.gantryPostH
      var pL = Math.round(edgeL(gy0)) - 8
      var pR = Math.round(edgeR(gy0)) + 4
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
      // the sponsor board above it, period type, near-black on magenta
      var boardH = scene.gantryBoardH
      ctx.fillStyle = scene.signage
      ctx.fillRect(pL, beamY - boardH, pR + postW - pL, boardH)
      ctx.fillStyle = scene.rim
      ctx.fillRect(pL, beamY - boardH, pR + postW - pL, 1)
      ctx.fillStyle = scene.skyMid
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
