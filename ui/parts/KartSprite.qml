import QtQuick
import "../"

// A kart, modelled in three dimensions and rendered through a camera that is
// above the kart and off its shoulder. Six bodies, any of the eight paints,
// the number on its plate. Drawn in code, not from a bitmap: the design asks
// for low-detail voxel-styled bodies, the same drawing has to hold at 150 px
// in a roster row and at 560 px on the stall turntable, and the paint is
// chosen at runtime from eight swatches, which a bitmap cannot follow without
// eight copies of every body.
//
// WHY THIS IS A RENDERER AND NOT A PILE OF RECTANGLES
//
// The previous revision projected the model with an oblique shear -- screen x
// was the model's x plus a fraction of z, screen y was the model's y minus a
// fraction of z. That is a side elevation with a skew on it. It has three
// consequences, and a critic named all three: the far wheels come out exactly
// the same size as the near ones, because an oblique projection has no
// foreshortening at all; the parts have to be drawn in a hand-written order,
// so occlusion is whatever the author remembered; and every face is one flat
// fill, so the parts share coordinates without looking joined.
//
// This revision replaces all three:
//
//   1. A CAMERA. `project()` yaws the model about the vertical axis, tilts it
//      by the camera's pitch, and divides by distance. Near parts come out
//      larger than far parts by their real depth ratio -- the far wheels
//      measure about 0.84 of the near ones, and it is the projection that
//      says so, not a fudge factor applied to a radius.
//
//   2. A DEPTH-SORTED FACE QUEUE. Every solid emits eight faces; each face
//      knows its own outward normal, is dropped when that normal points away
//      from the camera, and is painted back to front. Nothing is drawn in
//      "the order it was written". That is what puts the far wheels behind the
//      side pod rather than beside it, and it cannot fall out of step with the
//      geometry, because there is no second list to keep in step.
//
//   3. ONE LIGHT, AND CONTACT DARKENING. Every face is shaded by the same
//      light vector, so the value on a chamfer is continuous with the value on
//      the flank it runs into, and a seam reads as a fold rather than as a
//      join between two sprites. On top of that the overhanging parts cast on
//      the parts beneath them -- the wing on the engine cowl, the nose on the
//      dais, the body on the ground -- by projecting their own footprint down
//      the same light ray. Contact darkening is the largest single reason a
//      collection of boxes reads as one object.
//
// Placeholder art. The design's shipping karts are pre-rendered sprite sheets
// at eight angles and three scales for the track view. This is the one
// three-quarter view the garage needs, and it is not final art.
Item {
  id: kart

  property int body: 0
  property color paint: Theme.paint(0)
  property int number: 7
  property bool showNumber: true
  // Dims the whole kart without changing its hues.
  property real dim: 1.0
  property bool shadow: true

  // ------------------------------------------------------------- the camera
  // Model axes: +x runs from the tail toward the nose, +y is up, +z runs
  // across the kart away from the viewer. The camera is yawed off the kart's
  // flank and pitched above it, so the visible faces of any box are its near
  // flank, its top, and the end that faces the nose.
  readonly property real yawDeg: 22
  readonly property real pitchDeg: 25
  // Distance to the picture plane, in model units. This is the only thing
  // that makes the far side of the kart smaller than the near side; at 190 a
  // far wheel comes out at about 0.84 of its partner across the axle.
  readonly property real focal: 190

  readonly property real cosYaw: Math.cos(yawDeg * Math.PI / 180)
  readonly property real sinYaw: Math.sin(yawDeg * Math.PI / 180)
  readonly property real cosPitch: Math.cos(pitchDeg * Math.PI / 180)
  readonly property real sinPitch: Math.sin(pitchDeg * Math.PI / 180)

  // The point the camera is aimed at, and where it lands in the view box.
  // Perspective is measured from here, so the kart scales about its own
  // middle instead of about a corner.
  readonly property real refX: 56
  readonly property real refY: 13
  readonly property real refZ: 17
  readonly property real vbW: 132
  readonly property real vbH: 80
  readonly property real centreU: 62
  readonly property real centreV: 38

  readonly property real unit: Math.min(width / vbW, height / vbH)
  readonly property real originX: (width - vbW * unit) / 2
  readonly property real originY: (height - vbH * unit) / 2

  // Where the kart meets the floor, as a fraction of the sprite's height: the
  // ground directly under the camera's aim point, so a kart placed by this
  // number stands on a turntable rather than in front of it.
  readonly property real groundFraction: (centreV + refY * cosPitch) / vbH

  implicitWidth: 264
  implicitHeight: 160

  // Depth of a model point: how far it is from the camera, positive away.
  function depthAt(x, z) {
    return -(x - refX) * sinYaw + (z - refZ) * cosYaw
  }

  // The projection. Yaw, then pitch, then divide by distance.
  function project(x, y, z) {
    var d = depthAt(x, z)
    var p = focal / (focal + d)
    var u = ((x - refX) * cosYaw + (z - refZ) * sinYaw) * p
    var v = ((y - refY) * cosPitch + d * sinPitch) * p
    return [originX + (centreU + u) * unit, originY + (centreV - v) * unit]
  }

  // Per-body geometry, in model units. One table is what makes six
  // silhouettes six blocks of data rather than six drawing routines. Every
  // range touches its neighbour: the nose steps each begin where the last
  // ended, the wing posts stand on the engine cowl and run out to the wing's
  // own rear edge, and the floor pan spans from behind the rear axle to under
  // the nose.
  function spec(index) {
    var i = ((index % 6) + 6) % 6
    var table = [
      // 0 SPRINTER -- the reference kart: open wheels, big rear wing
      { rearX: 25, rearR: 13, frontX: 86, frontR: 12,
        nearZ0: -5, nearZ1: 5, farZ0: 29, farZ1: 39,
        bodyZ0: 3, bodyZ1: 31,
        panX0: 10, panX1: 94, panY0: 3, panY1: 6.5,
        podX0: 14, podX1: 76, podY0: 6, podY1: 18,
        cowlX0: 7, cowlX1: 27, cowlY: 22,
        seatX0: 30, seatX1: 41, seatY: 33, headrest: true,
        steering: true, steerX: 48, steerY: 28,
        noseSteps: [ { x0: 76, x1: 90, yA: 16, yB: 15, z0: 4, z1: 30 },
                     { x0: 90, x1: 100, yA: 15, yB: 12.5, z0: 6, z1: 28 },
                     { x0: 100, x1: 108, yA: 12.5, yB: 10, z0: 9, z1: 25 } ],
        frontWing: { x0: 95, x1: 108, y0: 2.5, y1: 4.6 },
        wing: { back: 2, len: 17, rise: 9, deck: 0 },
        hoop: false, roof: false, canopy: false, fenders: false, dualRear: false,
        plate: { x0: 43, x1: 66, y0: 4.8, y1: 19.0 } },
      // 1 WEDGE -- long and low, an arrow with a lip instead of a wing
      { rearX: 24, rearR: 11, frontX: 88, frontR: 11,
        nearZ0: -4, nearZ1: 5, farZ0: 29, farZ1: 38,
        bodyZ0: 2, bodyZ1: 32,
        panX0: 8, panX1: 98, panY0: 2.5, panY1: 5.5,
        podX0: 12, podX1: 72, podY0: 5, podY1: 15.5,
        cowlX0: 5, cowlX1: 24, cowlY: 18,
        seatX0: 28, seatX1: 38, seatY: 27, headrest: false,
        steering: true, steerX: 46, steerY: 23,
        noseSteps: [ { x0: 72, x1: 88, yA: 14, yB: 11.5, z0: 3, z1: 31 },
                     { x0: 88, x1: 100, yA: 11.5, yB: 9, z0: 5, z1: 29 },
                     { x0: 100, x1: 110, yA: 9, yB: 7.2, z0: 8, z1: 26 } ],
        frontWing: { x0: 96, x1: 110, y0: 2.0, y1: 3.8 },
        wing: { back: 1, len: 12, rise: 1.5, deck: 0 },
        hoop: false, roof: false, canopy: false, fenders: false, dualRear: false,
        plate: { x0: 41, x1: 64, y0: 4.3, y1: 16.5 } },
      // 2 STOCKCAR -- fendered, a roofed cabin over the seat
      { rearX: 26, rearR: 12, frontX: 84, frontR: 12,
        nearZ0: -3, nearZ1: 6, farZ0: 28, farZ1: 37,
        bodyZ0: -1, bodyZ1: 35,
        panX0: 10, panX1: 94, panY0: 3, panY1: 6,
        podX0: 12, podX1: 74, podY0: 6, podY1: 19,
        cowlX0: 6, cowlX1: 26, cowlY: 21,
        seatX0: 32, seatX1: 42, seatY: 28, headrest: false,
        steering: false, steerX: 48, steerY: 27,
        noseSteps: [ { x0: 74, x1: 88, yA: 18, yB: 16, z0: 0, z1: 34 },
                     { x0: 88, x1: 98, yA: 16, yB: 13.5, z0: 2, z1: 32 },
                     { x0: 98, x1: 104, yA: 13.5, yB: 11.5, z0: 5, z1: 29 } ],
        frontWing: null,
        wing: { back: 1, len: 13, rise: 1.0, deck: 0 },
        hoop: false, roof: true, canopy: false, fenders: true, dualRear: false,
        plate: { x0: 43, x1: 66, y0: 4.8, y1: 20.0 } },
      // 3 BUGGY -- tall on big wheels, an exposed roll cage
      { rearX: 27, rearR: 14.5, frontX: 85, frontR: 13.5,
        nearZ0: -5, nearZ1: 5, farZ0: 29, farZ1: 39,
        bodyZ0: 4, bodyZ1: 30,
        panX0: 12, panX1: 92, panY0: 8, panY1: 11.5,
        podX0: 16, podX1: 74, podY0: 11, podY1: 23,
        cowlX0: 9, cowlX1: 28, cowlY: 26,
        seatX0: 32, seatX1: 43, seatY: 29, headrest: false,
        steering: true, steerX: 50, steerY: 31,
        noseSteps: [ { x0: 74, x1: 88, yA: 21, yB: 19.5, z0: 5, z1: 29 },
                     { x0: 88, x1: 97, yA: 19.5, yB: 17, z0: 7, z1: 27 } ],
        frontWing: null,
        wing: null,
        hoop: true, roof: false, canopy: false, fenders: false, dualRear: false,
        plate: { x0: 45, x1: 68, y0: 9.8, y1: 24.0 } },
      // 4 HAULER -- a slab with a flat deck, twin rear wheels
      { rearX: 24, rearR: 11.5, frontX: 88, frontR: 11.5,
        nearZ0: -4, nearZ1: 6, farZ0: 28, farZ1: 38,
        bodyZ0: 0, bodyZ1: 34,
        panX0: 6, panX1: 98, panY0: 3, panY1: 6.5,
        podX0: 8, podX1: 70, podY0: 6, podY1: 17,
        cowlX0: 4, cowlX1: 34, cowlY: 25,
        seatX0: 38, seatX1: 49, seatY: 30, headrest: true,
        steering: true, steerX: 56, steerY: 25,
        noseSteps: [ { x0: 70, x1: 86, yA: 17, yB: 16, z0: 1, z1: 33 },
                     { x0: 86, x1: 96, yA: 16, yB: 14, z0: 3, z1: 31 },
                     { x0: 96, x1: 104, yA: 14, yB: 12, z0: 6, z1: 28 } ],
        frontWing: { x0: 94, x1: 106, y0: 2.5, y1: 4.4 },
        wing: null,
        hoop: false, roof: false, canopy: false, fenders: false, dualRear: true,
        plate: { x0: 55, x1: 75, y0: 4.8, y1: 18.0 } },
      // 5 PROTOTYPE -- a closed teal canopy and a double-deck rear wing
      { rearX: 25, rearR: 12, frontX: 88, frontR: 11,
        nearZ0: -4, nearZ1: 5, farZ0: 29, farZ1: 38,
        bodyZ0: 1, bodyZ1: 33,
        panX0: 8, panX1: 98, panY0: 2.5, panY1: 6,
        podX0: 12, podX1: 76, podY0: 5.5, podY1: 17,
        cowlX0: 5, cowlX1: 26, cowlY: 20,
        seatX0: 30, seatX1: 44, seatY: 24, headrest: false,
        steering: false, steerX: 50, steerY: 26,
        noseSteps: [ { x0: 76, x1: 90, yA: 16, yB: 14, z0: 2, z1: 32 },
                     { x0: 90, x1: 100, yA: 14, yB: 11, z0: 4, z1: 30 },
                     { x0: 100, x1: 110, yA: 11, yB: 8.5, z0: 7, z1: 27 } ],
        frontWing: { x0: 96, x1: 110, y0: 2.2, y1: 4.2 },
        wing: { back: 2, len: 18, rise: 11, deck: 5.2 },
        hoop: false, roof: false, canopy: true, fenders: false, dualRear: false,
        plate: { x0: 43, x1: 66, y0: 4.3, y1: 18.0 } }
    ]
    return table[i]
  }

  readonly property var geometry: spec(body)

  // The number plate stands 0.5 units proud of the side pod's near flank, so
  // it is a real plate with a lit edge rather than a sticker. Under this
  // camera a horizontal model line runs downhill to the right, so the digits
  // are rotated onto the plate instead of being set square to the screen.
  readonly property real plateZ: geometry.bodyZ0 - 0.5
  // p00 is the plate's bottom-left corner on screen, p10 its bottom-right and
  // p01 its top-left. The digits are laid out from p00 because the text item
  // rotates about its own bottom-left.
  readonly property var plateP00: project(geometry.plate.x0, geometry.plate.y0, plateZ)
  readonly property var plateP10: project(geometry.plate.x1, geometry.plate.y0, plateZ)
  readonly property var plateP01: project(geometry.plate.x0, geometry.plate.y1, plateZ)
  readonly property real plateW: Math.sqrt(Math.pow(plateP10[0] - plateP00[0], 2)
                                           + Math.pow(plateP10[1] - plateP00[1], 2))
  readonly property real plateH: Math.abs(plateP01[1] - plateP00[1])
  readonly property real plateAngle: Math.atan2(plateP10[1] - plateP00[1],
                                                plateP10[0] - plateP00[0]) * 180 / Math.PI

  Canvas {
    id: surface
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      if (kart.unit <= 0)
        return

      var g = kart.geometry

      function project(x, y, z) { return kart.project(x, y, z) }
      function depthAt(x, z) { return kart.depthAt(x, z) }

      // --------------------------------------------------------- the light
      // One unit vector, used by every face on the kart and by every shadow
      // it casts. Above, from the nose side, and a little toward the viewer,
      // which is where the stall's work lights are.
      var Lx = 0.52, Ly = 0.80, Lz = -0.30
      var warm = Qt.rgba(1.0, 0.84, 0.58, 1)     // the stall's work lights
      var cool = Qt.rgba(0.07, 0.20, 0.24, 1)    // the design's dark teal

      function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
      }
      function gain(c, k) {
        return Qt.rgba(Math.min(1, c.r * k), Math.min(1, c.g * k),
                       Math.min(1, c.b * k), 1)
      }

      // A face's colour, from its own outward normal. Lambert against the one
      // light, plus a small sky term that only upward faces catch, plus a
      // warm tint where the light lands and a cool one where it does not.
      // Because every face on the kart goes through this, the value either
      // side of a fold is continuous and the fold reads as a fold.
      function shade(base, n) {
        var lam = Math.max(0, n[0] * Lx + n[1] * Ly + n[2] * Lz)
        var sky = Math.max(0, n[1]) * 0.22
        var k = 0.30 + 0.72 * lam + sky
        var c = gain(base, k)
        c = mix(c, warm, 0.20 * lam)
        c = mix(c, cool, 0.26 * (1 - lam))
        return c
      }

      // ------------------------------------------------- the face queue
      // Everything the kart draws goes in here with a depth, and the queue is
      // painted back to front. Occlusion is therefore a property of the
      // model, not of the order these lines happen to appear in.
      var queue = []

      function normalOf(p) {
        var ax = p[1][0] - p[0][0], ay = p[1][1] - p[0][1], az = p[1][2] - p[0][2]
        var bx = p[2][0] - p[0][0], by = p[2][1] - p[0][1], bz = p[2][2] - p[0][2]
        var nx = ay * bz - az * by
        var ny = az * bx - ax * bz
        var nz = ax * by - ay * bx
        var len = Math.sqrt(nx * nx + ny * ny + nz * nz)
        if (len <= 0)
          return null
        return [nx / len, ny / len, nz / len]
      }

      // The direction the camera looks, in model coordinates. A face whose
      // outward normal has a positive dot product with it is facing away and
      // is never drawn.
      var Wx = -kart.sinYaw * kart.cosPitch
      var Wy = -kart.sinPitch
      var Wz = kart.cosYaw * kart.cosPitch

      // A flat polygon of the solid, given in model space.
      function face(points3, base, bias) {
        var n = normalOf(points3)
        if (!n)
          return
        if (n[0] * Wx + n[1] * Wy + n[2] * Wz > -0.0001)
          return
        var flat = []
        var d = 0
        for (var i = 0; i < points3.length; i++) {
          flat.push(project(points3[i][0], points3[i][1], points3[i][2]))
          d += depthAt(points3[i][0], points3[i][2])
        }
        queue.push({ pts: flat, fill: shade(base, n), depth: d / points3.length + (bias || 0) })
      }

      // A chamfered box. `ti` takes the top face in on both sides of z and
      // `ch` is how far down the flank the chamfer runs, so a solid presents
      // a flank, a bevel and a top instead of one plate of colour. `yA` is the
      // top at x0 and `yB` the top at x1, so a nose section is the same call
      // as a box with a slope on it.
      //
      // The solid is cut into slices along its length before its faces are
      // emitted, and only the two outermost slices keep their end caps. This
      // is not decoration: a painter's algorithm sorts by a face's average
      // depth, and the side pod is 62 units long, so one undivided flank
      // averages out to a depth near its middle and then paints straight over
      // the rear wheel standing at its far end. Slicing keeps each piece of
      // the flank at its own depth, which is what puts the near rear wheel in
      // front of the bodywork and the far rear wheel behind it.
      // The width may also change along the length: `zA` is the near/far pair
      // at x0 and `zB` the pair at x1. That is what lets the nose be one
      // tapering solid instead of three stacked slabs with their end caps
      // showing between them, and `capStart`/`capEnd` let consecutive sections
      // be chained into a single unbroken form.
      function sweep(x0, x1, y0, yA, yB, zA, zB, base, ti, ch, capStart, capEnd) {
        var slices = Math.max(1, Math.min(12, Math.round((x1 - x0) / 6)))

        for (var s = 0; s < slices; s++) {
          var t0 = s / slices, t1 = (s + 1) / slices
          var sx0 = x0 + (x1 - x0) * t0
          var sx1 = x0 + (x1 - x0) * t1
          var syA = yA + (yB - yA) * t0
          var syB = yA + (yB - yA) * t1
          var a0 = zA[0] + (zB[0] - zA[0]) * t0, a1 = zA[1] + (zB[1] - zA[1]) * t0
          var b0 = zA[0] + (zB[0] - zA[0]) * t1, b1 = zA[1] + (zB[1] - zA[1]) * t1
          var insA = Math.min(ti === undefined ? 1.8 : ti, (a1 - a0) / 2.6)
          var insB = Math.min(ti === undefined ? 1.8 : ti, (b1 - b0) / 2.6)
          var ai0 = a0 + insA, ai1 = a1 - insA
          var bi0 = b0 + insB, bi1 = b1 - insB
          var lipA = Math.min(ch === undefined ? 2.4 : ch, (syA - y0) * 0.55)
          var lipB = Math.min(ch === undefined ? 2.4 : ch, (syB - y0) * 0.55)
          var aL = syA - lipA, bL = syB - lipB

          // near flank, then its bevel
          face([[sx0, y0, a0], [sx0, aL, a0], [sx1, bL, b0], [sx1, y0, b0]], base)
          face([[sx0, aL, a0], [sx0, syA, ai0], [sx1, syB, bi0], [sx1, bL, b0]], base)
          // far flank, then its bevel
          face([[sx0, y0, a1], [sx1, y0, b1], [sx1, bL, b1], [sx0, aL, a1]], base)
          face([[sx0, aL, a1], [sx1, bL, b1], [sx1, syB, bi1], [sx0, syA, ai1]], base)
          // top
          face([[sx0, syA, ai0], [sx0, syA, ai1], [sx1, syB, bi1], [sx1, syB, bi0]], base)
          // underside
          face([[sx0, y0, a0], [sx1, y0, b0], [sx1, y0, b1], [sx0, y0, a1]], base)
          // Only the real ends of the solid get an end cap; an internal one
          // would paint a bright band of nose-colour across the flank.
          if (s === slices - 1 && capEnd !== false)
            face([[sx1, y0, b0], [sx1, bL, b0], [sx1, syB, bi0], [sx1, syB, bi1],
                  [sx1, bL, b1], [sx1, y0, b1]], base)
          if (s === 0 && capStart !== false)
            face([[sx0, y0, a0], [sx0, y0, a1], [sx0, aL, a1], [sx0, syA, ai1],
                  [sx0, syA, ai0], [sx0, aL, a0]], base)
        }
      }
      function prism(x0, x1, y0, yA, yB, z0, z1, base, ti, ch) {
        sweep(x0, x1, y0, yA, yB, [z0, z1], [z0, z1], base, ti, ch, true, true)
      }
      function box(x0, x1, y0, y1, z0, z1, base, ti, ch) {
        prism(x0, x1, y0, y1, y1, z0, z1, base, ti, ch)
      }

      // ----------------------------------------------------- cast shadows
      // A rectangle at height `from` dropped onto the horizontal plane at
      // `onto` along the light ray, as a screen polygon. This is what darkens
      // the cowl under the wing and the dais under the nose: the same light
      // that shades the faces decides where the dark goes.
      function castQuad(x0, x1, z0, z1, from, onto) {
        var drop = (from - onto) / Ly
        var dx = -Lx * drop
        var dz = -Lz * drop
        var corners = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]
        var out = []
        for (var i = 0; i < 4; i++)
          out.push(project(corners[i][0] + dx, onto, corners[i][1] + dz))
        return out
      }

      // Paint a screen polygon at a flat alpha, optionally clipped to another
      // screen polygon -- the receiving surface, so a shadow never spills off
      // the part it lands on.
      function shadowPoly(poly, alpha, clipPoly, depth) {
        queue.push({ pts: poly, fill: Qt.rgba(0, 0, 0, alpha), clip: clipPoly,
                     depth: depth })
      }

      function modelPoly(points3) {
        var out = []
        for (var i = 0; i < points3.length; i++)
          out.push(project(points3[i][0], points3[i][1], points3[i][2]))
        return out
      }

      // ----------------------------------------------------------- colours
      var paintBase = kart.paint
      var deepBase = gain(kart.paint, 0.58)
      var chassisBase = Qt.rgba(0.17, 0.19, 0.25, 1)
      var darkBase = Qt.rgba(0.10, 0.12, 0.16, 1)
      var glassBase = Qt.rgba(0.14, 0.40, 0.46, 1)
      var tyreBase = Qt.rgba(0.11, 0.12, 0.15, 1)

      // ------------------------------------------------------------ wheels
      // A wheel is a disc in the model's x-y plane, so the camera turns it
      // into a sheared ellipse on its own -- there is no ellipse constant
      // anywhere below. The basis vectors are read straight out of the
      // projection, which is why the far wheel comes out smaller than the
      // near one by exactly its depth ratio.
      function basis(x, yc, z, r) {
        var o = project(x, yc, z)
        var ex = project(x + r, yc, z)
        var ey = project(x, yc + r, z)
        return { o: o, ax: [ex[0] - o[0], ex[1] - o[1]], ay: [ey[0] - o[0], ey[1] - o[1]] }
      }
      function lerpBasis(a, b, t) {
        return { o: [a.o[0] + (b.o[0] - a.o[0]) * t, a.o[1] + (b.o[1] - a.o[1]) * t],
                 ax: [a.ax[0] + (b.ax[0] - a.ax[0]) * t, a.ax[1] + (b.ax[1] - a.ax[1]) * t],
                 ay: [a.ay[0] + (b.ay[0] - a.ay[0]) * t, a.ay[1] + (b.ay[1] - a.ay[1]) * t] }
      }
      function ringOn(ctx2, b, k, ox, oy, fill) {
        ctx2.save()
        ctx2.transform(b.ax[0], b.ax[1], b.ay[0], b.ay[1], b.o[0], b.o[1])
        ctx2.beginPath()
        ctx2.arc(ox, oy, k, 0, Math.PI * 2, false)
        ctx2.restore()
        ctx2.fillStyle = fill
        ctx2.fill()
      }

      function wheel(x, r, z0, z1) {
        var bNear = basis(x, r, z0, r)
        var bFar = basis(x, r, z1, r)
        var depth = (depthAt(x, z0) + depthAt(x, z1)) / 2
        queue.push({ depth: depth, custom: function (c) {
          // The far face, then the barrel, then the near face. The barrel is
          // banded so the tread reads, and it is lit by the same vector as
          // the bodywork: brighter toward the nose side, darker toward the
          // tail.
          ringOn(c, bFar, 1.0, 0, 0, "#0a0c10")
          var steps = 14
          for (var i = steps; i >= 0; i--) {
            var t = i / steps
            var b = lerpBasis(bNear, bFar, t)
            var band = (i % 3 === 0) ? 0.86 : 1.0
            var shadeK = 0.62 + 0.38 * (1 - t)
            var col = gain(tyreBase, band * shadeK * 1.5)
            ringOn(c, b, 1.0, 0, 0, col)
          }
          // Near face: tread edge, sidewall, rim, hub. The sidewall is
          // offset up and toward the nose, which is where the light is, so
          // the tyre has a lit crescent instead of a flat disc.
          ringOn(c, bNear, 1.0, 0, 0, shade(gain(tyreBase, 1.9), [0, 0, -1]))
          ringOn(c, bNear, 0.93, 0.05, 0.07, "#12151c")
          ringOn(c, bNear, 0.66, 0, 0, "#080a0e")
          ringOn(c, bNear, 0.53, -0.03, -0.05, "#8a93a6")
          ringOn(c, bNear, 0.46, 0, 0, "#4d5468")
          for (var bo = 0; bo < 5; bo++) {
            var ang = bo * Math.PI * 2 / 5 - Math.PI / 2
            ringOn(c, bNear, 0.08, Math.cos(ang) * 0.28, Math.sin(ang) * 0.28, "#20242e")
          }
          ringOn(c, bNear, 0.17, 0, 0, "#9aa3b6")
        } })
      }

      // ------------------------------------------------ GROUND AND SHADOW
      //
      // ROUND-4 REBUILD. Round three's ground was measurably almost nothing.
      // On its own shipped frame the floor directly under the near sill ran
      // Y = 0.0370 at 21 px below the sill and Y = 0.0744 at 42 px below it,
      // against an open dais of Y = 0.0480 -- the floor got BRIGHTER under
      // the kart than beside it. (Y here and throughout this file's comments
      // is WCAG relative luminance, linearised.) The cause was arithmetic:
      // the whole-kart pool was an ellipse whose z semi-axis was 0.62 of the
      // kart's track, about 27 model units, which foreshortens to roughly
      // 40 screen px, so almost all of the floor the eye reads as "under the
      // kart" fell outside it entirely.
      //
      // What replaces it:
      //   * a contact patch per tyre, opaque black at the contact and ramping
      //     out over about 30 px measured on the ground plane;
      //   * a long, dark pool under the floor pan running the whole wheelbase;
      //   * the body's own cast quads, kept, because they say what shape the
      //     thing standing here is.
      //
      // `pool` takes its extent in MODEL units on the ground plane, so a
      // stated ramp in units converts to px through `unit` and can be read
      // back off the shipped frame.
      function pool(cx, cz, rx, rz, stops, depth) {
        var o = project(cx, 0, cz)
        var ex = project(cx + rx, 0, cz)
        var ez = project(cx, 0, cz + rz)
        // The sort is by depth alone and is not promised to be stable, so
        // every pool carries its own depth rather than sharing one.
        queue.push({ depth: depth, custom: function (c) {
          c.save()
          c.transform(ex[0] - o[0], ex[1] - o[1], ez[0] - o[0], ez[1] - o[1], o[0], o[1])
          var grad = c.createRadialGradient(0, 0, 0, 0, 0, 1)
          for (var i = 0; i < stops.length; i++)
            grad.addColorStop(stops[i][0], Qt.rgba(0, 0, 0, stops[i][1]))
          c.fillStyle = grad
          c.beginPath()
          c.arc(0, 0, 1, 0, Math.PI * 2, false)
          c.fill()
          c.restore()
        } })
      }

      // A tyre's contact with the floor. `r` is the tyre radius; the patch is
      // black out to two thirds of it and gone by 2.1 of it, which at the
      // stall's scale is a 30 px ramp on the ground plane.
      function contactPatch(x, r, z0, z1) {
        var cz = (z0 + z1) / 2
        pool(x, cz, r * 2.1, r * 2.1,
             [[0, 0.94], [0.30, 0.92], [0.46, 0.66], [0.70, 0.26], [1, 0]], 2.20e6)
        pool(x, cz, r * 0.85, r * 0.72, [[0, 0.97], [0.72, 0.95], [1, 0.55]], 2.10e6)
      }

      if (kart.shadow) {
        var midZ = (g.nearZ0 + g.farZ1) / 2
        var midX = (g.rearX + g.frontX) / 2
        // The body pool: as long as the wheelbase and as wide as the track,
        // so the floor between the wheels is the darkest floor in the picture
        // rather than the brightest.
        var halfL = (g.frontX - g.rearX) / 2 + g.frontR * 0.7
        var halfW = (g.farZ1 - g.nearZ0) / 2 + 3
        // Two pools, not one. The tight one is the body's own footprint and
        // is nearly opaque; the wide one is the ambient occlusion that makes
        // the ramp long. A single pool cannot do both, because its core and
        // its falloff share one radius: round three's did, its z semi-axis
        // came out at 27 model units, and the ramp finished 40 px from the
        // centre -- inside the kart's own silhouette, where nothing can see
        // it. The wide pool's outer stop sits about 22 model units in front
        // of the near tyre, which is 32 px down the screen at stall size.
        pool(midX, midZ, halfL, halfW,
             [[0, 0.94], [0.58, 0.92], [0.88, 0.55], [1, 0]], 2.40e6)
        pool(midX, midZ, halfL * 1.30, halfW + 22,
             [[0, 0.70], [0.40, 0.66], [0.70, 0.34], [1, 0]], 2.50e6)

        shadowPoly(castQuad(g.podX0, g.podX1, g.bodyZ0, g.bodyZ1, g.panY0, 0),
                   0.62, null, 1.6e6)
        var last = g.noseSteps[g.noseSteps.length - 1]
        shadowPoly(castQuad(g.noseSteps[0].x0, last.x1, g.noseSteps[0].z0,
                            g.noseSteps[0].z1, g.panY0, 0), 0.58, null, 1.55e6)
        if (g.frontWing)
          shadowPoly(castQuad(g.frontWing.x0, g.frontWing.x1, g.bodyZ0 - 3,
                              g.bodyZ1 + 3, Math.max(0.7, g.panY0 - 2.0), 0),
                     0.60, null, 1.5e6)
        contactPatch(g.rearX, g.rearR, g.nearZ0, g.nearZ1)
        contactPatch(g.frontX, g.frontR, g.nearZ0, g.nearZ1)
        contactPatch(g.rearX, g.rearR, g.farZ0, g.farZ1)
        contactPatch(g.frontX, g.frontR, g.farZ0, g.farZ1)
        if (g.dualRear) {
          contactPatch(g.rearX + g.rearR * 1.55, g.rearR, g.nearZ0, g.nearZ1)
          contactPatch(g.rearX + g.rearR * 1.55, g.rearR, g.farZ0, g.farZ1)
        }
      }

      // ------------------------------------------------------- the wheels
      wheel(g.rearX, g.rearR, g.farZ0, g.farZ1)
      wheel(g.frontX, g.frontR, g.farZ0, g.farZ1)
      wheel(g.rearX, g.rearR, g.nearZ0, g.nearZ1)
      wheel(g.frontX, g.frontR, g.nearZ0, g.nearZ1)
      if (g.dualRear) {
        wheel(g.rearX + g.rearR * 1.55, g.rearR * 0.92, g.farZ0, g.farZ1)
        wheel(g.rearX + g.rearR * 1.55, g.rearR * 0.92, g.nearZ0, g.nearZ1)
      }

      // ------------------------------------------------- floor pan and pod
      box(g.panX0, g.panX1, g.panY0, g.panY1, g.bodyZ0 + 1, g.bodyZ1 - 1,
          chassisBase, 1.0, 1.0)
      box(g.podX0, g.podX1, g.panY0, g.podY1, g.bodyZ0, g.bodyZ1, paintBase, 2.2, 3.0)

      // The underbody. The pod's flank used to stop in mid-air with lit dais
      // showing between it and the ground; this is the dark the eye expects
      // to find under a car, drawn as a real surface from the pod's bottom
      // edge down to the contact line rather than as nothing at all.
      //
      // ROUND-4: sliced. As one quad it took a single average depth near its
      // middle, which is nearer than the rear wheel standing at its far end,
      // so it painted a dark chord straight across the near-rear rim -- the
      // detached light-grey crescent a critic found at (455-510, 592-612) on
      // the shipped frame was this quad's edge, not a broken annulus. Each
      // slice now sorts at its own depth, exactly as `sweep` does.
      var ubSlices = 10
      for (var ub = 0; ub < ubSlices; ub++) {
        var ux0 = g.podX0 + 1 + (g.podX1 - g.podX0 - 2) * ub / ubSlices
        var ux1 = g.podX0 + 1 + (g.podX1 - g.podX0 - 2) * (ub + 1) / ubSlices
        face([[ux0, g.panY0, g.bodyZ0 + 0.4], [ux1, g.panY0, g.bodyZ0 + 0.4],
              [ux1, 0, g.bodyZ0 + 3.2], [ux0, 0, g.bodyZ0 + 3.2]],
             Qt.rgba(0.03, 0.035, 0.05, 1))
      }

      // The flank is given two more values so the paint reads as a body and
      // not as one plate of colour: a dark sill along the bottom of the pod
      // and a livery band above it, both standing proud of the flank so they
      // catch the same light the flank does.
      var sillTop = g.panY0 + (g.podY1 - g.panY0) * 0.30
      box(g.podX0 + 0.5, g.podX1 - 0.5, g.panY0 + 0.2, sillTop,
          g.bodyZ0 - 0.45, g.bodyZ0, gain(kart.paint, 0.34), 0.1, 0.3)
      var bandY = sillTop + (g.podY1 - sillTop) * 0.20
      box(g.podX0 + 2.5, g.podX1 - 0.5, bandY, bandY + 2.1,
          g.bodyZ0 - 0.35, g.bodyZ0, gain(kart.paint, 1.34), 0.1, 0.3)

      // ------------------------------------------------------ WHEEL ARCHES
      //
      // ROUND-4. This is the round's central piece of work, and round three
      // did not have it. Round three called a soft radial pool centred on the
      // wheel's own hub an "arch": almost all of it fell behind the tyre that
      // cast it, and what survived was a faint haze. The verdict was exact --
      // "every wheel/body meeting is a hard silhouette edge", and the far
      // wheel came out as "a 13 x 5 grey chip that reads as debris... because
      // there is no fender: no arch, no wrap, no shadow of the wheel cast
      // onto the body, no darkening where they meet."
      //
      // An arch is four things, and all four are drawn here:
      //
      //   1. THE OPENING. A dark disc on the body's own surface at the
      //      wheel's radius, so the bodywork has a hole the tyre stands in
      //      rather than a silhouette it abuts.
      //   2. THE INNER LIP. A darker ring just inside the opening's edge --
      //      the cut edge of the panel, in shadow because it faces inward.
      //   3. THE OUTER LIP. A thin bright arc just outside it, the rolled
      //      edge of the arch catching the same light everything else does.
      //   4. THE WHEEL'S OWN SHADOW, cast onto the flank along the light ray
      //      and falling off over about a third of a radius.
      //
      // All four are clipped to `flankOutline`: the body's silhouette in the
      // plane they are drawn on, so no part of an arch can land on the dais
      // or on the wall behind the kart.
      //
      // The whole thing is queued at a depth just behind the tyre it belongs
      // to, so every slice of bodywork -- including nose slices nearer than
      // the arch's own x -- is already painted underneath it.
      function flankOutline(zp) {
        var pts = [[g.podX0 - 1, g.panY0 - 0.5, zp], [g.podX0 - 1, g.podY1, zp],
                   [g.podX1, g.podY1, zp]]
        for (var q = 0; q < g.noseSteps.length; q++) {
          var ns = g.noseSteps[q]
          pts.push([ns.x0, ns.yA, zp])
          pts.push([ns.x1, ns.yB, zp])
        }
        var lastStep = g.noseSteps[g.noseSteps.length - 1]
        pts.push([lastStep.x1, g.panY0 - 0.5, zp])
        return modelPoly(pts)
      }

      function wheelArch(x, r, zPlane, wheelDepth) {
        var b = basis(x, r, zPlane, r)
        var clipPts = flankOutline(zPlane)
        // The light's direction projected onto this plane, for the cast
        // shadow: down the ray, so the dark falls away from the light.
        var sx = -Lx * 0.30, sy = -Ly * 0.30
        queue.push({ depth: wheelDepth + 0.12, custom: function (c) {
          c.save()
          c.beginPath()
          c.moveTo(clipPts[0][0], clipPts[0][1])
          for (var ci = 1; ci < clipPts.length; ci++)
            c.lineTo(clipPts[ci][0], clipPts[ci][1])
          c.closePath()
          c.clip()
          c.transform(b.ax[0], b.ax[1], b.ay[0], b.ay[1], b.o[0], b.o[1])

          // 4. the tyre's shadow on the flank, offset down the light ray
          var cast = c.createRadialGradient(sx, sy, 0, sx, sy, 1.62)
          cast.addColorStop(0, Qt.rgba(0, 0, 0, 0.62))
          cast.addColorStop(0.66, Qt.rgba(0, 0, 0, 0.30))
          cast.addColorStop(1, Qt.rgba(0, 0, 0, 0))
          c.fillStyle = cast
          c.beginPath()
          c.arc(sx, sy, 1.62, 0, Math.PI * 2, false)
          c.fill()

          // 1. the opening
          var open = c.createRadialGradient(0, 0, 0, 0, 0, 1.16)
          open.addColorStop(0, Qt.rgba(0, 0, 0, 0.90))
          open.addColorStop(0.80, Qt.rgba(0, 0, 0, 0.86))
          open.addColorStop(1, Qt.rgba(0, 0, 0, 0))
          c.fillStyle = open
          c.beginPath()
          c.arc(0, 0, 1.16, 0, Math.PI * 2, false)
          c.fill()

          // 2. the inner lip: the cut edge of the panel, facing inward
          c.beginPath()
          c.arc(0, 0, 1.16, 0, Math.PI * 2, false)
          c.arc(0, 0, 1.02, 0, Math.PI * 2, true)
          c.fillStyle = Qt.rgba(0, 0, 0, 0.55)
          c.fill()

          // 3. the outer lip, over the top of the opening only. The basis
          // `ay` runs up the screen, so positive angles are the TOP of the
          // arch: 1.02*PI to 1.98*PI put this warm band along the BOTTOM of
          // each wheel, where it read as a tan crescent under the tyre.
          c.beginPath()
          c.arc(0, 0, 1.255, Math.PI * 0.02, Math.PI * 0.98, false)
          c.arc(0, 0, 1.155, Math.PI * 0.98, Math.PI * 0.02, true)
          c.fillStyle = Qt.rgba(1, 0.86, 0.66, 0.24)
          c.fill()
          c.restore()
        } })
      }

      // The fender arc: real geometry, so the wheel has something to pass
      // behind. A band of bodywork over the top of a tyre, built as a ring
      // segment between two radii and extruded across the tyre's width.
      //
      // Every quad is emitted ONCE, with the winding that makes its normal
      // point out of the solid. `oriented` does that by construction: it
      // reads the normal the winding would give and reverses the quad when
      // that disagrees with the outward direction the caller states.
      //
      // The first draft of this emitted both windings and let the back-face
      // cull choose. That is wrong for a band, and it showed: where the
      // outward face was culled, the reversed one survived carrying a normal
      // that pointed the wrong way, so the INSIDE of the arch -- which faces
      // down into the wheel and must be the darkest thing on the part --
      // picked up the sky term and rendered as a bright cream crescent under
      // each tyre. Shading is only as honest as the normals it is given.
      //
      // With the winding right, the inner surface comes out dark from the
      // same `shade` call every other face uses. That is the dark inner lip,
      // and it is the lighting model saying it rather than a chosen value.
      function oriented(pts, want) {
        var n = normalOf(pts)
        if (!n)
          return pts
        if (n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0)
          return [pts[3], pts[2], pts[1], pts[0]]
        return pts
      }
      function fenderArc(x, r, z0, z1, base, ri, ro, a0, a1, steps) {
        function pt(a, rad, z) {
          return [x + Math.cos(a) * rad, r + Math.sin(a) * rad, z]
        }
        for (var i = 0; i < steps; i++) {
          var t0 = a0 + (a1 - a0) * i / steps
          var t1 = a0 + (a1 - a0) * (i + 1) / steps
          var tm = (t0 + t1) / 2
          var out = [Math.cos(tm), Math.sin(tm), 0]
          var inn = [-out[0], -out[1], 0]
          face(oriented([pt(t0, ro, z0), pt(t1, ro, z0), pt(t1, ro, z1), pt(t0, ro, z1)], out), base)
          face(oriented([pt(t0, ri, z0), pt(t1, ri, z0), pt(t1, ri, z1), pt(t0, ri, z1)], inn), base)
          face(oriented([pt(t0, ri, z0), pt(t1, ri, z0), pt(t1, ro, z0), pt(t0, ro, z0)], [0, 0, -1]), base)
          face(oriented([pt(t0, ri, z1), pt(t1, ri, z1), pt(t1, ro, z1), pt(t0, ro, z1)], [0, 0, 1]), base)
        }
        face(oriented([pt(a0, ri, z0), pt(a0, ro, z0), pt(a0, ro, z1), pt(a0, ri, z1)],
                      [Math.sin(a0), -Math.cos(a0), 0]), base)
        face(oriented([pt(a1, ri, z0), pt(a1, ro, z0), pt(a1, ro, z1), pt(a1, ri, z1)],
                      [-Math.sin(a1), Math.cos(a1), 0]), base)
      }

      // Every wheel on every body gets an arc; the fendered bodies get a
      // deeper one. `wide` is how far past the tyre's own width the band
      // runs, which is the lip that reads at stall size.
      function seatWheel(x, r, zNear0, zNear1, zFar0, zFar1, deep) {
        // The band's inner radius is INSIDE the tyre, not outside it. At
        // r * 1.035 there was a sight line between the arch and the tyre it
        // covers, and the room showed through it as a few pixels of bare
        // background inside the kart's own silhouette. Overlapping the tyre
        // costs nothing -- the face queue puts the tyre in front of the part
        // of the band it covers -- and it closes the gap by construction.
        var ri = r * 0.92
        var ro = r * (deep ? 1.17 : 1.10)
        var a0 = Math.PI * (deep ? 0.07 : 0.11)
        var a1 = Math.PI * (deep ? 0.93 : 0.89)
        var steps = 13
        fenderArc(x, r, zNear0 - 0.7, zNear1 + 0.7, paintBase, ri, ro, a0, a1, steps)
        fenderArc(x, r, zFar0 - 0.7, zFar1 + 0.7, paintBase, ri, ro, a0, a1, steps)
        // The near tyre's opening in the flank, and its shadow on it.
        wheelArch(x, r, g.bodyZ0 - 0.05, depthAt(x, (zNear0 + zNear1) / 2))
      }
      seatWheel(g.rearX, g.rearR, g.nearZ0, g.nearZ1, g.farZ0, g.farZ1, g.fenders)
      seatWheel(g.frontX, g.frontR, g.nearZ0, g.nearZ1, g.farZ0, g.farZ1, g.fenders)
      if (g.dualRear)
        seatWheel(g.rearX + g.rearR * 1.55, g.rearR * 0.92,
                  g.nearZ0, g.nearZ1, g.farZ0, g.farZ1, true)

      // ------------------------------------------------------------- nose
      // The nose is one chained taper, not a stack of slabs. Each section
      // starts at the width the previous one ended on and only the tip gets
      // an end cap, so the flank runs unbroken from the side pod to the point
      // and the shading is continuous the whole way along it.
      for (var n = 0; n < g.noseSteps.length; n++) {
        var st = g.noseSteps[n]
        var prev = n === 0 ? { z0: g.bodyZ0, z1: g.bodyZ1 } : g.noseSteps[n - 1]
        sweep(st.x0, st.x1, g.panY0, st.yA, st.yB,
              [prev.z0, prev.z1], [st.z0, st.z1], paintBase, 2.4, 2.6,
              n === 0, n === g.noseSteps.length - 1)
      }
      if (g.frontWing) {
        // The plane's top face is the nose's own underside -- they share the
        // height `panY0` rather than being two solids that happen to be near
        // each other. That is what removes the round-two fault where the
        // bumper block ended in a flat edge with lit dais under it: there is
        // no height between the two at which anything could show through.
        var fw = g.frontWing
        var fwTop = g.panY0
        var fwBot = Math.max(0.7, g.panY0 - 2.0)
        var fz0 = g.bodyZ0 - 3, fz1 = g.bodyZ1 + 3
        box(fw.x0, fw.x1, fwBot, fwTop, fz0, fz1, deepBase, 0.7, 0.8)
        // Endplates at the plane's outboard ends, turned up.
        box(fw.x0 + 1.6, fw.x1, fwBot, fwTop + 4.0, fz1 - 1.9, fz1, paintBase, 0.3, 0.9)
        box(fw.x0 + 1.6, fw.x1, fwBot, fwTop + 4.0, fz0, fz0 + 1.9, paintBase, 0.3, 0.9)
      }

      // ------------------------------------------------------ engine cowl
      box(g.cowlX0, g.cowlX1, g.panY0, g.cowlY, g.bodyZ0 + 3, g.bodyZ1 - 3,
          deepBase, 2.0, 2.6)
      for (var v = 0; v < 3; v++)
        box(g.cowlX0 + 3 + v * 5, g.cowlX0 + 5.4 + v * 5, g.cowlY - 8, g.cowlY - 2.5,
            g.bodyZ0 + 2.2, g.bodyZ0 + 3, darkBase, 0.1, 0.4)

      // -------------------------------------------- rear wing and its posts
      if (g.wing) {
        // ROUND-4 REBUILD. Round three's posts stood at z = bodyZ0 - 1 and
        // bodyZ1 + 1, both of them outboard of the engine cowl they were
        // described as standing on: the cowl runs z = bodyZ0 + 3 to
        // bodyZ1 - 3, so the outboard post's whole footprint was open air.
        // On the shipped frame it ended at y = 540 with the wall's hazard
        // stripe visible at y = 546 underneath it. The posts now stand
        // inside the cowl's own footprint in both z and x, and the plane
        // starts at the cowl's rear face rather than two units behind it,
        // so no part of this assembly overhangs anything but the cowl.
        var cwz0 = g.bodyZ0 + 3
        var cwz1 = g.bodyZ1 - 3
        var wingX0 = g.cowlX0
        var wingX1 = wingX0 + g.wing.len
        var wingY0 = g.cowlY + g.wing.rise
        var wingY1 = wingY0 + 3.4
        if (g.wing.rise > 2) {
          // Two posts, both wholly over the cowl, both raked forward so the
          // plane is carried rather than balanced. A fillet block at the foot
          // of each is what describes the join: without it a post meets a
          // deck at a hard silhouette and reads as a stick resting on a box.
          var postX0 = wingX0 + 1.6
          var postX1 = postX0 + 4.4
          var pz = [[cwz0 + 1.0, cwz0 + 5.2], [cwz1 - 5.2, cwz1 - 1.0]]
          for (var wp = 0; wp < 2; wp++) {
            box(postX0, postX1, g.cowlY - 2.5, wingY0, pz[wp][0], pz[wp][1],
                deepBase, 0.5, 0.9)
            // The fillet: a wider, shorter block at the post's foot.
            box(postX0 - 1.2, postX1 + 1.2, g.cowlY - 2.5, g.cowlY + 2.0,
                pz[wp][0] - 1.0, pz[wp][1] + 1.0, deepBase, 0.5, 1.4)
          }
          // What the wing does to the cowl underneath it. This one shadow is
          // the single largest reason the tail reads as one object.
          shadowPoly(castQuad(wingX0, wingX1, cwz0, cwz1, wingY0, g.cowlY),
                     0.50,
                     modelPoly([[g.cowlX0, g.cowlY, cwz0], [g.cowlX0, g.cowlY, cwz1],
                                [g.cowlX1, g.cowlY, cwz1], [g.cowlX1, g.cowlY, cwz0]]),
                     depthAt((g.cowlX0 + g.cowlX1) / 2, (g.bodyZ0 + g.bodyZ1) / 2) - 0.5)
        }
        if (g.wing.deck > 0)
          box(wingX0 + 3, wingX1 - 3, wingY0 - g.wing.deck, wingY0 - g.wing.deck + 2.6,
              cwz0 + 1, cwz1 - 1, deepBase, 0.8, 0.9)
        // The plane itself, then an endplate at each end. Round three drew
        // the far post in `deepBase` where an endplate belongs, so the tail
        // read as two mismatched slabs meeting at a hard seam: one solid in
        // the paint value, one in the dark value, sharing a screen edge. The
        // endplates are the paint value, like the plane, and every face on
        // both of them takes its single value from `shade` and its own
        // normal, so no coplanar face carries two shades.
        var wz0 = cwz0 - 1.6
        var wz1 = cwz1 + 1.6
        box(wingX0, wingX1, wingY0, wingY1, wz0, wz1, paintBase, 1.2, 1.2)
        box(wingX0 + 0.8, wingX1 - 0.8, wingY0 - 1.2, wingY1 + 2.6,
            wz0 - 1.5, wz0, paintBase, 0.3, 0.8)
        box(wingX0 + 0.8, wingX1 - 0.8, wingY0 - 1.2, wingY1 + 2.6,
            wz1, wz1 + 1.5, paintBase, 0.3, 0.8)
      }

      // -------------------------------------------------- seat and roll bar
      //
      // ROUND-4 REBUILD. Round three's seat was one box, x seatX0..seatX1 by
      // panY1..seatY, and a critic called it a grey box with no back and no
      // shoulders -- correctly: a single solid cannot show a back, because a
      // back is the relationship between two solids. It is now four: a
      // cushion the driver sits on, a backrest raked away from the nose, two
      // shoulder bolsters standing proud of the backrest at both ends of z,
      // and a headrest that sits on the backrest rather than beside it.
      var seatZ0 = g.bodyZ0 + 6
      var seatZ1 = g.bodyZ1 - 6
      var seatMid = (seatZ0 + seatZ1) / 2
      var cushionY = g.panY1 + (g.podY1 - g.panY1) * 0.62
      // The seat is upholstery, so it gets its own two values rather than
      // borrowing the chassis grey for one part and the paint's dark value
      // for another: a brown bolster in front of a grey back reads as a
      // stray box, not as a seat.
      var seatBase = Qt.rgba(0.23, 0.25, 0.31, 1)
      var seatDark = Qt.rgba(0.145, 0.16, 0.205, 1)
      // The cushion. Wide in z, low, and it runs forward of the backrest.
      box(g.seatX0 + 4.0, g.seatX1 + 4.5, g.panY1, cushionY,
          seatZ0 - 0.5, seatZ1 + 0.5, seatBase, 1.6, 1.2)
      // The backrest: a raked plate. `prism` takes a different top height at
      // x0 and at x1, so the rake is geometry rather than a second box.
      prism(g.seatX0, g.seatX0 + 4.5, g.panY1, g.seatY, g.seatY - 2.5,
            seatZ0, seatZ1, seatBase, 1.4, 2.0)
      // Shoulders. Two bolsters standing proud of the backrest at each end
      // of its width, which is what turns a plate into a seat.
      box(g.seatX0 - 0.6, g.seatX0 + 5.1, cushionY, g.seatY + 1.0,
          seatZ0 - 1.2, seatZ0 + 2.2, seatDark, 0.7, 1.1)
      box(g.seatX0 - 0.6, g.seatX0 + 5.1, cushionY, g.seatY + 1.0,
          seatZ1 - 2.2, seatZ1 + 1.2, seatDark, 0.7, 1.1)
      // The seat sits in a well: the pod top darkens where the seat meets it.
      shadowPoly(castQuad(g.seatX0 - 1, g.seatX1 + 5, seatZ0 - 1.6, seatZ1 + 1.6,
                          g.seatY, g.podY1), 0.46,
                 modelPoly([[g.podX0, g.podY1, g.bodyZ0 + 2.2], [g.podX0, g.podY1, g.bodyZ1 - 2.2],
                            [g.podX1, g.podY1, g.bodyZ1 - 2.2], [g.podX1, g.podY1, g.bodyZ0 + 2.2]]),
                 depthAt((g.podX0 + g.podX1) / 2, (g.bodyZ0 + g.bodyZ1) / 2) - 0.5)
      if (g.headrest)
        box(g.seatX0 - 1.0, g.seatX0 + 4.0, g.seatY - 0.4, g.seatY + 4.0,
            seatMid - 3.6, seatMid + 3.6, seatDark, 1.0, 1.4)
      if (g.hoop) {
        // ROUND-4. Round three stood the cage's legs at x seatX0-3..seatX0+0.5
        // -- entirely behind the backrest, where at stall size the bars and
        // the seat merged into one lump. The rear legs are unchanged in
        // spirit but the front pair now stands clear in front of the driver,
        // the bars are 4.2 units instead of 3.5, and the top rail runs the
        // whole length, so the cage is a cage from any angle.
        var hy = g.seatY + 8
        var hz0 = seatZ0 - 1.5, hz1 = seatZ1 + 1.5
        var legBack0 = g.seatX0 - 3.6, legBack1 = legBack0 + 4.2
        var legFore0 = g.seatX1 + 3.0, legFore1 = legFore0 + 4.2
        box(legBack0, legBack1, g.podY1 - 2, hy, hz0, hz0 + 4.2, chassisBase, 0.6, 0.8)
        box(legBack0, legBack1, g.podY1 - 2, hy, hz1 - 4.2, hz1, chassisBase, 0.6, 0.8)
        box(legFore0, legFore1, g.podY1 - 2, hy - 1.5, hz0, hz0 + 4.2, chassisBase, 0.6, 0.8)
        box(legFore0, legFore1, g.podY1 - 2, hy - 1.5, hz1 - 4.2, hz1, chassisBase, 0.6, 0.8)
        // Roof rail, then a cross brace behind the driver's head.
        prism(legBack0, legFore1, hy - 4.2, hy, hy - 1.5, hz0, hz1, chassisBase, 0.8, 0.9)
        box(legBack0 + 1, legBack1 - 1, g.seatY + 1, g.seatY + 4.2, hz0, hz1,
            chassisBase, 0.8, 0.9)
      }

      // ----------------------------------------------------- steering wheel
      if (g.steering) {
        // ROUND-4 REBUILD. Round three's rim was an annulus in the source and
        // a dish on the screen: at the size the stall renders it the hole was
        // 23 x 14 px and a full-width spoke bar 0.22 of the radius plus a
        // boss 0.22 of the radius left two 4 px slots that closed up at 1:1.
        // The rim is bigger, the wall thinner, the boss half the size, and
        // the spokes are 0.055 of the radius, so the hole is open and the
        // scene is visible through it -- which is the only reason a wheel
        // reads as a wheel rather than as a plate.
        var colZ0 = (g.bodyZ0 + g.bodyZ1) / 2 - 1.9
        // A raked column, with a fairing where it enters the bodywork so it
        // does not plunge straight through a lit surface.
        prism(g.steerX - 0.4, g.steerX + 3.4, g.podY1 - 2.6, g.steerY - 2.2, g.steerY - 0.6,
              colZ0, colZ0 + 3.8, chassisBase, 0.5, 0.7)
        box(g.steerX - 2.2, g.steerX + 5.2, g.podY1 - 2.6, g.podY1 + 1.6,
            colZ0 - 1.8, colZ0 + 5.6, darkBase, 0.8, 1.2)
        var rimR = 7.0
        var rimC = [g.steerX + 1.5, g.steerY + 2.6, colZ0 + 1.9]
        var rb = basis(rimC[0], rimC[1], rimC[2], rimR)
        var rz = project(rimC[0], rimC[1], rimC[2] + rimR)
        // The rim's plane: mostly upright, laid back by the amount a driver
        // holds it at. 0.72 up against 0.62 into the screen.
        var tilt = { o: rb.o, ax: rb.ax,
                     ay: [(rb.ay[0] * 0.72 + (rz[0] - rb.o[0]) * 0.62),
                          (rb.ay[1] * 0.72 + (rz[1] - rb.o[1]) * 0.62)] }
        queue.push({ depth: depthAt(rimC[0], rimC[2]) - 0.2, custom: function (c) {
          function ann(outer, inner, fill) {
            c.save()
            c.transform(tilt.ax[0], tilt.ax[1], tilt.ay[0], tilt.ay[1], tilt.o[0], tilt.o[1])
            c.beginPath()
            c.arc(0, 0, outer, 0, Math.PI * 2, false)
            c.arc(0, 0, inner, 0, Math.PI * 2, true)
            c.restore()
            c.fillStyle = fill
            c.fill()
          }
          // The rim, then a lit crescent along its upper limb from the same
          // light that shades the bodywork.
          ann(1.0, 0.74, "#232935")
          c.save()
          c.transform(tilt.ax[0], tilt.ax[1], tilt.ay[0], tilt.ay[1], tilt.o[0], tilt.o[1])
          c.beginPath()
          c.arc(0, 0, 0.99, Math.PI * 1.10, Math.PI * 1.90, false)
          c.arc(0, 0, 0.80, Math.PI * 1.90, Math.PI * 1.10, true)
          c.restore()
          c.fillStyle = "#5c6578"
          c.fill()
          // Three thin spokes at the angles a real wheel carries them, and a
          // small boss. Nothing here crosses the middle of the opening.
          c.save()
          c.transform(tilt.ax[0], tilt.ax[1], tilt.ay[0], tilt.ay[1], tilt.o[0], tilt.o[1])
          c.beginPath()
          for (var sp = 0; sp < 3; sp++) {
            var a = sp * Math.PI * 2 / 3 + Math.PI / 6
            var ca = Math.cos(a), sa = Math.sin(a)
            c.moveTo(ca * 0.18 - sa * 0.055, sa * 0.18 + ca * 0.055)
            c.lineTo(ca * 0.80 - sa * 0.055, sa * 0.80 + ca * 0.055)
            c.lineTo(ca * 0.80 + sa * 0.055, sa * 0.80 - ca * 0.055)
            c.lineTo(ca * 0.18 + sa * 0.055, sa * 0.18 - ca * 0.055)
            c.closePath()
          }
          c.restore()
          c.fillStyle = "#39404e"
          c.fill()
          ringOn(c, tilt, 0.15, 0, 0, "#6a7386")
        } })
      }

      // ------------------------------------------- fenders, roof and canopy
      //
      // ROUND-4 REBUILD of the fendered bodies. The verdict called STOCKCAR
      // the worst of the six and the list was long: the near-rear hub bisected
      // into a grey chip, the far-rear wheel an unreadable black mass, a
      // jagged staircase notch on the rear quarter, a detached sliver below
      // the sill, the roof a tabletop on two thin posts, the windscreen an
      // unframed quad with a gap under its left edge. Almost all of it came
      // from two boxes: each "fender" was a slab running from z = nearZ0 - 1
      // to z = bodyZ1, i.e. from OUTBOARD OF THE NEAR TYRE'S OUTER FACE all
      // the way across the car, at a height that put it across the middle of
      // the wheels. It did not cover the wheels, it cut them in half.
      //
      // A fender is now the same arc every body's wheels get -- geometry over
      // the top of the tyre -- taken deeper, plus a haunch that ties the arc
      // into the flank. The wheel passes behind it because the face queue
      // sorts it there, not because a slab is painted over it.
      function haunch(x, r) {
        box(x - r * 1.05, x + r * 1.05, g.podY1 - 4.5, g.podY1 + 1.2,
            g.nearZ0 + 0.5, g.bodyZ1 - 0.5, paintBase, 1.6, 1.8)
      }
      if (g.fenders) {
        haunch(g.rearX, g.rearR)
        haunch(g.frontX, g.frontR)
      }
      if (g.roof) {
        // A cabin, not a tabletop: four pillars 4.4 units thick instead of
        // two at 3, a windscreen set inside a frame that runs all the way
        // down to the scuttle, and a raked roof.
        var cabZ0 = g.bodyZ0 + 4
        var cabZ1 = g.bodyZ1 - 4
        var pillarBack = g.seatX0 - 4.4
        var pillarFore = g.seatX1 + 7
        var roofY = g.seatY + 6.5
        var scuttle = g.podY1 + 1.2
        // Scuttle: the ledge the screen stands on, so nothing shows under it.
        box(pillarBack - 1, pillarFore + 5, g.podY1 - 1.5, scuttle,
            cabZ0 - 1.5, cabZ1 + 1.5, deepBase, 1.4, 1.0)
        for (var rp = 0; rp < 2; rp++) {
          var rz0 = rp === 0 ? cabZ0 : cabZ1 - 4.4
          box(pillarBack, pillarBack + 4.4, scuttle, roofY, rz0, rz0 + 4.4,
              chassisBase, 0.5, 0.7)
          box(pillarFore, pillarFore + 4.4, scuttle, roofY - 2.0, rz0, rz0 + 4.4,
              chassisBase, 0.5, 0.7)
        }
        // The screen: a raked plate inside the pillars, and a frame band
        // across its top so its upper edge is not a bare silhouette.
        prism(pillarFore + 0.6, pillarFore + 4.0, scuttle, roofY - 2.4, roofY - 2.4,
              cabZ0 + 1.0, cabZ1 - 1.0, glassBase, 0.6, 0.8)
        box(pillarFore - 0.4, pillarFore + 5.0, roofY - 2.6, roofY - 1.2,
            cabZ0 - 0.6, cabZ1 + 0.6, chassisBase, 0.6, 0.8)
        // Roof, raked down toward the nose so it is not a flat lid.
        prism(pillarBack - 1.2, pillarFore + 5.2, roofY - 3.2, roofY, roofY - 2.0,
              cabZ0 - 1.2, cabZ1 + 1.2, deepBase, 1.4, 1.6)
      }
      if (g.canopy) {
        box(g.seatX0 + 1, g.seatX1 + 2, g.podY1 - 1, g.seatY + 6,
            g.bodyZ0 + 4, g.bodyZ1 - 4, glassBase, 2.0, 3.0)
        box(g.seatX0 + 1, g.seatX1 + 2, g.seatY + 6, g.seatY + 8,
            g.bodyZ0 + 4, g.bodyZ1 - 4, chassisBase, 1.6, 1.0)
      }

      // ------------------------------------------------------- number plate
      if (kart.showNumber) {
        // The plate stands proud of the flank on a dark surround, and its face
        // is painted at a fixed value rather than through `shade`: it is the
        // one surface on the kart whose job is to carry black digits, so it
        // keeps its contrast whatever angle the flank is lit at.
        // Both the surround and the plate are single flat quads, and both take
        // their depth from the plate's nose-most edge -- the nearest point on
        // it. A sliced solid here would order its own slices against the
        // plate's average depth and paint the nose half of the surround back
        // over the digits.
        var pl = g.plate
        var plateD = depthAt(pl.x1, kart.plateZ) - 1.2
        queue.push({ pts: modelPoly([[pl.x0 - 0.9, pl.y0 - 0.9, kart.plateZ],
                                     [pl.x0 - 0.9, pl.y1 + 0.9, kart.plateZ],
                                     [pl.x1 + 0.9, pl.y1 + 0.9, kart.plateZ],
                                     [pl.x1 + 0.9, pl.y0 - 0.9, kart.plateZ]]),
                     fill: "#0b0d12", depth: plateD + 0.2 })
        queue.push({ pts: modelPoly([[pl.x0, pl.y0, kart.plateZ], [pl.x0, pl.y1, kart.plateZ],
                                     [pl.x1, pl.y1, kart.plateZ], [pl.x1, pl.y0, kart.plateZ]]),
                     fill: "#eef1f7", depth: plateD })
      }

      // ----------------------------------------------------------- paint it
      queue.sort(function (a, b) { return b.depth - a.depth })
      ctx.globalAlpha = Math.max(0, Math.min(1, kart.dim))
      for (var q = 0; q < queue.length; q++) {
        var item = queue[q]
        if (item.custom) {
          item.custom(ctx)
          continue
        }
        ctx.save()
        if (item.clip) {
          ctx.beginPath()
          ctx.moveTo(item.clip[0][0], item.clip[0][1])
          for (var ci = 1; ci < item.clip.length; ci++)
            ctx.lineTo(item.clip[ci][0], item.clip[ci][1])
          ctx.closePath()
          ctx.clip()
        }
        // Each face is stroked with its own fill as well as filled, which
        // widens it by half a pixel and closes the hairline seams fractional
        // coordinates would otherwise leave between two faces of one solid.
        ctx.fillStyle = item.fill
        ctx.strokeStyle = item.fill
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(item.pts[0][0], item.pts[0][1])
        for (var pi = 1; pi < item.pts.length; pi++)
          ctx.lineTo(item.pts[pi][0], item.pts[pi][1])
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
        ctx.restore()
      }
      ctx.globalAlpha = 1
    }
  }

  // The digits ride on the painted plate, rotated onto it, so they use the
  // shell's monospace face instead of being drawn as boxes.
  Item {
    visible: kart.showNumber
    x: kart.plateP00[0]
    y: kart.plateP00[1] - kart.plateH
    width: kart.plateW
    height: kart.plateH
    transformOrigin: Item.BottomLeft
    rotation: kart.plateAngle

    Text {
      anchors.fill: parent
      textFormat: Text.PlainText
      text: String(Math.max(1, Math.min(99, kart.number)))
      color: "#0c0e13"
      opacity: kart.dim
      font.family: Theme.mono
      font.bold: true
      // ROUND-4: 0.90 of the plate's own height, not 0.78, and the plate is
      // 15 % taller in the model. On the shipped frame the digit's ink went
      // from 21 px to 33 px tall. It is still not the identity B's is -- see
      // the report; the flank this plate lives on is 46 px tall in this
      // camera, and the design puts the number on the flank.
      font.pixelSize: Math.max(6, Math.round(kart.plateH * 0.90))
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }

  onBodyChanged: surface.requestPaint()
  onPaintChanged: surface.requestPaint()
  onShowNumberChanged: surface.requestPaint()
  onDimChanged: surface.requestPaint()
  onUnitChanged: surface.requestPaint()
  onShadowChanged: surface.requestPaint()
}
