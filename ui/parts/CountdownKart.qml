import QtQuick
import "../"

// PROTOTYPE (proto/golden-hour): the child's kart on the start line, seen from
// behind-right and low, lit by the sunset in front of it.
//
// This is TrackSprite's kart -- the same six body specs, the same box
// skeleton, the same painter's-queue of flat faces -- under a different camera
// and a different lamp. TrackSprite lights the tail from behind the camera so
// four karts on a track read as four paints; here there is one kart and one
// sun, low and ahead-right, so the face the camera sees is in cool purple
// shadow and the right flank and the top edge carry the warm rim. The body
// is not more detailed than the track's; it is lit differently, which is the
// whole proposal.
//
// Drawn once at its on-screen size (this is a still hero, like the garage's,
// not one of sixteen moving sprites), and repainted only when the paint, the
// body, the number or the size changes.
//
// If the direction is adopted, the right shape is a `light` on TrackSprite
// rather than this copy of its skeleton; the copy is the prototype's debt and
// is named in the notes.
//
// THE ANCHOR is the bottom centre: `footY` is the sheet row the tyres touch.
Item {
  id: kart

  property color paintColor: Theme.paint(0)
  property int number: 7
  property int body: 0

  // The camera: behind, to the right, and low. Compare TrackSprite's 7/15.
  readonly property real yawDeg: 17
  readonly property real pitchDeg: 9
  readonly property real focal: 210

  // The sun, as the direction the light comes FROM in model space: ahead of
  // the kart (+z), to its right (+x), and low.
  readonly property real lx: 0.42
  readonly property real ly: 0.17
  readonly property real lz: 0.875

  readonly property color shadowPurple: "#5f255e"
  readonly property color bounce: "#c24073"
  readonly property color rim: "#f0b07a"
  readonly property color cream: "#f2e6c4"

  readonly property int footY: Math.round(height - width * 0.035)

  readonly property real cy: Math.cos(yawDeg * Math.PI / 180)
  readonly property real sy: Math.sin(yawDeg * Math.PI / 180)
  readonly property real cp: Math.cos(pitchDeg * Math.PI / 180)
  readonly property real sp: Math.sin(pitchDeg * Math.PI / 180)

  readonly property real refX: 0
  readonly property real refY: 9
  readonly property real refZ: 20
  readonly property real unit: width / 66
  readonly property real centreU: width * 0.50
  readonly property real centreV: footY - refY * cp * unit

  smooth: false
  antialiasing: false

  function depthAt(x, z) {
    return (z - refZ) * cy - (x - refX) * sy
  }
  function project(x, y, z) {
    var d = depthAt(x, z)
    var p = focal / (focal + d)
    var u = ((x - refX) * cy + (z - refZ) * sy) * p
    // Farther points sit HIGHER on the sheet: the camera is above the kart.
    var v = ((y - refY) * cp + d * sp) * p
    return [centreU + u * unit, centreV - v * unit]
  }

  // The same six silhouettes as TrackSprite, so the kart the child chose in
  // the garage is the kart on the line.
  readonly property var bodySpecs: [
    { halfW: 13, tail: 13.5, nose: 8.5, wing: 1, wingH: 17.5, pod: 1, cockpit: 1, noseZ: 46 },
    { halfW: 12, tail: 12.0, nose: 7.0, wing: 1, wingH: 16.0, pod: 1, cockpit: 1, noseZ: 48 },
    { halfW: 14.5, tail: 15.5, nose: 12.0, wing: 0, wingH: 0, pod: 0, cockpit: 1, noseZ: 44 },
    { halfW: 13.5, tail: 12.5, nose: 9.0, wing: 0, wingH: 0, pod: 0, cockpit: 1, noseZ: 42 },
    { halfW: 15.0, tail: 17.0, nose: 13.0, wing: 0, wingH: 0, pod: 1, cockpit: 0, noseZ: 47 },
    { halfW: 13.0, tail: 14.0, nose: 7.5, wing: 1, wingH: 18.5, pod: 1, cockpit: 1, noseZ: 49 }
  ]
  readonly property var spec: bodySpecs[((body % 6) + 6) % 6]

  Canvas {
    id: surface
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
    antialiasing: false

    function mix(a, b, t) {
      return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                     a.b + (b.b - a.b) * t, 1)
    }
    function scaled(c, k) {
      return Qt.rgba(Math.min(1, c.r * k), Math.min(1, c.g * k), Math.min(1, c.b * k), 1)
    }

    // One key, the sun. A face in shadow is the material pulled toward the
    // bar's shadow purple; a face that sees the sky picks up magenta bounce;
    // a face that sees the sun goes warm, then cream as it faces it squarely.
    // `rimK` is how much of the rim a material takes: paint all of it, rubber
    // half.
    function shade(base, n, rimK) {
      var lam = Math.max(0, n[0] * kart.lx + n[1] * kart.ly + n[2] * kart.lz)
      var up = Math.max(0, n[1])
      var c = mix(scaled(base, 0.40), kart.shadowPurple, 0.62)
      c = mix(c, kart.bounce, 0.40 * up)
      var warm = Math.min(1, lam * 1.9) * rimK
      c = mix(c, kart.rim, warm)
      if (lam > 0.55)
        c = mix(c, kart.cream, Math.min(1, (lam - 0.55) * 2.2) * rimK)
      return c
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      if (width < 8 || height < 8)
        return

      var g = kart.spec
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

      // The camera's forward direction: from behind-right and above, toward
      // the kart. A face whose outward normal agrees with it faces away.
      var Wx = -kart.sy * kart.cp
      var Wy = -kart.sp
      var Wz = kart.cy * kart.cp

      // The winding below (TrackSprite's) yields normals that point INTO the
      // box, so the outward normal is the negative, and that is what both
      // the cull and the lamp use.
      function face(pts3, base, rimK, bias) {
        var nIn = normalOf(pts3)
        if (!nIn)
          return
        var n = [-nIn[0], -nIn[1], -nIn[2]]
        if (n[0] * Wx + n[1] * Wy + n[2] * Wz > -0.0001)
          return
        var flat = []
        var d = 0
        for (var i = 0; i < pts3.length; i++) {
          flat.push(kart.project(pts3[i][0], pts3[i][1], pts3[i][2]))
          d += kart.depthAt(pts3[i][0], pts3[i][2])
        }
        queue.push({ pts: flat, fill: shade(base, n, rimK), depth: d / pts3.length + (bias || 0) })
      }

      function box(x0, x1, y0, y1, z0, z1, base, rimK, bias) {
        face([[x0,y1,z0],[x1,y1,z0],[x1,y1,z1],[x0,y1,z1]], base, rimK, bias)   // top
        face([[x0,y0,z1],[x1,y0,z1],[x1,y0,z0],[x0,y0,z0]], base, rimK, bias)   // bottom
        face([[x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0]], base, rimK, bias)   // tail
        face([[x1,y0,z1],[x0,y0,z1],[x0,y1,z1],[x1,y1,z1]], base, rimK, bias)   // nose
        face([[x1,y0,z0],[x1,y0,z1],[x1,y1,z1],[x1,y1,z0]], base, rimK, bias)   // right
        face([[x0,y0,z1],[x0,y0,z0],[x0,y1,z0],[x0,y1,z1]], base, rimK, bias)   // left
      }

      var paint = kart.paintColor
      var tyre = Qt.rgba(0.16, 0.10, 0.16, 1)
      var dark = Qt.rgba(0.22, 0.14, 0.22, 1)
      var glass = Qt.rgba(0.30, 0.10, 0.30, 1)
      var hw = g.halfW
      var noseZ = g.noseZ

      // Contact shadow: the hard, near part. The long throw across the floor
      // is the scene's, because the floor is the scene's.
      var sh = []
      var corners = [[-hw - 3, 0, -1], [hw + 3, 0, -1], [hw + 3, 0, noseZ + 1], [-hw - 3, 0, noseZ + 1]]
      for (var c = 0; c < corners.length; c++)
        sh.push(kart.project(corners[c][0], -0.4, corners[c][2]))
      ctx.beginPath()
      ctx.moveTo(sh[0][0], sh[0][1])
      for (var si = 1; si < sh.length; si++)
        ctx.lineTo(sh[si][0], sh[si][1])
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(0.05, 0.02, 0.05, 0.55)
      ctx.fill()

      // wheels
      box(-hw - 5, -hw + 0.5, 0.5, 11.5, 4, 17, tyre, 0.45, 0)
      box(hw - 0.5, hw + 5, 0.5, 11.5, 4, 17, tyre, 0.45, 0)
      box(-hw - 4, -hw + 0.5, 1.0, 10.0, noseZ - 15, noseZ - 4, tyre, 0.45, 0)
      box(hw - 0.5, hw + 4, 1.0, 10.0, noseZ - 15, noseZ - 4, tyre, 0.45, 0)

      // floor pan
      box(-hw + 1, hw - 1, 1.6, 4.4, 2, noseZ - 2, dark, 0.6, 0)

      // side pods
      if (g.pod === 1) {
        box(-hw + 0.5, -hw + 6, 3.6, 10.5, 13, noseZ - 14, paint, 1.0, 0)
        box(hw - 6, hw - 0.5, 3.6, 10.5, 13, noseZ - 14, paint, 1.0, 0)
      }

      // engine cowl and the tail the number sits on
      box(-hw + 2, hw - 2, 3.6, g.tail, 3, 18, paint, 1.0, 0)
      // spine forward to the cockpit
      box(-hw + 4, hw - 4, 3.6, g.tail - 3.0, 18, noseZ - 12, paint, 1.0, 0)

      // cockpit and helmet
      if (g.cockpit === 1) {
        box(-5.5, 5.5, g.tail - 3.0, g.tail + 1.5, 19, 27, glass, 0.8, 0)
        box(-3.6, 3.6, g.tail + 1.5, g.tail + 5.5, 20.5, 25.5, Theme.cream, 1.0, 0)
      }

      // nose
      box(-g.nose, g.nose, 3.6, 8.6, noseZ - 12, noseZ, paint, 1.0, 0)

      // wing, on two posts
      if (g.wing === 1) {
        box(-3.0, -1.4, g.tail, g.wingH, 2.5, 6.5, dark, 0.6, 0)
        box(1.4, 3.0, g.tail, g.wingH, 2.5, 6.5, dark, 0.6, 0)
        box(-hw - 1.5, hw + 1.5, g.wingH, g.wingH + 2.2, 1.0, 7.5, paint, 1.0, 0)
      }

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

      // Tail lamps: the one thing on the shadow side that is its own light,
      // and the warmest thing on the tail.
      function lamp(x0, x1) {
        var a = kart.project(x0, 6.0, 2.9)
        var b = kart.project(x1, 6.0, 2.9)
        var t = kart.project(x0, 8.5, 2.9)
        ctx.fillStyle = Qt.rgba(1.0, 0.36, 0.30, 1)
        ctx.fillRect(a[0], t[1], b[0] - a[0], a[1] - t[1])
      }
      lamp(-hw + 4.0, -hw + 7.0)
      lamp(hw - 7.0, hw - 4.0)

      // The number, on a plate across the tail. The plate is in shadow like
      // the rest of the tail, so it is a dusk white, not a paper white.
      var a = kart.project(-hw + 2.4, 6.2, 2.9)
      var b = kart.project(hw - 2.4, 6.2, 2.9)
      var t = kart.project(-hw + 2.4, g.tail - 1.2, 2.9)
      var pw = b[0] - a[0]
      var ph = a[1] - t[1]
      if (pw > 6 && ph > 5) {
        ctx.fillStyle = Qt.rgba(0.80, 0.66, 0.78, 1)
        ctx.fillRect(a[0] + pw * 0.26, t[1] + ph * 0.10, pw * 0.48, ph * 0.80)
        ctx.fillStyle = Qt.rgba(0.10, 0.04, 0.10, 1)
        ctx.font = "bold " + Math.max(7, Math.round(ph * 0.72)) + "px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(String(kart.number), a[0] + pw * 0.50, t[1] + ph * 0.50)
      }
    }
  }

  onWidthChanged: surface.requestPaint()
  onHeightChanged: surface.requestPaint()
  onPaintColorChanged: surface.requestPaint()
  onNumberChanged: surface.requestPaint()
  onBodyChanged: surface.requestPaint()
}
