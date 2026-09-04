import QtQuick
import "../"
import "CarMeta.js" as CarMeta

// The stall: the garage bay the kart stands in. Drawn in a 1200 x 560 view
// box and scaled to the panel it is given, so the same scene composes at
// 1366x768 and at 2560x1440 without reflowing.
//
// The design's motif list is the brief for this scene -- roller door, tire
// walls, a diagnostic grid floor, rivets, a WELCOME TO THE PIT terminal.
//
// PROTOTYPE "Golden Hour at the Pit". The roller door is open onto a
// retrowave sunset and the sun through it is now the room's key light: a
// magenta sky, a low cream sun off-centre right, hills in silhouette, and
// the bay lit by the door -- pink bounce on the floor and the far wall that
// falls off with distance, purple shadows where the design's teal ones were.
// The amber work lights stay on as the warm, local counterpoint. The room's
// neutrals go from cool blue-grey to the bar's near-black purple; teal is
// kept for the door frame only. Geometry, the camera and the turntable are
// exactly what they were: only light and palette change.
//
// Placeholder art, drawn in code. It exists so the garage's composition can
// be judged now; a painted or rendered bay replaces it behind the same
// interface.
Item {
  id: stall

  readonly property real vbW: 1200
  readonly property real vbH: 560
  // Cover, not fit: the bay fills the panel and spills over its edges rather
  // than sitting in letterbox bars. The vertical bias keeps the work lights
  // and the door in frame and lets the empty floor be the part that is cut.
  property real cornerRadius: 0
  readonly property real unit: Math.max(width / vbW, height / vbH)
  readonly property real originX: (width - vbW * unit) / 2
  readonly property real originY: (height - vbH * unit) * 0.15

  // Where a kart stands: the centre of the turntable, in view-box units.
  // The turntable was moved right and taken in from a 322-unit radius to 248
  // so that the bottom-left corner of the bay is bare floor: round one parked
  // the KART BODY stepper on the dais and the amber rim grazed its edge.
  readonly property real daisX: 600
  readonly property real daisY: 372

  // How wide the kart standing here is drawn, in view-box units. Garage.qml
  // reads the hero sprite's width from here rather than repeating a number,
  // because the turntable's size is derived from it below: the plinth and
  // the thing on it are one scale, set once.
  readonly property real kartWidth: 486
  // View-box units per model unit of the kart's own space. The v1 live
  // sprite drew into a 132-unit-wide view box, and the dais below is still
  // derived from that model space so the plinth's size and pitch are what
  // the critic measured and accepted; the car standing on it is now a sheet
  // cell (CarSprite), placed by its contact point at `daisX`, `daisY`.
  readonly property real kartToStall: kartWidth / 132

  // ------------------------------------------------- ONE CAMERA, ROUND SIX
  //
  // There is no ellipse constant here. `daisGroundR` is the only art choice
  // on this plinth -- how many model units of floor the turntable covers --
  // and its projection comes from Theme.groundEllipse, the camera the v1
  // live sprite projected every face through. (The history of why is in the
  // round-six notes on Theme.groundEllipse.)
  //
  // `daisCy` is the projected ellipse's CENTRE, which is not the kart's
  // contact point: the near arc of a floor circle is closer to the camera
  // than the far arc, so it swings further down than the far arc swings up.
  // `daisY` stays the contact point, because that is what Garage.qml stands
  // the kart on.
  readonly property real daisGroundR: 53.7
  readonly property var daisFit: Theme.groundEllipse(daisGroundR)
  readonly property real daisRadius: daisFit.a * kartToStall
  // The dais is a solid plinth, not a painted disc: `daisRy` is the top
  // face's minor axis and `daisRim` the height of the course below it, which
  // is the surface that catches the rim light and carries the kerb.
  readonly property real daisRy: daisFit.b * kartToStall
  readonly property real daisCy: daisY + daisFit.dy * kartToStall
  readonly property real daisRim: 26

  // The door opening, in view-box units. The slats are raised further than
  // the design's night version so that the sky is most of what the opening
  // shows: the bar's frame is 40% sky, and the door is this room's frame.
  //
  // ROUND-7: wider and higher again. The bar puts the sky at 40% of the
  // picture and the sun low and large in it; this room can only show sky
  // through its own opening, so the opening is what had to grow. It went from
  // 350 x 227 view-box units to 386 x 247 -- 32% of the bay's width and, with
  // the horizon still at the same place, 57% of the opening is now sky.
  readonly property real doorX0: 452
  readonly property real doorX1: 838
  readonly property real doorTop: 98
  readonly property real doorSill: 345
  // The horizon sits at 57% of the opening's height, the sun straddles it
  // at 80% of its width -- a little further right than the bar's 68% so it
  // clears the kart's wing and shows between the wing and the nose.
  readonly property real horizonY: 240
  readonly property real sunX: 762
  readonly property real sunR: 62

  // ROUND-7. Where the two pieces of signage sit on the back wall, published
  // as properties because the Canvas draws their cases and the items below
  // draw their copy: two files' worth of numbers agreeing by accident is how
  // a caption ends up half off its own poster. They moved right this round to
  // clear the new corner at x = 118.
  readonly property real termX: 130
  readonly property real termY: 64
  readonly property real posterX: 288
  readonly property real posterY: 60

  function vx(x) { return originX + x * unit }
  function vy(y) { return originY + y * unit }
  function vs(v) { return v * unit }

  clip: true

  Canvas {
    id: scene
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      if (stall.unit <= 0)
        return

      var u = stall.unit

      if (stall.cornerRadius > 0) {
        ctx.beginPath()
        ctx.roundedRect(0, 0, width, height, stall.cornerRadius, stall.cornerRadius)
        ctx.clip()
      }

      function rect(x, y, w, h, fill) {
        ctx.fillStyle = fill
        ctx.fillRect(stall.vx(x), stall.vy(y), w * u, h * u)
      }
      function line(x1, y1, x2, y2, w, stroke) {
        ctx.strokeStyle = stroke
        ctx.lineWidth = Math.max(1, w * u)
        ctx.beginPath()
        ctx.moveTo(stall.vx(x1), stall.vy(y1))
        ctx.lineTo(stall.vx(x2), stall.vy(y2))
        ctx.stroke()
      }
      function ellipse(cx, cy, rx, ry, fill) {
        ctx.save()
        ctx.beginPath()
        ctx.translate(stall.vx(cx), stall.vy(cy))
        ctx.scale(rx * u, ry * u)
        ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
        ctx.restore()
        ctx.fillStyle = fill
        ctx.fill()
      }
      function rgbaOf(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
      }
      function poly(pts, fill) {
        ctx.fillStyle = fill
        ctx.beginPath()
        ctx.moveTo(stall.vx(pts[0][0]), stall.vy(pts[0][1]))
        for (var pi = 1; pi < pts.length; pi++)
          ctx.lineTo(stall.vx(pts[pi][0]), stall.vy(pts[pi][1]))
        ctx.closePath()
        ctx.fill()
      }

      var doorCx = (stall.doorX0 + stall.doorX1) / 2

      // ------------------------------------------------ ROUND-7: the room
      //
      // The one open note against this scene since round five was that "the
      // left wall and shelves are still flat", and it was fair: every prop on
      // that wall was a front-facing rectangle of one tone, with no side, no
      // cast shadow and no rim, on a wall that was itself a flat gradient.
      // Three things fix it, and all three follow the same rule the cars
      // follow -- one key, the sun through the door, low and behind-right.
      //
      //   1. The bay has a CORNER. A left return wall runs from the frame's
      //      edge to a vertical corner at `cornerX`, so the room has two
      //      planes meeting at an angle instead of one backdrop.
      //   2. Every prop on the back wall is a BOX, not a rectangle: the one
      //      side face that turns toward the eye is drawn, and because the
      //      eye and the door are both to the right of these props, that is
      //      the same face the sun lights. So each prop carries a warm edge
      //      on its door side, a cool purple body, and a top face between.
      //   3. Every prop THROWS A SHADOW, on the wall behind it and on the
      //      floor under it, away from the door: down and to the left.
      //
      // `eyeX`/`eyeY` are where the room's own vanishing point is -- the same
      // point the floor grid already converges on, at the height of the
      // camera. `boxProp` pushes a face toward it to get the box's back, so
      // the depth cue is one point for the whole room rather than a per-prop
      // guess.
      var eyeX = 600, eyeY = 268

      // A box standing off the back wall: `t` is how far it comes toward the
      // camera. Returns nothing; it paints, back to front, the side face, the
      // top or bottom face, and the front face.
      function boxProp(x, y, w, h, t, front, side, top, under) {
        var bx0 = x + (eyeX - x) * t
        var bx1 = (x + w) + (eyeX - (x + w)) * t
        var by0 = y + (eyeY - y) * t
        var by1 = (y + h) + (eyeY - (y + h)) * t
        // The side that turns toward the eye. Left of the vanishing point
        // that is the right-hand side, which is also the door's side.
        if (x + w < eyeX)
          poly([[x + w, y], [bx1, by0], [bx1, by1], [x + w, y + h]], side)
        else if (x > eyeX)
          poly([[x, y], [bx0, by0], [bx0, by1], [x, y + h]], side)
        // The horizontal face: the top when the box's top is below the eye,
        // the underside when it is above. They are not the same colour --
        // an underside sees no sky at all, so it takes `under`, which
        // defaults to a third of the front face's value rather than to the
        // top's. Round seven's first pass painted undersides in the top's
        // tone and the shelf boards read as lit from below.
        if (y + h < eyeY)
          poly([[x, y + h], [bx0, by1], [bx1, by1], [x + w, y + h]],
               under !== undefined ? under : Qt.darker(front, 1.9))
        else if (y < eyeY)
          poly([[x, y], [bx0, by0], [bx1, by0], [x + w, y]], top)
        rect(x, y, w, h, front)
      }

      // The shadow a wall prop throws: the same face, sheared down and to the
      // left, drawn before the prop. Purple, never grey -- the ambient in
      // this room is a magenta sky.
      function wallShadow(x, y, w, h, reach, alpha) {
        poly([[x, y + h], [x - reach, y + h + reach * 0.42],
              [x - reach + w, y + h + reach * 0.42], [x + w, y + h]],
             Qt.rgba(0.16, 0.04, 0.13, alpha))
        poly([[x, y], [x - reach * 0.62, y + reach * 0.26],
              [x - reach * 0.62, y + h + reach * 0.26], [x, y + h]],
             Qt.rgba(0.16, 0.04, 0.13, alpha * 0.8))
      }

      // ---------------------------------------------------------- back wall
      // Near-black purple, the bar's ground family, and a shade lighter at
      // the top where the sky's glow reaches the ceiling line.
      var wall = ctx.createLinearGradient(0, stall.vy(0), 0, stall.vy(360))
      wall.addColorStop(0, "#2a1024")
      wall.addColorStop(0.55, "#1e0a1a")
      wall.addColorStop(1, "#150612")
      ctx.fillStyle = wall
      ctx.fillRect(stall.vx(0), stall.vy(0), stall.vs(1200), stall.vs(360))

      // Wall panel seams and rivets. The seam's lit side faces the door, so
      // each seam is a dark groove with a warm hairline on its right lip.
      for (var px = 0; px <= 1200; px += 150) {
        line(px, 0, px, 340, 1, "#341630")
        line(px + 1.4, 0, px + 1.4, 340, 0.8, rgbaOf(Theme.duskRim, 0.12))
        for (var ry = 30; ry < 340; ry += 60) {
          rect(px - 2, ry, 4, 4, "#48213f")
          rect(px + 1, ry, 1, 4, rgbaOf(Theme.duskRim, 0.30))
        }
      }
      line(0, 120, 1200, 120, 1, "#30142c")

      // -------------------------------------------------- left return wall
      // The corner. Its inner face turns toward the door, so it is lit along
      // its length and falls off toward the camera, and the corner edge
      // itself carries the room's brightest warm line outside the opening.
      var cornerX = 118
      var returnWall = ctx.createLinearGradient(stall.vx(0), 0, stall.vx(cornerX), 0)
      returnWall.addColorStop(0, "#120410")
      returnWall.addColorStop(0.55, "#1e0819")
      returnWall.addColorStop(1, "#3a1330")
      ctx.fillStyle = returnWall
      ctx.beginPath()
      ctx.moveTo(stall.vx(-4), stall.vy(-52))
      ctx.lineTo(stall.vx(cornerX), stall.vy(14))
      ctx.lineTo(stall.vx(cornerX), stall.vy(352))
      ctx.lineTo(stall.vx(-4), stall.vy(482))
      ctx.closePath()
      ctx.fill()
      // Two courses of block on the return wall, drawn in its own perspective
      // so the corner reads as a receding plane and not as a painted wedge.
      for (var rc = 0; rc < 5; rc++) {
        var f = rc / 4
        line(-4, -52 + (482 + 52) * f, cornerX, 14 + (352 - 14) * f, 1,
             rgbaOf(Theme.duskShadow, 0.30))
      }
      for (var rv = 1; rv < 3; rv++) {
        var rx = cornerX * rv / 3
        line(rx, -52 + (66 * rv / 3), rx, 482 - (130 * rv / 3), 1,
             rgbaOf(Theme.duskShadow, 0.22))
      }
      // The corner edge, catching the sun, and the skirting where the return
      // wall meets the floor -- a receding line is what tells the eye the two
      // planes are at an angle rather than side by side.
      rect(cornerX - 2.5, 14, 2.5, 338, rgbaOf(Theme.duskRim, 0.62))
      rect(cornerX, 14, 3, 338, "#0e030c")
      poly([[-4, 482], [cornerX, 352], [cornerX, 344], [-4, 466]],
           rgbaOf(Theme.duskShadow, 0.55))
      line(-4, 466, cornerX, 344, 1.4, rgbaOf(Theme.duskRim, 0.20))

      // -------------------------------------------------------- shelf unit
      // A steel rack: two uprights, three boards, and crates on them. Every
      // piece is a box with its door-side face drawn, so the rack has a lit
      // right flank, a dark left one, and a shadow on the wall behind it.
      // ROUND-7 second pass: the rack sits 30 units lower and is 30 shorter
      // than the first pass made it, because the practice poster hangs on the
      // same wall and the first pass ran the top crates up BEHIND it -- a
      // poster cannot be in front of a freestanding rack. The round's own
      // light audit found it: the top crates' door-side flanks measured
      // darker than their far ends, and the reason was the poster covering
      // them.
      var shX = 260, shY = 250, shW = 168, shH = 84
      wallShadow(shX, shY, shW, shH, 26, 0.45)
      rect(shX - 4, shY - 4, shW + 8, shH + 8, "#1a0916")
      // Three boards, and on each of them a run of crates. Every crate is a
      // box: a cool front, a warm door-side flank, a top between the two, and
      // a shadow on the board it stands on. Two crate palettes, so the rack
      // has something in it rather than a row of identical blocks.
      // Offsets are spaced so that every crate's door-side flank is clear of
      // its neighbour: butted crates occlude each other's lit face, which is
      // exactly what the round's own light audit caught on the first pass.
      var crates = [[[4, 42, 32, "#4e4231", "#9a7f4c", "#63553a"],
                     [58, 28, 24, "#3d2c4c", "#74537e", "#4e3a62"],
                     [100, 46, 32, "#5a332f", "#a15c44", "#714038"]],
                    [[4, 32, 26, "#5a332f", "#a15c44", "#714038"],
                     [48, 44, 32, "#3d3a2e", "#6f6a45", "#4c4837"],
                     [106, 36, 22, "#40304e", "#79587f", "#513c64"]],
                    [[4, 48, 32, "#3d3a2e", "#6f6a45", "#4c4837"],
                     [64, 26, 26, "#5a332f", "#a15c44", "#714038"],
                     [102, 40, 30, "#4e4231", "#9a7f4c", "#63553a"]]]
      for (var sh = 0; sh < 3; sh++) {
        var sy2 = shY + sh * 38
        // The board: its front edge is a box, so the top face reads as a
        // shelf you could put something on and the underside as a shadow.
        boxProp(shX, sy2, shW, 8, 0.06, "#4a2742", "#84506a", "#653a56")
        // The lip catches the sun over the door-side third of its length and
        // no further, the same break piece C put in the cars' outline.
        rect(shX + shW * 0.62, sy2, shW * 0.38, 1.6, rgbaOf(Theme.duskRim, 0.40))
        var run = crates[sh]
        for (var ci = 0; ci < run.length; ci++) {
          var cdef = run[ci]
          var cx3 = shX + cdef[0], cw3 = cdef[1], ch3 = cdef[2]
          poly([[cx3, sy2], [cx3 - 11, sy2 + 4.5],
                [cx3 - 11 + cw3, sy2 + 4.5], [cx3 + cw3, sy2]],
               Qt.rgba(0.13, 0.03, 0.11, 0.55))
          boxProp(cx3, sy2 - ch3, cw3, ch3, 0.055, cdef[3], cdef[4], cdef[5])
          // A batten across the face, so a crate reads as a crate.
          rect(cx3 + 3, sy2 - ch3 * 0.62, cw3 - 6, 2.5,
               Qt.rgba(0, 0, 0, 0.30))
          rect(cx3 + cw3 - 1.6, sy2 - ch3, 1.6, ch3, rgbaOf(Theme.duskRim, 0.40))
        }
      }
      // The uprights, drawn last so they stand in front of the boards. They
      // are plain posts, NOT boxes: a post's flank is against the boards
      // beside it and cannot be seen, and drawing one anyway put a 24-unit
      // lit wedge under the crates -- which is what this round's own light
      // audit caught. Only the right-hand post has a face turned to the open
      // room, and only it carries the sun.
      rect(shX - 10, shY - 12, 10, shH + 24, "#2c1527")
      rect(shX - 1.4, shY - 12, 1.4, shH + 24, Qt.rgba(0, 0, 0, 0.35))
      rect(shX + shW, shY - 12, 10, shH + 24, "#331829")
      rect(shX + shW + 8.4, shY - 12, 1.6, shH + 24, rgbaOf(Theme.duskRim, 0.55))

      // ------------------------------------------------------ tool chest
      // The one saturated warm object on this wall, and it keeps its own hue
      // under the sun exactly as the cars do: a red chest reads red, and the
      // warmth is on its door-side flank and on the lip of every drawer.
      var tcX = 130, tcY = 234, tcW = 112, tcH = 108
      wallShadow(tcX, tcY, tcW, tcH, 30, 0.5)
      boxProp(tcX, tcY, tcW, tcH, 0.075, "#5a1f1c", "#a04b32", "#7a2c26")
      for (var dr = 0; dr < 4; dr++) {
        var dy2 = tcY + 14 + dr * 22
        rect(tcX + 6, dy2, tcW - 12, 17, "#481916")
        // The drawer's own top lip, lit, and the shadow it drops.
        rect(tcX + 6, dy2, tcW - 12, 1.6, rgbaOf(Theme.duskRim, 0.42))
        rect(tcX + 6, dy2 + 17, tcW - 12, 2, "#2a0f0e")
        rect(tcX + 28, dy2 + 6, 58, 4, "#b5674a")
      }
      rect(tcX + tcW - 2, tcY, 2, tcH, rgbaOf(Theme.duskRim, 0.55))
      // Its contact shadow on the floor, running toward the camera and left.
      poly([[tcX, 342], [tcX - 40, 372], [tcX + tcW - 16, 372], [tcX + tcW, 342]],
           Qt.rgba(0.13, 0.03, 0.11, 0.55))

      // -------------------------------------------------------- pegboard
      // The strip of wall right of the roller door that the COLOR panel does
      // not cover. Kept dark on purpose: nothing in the corner of the bay
      // should outrank the kart. It is right of the vanishing point, so the
      // face that turns toward the eye is its LEFT one -- which is the face
      // the door lights, and the tools on it catch the sun on the same side.
      boxProp(946, 44, 214, 104, 0.05, "#22101f", "#4a2440", "#33182d")
      rect(946, 44, 214, 4, "#3a1c35")
      rect(946, 44, 2, 104, rgbaOf(Theme.duskRim, 0.40))
      for (var pgx = 954; pgx < 1156; pgx += 12)
        for (var pgy = 56; pgy < 142; pgy += 12)
          rect(pgx, pgy, 2, 2, "#331a2f")
      // A spanner, a hammer and two hooks, as silhouettes, each with the sun
      // on its left edge because the door is left of this wall.
      function tool(x, y, w, h, body) {
        rect(x, y, w, h, body)
        rect(x, y, Math.max(1, w * 0.34), h, rgbaOf(Theme.duskRim, 0.34))
      }
      tool(968, 58, 6, 54, "#4a2e45")
      tool(963, 56, 16, 8, "#4a2e45")
      tool(963, 104, 16, 8, "#4a2e45")
      tool(1000, 58, 7, 40, "#40283c")
      tool(994, 56, 19, 9, "#573a52")
      tool(1036, 58, 5, 30, "#40283c")
      tool(1030, 86, 17, 7, "#4a2e45")
      tool(1074, 58, 5, 44, "#3a2236")
      tool(1068, 58, 17, 6, "#4a2e45")
      tool(1110, 58, 5, 36, "#3a2236")
      tool(1104, 58, 17, 6, "#4a2e45")
      rect(946, 146, 214, 3, "#12060f")

      // ------------------------------------------------------- tire walls
      // Tyres, not slabs: an ellipse for the sidewall, a darker one for the
      // hole, a warm crescent on the door side and a purple pool underneath.
      // A stack of tyres: each one a carcass with a tread band and a wheel
      // face, drawn bottom to top so the one above sits into the one below.
      // The door is to the right of this corner, so the sun lands on the
      // right shoulder of every carcass and the pool under the stack runs
      // away from it, toward the camera and left.
      // A stack of tyres. Each one is a short CYLINDER -- a sidewall band with
      // an elliptical top face on it -- and they are drawn bottom to top so
      // each covers the one below. Round seven's first pass drew them as flat
      // ellipses only, which under this camera read as a stack of plates: a
      // tyre is legible because you can see its side, not its face.
      function tyreStack(x, yBase, count, w) {
        var cx2 = x + w / 2, r2 = w / 2, band = 13, ry2 = 9
        poly([[x + 4, yBase + 13], [x - 28, yBase + 38],
              [x + w - 12, yBase + 38], [x + w - 2, yBase + 13]],
             Qt.rgba(0.12, 0.03, 0.10, 0.6))
        for (var t = 0; t < count; t++) {
          var cy2 = yBase - t * band
          // The sidewall: a band closed at the bottom by half an ellipse, so
          // the carcass has a round bottom rather than a cut edge.
          ellipse(cx2, cy2 + band, r2, ry2, "#150a13")
          rect(x, cy2, w, band, "#150a13")
          // The sun on its door-side shoulder, and the room's purple opposite.
          rect(x + w - 9, cy2, 9, band, "#33192e")
          rect(x + w - 4, cy2, 4, band, rgbaOf(Theme.duskRim, 0.34))
          rect(x, cy2, 7, band, "#0b0409")
          // Tread blocks across the band.
          for (var tb = 0; tb < 9; tb++)
            rect(x + 5 + tb * (w - 14) / 9, cy2 + 2, (w - 14) / 20, band - 4,
                 Qt.rgba(0, 0, 0, 0.22))
          // The top face, and the wheel sunk into it.
          ellipse(cx2, cy2, r2, ry2, "#261423")
          ellipse(cx2 + 4, cy2 - 1, r2 - 7, ry2 - 2.5, "#341d31")
          ellipse(cx2 + 1, cy2 + 0.5, r2 * 0.42, ry2 * 0.42, "#452a41")
          ellipse(cx2 + 1, cy2 + 0.5, r2 * 0.22, ry2 * 0.24, "#0c0409")
        }
      }
      // Only the left stack is drawn: the two on the right were under the
      // opaque COLOR panel on every screen at every size.
      tyreStack(14, 322, 4, 92)

      // ------------------------------------------- the door's light, wall
      // Magenta bounce on the wall, centred on the opening and dying with
      // distance from it. Painted over the wall and its props and UNDER the
      // sky, so the sky is the one pure thing in the room and everything
      // else is lit by it. The radius is most of the bay: the sun is not a
      // lamp, and the far corners are dim rather than dark.
      var wallGlow = ctx.createRadialGradient(stall.vx(doorCx), stall.vy(stall.horizonY), stall.vs(120),
                                              stall.vx(doorCx), stall.vy(stall.horizonY), stall.vs(760))
      wallGlow.addColorStop(0, rgbaOf(Theme.duskSkyHot, 0.50))
      wallGlow.addColorStop(0.28, rgbaOf(Theme.duskSkyMid, 0.30))
      wallGlow.addColorStop(0.62, rgbaOf(Theme.duskSkyTop, 0.12))
      wallGlow.addColorStop(1, rgbaOf(Theme.duskSkyTop, 0))
      ctx.fillStyle = wallGlow
      ctx.fillRect(stall.vx(0), stall.vy(0), stall.vs(1200), stall.vs(360))

      // ------------------------------------------------------- roller door
      // The sunset beyond the open door. Everything in here is clipped to
      // the opening, so the sun's glow cannot leak onto the wall as a disc:
      // the wall gets its light from the bounce above, as a wall would.
      ctx.save()
      ctx.beginPath()
      ctx.rect(stall.vx(stall.doorX0), stall.vy(stall.doorTop),
               stall.vs(stall.doorX1 - stall.doorX0), stall.vs(stall.doorSill - stall.doorTop))
      ctx.clip()

      // The sky: the brief's four-stop gradient, top of the opening to the
      // horizon. It is never black.
      var sky = ctx.createLinearGradient(0, stall.vy(stall.doorTop), 0, stall.vy(stall.horizonY))
      sky.addColorStop(0, Theme.duskSkyTop)
      sky.addColorStop(0.42, Theme.duskSkyMid)
      sky.addColorStop(0.78, Theme.duskSkyHot)
      sky.addColorStop(1, Theme.duskHorizon)
      ctx.fillStyle = sky
      ctx.fillRect(stall.vx(stall.doorX0), stall.vy(stall.doorTop),
                   stall.vs(stall.doorX1 - stall.doorX0), stall.vs(292 - stall.doorTop))

      // Streaky cloud bands: soft horizontal shapes, one a shade lighter
      // than the sky behind it and two a shade darker, thin, and stretched
      // toward the sun so they read as lit from it.
      function cloud(cx, cy, w, h, fill) {
        ctx.save()
        ctx.beginPath()
        ctx.translate(stall.vx(cx), stall.vy(cy))
        ctx.scale(w * u, h * u)
        ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
        ctx.restore()
        ctx.fillStyle = fill
        ctx.fill()
      }
      cloud(600, 148, 150, 5, rgbaOf(Theme.duskSkyTop, 0.55))
      cloud(700, 166, 120, 3.5, rgbaOf(Theme.duskSkyTop, 0.45))
      cloud(560, 190, 130, 4, rgbaOf(Theme.duskHorizon, 0.55))
      cloud(720, 212, 160, 4.5, rgbaOf(Theme.duskSun, 0.32))
      cloud(590, 228, 110, 3, rgbaOf(Theme.duskSun, 0.26))

      // The sun's glow: wide, horizon-pink, and it reaches the whole opening.
      var halo = ctx.createRadialGradient(stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR * 0.8),
                                          stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR * 3.4))
      halo.addColorStop(0, rgbaOf(Theme.duskSunEdge, 0.85))
      halo.addColorStop(0.35, rgbaOf(Theme.duskHorizon, 0.55))
      halo.addColorStop(1, rgbaOf(Theme.duskHorizon, 0))
      ctx.fillStyle = halo
      ctx.fillRect(stall.vx(stall.doorX0), stall.vy(stall.doorTop),
                   stall.vs(stall.doorX1 - stall.doorX0), stall.vs(stall.doorSill - stall.doorTop))

      // The sun: a big low disc, cream at the core going to orange at the
      // limb, sitting on the horizon. Then the genre's signature: horizontal
      // cut lines through its lower half, thickening downward, in the sky's
      // own horizon colour.
      var sunG = ctx.createRadialGradient(stall.vx(stall.sunX), stall.vy(stall.horizonY - 6), 0,
                                          stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR))
      sunG.addColorStop(0, "#fbe6a0")
      sunG.addColorStop(0.55, Theme.duskSun)
      sunG.addColorStop(1, Theme.duskSunEdge)
      ctx.fillStyle = sunG
      ctx.beginPath()
      ctx.arc(stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR), 0, Math.PI * 2, false)
      ctx.fill()
      var cutY = stall.horizonY - stall.sunR * 0.02
      for (var cut = 0; cut < 6; cut++) {
        var cw = 1.2 + cut * 1.1
        rect(stall.sunX - stall.sunR - 2, cutY - cw * 0.5, stall.sunR * 2 + 4, cw, Theme.duskHorizon)
        cutY += 5 + cut * 1.6
      }

      // Hills: two silhouette layers, the far one lighter (atmospheric
      // perspective), both rising a little above the horizon so the sun's
      // lower limb sets behind them. A skyline is a polyline, not a curve
      // -- low-poly is the medium.
      function hills(pts, yBase, fill) {
        ctx.fillStyle = fill
        ctx.beginPath()
        ctx.moveTo(stall.vx(pts[0][0]), stall.vy(yBase))
        for (var hi = 0; hi < pts.length; hi++)
          ctx.lineTo(stall.vx(pts[hi][0]), stall.vy(pts[hi][1]))
        ctx.lineTo(stall.vx(pts[pts.length - 1][0]), stall.vy(yBase))
        ctx.closePath()
        ctx.fill()
      }
      hills([[460, 252], [520, 234], [580, 242], [640, 228], [700, 238], [760, 226],
             [800, 236], [830, 230]], 300, Theme.duskHillFar)
      hills([[460, 274], [530, 256], [600, 266], [660, 252], [720, 264], [790, 250],
             [830, 260]], 320, Theme.duskHillNear)

      // The near ground: the bar's near-black purple, a hard floor line,
      // and a warm glint under the sun where the road catches it.
      var groundG = ctx.createLinearGradient(0, stall.vy(292), 0, stall.vy(stall.doorSill))
      groundG.addColorStop(0, "#4a1832")
      groundG.addColorStop(1, Theme.duskGround)
      ctx.fillStyle = groundG
      ctx.fillRect(stall.vx(stall.doorX0), stall.vy(292),
                   stall.vs(stall.doorX1 - stall.doorX0), stall.vs(stall.doorSill - 292))
      rect(stall.doorX0, 291, stall.doorX1 - stall.doorX0, 2, "#6a2a4c")
      var glint = ctx.createLinearGradient(stall.vx(stall.sunX - 90), 0, stall.vx(stall.sunX + 90), 0)
      glint.addColorStop(0, rgbaOf(Theme.duskSun, 0))
      glint.addColorStop(0.5, rgbaOf(Theme.duskSun, 0.55))
      glint.addColorStop(1, rgbaOf(Theme.duskSun, 0))
      ctx.fillStyle = glint
      for (var gl = 0; gl < 4; gl++)
        ctx.fillRect(stall.vx(stall.sunX - 90 + gl * 8), stall.vy(298 + gl * 9),
                     stall.vs(180 - gl * 16), stall.vs(1.6 + gl * 0.5))
      // A neon grid on the yard outside, converging on the sun: the design's
      // diagnostic grid, in the sky's own pink.
      ctx.globalAlpha = 0.30
      for (var yg = -6; yg <= 6; yg++)
        line(stall.sunX + yg * 20, 292, stall.sunX + yg * 110, stall.doorSill + 10, 1, Theme.duskNeon)
      var yardRows = [300, 311, 326, 345]
      for (var yr = 0; yr < yardRows.length; yr++)
        line(stall.doorX0, yardRows[yr], stall.doorX1, yardRows[yr], 1, Theme.duskNeon)
      ctx.globalAlpha = 1
      ctx.restore()

      // The raised door: slats and the bottom rail, now rolled higher than
      // the night version so the sky has room. Their undersides catch the
      // sky, so the highlight on each slat is pink rather than grey.
      var slat = ctx.createLinearGradient(0, stall.vy(56), 0, stall.vy(stall.doorTop))
      slat.addColorStop(0, "#3a1a34")
      slat.addColorStop(1, "#22101f")
      ctx.fillStyle = slat
      ctx.fillRect(stall.vx(444), stall.vy(44), stall.vs(402), stall.vs(stall.doorTop - 44))
      for (var sy = 50; sy < stall.doorTop - 2; sy += 11) {
        line(446, sy, 844, sy, 1.6, "#150812")
        line(446, sy + 3, 844, sy + 3, 1, "#5a2a50")
      }
      rect(444, stall.doorTop - 3, 402, 7, "#4a2444")
      rect(444, stall.doorTop + 2, 402, 2, rgbaOf(Theme.duskHorizon, 0.55))
      // Door frame uprights: the design's teal, kept here and nowhere else in
      // the room, with a bright teal edge on the side that faces the sky.
      rect(438, 38, 8, 308, Theme.tealDeep)
      rect(838, 38, 8, 308, Theme.tealDeep)
      rect(444, 38, 2, 308, rgbaOf(Theme.teal, 0.75))
      rect(838, 38, 2, 308, rgbaOf(Theme.teal, 0.75))
      rect(438, 34, 408, 6, Theme.tealDeep)

      // ------------------------------------------------------------ floor
      var floor = ctx.createLinearGradient(0, stall.vy(340), 0, stall.vy(560))
      floor.addColorStop(0, "#2c1026")
      floor.addColorStop(0.45, "#1a0917")
      floor.addColorStop(1, "#0e040c")
      ctx.fillStyle = floor
      ctx.fillRect(stall.vx(0), stall.vy(340), stall.vs(1200), stall.vs(220))

      // The door's light on the floor: the opening, thrown across the bay
      // toward the camera as a widening pool that is hottest at the sill.
      // This is the room's key on the ground plane -- what the kart's long
      // shadow is cut out of.
      var spill = ctx.createLinearGradient(0, stall.vy(stall.doorSill), 0, stall.vy(560))
      spill.addColorStop(0, rgbaOf(Theme.duskHorizon, 0.62))
      spill.addColorStop(0.25, rgbaOf(Theme.duskSkyHot, 0.42))
      spill.addColorStop(0.7, rgbaOf(Theme.duskSkyMid, 0.14))
      spill.addColorStop(1, rgbaOf(Theme.duskSkyTop, 0))
      ctx.fillStyle = spill
      ctx.beginPath()
      ctx.moveTo(stall.vx(stall.doorX0), stall.vy(stall.doorSill))
      ctx.lineTo(stall.vx(stall.doorX1), stall.vy(stall.doorSill))
      ctx.lineTo(stall.vx(stall.doorX1 + 260), stall.vy(560))
      ctx.lineTo(stall.vx(stall.doorX0 - 330), stall.vy(560))
      ctx.closePath()
      ctx.fill()
      // And the wider, weaker bounce that reaches the rest of the floor.
      var floorGlow = ctx.createRadialGradient(stall.vx(doorCx), stall.vy(stall.doorSill), 0,
                                               stall.vx(doorCx), stall.vy(stall.doorSill), stall.vs(700))
      floorGlow.addColorStop(0, rgbaOf(Theme.duskSkyHot, 0.22))
      floorGlow.addColorStop(0.5, rgbaOf(Theme.duskSkyMid, 0.08))
      floorGlow.addColorStop(1, rgbaOf(Theme.duskSkyTop, 0))
      ctx.fillStyle = floorGlow
      ctx.fillRect(stall.vx(0), stall.vy(340), stall.vs(1200), stall.vs(220))

      // Hazard stripe along the back of the bay: the design's amber, kept.
      ctx.save()
      ctx.beginPath()
      ctx.rect(stall.vx(0), stall.vy(340), stall.vs(1200), stall.vs(14))
      ctx.clip()
      for (var hx = -40; hx < 1240; hx += 34) {
        ctx.fillStyle = "#8a6a19"
        ctx.beginPath()
        ctx.moveTo(stall.vx(hx), stall.vy(354))
        ctx.lineTo(stall.vx(hx + 17), stall.vy(354))
        ctx.lineTo(stall.vx(hx + 34), stall.vy(340))
        ctx.lineTo(stall.vx(hx + 17), stall.vy(340))
        ctx.closePath()
        ctx.fill()
      }
      ctx.restore()
      rect(0, 338, 1200, 2, "#3e1a38")

      // The diagnostic grid: lines converging on a vanishing point, in the
      // sky's pink at low alpha so the floor keeps the neon cue without the
      // grid outranking anything standing on it.
      ctx.globalAlpha = 0.22
      for (var gx = -1400; gx <= 2600; gx += 100)
        line(600 + (gx - 600) * 0.16, 344, gx, 566, 1, Theme.duskNeon)
      var depth = [346, 356, 370, 390, 418, 456, 506, 566]
      for (var d = 0; d < depth.length; d++)
        line(0, depth[d], 1200, depth[d], 1, Theme.duskNeon)
      ctx.globalAlpha = 1

      // ------------------------------------------------------------- dais
      var dx0 = stall.daisX
      var dr = stall.daisRadius
      var dcy = stall.daisCy
      var dry = stall.daisRy
      var rim = stall.daisRim

      // Every ring on this plinth is a floor circle put through the kart's
      // camera. `ring(k)` is the circle of k times the turntable's radius.
      function ring(k) {
        var e = Theme.groundEllipse(stall.daisGroundR * k)
        return { rx: e.a * stall.kartToStall, ry: e.b * stall.kartToStall,
                 cy: stall.daisY + e.dy * stall.kartToStall }
      }

      function daisPoint(angle, drop) {
        return [stall.vx(dx0 + Math.cos(angle) * dr),
                stall.vy(dcy + Math.sin(angle) * dry + drop)]
      }

      // The plinth's own shadow, thrown by the sun through the door: away
      // from the door, which is up and right of it, so toward the camera
      // and to the left. Purple, because the ambient is a magenta sky.
      var dsh = ring(1.14)
      ctx.save()
      ctx.translate(stall.vx(dx0 - 34), stall.vy(dsh.cy + rim + 16))
      ctx.scale(dsh.rx * u, dsh.ry * u)
      var daisShadow = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      daisShadow.addColorStop(0, Qt.rgba(0.10, 0.02, 0.09, 0.66))
      daisShadow.addColorStop(0.72, Qt.rgba(0.10, 0.02, 0.09, 0.36))
      daisShadow.addColorStop(1, Qt.rgba(0.10, 0.02, 0.09, 0))
      ctx.fillStyle = daisShadow
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.fill()
      ctx.restore()

      // The course, then the top face over it: what stays visible between the
      // two is the rim, so the plinth has a real thickness.
      ellipse(dx0, dcy + rim, dr, dry, "#150a14")
      ellipse(dx0, dcy + rim * 0.45, dr, dry, "#22121f")

      // The kerb, cut from the rim on a constant arc pitch and anchored to
      // the top face's own edge at both ends.
      var kerbs = 30
      for (var k = 0; k < kerbs; k++) {
        var a0 = -0.08 * Math.PI + (1.16 * Math.PI) * (k / kerbs)
        var a1 = -0.08 * Math.PI + (1.16 * Math.PI) * ((k + 0.66) / kerbs)
        var p0 = daisPoint(a0, 0), p1 = daisPoint(a1, 0)
        var p2 = daisPoint(a1, rim * 0.62), p3 = daisPoint(a0, rim * 0.62)
        ctx.fillStyle = (k % 2 === 0) ? "#4e3550" : "#1d101c"
        ctx.beginPath()
        ctx.moveTo(p0[0], p0[1])
        ctx.lineTo(p1[0], p1[1])
        ctx.lineTo(p2[0], p2[1])
        ctx.lineTo(p3[0], p3[1])
        ctx.closePath()
        ctx.fill()
      }

      // The top face, lit from the door: a gradient across the ellipse from
      // the far (door) edge, where it is pink, to the near edge, where it is
      // the room's purple. Three concentric rings step the same gradient so
      // the turntable still reads as a turntable.
      function daisTop(cy, rx, ry, farC, nearC) {
        ctx.save()
        ctx.beginPath()
        ctx.translate(stall.vx(dx0), stall.vy(cy))
        ctx.scale(rx * u, ry * u)
        ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
        ctx.restore()
        var topG = ctx.createLinearGradient(stall.vx(dx0 + rx * 0.5), stall.vy(cy - ry),
                                            stall.vx(dx0 - rx * 0.5), stall.vy(cy + ry))
        topG.addColorStop(0, farC)
        topG.addColorStop(1, nearC)
        ctx.fillStyle = topG
        ctx.fill()
      }
      daisTop(dcy, dr, dry, "#7a3462", "#2a1626")
      var r90 = ring(0.90), r70 = ring(0.70)
      daisTop(r90.cy - 2, r90.rx, r90.ry, "#83396a", "#31192d")
      daisTop(r70.cy - 4, r70.rx, r70.ry, "#8d3f72", "#381d34")

      // Two rims on the top face. The near arc catches the amber work light
      // -- the design's own rim, kept -- and the far arc catches the sun,
      // in the same #f0b07a the kart's own rim is.
      ctx.save()
      ctx.beginPath()
      ctx.translate(stall.vx(dx0), stall.vy(dcy))
      ctx.scale(dr * u, dry * u)
      ctx.arc(0, 0, 1, 0.04 * Math.PI, 0.96 * Math.PI, false)
      ctx.restore()
      ctx.strokeStyle = Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.72)
      ctx.lineWidth = Math.max(1.5, 3 * u)
      ctx.stroke()
      ctx.save()
      ctx.beginPath()
      ctx.translate(stall.vx(dx0), stall.vy(dcy))
      ctx.scale(dr * u, dry * u)
      ctx.arc(0, 0, 1, 1.04 * Math.PI, 1.96 * Math.PI, false)
      ctx.restore()
      ctx.strokeStyle = rgbaOf(Theme.duskRim, 0.70)
      ctx.lineWidth = Math.max(1, 2.5 * u)
      ctx.stroke()

      // ------------------------------------------------------ work lights
      // A work light: two hanger rods, a reflector that is wider at the top
      // than at the tube so it reads as a shade, end caps, a hot core inside
      // the tube, and a beam with a brighter inner cone. Unchanged from the
      // design's version except for the fixture's own metal, which is now in
      // the room's purple neutrals. The beam is a little weaker than it was:
      // this is the local light now, not the only one.
      function workLight(x, y, w) {
        // Hangers.
        rect(x + w * 0.17, y - 30, 3, 30, "#3a1e34")
        rect(x + w * 0.80, y - 30, 3, 30, "#3a1e34")
        rect(x + w * 0.17 - 2, y - 31, 7, 3, "#4d2c48")
        rect(x + w * 0.80 - 2, y - 31, 7, 3, "#4d2c48")
        // The reflector, as a trapezoid.
        ctx.fillStyle = "#4b2f48"
        ctx.beginPath()
        ctx.moveTo(stall.vx(x - 16), stall.vy(y))
        ctx.lineTo(stall.vx(x + w + 16), stall.vy(y))
        ctx.lineTo(stall.vx(x + w + 4), stall.vy(y + 11))
        ctx.lineTo(stall.vx(x - 4), stall.vy(y + 11))
        ctx.closePath()
        ctx.fill()
        rect(x - 16, y, w + 32, 3, "#5d3d5a")
        rect(x - 4, y + 10, w + 8, 2, "#6a4866")
        // End caps, then the tube: a hot core, the amber body, a warm base.
        rect(x - 4, y + 11, 7, 11, "#2e1a2c")
        rect(x + w - 3, y + 11, 7, 11, "#2e1a2c")
        rect(x + 3, y + 12, w - 6, 9, Theme.amberGlow)
        rect(x + 3, y + 12, w - 6, 3, "#fff2d6")
        rect(x + 3, y + 20, w - 6, 3, Theme.amberDeep)
        var glow = ctx.createRadialGradient(stall.vx(x + w / 2), stall.vy(y + 16), 0,
                                            stall.vx(x + w / 2), stall.vy(y + 16), stall.vs(w * 1.9))
        glow.addColorStop(0, Qt.rgba(1, 0.80, 0.40, 0.40))
        glow.addColorStop(0.45, Qt.rgba(1, 0.72, 0.3, 0.12))
        glow.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
        ctx.fillStyle = glow
        ctx.fillRect(stall.vx(x + w / 2 - w * 1.9), stall.vy(y + 16 - w * 1.9),
                     stall.vs(w * 3.8), stall.vs(w * 3.8))
        // The beam. Two cones: a wide soft one and a narrow bright one, both
        // fading to nothing over their own length so neither ends on an edge.
        function beam(spread, a0, a1) {
          var cone = ctx.createLinearGradient(0, stall.vy(y + 22), 0, stall.vy(500))
          cone.addColorStop(0, Qt.rgba(1, 0.76, 0.36, a0))
          cone.addColorStop(0.50, Qt.rgba(1, 0.75, 0.34, a1))
          cone.addColorStop(1, Qt.rgba(1, 0.74, 0.33, 0))
          ctx.fillStyle = cone
          ctx.beginPath()
          ctx.moveTo(stall.vx(x + 2), stall.vy(y + 22))
          ctx.lineTo(stall.vx(x + w - 2), stall.vy(y + 22))
          ctx.lineTo(stall.vx(x + w + spread), stall.vy(500))
          ctx.lineTo(stall.vx(x - spread), stall.vy(500))
          ctx.closePath()
          ctx.fill()
        }
        beam(150, 0.095, 0.035)
        beam(52, 0.095, 0.032)
      }
      // A matched pair: same length, same baseline.
      workLight(206, 34, 180)
      workLight(794, 34, 180)

      // A pool of warm light on the floor under the kart: the amber
      // counterpoint, local, sitting inside the door's wide pink.
      var pool = ctx.createRadialGradient(stall.vx(stall.daisX), stall.vy(stall.daisY - 4), 0,
                                          stall.vx(stall.daisX), stall.vy(stall.daisY - 4), stall.vs(260))
      pool.addColorStop(0, Qt.rgba(1, 0.75, 0.34, 0.16))
      pool.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
      ctx.fillStyle = pool
      ctx.fillRect(stall.vx(stall.daisX - 260), stall.vy(330), stall.vs(520), stall.vs(230))

      // ----------------------------------------------------------- signage
      // The pit terminal, left wall. A cased screen: the case is a box with
      // its door-side flank lit, and it throws a shadow left across the wall.
      wallShadow(stall.termX, stall.termY, 152, 94, 22, 0.42)
      boxProp(stall.termX, stall.termY, 152, 94, 0.07, "#160a14", "#4a2440", "#2a1526")
      rect(stall.termX + 4, stall.termY + 4, 144, 86, "#241422")
      rect(stall.termX + 10, stall.termY + 10, 132, 74, "#06120e")
      rect(stall.termX + 10, stall.termY + 10, 132, 3, "#0d2a1e")
      for (var scan = stall.termY + 14; scan < stall.termY + 84; scan += 4)
        rect(stall.termX + 10, scan, 132, 1, "#0a1f16")
      rect(stall.termX, stall.termY, 152, 4, "#3a1e36")
      rect(stall.termX + 150, stall.termY, 2, 94, rgbaOf(Theme.duskRim, 0.5))

      // The practice poster, between the terminal and the roller door. Its
      // backdrop is the same sunset as the door: the poster is the bar's own
      // composition in miniature. It hangs off the wall, so it too has a
      // frame with a lit door-side edge and a shadow behind it.
      var poX = stall.posterX, poY = stall.posterY, poW = 148, poH = 150
      wallShadow(poX, poY, poW, poH, 20, 0.40)
      boxProp(poX, poY, poW, poH, 0.045, "#3a1e36", "#6e3a5c", "#4a2644")
      rect(poX + 6, poY + 6, poW - 12, poH - 12, "#160a14")
      var posterSky = ctx.createLinearGradient(0, stall.vy(poY + 6), 0, stall.vy(poY + 84))
      posterSky.addColorStop(0, Theme.duskSkyTop)
      posterSky.addColorStop(0.7, Theme.duskSkyHot)
      posterSky.addColorStop(1, Theme.duskHorizon)
      ctx.fillStyle = posterSky
      ctx.fillRect(stall.vx(poX + 6), stall.vy(poY + 6), stall.vs(poW - 12), stall.vs(78))
      ctx.fillStyle = Theme.duskSun
      ctx.beginPath()
      ctx.arc(stall.vx(poX + poW / 2), stall.vy(poY + 74), stall.vs(22), Math.PI, Math.PI * 2, false)
      ctx.fill()
      rect(poX + 6, poY + 74, poW - 12, 10, Theme.duskHillNear)
      rect(poX + 6, poY + 82, poW - 12, 2, "#4a1838")
      rect(poX + poW - 2, poY, 2, poH, rgbaOf(Theme.duskRim, 0.5))

      // Hanging checkered flag, on the wall right of the door. The light
      // square is kept below the kart's value; the hem ties the columns.
      // ROUND-7: the light square was #9a8a94, a neutral grey, and the only
      // neutral left in the room. Nothing under this sun is grey. It is now
      // the cream the design already gives to plates and road paint, dropped
      // to a value below the kart's, and the fold shadow beside it is purple.
      rect(858, 60, 72, 5, "#3a1e36")
      rect(860, 64, 68, 6, "#180a16")
      for (var fc = 0; fc < 6; fc++) {
        var drape = Math.round(Math.abs(Math.sin((fc + 0.4) * 0.7)) * 3)
        var lit = fc < 3 ? "#a48678" : "#b9937f"
        for (var fr = 0; fr < 7; fr++) {
          rect(862 + fc * 11, 68 + drape + fr * 11, 11, 11,
               (fr + fc) % 2 === 0 ? lit : "#1c0a18")
        }
        rect(862 + fc * 11, 68 + drape + 77, 11, 3, "#4a2a46")
      }

      // Traffic cone, on open floor left of the dais. Its shadow now runs
      // toward the camera and left, like everything else's.
      var coneX = 250, coneBase = 372
      ctx.save()
      ctx.translate(stall.vx(coneX + 14), stall.vy(coneBase + 6))
      ctx.scale(44 * u, 8 * u)
      var coneShadow = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      coneShadow.addColorStop(0, Qt.rgba(0.10, 0.02, 0.09, 0.6))
      coneShadow.addColorStop(1, Qt.rgba(0.10, 0.02, 0.09, 0))
      ctx.fillStyle = coneShadow
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.fill()
      ctx.restore()
      rect(coneX, coneBase - 8, 56, 8, "#7a3a14")
      rect(coneX, coneBase - 10, 56, 2, "#94491c")
      for (var cn = 0; cn < 6; cn++)
        rect(coneX + 6 + cn * 3, coneBase - 8 - cn * 11 - 11, 44 - cn * 6, 11,
             cn === 2 || cn === 3 ? "#e4cbb4" : "#c25a1c")
      // The sun on the cone's right edge and the room's purple on its left.
      // The lit tone follows the band it lands on: painting the rim colour
      // over a cream band made the cream band's lit side DARKER than its
      // body, which the round's light audit caught on both cream bands.
      for (var cr = 0; cr < 6; cr++) {
        var cbx = coneX + 6 + cr * 3, cbw = 44 - cr * 6
        var cby = coneBase - 8 - cr * 11 - 11
        rect(cbx + cbw - 4, cby, 4, 11,
             cr === 2 || cr === 3 ? "#fbeada" : rgbaOf(Theme.duskRim, 0.75))
        rect(cbx, cby, 4, 11,
             cr === 2 || cr === 3 ? "#9d8092" : Qt.rgba(0.42, 0.20, 0.09, 1))
      }

      // ---------------------------------------------------------- vignette
      // Purple, not black: the corners fall toward the bar's ground colour.
      var vig = ctx.createRadialGradient(stall.vx(640), stall.vy(280), stall.vs(260),
                                         stall.vx(640), stall.vy(280), stall.vs(800))
      vig.addColorStop(0, Qt.rgba(0.08, 0.02, 0.07, 0))
      vig.addColorStop(1, Qt.rgba(0.08, 0.02, 0.07, 0.70))
      ctx.fillStyle = vig
      ctx.fillRect(0, 0, width, height)
    }
  }

  // The terminal's green CRT copy, and the poster's, as real text so they
  // stay crisp and stay plain text.
  Column {
    x: stall.vx(stall.termX + 18)
    y: stall.vy(stall.termY + 18)
    spacing: stall.vs(6)
    Text {
      text: "WELCOME TO"
      textFormat: Text.PlainText
      color: "#5de08a"
      font.family: Theme.mono
      font.pixelSize: Math.max(7, stall.vs(19))
      font.letterSpacing: stall.vs(1)
    }
    Text {
      text: "THE PIT"
      textFormat: Text.PlainText
      color: "#5de08a"
      font.family: Theme.mono
      font.pixelSize: Math.max(7, stall.vs(19))
      font.letterSpacing: stall.vs(1)
    }
    Text {
      text: "> READY"
      textFormat: Text.PlainText
      // 6.26:1 against the lighter scanline band of the CRT, 6.94:1 against
      // the darker. The previous #2f7d51 measured 3.42:1 and 3.79:1.
      color: "#4fae74"
      font.family: Theme.mono
      font.pixelSize: Math.max(6, stall.vs(13))
    }
  }

  // The poster's car: a sheet cell, red, at whichever whole-number size is
  // nearest 96 view-box units wide -- two thirds of the poster, which keeps
  // the cell (a cell is two thirds as tall as it is wide) above the caption
  // at 176 -- with its cell's top on the poster's top edge, whatever the
  // bake's contact point.
  CarSprite {
    readonly property var fit: CarMeta.fit(stall.vs(96))
    x: Math.round(stall.vx(stall.posterX + 74) - drawnWidth / 2 + anchorDx)
    y: Math.round(stall.vy(stall.posterY + 8) + anchorDy)
    body: 2
    paint: 0
    camera: "stall"
    yaw: 0
    sheetScale: fit.sheetScale
    pixelScale: fit.pixelScale
    showNumber: false
  }

  Column {
    x: stall.vx(stall.posterX + 6)
    y: stall.vy(stall.posterY + 90)
    width: stall.vs(136)
    spacing: stall.vs(4)
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "PRACTICE"
      textFormat: Text.PlainText
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.max(7, stall.vs(21))
      font.letterSpacing: stall.vs(1)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "PAYS OFF"
      textFormat: Text.PlainText
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.max(7, stall.vs(21))
      font.letterSpacing: stall.vs(1)
    }
  }

  onUnitChanged: scene.requestPaint()
  onCornerRadiusChanged: scene.requestPaint()
}
