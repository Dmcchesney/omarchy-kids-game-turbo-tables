import QtQuick

// The sky at golden hour: what the track, the garage door and the countdown
// all look out onto.
//
// PROTOTYPE. This is the "Golden Hour at the Pit" proposal, not the design's
// garage-at-night. One key light, the sun, low and off-centre right, sitting
// on the horizon; a magenta-to-pink gradient above it; two streaky cloud
// bands; and three silhouette hill layers that parallax with the road's
// lateral offset. Everything here is a gradient, a disc or a silhouette --
// nothing is painted -- so it holds up drawn into a 480 x 270 plane and
// scaled to 1080p with a nearest-neighbour filter.
//
// WHAT IT COSTS. Four textured quads a frame. The sky, the sun and the clouds
// are one canvas painted once and moved with the horizon; each hill layer is
// its own canvas painted once and translated by `lateral`. Nothing repaints
// while the road runs.
//
// HOW TO USE IT. Fill the plane with it, put it BELOW the road, and bind
// `horizon` (0..1 down the item) and `lateral` (the road's far-centre offset
// in this item's pixels: positive when the road bends right). `sunX` is the
// sun's centre as a fraction of the width.
Item {
  id: sky

  property real horizon: 0.40
  property real lateral: 0
  property real sunX: 0.68
  // Radius of the sun disc, as a fraction of the item's height.
  property real sunRadius: 0.18
  // How much of the disc sits above the horizon line: 0.5 is a disc bisected
  // by it, 1.0 a disc resting on it. The bar has it low and cut by the hills.
  property real sunLift: 0.62

  // Sampled off the bar (DIRECTION.md), sRGB.
  readonly property color skyTop: "#5e1a50"
  readonly property color skyHigh: "#a4337b"
  readonly property color skyMid: "#c24073"
  readonly property color skyLow: "#d75d6b"
  readonly property color sunCore: "#efcb72"
  readonly property color sunEdge: "#f0956e"
  readonly property color hillFar: "#bc405f"
  readonly property color hillMid: "#8e2c50"
  readonly property color hillNear: "#5e1a50"

  readonly property real horizonY: Math.round(horizon * height)
  // How tall the sky canvas is: enough to reach the top of the item at the
  // lowest horizon the track ever draws, and the gradient is fitted to that.
  readonly property int skyH: Math.ceil(height * 0.56)

  clip: true

  // ------------------------------------------------------------- the sky
  // Gradient, glow, sun, cut lines and clouds, painted once. It is anchored to
  // the horizon so a pull-back or a crest moves the whole sky as a camera
  // pitch would, and nothing has to be repainted for it.
  Canvas {
    id: dome
    width: sky.width
    height: sky.skyH
    y: sky.horizonY - height
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
    antialiasing: false

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      ctx.reset()
      ctx.clearRect(0, 0, w, h)

      // The gradient. Magenta at the top edge, hot pink through the middle,
      // pink-orange sitting on the horizon.
      var g = ctx.createLinearGradient(0, 0, 0, h)
      g.addColorStop(0.00, sky.skyTop)
      g.addColorStop(0.32, sky.skyHigh)
      g.addColorStop(0.66, sky.skyMid)
      g.addColorStop(1.00, sky.skyLow)
      ctx.fillStyle = g
      ctx.fillRect(0, 0, w, h)

      var r = sky.sunRadius * sky.height
      var cx = Math.round(sky.sunX * w)
      var cy = Math.round(h - r * (sky.sunLift * 2 - 1))

      // The wide glow, in two rings: a broad pink-orange halo and a tighter,
      // warmer one. Radial gradients, so the halo is soft at every scale.
      var halo = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 3.2)
      halo.addColorStop(0.00, rgba(sky.sunEdge, 0.55))
      halo.addColorStop(0.35, rgba(sky.sunEdge, 0.28))
      halo.addColorStop(1.00, rgba(sky.sunEdge, 0.0))
      ctx.fillStyle = halo
      ctx.fillRect(0, 0, w, h)
      var inner = ctx.createRadialGradient(cx, cy, r * 0.9, cx, cy, r * 1.6)
      inner.addColorStop(0.0, rgba(sky.sunCore, 0.40))
      inner.addColorStop(1.0, rgba(sky.sunCore, 0.0))
      ctx.fillStyle = inner
      ctx.fillRect(0, 0, w, h)

      // Cloud bands: streaky horizontal shapes, each a run of long thin
      // lozenges with feathered ends. Two above the sun in a shade darker
      // than the sky behind them, one low band lit pink-cream from below.
      function streak(x, y, len, thick, col, alpha) {
        var s = ctx.createLinearGradient(x, 0, x + len, 0)
        s.addColorStop(0.0, rgba(col, 0))
        s.addColorStop(0.18, rgba(col, alpha))
        s.addColorStop(0.82, rgba(col, alpha))
        s.addColorStop(1.0, rgba(col, 0))
        ctx.fillStyle = s
        ctx.fillRect(x, y, len, thick)
      }
      var dark = Qt.rgba(0.44, 0.10, 0.34, 1)
      var lit = Qt.rgba(0.96, 0.62, 0.55, 1)
      var bright = Qt.rgba(0.99, 0.80, 0.62, 1)
      // band one, high and dark
      streak(w * 0.02, h * 0.20, w * 0.46, Math.max(2, h * 0.030), dark, 0.62)
      streak(w * 0.30, h * 0.24, w * 0.52, Math.max(1, h * 0.018), dark, 0.52)
      streak(w * 0.58, h * 0.16, w * 0.40, Math.max(1, h * 0.022), dark, 0.46)
      // band two, mid, lit on the underside
      streak(w * 0.10, h * 0.42, w * 0.40, Math.max(2, h * 0.034), dark, 0.50)
      streak(w * 0.12, h * 0.42 + Math.max(2, h * 0.034), w * 0.36, Math.max(1, h * 0.012), lit, 0.80)
      streak(w * 0.52, h * 0.47, w * 0.46, Math.max(2, h * 0.028), dark, 0.46)
      streak(w * 0.55, h * 0.47 + Math.max(2, h * 0.028), w * 0.40, Math.max(1, h * 0.012), lit, 0.85)
      // band three, low across the sun, thin and bright
      streak(w * 0.36, h * 0.70, w * 0.62, Math.max(1, h * 0.016), bright, 0.75)
      streak(w * 0.00, h * 0.76, w * 0.42, Math.max(1, h * 0.014), lit, 0.60)

      // The sun. A disc with a warm edge, then the genre's cut lines through
      // its lower half, in the sky colour at that height, thickening downward.
      var disc = ctx.createRadialGradient(cx, cy, r * 0.55, cx, cy, r)
      disc.addColorStop(0.0, sky.sunCore)
      disc.addColorStop(1.0, sky.sunEdge)
      ctx.fillStyle = disc
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.fill()

      var cuts = [[0.06, 1], [0.20, 1], [0.34, 2], [0.48, 2], [0.62, 3], [0.76, 3], [0.90, 4]]
      for (var i = 0; i < cuts.length; i++) {
        var yy = Math.round(cy + r * cuts[i][0])
        var t = Math.max(1, Math.round(cuts[i][1] * sky.height / 270))
        // the sky colour at this row, so the cut reads as sky through the disc
        var f = Math.max(0, Math.min(1, yy / h))
        ctx.fillStyle = f < 0.66 ? sky.skyMid : sky.skyLow
        ctx.fillRect(cx - r - 1, yy, r * 2 + 2, t)
      }
    }
    Component.onCompleted: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  // ----------------------------------------------------------- the hills
  // Three silhouettes, far to near, lighter with distance. Each is twice the
  // width of the sky and slides by a fraction of the road's lateral offset:
  // the far ridge barely, the near one by half. Drawn once.
  Repeater {
    model: 3

    Canvas {
      readonly property real par: [0.15, 0.30, 0.50][index]
      readonly property real tall: [0.105, 0.070, 0.044][index] * sky.height
      readonly property color tone: [sky.hillFar, sky.hillMid, sky.hillNear][index]
      readonly property var bumps: [
        [[0.05, 0.9, 0.16], [0.30, 0.55, 0.09], [0.52, 1.0, 0.14], [0.78, 0.7, 0.10], [1.05, 0.95, 0.15], [1.35, 0.6, 0.08], [1.62, 0.85, 0.12], [1.90, 0.75, 0.11]],
        [[0.12, 0.8, 0.10], [0.40, 1.0, 0.13], [0.66, 0.6, 0.07], [0.92, 0.9, 0.12], [1.20, 0.7, 0.09], [1.48, 1.0, 0.14], [1.78, 0.65, 0.08]],
        [[0.08, 0.7, 0.06], [0.26, 1.0, 0.09], [0.47, 0.55, 0.05], [0.70, 0.85, 0.08], [0.98, 0.6, 0.06], [1.24, 1.0, 0.10], [1.55, 0.7, 0.07], [1.82, 0.9, 0.08]]
      ][index]

      width: sky.width * 2
      height: Math.ceil(tall) + 2
      y: sky.horizonY - height + 1
      x: Math.round(-sky.width / 2 + sky.lateral * par)
      z: 1 + index
      renderStrategy: Canvas.Immediate
      renderTarget: Canvas.Image
      smooth: false
      antialiasing: false

      onPaint: {
        var ctx = getContext("2d")
        var w = width
        var h = height
        ctx.reset()
        ctx.clearRect(0, 0, w, h)
        ctx.fillStyle = tone
        ctx.beginPath()
        ctx.moveTo(0, h)
        // A ridge line: the max of a few bell-shaped bumps, sampled every two
        // pixels and stepped, so the silhouette is a hill and not a wave.
        var step = 2
        for (var px = 0; px <= w; px += step) {
          var u = px / sky.width
          var ridge = 0.18
          for (var b = 0; b < bumps.length; b++) {
            var d = (u - bumps[b][0]) / bumps[b][2]
            ridge = Math.max(ridge, bumps[b][1] * Math.max(0, 1 - d * d * 0.5) * Math.exp(-d * d * 0.35))
          }
          ctx.lineTo(px, h - Math.round(ridge * tall))
        }
        ctx.lineTo(w, h)
        ctx.closePath()
        ctx.fill()
      }
      Component.onCompleted: requestPaint()
      onWidthChanged: requestPaint()
    }
  }
}
