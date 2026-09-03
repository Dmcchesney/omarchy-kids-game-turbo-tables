import QtQuick
import "../"

// One thing standing on the track: a kart seen from behind, or a piece of
// roadside furniture.
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
//
// `smooth: false` keeps the enlargement nearest-neighbour, which is the pixel
// look the game wants and is also the cheapest filter there is.
//
// THE ANCHOR is the bottom centre of the ITEM, and every kind is drawn
// standing on that point, so the track view positions a sprite by where it
// touches the ground and never has to know how tall it is. The canvas is
// taller than the item by `shadowRoom`: the long shadow toward the camera is
// drawn BELOW the contact point, and the item does not clip it.
//
// GOLDEN-HOUR PROTOTYPE. One key light, the sun, low and ahead-right of every
// object, so the face a driver sees -- the tail -- is in shadow, the body is
// a cool purple ramp, the sun-side silhouette carries one warm rim, and a
// long soft shadow runs toward the camera. Flat-shaded low-poly is the
// medium: nothing here adds detail, it adds light.
//
// Placeholder art. The design's shipping karts are eight angles and three
// scales; this is the one angle the track needs.
Item {
  id: sprite

  // "kart", or one of the roadside kinds below: tireWall, banner, timingBoard,
  // gantry, rollerDoor, drum, cone.
  property string kind: "kart"
  property color paintColor: Theme.paint(0)
  property int number: 7
  property int body: 0
  // What a banner or a board says.
  property string label: "TURBO"
  // A ghost is the same kart in the design's dark teal, and translucent.
  property bool ghost: false
  property bool showNumber: true
  // Dims a sprite that is far away, so distance reads as light as well as size.
  property real dim: 1.0

  readonly property bool isKart: kind === "kart"
  readonly property bool isArch: kind === "rollerDoor" || kind === "gantry"

  // The sheet. Karts are wide, roadside furniture is tall, arches span the road.
  readonly property int sheetW: isKart ? 192 : (isArch ? 320 : 128)
  readonly property int sheetH: isKart ? 128 : (isArch ? 200 : 176)
  // Extra canvas below the contact point, for the shadow toward the camera.
  readonly property int shadowRoom: isKart ? 44 : (isArch ? 0 : 34)

  width: sheetW
  height: sheetH
  transformOrigin: Item.Bottom
  smooth: false
  antialiasing: false

  // ------------------------------------------------------------ the camera
  // Model axes: +x to the right, +y up, +z from the tail toward the nose and
  // away from the camera. The camera sits behind and above the kart and is
  // yawed a few degrees off its centre line, so the visible faces are the
  // tail, the top, and a sliver of the right flank.
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
    width: sprite.sheetW
    height: sprite.sheetH + sprite.shadowRoom
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

    // ------------------------------------------------------- the one light
    // The sun, expressed in the space of the face normals `normalOf` below
    // computes. It is ahead of every kart, to the right, and low: so the
    // tail is in shadow, the roof catches a little, the right flank catches
    // more, and the rim -- a hidden, sun-facing face leaking round its
    // silhouette edge -- lands on the upper right.
    readonly property real lx: -0.42
    readonly property real ly: -0.26
    readonly property real lz: 0.87
    readonly property color warm: "#f0b07a"
    readonly property color cool: "#5f255e"
    readonly property color rim: "#f0b07a"
    readonly property color shade0: Qt.rgba(0.16, 0.04, 0.16, 1)

    function mix(a, b, t) {
      return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                     a.b + (b.b - a.b) * t, 1)
    }
    function gain(c, k) {
      var d = sprite.dim
      return Qt.rgba(Math.min(1, c.r * k * d), Math.min(1, c.g * k * d),
                     Math.min(1, c.b * k * d), 1)
    }
    function lambert(n) {
      return Math.max(0, n[0] * lx + n[1] * ly + n[2] * lz)
    }
    // The body ramp: the paint at a third of its strength in shadow, pulled
    // toward the cool purple; the paint nearly full where the sun reaches,
    // pulled toward the warm rim.
    function shade(base, n) {
      var lam = lambert(n)
      var c = gain(base, 0.46 + 0.54 * lam)
      c = mix(c, warm, 0.22 * lam)
      c = mix(c, cool, 0.26 * (1 - lam))
      return c
    }
    function rimColor(strength) {
      var d = sprite.dim
      return Qt.rgba(rim.r * d, rim.g * d, rim.b * d, Math.min(1, strength))
    }

    // ------------------------------------------------------ the shadow
    // Long, soft, toward the camera -- which on the sheet is down and, with
    // the sun off to the right, a little to the left. A gradient so it
    // fades out rather than ending at a line.
    function longShadow(ctx, x0, x1, yBase, len, lean) {
      var g = ctx.createLinearGradient(0, yBase, 0, yBase + len)
      g.addColorStop(0.0, Qt.rgba(0.08, 0.02, 0.09, 0.52))
      g.addColorStop(0.55, Qt.rgba(0.08, 0.02, 0.09, 0.30))
      g.addColorStop(1.0, Qt.rgba(0.08, 0.02, 0.09, 0.0))
      ctx.fillStyle = g
      ctx.beginPath()
      ctx.moveTo(x0, yBase)
      ctx.lineTo(x1, yBase)
      ctx.lineTo(x1 - lean + (x1 - x0) * 0.12, yBase + len)
      ctx.lineTo(x0 - lean - (x1 - x0) * 0.12, yBase + len)
      ctx.closePath()
      ctx.fill()
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

      // The camera's forward direction in model space. A face whose normal
      // agrees with it points away and is dropped before it is ever
      // projected, so the queue only ever holds faces that can be seen.
      var Wx = sprite.sy * sprite.cp
      var Wy = sprite.sp
      var Wz = sprite.cy * sprite.cp

      function faceOf(pts3, base, bias) {
        var n = normalOf(pts3)
        if (!n)
          return null
        var hidden = n[0] * Wx + n[1] * Wy + n[2] * Wz > -0.0001
        var flat = []
        var d = 0
        for (var i = 0; i < pts3.length; i++) {
          flat.push(sprite.project(pts3[i][0], pts3[i][1], pts3[i][2]))
          d += sprite.depthAt(pts3[i][0], pts3[i][2])
        }
        return { pts3: pts3, pts: flat, n: n, hidden: hidden,
                 fill: shade(base, n), depth: d / pts3.length + (bias || 0) }
      }

      function same(a, b) {
        return a[0] === b[0] && a[1] === b[1] && a[2] === b[2]
      }

      // A box, as its six faces. The visible ones go on the queue; then
      // every edge shared between a visible face and a hidden one is a
      // silhouette edge, and if the hidden face is the one facing the sun,
      // the light leaks round it: that is the rim, and it goes on the queue
      // just in front of its own face so nearer bodywork still covers it.
      function box(x0, x1, y0, y1, z0, z1, base, bias) {
        var faces = [
          faceOf([[x0,y1,z0],[x1,y1,z0],[x1,y1,z1],[x0,y1,z1]], base, bias),   // top
          faceOf([[x0,y0,z1],[x1,y0,z1],[x1,y0,z0],[x0,y0,z0]], base, bias),   // bottom
          faceOf([[x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0]], base, bias),   // tail
          faceOf([[x1,y0,z1],[x0,y0,z1],[x0,y1,z1],[x1,y1,z1]], base, bias),   // nose
          faceOf([[x1,y0,z0],[x1,y0,z1],[x1,y1,z1],[x1,y1,z0]], base, bias),   // right
          faceOf([[x0,y0,z1],[x0,y0,z0],[x0,y1,z0],[x0,y1,z1]], base, bias)    // left
        ]
        for (var f = 0; f < faces.length; f++)
          if (faces[f] && !faces[f].hidden)
            queue.push(faces[f])
        for (var a = 0; a < faces.length; a++) {
          var A = faces[a]
          if (!A || A.hidden)
            continue
          for (var b = 0; b < faces.length; b++) {
            var B = faces[b]
            if (!B || !B.hidden)
              continue
            var strength = lambert(B.n)
            if (strength < 0.15)
              continue
            // the two vertices A and B share, if any
            var shared = []
            for (var i = 0; i < 4; i++)
              for (var j = 0; j < 4; j++)
                if (same(A.pts3[i], B.pts3[j]))
                  shared.push(A.pts[i])
            if (shared.length === 2)
              queue.push({ line: shared, rim: strength, depth: A.depth - 0.4 })
          }
        }
      }

      var paint = sprite.skin
      var tyre = Qt.rgba(0.10, 0.06, 0.10, 1)
      var dark = Qt.rgba(0.15, 0.09, 0.15, 1)
      var glass = Qt.rgba(0.24, 0.10, 0.28, 1)

      var hw = g.halfW
      var noseZ = g.noseZ

      // The shadow first: a long one toward the camera, then the contact
      // shadow that gives it a hard edge under the wheels.
      var footL = sprite.project(-hw - 3, 0, 4)
      var footR = sprite.project(hw + 3, 0, 4)
      longShadow(ctx, footL[0] + 2, footR[0] - 2, footL[1] - 3,
                 sprite.shadowRoom + 16, 22)

      ctx.fillStyle = Qt.rgba(0.05, 0.01, 0.06, 0.34)
      ctx.beginPath()
      ctx.ellipse(sprite.sheetW * 0.155, sprite.sheetH - 20,
                  sprite.sheetW * 0.69, 20)
      ctx.fill()

      var sh = []
      var corners = [[-hw - 3, 0, -1], [hw + 3, 0, -1], [hw + 3, 0, noseZ + 1], [-hw - 3, 0, noseZ + 1]]
      for (var c = 0; c < corners.length; c++)
        sh.push(sprite.project(corners[c][0], -0.4, corners[c][2]))
      ctx.beginPath()
      ctx.moveTo(sh[0][0], sh[0][1])
      for (var si = 1; si < sh.length; si++)
        ctx.lineTo(sh[si][0], sh[si][1])
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(0.05, 0.01, 0.06, 0.42)
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

      // tail lamps, two warm squares that read at any size -- the one thing
      // on the shadow side that is lit, because it lights itself
      box(-hw + 4.0, -hw + 7.0, 6.0, 8.5, 2.6, 3.2, Theme.amber, 0.6)
      box(hw - 7.0, hw - 4.0, 6.0, 8.5, 2.6, 3.2, Theme.amber, 0.6)

      queue.sort(function (a, b) { return b.depth - a.depth })
      ctx.lineCap = "round"
      for (var q = 0; q < queue.length; q++) {
        var f = queue[q]
        if (f.line) {
          ctx.strokeStyle = rimColor(0.55 + f.rim * 0.5)
          ctx.lineWidth = 1.6
          ctx.beginPath()
          ctx.moveTo(f.line[0][0], f.line[0][1])
          ctx.lineTo(f.line[1][0], f.line[1][1])
          ctx.stroke()
          continue
        }
        ctx.beginPath()
        ctx.moveTo(f.pts[0][0], f.pts[0][1])
        for (var p = 1; p < f.pts.length; p++)
          ctx.lineTo(f.pts[p][0], f.pts[p][1])
        ctx.closePath()
        ctx.fillStyle = f.fill
        ctx.fill()
      }

      // The number, on a plate across the tail. Drawn after the faces because
      // it is a decal on one of them, not a solid of its own. Cream rather
      // than white: the tail is in shadow and a white plate would glow.
      if (sprite.showNumber && !sprite.ghost) {
        var a = sprite.project(-hw + 2.4, 6.2, 2.9)
        var b = sprite.project(hw - 2.4, 6.2, 2.9)
        var t = sprite.project(-hw + 2.4, g.tail - 1.2, 2.9)
        var pw = b[0] - a[0]
        var ph = a[1] - t[1]
        if (pw > 6 && ph > 5) {
          ctx.fillStyle = gain(Qt.rgba(0.88, 0.80, 0.70, 1), 1.0)
          ctx.fillRect(a[0] + pw * 0.26, t[1] + ph * 0.10, pw * 0.48, ph * 0.80)
          ctx.fillStyle = Qt.rgba(0.10, 0.04, 0.10, 1)
          ctx.font = "bold " + Math.max(7, Math.round(ph * 0.72)) + "px sans-serif"
          ctx.textAlign = "center"
          ctx.textBaseline = "middle"
          ctx.fillText(String(sprite.number), a[0] + pw * 0.50, t[1] + ph * 0.50)
        }
      }
    }

    // ------------------------------------------------- roadside furniture
    // Billboards: the camera looks at these nearly face on, so they are drawn
    // flat -- silhouettes in the cool purple, with one warm rim along the
    // sun side, upper right, and a long shadow toward the camera.
    function paintProp(ctx) {
      var w = width
      var h = sprite.sheetH
      var d = sprite.dim
      function tint(c, k) {
        return Qt.rgba(Math.min(1, c.r * k * d), Math.min(1, c.g * k * d),
                       Math.min(1, c.b * k * d), 1)
      }
      var ink = Qt.rgba(0.16, 0.055, 0.15, 1)      // #280e27, the bar's signage
      var post = Qt.rgba(0.22, 0.09, 0.22, 1)
      var rubber = Qt.rgba(0.11, 0.05, 0.11, 1)
      var magenta = Qt.rgba(1.0, 0.31, 0.64, 1)   // #ff4fa3
      var cream = Theme.cream
      var rimW = 1.5

      // a block with its warm rim on the top and right edges
      function block(x, y, bw, bh, col, rimTop, rimRight) {
        ctx.fillStyle = col
        ctx.fillRect(x, y, bw, bh)
        ctx.fillStyle = rimColor(0.95)
        if (rimTop !== false)
          ctx.fillRect(x, y, bw, rimW)
        if (rimRight !== false)
          ctx.fillRect(x + bw - rimW, y, rimW, bh)
      }
      function mono(px) {
        return "bold " + px + "px " + Theme.mono
      }

      // the shadow under everything except an arch, which the road runs
      // through rather than past
      if (!sprite.isArch) {
        longShadow(ctx, w * 0.30, w * 0.70, h - 16, sprite.shadowRoom + 12, 16)
        ctx.fillStyle = Qt.rgba(0.05, 0.01, 0.06, 0.36)
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
            block(x, y, tw * 0.92, th * 0.92, tint(rubber, 1 + r * 0.10), true, true)
            ctx.fillStyle = tint(post, 1.3)
            ctx.fillRect(x + tw * 0.30, y + th * 0.28, tw * 0.32, th * 0.36)
          }
          ctx.fillStyle = tint(r % 2 === 0 ? Theme.amberDeep : cream, 0.7)
          ctx.fillRect(0, h - 18 - (r + 1) * th - 3, w, 3)
        }
        return
      }

      if (sprite.kind === "drum") {
        var dw = w * 0.56
        var dx = (w - dw) / 2
        var dh = h * 0.62
        var dy = h - 16 - dh
        block(dx, dy, dw, dh, tint(Theme.amberDeep, 0.62), true, true)
        ctx.fillStyle = tint(Theme.amberDeep, 0.85)
        ctx.fillRect(dx + dw * 0.62, dy + rimW, dw * 0.38 - rimW, dh - rimW)
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(dx, dy + dh * 0.20, dw, dh * 0.08)
        ctx.fillRect(dx, dy + dh * 0.68, dw, dh * 0.08)
        return
      }

      if (sprite.kind === "cone") {
        var bx = w * 0.5
        var by = h - 16
        var ch = h * 0.52
        ctx.fillStyle = tint(Theme.amberDeep, 0.72)
        ctx.beginPath()
        ctx.moveTo(bx, by - ch)
        ctx.lineTo(bx + w * 0.24, by)
        ctx.lineTo(bx - w * 0.24, by)
        ctx.closePath()
        ctx.fill()
        // the rim: the sun-side slope of the cone
        ctx.strokeStyle = rimColor(0.95)
        ctx.lineWidth = rimW
        ctx.beginPath()
        ctx.moveTo(bx, by - ch)
        ctx.lineTo(bx + w * 0.24, by)
        ctx.stroke()
        ctx.fillStyle = tint(cream, 0.72)
        ctx.fillRect(bx - w * 0.155, by - ch * 0.52, w * 0.31, ch * 0.16)
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(bx - w * 0.30, by - 6, w * 0.60, 6)
        return
      }

      if (sprite.kind === "banner") {
        // A period sponsor banner: mono type, near-black on magenta, strung
        // between two posts, with the sun catching its top edge.
        var bw = w * 0.92
        var bx0 = (w - bw) / 2
        var by0 = h * 0.16
        var bh = h * 0.30
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(bx0 + 3, by0 + bh * 0.5, 4, h - 16 - by0 - bh * 0.5)
        ctx.fillRect(bx0 + bw - 7, by0 + bh * 0.5, 4, h - 16 - by0 - bh * 0.5)
        block(bx0, by0, bw, bh, tint(ink, 1.0), true, true)
        ctx.fillStyle = tint(magenta, 0.62)
        ctx.fillRect(bx0 + 3, by0 + 3, bw - 6, 2)
        ctx.fillRect(bx0 + 3, by0 + bh - 5, bw - 6, 2)
        ctx.fillStyle = tint(magenta, 0.95)
        ctx.font = mono(Math.round(bh * 0.52))
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(sprite.label, w / 2, by0 + bh * 0.52)
        return
      }

      if (sprite.kind === "timingBoard") {
        // A timing board on one post: three rows of lit digits on a dark
        // face, the top edge rimmed by the sun.
        var tbw = w * 0.80
        var tbx = (w - tbw) / 2
        var tby = h * 0.05
        var tbh = h * 0.50
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(w * 0.47, tby + tbh, w * 0.06, h - 16 - tby - tbh)
        block(tbx, tby, tbw, tbh, tint(ink, 1.0), true, true)
        ctx.fillStyle = tint(magenta, 0.62)
        ctx.fillRect(tbx + 3, tby + 3, tbw - 6, 1.5)
        ctx.font = mono(Math.round(tbh * 0.22))
        ctx.textAlign = "left"
        ctx.textBaseline = "middle"
        var rowsText = ["1  21", "2  34", "3  55"]
        for (var rt = 0; rt < rowsText.length; rt++) {
          ctx.fillStyle = tint(rt === 0 ? Theme.amberGlow : cream, 0.85)
          ctx.fillText(rowsText[rt], tbx + tbw * 0.12, tby + tbh * (0.24 + rt * 0.26))
        }
        return
      }

      if (sprite.kind === "gantry") {
        // The start gantry: two posts, a beam with a checkered band and the
        // name of the race across it, the sun on its top edge.
        // The beam sits low -- a third of the way down the sheet -- so it
        // crosses the road below the answer field rather than through it.
        var gTop = h * 0.30
        var gJamb = w * 0.06
        var gBeam = h * 0.20
        var gFloor = h - 12
        block(0, gTop, w, gBeam, tint(ink, 1.0), true, true)
        block(0, gTop + gBeam, gJamb, gFloor - gTop - gBeam, tint(post, 1.0), false, true)
        block(w - gJamb, gTop + gBeam, gJamb, gFloor - gTop - gBeam, tint(post, 1.0), false, true)
        var sq = h * 0.045
        for (var gc = 0; gc < Math.ceil(w / sq); gc++)
          for (var gr = 0; gr < 2; gr++) {
            ctx.fillStyle = tint((gc + gr) % 2 === 0 ? cream : ink, 0.9)
            ctx.fillRect(gc * sq, gTop + gBeam - sq * 2 - 2 + gr * sq, sq, sq)
          }
        ctx.fillStyle = tint(magenta, 0.95)
        ctx.font = mono(Math.round(gBeam * 0.46))
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(sprite.label, w / 2, gTop + (gBeam - sq * 2) * 0.52)
        // magenta stripes on the posts
        ctx.fillStyle = tint(magenta, 0.7)
        for (var gs = 0; gs < 6; gs++) {
          var gy = gTop + gBeam + 20 + gs * ((gFloor - gTop - gBeam - 20) / 6)
          ctx.fillRect(0, gy, gJamb, 4)
          ctx.fillRect(w - gJamb, gy + 3, gJamb, 4)
        }
        return
      }

      if (sprite.kind === "rollerDoor") {
        // The sector landmark the design names: "the sevens run under the
        // roller door". So the curtain is rolled up and the opening is clear,
        // because the track goes through it.
        var doorTop = h * 0.30
        var jamb = w * 0.075
        var head = h * 0.46
        var floorY = h - 12
        block(0, doorTop, w, head - doorTop, tint(ink, 1.0), true, true)      // lintel
        block(0, head, jamb, floorY - head, tint(post, 1.0), false, true)     // left jamb
        block(w - jamb, head, jamb, floorY - head, tint(post, 1.0), false, true)
        // the rolled-up curtain, hanging out of the lintel
        for (var s = 0; s < 4; s++) {
          ctx.fillStyle = tint(post, s % 2 === 0 ? 1.4 : 1.1)
          ctx.fillRect(jamb, head + s * 4, w - jamb * 2, 3)
        }
        ctx.fillStyle = tint(magenta, 0.7)
        for (var c2 = 0; c2 < 7; c2++) {
          var cy2 = head + 30 + c2 * ((floorY - head - 30) / 7)
          ctx.fillRect(0, cy2, jamb, 6)
          ctx.fillRect(w - jamb, cy2 + 4, jamb, 6)
        }
        ctx.fillStyle = tint(magenta, 0.8)
        ctx.fillRect(w * 0.16, doorTop + (head - doorTop) * 0.62, w * 0.68, 3)
        return
      }
    }
  }

  onKindChanged: surface.requestPaint()
  onPaintColorChanged: surface.requestPaint()
  onNumberChanged: surface.requestPaint()
  onBodyChanged: surface.requestPaint()
  onLabelChanged: surface.requestPaint()
  onGhostChanged: surface.requestPaint()
  onShowNumberChanged: surface.requestPaint()
  onDimChanged: surface.requestPaint()
}
