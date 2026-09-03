import QtQuick
import "parts"

// The floor. Same road, no shader.
//
// GOLDEN-HOUR PROTOTYPE. Above the horizon this canvas is cleared to
// transparent -- the sky is ui/parts/SunsetSky.qml, an item behind this plane
// -- and below it the floor is near-black purple with a neon magenta grid
// that dissolves into a dusk fog, with the sun's foot spilling a warm ellipse
// down from the horizon. road.frag draws the same thing per pixel.
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
  property real glowAmount: 1.0
  property real gridAlpha: 0.35
  property real sunU: 0.68
  property real glowRx: 0.24
  property real glowRy: 0.08

  property color roadColor: "#221420"
  property color roadAlt: "#2c1a2a"
  property color rumbleColor: "#d8a12a"
  property color rumbleAlt: "#f2e6c4"
  property color laneColor: "#f2e6c4"
  property color groundColor: "#3c1228"
  property color gridColor: "#ff4fa3"
  property color skyColor: "#5e1a50"
  property color fogColor: "#3a1032"
  property color glowColor: "#f0956e"

  // How far down the track to draw. Past this the fog has closed anyway.
  property real drawDistance: 190
  property real nearDistance: 2.0
  // Where road.frag's `smoothstep(52.0, 16.0, z)` has finished: past this the
  // rumble alternation has dissolved into its own average and a band's colour
  // no longer depends on which stripe it is. The same two numbers appear in
  // `detail` below, and the sample ladder uses this one to know when it is
  // allowed to stop landing on stripe boundaries.
  readonly property real detailEnd: 52.0

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
    // Nothing. The sky is an item behind this plane; clear to it.
    var hy = Math.round(horizon * h)
    ctx.clearRect(0, 0, w, Math.max(0, hy))

    // ------------------------------------------------- the sample ladder
    //
    // A BAND IS ONE FILLED QUAD, SO IT MUST NOT STRADDLE A COLOUR BOUNDARY.
    //
    // The rumble colour flips every `stripe` world units and road.frag decides
    // that per pixel; here one band is painted one colour. Round two snapped
    // the ladder to HALF-stripe boundaries and took strides of `z * 0.18`, so
    // from about z = 8 outward a single band covered a whole stripe or more and
    // was painted a single colour across boundaries the shader draws. That is
    // the coarse, wrong zebra pitch the fallback has been shipping.
    //
    // Two rules now, and they are the ones that make the two pictures the same:
    //
    //   * inside `detailEnd`, no band may cross a multiple of `stripe`, so every
    //     band is one colour run and the pitch is the shader's exactly;
    //   * near the camera a band is subdivided further still, because between
    //     two z samples this draws a straight edge where the true projection
    //     curves, and close to the eye that is a visible kink in the kerb.
    //
    // Past `detailEnd` the alternation has already dissolved to its average, so
    // the ladder is free to stride geometrically and the band count stays down.
    var zs = []
    var z = drawDistance
    zs.push(z)
    var guard = 0
    while (z > nearDistance && ++guard < 240) {
      var step = Math.max(0.30, z * 0.18)
      var next
      if (z > detailEnd) {
        next = z - Math.max(stripe, step)
      } else {
        next = z - Math.min(stripe, step)
        var edge = Math.floor((z + travel) / stripe) * stripe - travel
        if (edge >= z - 1e-6)
          edge -= stripe
        if (next < edge)
          next = edge
      }
      if (next >= z - 1e-6)
        next = z - 0.30
      z = Math.max(nearDistance, next)
      zs.push(z)
    }

    function fog(zz) {
      return Math.max(0, Math.min(1, Math.exp(-fogDensity * zz * zz * 0.0011)))
    }
    // The shader's smoothstep(edge0, edge1, z), written the same way round:
    // 0 at `far`, 1 at `near`, eased at both ends.
    function fade(zz, far, near) {
      var t = Math.max(0, Math.min(1, (zz - far) / (near - far)))
      return t * t * (3 - 2 * t)
    }
    function blend(a, b, t) {
      var k = Math.max(0, Math.min(1, t))
      return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k,
                     a.b + (b.b - a.b) * k, 1)
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

      // The garage floor grid, in three octaves.
      //
      // One 4.5-unit spacing is right in the middle distance and wrong at both
      // ends. The bottom fifth of the screen covers under one world unit of
      // depth and about six across, so a single coarse grid puts nothing in
      // it: measured, the floor went black below y = 900, which is the
      // fastest-moving part of the frame and the part that sells speed. So the
      // two finer octaves fade in as the floor comes toward the eye. The
      // fade is by alpha, not by a switch, so no line ever pops into being --
      // and the coarse lines are skipped inside the finer passes, because a
      // multiple of 4.5 is also a multiple of 4.5/4.
      //
      // OPAQUE, PRE-BLENDED, FINEST FIRST. road.frag takes the MAX of the
      // line masks and mixes the ground toward the grid colour once, so a
      // crossing is exactly as bright as a line. Drawing translucent lines
      // stacked alpha at every crossing and the floor read as strings of
      // beads. Each octave is now painted opaque in the colour the shader
      // would arrive at, dimmest octave first, so the brightest line wins
      // wherever two cross -- which is what max() does.
      var octaves = [
        { "period": gridScale * 0.0625, "alpha": fade(zFar, 4.6, 2.2) * 0.55 * gridAlpha, "coarse": 16 },
        { "period": gridScale * 0.25, "alpha": fade(zFar, 12.0, 4.5) * 0.72 * gridAlpha, "coarse": 4 },
        { "period": gridScale, "alpha": gridAlpha, "coarse": 0 }
      ]
      var sFar = zFar + travel
      var sNear = zNear + travel
      for (var o = 0; o < octaves.length; o++) {
        var period = octaves[o].period
        var alpha = octaves[o].alpha
        if (alpha <= 0.02)
          continue
        ctx.globalAlpha = 1
        ctx.fillStyle = blend(groundColor, gridColor, alpha)
        var coarse = octaves[o].coarse

        // LONGITUDINAL: THE COLUMNS THAT CAN ACTUALLY LAND ON THE SCREEN.
        //
        // Round two counted columns outward from x = 0 and capped the count at
        // nine for the coarse octave. In a corner the road is not near x = 0:
        // at z = 190 with curve 0.0255 the visible world-x runs from -1201 to
        // -638, and not one of columns -9..9 falls inside it. So the far floor
        // carried no longitudinal lines at all and what survived was a handful
        // of near columns swept into thick arcs -- the "fuzzy diagonal arcs"
        // the fallback has been drawing where road.frag draws a lattice.
        //
        // The range is now solved rather than guessed. u in [0,1] means
        // x + curve z^2 in [-z aspect / focal, +z aspect / focal].
        var reach = zFar * aspect / focal
        var mid0 = -curve * zFar * zFar
        // A column pitch under about three plane pixels is a moire rather than
        // a grid. road.frag's derivative term fades those to the average; this
        // skips them, which is the same picture for much less fill, and is what
        // keeps the honest range from costing what the guessed one saved.
        var pitchPx = (period * focal * w) / (2 * zFar * aspect)
        var gLo = Math.ceil((mid0 - reach) / period)
        var gHi = Math.floor((mid0 + reach) / period)
        if (pitchPx >= 3.0 && gHi - gLo <= 220) {
          for (var g = gLo; g <= gHi; g++) {
            if (coarse > 0 && (g % coarse) === 0)
              continue
            var gx = g * period
            if (Math.abs(gx) < roadHalf + rumbleHalf)
              continue
            var gf = uAt(gx, zFar) * w
            var gn = uAt(gx, zNear) * w
            if ((gf < -0.05 * w && gn < -0.05 * w) || (gf > 1.05 * w && gn > 1.05 * w))
              continue
            // A hairline, not a smear. This plane is 480 px wide and is scaled
            // up with a nearest-neighbour filter, so one plane pixel is already
            // four on a 1920 screen. Round two's width expression hit its own
            // 2.4 cap at every depth inside z = 24 and drew the grid as
            // five-plane-pixel bars -- twenty screen pixels, measured, which is
            // most of why the floor read as a contour map.
            quad(gf - 0.5, yFar, gf + 0.5, yFar,
                 gn + 0.5, yNear + 1, gn - 0.5, yNear + 1)
          }
        }

        // TRANSVERSE: every grid boundary this band crosses.
        //
        // Round two ran this loop from the FAR index up to the NEAR one, and
        // the near index is the SMALLER of the two -- `sNear < sFar` -- so
        // `k <= kNear` was false on entry and the body never executed, on any
        // band, at any depth, on any frame. The fallback's floor has been
        // carrying no transverse lines whatever, which is exactly why round
        // two's critic measured "only longitudinal lines at roughly 45 degrees,
        // no cross-hatch anywhere in the bottom 260 px" and read it as
        // corduroy. road.frag has drawn both directions all along.
        var mLo = Math.ceil(sNear / period)
        var mHi = Math.floor(sFar / period)
        for (var m2 = mLo; m2 <= mHi && m2 - mLo < 24; m2++) {
          if (coarse > 0 && (m2 % coarse) === 0)
            continue
          var zLine = m2 * period - travel
          if (zLine <= zNear || zLine >= zFar)
            continue
          var yLine = vAt(zLine) * h
          ctx.fillRect(0, yLine, w, Math.max(1, Math.min(2, (yNear - yFar) * 0.18)))
        }
        ctx.globalAlpha = 1
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

      // How much of the zebra survives at this distance. Between the horizon
      // and about y = 480 a band is a couple of pixels tall, and a hard
      // black-and-cream alternation there reads as speckle rather than as fog,
      // so the alternations dissolve toward their own average with distance.
      // The shader does the same thing with the same two numbers.
      var detail = fade(mid, detailEnd, 16.0)
      var soft = 0.5 + (band - 0.5) * detail

      ctx.fillStyle = blend(rumbleColor, rumbleAlt, soft)
      quad(lFarOut, yFar, lFarIn, yFar, lNearIn, yNear + 1, lNearOut, yNear + 1)
      quad(rFarIn, yFar, rFarOut, yFar, rNearOut, yNear + 1, rNearIn, yNear + 1)

      ctx.fillStyle = blend(roadColor, roadAlt, soft * 0.34)
      quad(lFarIn, yFar, rFarIn, yFar, rNearIn, yNear + 1, lNearIn, yNear + 1)

      // lane markings: two solid inner edge lines and a dashed centre
      ctx.globalAlpha = detail
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
      ctx.globalAlpha = 1

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

    // ------------------------------------------------------ the sun's foot
    // A warm ellipse spilling down from the horizon under the disc, over
    // floor and road alike. The three stops are road.frag's `glowFall`.
    if (glowAmount > 0.001) {
      ctx.save()
      ctx.translate(sunU * w, hy)
      ctx.scale(glowRx * w, glowRy * h)
      var foot = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      foot.addColorStop(0.0, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.55 * glowAmount))
      foot.addColorStop(0.5, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.18 * glowAmount))
      foot.addColorStop(1.0, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0))
      ctx.fillStyle = foot
      ctx.fillRect(-1, 0, 2, 1)
      ctx.restore()
    }
  }
}
