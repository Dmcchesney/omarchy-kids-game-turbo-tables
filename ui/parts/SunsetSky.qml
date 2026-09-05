import QtQuick

// The sky at golden hour: what the track, the garage door and the countdown
// all look out onto.
//
// PIECE T OWNS THIS FILE, AND SAYING SO IS THE POINT.
//
// It arrived with the "Golden Hour at the Pit" prototype and stayed a
// prototype: three separate pieces named it the largest single gap in the
// picture and each declined to take it, because it is shared by the race view,
// the garage's open roller door and the countdown, and a change here changes
// three screens at once. It is taken now. What is new:
//
//   * THE HOUR PASSES. `nightfall` runs 0 at lap 1 to 1 at lap 12 and every
//     colour in this file is a lerp between a golden-hour stop and a dusk one.
//     The sun sinks with it -- `sunLift` 0.80 to 0.50, which is the design's
//     "sits on the horizon at lap 1 and is half set by lap 12" -- and the glow
//     dims with the disc rather than staying at full strength over a set sun.
//   * THE CLOUDS ARE TWO PARALLAX LAYERS THAT DRIFT. They used to be painted
//     into the fixed dome canvas, so the sky was a still photograph on every
//     screen. They are their own two canvases now, each painted once with a
//     pattern whose period is exactly the sky's width, so `drift` scrolls them
//     seamlessly and the far layer moves at a third of the near one's rate.
//   * THE FIRST STARS. `stars` fades in a fixed field of single-plane-pixel
//     squares above the horizon, which at the track's four-times upscale are
//     four-pixel blocks like everything else. They are static: the design's
//     accessibility rule is that nothing flashes faster than 3 Hz, and a
//     twinkle is the easiest way to break it by accident.
//
// Everything here is still a gradient, a disc, a block or a silhouette --
// nothing is painted from a texture -- so it holds up drawn into a 480 x 270
// plane and scaled to 1080p with a nearest-neighbour filter.
//
// WHAT IT COSTS. Six textured quads a frame plus the stars. The dome is one
// canvas repainted only when the LAP changes; each cloud layer and each hill
// layer is its own canvas painted once and translated. Nothing repaints while
// the road runs.
//
// HOW TO USE IT. Fill the plane with it, put it BELOW the road, and bind
// `horizon` (0..1 down the item) and `lateral` (the road's far-centre offset
// in this item's pixels: positive when the road bends right). `sunX` is the
// sun's centre as a fraction of the width; `nightfall`, `drift` and `stars`
// are the three things that move.
Item {
  id: sky

  property real horizon: 0.40
  property real lateral: 0
  property real sunX: 0.68
  // 0 at lap 1, 1 at lap 12. Every colour below is a lerp on it.
  property real nightfall: 0
  // How far the clouds have drifted, in this item's pixels. Monotonic; the
  // layers wrap on their own.
  property real drift: 0
  // 0..1, the first stars. The track raises it from lap 11.
  property real stars: 0
  // THE HEIGHT EVERY PROPORTION IN THIS SKY IS MEASURED AGAINST.
  //
  // Normally the item's own height, and every caller but one leaves it there.
  // `ui/TrackView.qml` draws this into an OVERSCANNED plane -- taller than the
  // frame, so a camera shake has somewhere to move without uncovering the void
  // behind the scene -- and passes 270, the frame's own height. Without it the
  // sun, the cloud bands and the three hill silhouettes would all grow with the
  // margin, which is a change to the picture and not to the camera.
  property real unitH: height
  // Radius of the sun disc, as a fraction of the item's height.
  property real sunRadius: 0.18
  // How much of the disc sits above the horizon line: 0.5 is a disc bisected
  // by it, 1.0 a disc resting on it. Design v4, Time passes: on the horizon at
  // lap 1, half set by lap 12.
  property real sunLift: 0.80 - 0.30 * sky.nightfall

  // Sampled off the bar (DIRECTION.md), sRGB, at golden hour; and the dusk
  // stop each one travels to over twelve laps. `duskLow` is deliberately the
  // same number as `TrackView.fogDusk`, because the floor's haze and the sky's
  // horizon have to meet in one tone at every lap, not only at the first.
  readonly property color dayTop: "#5e1a50"
  readonly property color dayHigh: "#a4337b"
  readonly property color dayMid: "#c24073"
  readonly property color dayLow: "#d75d6b"
  readonly property color duskTop: "#241038"
  readonly property color duskHigh: "#4c1a56"
  readonly property color duskMid: "#7a2360"
  readonly property color duskLow: "#6b2a55"

  function lerpTone(a, b) {
    var t = Math.max(0, Math.min(1, sky.nightfall))
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t, 1)
  }

  readonly property color dayCore: "#efcb72"
  readonly property color dayEdge: "#f0956e"
  readonly property color dayHillFar: "#bc405f"
  readonly property color dayHillMid: "#8e2c50"
  readonly property color dayHillNear: "#5e1a50"
  readonly property color duskCore: "#e8a75c"
  readonly property color duskEdge: "#d9705f"
  readonly property color duskHillFar: "#7a2a4e"
  readonly property color duskHillMid: "#55203f"
  readonly property color duskHillNear: "#2e1030"

  readonly property color skyTop: lerpTone(dayTop, duskTop)
  readonly property color skyHigh: lerpTone(dayHigh, duskHigh)
  readonly property color skyMid: lerpTone(dayMid, duskMid)
  readonly property color skyLow: lerpTone(dayLow, duskLow)
  readonly property color sunCore: lerpTone(dayCore, duskCore)
  readonly property color sunEdge: lerpTone(dayEdge, duskEdge)
  readonly property color hillFar: lerpTone(dayHillFar, duskHillFar)
  readonly property color hillMid: lerpTone(dayHillMid, duskHillMid)
  readonly property color hillNear: lerpTone(dayHillNear, duskHillNear)

  readonly property real horizonY: Math.round(horizon * height)
  // How tall the sky canvas is: enough to reach the top of the item at the
  // lowest horizon the track ever draws, and the gradient is fitted to that.
  readonly property int skyH: Math.ceil(sky.unitH * 0.56)

  clip: true

  // ------------------------------------------------------------- the sky
  // Gradient, glow, sun and cut lines, painted once per lap. Anchored to the
  // horizon so a pull-back or a crest moves the whole sky as a camera pitch
  // would, and nothing has to be repainted for it.
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
      // pink-orange sitting on the horizon -- all three deepening toward plum
      // as the hour passes.
      var g = ctx.createLinearGradient(0, 0, 0, h)
      g.addColorStop(0.00, sky.skyTop)
      g.addColorStop(0.32, sky.skyHigh)
      g.addColorStop(0.66, sky.skyMid)
      g.addColorStop(1.00, sky.skyLow)
      ctx.fillStyle = g
      ctx.fillRect(0, 0, w, h)

      var r = sky.sunRadius * sky.unitH
      var cx = Math.round(sky.sunX * w)
      var cy = Math.round(h - r * (sky.sunLift * 2 - 1))

      // The wide glow, in two rings: a broad pink-orange halo and a tighter,
      // warmer one. Radial gradients, so the halo is soft at every scale, and
      // both fade with the disc.
      var lit = 1 - 0.45 * sky.nightfall
      var halo = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 3.2)
      halo.addColorStop(0.00, rgba(sky.sunEdge, 0.55 * lit))
      halo.addColorStop(0.35, rgba(sky.sunEdge, 0.28 * lit))
      halo.addColorStop(1.00, rgba(sky.sunEdge, 0.0))
      ctx.fillStyle = halo
      ctx.fillRect(0, 0, w, h)
      var inner = ctx.createRadialGradient(cx, cy, r * 0.9, cx, cy, r * 1.6)
      inner.addColorStop(0.0, rgba(sky.sunCore, 0.40 * lit))
      inner.addColorStop(1.0, rgba(sky.sunCore, 0.0))
      ctx.fillStyle = inner
      ctx.fillRect(0, 0, w, h)

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
        var t = Math.max(1, Math.round(cuts[i][1] * sky.unitH / 270))
        // the sky colour at this row, so the cut reads as sky through the disc
        var f = Math.max(0, Math.min(1, yy / h))
        ctx.fillStyle = f < 0.66 ? sky.skyMid : sky.skyLow
        ctx.fillRect(cx - r - 1, yy, r * 2 + 2, t)
      }
    }
    Component.onCompleted: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    // One repaint per lap, not one per frame: `nightfall` only ever moves when
    // the lap counter does.
    Connections {
      target: sky
      function onNightfallChanged() { dome.requestPaint() }
    }
  }

  // ----------------------------------------------------------- the stars
  // Design v4: "the first stars appear by lap 11." A fixed field of single
  // plane-pixel squares in the upper half of the sky, brighter the higher they
  // are, none of them within a disc's width of the sun. Static: nothing in
  // this game may flash faster than 3 Hz and a twinkle is the easiest way to
  // break that by accident.
  Item {
    id: starField
    anchors.fill: parent
    visible: sky.stars > 0.01
    opacity: sky.stars
    z: 0.5

    Repeater {
      model: 46

      Rectangle {
        // A cheap deterministic scatter: two coprime multipliers taken mod 1.
        readonly property real fx: ((index * 0.6180339887) % 1)
        readonly property real fy: ((index * 0.2360679775 + 0.11) % 1)
        readonly property real up: 0.10 + fy * 0.62
        width: 1
        height: 1
        antialiasing: false
        x: Math.round(fx * sky.width)
        y: Math.round(sky.horizonY - sky.skyH * up)
        color: (index % 5 === 0) ? "#fff3d6" : "#e8d2f0"
        opacity: 0.45 + 0.55 * up
        // Never inside the sun's halo, where a star would read as a speck of
        // dirt on the disc.
        visible: Math.abs(fx - sky.sunX) > 0.12 || up > 0.42
      }
    }
  }

  // ---------------------------------------------------------- the clouds
  // Two parallax layers of streaks, drifting. Each canvas is twice the sky's
  // width and its pattern repeats with period exactly `sky.width`, so sliding
  // it by `drift mod width` is seamless and nothing pops at the wrap.
  Repeater {
    model: 2

    Canvas {
      id: cloudLayer
      readonly property real par: [0.35, 1.0][index]
      readonly property real depth: index
      readonly property real slab: Math.max(1, sky.unitH * [0.026, 0.034][index])
      width: sky.width * 2
      height: sky.skyH
      y: sky.horizonY - height
      x: {
        var span = Math.max(1, sky.width)
        var d = (sky.drift * par) % span
        return -(d < 0 ? d + span : d)
      }
      z: 0.6 + index * 0.1
      renderStrategy: Canvas.Immediate
      renderTarget: Canvas.Image
      smooth: false
      antialiasing: false

      // Each streak is [phase across the period, height up the canvas, length,
      // lit]. The high layer is dark against the sky; the low one is lit on
      // its underside by the sun beneath it.
      readonly property var streaks: [
        [[0.02, 0.20, 0.46, 0], [0.30, 0.24, 0.52, 0], [0.58, 0.16, 0.40, 0], [0.74, 0.30, 0.30, 0]],
        [[0.10, 0.44, 0.40, 1], [0.52, 0.49, 0.46, 1], [0.36, 0.70, 0.44, 1], [0.00, 0.77, 0.34, 1]]
      ][index]

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        var period = sky.width
        var dark = Qt.rgba(0.44, 0.10, 0.34, 1)
        var glow = Qt.rgba(0.96, 0.62, 0.55, 1)
        var bright = Qt.rgba(0.99, 0.80, 0.62, 1)
        var fade = 1 - 0.45 * sky.nightfall

        function streak(x, y, len, thick, col, alpha) {
          var s = ctx.createLinearGradient(x, 0, x + len, 0)
          s.addColorStop(0.0, Qt.rgba(col.r, col.g, col.b, 0))
          s.addColorStop(0.18, Qt.rgba(col.r, col.g, col.b, alpha))
          s.addColorStop(0.82, Qt.rgba(col.r, col.g, col.b, alpha))
          s.addColorStop(1.0, Qt.rgba(col.r, col.g, col.b, 0))
          ctx.fillStyle = s
          ctx.fillRect(x, y, len, thick)
        }

        // Painted twice, one period apart, so the wrap has no seam.
        for (var rep = 0; rep < 2; rep++) {
          var base = rep * period
          for (var i = 0; i < streaks.length; i++) {
            var st = streaks[i]
            var x = base + st[0] * period
            var y = Math.round(st[1] * height)
            var len = st[2] * period
            streak(x, y, len, slab, dark, 0.56 - depth * 0.08)
            if (st[3] === 1)
              streak(x + len * 0.05, y + slab, len * 0.88,
                     Math.max(1, slab * 0.35), rep === 0 ? bright : glow, 0.80 * fade)
          }
        }
      }
      Component.onCompleted: requestPaint()
      onWidthChanged: requestPaint()
      Connections {
        target: sky
        function onNightfallChanged() { cloudLayer.requestPaint() }
      }
    }
  }

  // ----------------------------------------------------------- the hills
  // Three silhouettes, far to near, lighter with distance. Each is twice the
  // width of the sky and slides by a fraction of the road's lateral offset:
  // the far ridge barely, the near one by half. Drawn once, repainted only
  // when the hour changes their tone.
  Repeater {
    model: 3

    Canvas {
      readonly property real par: [0.15, 0.30, 0.50][index]
      readonly property real tall: [0.105, 0.070, 0.044][index] * sky.unitH
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
      onToneChanged: requestPaint()
    }
  }
}
