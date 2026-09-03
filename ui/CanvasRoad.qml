import QtQuick
import "parts"

// The floor. Same road, no shader.
//
// Design, Rendering approach, Fallback and floor: "If the shader fails to
// compile on a machine, the view falls back to a Canvas port of the classic
// segment-based road renderer at the same internal size."
//
// It is a port in the sense that matters -- back-to-front bands down the
// track, alternating rumble colours, converging lane markings, exponential
// fog -- but the geometry is not the classic renderer's. The classic one
// projects a list of segment vertices it keeps in memory; this one inverts the
// same projection the shader inverts, from the same uniforms, so the two
// pictures are the same picture. `zAt(v)` here and the `z = focal * camHeight
// / (2 (v - horizon))` line in road.frag are the same equation, and
// TrackView.qml's `groundV` is its inverse. If one of the three moves, all
// three move.
//
// Bands are cut at half-rumble boundaries so the stripes never crawl, and each
// band is subdivided near the camera, because between two z samples this draws
// a straight edge where the true projection curves, and close to the eye that
// difference is a visible kink in the kerb.
Canvas {
  id: road

  // ----------------------------------------------- the shader's uniforms
  property real horizon: 0.42
  property real camHeight: 2.20
  property real focal: 1.19
  property real aspect: 16 / 9
  property real travel: 0
  property real curve: 0
  property real roadHalf: 2.0
  property real rumbleHalf: 0.32
  property real stripe: 1.4
  property real gridScale: 4.5
  property real fogDensity: 1.0
  property real glowAmount: 0.10

  property color roadColor: "#23262c"
  property color roadAlt: "#2b2f36"
  property color rumbleColor: "#d8a12a"
  property color rumbleAlt: "#f2e6c4"
  property color laneColor: "#f2e6c4"
  property color groundColor: "#0b0d10"
  property color gridColor: "#16323a"
  property color skyColor: "#07090c"
  property color fogColor: "#07090c"
  property color glowColor: "#f5a524"

  // How far down the track to draw. Past this the fog has closed anyway.
  property real drawDistance: 190
  property real nearDistance: 2.0

  renderStrategy: Canvas.Immediate
  renderTarget: Canvas.Image
  smooth: false
  antialiasing: false

  // ------------------------------------------------------- the projection
  function vAt(z) { return horizon + (focal * camHeight) / (2 * z) }
  function zAt(v) { return (focal * camHeight) / (2 * Math.max(1e-4, v - horizon)) }
  function uAt(x, z) {
    return 0.5 + ((x + curve * z * z) * focal) / (z * 2 * aspect)
  }

  onPaint: {
    var ctx = getContext("2d")
    var w = width
    var h = height
    if (w <= 0 || h <= 0)
      return

    ctx.reset()

    // ------------------------------------------------------------- the sky
    var hy = Math.round(horizon * h)
    var sky = ctx.createLinearGradient(0, 0, 0, Math.max(1, hy))
    sky.addColorStop(0, skyColor)
    // The warm half of the backdrop is kept in the bottom quarter of the wall.
    // Spread over the whole of it, it stops reading as work lights behind a
    // roller door and starts reading as a sunset, which this game does not
    // have: it is a garage, at night, indoors.
    sky.addColorStop(0.76, Qt.rgba(groundColor.r * 0.34, groundColor.g * 0.34,
                                   groundColor.b * 0.40, 1))
    sky.addColorStop(1, Qt.rgba(groundColor.r * 0.30 + glowColor.r * 0.075,
                                groundColor.g * 0.30 + glowColor.g * 0.058,
                                groundColor.b * 0.30 + glowColor.b * 0.038, 1))
    ctx.fillStyle = sky
    ctx.fillRect(0, 0, w, Math.max(0, hy))

    // the warm haze that sits on the horizon where the work lights are
    var haze = ctx.createLinearGradient(0, Math.max(0, hy - h * 0.07), 0, hy)
    haze.addColorStop(0, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0))
    haze.addColorStop(1, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.17))
    ctx.fillStyle = haze
    ctx.fillRect(0, Math.max(0, hy - h * 0.07), w, Math.min(h * 0.07, hy))

    // ------------------------------------------------- the sample ladder
    // Cut at half-stripe boundaries so the rumble bands never crawl, and
    // subdivide near the camera so the kerbs do not kink.
    var half = stripe * 0.5
    var zs = []
    var z = drawDistance
    zs.push(z)
    var guard = 0
    while (z > nearDistance && ++guard < 200) {
      // The next sample is at least a fifth of the way closer -- which is what
      // keeps the band count logarithmic rather than proportional to the draw
      // distance -- and is then snapped down onto a half-stripe boundary, so
      // the rumble bands never crawl. Far away that skips whole stripes, and
      // it does not matter: the fog has closed over them.
      var target = z - Math.max(0.30, z * 0.18)
      var snapped = Math.floor((target + travel) / half) * half - travel
      if (snapped >= z - 1e-6)
        snapped = z - half
      z = Math.max(nearDistance, snapped)
      zs.push(z)
    }

    function fog(zz) {
      return Math.max(0, Math.min(1, Math.exp(-fogDensity * zz * zz * 0.0011)))
    }
    function quad(x1, y1, x2, y2, x3, y3, x4, y4) {
      ctx.beginPath()
      ctx.moveTo(x1, y1)
      ctx.lineTo(x2, y2)
      ctx.lineTo(x3, y3)
      ctx.lineTo(x4, y4)
      ctx.closePath()
      ctx.fill()
    }

    // ------------------------------------------------------------ the road
    for (var i = 0; i < zs.length - 1; i++) {
      var zFar = zs[i]
      var zNear = zs[i + 1]
      var yFar = vAt(zFar) * h
      var yNear = vAt(zNear) * h
      if (yNear - yFar < 0.35 && i > 0)
        continue

      var mid = (zFar + zNear) * 0.5
      var band = Math.floor(((mid + travel) / stripe) % 2 + 2) % 2

      // ground, full width, so the grid and the road sit on something
      ctx.fillStyle = groundColor
      ctx.fillRect(0, yFar, w, Math.max(1, yNear - yFar + 1))

      // the garage floor grid, longitudinal lines only: the transverse ones
      // fall out of the band edges below.
      // The columns that can possibly land on the plane at this depth, rather
      // than a fixed count with a loose reject: at the far end that is two or
      // three lines and at the near end it is none at all, and asking for the
      // range is what keeps the fallback's fill count flat instead of
      // proportional to the draw distance.
      var span = (aspect * zFar / focal) * 1.25 + Math.abs(curve) * zFar * zFar
      var columns = Math.min(9, Math.ceil(span / gridScale))
      ctx.fillStyle = gridColor
      for (var g = -columns; g <= columns; g++) {
        var gx = g * gridScale
        if (Math.abs(gx) < roadHalf + rumbleHalf)
          continue
        var gf = uAt(gx, zFar) * w
        var gn = uAt(gx, zNear) * w
        if ((gf < -0.05 * w && gn < -0.05 * w) || (gf > 1.05 * w && gn > 1.05 * w))
          continue
        var wf = Math.max(0.5, Math.min(2.4, (w * 0.0016) * (focal / zFar) * 40))
        var wn = Math.max(0.5, Math.min(2.4, (w * 0.0016) * (focal / zNear) * 40))
        quad(gf - wf, yFar, gf + wf, yFar, gn + wn, yNear + 1, gn - wn, yNear + 1)
      }

      // a transverse grid line wherever a grid boundary crosses this band
      var sFar = zFar + travel
      var sNear = zNear + travel
      var kFar = Math.floor(sFar / gridScale)
      var kNear = Math.floor(sNear / gridScale)
      if (kFar !== kNear) {
        var zLine = kFar * gridScale - travel
        var yLine = vAt(zLine) * h
        ctx.fillStyle = gridColor
        ctx.fillRect(0, yLine, w, Math.max(1, Math.min(2, (yNear - yFar) * 0.20)))
      }

      // rumble strips, then the road on top of them
      var edgeFar = roadHalf + rumbleHalf
      var edgeNear = roadHalf + rumbleHalf
      var lFarOut = uAt(-edgeFar, zFar) * w
      var lFarIn = uAt(-roadHalf, zFar) * w
      var lNearOut = uAt(-edgeNear, zNear) * w
      var lNearIn = uAt(-roadHalf, zNear) * w
      var rFarIn = uAt(roadHalf, zFar) * w
      var rFarOut = uAt(edgeFar, zFar) * w
      var rNearIn = uAt(roadHalf, zNear) * w
      var rNearOut = uAt(edgeNear, zNear) * w

      ctx.fillStyle = band === 1 ? rumbleAlt : rumbleColor
      quad(lFarOut, yFar, lFarIn, yFar, lNearIn, yNear + 1, lNearOut, yNear + 1)
      quad(rFarIn, yFar, rFarOut, yFar, rNearOut, yNear + 1, rNearIn, yNear + 1)

      ctx.fillStyle = band === 1 ? roadAlt : roadColor
      quad(lFarIn, yFar, rFarIn, yFar, rNearIn, yNear + 1, lNearIn, yNear + 1)

      // lane markings: two solid inner edge lines and a dashed centre
      ctx.fillStyle = laneColor
      var inner = roadHalf * 0.88
      var markF = Math.max(0.5, (rFarIn - lFarIn) * 0.012)
      var markN = Math.max(0.5, (rNearIn - lNearIn) * 0.012)
      var eLF = uAt(-inner, zFar) * w, eLN = uAt(-inner, zNear) * w
      var eRF = uAt(inner, zFar) * w, eRN = uAt(inner, zNear) * w
      quad(eLF - markF, yFar, eLF + markF, yFar, eLN + markN, yNear + 1, eLN - markN, yNear + 1)
      quad(eRF - markF, yFar, eRF + markF, yFar, eRN + markN, yNear + 1, eRN - markN, yNear + 1)
      if (Math.floor(((mid + travel) / (stripe * 2)) % 2 + 2) % 2 === 1) {
        var cF = uAt(0, zFar) * w, cN = uAt(0, zNear) * w
        quad(cF - markF, yFar, cF + markF, yFar, cN + markN, yNear + 1, cN - markN, yNear + 1)
      }

      // a pool of work light on the tarmac, every fourth stripe
      var pool = ((mid + travel) / (stripe * 12)) % 1 - 0.5
      var poolAmount = Math.exp(-pool * pool * 26) * glowAmount
      if (poolAmount > 0.004) {
        ctx.globalAlpha = Math.min(0.5, poolAmount)
        ctx.fillStyle = glowColor
        quad(lFarIn, yFar, rFarIn, yFar, rNearIn, yNear + 1, lNearIn, yNear + 1)
        ctx.globalAlpha = 1
      }

    }

    // ------------------------------------------------------------- the fog
    // One gradient rather than a translucent rectangle per band. Fog is a
    // function of distance, distance is a function of the screen row, so it is
    // a vertical gradient exactly -- and drawing it once instead of two dozen
    // times is the single biggest saving in this file on a CPU renderer, and
    // it removes the banding the per-band version had at the vanishing point.
    var fogTop = vAt(drawDistance) * h
    var fogBottom = h
    if (fogBottom > fogTop + 1) {
      var grad = ctx.createLinearGradient(0, fogTop, 0, fogBottom)
      for (var f = 0; f <= 12; f++) {
        var t = f / 12
        var y = fogTop + (fogBottom - fogTop) * t
        var alpha = 1 - fog(zAt(y / h))
        grad.addColorStop(t, Qt.rgba(fogColor.r, fogColor.g, fogColor.b,
                                     Math.max(0, Math.min(1, alpha))))
      }
      ctx.fillStyle = grad
      ctx.fillRect(0, fogTop, w, fogBottom - fogTop)
    }
  }
}
