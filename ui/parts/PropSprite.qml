import QtQuick
import "../"

// One piece of roadside furniture standing on the track: a tyre wall, a
// sponsor banner, a timing board, the start gantry, a roller door, a drum or
// a cone. The cars are not here: they are cells of a baked sheet, drawn by
// CarSprite.
//
// WHY THIS IS A SPRITE AND NOT A LIVE RENDERER
//
// A track has a couple of dozen props in view, changing size on every one of
// sixty frames a second. So this draws once, into a canvas of a fixed size,
// and the track view scales it with `scale` and moves it with `x` and `y`.
// Neither of those touches the canvas, so a prop that crosses the whole
// screen and grows from a speck to half its height costs one textured blit
// per frame and no drawing at all. `smooth: false` keeps the enlargement
// nearest-neighbour, which is the pixel look the game wants and is also the
// cheapest filter there is.
//
// THE ANCHOR is the bottom centre of the ITEM, and every kind is drawn
// standing on that point, so the track view positions a sprite by where it
// touches the ground and never has to know how tall it is. The canvas is
// taller than the item by `shadowRoom`: the long shadow toward the camera is
// drawn BELOW the contact point, and the item does not clip it.
//
// GOLDEN-HOUR PROTOTYPE. One key light, the sun, low and ahead-right of every
// object, so the face a driver sees is in shadow, the sun-side silhouette
// carries one warm rim, and a long soft shadow runs toward the camera.
Item {
  id: sprite

  // One of: tireWall, banner, timingBoard, gantry, rollerDoor, drum, cone.
  property string kind: "cone"
  // What a banner or a board says.
  property string label: "TURBO"
  // Dims a sprite that is far away, so distance reads as light as well as size.
  property real dim: 1.0

  readonly property bool isArch: kind === "rollerDoor" || kind === "gantry"

  // The sheet. Roadside furniture is tall, arches span the road.
  readonly property int sheetW: isArch ? 320 : 128
  readonly property int sheetH: isArch ? 200 : 176
  // Extra canvas below the contact point, for the shadow toward the camera.
  readonly property int shadowRoom: isArch ? 0 : 34

  width: sheetW
  height: sheetH
  transformOrigin: Item.Bottom
  smooth: false
  antialiasing: false

  Canvas {
    id: surface
    width: sprite.sheetW
    height: sprite.sheetH + sprite.shadowRoom
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
    antialiasing: false

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      paintProp(ctx)
    }

    readonly property color rim: "#f0b07a"

    function rimColor(strength) {
      var d = sprite.dim
      return Qt.rgba(rim.r * d, rim.g * d, rim.b * d, Math.min(1, strength))
    }

    // ------------------------------------------------------ the shadow
    // Long, soft, toward the camera -- which on the sheet is down and, with
    // the sun off to the right, a little to the left. A gradient so it
    // fades out rather than ending at a line.
    function longShadow(ctx, x0, x1, yBase, len, lean) {
      var g = ctx.createLinearGradient(0, yBase, 0, yBase + len)
      g.addColorStop(0.0, Qt.rgba(0.08, 0.02, 0.09, 0.52))
      g.addColorStop(0.55, Qt.rgba(0.08, 0.02, 0.09, 0.30))
      g.addColorStop(1.0, Qt.rgba(0.08, 0.02, 0.09, 0.0))
      ctx.fillStyle = g
      ctx.beginPath()
      ctx.moveTo(x0, yBase)
      ctx.lineTo(x1, yBase)
      ctx.lineTo(x1 - lean + (x1 - x0) * 0.12, yBase + len)
      ctx.lineTo(x0 - lean - (x1 - x0) * 0.12, yBase + len)
      ctx.closePath()
      ctx.fill()
    }

    // ------------------------------------------------- roadside furniture
    // Billboards: the camera looks at these nearly face on, so they are drawn
    // flat -- silhouettes in the cool purple, with one warm rim along the
    // sun side, upper right, and a long shadow toward the camera.
    function paintProp(ctx) {
      var w = width
      var h = sprite.sheetH
      var d = sprite.dim
      function tint(c, k) {
        return Qt.rgba(Math.min(1, c.r * k * d), Math.min(1, c.g * k * d),
                       Math.min(1, c.b * k * d), 1)
      }
      var ink = Qt.rgba(0.16, 0.055, 0.15, 1)      // #280e27, the bar's signage
      var post = Qt.rgba(0.22, 0.09, 0.22, 1)
      var rubber = Qt.rgba(0.11, 0.05, 0.11, 1)
      var magenta = Qt.rgba(1.0, 0.31, 0.64, 1)   // #ff4fa3
      var cream = Theme.cream
      var rimW = 1.5

      // a block with its warm rim on the top and right edges
      function block(x, y, bw, bh, col, rimTop, rimRight) {
        ctx.fillStyle = col
        ctx.fillRect(x, y, bw, bh)
        ctx.fillStyle = rimColor(0.95)
        if (rimTop !== false)
          ctx.fillRect(x, y, bw, rimW)
        if (rimRight !== false)
          ctx.fillRect(x + bw - rimW, y, rimW, bh)
      }
      function mono(px) {
        return "bold " + px + "px " + Theme.mono
      }

      // the shadow under everything except an arch, which the road runs
      // through rather than past
      if (!sprite.isArch) {
        longShadow(ctx, w * 0.30, w * 0.70, h - 16, sprite.shadowRoom + 12, 16)
        ctx.fillStyle = Qt.rgba(0.05, 0.01, 0.06, 0.36)
        ctx.beginPath()
        ctx.ellipse(w * 0.16, h - 14, w * 0.68, 13)
        ctx.fill()
      }

      if (sprite.kind === "tireWall") {
        var rows = 4
        var cols = 3
        var tw = w / cols
        var th = (h - 24) / rows
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            var offset = (r % 2) * tw * 0.5
            var x = c * tw + offset - tw * 0.25
            var y = h - 18 - (r + 1) * th
            block(x, y, tw * 0.92, th * 0.92, tint(rubber, 1 + r * 0.10), true, true)
            ctx.fillStyle = tint(post, 1.3)
            ctx.fillRect(x + tw * 0.30, y + th * 0.28, tw * 0.32, th * 0.36)
          }
          ctx.fillStyle = tint(r % 2 === 0 ? Theme.amberDeep : cream, 0.7)
          ctx.fillRect(0, h - 18 - (r + 1) * th - 3, w, 3)
        }
        return
      }

      if (sprite.kind === "drum") {
        var dw = w * 0.56
        var dx = (w - dw) / 2
        var dh = h * 0.62
        var dy = h - 16 - dh
        block(dx, dy, dw, dh, tint(Theme.amberDeep, 0.62), true, true)
        ctx.fillStyle = tint(Theme.amberDeep, 0.85)
        ctx.fillRect(dx + dw * 0.62, dy + rimW, dw * 0.38 - rimW, dh - rimW)
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(dx, dy + dh * 0.20, dw, dh * 0.08)
        ctx.fillRect(dx, dy + dh * 0.68, dw, dh * 0.08)
        return
      }

      if (sprite.kind === "cone") {
        var bx = w * 0.5
        var by = h - 16
        var ch = h * 0.52
        ctx.fillStyle = tint(Theme.amberDeep, 0.72)
        ctx.beginPath()
        ctx.moveTo(bx, by - ch)
        ctx.lineTo(bx + w * 0.24, by)
        ctx.lineTo(bx - w * 0.24, by)
        ctx.closePath()
        ctx.fill()
        // the rim: the sun-side slope of the cone
        ctx.strokeStyle = rimColor(0.95)
        ctx.lineWidth = rimW
        ctx.beginPath()
        ctx.moveTo(bx, by - ch)
        ctx.lineTo(bx + w * 0.24, by)
        ctx.stroke()
        ctx.fillStyle = tint(cream, 0.72)
        ctx.fillRect(bx - w * 0.155, by - ch * 0.52, w * 0.31, ch * 0.16)
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(bx - w * 0.30, by - 6, w * 0.60, 6)
        return
      }

      if (sprite.kind === "banner") {
        // A period sponsor banner: mono type, near-black on magenta, strung
        // between two posts, with the sun catching its top edge.
        var bw = w * 0.92
        var bx0 = (w - bw) / 2
        var by0 = h * 0.16
        var bh = h * 0.30
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(bx0 + 3, by0 + bh * 0.5, 4, h - 16 - by0 - bh * 0.5)
        ctx.fillRect(bx0 + bw - 7, by0 + bh * 0.5, 4, h - 16 - by0 - bh * 0.5)
        block(bx0, by0, bw, bh, tint(ink, 1.0), true, true)
        ctx.fillStyle = tint(magenta, 0.62)
        ctx.fillRect(bx0 + 3, by0 + 3, bw - 6, 2)
        ctx.fillRect(bx0 + 3, by0 + bh - 5, bw - 6, 2)
        ctx.fillStyle = tint(magenta, 0.95)
        ctx.font = mono(Math.round(bh * 0.52))
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(sprite.label, w / 2, by0 + bh * 0.52)
        return
      }

      if (sprite.kind === "timingBoard") {
        // A timing board on one post: three rows of lit digits on a dark
        // face, the top edge rimmed by the sun.
        var tbw = w * 0.80
        var tbx = (w - tbw) / 2
        var tby = h * 0.05
        var tbh = h * 0.50
        ctx.fillStyle = tint(post, 1.0)
        ctx.fillRect(w * 0.47, tby + tbh, w * 0.06, h - 16 - tby - tbh)
        block(tbx, tby, tbw, tbh, tint(ink, 1.0), true, true)
        ctx.fillStyle = tint(magenta, 0.62)
        ctx.fillRect(tbx + 3, tby + 3, tbw - 6, 1.5)
        ctx.font = mono(Math.round(tbh * 0.22))
        ctx.textAlign = "left"
        ctx.textBaseline = "middle"
        var rowsText = ["1  21", "2  34", "3  55"]
        for (var rt = 0; rt < rowsText.length; rt++) {
          ctx.fillStyle = tint(rt === 0 ? Theme.amberGlow : cream, 0.85)
          ctx.fillText(rowsText[rt], tbx + tbw * 0.12, tby + tbh * (0.24 + rt * 0.26))
        }
        return
      }

      if (sprite.kind === "gantry") {
        // The start gantry: two posts, a beam with a checkered band and the
        // name of the race across it, the sun on its top edge.
        // The beam sits low -- a third of the way down the sheet -- so it
        // crosses the road below the answer field rather than through it.
        var gTop = h * 0.30
        var gJamb = w * 0.06
        var gBeam = h * 0.20
        var gFloor = h - 12
        block(0, gTop, w, gBeam, tint(ink, 1.0), true, true)
        block(0, gTop + gBeam, gJamb, gFloor - gTop - gBeam, tint(post, 1.0), false, true)
        block(w - gJamb, gTop + gBeam, gJamb, gFloor - gTop - gBeam, tint(post, 1.0), false, true)
        var sq = h * 0.045
        for (var gc = 0; gc < Math.ceil(w / sq); gc++)
          for (var gr = 0; gr < 2; gr++) {
            ctx.fillStyle = tint((gc + gr) % 2 === 0 ? cream : ink, 0.9)
            ctx.fillRect(gc * sq, gTop + gBeam - sq * 2 - 2 + gr * sq, sq, sq)
          }
        ctx.fillStyle = tint(magenta, 0.95)
        ctx.font = mono(Math.round(gBeam * 0.46))
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText(sprite.label, w / 2, gTop + (gBeam - sq * 2) * 0.52)
        // magenta stripes on the posts
        ctx.fillStyle = tint(magenta, 0.7)
        for (var gs = 0; gs < 6; gs++) {
          var gy = gTop + gBeam + 20 + gs * ((gFloor - gTop - gBeam - 20) / 6)
          ctx.fillRect(0, gy, gJamb, 4)
          ctx.fillRect(w - gJamb, gy + 3, gJamb, 4)
        }
        return
      }

      if (sprite.kind === "rollerDoor") {
        // The sector landmark the design names: "the sevens run under the
        // roller door". So the curtain is rolled up and the opening is clear,
        // because the track goes through it.
        var doorTop = h * 0.30
        var jamb = w * 0.075
        var head = h * 0.46
        var floorY = h - 12
        block(0, doorTop, w, head - doorTop, tint(ink, 1.0), true, true)      // lintel
        block(0, head, jamb, floorY - head, tint(post, 1.0), false, true)     // left jamb
        block(w - jamb, head, jamb, floorY - head, tint(post, 1.0), false, true)
        // the rolled-up curtain, hanging out of the lintel
        for (var s = 0; s < 4; s++) {
          ctx.fillStyle = tint(post, s % 2 === 0 ? 1.4 : 1.1)
          ctx.fillRect(jamb, head + s * 4, w - jamb * 2, 3)
        }
        ctx.fillStyle = tint(magenta, 0.7)
        for (var c2 = 0; c2 < 7; c2++) {
          var cy2 = head + 30 + c2 * ((floorY - head - 30) / 7)
          ctx.fillRect(0, cy2, jamb, 6)
          ctx.fillRect(w - jamb, cy2 + 4, jamb, 6)
        }
        ctx.fillStyle = tint(magenta, 0.8)
        ctx.fillRect(w * 0.16, doorTop + (head - doorTop) * 0.62, w * 0.68, 3)
        return
      }
    }
  }

  onKindChanged: surface.requestPaint()
  onLabelChanged: surface.requestPaint()
  onDimChanged: surface.requestPaint()
}
