import QtQuick
import "parts"
import "parts/Terrain.js" as Terrain

// The floor. Same road, no shader.
//
// GOLDEN HOUR. Above the horizon this canvas is cleared to transparent -- the
// sky is ui/parts/SunsetSky.qml, an item behind this plane -- and below it the
// floor is the circuit's terrain, hazing into the horizon glow, with the sun's
// foot spilling a warm ellipse down from the horizon and the tarmac holding its
// own tone further out than the ground does. road.frag draws the same thing per
// pixel.
//
// PIECE T -- AND THE ONLY REASON THE TWO CAN NOW BE IDENTICAL.
//
// The terrain the design asks for is two octaves of noise. A smooth,
// interpolated noise is free in a fragment shader and impossible in a renderer
// that fills quads, so "the fallback draws the same picture" would have been a
// claim again rather than a fact. `ui/parts/Terrain.js` makes it a fact: the
// noise is an INTEGER HASH ON A WORLD LATTICE, flat inside a cell, and the same
// bits come out of GLSL's `uint` chain and JavaScript's `Math.imul` chain. So
// the shader paints blocks and this file fills the same blocks, cell for cell,
// and away from a polygon edge the two frames difference to zero.
//
// That also happens to be the right picture. The design's world resolves into
// four-pixel blocks at 1080p, and a ground made of interpolated gradients would
// have floated over it -- which is the exact complaint the piece before this one
// closed on its own effects.
//
// THIS IS THE FALLBACK, NOT THE PICTURE THE VM RENDERS.
//
// `LIBGL_ALWAYS_SOFTWARE=1`, which is what the VM's Hyprland environment sets,
// selects Mesa's **llvmpipe**, which is an OpenGL DRIVER: `GraphicsInfo.api` is
// `OpenGL`, a `ShaderEffect` compiles and runs, and `TrackView.shaderMode` is
// true. `QT_QUICK_BACKEND=software` selects Qt's **QPainter scene graph**, which
// has no shader pipeline at all -- and that is the only thing
// `TrackView.softwareScene` gates on.
//
// Measured in the VM, on the real stack, round five: with the Wayland platform
// and `LIBGL_ALWAYS_SOFTWARE=1` the log reads
//   qt.rhi.general: OpenGL VENDOR: Mesa RENDERER: llvmpipe (LLVM 22.1.8)
//   qml: TrackView: road path = shader
// and with `QT_QUICK_BACKEND=software` added to the same command it reads
//   qt.scenegraph.general: Loading backend software
//   qml: TrackView: road path = canvas (software scene graph)
//
// So `road.frag` is what a child sees in the VM and on any machine with a GL
// or Vulkan stack; this file is the fallback for Qt's software scene graph,
// which is what this project's own headless Mac harness runs under and what a
// machine whose shader refuses to compile falls back to.
//
// Design, Rendering approach, Fallback and floor: "If the shader fails to
// compile on a machine, the view falls back to a Canvas port of the classic
// segment-based road renderer at the same internal size."
//
// It is a port in the sense that matters -- back-to-front bands down the
// track, alternating rumble colours, converging lane markings, exponential
// haze -- but the geometry is not the classic renderer's. The classic one
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
  // What fraction of the floor's haze density the tarmac and its kerbs take.
  // road.frag's `surfaceFog`; see the comment on the haze below.
  property real surfaceFog: 0.30
  property real glowAmount: 1.0
  property real gridAlpha: 0.35
  property real sunU: 0.68
  property real glowRx: 0.24
  property real glowRy: 0.08

  // ------------------------------------------------------------- piece T
  property real sectorLength: 36.0
  property real clock: 0
  property real shimmer: 0
  property real texelU: 1 / 528
  property real nightfall: 0

  property color roadColor: "#221420"
  property color roadAlt: "#2c1a2a"
  property color rumbleColor: "#d8a12a"
  property color rumbleAlt: "#f2e6c4"
  property color laneColor: "#f2e6c4"
  property color groundColor: "#3c1228"
  property color gridColor: "#ff4fa3"
  property color skyColor: "#5e1a50"
  property color fogColor: "#d75d6b"
  property color glowColor: "#f0956e"
  property color waterColor: "#3a1c46"
  property color waterLit: "#f2c68a"

  // How far down the track to draw. Past this the haze has closed anyway.
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

  // road.frag's shimmer: a WHOLE-ROW displacement, a whole plane pixel at a
  // time, in a band a tenth of the frame deep under the horizon. The shader
  // shifts the sampled `u` right by this, so the picture moves left by it; here
  // the band is drawn shifted left by the same integer number of pixels. That
  // is why the shimmer is row-based rather than per-pixel: a per-pixel warp
  // would be free in the shader and unreachable here, and the two paths drawing
  // the same picture is a gate on this piece.
  function shimmerPx(v) {
    if (shimmer <= 0.001)
      return 0
    var dy = v - horizon
    if (dy <= 0)
      return 0
    var band = Terrain.smooth(0.085, 0.006, dy)
    var wobble = Math.sin(v * 190.0 + clock * 2.6) * 0.55
                 + Math.sin(v * 71.0 - clock * 1.7) * 0.45
    return Math.floor(shimmer * band * wobble * 1.6 + 0.5)
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
    // that per pixel; here one band is painted one colour. Four rules, and the
    // fourth is the one that nearly cost the road:
    //
    //   * inside `detailEnd`, a band's edges land on multiples of HALF a
    //     stripe, so every band is one colour run at the shader's own pitch;
    //   * the band's colour is the shader's expression, on the same `s`;
    //   * past `detailEnd` the alternation has dissolved into its own average,
    //     so the ladder strides geometrically and the band count stays down;
    //   * AND NO BAND IS EVER THINNER THAN HALF A PLANE PIXEL.
    //
    // A band thinner than a third of a plane pixel is dropped by the loop
    // below, and halving the stride to fix the zebra pitch once made every band
    // from about z = 25 outward exactly that thin: the tarmac, the kerb and the
    // floor at z = 30, 35 and 40 all read luminance 119.9, which is `fogColor`
    // and nothing else.
    //
    // `minStep` is the z-stride that gives half a plane pixel at this depth,
    // solved rather than guessed: a band of depth dz is
    // `height * focal * camHeight * dz / (2 z^2)` plane pixels tall, so half a
    // pixel is `dz = z^2 / (height * focal * camHeight)`.
    var half = stripe * 0.5
    var zs = []
    var z = drawDistance
    zs.push(z)
    var guard = 0
    while (z > nearDistance && ++guard < 400) {
      var step = Math.max(0.30, z * 0.18)
      var next
      if (z > detailEnd) {
        next = z - Math.max(stripe, step)
      } else {
        var minStep = (z * z) / Math.max(1, height * focal * camHeight)
        var want = Math.max(minStep, Math.min(half, step))
        next = z - want
        // Snap DOWN to a half-stripe boundary, so a band's edges are always
        // colour boundaries and it is never shortened back under `want`.
        var edge = Math.floor((next + travel) / half) * half - travel
        if (edge < next + half - 1e-6 && edge < z - 1e-6)
          next = edge
      }
      if (next >= z - 1e-6)
        next = z - 0.30
      z = Math.max(nearDistance, next)
      zs.push(z)
    }

    // THE HAZE IS PRE-MULTIPLIED INTO EVERY FILL, NOT LAID OVER THE TOP.
    //
    // An overlay is only correct while every surface hazes at the same rate,
    // and road.frag no longer does: the tarmac and its kerbs take `surfaceFog`
    // of the ground's density so the road stays legible into the distance. So
    // each fill is blended toward `fogColor` before it is filled -- the same
    // arithmetic the shader does per pixel, at no extra draw call.
    function fog(zz) {
      return Math.max(0, Math.min(1, Math.exp(-fogDensity * zz * zz * 0.0011)))
    }
    function fogSurface(zz) {
      return Math.max(0, Math.min(1,
        Math.exp(-fogDensity * surfaceFog * zz * zz * 0.0011)))
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
    // A terrain triple, hazed, as a colour. The one place the two renderers'
    // arithmetic has to line up, so it is written once.
    function hazed(rgb, f) {
      return Qt.rgba(fogColor.r + (rgb[0] - fogColor.r) * f,
                     fogColor.g + (rgb[1] - fogColor.g) * f,
                     fogColor.b + (rgb[2] - fogColor.b) * f, 1)
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

    // ------------------------------------------------ the far side of the haze
    //
    // ONE BASE COAT UNDER THE WHOLE FLOOR, AND IT IS NOT DECORATION.
    //
    // road.frag draws a colour for every pixel below the horizon; this file
    // draws bands, and the bands do not tile the floor exactly. Two rows are
    // left over: between the horizon line and the first band, z runs to infinity
    // and the haze has closed over it entirely; and a band thinner than a third
    // of a plane pixel is skipped below. Without this coat both gaps show the
    // Race screen's own background straight through the plane.
    ctx.fillStyle = fogColor
    ctx.fillRect(0, hy, w, Math.max(0, h - hy))

    // ------------------------------------------------------------ the road
    for (var i = 0; i < zs.length - 1; i++) {
      var zFar = zs[i]
      var zNear = zs[i + 1]
      var yFar = vAt(zFar) * h
      var yNear = vAt(zNear) * h
      if (yNear - yFar < 0.35 && i > 0)
        continue

      var mid = (zFar + zNear) * 0.5
      var sMid = mid + travel
      // road.frag: `float zebra = step(0.5, fract(s / stripe));`
      var bandPhase = (sMid / stripe) % 1
      if (bandPhase < 0)
        bandPhase += 1
      var band = bandPhase >= 0.5 ? 1 : 0
      // How much of each surface survives the dusk at this depth. The ground
      // and the tarmac take different rates; see `fog` above.
      var fFloor = fog(mid)
      var fSurf = fogSurface(mid)
      // road.frag shifts a row by whole plane pixels near the horizon; this
      // shifts the whole band by the same integer. Applied to every x below.
      var sx = -shimmerPx(yNear / h)

      // ------------------------------------------------------ the terrain
      // One row of lattice blocks across the visible floor, evaluated by the
      // same `Terrain.groundAt` road.frag evaluates per pixel. Adjacent cells
      // whose colour rounds the same way are merged into one quad, which is
      // most of them on the flatter sectors.
      //
      // The step is the finest lattice that can still contribute at this depth:
      // half a unit while the fine octave survives, one unit (the rut lattice)
      // past it. Every lattice in Terrain.js is a multiple of half a unit for
      // exactly this reason -- so one loop lands on every cell boundary all
      // three octaves have, and the fallback's blocks are the shader's blocks
      // rather than an average of them.
      var ff = Terrain.fineFade(zFar)
      var gstep = ff > 0.02 ? Terrain.FINE : Terrain.RUT
      var reach = zFar * aspect / focal
      var mid0 = -curve * zFar * zFar
      var pitchPx = (gstep * focal * w) / (2 * zFar * aspect)
      if (pitchPx >= 0.75) {
        var cLo = Math.floor((mid0 - reach) / gstep)
        var cHi = Math.ceil((mid0 + reach) / gstep)
        if (cHi - cLo > 400) {
          cLo = Math.floor(mid0 / gstep) - 200
          cHi = cLo + 400
        }
        var runStart = cLo
        var runKey = ""
        var runColor = null
        for (var c = cLo; c <= cHi; c++) {
          var cx0 = c * gstep
          var rgb = Terrain.groundAt(cx0 + gstep * 0.5, sMid, zFar)
          var col = hazed(rgb, fFloor)
          var key = Math.round(col.r * 255) + "," + Math.round(col.g * 255)
                    + "," + Math.round(col.b * 255)
          if (runColor === null) {
            runStart = c
            runKey = key
            runColor = col
          } else if (key !== runKey || c === cHi) {
            var endAt = (key !== runKey) ? c : c + 1
            ctx.fillStyle = runColor
            var aF = uAt(runStart * gstep, zFar) * w + sx
            var bF = uAt(endAt * gstep, zFar) * w + sx
            var aN = uAt(runStart * gstep, zNear) * w + sx
            var bN = uAt(endAt * gstep, zNear) * w + sx
            quad(aF, yFar, bF, yFar, bN, yNear + 1, aN, yNear + 1)
            runStart = c
            runKey = key
            runColor = col
          }
        }
      } else {
        // Past the pitch at which a block is under a pixel, the blocks average
        // out; the shader's derivative-free hash does not, but at this depth
        // the haze has taken almost everything anyway. One fill of the sector's
        // own soil, which is what the average converges to.
        ctx.fillStyle = hazed(Terrain.groundAt(mid0, sMid, zFar), fFloor)
        ctx.fillRect(0, yFar, w, Math.max(1, yNear - yFar + 1))
      }

      // --------------------------------------------------------- the lake
      // Water on the right of the road, with the sun's column reflected in it
      // as rungs that stretch toward the eye. road.frag's `water` block.
      var flags = sectorFlags(sMid)
      if (flags[1] > 0.001) {
        var shore = roadHalf + rumbleHalf + 2.6
        var ripple = Math.sin(sMid * 2.7 - clock * 1.9) * 0.5
                     + Math.sin(sMid * 6.1 + clock * 1.1) * 0.5
        var rungs = ripple >= 0 ? 1 : 0
        var lakeR = waterColor.r * (rungs ? 1.18 : 1)
        var lakeG = waterColor.g * (rungs ? 1.18 : 1)
        var lakeB = waterColor.b * (rungs ? 1.18 : 1)
        var xShoreF = uAt(shore + 1.1, zFar) * w + sx
        var xShoreN = uAt(shore + 1.1, zNear) * w + sx
        // THE REFLECTED COLUMN IS IN SCREEN u, because that is what a
        // reflection is: the sun's image is under the disc, not at a fixed
        // place on the lake. Twelve slices from the shore to the right edge,
        // each one flat, so the ladder is made of the same blocks as the rest
        // of the ground rather than being a smooth beam laid over it.
        var xStart = Math.max(0, Math.min(xShoreF, xShoreN))
        if (xStart < w) {
          var slices = 12
          for (var q = 0; q < slices; q++) {
            var px0 = xStart + (w - xStart) * q / slices
            var px1 = xStart + (w - xStart) * (q + 1) / slices
            var uc = ((px0 + px1) * 0.5 - sx) / w
            var colm = Math.max(0, 1 - Math.abs(uc - sunU) / 0.075)
            colm *= colm
            var ladder = colm * (0.45 + 0.55 * rungs)
            var lr = lakeR + (waterLit.r - lakeR) * ladder
            var lg = lakeG + (waterLit.g - lakeG) * ladder
            var lb = lakeB + (waterLit.b - lakeB) * ladder
            ctx.fillStyle = hazed([lr, lg, lb], fFloor)
            quad(Math.max(px0, xShoreF), yFar, Math.max(px1, xShoreF), yFar,
                 Math.max(px1, xShoreN), yNear + 1, Math.max(px0, xShoreN), yNear + 1)
          }
        }
      }

      // ------------------------------------------------- the pit's grid
      // The diagnostic floor grid, in three octaves, and ONLY at the pit --
      // which is where the design keeps it. Everywhere else the ground is
      // terrain and this loop does nothing at all, which is most of why the
      // fallback got faster rather than slower this piece.
      if (flags[0] > 0.001) {
        drawGrid(ctx, w, h, zFar, zNear, yFar, yNear, fFloor, sx, flags[0])
      }

      // ------------------------------------------------------- the surface
      var edge = roadHalf + rumbleHalf
      var lFarOut = uAt(-edge, zFar) * w + sx
      var lFarIn = uAt(-roadHalf, zFar) * w + sx
      var lNearOut = uAt(-edge, zNear) * w + sx
      var lNearIn = uAt(-roadHalf, zNear) * w + sx
      var rFarIn = uAt(roadHalf, zFar) * w + sx
      var rFarOut = uAt(edge, zFar) * w + sx
      var rNearIn = uAt(roadHalf, zNear) * w + sx
      var rNearOut = uAt(edge, zNear) * w + sx

      // How much of the zebra survives at this distance. Between the horizon
      // and about y = 480 a band is a couple of pixels tall, and a hard
      // alternation there reads as speckle rather than as haze, so it dissolves
      // toward its own average with distance. The shader does the same thing
      // with the same two numbers.
      var detail = fade(mid, detailEnd, 16.0)
      var soft = 0.5 + (band - 0.5) * detail

      // KERBS ONLY INSIDE CORNERS. road.frag's `kerbHere`: the inside of a
      // right-hand bend is the right verge, and where there is no kerb the
      // strip is a dirt shoulder in the sector's own soil.
      var cHere = Terrain.curveNormAt(sMid)
      var bend = Terrain.smooth(0.22, 0.72, Math.abs(cHere))
      var soilRgb = sectorSoil(sMid)
      var shoulder = [soilRgb[0] * 0.72, soilRgb[1] * 0.72, soilRgb[2] * 0.72]
      var zebra = blend(rumbleColor, rumbleAlt, soft)
      var kerbR = cHere > 0 ? bend : 0
      var kerbL = cHere < 0 ? bend : 0

      ctx.fillStyle = blend(hazed(shoulder, fSurf), blend(fogColor, zebra, fSurf), kerbL)
      quad(lFarOut, yFar, lFarIn, yFar, lNearIn, yNear + 1, lNearOut, yNear + 1)
      ctx.fillStyle = blend(hazed(shoulder, fSurf), blend(fogColor, zebra, fSurf), kerbR)
      quad(rFarIn, yFar, rFarOut, yFar, rNearOut, yNear + 1, rNearIn, yNear + 1)

      // THE TARMAC, IN LATERAL SLICES, because it now has a crown, two tyre
      // lines per lane and, at a corner's exit, skid marks -- all of which are
      // functions of x. Sixteen slices across the road is one slice per eighth
      // of a lane, which is finer than the narrowest feature on it.
      var wear = Terrain.blockNoise(mid0, sMid, Terrain.COARSE * 3.0)
      var cAhead = Terrain.curveNormAt(sMid + 7.0)
      var exiting = Math.max(0, Math.min(1, (Math.abs(cHere) - Math.abs(cAhead)) * 7.0))
                    * Terrain.smooth(0.30, 0.62, Math.abs(cHere))
      var side = cHere > 0 ? -1 : 1
      var drift = 0.34 + 0.34 * Math.max(0, Math.min(1, (Math.abs(cHere) - 0.3) / 0.7))
      var gp = ((sMid % (sectorLength * 12)) + sectorLength * 12) % (sectorLength * 12)
      var inGrid = (gp >= 2 && gp <= 5) ? detail : 0

      var slices2 = 16
      for (var t2 = 0; t2 < slices2; t2++) {
        var xa = -roadHalf + (2 * roadHalf) * t2 / slices2
        var xb = -roadHalf + (2 * roadHalf) * (t2 + 1) / slices2
        var xc = (xa + xb) * 0.5
        var axc = Math.abs(xc)
        var rr = roadColor.r + (roadAlt.r - roadColor.r) * soft * 0.34
        var rg = roadColor.g + (roadAlt.g - roadColor.g) * soft * 0.34
        var rb = roadColor.b + (roadAlt.b - roadColor.b) * soft * 0.34
        var lift = (0.94 + 0.12 * wear) * (0.88 + 0.20 * (1 - (axc / roadHalf) * (axc / roadHalf)))
        var tyre = (Math.abs(axc - roadHalf * 0.30) < roadHalf * 0.055
                    || Math.abs(axc - roadHalf * 0.70) < roadHalf * 0.055) ? 1 : 0
        lift *= 1 - 0.16 * tyre * detail
        if (exiting > 0.002) {
          var skid = (Math.abs(xc - side * roadHalf * drift) < roadHalf * 0.075
                      || Math.abs(xc - side * roadHalf * (drift + 0.30)) < roadHalf * 0.060) ? 1 : 0
          lift *= 1 - 0.30 * skid * exiting * detail
        }
        rr *= lift; rg *= lift; rb *= lift
        if (inGrid > 0.001) {
          var chequer = (Math.floor((xc + roadHalf) / (roadHalf * 0.25))
                         + Math.floor((gp - 2) / 0.75)) % 2
          chequer = chequer < 0 ? chequer + 2 : chequer
          var gr = chequer ? rumbleAlt.r : roadColor.r * 0.55
          var gg = chequer ? rumbleAlt.g : roadColor.g * 0.55
          var gb = chequer ? rumbleAlt.b : roadColor.b * 0.55
          rr += (gr - rr) * inGrid * 0.88
          rg += (gg - rg) * inGrid * 0.88
          rb += (gb - rb) * inGrid * 0.88
        }
        ctx.fillStyle = hazed([rr, rg, rb], fSurf)
        quad(uAt(xa, zFar) * w + sx, yFar, uAt(xb, zFar) * w + sx, yFar,
             uAt(xb, zNear) * w + sx, yNear + 1, uAt(xa, zNear) * w + sx, yNear + 1)
      }

      // Lane markings: two solid inner edge lines and a dashed centre. The
      // shader mixes toward `laneColor` at 0.88 * detail * (1 - inGrid) and
      // hazes the result, so compositing a hazed lane colour at that alpha over
      // the hazed road is the same number.
      ctx.globalAlpha = detail * 0.88 * (1 - inGrid)
      if (ctx.globalAlpha > 0.004) {
        ctx.fillStyle = blend(fogColor, laneColor, fSurf)
        var innerX = roadHalf * 0.88
        var markF = Math.max(0.5, (rFarIn - lFarIn) * 0.012)
        var markN = Math.max(0.5, (rNearIn - lNearIn) * 0.012)
        var eLF = uAt(-innerX, zFar) * w + sx, eLN = uAt(-innerX, zNear) * w + sx
        var eRF = uAt(innerX, zFar) * w + sx, eRN = uAt(innerX, zNear) * w + sx
        quad(eLF - markF, yFar, eLF + markF, yFar, eLN + markN, yNear + 1, eLN - markN, yNear + 1)
        quad(eRF - markF, yFar, eRF + markF, yFar, eRN + markN, yNear + 1, eRN - markN, yNear + 1)
        // road.frag: `dash = step(0.45, fract(s / (stripe * 2.0)))` -- a mark
        // every 2.8 world units, on for 55% of it.
        var dashPhase = (sMid / (stripe * 2)) % 1
        if (dashPhase < 0)
          dashPhase += 1
        if (dashPhase >= 0.45) {
          var cF = uAt(0, zFar) * w + sx, cN = uAt(0, zNear) * w + sx
          quad(cF - markF, yFar, cF + markF, yFar, cN + markN, yNear + 1, cN - markN, yNear + 1)
        }
      }
      ctx.globalAlpha = 1
    }

    // ------------------------------------------------------ the sun's foot
    // A warm ellipse spilling down from the horizon under the disc, over
    // floor and road alike. The three stops are road.frag's `glowFall`, and it
    // dims as the sun sets exactly as the shader's does.
    var glowNow = glowAmount * (1 - 0.45 * nightfall)
    if (glowNow > 0.001) {
      ctx.save()
      ctx.translate(sunU * w, hy)
      ctx.scale(glowRx * w, glowRy * h)
      var foot = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      foot.addColorStop(0.0, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.55 * glowNow))
      foot.addColorStop(0.5, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.18 * glowNow))
      foot.addColorStop(1.0, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0))
      ctx.fillStyle = foot
      ctx.fillRect(-1, 0, 2, 1)
      ctx.restore()
    }
  }

  // The blended sector flags and soil at a point down the track: the same two
  // lookups road.frag makes with `sectorMix`.
  function sectorFlags(s) {
    var m = Terrain.sectorMix(s)
    var a = Terrain.FLAGS[m[0]], b = Terrain.FLAGS[m[1]], t = m[2]
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t]
  }
  function sectorSoil(s) {
    var m = Terrain.sectorMix(s)
    return Terrain.mix3(Terrain.SOIL[m[0]], Terrain.SOIL[m[1]], m[2])
  }

  // The pit's diagnostic grid, three octaves, both directions. Unchanged from
  // the round that got it right -- it is simply gated on the sector now.
  //
  // OPAQUE, PRE-BLENDED, FINEST FIRST. road.frag takes the MAX of the line
  // masks and mixes the ground toward the grid colour once, so a crossing is
  // exactly as bright as a line. Drawing translucent lines stacked alpha at
  // every crossing and the floor read as strings of beads.
  function drawGrid(ctx, w, h, zFar, zNear, yFar, yNear, fFloor, sx, amount) {
    var groundHere = sectorSoil(zFar + travel)
    var base = Qt.rgba(groundHere[0], groundHere[1], groundHere[2], 1)
    var octaves = [
      { "period": gridScale * 0.0625, "alpha": fadeIn(zFar, 4.6, 2.2) * 0.55 * gridAlpha * amount, "coarse": 16 },
      { "period": gridScale * 0.25, "alpha": fadeIn(zFar, 12.0, 4.5) * 0.72 * gridAlpha * amount, "coarse": 4 },
      { "period": gridScale, "alpha": gridAlpha * amount, "coarse": 0 }
    ]
    var sFar = zFar + travel
    var sNear = zNear + travel
    for (var o = 0; o < octaves.length; o++) {
      var period = octaves[o].period
      var alpha = octaves[o].alpha
      if (alpha <= 0.02)
        continue
      var lineTone = Qt.rgba(base.r + (gridColor.r - base.r) * alpha,
                             base.g + (gridColor.g - base.g) * alpha,
                             base.b + (gridColor.b - base.b) * alpha, 1)
      ctx.fillStyle = Qt.rgba(fogColor.r + (lineTone.r - fogColor.r) * fFloor,
                              fogColor.g + (lineTone.g - fogColor.g) * fFloor,
                              fogColor.b + (lineTone.b - fogColor.b) * fFloor, 1)
      var coarse = octaves[o].coarse

      // LONGITUDINAL. The range is solved rather than guessed: u in [0,1] means
      // x + curve z^2 in [-z aspect / focal, +z aspect / focal].
      var reach = zFar * aspect / focal
      var mid0 = -curve * zFar * zFar
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
          var gf = uAt(gx, zFar) * w + sx
          var gn = uAt(gx, zNear) * w + sx
          if ((gf < -0.05 * w && gn < -0.05 * w) || (gf > 1.05 * w && gn > 1.05 * w))
            continue
          // A HAIRLINE IS DRAWN A ROW AT A TIME, NOT AS A SLIVER OF POLYGON: a
          // polygon a pixel wide with `antialiasing: false` lands on whichever
          // pixel centres it happens to contain, which is not a thing to rely
          // on for the picture the fallback is held to.
          var yTop = Math.floor(yFar)
          var yBot = Math.ceil(yNear)
          if (yBot <= yTop) {
            ctx.fillRect(Math.round(gf), yTop, 1, 1)
          } else {
            for (var gy = yTop; gy < yBot; gy++) {
              var gt = (gy + 0.5 - yFar) / Math.max(1e-6, yNear - yFar)
              gt = gt < 0 ? 0 : (gt > 1 ? 1 : gt)
              ctx.fillRect(Math.round(gf + (gn - gf) * gt), gy, 1, 1)
            }
          }
        }
      }

      // TRANSVERSE: every grid boundary this band crosses. `sNear < sFar`, so
      // the loop runs from the near index UP to the far one; running it the
      // other way round meant the body never executed on any band, on any
      // frame, and the fallback's floor carried no transverse lines at all.
      var mLo = Math.ceil(sNear / period)
      var mHi = Math.floor(sFar / period)
      for (var m2 = mLo; m2 <= mHi && m2 - mLo < 24; m2++) {
        if (coarse > 0 && (m2 % coarse) === 0)
          continue
        var zLine = m2 * period - travel
        if (zLine <= zNear || zLine >= zFar)
          continue
        ctx.fillRect(0, vAt(zLine) * h, w, 1)
      }
    }
  }

  function fadeIn(zz, far, near) {
    var t = Math.max(0, Math.min(1, (zz - far) / (near - far)))
    return t * t * (3 - 2 * t)
  }
}
