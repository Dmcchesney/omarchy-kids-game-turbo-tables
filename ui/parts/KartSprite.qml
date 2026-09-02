import QtQuick
import "../"

// A kart, drawn as a solid built out of voxel boxes in a fixed 132 x 70 view
// box and scaled to whatever room it is given. Six bodies, any of the eight
// paints, the number on its white plate.
//
// Boxes rather than a bitmap, for three reasons: the design asks for
// "low-detail voxel-styled bodies"; the same drawing has to hold up at 150 px
// wide in a roster row and at 500 px wide on the stall turntable; and the
// paint is chosen at runtime from eight swatches, which a bitmap cannot follow
// without eight copies of every body.
//
// The kart is modelled in three dimensions and projected, rather than
// assembled out of flat rectangles. Every part is a box in (x along the kart,
// y up, z across it) and is drawn as its three visible faces -- the near side,
// the lit top, and the end that faces the nose. Parts are given touching
// coordinate ranges, so a wing post starts exactly at the height the engine
// cowl ends and nothing can float: the previous revision's detached nose and
// hanging wing were two boxes that happened to be near each other on screen,
// which is what modelling in three dimensions removes as a possibility.
//
// Light comes from above, which is where the stall's work lights are. Top
// faces are lifted toward the lamps' warm amber, side faces keep the paint,
// end faces fall toward the dark teal the design uses for shadow, and every
// part is shaded a second time by how high it stands, so the floor pan reads
// darker than the engine cowl above it. A soft contact shadow on the ground
// plane, plus a harder patch under each tyre, anchors the kart to whatever it
// is standing on.
//
// Placeholder art. The design's shipping karts are pre-rendered sprite sheets
// at eight angles and three scales for the track view. This is the one
// three-quarter elevation the garage needs, drawn in code, and it is not
// final art.
Item {
  id: kart

  property int body: 0
  property color paint: Theme.paint(0)
  property int number: 7
  property bool showNumber: true
  // Dims the whole kart without changing its hues.
  property real dim: 1.0
  property bool shadow: true

  readonly property real vbW: 132
  readonly property real vbH: 64

  // The projection. A point (x, y, z) lands at
  //   view x = originX + x + z * depthX
  //   view y = groundLine - y - z * depthY
  // so +z runs away from the viewer, up and to the right, and the ground
  // plane y = 0 is a sheared parallelogram rather than a line.
  readonly property real depthX: 0.36
  readonly property real depthY: 0.26
  readonly property real modelX: 5
  readonly property real groundLine: 54

  // Where the kart meets the floor, as a fraction of the sprite's height:
  // the middle of the contact shadow, not the near tyre, so a kart placed by
  // this number sits on a turntable rather than in front of it.
  readonly property real groundFraction: (groundLine - 17 * depthY) / vbH

  readonly property real unit: Math.min(width / vbW, height / vbH)
  readonly property real originX: (width - vbW * unit) / 2
  readonly property real originY: (height - vbH * unit) / 2

  implicitWidth: 264
  implicitHeight: 128

  // Per-body geometry, in model units. One table is what makes six
  // silhouettes six blocks of data rather than six drawing routines. Every
  // range is chosen to touch its neighbour: `noseSteps` each begin where the
  // last ended, the wing posts begin at `cowlY`, and the floor pan spans from
  // behind the rear axle to under the nose.
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
        plate: { x0: 44, x1: 67, y0: 7, y1: 17.2 } },
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
        plate: { x0: 42, x1: 64, y0: 6, y1: 14.6 } },
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
        plate: { x0: 44, x1: 66, y0: 7.5, y1: 18 } },
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
        plate: { x0: 46, x1: 68, y0: 12.5, y1: 22 } },
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
        plate: { x0: 52, x1: 68, y0: 7, y1: 16.2 } },
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
        plate: { x0: 46, x1: 68, y0: 6.5, y1: 16.2 } }
    ]
    return table[i]
  }

  readonly property var geometry: spec(body)

  // The number plate's rectangle on screen. The plate is painted on the near
  // face of the side pod, which is a plane of constant z, so it projects to
  // an upright rectangle and the digits can be real text on top of it.
  readonly property real plateX: originX + (modelX + geometry.plate.x0 + geometry.bodyZ0 * depthX) * unit
  readonly property real plateY: originY + (groundLine - geometry.plate.y1 - geometry.bodyZ0 * depthY) * unit
  readonly property real plateW: (geometry.plate.x1 - geometry.plate.x0) * unit
  readonly property real plateH: (geometry.plate.y1 - geometry.plate.y0) * unit

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
      var u = kart.unit

      // ------------------------------------------------------- projection
      function sx(x, z) { return kart.originX + (kart.modelX + x + z * kart.depthX) * u }
      function sy(y, z) { return kart.originY + (kart.groundLine - y - z * kart.depthY) * u }

      // Polygons are stroked with their own fill as well as filled, which
      // widens each face by half a pixel and closes the hairline seams that
      // fractional coordinates would otherwise leave between two faces of the
      // same solid.
      function poly(points, fill) {
        ctx.fillStyle = fill
        ctx.strokeStyle = fill
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(points[0][0], points[0][1])
        for (var i = 1; i < points.length; i++)
          ctx.lineTo(points[i][0], points[i][1])
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
      }

      // ----------------------------------------------------------- colour
      var warm = Qt.rgba(1.0, 0.82, 0.55, 1)      // the stall's work lights
      var cool = Qt.rgba(0.07, 0.20, 0.24, 1)     // the design's dark teal

      function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
      }
      function gain(c, k) {
        return Qt.rgba(Math.min(1, c.r * k), Math.min(1, c.g * k),
                       Math.min(1, c.b * k), 1)
      }
      // How much of the lamps a part standing this high catches. Low parts
      // sit in the kart's own shadow; the highest parts are almost in the
      // lamp. This is the falloff, and it is what stops the paint reading as
      // one flat fill.
      function key(height) {
        var t = Math.max(0, Math.min(1, height / 38))
        return 0.74 + 0.26 * t
      }

      // The three faces of a solid, given its base colour and its height.
      function faces(c, height) {
        var k = key(height)
        return {
          top: mix(gain(c, 1.06 + 0.30 * k), warm, 0.10 + 0.16 * k),
          front: mix(gain(c, 0.62 + 0.38 * k), cool, 0.10),
          end: mix(gain(c, 0.40 + 0.22 * k), cool, 0.34)
        }
      }

      // Bodywork takes the lamps; the chassis, the seat and the cage are a
      // cool grey given by hand, because pushing a near-black toward a warm
      // amber turns it tan and the kart grows wooden parts.
      var paintFace = faces(kart.paint, 16)
      var chassisFace = { top: "#3f4657", front: "#232936", end: "#141821" }
      var darkFace = { top: "#2c3243", front: "#1a1f2a", end: "#0e1118" }
      var deep = faces(gain(kart.paint, 0.66), 12)
      var glassFace = { top: "#3f8b98", front: "#215a66", end: "#12333c" }

      // -------------------------------------------------------- primitives
      // One solid. `yA` is the top at x0 and `yB` the top at x1, so a nose
      // section is the same call as a box with a slope on it.
      function solid(x0, x1, y0, yA, yB, z0, z1, f) {
        // The end that faces the nose.
        poly([[sx(x1, z0), sy(y0, z0)], [sx(x1, z1), sy(y0, z1)],
              [sx(x1, z1), sy(yB, z1)], [sx(x1, z0), sy(yB, z0)]], f.end)
        // The top, toward the lamps.
        poly([[sx(x0, z0), sy(yA, z0)], [sx(x1, z0), sy(yB, z0)],
              [sx(x1, z1), sy(yB, z1)], [sx(x0, z1), sy(yA, z1)]], f.top)
        // The near side, facing the viewer.
        poly([[sx(x0, z0), sy(y0, z0)], [sx(x1, z0), sy(y0, z0)],
              [sx(x1, z0), sy(yB, z0)], [sx(x0, z0), sy(yA, z0)]], f.front)
      }
      function box(x0, x1, y0, y1, z0, z1, f) {
        solid(x0, x1, y0, y1, y1, z0, z1, f)
      }

      function disc(cx, cy, r, fill) {
        ctx.fillStyle = fill
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, Math.PI * 2, false)
        ctx.fill()
      }

      // A tyre: the far face, a barrel of interpolated discs whose banding
      // reads as tread, then the near face with its sidewall and rim.
      function tyre(x, r, z0, z1) {
        var nearX = sx(x, z0), nearY = sy(r, z0)
        var farX = sx(x, z1), farY = sy(r, z1)
        var rp = r * u
        disc(farX, farY, rp, "#0a0c10")
        var steps = Math.max(6, Math.round(12 * Math.min(2, u)))
        for (var i = steps - 1; i >= 0; i--) {
          var t = i / steps
          disc(farX + (nearX - farX) * (1 - t), farY + (nearY - farY) * (1 - t), rp,
               (i % 3 === 0) ? "#101319" : "#1a1e26")
        }
        // Near face: tread edge, sidewall, rim, hub.
        disc(nearX, nearY, rp, "#2a2f39")
        disc(nearX + rp * 0.06, nearY + rp * 0.07, rp * 0.93, "#13161d")
        disc(nearX, nearY, rp * 0.66, "#080a0e")
        disc(nearX - rp * 0.03, nearY - rp * 0.05, rp * 0.52, "#7c8598")
        disc(nearX, nearY, rp * 0.46, "#4a5164")
        // Five lug bolts, so the rim is a wheel and not a washer.
        for (var b = 0; b < 5; b++) {
          var ang = b * Math.PI * 2 / 5 - Math.PI / 2
          disc(nearX + Math.cos(ang) * rp * 0.28, nearY + Math.sin(ang) * rp * 0.28,
               Math.max(0.7, rp * 0.075), "#20242e")
        }
        disc(nearX, nearY, Math.max(1, rp * 0.16), "#9aa3b6")
      }

      // Where a tyre meets the floor, and how dark the patch under it is.
      function patch(x, r, z0, z1) {
        var cx = (sx(x, z0) + sx(x, z1)) / 2
        var cy = (sy(0, z0) + sy(0, z1)) / 2
        ctx.save()
        ctx.translate(cx, cy)
        ctx.scale(1, 0.34)
        var grad = ctx.createRadialGradient(0, 0, 0, 0, 0, r * u * 1.5)
        grad.addColorStop(0, Qt.rgba(0, 0, 0, 0.60))
        grad.addColorStop(1, Qt.rgba(0, 0, 0, 0))
        ctx.fillStyle = grad
        ctx.beginPath()
        ctx.arc(0, 0, r * u * 1.5, 0, Math.PI * 2, false)
        ctx.fill()
        ctx.restore()
      }

      ctx.globalAlpha = Math.max(0, Math.min(1, kart.dim))

      // ---------------------------------------------------- contact shadow
      if (kart.shadow) {
        var midZ = (g.nearZ0 + g.farZ1) / 2
        var cx0 = sx(g.rearX - g.rearR * 1.5, midZ)
        var cx1 = sx(g.frontX + g.frontR * 1.5, midZ)
        var scx = (cx0 + cx1) / 2
        var scy = sy(0, midZ)
        var srx = (cx1 - cx0) / 2
        ctx.save()
        ctx.translate(scx, scy)
        ctx.scale(1, 0.26)
        var pool = ctx.createRadialGradient(0, 0, 0, 0, 0, srx)
        pool.addColorStop(0, Qt.rgba(0, 0, 0, 0.55))
        pool.addColorStop(0.6, Qt.rgba(0, 0, 0, 0.30))
        pool.addColorStop(1, Qt.rgba(0, 0, 0, 0))
        ctx.fillStyle = pool
        ctx.beginPath()
        ctx.arc(0, 0, srx, 0, Math.PI * 2, false)
        ctx.fill()
        ctx.restore()
        patch(g.rearX, g.rearR, g.nearZ0, g.farZ1)
        patch(g.frontX, g.frontR, g.nearZ0, g.farZ1)
        if (g.dualRear)
          patch(g.rearX + g.rearR * 1.55, g.rearR, g.nearZ0, g.farZ1)
      }

      // ------------------------------------------------------- far wheels
      tyre(g.rearX, g.rearR, g.farZ0, g.farZ1)
      if (g.dualRear)
        tyre(g.rearX + g.rearR * 1.55, g.rearR * 0.92, g.farZ0, g.farZ1)
      tyre(g.frontX, g.frontR, g.farZ0, g.farZ1)

      // ------------------------------------------------------- engine cowl
      box(g.cowlX0, g.cowlX1, g.panY0, g.cowlY, g.bodyZ0 + 3, g.bodyZ1 - 3, deep)
      // Air intake slots on the cowl's near flank.
      for (var v = 0; v < 3; v++)
        box(g.cowlX0 + 3 + v * 5, g.cowlX0 + 5.4 + v * 5,
            g.cowlY - 8, g.cowlY - 2.5, g.bodyZ0 + 2.4, g.bodyZ0 + 3, chassisFace)

      // -------------------------------------------- rear wing and its posts
      // The posts start at exactly the height the engine cowl ends, so the
      // wing is carried by the kart rather than hovering over it.
      if (g.wing) {
        // The wing is measured off the engine cowl, never given absolute
        // coordinates: its posts stand inside the cowl's own footprint and
        // start one unit below the cowl's top face, so there is no height at
        // which the assembly can come away from the kart.
        var wingX0 = g.cowlX0 - g.wing.back
        var wingX1 = wingX0 + g.wing.len
        var wingY0 = g.cowlY + g.wing.rise
        var wingY1 = wingY0 + 3.4
        var postX = g.cowlX0 + 3
        var wz0 = g.bodyZ0 + 5
        var wz1 = g.bodyZ1 - 5
        if (g.wing.rise > 2) {
          box(postX, postX + 4.5, g.cowlY - 1, wingY0, wz0, wz0 + 4.5, chassisFace)
          box(postX, postX + 4.5, g.cowlY - 1, wingY0, wz1 - 4.5, wz1, chassisFace)
        }
        // A second, shorter plane below the first: what makes the
        // prototype's tail read as a different kart from the sprinter's.
        if (g.wing.deck > 0)
          box(wingX0 + 3, wingX1 - 3, wingY0 - g.wing.deck,
              wingY0 - g.wing.deck + 2.6, g.bodyZ0 + 1, g.bodyZ1 - 1, deep)
        // One plane, the full width of the body and no wider. End plates
        // were tried and removed: at roster size they broke into loose bars
        // beside the wing instead of reading as its turned-up tips.
        box(wingX0, wingX1, wingY0, wingY1, g.bodyZ0 - 1, g.bodyZ1 + 1, paintFace)
      }

      // -------------------------------------------------- seat and roll bar
      var seatZ0 = g.bodyZ0 + 6
      var seatZ1 = g.bodyZ1 - 6
      box(g.seatX0, g.seatX1, g.panY1, g.seatY, seatZ0, seatZ1, chassisFace)
      if (g.headrest)
        box(g.seatX0 - 2, g.seatX0 + 6, g.seatY, g.seatY + 4.5, seatZ0 + 1, seatZ1 - 1, deep)
      if (g.hoop) {
        var hy = g.seatY + 7
        box(g.seatX0 - 3, g.seatX0 + 0.5, g.seatY - 6, hy, seatZ0, seatZ0 + 3.5, chassisFace)
        box(g.seatX0 - 3, g.seatX0 + 0.5, g.seatY - 6, hy, seatZ1 - 3.5, seatZ1, chassisFace)
        box(g.seatX0 - 3, g.seatX1 + 2, hy - 3.5, hy, seatZ0, seatZ1, chassisFace)
        box(g.seatX1 - 1, g.seatX1 + 2, g.podY1, hy - 3.5, seatZ0, seatZ0 + 3, chassisFace)
        box(g.seatX1 - 1, g.seatX1 + 2, g.podY1, hy - 3.5, seatZ1 - 3, seatZ1, chassisFace)
      }

      // ----------------------------------------------------- steering wheel
      // A column off the bulkhead and a rim above it: the one part that says
      // at a glance which end a child would sit in.
      if (g.steering) {
        var colZ0 = (g.bodyZ0 + g.bodyZ1) / 2 - 2.2
        box(g.steerX, g.steerX + 4, g.podY1 - 2, g.steerY - 1, colZ0, colZ0 + 4.4, chassisFace)
        var wcx = sx(g.steerX + 2, colZ0 + 2.2)
        var wcy = sy(g.steerY + 1.4, colZ0 + 2.2)
        var wrx = 5.6 * u
        ctx.save()
        ctx.translate(wcx, wcy)
        ctx.scale(1, 0.46)
        ctx.lineWidth = Math.max(1.4, 2.6 * u)
        ctx.strokeStyle = "#20242e"
        ctx.beginPath()
        ctx.arc(0, 0, wrx, 0, Math.PI * 2, false)
        ctx.stroke()
        ctx.restore()
        // Rim highlight along the top, and the two spokes.
        ctx.save()
        ctx.translate(wcx, wcy)
        ctx.scale(1, 0.46)
        ctx.lineWidth = Math.max(1, 1.3 * u)
        ctx.strokeStyle = "#5b6478"
        ctx.beginPath()
        ctx.arc(0, 0, wrx, Math.PI * 1.08, Math.PI * 1.92, false)
        ctx.stroke()
        ctx.restore()
        ctx.fillStyle = "#2b303c"
        ctx.fillRect(wcx - wrx, wcy - Math.max(0.8, 1.1 * u), wrx * 2, Math.max(1.6, 2.2 * u))
        disc(wcx, wcy, Math.max(1.2, 2.2 * u), "#6b7488")
      }

      // ------------------------------------------- floor pan, pod, and nose
      box(g.panX0, g.panX1, g.panY0, g.panY1, g.bodyZ0 + 1, g.bodyZ1 - 1, chassisFace)
      box(g.podX0, g.podX1, g.panY0, g.podY1, g.bodyZ0, g.bodyZ1, paintFace)
      for (var n = 0; n < g.noseSteps.length; n++) {
        var st = g.noseSteps[n]
        solid(st.x0, st.x1, g.panY0, st.yA, st.yB, st.z0, st.z1, paintFace)
      }
      if (g.frontWing) {
        var fw = g.frontWing
        box(fw.x0, fw.x1, fw.y0, fw.y1, g.bodyZ0 - 4, g.bodyZ1 + 4, deep)
        box(fw.x0 + 2, fw.x1 - 1, fw.y0, fw.y1 + 4, g.bodyZ1 + 2.5, g.bodyZ1 + 4, paintFace)
        box(fw.x0 + 2, fw.x1 - 1, fw.y0, fw.y1 + 4, g.bodyZ0 - 4, g.bodyZ0 - 2.5, paintFace)
      }

      // The flank is given two more values so the paint reads as a body and
      // not as one plate of colour: a dark sill along the bottom of the pod,
      // and a livery band above it.
      function flank(y0, y1, x1, fill) {
        poly([[sx(g.podX0, g.bodyZ0), sy(y0, g.bodyZ0)],
              [sx(x1, g.bodyZ0), sy(y0, g.bodyZ0)],
              [sx(x1, g.bodyZ0), sy(y1, g.bodyZ0)],
              [sx(g.podX0, g.bodyZ0), sy(y1, g.bodyZ0)]], fill)
      }
      var sillTop = g.panY0 + (g.podY1 - g.panY0) * 0.22
      flank(g.panY0, sillTop, g.podX1 + 8, deep.end)
      var bandY = sillTop + (g.podY1 - sillTop) * 0.12
      flank(bandY, bandY + 1.6, g.podX1 + 6, deep.front)

      // ------------------------------------------------------- near wheels
      tyre(g.rearX, g.rearR, g.nearZ0, g.nearZ1)
      if (g.dualRear)
        tyre(g.rearX + g.rearR * 1.55, g.rearR * 0.92, g.nearZ0, g.nearZ1)
      tyre(g.frontX, g.frontR, g.nearZ0, g.nearZ1)

      // ------------------------------------------- fenders, roof and canopy
      if (g.fenders) {
        box(g.rearX - g.rearR - 2, g.rearX + g.rearR + 2, g.podY1 - 5, g.podY1 + 1.5,
            g.nearZ0 - 1, g.bodyZ1, paintFace)
        box(g.frontX - g.frontR - 2, g.frontX + g.frontR + 2, g.podY1 - 6, g.podY1 - 0.5,
            g.nearZ0 - 1, g.bodyZ1, paintFace)
      }
      if (g.roof) {
        var cabZ0 = g.bodyZ0 + 4
        var cabZ1 = g.bodyZ1 - 4
        box(g.seatX0 - 4, g.seatX0 - 1, g.podY1, g.seatY + 4, cabZ0, cabZ0 + 3, chassisFace)
        box(g.seatX0 - 4, g.seatX0 - 1, g.podY1, g.seatY + 4, cabZ1 - 3, cabZ1, chassisFace)
        box(g.seatX1 + 8, g.seatX1 + 11, g.podY1, g.seatY + 4, cabZ0, cabZ0 + 3, chassisFace)
        box(g.seatX1 + 8, g.seatX1 + 11, g.podY1, g.seatY + 4, cabZ1 - 3, cabZ1, chassisFace)
        box(g.seatX0 - 5, g.seatX1 + 12, g.seatY + 4, g.seatY + 7, cabZ0 - 0.5, cabZ1 + 0.5, deep)
        box(g.seatX0 - 1, g.seatX1 + 8, g.podY1 + 1, g.seatY + 3.5, cabZ0 + 1, cabZ0 + 1.6,
            glassFace)
      }
      if (g.canopy) {
        // The cap is kept inside the canopy's own depth. Given a wider z range
        // it overhung the far side and left a 48 px slot of nothing under its
        // top face, which is the exact fault this revision exists to remove.
        box(g.seatX0 + 1, g.seatX1 + 2, g.podY1 - 1, g.seatY + 6,
            g.bodyZ0 + 4, g.bodyZ1 - 4, glassFace)
        box(g.seatX0 + 1, g.seatX1 + 2, g.seatY + 6, g.seatY + 8,
            g.bodyZ0 + 4, g.bodyZ1 - 4, chassisFace)
      }

      // ------------------------------------------------------- number plate
      if (kart.showNumber) {
        var pz = g.bodyZ0
        var px0 = sx(g.plate.x0, pz), px1 = sx(g.plate.x1, pz)
        var py0 = sy(g.plate.y1, pz), py1 = sy(g.plate.y0, pz)
        ctx.fillStyle = "#0b0d12"
        ctx.fillRect(px0 - u, py0 - u, (px1 - px0) + u * 2, (py1 - py0) + u * 2)
        ctx.fillStyle = "#eef1f7"
        ctx.fillRect(px0, py0, px1 - px0, py1 - py0)
        ctx.fillStyle = "#c2c7d3"
        ctx.fillRect(px0, py1 - Math.max(1, u * 1.4), px1 - px0, Math.max(1, u * 1.4))
      }
      ctx.globalAlpha = 1
    }
  }

  // The digits ride on the painted plate so they use the shell's monospace
  // face instead of being drawn as boxes.
  Text {
    visible: kart.showNumber
    textFormat: Text.PlainText
    text: String(Math.max(1, Math.min(99, kart.number)))
    color: "#0c0e13"
    opacity: kart.dim
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: Math.max(6, Math.round(kart.plateH * 0.80))
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    x: kart.plateX
    y: kart.plateY
    width: kart.plateW
    height: kart.plateH
  }

  onBodyChanged: surface.requestPaint()
  onPaintChanged: surface.requestPaint()
  onShowNumberChanged: surface.requestPaint()
  onDimChanged: surface.requestPaint()
  onUnitChanged: surface.requestPaint()
  onShadowChanged: surface.requestPaint()
}
