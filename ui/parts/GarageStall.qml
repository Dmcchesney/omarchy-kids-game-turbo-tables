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
  readonly property real daisY: 430
  readonly property real daisRadius: 248

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

      // The yard beyond the doorway: a low roofline, then lit windows of
      // uneven width and height at uneven spacing. Round one drew a regular
      // 7 x 5 grid of identical dashes here and it read as a spreadsheet.
      rect(470, 236, 350, 4, "#0b2029")
      rect(486, 196, 96, 40, "#0d2731")
      rect(600, 172, 74, 64, "#0d2731")
      rect(692, 206, 112, 30, "#0d2731")
      var winX = [492, 508, 530, 552, 566, 606, 622, 640, 606, 630, 700, 722, 748, 776, 700, 736]
      var winY = [204, 220, 204, 218, 204, 180, 180, 182, 208, 206, 212, 212, 214, 212, 224, 224]
      var winW = [10, 16, 14, 8, 12, 10, 12, 18, 16, 10, 14, 18, 20, 12, 22, 14]
      var winH = [8, 6, 10, 8, 12, 14, 10, 8, 12, 16, 8, 10, 6, 12, 6, 8]
      for (var w = 0; w < winX.length; w++)
        rect(winX[w], winY[w], winW[w], winH[w], (w % 3 === 0) ? "#2f8790" : "#1a5a66")
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

      // ------------------------------------------------------- tire walls
      function tyreStack(x, yBase, count, w) {
        for (var t = 0; t < count; t++) {
          var ty = yBase - t * 26
          rect(x, ty, w, 24, "#191b21")
          rect(x + 3, ty + 3, w - 6, 18, "#101216")
          rect(x, ty, w, 4, "#24272f")
        }
      }
      tyreStack(24, 316, 4, 84)
      tyreStack(1096, 316, 5, 80)
      tyreStack(1010, 316, 3, 76)

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

      // --------------------------------------------------------- turntable
      var dx0 = stall.daisX
      var dr = stall.daisRadius
      ellipse(dx0, 434, dr + 8, 65, "#101319")
      ellipse(dx0, 430, dr, 60, "#1d222c")
      ellipse(dx0, 428, dr - 18, 54, "#252b37")
      ellipse(dx0, 425, dr - 62, 41, "#2c3341")
      // Amber rim light on the near edge of the dais. Round one stroked this
      // in amberDeep at 2.5 units and it was invisible at 1:1 -- the report
      // called a rim a feature that only a 2.4x brightness boost could find.
      ctx.save()
      ctx.beginPath()
      ctx.translate(stall.vx(dx0), stall.vy(430))
      ctx.scale(dr * u, 60 * u)
      ctx.arc(0, 0, 1, 0, Math.PI * 2, false)
      ctx.restore()
      ctx.strokeStyle = Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.75)
      ctx.lineWidth = Math.max(1.5, 3 * u)
      ctx.stroke()

      // Checker ring around the dais edge, in values that read without help.
      for (var a = 0; a < 40; a++) {
        var ang = (a / 40) * Math.PI * 2
        var cx2 = dx0 + Math.cos(ang) * (dr - 10)
        var cy2 = 430 + Math.sin(ang) * 56
        rect(cx2 - 7, cy2 - 3.5, 14, 7, a % 2 === 0 ? "#5a6274" : "#14171f")
      }

      // ------------------------------------------------------ work lights
      function workLight(x, y, w) {
        rect(x + w * 0.42, y - 22, 5, 22, "#2a2e39")
        rect(x - 6, y, w + 12, 12, "#31353f")
        rect(x, y + 10, w, 7, Theme.amberGlow)
        rect(x, y + 17, w, 3, Theme.amberDeep)
        var glow = ctx.createRadialGradient(stall.vx(x + w / 2), stall.vy(y + 16), 0,
                                            stall.vx(x + w / 2), stall.vy(y + 16), stall.vs(w * 1.9))
        glow.addColorStop(0, Qt.rgba(1, 0.78, 0.36, 0.30))
        glow.addColorStop(0.45, Qt.rgba(1, 0.72, 0.3, 0.10))
        glow.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
        ctx.fillStyle = glow
        ctx.fillRect(stall.vx(x + w / 2 - w * 1.9), stall.vy(y + 16 - w * 1.9),
                     stall.vs(w * 3.8), stall.vs(w * 3.8))
        // The cone of light falling toward the floor. It fades to nothing
        // over its own length: round one filled it at a flat alpha and left a
        // hard diagonal edge across the tool chest with no source above it.
        var cone = ctx.createLinearGradient(0, stall.vy(y + 18), 0, stall.vy(490))
        cone.addColorStop(0, Qt.rgba(1, 0.74, 0.33, 0.10))
        cone.addColorStop(0.55, Qt.rgba(1, 0.74, 0.33, 0.035))
        cone.addColorStop(1, Qt.rgba(1, 0.74, 0.33, 0))
        ctx.fillStyle = cone
        ctx.beginPath()
        ctx.moveTo(stall.vx(x), stall.vy(y + 18))
        ctx.lineTo(stall.vx(x + w), stall.vy(y + 18))
        ctx.lineTo(stall.vx(x + w + 140), stall.vy(490))
        ctx.lineTo(stall.vx(x - 140), stall.vy(490))
        ctx.closePath()
        ctx.fill()
      }
      // A matched pair: same length, same baseline. Round one had them 186
      // and 194 units long, hung four units apart, and called them a pair.
      workLight(206, 34, 180)
      workLight(794, 34, 180)

      // A pool of warm light on the floor under the kart.
      var pool = ctx.createRadialGradient(stall.vx(stall.daisX), stall.vy(426), 0,
                                          stall.vx(stall.daisX), stall.vy(426), stall.vs(300))
      pool.addColorStop(0, Qt.rgba(1, 0.75, 0.34, 0.18))
      pool.addColorStop(1, Qt.rgba(1, 0.7, 0.3, 0))
      ctx.fillStyle = pool
      ctx.fillRect(stall.vx(stall.daisX - 300), stall.vy(350), stall.vs(600), stall.vs(210))

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
      for (var fr = 0; fr < 7; fr++) {
        for (var fc = 0; fc < 6; fc++) {
          var lightSquare = (fr + fc) % 2 === 0
          rect(856 + fc * 11, 66 + fr * 11 + (fc > 3 ? 4 : 0), 11, 11,
               lightSquare ? "#c9cdd8" : "#15171d")
        }
      }
      rect(852, 62, 72, 4, "#2b3040")

      // Traffic cone, near left.
      rect(46, 400, 56, 8, "#7a3a14")
      for (var cn = 0; cn < 6; cn++)
        rect(52 + cn * 3, 400 - cn * 11 - 11, 44 - cn * 6, 11,
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
      color: "#2f7d51"
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
