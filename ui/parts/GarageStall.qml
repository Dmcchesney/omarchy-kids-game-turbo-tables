import QtQuick
import "../"

// The stall: the garage bay the kart stands in. Drawn in a 1200 x 560 view
// box and scaled to the panel it is given, so the same scene composes at
// 1366x768 and at 2560x1440 without reflowing.
//
// The design's motif list is the brief for this scene -- roller door, tire
// walls, a diagnostic grid floor, rivets, a WELCOME TO THE PIT terminal --
// lit by warm amber work lights against dark teal night through the door.
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
  // View-box units per model unit of the kart's own space. KartSprite draws
  // into a 132-unit-wide view box, so a sprite `kartWidth` units wide puts
  // this many stall units on one kart model unit.
  readonly property real kartToStall: kartWidth / 132

  // ------------------------------------------------- ONE CAMERA, ROUND SIX
  //
  // Rounds two through five drew this plinth as an ellipse whose ratio was a
  // typed constant. Round two used 60/248 = 0.24. Round four replaced it
  // with 104/256 = 0.406 = sin(24 deg), reasoning that the kart is drawn by
  // a camera pitched 25 degrees and a floor circle seen from there projects
  // to sin(pitch).
  //
  // BOTH OF THOSE ARE WRONG, and a critic measured how wrong: fitting the
  // shipped rim (486 points, rms 0.35 px) gave an apparent pitch of 23.96
  // degrees against about 31 for the kart's own projection -- the dais was
  // 27 px flatter than the kart standing on it needed, which is 77 times the
  // fit residual. sin(pitch) is the ORTHOGRAPHIC answer. KartSprite is not
  // orthographic: it divides by distance, and its aim point sits 13 model
  // units above the floor. Both of those steepen a floor circle, and the
  // second one steepens it even for a circle of zero radius.
  //
  // So there is no ellipse constant here any more. `daisGroundR` is the only
  // art choice on this plinth -- how many model units of floor the turntable
  // covers -- and its projection comes from Theme.groundEllipse, the same
  // camera KartSprite projects every face through.
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
  // is the surface that catches the amber rim light and carries the kerb.
  readonly property real daisRy: daisFit.b * kartToStall
  readonly property real daisCy: daisY + daisFit.dy * kartToStall
  readonly property real daisRim: 26

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

      // ---------------------------------------------------------- back wall
      var wall = ctx.createLinearGradient(0, stall.vy(0), 0, stall.vy(360))
      wall.addColorStop(0, "#161821")
      wall.addColorStop(0.55, "#12131a")
      wall.addColorStop(1, "#0b0c11")
      ctx.fillStyle = wall
      ctx.fillRect(stall.vx(0), stall.vy(0), stall.vs(1200), stall.vs(360))

      // Wall panel seams and rivets.
      for (var px = 0; px <= 1200; px += 150) {
        line(px, 0, px, 340, 1, "#1d202b")
        for (var ry = 30; ry < 340; ry += 60) {
          rect(px - 2, ry, 4, 4, "#262a37")
        }
      }
      line(0, 120, 1200, 120, 1, "#1c1f29")

      // ------------------------------------------------------- roller door
      // Night beyond the open door: the design's dark teal.
      var night = ctx.createLinearGradient(0, stall.vy(150), 0, stall.vy(345))
      night.addColorStop(0, "#12414c")
      night.addColorStop(0.6, "#0e2c35")
      night.addColorStop(1, "#0a1d24")
      ctx.fillStyle = night
      ctx.fillRect(stall.vx(470), stall.vy(150), stall.vs(350), stall.vs(195))

      // The yard beyond the doorway: a low roofline, then three buildings.
      //
      // Round three scattered sixteen teal rectangles of eight different
      // widths and six different heights across this strip at unrelated
      // positions, and a critic read them for exactly what they were --
      // "arbitrary teal rectangles that read as noise, not as anything".
      // Randomness is not detail. A window is legible because windows repeat
      // on a building's own grid, so each block now carries one grid of its
      // own, on the block's own pitch, and only the lit pattern varies.
      rect(470, 236, 350, 4, "#0b2029")
      var blocks = [ { bx: 486, by: 196, bw: 96, bh: 40, cap: "#0f2c37" },
                     { bx: 600, by: 172, bw: 74, bh: 64, cap: "#123340" },
                     { bx: 692, by: 206, bw: 112, bh: 30, cap: "#0f2c37" } ]
      // One character per window, walked in reading order: a fixed pattern,
      // so the yard is the same yard every time the screen opens.
      var litBits = "1011010011100101101100101101011010011011"
      var bit = 0
      for (var bl = 0; bl < blocks.length; bl++) {
        var bk = blocks[bl]
        rect(bk.bx, bk.by, bk.bw, bk.bh, "#0d2731")
        rect(bk.bx, bk.by, bk.bw, 3, bk.cap)
        for (var wy = bk.by + 8; wy + 7 <= bk.by + bk.bh; wy += 13)
          for (var wx = bk.bx + 7; wx + 8 <= bk.bx + bk.bw; wx += 15) {
            var on = litBits.charAt(bit % litBits.length) === "1"
            bit++
            rect(wx, wy, 8, 7, on ? "#2c7d87" : "#14414c")
          }
      }
      // Wet floor reflection outside.
      rect(470, 292, 350, 53, "#0c2831")
      for (var rx2 = 490; rx2 < 810; rx2 += 60)
        rect(rx2, 300 + (rx2 % 40) / 4, 26, 3, "#1c5c66")

      // The raised door: slats and the bottom rail.
      var slat = ctx.createLinearGradient(0, stall.vy(60), 0, stall.vy(150))
      slat.addColorStop(0, "#2b2e39")
      slat.addColorStop(1, "#191b23")
      ctx.fillStyle = slat
      ctx.fillRect(stall.vx(462), stall.vy(56), stall.vs(366), stall.vs(94))
      for (var sy = 62; sy < 150; sy += 11) {
        line(464, sy, 826, sy, 1.6, "#111319")
        line(464, sy + 3, 826, sy + 3, 1, "#3a3f4d")
      }
      rect(462, 148, 366, 7, "#3f4552")
      // Door frame uprights.
      rect(456, 50, 8, 296, "#22252f")
      rect(824, 50, 8, 296, "#22252f")

      // -------------------------------------------------------- shelf unit
      rect(246, 238, 190, 102, "#14161d")
      for (var sh = 0; sh < 2; sh++) {
        var sy2 = 238 + sh * 48
        rect(246, sy2, 190, 6, "#2d323f")
        // crates
        rect(254, sy2 + 10, 34, 32, sh % 2 === 0 ? "#3d4a2c" : "#4a3324")
        rect(294, sy2 + 16, 26, 26, "#2b3a49")
        rect(326, sy2 + 12, 40, 30, sh % 2 === 0 ? "#48342a" : "#2f3a2a")
        rect(372, sy2 + 20, 22, 22, "#3a3040")
      }
      rect(240, 234, 8, 106, "#20242e")
      rect(430, 234, 8, 106, "#20242e")

      // ------------------------------------------------------ tool chest
      rect(120, 236, 122, 106, "#5a1f1c")
      rect(120, 236, 122, 8, "#7a2c26")
      for (var dr = 0; dr < 4; dr++) {
        rect(126, 250 + dr * 22, 110, 17, "#481916")
        rect(150, 256 + dr * 22, 62, 4, "#8f4038")
      }
      rect(120, 336, 122, 6, "#1a0f0e")

      // -------------------------------------------------------- pegboard
      // The wall right of the roller door was a large dead expanse. The
      // COLOR panel covers everything below y=156 on that side, so this sits
      // in the strip that is actually visible, and it is kept dark on purpose
      // -- the brief for this round is that nothing in the corner of the bay
      // should outrank the kart.
      rect(946, 44, 214, 104, "#191c24")
      rect(946, 44, 214, 4, "#272c38")
      for (var pgx = 954; pgx < 1156; pgx += 12)
        for (var pgy = 56; pgy < 142; pgy += 12)
          rect(pgx, pgy, 2, 2, "#232733")
      // A spanner, a hammer and two hooks, as silhouettes.
      rect(968, 58, 6, 54, "#3a4050")
      rect(963, 56, 16, 8, "#3a4050")
      rect(963, 104, 16, 8, "#3a4050")
      rect(1000, 58, 7, 40, "#333947")
      rect(994, 56, 19, 9, "#464d5e")
      rect(1036, 58, 5, 30, "#333947")
      rect(1030, 86, 17, 7, "#3a4050")
      rect(1074, 58, 5, 44, "#2f3441")
      rect(1068, 58, 17, 6, "#3a4050")
      rect(1110, 58, 5, 36, "#2f3441")
      rect(1104, 58, 17, 6, "#3a4050")
      rect(946, 146, 214, 3, "#0d0f14")

      // ------------------------------------------------------- tire walls
      function tyreStack(x, yBase, count, w) {
        for (var t = 0; t < count; t++) {
          var ty = yBase - t * 26
          rect(x, ty, w, 24, "#191b21")
          rect(x + 3, ty + 3, w - 6, 18, "#101216")
          rect(x, ty, w, 4, "#24272f")
        }
      }
      // Only the left stack is drawn. There were two more at x=1010 and
      // x=1096, and the opaque COLOR panel begins at x=889 and runs to the
      // bottom-right corner, so neither of them was ever visible on any
      // screen at any size -- the composition scales as one factor, so what
      // is covered at 1920 is covered everywhere. Scenery nothing can see is
      // scenery that gets counted in a report and not in the picture.
      tyreStack(24, 316, 4, 84)

      // ------------------------------------------------------------ floor
      var floor = ctx.createLinearGradient(0, stall.vy(340), 0, stall.vy(560))
      floor.addColorStop(0, "#15171d")
      floor.addColorStop(0.45, "#0e1014")
      floor.addColorStop(1, "#08090c")
      ctx.fillStyle = floor
      ctx.fillRect(stall.vx(0), stall.vy(340), stall.vs(1200), stall.vs(220))

      // Hazard stripe along the back of the bay.
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
      rect(0, 338, 1200, 2, "#2a2d38")

      // The diagnostic grid: lines converging on a vanishing point.
      ctx.globalAlpha = 0.5
      for (var gx = -1400; gx <= 2600; gx += 100)
        line(600 + (gx - 600) * 0.16, 344, gx, 566, 1, "#252a36")
      var depth = [346, 356, 370, 390, 418, 456, 506, 566]
      for (var d = 0; d < depth.length; d++)
        line(0, depth[d], 1200, depth[d], 1, "#232833")
      ctx.globalAlpha = 1

      // ------------------------------------------------------------- dais
      // A plinth with a top face, a rim course under it and its own shadow on
      // the floor. Round two drew a stack of four flat ellipses and scattered
      // 40 kerb blocks around the widest of them at a constant *angular*
      // pitch measured on the wrong ellipse, so the blocks came out 12 to 22
      // units wide with 15 to 35 unit gaps and several floated clear of the
      // stroke. Here the kerb is cut from the rim itself -- every block runs
      // from the top face's edge down to the bottom of the course, so no
      // block can be detached from it.
      var dx0 = stall.daisX
      var dr = stall.daisRadius
      var dcy = stall.daisCy
      var dry = stall.daisRy
      var rim = stall.daisRim

      // ROUND-6. Every ring on this plinth is a floor circle put through the
      // kart's camera, not the outer ellipse with a number subtracted from
      // each axis. `ring(k)` is the circle of k times the turntable's radius.
      // Subtracting a constant is wrong twice over: it changes the axis ratio
      // (26 off 256 and 12 off 104 is a different camera again) and it leaves
      // the ring concentric with the outer ellipse when a smaller floor
      // circle projects with its centre HIGHER up the screen, not level.
      function ring(k) {
        var e = Theme.groundEllipse(stall.daisGroundR * k)
        return { rx: e.a * stall.kartToStall, ry: e.b * stall.kartToStall,
                 cy: stall.daisY + e.dy * stall.kartToStall }
      }

      function daisPoint(angle, drop) {
        return [stall.vx(dx0 + Math.cos(angle) * dr),
                stall.vy(dcy + Math.sin(angle) * dry + drop)]
      }

      // The plinth's own shadow, thrown away from the work lights overhead.
      var dsh = ring(1.10)
      ctx.save()
      ctx.translate(stall.vx(dx0), stall.vy(dsh.cy + rim + 6))
      ctx.scale(dsh.rx * u, dsh.ry * u)
      var daisShadow = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      daisShadow.addColorStop(0, Qt.rgba(0, 0, 0, 0.62))
      daisShadow.addColorStop(0.72, Qt.rgba(0, 0, 0, 0.34))
      daisShadow.addColorStop(1, Qt.rgba(0, 0, 0, 0))
      ctx.fillStyle = daisShadow
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.fill()
      ctx.restore()

      // The course, then the top face over it: what stays visible between the
      // two is the rim, so the plinth has a real thickness.
      ellipse(dx0, dcy + rim, dr, dry, "#0e1116")
      ellipse(dx0, dcy + rim * 0.45, dr, dry, "#191d26")

      // The kerb, cut from the rim on a constant arc pitch and anchored to
      // the top face's own edge at both ends.
      var kerbs = 30
      for (var k = 0; k < kerbs; k++) {
        var a0 = -0.08 * Math.PI + (1.16 * Math.PI) * (k / kerbs)
        var a1 = -0.08 * Math.PI + (1.16 * Math.PI) * ((k + 0.66) / kerbs)
        var p0 = daisPoint(a0, 0), p1 = daisPoint(a1, 0)
        var p2 = daisPoint(a1, rim * 0.62), p3 = daisPoint(a0, rim * 0.62)
        ctx.fillStyle = (k % 2 === 0) ? "#3d4658" : "#171b23"
        ctx.beginPath()
        ctx.moveTo(p0[0], p0[1])
        ctx.lineTo(p1[0], p1[1])
        ctx.lineTo(p2[0], p2[1])
        ctx.lineTo(p3[0], p3[1])
        ctx.closePath()
        ctx.fill()
      }

      ellipse(dx0, dcy, dr, dry, "#242b38")
      var r90 = ring(0.90), r70 = ring(0.70)
      ellipse(dx0, r90.cy - 2, r90.rx, r90.ry, "#2b3341")
      ellipse(dx0, r70.cy - 4, r70.rx, r70.ry, "#313a49")

      // Amber rim light along the near edge of the top face, dying away round
      // the sides. Round one stroked the whole ellipse in amberDeep at 2.5
      // units and it was invisible at 1:1.
      ctx.save()
      ctx.beginPath()
      ctx.translate(stall.vx(dx0), stall.vy(dcy))
      ctx.scale(dr * u, dry * u)
      ctx.arc(0, 0, 1, 0.04 * Math.PI, 0.96 * Math.PI, false)
      ctx.restore()
      ctx.strokeStyle = Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.82)
      ctx.lineWidth = Math.max(1.5, 3 * u)
      ctx.stroke()
      ctx.save()
      ctx.beginPath()
      ctx.translate(stall.vx(dx0), stall.vy(dcy))
      ctx.scale(dr * u, dry * u)
      ctx.arc(0, 0, 1, 0.96 * Math.PI, 2.04 * Math.PI, false)
      ctx.restore()
      ctx.strokeStyle = Qt.rgba(Theme.amberDeep.r, Theme.amberDeep.g, Theme.amberDeep.b, 0.5)
      ctx.lineWidth = Math.max(1, 2 * u)
      ctx.stroke()

      // ------------------------------------------------------ work lights
      // A work light. ROUND-4: a fixture, not a bar.
      //
      // The design's own visual pillar is "amber work lights", and round
      // three's were, in a critic's words, "flat amber bars with no fixture
      // or cord, and near-invisible beams" -- fairly, because the fixture was
      // one flat grey rectangle behind one flat amber rectangle, with a
      // single 5-unit stem, and the beam left the source at alpha 0.10.
      // What is here now: two hanger rods, a reflector that is wider at the
      // top than at the tube so it reads as a shade, end caps that stop the
      // tube being a bar, a hot core inside the tube, and a beam that starts
      // at alpha 0.20 with a brighter inner cone inside it.
      function workLight(x, y, w) {
        // Hangers.
        rect(x + w * 0.17, y - 30, 3, 30, "#2a2e39")
        rect(x + w * 0.80, y - 30, 3, 30, "#2a2e39")
        rect(x + w * 0.17 - 2, y - 31, 7, 3, "#3a4050")
        rect(x + w * 0.80 - 2, y - 31, 7, 3, "#3a4050")
        // The reflector, as a trapezoid: 20 units wider at its top edge than
        // at the tube, which is the whole reason it reads as a shade.
        ctx.fillStyle = "#3b414e"
        ctx.beginPath()
        ctx.moveTo(stall.vx(x - 16), stall.vy(y))
        ctx.lineTo(stall.vx(x + w + 16), stall.vy(y))
        ctx.lineTo(stall.vx(x + w + 4), stall.vy(y + 11))
        ctx.lineTo(stall.vx(x - 4), stall.vy(y + 11))
        ctx.closePath()
        ctx.fill()
        rect(x - 16, y, w + 32, 3, "#4b5262")
        rect(x - 4, y + 10, w + 8, 2, "#565d6e")
        // End caps, then the tube: a hot core, the amber body, a warm base.
        rect(x - 4, y + 11, 7, 11, "#262a34")
        rect(x + w - 3, y + 11, 7, 11, "#262a34")
        rect(x + 3, y + 12, w - 6, 9, Theme.amberGlow)
        rect(x + 3, y + 12, w - 6, 3, "#fff2d6")
        rect(x + 3, y + 20, w - 6, 3, Theme.amberDeep)
        var glow = ctx.createRadialGradient(stall.vx(x + w / 2), stall.vy(y + 16), 0,
                                            stall.vx(x + w / 2), stall.vy(y + 16), stall.vs(w * 1.9))
        glow.addColorStop(0, Qt.rgba(1, 0.80, 0.40, 0.42))
        glow.addColorStop(0.45, Qt.rgba(1, 0.72, 0.3, 0.14))
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
        beam(150, 0.115, 0.045)
        beam(52, 0.115, 0.040)
      }
      // A matched pair: same length, same baseline. Round one had them 186
      // and 194 units long, hung four units apart, and called them a pair.
      workLight(206, 34, 180)
      workLight(794, 34, 180)

      // A pool of warm light on the floor under the kart.
      var pool = ctx.createRadialGradient(stall.vx(stall.daisX), stall.vy(stall.daisY - 4), 0,
                                          stall.vx(stall.daisX), stall.vy(stall.daisY - 4), stall.vs(300))
      pool.addColorStop(0, Qt.rgba(1, 0.75, 0.34, 0.18))
      pool.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
      ctx.fillStyle = pool
      ctx.fillRect(stall.vx(stall.daisX - 300), stall.vy(330), stall.vs(600), stall.vs(230))

      // ----------------------------------------------------------- signage
      // The pit terminal, left wall.
      rect(38, 92, 174, 104, "#101318")
      rect(42, 96, 166, 96, "#1a1d24")
      rect(48, 102, 154, 84, "#06120e")
      rect(48, 102, 154, 3, "#0d2a1e")
      for (var scan = 106; scan < 186; scan += 4)
        rect(48, scan, 154, 1, "#0a1f16")
      rect(38, 92, 174, 4, "#232833")

      // The practice poster. It hangs on the wall between the terminal and
      // the roller door, where the COLOR panel cannot reach it: on the right
      // wall the panel cut it in half and left its kart floating.
      rect(246, 86, 164, 146, "#2a3140")
      rect(252, 92, 152, 134, "#0f1319")
      rect(252, 92, 152, 78, "#14232d")
      rect(252, 168, 152, 2, "#243544")

      // Hanging checkered flag, on the wall right of the door.
      //
      // Two faults here in round two. The drape was a single hard step -- the
      // last two columns dropped by four units in one jump -- which read as a
      // texture seam rather than as cloth. And at #c9cdd8 the prop measured a
      // 95th-percentile luminance of 0.446 against the kart's 0.359, so the
      // highest-contrast object in the stall was a decoration in the corner
      // rather than the thing the screen exists for.
      //
      // The drape is now a smooth per-column curve, and the check's phase is
      // taken from the column and row indices rather than from the offset
      // position, so no amount of drape can put the pattern out of register.
      // The light square is dropped to a value that sits under the kart.
      //
      // ROUND-4: the hem. A critic found "a detached dark square at
      // (955-962, 350-356), 8 px below the checkered flag's bottom edge,
      // floating on the wall." It was the bottom check of the one column
      // whose drape ran three units lower than its neighbours': a dark square
      // on a dark wall with dark squares either side of it, so its own column
      // gave it nothing to belong to. Cloth has a hem, and a hem is what ties
      // the columns together, so there is one now -- a continuous band in a
      // value that reads against the wall, following each column's drape.
      rect(852, 60, 72, 5, "#2b3040")
      rect(854, 64, 68, 6, "#131620")
      for (var fc = 0; fc < 6; fc++) {
        var drape = Math.round(Math.abs(Math.sin((fc + 0.4) * 0.7)) * 3)
        for (var fr = 0; fr < 7; fr++) {
          rect(856 + fc * 11, 68 + drape + fr * 11, 11, 11,
               (fr + fc) % 2 === 0 ? "#8a90a0" : "#131620")
        }
        rect(856 + fc * 11, 68 + drape + 77, 11, 3, "#5a6070")
      }

      // Traffic cone. It used to stand at x=46 with its base at y=400, and
      // the KART BODY card's top edge falls at y=386 -- so the card cut the
      // cone off at the ankles, with no base, no floor contact and no shadow.
      // Moved back and right, it stands on open floor 14 px above the card
      // and 144 px clear of the dais, with its whole base visible.
      var coneX = 250, coneBase = 372
      ctx.save()
      ctx.translate(stall.vx(coneX + 28), stall.vy(coneBase + 3))
      ctx.scale(34 * u, 7 * u)
      var coneShadow = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
      coneShadow.addColorStop(0, Qt.rgba(0, 0, 0, 0.6))
      coneShadow.addColorStop(1, Qt.rgba(0, 0, 0, 0))
      ctx.fillStyle = coneShadow
      ctx.beginPath()
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.fill()
      ctx.restore()
      rect(coneX, coneBase - 8, 56, 8, "#7a3a14")
      rect(coneX, coneBase - 10, 56, 2, "#94491c")
      for (var cn = 0; cn < 6; cn++)
        rect(coneX + 6 + cn * 3, coneBase - 8 - cn * 11 - 11, 44 - cn * 6, 11,
             cn === 2 || cn === 3 ? "#d8d9dd" : "#c25a1c")

      // There is no oil drum. Round one drew one on the right, where the
      // COLOR panel covered it, and the self-report counted it as scenery the
      // reader could see. Moved to the left it fell behind the KART BODY
      // card instead, so it is gone rather than claimed.

      // ---------------------------------------------------------- vignette
      var vig = ctx.createRadialGradient(stall.vx(600), stall.vy(300), stall.vs(240),
                                         stall.vx(600), stall.vy(300), stall.vs(760))
      vig.addColorStop(0, Qt.rgba(0, 0, 0, 0))
      vig.addColorStop(1, Qt.rgba(0, 0, 0, 0.72))
      ctx.fillStyle = vig
      ctx.fillRect(0, 0, width, height)
    }
  }

  // The terminal's green CRT copy, and the poster's, as real text so they
  // stay crisp and stay plain text.
  Column {
    x: stall.vx(56)
    y: stall.vy(112)
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

  KartSprite {
    x: stall.vx(256)
    y: stall.vy(98)
    width: stall.vs(144)
    height: stall.vs(70)
    body: 2
    paint: "#c8492f"
    showNumber: false
    shadow: false
    dim: 0.92
  }

  Column {
    x: stall.vx(252)
    y: stall.vy(176)
    width: stall.vs(152)
    spacing: stall.vs(4)
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "PRACTICE"
      textFormat: Text.PlainText
      color: Theme.amberGlow
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
      color: Theme.amberGlow
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.max(7, stall.vs(21))
      font.letterSpacing: stall.vs(1)
    }
  }

  onUnitChanged: scene.requestPaint()
  onCornerRadiusChanged: scene.requestPaint()
}
