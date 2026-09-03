import QtQuick
import "../"

// One thing standing on the track: a kart seen from behind, or a piece of
// garage furniture at the roadside.
//
// WHY THIS IS A SPRITE AND NOT A LIVE RENDERER
//
// GarageStall's KartSprite models a kart in three dimensions and re-renders it
// whenever its size changes. That is right for a stall, where one kart is
// large and still. It is wrong for a track, where four karts and twelve props
// change size on every one of sixty frames a second: the canvas would repaint
// sixteen times a frame and the frame budget would be gone before the road was
// drawn.
//
// So this draws once, into a canvas of a fixed size, and the track view scales
// it with `scale` and moves it with `x` and `y`. Neither of those touches the
// canvas, so a kart that crosses the whole screen and grows from a speck to
// half its height costs one textured blit per frame and no drawing at all.
// That is exactly what the design means by "pre-rendered sprite sheets"; the
// sheet here happens to be drawn in code so the paint can be any of the eight
// swatches, which a bitmap sheet cannot follow without eight copies.
//
// `smooth: false` keeps the enlargement nearest-neighbour, which is the pixel
// look the garage wants and is also the cheapest filter there is.
//
// THE ANCHOR is the bottom centre of the sheet, and every kind is drawn
// standing on that point, so the track view positions a sprite by where it
// touches the ground and never has to know how tall it is.
//
// Placeholder art. The design's shipping karts are eight angles and three
// scales; this is the one angle the track needs, drawn to match the garage's
// palette, its one-light shading and its contact shadow.
Item {
  id: sprite

  // "kart", or one of the six roadside kinds below.
  property string kind: "kart"
  property color paintColor: Theme.paint(0)
  property int number: 7
  property int body: 0
  // A ghost is the same kart in the design's dark teal, and translucent.
  property bool ghost: false
  property bool showNumber: true
  // Dims a sprite that is far away, so distance reads as light as well as size.
  property real dim: 1.0

  readonly property bool isKart: kind === "kart"

  // The sheet. Karts are wide, roadside furniture is tall.
  readonly property int sheetW: isKart ? 192 : (kind === "rollerDoor" ? 320 : 128)
  readonly property int sheetH: isKart ? 128 : (kind === "rollerDoor" ? 200 : 176)

  width: sheetW
  height: sheetH
  transformOrigin: Item.Bottom
  smooth: false
  antialiasing: false

  // ------------------------------------------------------------ the camera
  // Model axes: +x to the right, +y up, +z from the tail toward the nose and
  // away from the camera. The camera sits behind and above the kart and is
  // yawed a few degrees off its centre line, so the visible faces are the
  // tail, the top, and a sliver of the right flank. That is the view a driver
  // has of the kart in front, which is the whole point of the screen.
  readonly property real yawDeg: 7
  readonly property real pitchDeg: 15
  readonly property real focal: 210

  readonly property real cy: Math.cos(yawDeg * Math.PI / 180)
  readonly property real sy: Math.sin(yawDeg * Math.PI / 180)
  readonly property real cp: Math.cos(pitchDeg * Math.PI / 180)
  readonly property real sp: Math.sin(pitchDeg * Math.PI / 180)

  // Model box the camera is aimed at, and where its floor lands on the sheet.
  readonly property real refX: 0
  readonly property real refY: 9
  readonly property real refZ: 20
  readonly property real unit: sheetW / 62
  readonly property real centreU: sheetW / 2
  readonly property real centreV: sheetH - 12 - refY * cp * unit

  function depthAt(x, z) {
    return (z - refZ) * cy - (x - refX) * sy
  }

  function project(x, y, z) {
    var d = depthAt(x, z)
    var p = focal / (focal + d)
    var u = ((x - refX) * cy + (z - refZ) * sy) * p
    var v = ((y - refY) * cp - d * sp) * p
    return [centreU + u * unit, centreV - v * unit]
  }

  // ---------------------------------------------------------------- bodies
  // Six silhouettes as six blocks of numbers rather than six routines: the
  // wheelbase, how high the tail sits, whether there is a wing, and how the
  // nose tapers. Every kart shares the same skeleton, which is what makes a
  // field of four read as four karts of one class.
  readonly property var bodySpecs: [
    // sprinter
    { halfW: 13, tail: 13.5, nose: 8.5, wing: 1, wingH: 17.5, pod: 1, cockpit: 1, noseZ: 46 },
    // wedge
    { halfW: 12, tail: 12.0, nose: 7.0, wing: 1, wingH: 16.0, pod: 1, cockpit: 1, noseZ: 48 },
    // stockcar
    { halfW: 14.5, tail: 15.5, nose: 12.0, wing: 0, wingH: 0, pod: 0, cockpit: 1, noseZ: 44 },
    // buggy
    { halfW: 13.5, tail: 12.5, nose: 9.0, wing: 0, wingH: 0, pod: 0, cockpit: 1, noseZ: 42 },
    // hauler
    { halfW: 15.0, tail: 17.0, nose: 13.0, wing: 0, wingH: 0, pod: 1, cockpit: 0, noseZ: 47 },
    // prototype
    { halfW: 13.0, tail: 14.0, nose: 7.5, wing: 1, wingH: 18.5, pod: 1, cockpit: 1, noseZ: 49 }
  ]

  readonly property var spec: bodySpecs[((body % 6) + 6) % 6]

  readonly property color skin: ghost ? Theme.teal : paintColor

  Canvas {
    id: surface
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
    antialiasing: false

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      if (sprite.isKart)
        paintKart(ctx)
      else
        paintProp(ctx)
    }

    // ------------------------------------------------------- shared light
    // The same light vector the garage stall uses, so a kart on the track and
    // the same kart on the turntable are lit by the same lamp.
    // Pointing down the track from behind the camera, so the face a driver
    // actually sees -- the tail -- is the lit one. Round one lit the roof and
    // left every tail two thirds dark, and four karts of eight different
    // paints all came out the same olive.
    readonly property real lx: 0.37
    readonly property real ly: 0.66
    readonly property real lz: -0.66
    readonly property color warm: Qt.rgba(1.0, 0.84, 0.58, 1)
    readonly property color cool: Qt.rgba(0.07, 0.20, 0.24, 1)

    function mix(a, b, t) {
      return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                     a.b + (b.b - a.b) * t, 1)
    }
    function gain(c, k) {
      var d = sprite.dim
      return Qt.rgba(Math.min(1, c.r * k * d), Math.min(1, c.g * k * d),
                     Math.min(1, c.b * k * d), 1)
    }
    function shade(base, n) {
      var lam = Math.max(0, n[0] * lx + n[1] * ly + n[2] * lz)
      var sky = Math.max(0, n[1]) * 0.20
      var c = gain(base, 0.38 + 0.66 * lam + sky)
      c = mix(c, warm, 0.16 * lam)
      c = mix(c, cool, 0.34 * (1 - lam))
      return c
    }

    // ------------------------------------------------------- the kart
    function paintKart(ctx) {
      var g = sprite.spec
      var queue = []

      function normalOf(p) {
        var ax = p[1][0] - p[0][0], ay = p[1][1] - p[0][1], az = p[1][2] - p[0][2]
        var bx = p[2][0] - p[0][0], by = p[2][1] - p[0][1], bz = p[2][2] - p[0][2]
        var nx = ay * bz - az * by
        var ny = az * bx - ax * bz
        var nz = ax * by - ay * bx
        var len = Math.sqrt(nx * nx + ny * ny + nz * nz)
        return len <= 0 ? null : [nx / len, ny / len, nz / len]
      }

      // The camera's forward direction in model space. A face whose outward
      // normal agrees with it points away and is dropped before it is ever
      // projected, so the queue only ever holds faces that can be seen.
      var Wx = sprite.sy * sprite.cp
      var Wy = sprite.sp
      var Wz = sprite.cy * sprite.cp

      function face(pts3, base, bias) {
        var n = normalOf(pts3)
        if (!n)
          return
        if (n[0] * Wx + n[1] * Wy + n[2] * Wz > -0.0001)
          return
        var flat = []
        var d = 0
        for (var i = 0; i < pts3.length; i++) {
          flat.push(sprite.project(pts3[i][0], pts3[i][1], pts3[i][2]))
          d += sprite.depthAt(pts3[i][0], pts3[i][2])
        }
        queue.push({ pts: flat, fill: shade(base, n), depth: d / pts3.length + (bias || 0) })
      }

      // A box, as its six faces, wound so every outward normal points out.
      function box(x0, x1, y0, y1, z0, z1, base, bias) {
        face([[x0,y1,z0],[x1,y1,z0],[x1,y1,z1],[x0,y1,z1]], base, bias)   // top
        face([[x0,y0,z1],[x1,y0,z1],[x1,y0,z0],[x0,y0,z0]], base, bias)   // bottom
        face([[x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0]], base, bias)   // tail
        face([[x1,y0,z1],[x0,y0,z1],[x0,y1,z1],[x1,y1,z1]], base, bias)   // nose
        face([[x1,y0,z0],[x1,y0,z1],[x1,y1,z1],[x1,y1,z0]], base, bias)   // right
        face([[x0,y0,z1],[x0,y0,z0],[x0,y1,z0],[x0,y1,z1]], base, bias)   // left
      }

      var paint = sprite.skin
      var tyre = Qt.rgba(0.10, 0.11, 0.13, 1)
      var dark = Qt.rgba(0.14, 0.16, 0.19, 1)
      var glass = Theme.tealDeep

      var hw = g.halfW
      var noseZ = g.noseZ

      // contact shadow, on the ground, before anything else
      var sh = []
      var corners = [[-hw - 3, 0, -1], [hw + 3, 0, -1], [hw + 3, 0, noseZ + 1], [-hw - 3, 0, noseZ + 1]]
      for (var c = 0; c < corners.length; c++)
        sh.push(sprite.project(corners[c][0], -0.4, corners[c][2]))
      ctx.beginPath()
      ctx.moveTo(sh[0][0], sh[0][1])
      for (var si = 1; si < sh.length; si++)
        ctx.lineTo(sh[si][0], sh[si][1])
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(0, 0, 0, 0.38)
      ctx.fill()

      // wheels
      box(-hw - 5, -hw + 0.5, 0.5, 11.5, 4, 17, tyre, 0)
      box(hw - 0.5, hw + 5, 0.5, 11.5, 4, 17, tyre, 0)
      box(-hw - 4, -hw + 0.5, 1.0, 10.0, noseZ - 15, noseZ - 4, tyre, 0)
      box(hw - 0.5, hw + 4, 1.0, 10.0, noseZ - 15, noseZ - 4, tyre, 0)

      // floor pan
      box(-hw + 1, hw - 1, 1.6, 4.4, 2, noseZ - 2, dark, 0)

      // side pods
      if (g.pod === 1) {
        box(-hw + 0.5, -hw + 6, 3.6, 10.5, 13, noseZ - 14, paint, 0)
        box(hw - 6, hw - 0.5, 3.6, 10.5, 13, noseZ - 14, paint, 0)
      }

      // engine cowl and the tail the number sits on
      box(-hw + 2, hw - 2, 3.6, g.tail, 3, 18, paint, 0)
      // spine forward to the cockpit
      box(-hw + 4, hw - 4, 3.6, g.tail - 3.0, 18, noseZ - 12, paint, 0)

      // cockpit and helmet
      if (g.cockpit === 1) {
        box(-5.5, 5.5, g.tail - 3.0, g.tail + 1.5, 19, 27, glass, 0)
        box(-3.6, 3.6, g.tail + 1.5, g.tail + 5.5, 20.5, 25.5, Theme.cream, 0)
      }

      // nose
      box(-g.nose, g.nose, 3.6, 8.6, noseZ - 12, noseZ, paint, 0)

      // wing, on two posts
      if (g.wing === 1) {
        box(-3.0, -1.4, g.tail, g.wingH, 2.5, 6.5, dark, 0)
        box(1.4, 3.0, g.tail, g.wingH, 2.5, 6.5, dark, 0)
        box(-hw - 1.5, hw + 1.5, g.wingH, g.wingH + 2.2, 1.0, 7.5, paint, 0)
      }

      // tail lamps, two warm squares that read at any size
      box(-hw + 4.0, -hw + 7.0, 6.0, 8.5, 2.6, 3.2, Theme.amber, 0.6)
      box(hw - 7.0, hw - 4.0, 6.0, 8.5, 2.6, 3.2, Theme.amber, 0.6)

      queue.sort(function (a, b) { return b.depth - a.depth })
      for (var q = 0; q < queue.length; q++) {
        var f = queue[q]
        ctx.beginPath()
        ctx.moveTo(f.pts[0][0], f.pts[0][1])
        for (var p = 1; p < f.pts.length; p++)
          ctx.lineTo(f.pts[p][0], f.pts[p][1])
        ctx.closePath()
        ctx.fillStyle = f.fill
        ctx.fill()
      }

      // The number, on a white plate across the tail. Drawn after the faces
      // because it is a decal on one of them, not a solid of its own.
      if (sprite.showNumber && !sprite.ghost) {
        var a = sprite.project(-hw + 2.4, 6.2, 2.9)
        var b = sprite.project(hw - 2.4, 6.2, 2.9)
        var t = sprite.project(-hw + 2.4, g.tail - 1.2, 2.9)
        var pw = b[0] - a[0]
        var ph = a[1] - t[1]
        if (pw > 6 && ph > 5) {
          ctx.fillStyle = Qt.rgba(0.93, 0.93, 0.90, 1)
          ctx.fillRect(a[0] + pw * 0.26, t[1] + ph * 0.10, pw * 0.48, ph * 0.80)
          ctx.fillStyle = Qt.rgba(0.06, 0.06, 0.07, 1)
          ctx.font = "bold " + Math.max(7, Math.round(ph * 0.72)) + "px sans-serif"
          ctx.textAlign = "center"
          ctx.textBaseline = "middle"
          ctx.fillText(String(sprite.number), a[0] + pw * 0.50, t[1] + ph * 0.50)
        }
      }
    }

    // ------------------------------------------------- roadside furniture
    // Billboards: the camera looks at these nearly face on, so they are drawn
    // flat, with the same warm-over-cool palette as everything else.
    function paintProp(ctx) {
      var w = width
      var h = height
      var d = sprite.dim
      function tint(c, k) {
        return Qt.rgba(Math.min(1, c.r * k * d), Math.min(1, c.g * k * d),
                       Math.min(1, c.b * k * d), 1)
      }
      var steel = Qt.rgba(0.30, 0.33, 0.37, 1)
      var steelDark = Qt.rgba(0.16, 0.18, 0.21, 1)
      var rubber = Qt.rgba(0.09, 0.10, 0.12, 1)

      // a contact shadow under everything except the arch, which the road
      // runs through rather than past
      if (sprite.kind !== "rollerDoor") {
        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.34)
        ctx.beginPath()
        ctx.ellipse(w * 0.16, h - 14, w * 0.68, 13)
        ctx.fill()
      }

      if (sprite.kind === "tireWall") {
        var rows = 4
        var cols = 3
        var tw = w / cols
        var th = (h - 24) / rows
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            var offset = (r % 2) * tw * 0.5
            var x = c * tw + offset - tw * 0.25
            var y = h - 18 - (r + 1) * th
            ctx.fillStyle = tint(rubber, 1 + r * 0.10)
            ctx.fillRect(x, y, tw * 0.92, th * 0.92)
            ctx.fillStyle = tint(steelDark, 1.6)
            ctx.fillRect(x + tw * 0.30, y + th * 0.28, tw * 0.32, th * 0.36)
          }
          ctx.fillStyle = tint(r % 2 === 0 ? Theme.amber : Theme.cream, 0.9)
          ctx.fillRect(0, h - 18 - (r + 1) * th - 3, w, 3)
        }
        return
      }

      if (sprite.kind === "drum") {
        var dw = w * 0.56
        var dx = (w - dw) / 2
        var dh = h * 0.62
        var dy = h - 16 - dh
        ctx.fillStyle = tint(Theme.amberDeep, 1.0)
        ctx.fillRect(dx, dy, dw, dh)
        ctx.fillStyle = tint(Theme.amber, 1.0)
        ctx.fillRect(dx, dy, dw * 0.30, dh)
        ctx.fillStyle = tint(steelDark, 1.0)
        ctx.fillRect(dx, dy + dh * 0.20, dw, dh * 0.08)
        ctx.fillRect(dx, dy + dh * 0.68, dw, dh * 0.08)
        ctx.fillStyle = tint(Theme.amberGlow, 1.0)
        ctx.fillRect(dx, dy, dw, dh * 0.06)
        return
      }

      if (sprite.kind === "cone") {
        var bx = w * 0.5
        var by = h - 16
        var ch = h * 0.52
        ctx.fillStyle = tint(Theme.amber, 1.0)
        ctx.beginPath()
        ctx.moveTo(bx, by - ch)
        ctx.lineTo(bx + w * 0.24, by)
        ctx.lineTo(bx - w * 0.24, by)
        ctx.closePath()
        ctx.fill()
        ctx.fillStyle = tint(Theme.cream, 1.0)
        ctx.fillRect(bx - w * 0.155, by - ch * 0.52, w * 0.31, ch * 0.16)
        ctx.fillStyle = tint(steelDark, 1.0)
        ctx.fillRect(bx - w * 0.30, by - 6, w * 0.60, 6)
        return
      }

      if (sprite.kind === "workLight") {
        // A tall stand with a small hooded head and a cone of amber under it.
        // The head is small on purpose: a wide shade at this scale reads as a
        // table lamp, and the garage's lights hang off poles. The cone fades
        // out downward, because a flat-filled polygon at any alpha reads as a
        // solid object rather than as light.
        var px = w * 0.5
        ctx.fillStyle = tint(steelDark, 1.0)
        ctx.fillRect(px - w * 0.17, h - 18, w * 0.34, 6)
        ctx.fillStyle = tint(steel, 1.0)
        ctx.fillRect(px - w * 0.028, h * 0.10, w * 0.056, h * 0.80)
        ctx.fillStyle = tint(steelDark, 1.25)
        ctx.beginPath()
        ctx.moveTo(px - w * 0.15, h * 0.115)
        ctx.lineTo(px + w * 0.15, h * 0.115)
        ctx.lineTo(px + w * 0.085, h * 0.035)
        ctx.lineTo(px - w * 0.085, h * 0.035)
        ctx.closePath()
        ctx.fill()
        ctx.fillStyle = tint(Theme.amberGlow, 1.0)
        ctx.fillRect(px - w * 0.13, h * 0.108, w * 0.26, h * 0.020)
        var beam = ctx.createLinearGradient(0, h * 0.13, 0, h * 0.66)
        beam.addColorStop(0, Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.26))
        beam.addColorStop(1, Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0))
        ctx.fillStyle = beam
        ctx.beginPath()
        ctx.moveTo(px - w * 0.13, h * 0.13)
        ctx.lineTo(px + w * 0.13, h * 0.13)
        ctx.lineTo(px + w * 0.40, h * 0.66)
        ctx.lineTo(px - w * 0.40, h * 0.66)
        ctx.closePath()
        ctx.fill()
        return
      }

      if (sprite.kind === "rollerDoor") {
        // The sector landmark the design names: "the sevens run under the
        // roller door". So the curtain is rolled up and the opening is clear,
        // because the track goes through it. A closed door would be a wall
        // across the road.
        var doorTop = h * 0.06
        var jamb = w * 0.075
        var head = h * 0.30
        var floorY = h - 12
        ctx.fillStyle = tint(steelDark, 1.0)
        ctx.fillRect(0, doorTop, w, head - doorTop)                       // lintel
        ctx.fillRect(0, head, jamb, floorY - head)                        // left jamb
        ctx.fillRect(w - jamb, head, jamb, floorY - head)                 // right jamb
        // the rolled-up curtain, hanging out of the lintel
        var slats = 5
        for (var s = 0; s < slats; s++) {
          ctx.fillStyle = tint(steel, s % 2 === 0 ? 1.0 : 0.78)
          ctx.fillRect(jamb, head + s * 5, w - jamb * 2, 4)
        }
        // hazard chevrons on the jambs, and a lit header
        ctx.fillStyle = tint(Theme.hazard, 1.0)
        for (var c2 = 0; c2 < 7; c2++) {
          var cy2 = head + 30 + c2 * ((floorY - head - 30) / 7)
          ctx.fillRect(0, cy2, jamb, 6)
          ctx.fillRect(w - jamb, cy2 + 4, jamb, 6)
        }
        ctx.fillStyle = tint(Theme.amberGlow, 1.0)
        ctx.fillRect(w * 0.16, doorTop + (head - doorTop) * 0.62, w * 0.68, 5)
        return
      }

      // "sign": a diagnostic board on a post
      var sw = w * 0.86
      var sx = (w - sw) / 2
      var shh = h * 0.42
      ctx.fillStyle = tint(steel, 0.8)
      ctx.fillRect(w * 0.46, h * 0.40, w * 0.08, h * 0.52)
      ctx.fillStyle = tint(Theme.tealDeep, 1.0)
      ctx.fillRect(sx, h * 0.06, sw, shh)
      ctx.strokeStyle = tint(Theme.teal, 1.0)
      ctx.lineWidth = 2
      ctx.strokeRect(sx + 1, h * 0.06 + 1, sw - 2, shh - 2)
      ctx.fillStyle = tint(Theme.teal, 1.0)
      for (var b = 0; b < 3; b++)
        ctx.fillRect(sx + sw * 0.12, h * 0.06 + shh * (0.22 + b * 0.24), sw * (0.72 - b * 0.18), shh * 0.11)
    }
  }

  onKindChanged: surface.requestPaint()
  onPaintColorChanged: surface.requestPaint()
  onNumberChanged: surface.requestPaint()
  onBodyChanged: surface.requestPaint()
  onGhostChanged: surface.requestPaint()
  onShowNumberChanged: surface.requestPaint()
  onDimChanged: surface.requestPaint()
}
