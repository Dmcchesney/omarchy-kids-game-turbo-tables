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
  // Named `heatShimmer` rather than `shimmer` because `ui/TrackView.qml`, which
  // binds it, already has an `id: shimmer` for Turbo's exhaust -- and in QML an
  // unqualified read there would resolve to the id and not to this. That is the
  // defect `npm run check:qmlids` exists for; the shader's uniform is renamed to
  // match, because a uniform is bound by name.
  property real heatShimmer: 0
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
  // The wet sand and foam where the lake meets the land: road.frag's
  // `shoreColor`. Without it the two sample the same colour and there is no
  // lake for the reflection to be in.
  property color shoreColor: "#c98a86"

  // How far down the track to draw. Past this the haze has closed anyway.
  property real drawDistance: 190
  property real nearDistance: 2.0
  // Where road.frag's `smoothstep(52.0, 16.0, z)` has finished: past this the
  // rumble alternation has dissolved into its own average and a band's colour
  // no longer depends on which stripe it is. The same two numbers appear in
  // `detail` below, and the sample ladder uses this one to know when it is
  // allowed to stop landing on stripe boundaries.
  readonly property real detailEnd: 52.0
  // Where the ground stops being drawn as blocks: `hazeFloor` is the fraction
  // of the ground's own colour that has to survive the haze for the lattice to
  // be worth filling (0.05 is z = 47), and `coarseOut` is where the one-unit
  // rut lattice gives way to the two-unit one.
  readonly property real hazeFloor: 0.05
  readonly property real coarseOut: 30.0

  renderStrategy: Canvas.Immediate
  renderTarget: Canvas.Image
  smooth: false
  antialiasing: false

  // ------------------------------------ THE BUFFERS, AND WHY THEY ARE HERE
  //
  // THIS FUNCTION IS THE GAME'S ALLOCATOR. On a scene graph with no shader --
  // the software renderer this project's whole evidence trail is taken on, and
  // the fallback any machine without a working GL lands on -- `onPaint` runs on
  // every frame, and it built a fresh array or object for every band of the
  // road and every row of the ground: the sector mix, the flags, the soil, the
  // scrub, the shoulder, the row context, the depth ladder. Measured on the
  // Race screen at 480x270 with Qt's own `qt.qml.gc.allocatorStats` and the
  // start-up collections differenced out, disabling this one function's body
  // took garbage collections from 184.5 to 81.2 per thousand animation ticks,
  // and a bare moving TrackView from 104.7 to 10.9 -- ninety per cent of the
  // view's allocation pressure, in one function.
  //
  // Plan v3: "No per-frame allocation in anything that runs every frame -- no
  // new arrays, strings or objects in a paint or an update path." These are
  // what the paint writes into instead. Every one of them is scratch: nothing
  // outside a single `onPaint` ever reads one, and the arithmetic that fills
  // them is the same arithmetic, in the same order, as the code that used to
  // return a new array.
  property var zsBuf: []
  property var mixBuf: [0, 0, 0]
  property var flagsBuf: [0, 0, 0, 0]
  property var soilBuf: [0, 0, 0]
  property var scrubBuf: [0, 0, 0]
  property var shoulderBuf: [0, 0, 0]
  property var rowBuf: Terrain.newRowContext()
  // The dusk triple is a function of the hour alone, so it is a binding rather
  // than three multiplies per band: it is rebuilt when the lap changes and at
  // no other time.
  readonly property var duskNow: Terrain.duskMul(nightfall)

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
  // How much of a surface's own colour survives the haze at that distance. The
  // ground takes the full rate and the tarmac `surfaceFog` of it; road.frag
  // does the same two exponentials per pixel. Member functions rather than
  // locals inside `onPaint`, because the terrain pass needs them too.
  function fog(zz) {
    return Math.max(0, Math.min(1, Math.exp(-fogDensity * zz * zz * 0.0011)))
  }
  function fogSurface(zz) {
    return Math.max(0, Math.min(1,
      Math.exp(-fogDensity * surfaceFog * zz * zz * 0.0011)))
  }

  function shimmerPx(v) {
    if (heatShimmer <= 0.001)
      return 0
    var dy = v - horizon
    if (dy <= 0)
      return 0
    var band = Terrain.smooth(0.230, 0.020, dy)
    var wobble = Math.sin(v * 34.0 + clock * 2.6) * 0.55
                 + Math.sin(v * 13.0 - clock * 1.7) * 0.45
    return Math.floor(heatShimmer * band * wobble * 1.6 + 0.5)
  }

  onPaint: {
    var ctx = getContext("2d")
    var w = width
    var h = height
    if (w <= 0 || h <= 0)
      return

    ctx.reset()

    // EVERY UNIFORM READ ONCE. See the note on `drawTerrain`: `fogColor.r`
    // inside a loop is a trip through the QML property system, and this loop
    // runs it about three thousand times a repaint.
    var uCurve = curve, uFocal = focal, uAspect = aspect, uTravel = travel
    var uCamH = camHeight, uRoadHalf = roadHalf, uRumbleHalf = rumbleHalf
    var uStripe = stripe, uFog = fogDensity, uSurfaceFog = surfaceFog
    var uSectorLength = sectorLength
    var fr = fogColor.r, fg = fogColor.g, fb = fogColor.b
    var rdr = roadColor.r, rdg = roadColor.g, rdb = roadColor.b
    var rar = roadAlt.r, rag = roadAlt.g, rab = roadAlt.b
    // THE BUFFERS, READ ONCE, FOR THE REASON THE PARAGRAPH ABOVE GIVES. They
    // are QML properties, so `flagsBuf` inside the band loop would be a trip
    // through the property system a hundred times a repaint -- which is how a
    // change made to stop allocating can end up costing more than the
    // allocation did. Everything below takes its buffer as an argument.
    var mixB = mixBuf, flagsB = flagsBuf, soilB = soilBuf, scrubB = scrubBuf
    var shoulder = shoulderBuf, duskB = duskNow
    var rur = rumbleColor.r, rug = rumbleColor.g, rub = rumbleColor.b
    var rlr = rumbleAlt.r, rlg = rumbleAlt.g, rlb = rumbleAlt.b

    function screenU(x, zz) {
      return (0.5 + ((x + uCurve * zz * zz) * uFocal) / (zz * 2 * uAspect))
    }

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
    // Reused, not rebuilt: the ladder is up to four hundred entries and this
    // ran on every frame. See the buffers above.
    var zs = zsBuf
    zs.length = 0
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

    // The ground, in its own pass and on its own ladder. Everything after this
    // is drawn over it.
    drawTerrain(ctx, w, h)

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

      // The terrain and the lake are drawn in their own pass, before this
      // loop -- see `drawTerrain` below and the note on what it costs.
      var flags = sectorFlags(sMid, mixB, flagsB)

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
      var lFarOut = screenU(-edge, zFar) * w + sx
      var lFarIn = screenU(-roadHalf, zFar) * w + sx
      var lNearOut = screenU(-edge, zNear) * w + sx
      var lNearIn = screenU(-roadHalf, zNear) * w + sx
      var rFarIn = screenU(roadHalf, zFar) * w + sx
      var rFarOut = screenU(edge, zFar) * w + sx
      var rNearIn = screenU(roadHalf, zNear) * w + sx
      var rNearOut = screenU(edge, zNear) * w + sx

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
      var soilRgb = sectorSoil(sMid, mixB, soilB, duskB)
      shoulder[0] = soilRgb[0] * 0.72
      shoulder[1] = soilRgb[1] * 0.72
      shoulder[2] = soilRgb[2] * 0.72
      var zebra = Qt.rgba(rur + (rlr - rur) * soft, rug + (rlg - rug) * soft,
                          rub + (rlb - rub) * soft, 1)
      var kerbR = cHere > 0 ? bend : 0
      var kerbL = cHere < 0 ? bend : 0
      // THE ROAD HALF BURIED AT THE EDGES. road.frag's drift block, and it is
      // a function of `s` alone for exactly this reason: this renderer paints
      // one shoulder colour per band, so a drift that varied across x could not
      // be the same picture. Three world units of sand at a time, and where it
      // lands the kerb goes under it.
      if (flags[2] > 0.001) {
        var drift = Math.max(0, Math.min(1,
          (Terrain.blockNoise(0, sMid, 3.0) - 0.34) / 0.40)) * flags[2]
        if (drift > 0.001) {
          var crest = sectorScrub(sMid, mixB, scrubB, duskB)
          for (var dc = 0; dc < 3; dc++)
            shoulder[dc] += (crest[dc] - shoulder[dc]) * drift
          kerbR *= 1 - 0.70 * drift
          kerbL *= 1 - 0.70 * drift
        }
      }

      var shoulderCol = hazed(shoulder, fSurf)
      var zebraCol = blend(fogColor, zebra, fSurf)
      ctx.fillStyle = blend(shoulderCol, zebraCol, kerbL)
      quad(lFarOut, yFar, lFarIn, yFar, lNearIn, yNear + 1, lNearOut, yNear + 1)
      ctx.fillStyle = blend(shoulderCol, zebraCol, kerbR)
      quad(rFarIn, yFar, rFarOut, yFar, rNearOut, yNear + 1, rNearIn, yNear + 1)

      // THE TARMAC, IN LATERAL SLICES, because it now has a crown, two tyre
      // lines per lane and, at a corner's exit, skid marks -- all of which are
      // functions of x.
      // The road's own worn patches, sampled on the road centre line: the far
      // road-centre offset `-curve z^2` is where `x = 0` lands in world space,
      // and the terrain pass no longer computes it for us.
      var wear = Terrain.blockNoise(-curve * mid * mid, sMid, Terrain.COARSE * 3.0)
      var cAhead = Terrain.curveNormAt(sMid + 7.0)
      var exiting = Math.max(0, Math.min(1, (Math.abs(cHere) - Math.abs(cAhead)) * 7.0))
                    * Terrain.smooth(0.30, 0.62, Math.abs(cHere))
      var side = cHere > 0 ? -1 : 1
      var drift = 0.34 + 0.34 * Math.max(0, Math.min(1, (Math.abs(cHere) - 0.3) / 0.7))
      var gp = ((sMid % (sectorLength * 12)) + sectorLength * 12) % (sectorLength * 12)
      var inGrid = (gp >= 2 && gp <= 5) ? detail : 0

      // EIGHT SLICES, AND EIGHT IS NOT A ROUND NUMBER PICKED FOR SPEED. The
      // start grid's chequer is `floor((x + roadHalf) / (roadHalf * 0.25))`,
      // which is exactly eight columns across the road, so eight slices land on
      // its own boundaries and the chequer comes out square rather than
      // approximated. The tyre lines at 0.30 and 0.70 of `roadHalf` fall one
      // per slice at this pitch, and `detail` has dissolved them before the
      // slices are wider than they are.
      var slices2 = 8
      var baseR = rdr + (rar - rdr) * soft * 0.34
      var baseG = rdg + (rag - rdg) * soft * 0.34
      var baseB = rdb + (rab - rdb) * soft * 0.34
      for (var t2 = 0; t2 < slices2; t2++) {
        var xa = -roadHalf + (2 * roadHalf) * t2 / slices2
        var xb = -roadHalf + (2 * roadHalf) * (t2 + 1) / slices2
        var xc = (xa + xb) * 0.5
        var axc = Math.abs(xc)
        var rr = baseR, rg = baseG, rb = baseB
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
          var gr = chequer ? rlr : rdr * 0.55
          var gg = chequer ? rlg : rdg * 0.55
          var gb = chequer ? rlb : rdb * 0.55
          rr += (gr - rr) * inGrid * 0.88
          rg += (gg - rg) * inGrid * 0.88
          rb += (gb - rb) * inGrid * 0.88
        }
        ctx.fillStyle = Qt.rgba(fr + (rr - fr) * fSurf, fg + (rg - fg) * fSurf,
                                fb + (rb - fb) * fSurf, 1)
        quad(screenU(xa, zFar) * w + sx, yFar, screenU(xb, zFar) * w + sx, yFar,
             screenU(xb, zNear) * w + sx, yNear + 1, screenU(xa, zNear) * w + sx, yNear + 1)
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
        var eLF = screenU(-innerX, zFar) * w + sx, eLN = screenU(-innerX, zNear) * w + sx
        var eRF = screenU(innerX, zFar) * w + sx, eRN = screenU(innerX, zNear) * w + sx
        quad(eLF - markF, yFar, eLF + markF, yFar, eLN + markN, yNear + 1, eLN - markN, yNear + 1)
        quad(eRF - markF, yFar, eRF + markF, yFar, eRN + markN, yNear + 1, eRN - markN, yNear + 1)
        // road.frag: `dash = step(0.45, fract(s / (stripe * 2.0)))` -- a mark
        // every 2.8 world units, on for 55% of it.
        var dashPhase = (sMid / (stripe * 2)) % 1
        if (dashPhase < 0)
          dashPhase += 1
        if (dashPhase >= 0.45) {
          var cF = screenU(0, zFar) * w + sx, cN = screenU(0, zNear) * w + sx
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

  // ============================================================ THE TERRAIN
  //
  // ONE PASS, ITS OWN LADDER, AND THE LADDER IS THE WHOLE OF WHAT IT COSTS.
  //
  // The ground is blocks, and a block is flat, so drawing it is a matter of how
  // many blocks land on the screen. The first cut of this drew a row of them for
  // every ROAD band -- and the road's bands are cut on half-stripe boundaries so
  // the zebra never crawls, which near the camera is a band every third of a
  // world unit. That is five times finer in depth than a block is deep, so four
  // rows in five were redrawing the same blocks. 5,923 cells a repaint, 15.7 ms
  // of JavaScript and 2.4 ms of fill, and the Race screen -- which repaints this
  // every frame -- fell from 62.8 fps to 23.3 at 1920x1080 on this Mac's
  // software scene graph.
  //
  // The ground has its own ladder now, and two rules set it:
  //
  //   * a row is at least `rowPx` plane pixels tall, and never shallower in
  //     world units than the lattice it is drawing;
  //   * a block is at least `cellPx` plane pixels wide, which chooses between
  //     the half-unit, one-unit and two-unit lattices by distance rather than
  //     by a depth guessed in advance.
  //
  // and one more that is not about cost: past `hazeOut` the haze has taken 94%
  // of the ground, so the whole of the rest is one fill of what the blocks
  // average to -- which is what the shader converges on there anyway.
  //
  // WHAT IT GIVES UP, stated rather than left to be found. At twenty world
  // units a two-unit block is 1.8 plane pixels deep, so a four-pixel row spans
  // two or three blocks in `s` and paints them as one. The shader dithers there
  // and this does not. The piece T evidence measures exactly that, against a CPU
  // reference of road.frag at the same camera.
  readonly property real rowPx: 6.0
  readonly property real cellPx: 10.0
  readonly property real hazeOut: 42.0

  // EVERY UNIFORM IS READ ONCE, INTO A LOCAL, AND THAT IS WORTH 13 MILLISECONDS.
  //
  // `fogColor`, `curve`, `focal` and the rest are QML properties, and every
  // `fogColor.r` inside a loop is a trip through the property system. The first
  // cut of this pass read six of them per BLOCK and called `uAt`, which reads
  // three more, four times per run: with eleven hundred blocks that is about
  // twenty thousand property reads a repaint, and measured it cost 16.6 ms of
  // the 22 ms this pass was taking. Hoisted, the same eleven hundred blocks
  // cost about three. Nothing about the picture changed.
  function drawTerrain(ctx, w, h) {
    var uCurve = curve, uFocal = focal, uAspect = aspect, uTravel = travel
    var uCamH = camHeight, uRoadHalf = roadHalf, uRumbleHalf = rumbleHalf
    var uSunU = sunU, uClock = clock, uHorizon = horizon
    var fr = fogColor.r, fg = fogColor.g, fb = fogColor.b
    var wr = waterColor.r, wg = waterColor.g, wb = waterColor.b
    var lr0 = waterLit.r, lg0 = waterLit.g, lb0 = waterLit.b
    var uFog = fogDensity
    // THE HOUR, HOISTED. `Terrain.duskMul` is the same triple road.frag applies
    // at the same point in the same order; read once per repaint rather than
    // once per block, for the reason the whole of this function's preamble
    // exists.
    var dusk = duskNow
    var dmR = dusk[0], dmG = dusk[1], dmB = dusk[2]
    var scratch = [0, 0, 0]
    var rowCtx = rowBuf
    var z = nearDistance
    var guard = 0
    // A COLOUR IS ALLOCATED ONCE PER TONE, NOT ONCE PER BLOCK.
    //
    // `Qt.rgba` builds a colour value, and the ground quantises to 8 bits a
    // channel, so a row of sixty blocks over one sector's two-tone palette
    // produces a few dozen distinct tones and hundreds of allocations. Keyed by
    // the packed 24-bit tone, the whole pass allocates once per tone it actually
    // uses -- and plan v3's rule is "no per-frame allocation in anything that
    // runs every frame".
    var tones = {}
    function toneFor(key, rr, gg, bb) {
      var c = tones[key]
      if (c === undefined) {
        c = Qt.rgba(rr / 255, gg / 255, bb / 255, 1)
        tones[key] = c
      }
      return c
    }

    function screenU(x, zz) {
      return (0.5 + ((x + uCurve * zz * zz) * uFocal) / (zz * 2 * uAspect)) * w
    }
    function screenY(zz) {
      return (uHorizon + (uFocal * uCamH) / (2 * zz)) * h
    }

    while (z < hazeOut && ++guard < 200) {
      // The lattice: the coarsest that is still finer than the eye at this
      // depth, so a block is never under `cellPx` plane pixels across.
      var want = (2 * z * uAspect * cellPx) / Math.max(1e-6, uFocal * w)
      var gstep = want <= Terrain.FINE ? Terrain.FINE
                  : (want <= Terrain.RUT ? Terrain.RUT : Terrain.COARSE)
      var dz = Math.max(gstep, (z * z * rowPx * 2) / Math.max(1, h * uFocal * uCamH))
      var zFar = Math.min(hazeOut, z + dz)
      var zNear = z
      var yFar = screenY(zFar)
      var yNear = screenY(zNear)
      z = zFar
      if (yNear - yFar < 0.5)
        continue

      var mid = (zFar + zNear) * 0.5
      var sMid = mid + uTravel
      var fFloor = Math.max(0, Math.min(1, Math.exp(-uFog * mid * mid * 0.0011)))
      var sx = -shimmerPx(yNear / h)
      var row = Terrain.rowContextInto(sMid, mid, rowCtx)

      var reach = mid * uAspect / uFocal
      var mid0 = -uCurve * mid * mid
      var cLo = Math.floor((mid0 - reach) / gstep)
      var cHi = Math.ceil((mid0 + reach) / gstep)
      if (cHi - cLo > 300) {
        cLo = Math.floor(mid0 / gstep) - 150
        cHi = cLo + 300
      }

      var runStart = cLo
      var runKey = -1
      var runColor = null
      var rowH = Math.max(1, yNear - yFar + 1)
      for (var c = cLo; c <= cHi; c++) {
        Terrain.rowGround(row, c * gstep + gstep * 0.5, scratch)
        var gr = scratch[0] * dmR, gg0 = scratch[1] * dmG, gb0 = scratch[2] * dmB
        var rr = Math.round((fr + (gr - fr) * fFloor) * 255)
        var gg = Math.round((fg + (gg0 - fg) * fFloor) * 255)
        var bb = Math.round((fb + (gb0 - fb) * fFloor) * 255)
        var key = (rr << 16) | (gg << 8) | bb
        if (runColor === null) {
          runStart = c
          runKey = key
          runColor = toneFor(key, rr, gg, bb)
        } else if (key !== runKey || c === cHi) {
          var endAt = (key !== runKey) ? c : c + 1
          ctx.fillStyle = runColor
          var aF = screenU(runStart * gstep, zFar) + sx
          var bF = screenU(endAt * gstep, zFar) + sx
          var aN = screenU(runStart * gstep, zNear) + sx
          var bN = screenU(endAt * gstep, zNear) + sx
          if (Math.abs(aN - aF) < 1 && Math.abs(bN - bF) < 1) {
            var rx = Math.min(aF, aN)
            ctx.fillRect(rx, yFar, Math.max(1, Math.max(bF, bN) - rx), rowH)
          } else {
            ctx.beginPath()
            ctx.moveTo(aF, yFar)
            ctx.lineTo(bF, yFar)
            ctx.lineTo(bN, yNear + 1)
            ctx.lineTo(aN, yNear + 1)
            ctx.closePath()
            ctx.fill()
          }
          runStart = c
          runKey = key
          runColor = toneFor(key, rr, gg, bb)
        }
      }

      // --------------------------------------------------------- the lake
      // Water on the right of the road, with the sun's column reflected in it
      // as rungs that stretch toward the eye. road.frag's `water` block. The
      // column is in SCREEN u, because that is what a reflection is: the sun's
      // image is under the disc, not at a fixed place on the lake.
      if (row.water > 0.001) {
        // 1.15 and not 2.6: road.frag carries the argument -- at 2.6 the bank
        // was off the right of the frame until z = 3 and did not cross the
        // sun's own column until z = 7, so the design's reflection had no
        // water to be in anywhere the haze had not already taken it.
        var shore = uRoadHalf + uRumbleHalf + 1.15
        // THE SHORE, FIRST AND UNDER THE WATER. road.frag mixes a pale band
        // into the floor before it lays the lake over it; four slices across
        // the same unit and a half, each weighted by the same quadratic, is
        // what a renderer that fills quads can do with that. Drawn before the
        // water so the lake's own edge lands on top of it, exactly as the
        // shader's two mixes compose.
        for (var e = 0; e < 4; e++) {
          var ex0 = shore - 0.46 + e * 0.39
          var ex1 = ex0 + 0.39
          var em = 1 - Math.abs((ex0 + ex1) * 0.5 - shore - 0.32) / 0.78
          em = em < 0 ? 0 : em * em * row.water
          if (em <= 0.02)
            continue
          // The ground the band is mixed INTO, at the middle of this slice, on
          // the same lattice and with the same dusk the rest of the row took.
          Terrain.rowGround(row, (ex0 + ex1) * 0.5, scratch)
          var sr = scratch[0] * dmR, sg = scratch[1] * dmG, sb = scratch[2] * dmB
          ctx.fillStyle = Qt.rgba(
            fr + ((sr + (shoreColor.r - sr) * em) - fr) * fFloor,
            fg + ((sg + (shoreColor.g - sg) * em) - fg) * fFloor,
            fb + ((sb + (shoreColor.b - sb) * em) - fb) * fFloor, 1)
          ctx.beginPath()
          ctx.moveTo(screenU(ex0, zFar) + sx, yFar)
          ctx.lineTo(screenU(ex1, zFar) + sx, yFar)
          ctx.lineTo(screenU(ex1, zNear) + sx, yNear + 1)
          ctx.lineTo(screenU(ex0, zNear) + sx, yNear + 1)
          ctx.closePath()
          ctx.fill()
        }
        var ripple = Math.sin(sMid * 2.7 - uClock * 1.9) * 0.5
                     + Math.sin(sMid * 6.1 + uClock * 1.1) * 0.5
        var rungs = ripple >= 0 ? 1 : 0
        var lakeR = wr * (rungs ? 1.18 : 1)
        var lakeG = wg * (rungs ? 1.18 : 1)
        var lakeB = wb * (rungs ? 1.18 : 1)
        var xShoreF = screenU(shore + 1.1, zFar) + sx
        var xShoreN = screenU(shore + 1.1, zNear) + sx
        var xStart = Math.max(0, Math.min(xShoreF, xShoreN))
        if (xStart < w) {
          for (var q = 0; q < 8; q++) {
            var px0 = xStart + (w - xStart) * q / 8
            var px1 = xStart + (w - xStart) * (q + 1) / 8
            var uc = ((px0 + px1) * 0.5 - sx) / w
            // road.frag's wedge: narrow at the horizon, wide at the eye, with
            // the rungs losing contrast with distance. A reflection converges
            // on its source; a constant-width stripe is a bar of light standing
            // on the water.
            var nearK = Math.max(0, Math.min(1, (30 - mid) / 26))
            var colm = Math.max(0, 1 - Math.abs(uc - uSunU) / (0.022 + 0.278 * nearK))
            colm *= colm
            var ladder = colm * (0.45 + 0.55 * rungs) * (0.55 + 0.45 * nearK)
            ctx.fillStyle = Qt.rgba(
              fr + ((lakeR + (lr0 - lakeR) * ladder) - fr) * fFloor,
              fg + ((lakeG + (lg0 - lakeG) * ladder) - fg) * fFloor,
              fb + ((lakeB + (lb0 - lakeB) * ladder) - fb) * fFloor, 1)
            ctx.beginPath()
            ctx.moveTo(Math.max(px0, xShoreF), yFar)
            ctx.lineTo(Math.max(px1, xShoreF), yFar)
            ctx.lineTo(Math.max(px1, xShoreN), yNear + 1)
            ctx.lineTo(Math.max(px0, xShoreN), yNear + 1)
            ctx.closePath()
            ctx.fill()
          }
        }
      }
    }
  }

  // The blended sector flags and soil at a point down the track: the same two
  // lookups road.frag makes with `sectorMix`.
  //
  // ONE BUFFER EACH, AND THE CALLER MUST NOT HOLD ON TO ONE. Every one of
  // these ran once per band per frame and returned a new array; see the note
  // on the buffers above for what that was costing. `flagsBuf`, `soilBuf` and
  // `scrubBuf` are separate arrays precisely because the road loop holds all
  // three at once; `mixBuf` is shared because no caller keeps it past the line
  // that reads it.
  function sectorFlags(s, mix, out) {
    var m = Terrain.sectorMixInto(s, mix)
    var a = Terrain.FLAGS[m[0]], b = Terrain.FLAGS[m[1]], t = m[2]
    out[0] = a[0] + (b[0] - a[0]) * t
    out[1] = a[1] + (b[1] - a[1]) * t
    out[2] = a[2] + (b[2] - a[2]) * t
    out[3] = a[3] + (b[3] - a[3]) * t
    return out
  }
  // The grid's own backing tone. Dusked with the same triple the terrain takes,
  // so the pit's floor under the neon dims with everything else rather than
  // staying at noon under a lap-12 sky.
  function sectorSoil(s, mix, out, d) {
    var m = Terrain.sectorMixInto(s, mix)
    Terrain.mix3Into(Terrain.SOIL[m[0]], Terrain.SOIL[m[1]], m[2], out)
    out[0] *= d[0]
    out[1] *= d[1]
    out[2] *= d[2]
    return out
  }

  // The sector's crest tone, dusked: what the dunes' sand drifts over the
  // shoulder are made of. road.frag has `scrub` as a local at that point;
  // this renderer has to go and get it.
  function sectorScrub(s, mix, out, d) {
    var m = Terrain.sectorMixInto(s, mix)
    Terrain.mix3Into(Terrain.SCRUB[m[0]], Terrain.SCRUB[m[1]], m[2], out)
    out[0] *= d[0]
    out[1] *= d[1]
    out[2] *= d[2]
    return out
  }

  // The pit's diagnostic grid, three octaves, both directions. Unchanged from
  // the round that got it right -- it is simply gated on the sector now.
  //
  // OPAQUE, PRE-BLENDED, FINEST FIRST. road.frag takes the MAX of the line
  // masks and mixes the ground toward the grid colour once, so a crossing is
  // exactly as bright as a line. Drawing translucent lines stacked alpha at
  // every crossing and the floor read as strings of beads.
  function drawGrid(ctx, w, h, zFar, zNear, yFar, yNear, fFloor, sx, amount) {
    var groundHere = sectorSoil(zFar + travel, mixBuf, soilBuf, duskNow)
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
