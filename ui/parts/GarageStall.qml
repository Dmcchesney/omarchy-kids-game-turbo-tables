import QtQuick
import "../"
import "CarMeta.js" as CarMeta

// The pit: the room the whole garage screen stands in, drawn in a 1200 x 560
// view box and mapped onto whatever item it is given.
//
// The design's motif list is the brief for this scene -- roller door, tire
// walls, a diagnostic grid floor, rivets, a WELCOME TO THE PIT terminal.
//
// "Golden Hour at the Pit". The roller door is open onto a retrowave sunset
// and the sun through it is the room's key light: a magenta sky, a low cream
// sun off-centre right, hills in silhouette, and the bay lit from the
// opening -- pink bounce on the floor and the left wall that falls off with
// distance, purple shadows where the design's teal ones were. The amber work
// lights stay on as the warm, local counterpoint.
//
// ROUND-9, AND THE WHOLE OF THE ROUND. Until round eight this scene was a
// PANEL: a 1226 x 530 picture in the top-left quadrant with a 400 x 290
// door cut in it, so the sunset was 3.87 % of the frame, the horizon sat at
// 40.6 % of frame height against the plan's 55-60 %, and the brightest object
// in the picture was a button. Round eight recoloured that button and left the
// composition where it was; a critic's verdict was that the frame, not the
// paint, was the fault.
//
// The room is now the PAGE. This item fills the whole garage card and every
// panel on the screen -- the title, the rail, the kart card, the roster, the
// three boards along the bottom -- stands in it. Three consequences follow and
// they are the round:
//
//   * `horizonPlace` puts the horizon at a stated fraction of THIS ITEM'S
//     height, so the plan's "horizon at 55-60 % of frame height" is a number
//     the file sets rather than one that falls out of a panel's aspect. It
//     holds at every size the evidence renders.
//   * The opening is no longer a door in a wall. The left wall stops at
//     `wallX` and the sky runs from there to the right-hand edge of the item,
//     however wide that is (`vbRight`), so the sunset is the backdrop of the
//     screen and not a window in it.
//   * The props that filled the old back wall -- the shelf rack, the tool
//     chest, the pegboard, the cone, the second tyre stack -- are gone with
//     the wall they hung on. A critic called that wall "a dead quarter", and
//     the answer to a dead quarter is not more props on it.
//
// Placeholder art, drawn in code. It exists so the garage's composition can
// be judged now; a painted or rendered bay replaces it behind the same
// interface.
Item {
  id: stall

  readonly property real vbW: 1200
  readonly property real vbH: 560
  property real cornerRadius: 0

  // The room is fitted to the item's WIDTH, so nothing on the left wall can be
  // cut at any aspect (round eight's 1024 x 768 fix), and capped by its HEIGHT,
  // so an ultra-wide page cannot scale the room until the car stands behind the
  // boards along the bottom. `vbHFit` is set so that 16:9 is width-driven and
  // only 21:9 and wider take the cap.
  readonly property real vbHFit: 664
  readonly property real unit: width > 0 && height > 0
                               ? Math.min(width / vbW, height / vbHFit) : 0

  // WHERE THE HORIZON GOES, as a fraction of this item's height. The plan's
  // Composition line asks for 55-60 % of frame height and this is the number
  // that delivers it: everything else in the room is placed relative to the
  // horizon, not to the view box's top.
  readonly property real horizonPlace: 0.552
  // Where the kart's contact point wants to be, same units. It is a want, not
  // a placement: `daisY` below clamps it so the turntable's far edge always
  // lands below the yard's own ground line, which is what stops a floor
  // ellipse from crossing the horizon.
  readonly property real daisPlace: 0.69

  readonly property real originX: 0
  readonly property real originY: height * horizonPlace - horizonY * unit
  // How far the item actually reaches, in view-box units, on all four sides.
  // The wall, the sky, the floor and the vignette are drawn to these instead
  // of to a hard-coded 0, 0, 1200, 560, so the room fills the item at every
  // aspect and is never letterboxed.
  readonly property real vbTop: unit > 0 ? Math.min(0, -originY / unit) : 0
  readonly property real vbBottom: unit > 0 ? Math.max(vbH, (height - originY) / unit) : vbH
  readonly property real vbLeft: 0
  readonly property real vbRight: unit > 0 ? Math.max(vbW, width / unit) : vbW

  // ------------------------------------------------------------- the room
  // The left wall is all that is left of the room's masonry: it carries the
  // terminal and the practice poster, it is where the kart card leans, and its
  // jamb is the left edge of the opening. Everything right of it is sky.
  readonly property real wallX: 300
  readonly property real doorX0: wallX
  readonly property real doorX1: vbRight
  // The door head is above the picture: the slats are a strip along the very
  // top and the opening runs off the top of the frame, which is what lets the
  // sky reach the title.
  readonly property real doorTop: -84
  readonly property real doorSill: 336

  // The horizon is the sun's own centre and the room's vanishing point; the
  // ground line is where the sky meets the yard, several tens of units below
  // it. Round eight kept two numbers for this and called them the same thing.
  readonly property real horizonY: 268
  readonly property real groundLineY: 312
  readonly property real eyeX: 600

  // The sun: off-centre right, straddling the horizon, and clear of the
  // roster column at every size the evidence renders.
  readonly property real sunX: 712
  readonly property real sunR: 70

  // Where a kart stands: the centre of the turntable, in view-box units.
  readonly property real daisX: 498
  // The contact point, placed against the item and then clamped so the
  // plinth's far arc stays below the yard's ground line.
  readonly property real daisY: Math.max(groundLineY + daisRise + 8,
                                         unit > 0 ? (height * daisPlace - originY) / unit
                                                  : groundLineY + daisRise + 8)

  // How wide the kart standing here is drawn, in view-box units. Garage.qml
  // reads the hero sprite's width from here rather than repeating a number,
  // because the turntable's size is derived from it below: the plinth and
  // the thing on it are one scale, set once.
  //
  // ROUND-9: 486 becomes 306, and it is not a shrink. The room is now the page
  // and its unit is half as big again as the old panel's, so 306 units is the
  // same 481 px of requested width at 1920 x 1080 that 486 units used to be --
  // `CarMeta.fit` returns the same row and the same whole-number upscale, and
  // the plinth derived from it stays the same size on screen against a car
  // whose size cannot change. See the note on the cap in Garage.qml.
  readonly property real kartWidth: 306
  readonly property real kartToStall: kartWidth / 132

  // ------------------------------------------------- ONE CAMERA, ROUND SIX
  //
  // There is no ellipse constant here. `daisGroundR` is the only art choice
  // on this plinth -- how many model units of floor the turntable covers --
  // and its projection comes from Theme.groundEllipse, the camera the v1
  // live sprite projected every face through.
  //
  // `daisCy` is the projected ellipse's CENTRE, which is not the kart's
  // contact point: the near arc of a floor circle is closer to the camera
  // than the far arc, so it swings further down than the far arc swings up.
  // `daisY` stays the contact point, because that is what Garage.qml stands
  // the kart on.
  readonly property real daisGroundR: 53.7
  readonly property var daisFit: Theme.groundEllipse(daisGroundR)
  readonly property real daisRadius: daisFit.a * kartToStall
  readonly property real daisRy: daisFit.b * kartToStall
  readonly property real daisCy: daisY + daisFit.dy * kartToStall
  readonly property real daisRim: 26
  // How far the plinth's far arc rises above the contact point, in view-box
  // units. `daisY` is clamped by it, so the turntable can never be drawn as a
  // floor circle whose far edge is above the ground line -- which is what a
  // floor ellipse crossing the horizon looks like, and it is wrong at any size.
  readonly property real daisRise: (daisFit.b - daisFit.dy) * kartToStall

  // Where the two pieces of signage sit on the left wall, published as
  // properties because the Canvas draws their cases and the items below draw
  // their copy: two files' worth of numbers agreeing by accident is how a
  // caption ends up half off its own poster.
  readonly property real termX: 24
  readonly property real termY: 40
  readonly property real termW: 132
  readonly property real termH: 84
  readonly property real posterX: 172
  readonly property real posterY: 40
  readonly property real posterW: 116
  readonly property real posterH: 126

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
      var L = stall.vbLeft, R = stall.vbRight
      var T = stall.vbTop, B = stall.vbBottom

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

      // A box standing off a wall: `t` is how far it comes toward the camera.
      // It paints, back to front, the side face that turns toward the eye, the
      // top or the underside, and then the front face. The eye and the door
      // are both right of these props, so the face that turns toward the eye
      // is the face the sun lights.
      var eyeX = stall.eyeX, eyeY = stall.horizonY
      function boxProp(x, y, w, h, t, front, side, top, under) {
        var bx0 = x + (eyeX - x) * t
        var bx1 = (x + w) + (eyeX - (x + w)) * t
        var by0 = y + (eyeY - y) * t
        var by1 = (y + h) + (eyeY - (y + h)) * t
        if (x + w < eyeX)
          poly([[x + w, y], [bx1, by0], [bx1, by1], [x + w, y + h]], side)
        else if (x > eyeX)
          poly([[x, y], [bx0, by0], [bx0, by1], [x, y + h]], side)
        if (y + h < eyeY)
          poly([[x, y + h], [bx0, by1], [bx1, by1], [x + w, y + h]],
               under !== undefined ? under : Qt.darker(front, 1.9))
        else if (y < eyeY)
          poly([[x, y], [bx0, by0], [bx1, by0], [x + w, y]], top)
        rect(x, y, w, h, front)
      }

      // The shadow a wall prop throws: the same face, sheared down and to the
      // left, drawn before the prop. Purple, never grey.
      function wallShadow(x, y, w, h, reach, alpha) {
        poly([[x, y + h], [x - reach, y + h + reach * 0.42],
              [x - reach + w, y + h + reach * 0.42], [x + w, y + h]],
             Qt.rgba(0.16, 0.04, 0.13, alpha))
        poly([[x, y], [x - reach * 0.62, y + reach * 0.26],
              [x - reach * 0.62, y + h + reach * 0.26], [x, y + h]],
             Qt.rgba(0.16, 0.04, 0.13, alpha * 0.8))
      }

      // ======================================================== THE SKY
      // Everything beyond the opening, painted first and across the whole
      // item: the wall, the jamb and the floor are drawn over it. The sky is
      // the backdrop of the screen, so it is the first thing down and the one
      // thing nothing tints.
      var skyBottom = stall.doorSill
      var sky = ctx.createLinearGradient(0, stall.vy(stall.doorTop), 0, stall.vy(stall.horizonY))
      // The top stop is a shade under duskSkyTop. It is the surface the title
      // sits on, and the theme accent -- the one colour on this screen the
      // game may not brighten, because it belongs to the child's Omarchy --
      // needs the headroom: 5.8:1 against this against 4.9:1 against
      // duskSkyTop itself.
      sky.addColorStop(0.00, "#4b1442")
      sky.addColorStop(0.20, Theme.duskSkyTop)
      sky.addColorStop(0.60, Theme.duskSkyMid)
      sky.addColorStop(0.86, Theme.duskSkyHot)
      sky.addColorStop(1.00, Theme.duskHorizon)
      ctx.fillStyle = sky
      ctx.fillRect(stall.vx(L), stall.vy(T), stall.vs(R - L), stall.vs(skyBottom - T))

      // Streaky cloud bands: soft horizontal shapes stretched toward the sun,
      // one a shade lighter than the sky behind them and the rest a shade
      // darker, so they read as lit from it.
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
      cloud(560, 24, 250, 6, rgbaOf(Theme.duskSkyTop, 0.55))
      cloud(830, 62, 210, 4.5, rgbaOf(Theme.duskSkyTop, 0.45))
      cloud(520, 118, 230, 5, rgbaOf(Theme.duskHorizon, 0.40))
      cloud(860, 156, 240, 5.5, rgbaOf(Theme.duskSun, 0.26))
      cloud(600, 196, 190, 4, rgbaOf(Theme.duskSun, 0.22))
      cloud(900, 218, 165, 3.5, rgbaOf(Theme.duskHorizon, 0.45))

      // The sun's glow: wide, horizon-pink, and it reaches most of the sky.
      var halo = ctx.createRadialGradient(stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR * 0.8),
                                          stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR * 4.2))
      halo.addColorStop(0, rgbaOf(Theme.duskSunEdge, 0.85))
      halo.addColorStop(0.32, rgbaOf(Theme.duskHorizon, 0.52))
      halo.addColorStop(1, rgbaOf(Theme.duskHorizon, 0))
      ctx.fillStyle = halo
      ctx.fillRect(stall.vx(L), stall.vy(T), stall.vs(R - L), stall.vs(skyBottom - T))

      // The sun: a big low disc, cream at the core going to orange at the
      // limb, sitting on the horizon. Then the genre's signature: horizontal
      // cut lines through its lower half, thickening downward, in the sky's
      // own horizon colour.
      var sunG = ctx.createRadialGradient(stall.vx(stall.sunX), stall.vy(stall.horizonY - stall.sunR * 0.09), 0,
                                          stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR))
      sunG.addColorStop(0, "#fbe6a0")
      sunG.addColorStop(0.55, Theme.duskSun)
      sunG.addColorStop(1, Theme.duskSunEdge)
      ctx.fillStyle = sunG
      ctx.beginPath()
      ctx.arc(stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(stall.sunR), 0, Math.PI * 2, false)
      ctx.fill()
      // The bands start ABOVE the sun's centre, so the first of them is in
      // open sky whatever the skyline does, and the hills below crest under
      // the centre rather than over it, so the sun still SETS behind them and
      // the bands still have somewhere to disappear. Their pitch scales with
      // the disc, so a bigger sun gets a wider-spaced ladder and not more
      // lines in the same space.
      var cutY = stall.horizonY - stall.sunR * 0.30
      var cutStep = stall.sunR / 70
      for (var cut = 0; cut < 8; cut++) {
        var cw = (1.1 + cut * 1.15) * cutStep
        rect(stall.sunX - stall.sunR - 2, cutY - cw * 0.5, stall.sunR * 2 + 4, cw, Theme.duskHorizon)
        cutY += (4.6 + cut * 1.5) * cutStep
      }

      // Hills: two silhouette layers, the far one lighter (atmospheric
      // perspective), both rising above the ground line so the sun's lower
      // limb sets behind them. A skyline is a polyline, not a curve -- low-poly
      // is the medium. They are drawn from the left edge of the item to the
      // right of it, so the skyline runs the width of the screen.
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
      hills([[L - 20, 300], [120, 278], [250, 292], [370, 272], [500, 288],
             [620, 274], [712, 304], [800, 286], [920, 296], [1040, 280],
             [1180, 292], [R + 20, 282]], 330, Theme.duskHillFar)
      hills([[L - 20, 316], [160, 300], [300, 312], [440, 298], [580, 310],
             [700, 316], [812, 300], [960, 312], [1100, 302], [R + 20, 310]],
            348, Theme.duskHillNear)

      // The yard outside: the bar's near-black purple, a hard ground line, a
      // warm glint under the sun where the tarmac catches it, and the design's
      // diagnostic grid converging on the sun.
      var groundG = ctx.createLinearGradient(0, stall.vy(stall.groundLineY), 0, stall.vy(stall.doorSill))
      groundG.addColorStop(0, "#6a2446")
      groundG.addColorStop(1, Theme.duskGround)
      ctx.fillStyle = groundG
      ctx.fillRect(stall.vx(L), stall.vy(stall.groundLineY),
                   stall.vs(R - L), stall.vs(stall.doorSill - stall.groundLineY))
      rect(L, stall.groundLineY - 1, R - L, 2, "#8c3a60")
      var glint = ctx.createLinearGradient(stall.vx(stall.sunX - 110), 0, stall.vx(stall.sunX + 110), 0)
      glint.addColorStop(0, rgbaOf(Theme.duskSun, 0))
      glint.addColorStop(0.5, rgbaOf(Theme.duskSun, 0.55))
      glint.addColorStop(1, rgbaOf(Theme.duskSun, 0))
      ctx.fillStyle = glint
      for (var gl = 0; gl < 4; gl++)
        ctx.fillRect(stall.vx(stall.sunX - 110 + gl * 10), stall.vy(stall.groundLineY + 4 + gl * 6),
                     stall.vs(220 - gl * 20), stall.vs(1.6 + gl * 0.5))
      ctx.globalAlpha = 0.34
      for (var yg = -9; yg <= 9; yg++)
        line(stall.sunX + yg * 22, stall.groundLineY, stall.sunX + yg * 150,
             stall.doorSill + 20, 1, Theme.duskNeon)
      var yardRows = [stall.groundLineY + 4, stall.groundLineY + 12,
                      stall.groundLineY + 23, stall.doorSill - 2]
      for (var yr = 0; yr < yardRows.length; yr++)
        line(L, yardRows[yr], R, yardRows[yr], 1, Theme.duskNeon)
      ctx.globalAlpha = 1

      // ================================================== THE ROLLER DOOR
      // The slats, rolled up above the picture: a strip along the top of the
      // frame with the sky running out from under it. Their undersides catch
      // the sky, so the highlight on each slat is pink rather than grey.
      var slat = ctx.createLinearGradient(0, stall.vy(T), 0, stall.vy(stall.doorTop))
      slat.addColorStop(0, "#3a1a34")
      slat.addColorStop(1, "#5c2450")
      ctx.fillStyle = slat
      ctx.fillRect(stall.vx(L), stall.vy(T), stall.vs(R - L), stall.vs(stall.doorTop - T))
      for (var sy = stall.doorTop - 8; sy > T; sy -= 11) {
        line(L, sy, R, sy, 1.6, "#2a1226")
        line(L, sy + 3, R, sy + 3, 1, "#7c3a6e")
      }
      rect(L, stall.doorTop - 4, R - L, 8, "#653361")
      rect(L, stall.doorTop + 3, R - L, 2, rgbaOf(Theme.duskHorizon, 0.62))

      // ==================================================== THE LEFT WALL
      // All that is left of the room's masonry, and the plane every card on
      // the left of the screen leans against. Lit down its length by the
      // opening beside it and falling off toward the camera.
      var wallG = ctx.createLinearGradient(stall.vx(L), 0, stall.vx(stall.wallX), 0)
      wallG.addColorStop(0.0, "#3a1129")
      wallG.addColorStop(0.62, "#4d193a")
      wallG.addColorStop(1.0, "#6b2549")
      ctx.fillStyle = wallG
      ctx.fillRect(stall.vx(L), stall.vy(T), stall.vs(stall.wallX - L), stall.vs(348 - T))

      // Panel seams and rivets. The seam's lit side faces the opening, so each
      // seam is a dark groove with a warm hairline on its right lip.
      for (var px = 0; px <= stall.wallX; px += 100) {
        line(px, T, px, 344, 1, "#3d1230")
        line(px + 1.4, T, px + 1.4, 344, 0.8, rgbaOf(Theme.duskRim, 0.16))
        for (var ry = T + 24; ry < 344; ry += 56) {
          rect(px - 2, ry, 4, 4, "#602c53")
          rect(px + 1, ry, 1, 4, rgbaOf(Theme.duskRim, 0.34))
        }
      }

      // ----------------------------------------------------------- signage
      // The pit terminal. A cased screen: the case is a box with its
      // door-side flank lit, and it throws a shadow left across the wall.
      wallShadow(stall.termX, stall.termY, stall.termW, stall.termH, 22, 0.42)
      boxProp(stall.termX, stall.termY, stall.termW, stall.termH, 0.07,
              "#341430", "#6a3459", "#472240")
      rect(stall.termX + 4, stall.termY + 4, stall.termW - 8, stall.termH - 8, "#432038")
      rect(stall.termX + 9, stall.termY + 9, stall.termW - 18, stall.termH - 18, "#1f0a18")
      rect(stall.termX + 9, stall.termY + 9, stall.termW - 18, 3, "#4a2a12")
      for (var scan = stall.termY + 13; scan < stall.termY + stall.termH - 9; scan += 4)
        rect(stall.termX + 9, scan, stall.termW - 18, 1, "#301508")
      rect(stall.termX, stall.termY, stall.termW, 4, "#5a2f52")
      rect(stall.termX + stall.termW - 2, stall.termY, 2, stall.termH, rgbaOf(Theme.duskRim, 0.5))

      // The practice poster. Its backdrop is the same sunset as the opening:
      // the poster is the bar's own composition in miniature, hanging on the
      // one wall this room has left.
      var poX = stall.posterX, poY = stall.posterY, poW = stall.posterW, poH = stall.posterH
      wallShadow(poX, poY, poW, poH, 18, 0.40)
      boxProp(poX, poY, poW, poH, 0.045, "#563050", "#8a4c74", "#63375a")
      rect(poX + 5, poY + 5, poW - 10, poH - 10, "#341430")
      var posterSky = ctx.createLinearGradient(0, stall.vy(poY + 5), 0, stall.vy(poY + 68))
      posterSky.addColorStop(0, Theme.duskSkyTop)
      posterSky.addColorStop(0.7, Theme.duskSkyHot)
      posterSky.addColorStop(1, Theme.duskHorizon)
      ctx.fillStyle = posterSky
      ctx.fillRect(stall.vx(poX + 5), stall.vy(poY + 5), stall.vs(poW - 10), stall.vs(63))
      ctx.fillStyle = Theme.duskSun
      ctx.beginPath()
      ctx.arc(stall.vx(poX + poW / 2), stall.vy(poY + 60), stall.vs(18), Math.PI, Math.PI * 2, false)
      ctx.fill()
      rect(poX + 5, poY + 60, poW - 10, 8, Theme.duskHillNear)
      rect(poX + 5, poY + 66, poW - 10, 2, "#4a1838")
      rect(poX + poW - 2, poY, 2, poH, rgbaOf(Theme.duskRim, 0.5))

      // The checkered flag, pinned to the wall under the terminal. The light
      // square is the cream the design already gives to plates and road paint,
      // kept below the kart's value; the fold shadow beside it is purple.
      // Nothing under this sun is grey.
      var flagX = 28, flagY = 132, fw = 10
      wallShadow(flagX, flagY, fw * 6, fw * 5 + 6, 14, 0.34)
      rect(flagX - 3, flagY, fw * 6 + 6, 4, "#5a2f52")
      for (var fc = 0; fc < 6; fc++) {
        var drape = Math.round(Math.abs(Math.sin((fc + 0.4) * 0.7)) * 3)
        var lit = fc < 3 ? "#a48678" : "#b9937f"
        for (var fr = 0; fr < 5; fr++) {
          rect(flagX + fc * fw, flagY + 4 + drape + fr * fw, fw, fw,
               (fr + fc) % 2 === 0 ? lit : "#301224")
        }
        rect(flagX + fc * fw, flagY + 4 + drape + fw * 5, fw, 3, "#5f3a5a")
      }

      // The jamb: the wall's own edge, turned toward the opening, so it is the
      // brightest warm line in the room outside the sky itself.
      rect(stall.wallX - 3, T, 3, 348 - T, rgbaOf(Theme.duskRim, 0.62))
      rect(stall.wallX, T, 4, 348 - T, "#280d22")

      // The door's light on the wall: magenta bounce, centred on the opening
      // and dying with distance from it.
      var wallGlow = ctx.createRadialGradient(stall.vx(stall.wallX), stall.vy(stall.horizonY), stall.vs(60),
                                              stall.vx(stall.wallX), stall.vy(stall.horizonY), stall.vs(520))
      wallGlow.addColorStop(0, rgbaOf(Theme.duskSkyHot, 0.44))
      wallGlow.addColorStop(0.34, rgbaOf(Theme.duskSkyMid, 0.24))
      wallGlow.addColorStop(1, rgbaOf(Theme.duskSkyTop, 0))
      ctx.fillStyle = wallGlow
      ctx.fillRect(stall.vx(L), stall.vy(T), stall.vs(stall.wallX + 4 - L), stall.vs(348 - T))

      // ======================================================= THE FLOOR
      // The bay's own floor, from the threshold toward the camera. The plan's
      // palette names the ground `#3c1228` and that is the NEAR floor exactly,
      // with the far end lifted by the light coming in over the sill.
      var floor = ctx.createLinearGradient(0, stall.vy(stall.doorSill), 0, stall.vy(B))
      floor.addColorStop(0, "#632044")
      floor.addColorStop(0.40, "#4a1733")
      floor.addColorStop(1, Theme.duskGround)
      ctx.fillStyle = floor
      ctx.fillRect(stall.vx(L), stall.vy(stall.doorSill), stall.vs(R - L),
                   stall.vs(B - stall.doorSill))

      // The threshold. The hazard stripe is the design's amber and it now runs
      // along the SILL, where a pit's hazard marking belongs -- and where no
      // label stands on it. Round eight ran it across the middle of the bay
      // and a section heading was printed over it.
      ctx.save()
      ctx.beginPath()
      ctx.rect(stall.vx(L), stall.vy(stall.doorSill), stall.vs(R - L), stall.vs(13))
      ctx.clip()
      for (var hx = L - 40; hx < R + 40; hx += 34) {
        ctx.fillStyle = "#8a6a19"
        ctx.beginPath()
        ctx.moveTo(stall.vx(hx), stall.vy(stall.doorSill + 13))
        ctx.lineTo(stall.vx(hx + 17), stall.vy(stall.doorSill + 13))
        ctx.lineTo(stall.vx(hx + 34), stall.vy(stall.doorSill))
        ctx.lineTo(stall.vx(hx + 17), stall.vy(stall.doorSill))
        ctx.closePath()
        ctx.fill()
      }
      ctx.restore()
      rect(L, stall.doorSill - 2, R - L, 2, "#9a4368")

      // The door's light on the floor: the opening thrown across the bay
      // toward the camera as a widening pool, hottest at the sill. This is the
      // room's key on the ground plane -- what the kart's long shadow is cut
      // out of.
      var spill = ctx.createLinearGradient(0, stall.vy(stall.doorSill), 0, stall.vy(B))
      spill.addColorStop(0, rgbaOf(Theme.duskHorizon, 0.55))
      spill.addColorStop(0.30, rgbaOf(Theme.duskSkyHot, 0.34))
      spill.addColorStop(0.72, rgbaOf(Theme.duskSkyMid, 0.12))
      spill.addColorStop(1, rgbaOf(Theme.duskSkyTop, 0))
      ctx.fillStyle = spill
      ctx.beginPath()
      ctx.moveTo(stall.vx(stall.wallX), stall.vy(stall.doorSill))
      ctx.lineTo(stall.vx(R), stall.vy(stall.doorSill))
      ctx.lineTo(stall.vx(R), stall.vy(B))
      ctx.lineTo(stall.vx(stall.wallX - 220), stall.vy(B))
      ctx.closePath()
      ctx.fill()

      // The diagnostic grid: lines converging on the room's vanishing point,
      // in the sky's pink at the plan's own alpha. The stroke is 1.6 units
      // wide rather than 1, so more of its width lands in the line and less in
      // the antialiased fringe -- at 1 unit and 0.22 the grid measured DARKER
      // than the floor it was drawn on.
      ctx.globalAlpha = 0.35
      var gridTop = stall.doorSill + 14
      for (var gx = -2600; gx <= 4200; gx += 130)
        line(eyeX + (gx - eyeX) * 0.14, gridTop, gx, B + 6, 1.6, Theme.duskNeon)
      var depth = [gridTop + 2, gridTop + 12, gridTop + 26, gridTop + 46,
                   gridTop + 74, gridTop + 112, gridTop + 162, gridTop + 226,
                   gridTop + 306, gridTop + 404]
      for (var d = 0; d < depth.length; d++)
        if (depth[d] <= B)
          line(L, depth[d], R, depth[d], 1.6, Theme.duskNeon)
      ctx.globalAlpha = 1

      // ==================================================== TYRE WALL
      // A stack of tyres on the floor left of the turntable, between the kart
      // card and the kart: each one a short CYLINDER -- a sidewall band with an
      // elliptical top face on it -- drawn bottom to top so each covers the one
      // below. A tyre is legible because you can see its side, not its face.
      function tyreStack(x, yBase, count, w) {
        var cx2 = x + w / 2, r2 = w / 2, band = 11, ry2 = 7.5
        poly([[x + 4, yBase + 11], [x - 24, yBase + 32],
              [x + w - 10, yBase + 32], [x + w - 2, yBase + 11]],
             Qt.rgba(0.12, 0.03, 0.10, 0.6))
        for (var t = 0; t < count; t++) {
          var cy2 = yBase - t * band
          ellipse(cx2, cy2 + band, r2, ry2, "#2b1226")
          rect(x, cy2, w, band, "#2b1226")
          rect(x + w - 8, cy2, 8, band, "#4a2340")
          rect(x + w - 3.5, cy2, 3.5, band, rgbaOf(Theme.duskRim, 0.40))
          rect(x, cy2, 6, band, "#1d0b19")
          for (var tb = 0; tb < 9; tb++)
            rect(x + 4 + tb * (w - 12) / 9, cy2 + 2, (w - 12) / 20, band - 4,
                 Qt.rgba(0, 0, 0, 0.22))
          ellipse(cx2, cy2, r2, ry2, "#3a1d34")
          ellipse(cx2 + 3, cy2 - 1, r2 - 6, ry2 - 2, "#4a2a44")
          ellipse(cx2 + 1, cy2 + 0.5, r2 * 0.42, ry2 * 0.42, "#5d3a56")
          ellipse(cx2 + 1, cy2 + 0.5, r2 * 0.22, ry2 * 0.24, "#1a0916")
        }
      }
      // On the floor strip between the jamb and the turntable, standing on the
      // threshold rather than deep in the bay: the bay's floor is a 73 px band
      // at 1920 now, so anything standing further back is behind the boards.
      tyreStack(stall.wallX + 6, stall.doorSill + 40, 3, 66)

      // ========================================================= THE DAIS
      var dx0 = stall.daisX
      var dr = stall.daisRadius
      var dcy = stall.daisCy
      var dry = stall.daisRy
      var rim = stall.daisRim

      function ring(k) {
        var e = Theme.groundEllipse(stall.daisGroundR * k)
        return { rx: e.a * stall.kartToStall, ry: e.b * stall.kartToStall,
                 cy: stall.daisY + e.dy * stall.kartToStall }
      }

      function daisPoint(angle, drop) {
        return [stall.vx(dx0 + Math.cos(angle) * dr),
                stall.vy(dcy + Math.sin(angle) * dry + drop)]
      }

      // The plinth's own shadow, thrown by the sun through the door: away from
      // the door, which is up and right of it, so toward the camera and to the
      // left. Purple, because the ambient is a magenta sky.
      var dsh = ring(1.14)
      ctx.save()
      ctx.translate(stall.vx(dx0 - 22), stall.vy(dsh.cy + rim + 10))
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

      // The kerb, cut from the rim on a constant arc pitch and anchored to the
      // top face's own edge at both ends.
      var kerbs = 30
      for (var k = 0; k < kerbs; k++) {
        var a0 = -0.08 * Math.PI + (1.16 * Math.PI) * (k / kerbs)
        var a1 = -0.08 * Math.PI + (1.16 * Math.PI) * ((k + 0.66) / kerbs)
        var p0 = daisPoint(a0, 0), p1 = daisPoint(a1, 0)
        var p2 = daisPoint(a1, rim * 0.62), p3 = daisPoint(a0, rim * 0.62)
        ctx.fillStyle = (k % 2 === 0) ? "#5f4262" : "#251523"
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
      daisTop(dcy, dr, dry, "#8f3f72", "#391f33")
      var r90 = ring(0.90), r70 = ring(0.70)
      daisTop(r90.cy - 2, r90.rx, r90.ry, "#99457b", "#40243a")
      daisTop(r70.cy - 4, r70.rx, r70.ry, "#a34b84", "#472a41")

      // Two rims on the top face. The near arc catches the amber work light --
      // the design's own rim, kept -- and the far arc catches the sun, in the
      // same #f0b07a the kart's own rim is.
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

      // -------------------------------------------------- the hero's shadow
      // The sun is up and to the RIGHT of the kart's contact point, so the
      // shadow goes down and to the LEFT, and it goes long: the ellipse's
      // centre is left of the contact point and below it, its major axis is
      // 1.14 times the dais's own radius, and it runs off the plinth's
      // near-left edge onto the floor, which is what makes it read as cast
      // rather than painted on. Two passes: the soft body, then a tighter,
      // darker core under the wheels so the car still touches something.
      ctx.save()
      ctx.translate(stall.vx(stall.daisX - 62), stall.vy(stall.daisY + 20))
      ctx.rotate(-0.10)
      ctx.scale(dr * 1.14 * u, dry * 0.62 * u)
      var heroShadow = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      heroShadow.addColorStop(0.00, Qt.rgba(0.16, 0.04, 0.13, 0.72))
      heroShadow.addColorStop(0.52, Qt.rgba(0.16, 0.04, 0.13, 0.46))
      heroShadow.addColorStop(1.00, Qt.rgba(0.16, 0.04, 0.13, 0))
      ctx.fillStyle = heroShadow
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.fill()
      ctx.restore()

      ctx.save()
      ctx.translate(stall.vx(stall.daisX - 17), stall.vy(stall.daisY + 8))
      ctx.scale(dr * 0.58 * u, dry * 0.30 * u)
      var heroCore = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      heroCore.addColorStop(0.00, Qt.rgba(0.13, 0.03, 0.11, 0.66))
      heroCore.addColorStop(1.00, Qt.rgba(0.13, 0.03, 0.11, 0))
      ctx.fillStyle = heroCore
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.fill()
      ctx.restore()

      // ==================================================== WORK LIGHTS
      // A work light: two hanger rods running up out of the picture, a
      // reflector wider at the top than at the tube so it reads as a shade,
      // end caps, a hot core inside the tube, and a beam with a brighter inner
      // cone. They hang in the bay, in front of the opening, which is where a
      // pit's lights are and is what keeps the design's amber counterpoint in
      // a room whose one wall is now sky.
      function workLight(x, y, w) {
        rect(x + w * 0.17, T, 3, y - T, "#3a1e34")
        rect(x + w * 0.80, T, 3, y - T, "#3a1e34")
        rect(x + w * 0.17 - 2, y - 1, 7, 3, "#4d2c48")
        rect(x + w * 0.80 - 2, y - 1, 7, 3, "#4d2c48")
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
        rect(x - 4, y + 11, 7, 11, "#2e1a2c")
        rect(x + w - 3, y + 11, 7, 11, "#2e1a2c")
        rect(x + 3, y + 12, w - 6, 9, Theme.amberGlow)
        rect(x + 3, y + 12, w - 6, 3, "#fff2d6")
        rect(x + 3, y + 20, w - 6, 3, Theme.amberDeep)
        var glow = ctx.createRadialGradient(stall.vx(x + w / 2), stall.vy(y + 16), 0,
                                            stall.vx(x + w / 2), stall.vy(y + 16), stall.vs(w * 1.6))
        glow.addColorStop(0, Qt.rgba(1, 0.80, 0.40, 0.30))
        glow.addColorStop(0.45, Qt.rgba(1, 0.72, 0.3, 0.10))
        glow.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
        ctx.fillStyle = glow
        ctx.fillRect(stall.vx(x + w / 2 - w * 1.6), stall.vy(y + 16 - w * 1.6),
                     stall.vs(w * 3.2), stall.vs(w * 3.2))
        function beam(spread, a0, a1) {
          var cone = ctx.createLinearGradient(0, stall.vy(y + 22), 0, stall.vy(stall.daisY + 40))
          cone.addColorStop(0, Qt.rgba(1, 0.76, 0.36, a0))
          cone.addColorStop(0.50, Qt.rgba(1, 0.75, 0.34, a1))
          cone.addColorStop(1, Qt.rgba(1, 0.74, 0.33, 0))
          ctx.fillStyle = cone
          ctx.beginPath()
          ctx.moveTo(stall.vx(x + 2), stall.vy(y + 22))
          ctx.lineTo(stall.vx(x + w - 2), stall.vy(y + 22))
          ctx.lineTo(stall.vx(x + w + spread), stall.vy(stall.daisY + 40))
          ctx.lineTo(stall.vx(x - spread), stall.vy(stall.daisY + 40))
          ctx.closePath()
          ctx.fill()
        }
        beam(120, 0.075, 0.028)
        beam(44, 0.075, 0.026)
      }
      workLight(stall.daisX - 88, 34, 176)

      // A pool of warm light on the floor under the kart: the amber
      // counterpoint, local, sitting inside the door's wide pink.
      var pool = ctx.createRadialGradient(stall.vx(stall.daisX), stall.vy(stall.daisY - 4), 0,
                                          stall.vx(stall.daisX), stall.vy(stall.daisY - 4), stall.vs(230))
      pool.addColorStop(0, Qt.rgba(1, 0.75, 0.34, 0.16))
      pool.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
      ctx.fillStyle = pool
      ctx.fillRect(stall.vx(stall.daisX - 230), stall.vy(stall.daisY - 234),
                   stall.vs(460), stall.vs(460))

      // ---------------------------------------------------------- vignette
      // Purple, not black: the corners fall toward the bar's ground colour.
      // A vignette is a lens, not a wall.
      var vig = ctx.createRadialGradient(stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(320),
                                         stall.vx(stall.sunX), stall.vy(stall.horizonY), stall.vs(1000))
      vig.addColorStop(0, Qt.rgba(0.12, 0.03, 0.10, 0))
      vig.addColorStop(1, Qt.rgba(0.12, 0.03, 0.10, 0.30))
      ctx.fillStyle = vig
      ctx.fillRect(0, 0, width, height)
    }
  }

  // The terminal's amber CRT copy, and the poster's, as real text so they
  // stay crisp and stay plain text.
  Column {
    x: stall.vx(stall.termX + 15)
    y: stall.vy(stall.termY + 16)
    spacing: stall.vs(5)
    Text {
      text: "WELCOME TO"
      textFormat: Text.PlainText
      color: Theme.amberGlow
      font.family: Theme.mono
      font.pixelSize: Math.max(7, stall.vs(17))
      font.letterSpacing: stall.vs(1)
    }
    Text {
      text: "THE PIT"
      textFormat: Text.PlainText
      color: Theme.amberGlow
      font.family: Theme.mono
      font.pixelSize: Math.max(7, stall.vs(17))
      font.letterSpacing: stall.vs(1)
    }
    Text {
      text: "> READY"
      textFormat: Text.PlainText
      color: Theme.amber
      font.family: Theme.mono
      font.pixelSize: Math.max(6, stall.vs(12))
    }
  }

  // The poster's car: a sheet cell, red, at whichever whole-number size is
  // nearest 80 view-box units wide, with its cell's top on the poster's top
  // edge, whatever the bake's contact point.
  CarSprite {
    readonly property var fit: CarMeta.fit(stall.vs(80))
    x: Math.round(stall.vx(stall.posterX + stall.posterW / 2) - drawnWidth / 2 + anchorDx)
    y: Math.round(stall.vy(stall.posterY + 6) + anchorDy)
    body: 2
    paint: 0
    camera: "stall"
    yaw: 0
    sheetScale: fit.sheetScale
    pixelScale: fit.pixelScale
    showNumber: false
  }

  Column {
    x: stall.vx(stall.posterX + 5)
    y: stall.vy(stall.posterY + 74)
    width: stall.vs(stall.posterW - 10)
    spacing: stall.vs(3)
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "PRACTICE"
      textFormat: Text.PlainText
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.max(7, stall.vs(18))
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
      font.pixelSize: Math.max(7, stall.vs(18))
      font.letterSpacing: stall.vs(1)
    }
  }

  onUnitChanged: scene.requestPaint()
  onOriginYChanged: scene.requestPaint()
  onCornerRadiusChanged: scene.requestPaint()
}
