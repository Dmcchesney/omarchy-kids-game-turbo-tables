import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts"
import "../../ui/parts/CarMeta.js" as CarMeta
import "../../dev"

// The one car renderer, measured on what it DRAWS: which cell of the sheet an
// Image is clipped to, where that cell hangs from the anchor, where the
// number lands and whether it is shown, and that nothing is ever smoothed or
// scaled by a fraction. The last case opens the real garage and asserts the
// car in the child's roster row is the car on the dais.
//
// Run it:
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
//     qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml
Item {
  id: root
  width: 1920
  height: 1080

  CarSprite {
    id: car
    x: 400
    y: 300
  }

  MemoryStore { id: memory }

  // A pixel reader for the sheet: a canvas the size of a 1.0-row cell that
  // draws one cell of the sheet file and hands its pixels back. QtTest's
  // grabImage cannot be used for this -- under the offscreen platform it
  // returns the window's blank background -- and the canvas reads the PNG
  // the sprite reads, through Qt's own decoder.
  Canvas {
    id: reader
    width: 192
    height: 128
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    smooth: false
  }

  Component {
    id: garageFactory
    Garage {
      width: 1920
      height: 1080
    }
  }

  // The contract's six rows: camera, scale, cell width, cell height, row y.
  readonly property var rows: [
    { camera: "stall", scale: 1.0,  w: 192, h: 128, y: 0,   row: 0 },
    { camera: "stall", scale: 0.5,  w: 96,  h: 64,  y: 128, row: 1 },
    { camera: "stall", scale: 0.25, w: 48,  h: 32,  y: 192, row: 2 },
    { camera: "road",  scale: 1.0,  w: 192, h: 128, y: 224, row: 3 },
    { camera: "road",  scale: 0.5,  w: 96,  h: 64,  y: 352, row: 4 },
    { camera: "road",  scale: 0.25, w: 48,  h: 32,  y: 416, row: 5 }
  ]

  TestCase {
    id: suite
    name: "CarSprite"
    when: windowShown

    function applyTheme() {
      Theme.background = Color.background
      Theme.foreground = Color.foreground
      Theme.accent = Color.accent
      Theme.menuBackground = Color.menu.background
      Theme.menuText = Color.menu.text
      Theme.menuBorder = Color.menu.border
      Theme.fontFamily = Style.font.family
      Theme.resolvedFontFamily = Style.font.resolvedFamily
      Theme.fontBaseSize = Style.font.baseSize
    }

    function initTestCase() {
      applyTheme()
      Store.backend = memory
    }

    function init() {
      car.body = 0
      car.paint = 0
      car.number = 7
      car.camera = "stall"
      car.yaw = 0
      car.sheetScale = 1.0
      car.pixelScale = 1
      car.showNumber = true
      car.lampGlow = 0
    }

    function cellImage() { return findChild(car, "cell") }
    function plateItem() { return findChild(car, "plate") }
    function digitsText() { return findChild(car, "digits") }

    // ------------------------------------------------------------------
    // Every row of both cameras, every column: the Image is clipped to
    // exactly that cell of the sheet, and the cell is where the contract
    // says it is.
    function test_01_every_row_and_every_column_selects_its_cell() {
      var img = cellImage()
      verify(img !== null, "the cell Image is reachable")
      for (var r = 0; r < root.rows.length; r++) {
        var spec = root.rows[r]
        car.camera = spec.camera
        car.sheetScale = spec.scale
        for (var yaw = 0; yaw < 8; yaw++) {
          car.yaw = yaw
          var where = spec.camera + " " + spec.scale + " yaw " + yaw
          compare(car.row, spec.row, "row for " + where)
          compare(car.cellW, spec.w, "cell width for " + where)
          compare(car.cellH, spec.h, "cell height for " + where)
          compare(car.cellX, yaw * spec.w, "cell x for " + where)
          compare(car.cellY, spec.y, "cell y for " + where)
          compare(img.sourceClipRect.x, yaw * spec.w, "clip x for " + where)
          compare(img.sourceClipRect.y, spec.y, "clip y for " + where)
          compare(img.sourceClipRect.width, spec.w, "clip width for " + where)
          compare(img.sourceClipRect.height, spec.h, "clip height for " + where)
        }
      }
      // The last row ends at the sheet's bottom edge: no cell hangs off it.
      var last = root.rows[root.rows.length - 1]
      compare(last.y + last.h, CarMeta.SHEET_H)
      compare(8 * 192, CarMeta.SHEET_W)
    }

    // Yaw wraps rather than falling off the sheet, so a heading that comes
    // round past 360 is still a column.
    function test_02_yaw_wraps() {
      car.yaw = 8
      compare(car.column, 0)
      car.yaw = -1
      compare(car.column, 7)
      car.yaw = 13
      compare(car.column, 5)
    }

    // ------------------------------------------------------------------
    // The anchor is the contact point. Where the bake says where in the cell
    // the wheels touch (`ground`), that point sits on the item's origin;
    // where it does not, the cell's bottom centre does. Either way the cell
    // is exactly cell x upscale pixels, for every upscale and every row.
    function test_03_anchor_is_the_contact_point() {
      var img = cellImage()
      var meta = CarMeta.forBody("coupe")
      for (var r = 0; r < root.rows.length; r++) {
        var spec = root.rows[r]
        car.camera = spec.camera
        car.sheetScale = spec.scale
        var ground = (meta.ground && meta.ground[spec.camera]) ? meta.ground[spec.camera] : null
        for (var ps = 1; ps <= 3; ps++) {
          car.pixelScale = ps
          var where = spec.camera + " " + spec.scale + " x" + ps
          compare(car.drawnWidth, spec.w * ps, "drawn width " + where)
          compare(car.drawnHeight, spec.h * ps, "drawn height " + where)
          compare(img.width, spec.w * ps, "image width " + where)
          compare(img.height, spec.h * ps, "image height " + where)
          var ax = ground ? Math.round(ground[0] * spec.scale) * ps : spec.w * ps / 2
          var ay = ground ? Math.round(ground[1] * spec.scale) * ps : spec.h * ps
          compare(car.anchorDx, ax, "anchor dx " + where)
          compare(car.anchorDy, ay, "anchor dy " + where)
          compare(img.x, -ax, "image x " + where)
          compare(img.y, -ay, "image y " + where)
          // In the parent's coordinates the contact point IS the item's
          // position.
          var contact = img.mapToItem(root, ax, ay)
          compare(contact.x, car.x, "contact x in the parent " + where)
          compare(contact.y, car.y, "contact y in the parent " + where)
          // And it is inside the cell: a car never stands outside its own
          // picture.
          verify(ax >= 0 && ax <= img.width && ay >= 0 && ay <= img.height,
                 "contact point inside the cell " + where)
        }
      }
      if (!ground)
        console.log("carsprite: coupe meta has no ground point; the bottom-centre fallback was exercised")
      // The item itself has no size: nothing anchors to its box by mistake.
      compare(car.width, 0)
      compare(car.height, 0)
    }

    // ------------------------------------------------------------------
    // The number is placed from the meta, scaled with the row and the
    // upscale, tilted as the meta says, and hidden where the meta hides it
    // or where it would be too small to read.
    function test_04_number_overlay_follows_the_meta() {
      var meta = CarMeta.forBody("coupe")
      verify(meta !== null, "coupe has meta")
      verify(meta.number.stall.length === 8 && meta.number.road.length === 8,
             "eight number rects per camera")
      var img = cellImage()
      var plate = plateItem()
      var digits = digitsText()
      verify(plate !== null && digits !== null)

      // One visible yaw per camera, at the 1.0 row, at 2x.
      var cameras = ["stall", "road"]
      for (var c = 0; c < cameras.length; c++) {
        var cam = cameras[c]
        var rects = meta.number[cam]
        var shown = -1
        var hidden = -1
        for (var yaw = 0; yaw < 8; yaw++) {
          if (rects[yaw].visible !== false && shown < 0) shown = yaw
          if (rects[yaw].visible === false && hidden < 0) hidden = yaw
        }
        verify(shown >= 0, cam + ": at least one yaw shows the number")

        car.camera = cam
        car.number = 7
        car.sheetScale = 1.0
        car.pixelScale = 2
        car.yaw = shown
        var rect = rects[shown]
        verify(plate.visible, cam + " yaw " + shown + ": the number is drawn")
        // The bake writes fractional cell pixels; the sprite rounds them to
        // whole sheet pixels before upscaling, so a plate never straddles
        // a pixel boundary.
        compare(plate.x, img.x + Math.round(rect.x) * 2, cam + ": number x")
        compare(plate.y, img.y + Math.round(rect.y) * 2, cam + ": number y")
        compare(plate.width, Math.round(rect.w) * 2, cam + ": number width")
        compare(plate.height, Math.round(rect.h) * 2, cam + ": number height")
        // The tilt is the meta's, and it is rasterised into the squares: no
        // item is rotated, because rotating a pixel grid resamples it.
        compare(car.numberAngle, rect.angle || 0, cam + ": number tilt")
        compare(plate.rotation, 0, cam + ": the plate item is never rotated")
        var seven = JSON.stringify(car.digitSquares)
        verify(car.digitSquares.length > 0, cam + ": a 7 has ink")
        car.number = 42
        verify(car.digitSquares.length > 0, cam + ": a 42 has ink")
        verify(JSON.stringify(car.digitSquares) !== seven, cam + ": 42 is not drawn as 7")
        // Every square is a whole sheet pixel: on the upscale's grid, inside
        // the rect sideways, and within one sheet pixel of it above and
        // below (the slack CarMeta allows, which the panel covers).
        var slack = CarMeta.NUMBER_SLACK * 2
        for (var s = 0; s < car.digitSquares.length; s++) {
          var sq = car.digitSquares[s]
          compare(sq[0] % 2, 0, cam + ": square x on the 2x grid")
          compare(sq[1] % 2, 0, cam + ": square y on the 2x grid")
          verify(sq[0] >= 0 && sq[0] + 2 <= plate.width, cam + ": square inside the rect (x)")
          verify(sq[1] >= -slack && sq[1] + 2 <= plate.height + slack, cam + ": square within the slack (y)")
        }

        // At the 0.5 row the rect halves and rounds; at 1x that is a whole
        // number of pixels.
        car.sheetScale = 0.5
        car.pixelScale = 1
        compare(plate.x, img.x + Math.round(rect.x * 0.5), cam + ": half-row number x")
        compare(plate.width, Math.round(rect.w * 0.5), cam + ": half-row number width")

        if (hidden >= 0) {
          car.sheetScale = 1.0
          car.pixelScale = 3
          car.yaw = hidden
          verify(!plate.visible, cam + " yaw " + hidden + ": the meta hides the number and so does the sprite")
        } else {
          console.log("carsprite: " + cam + " meta hides the number at no yaw; the hidden case is not exercised")
        }
      }

      // Too small to read: the quarter row at 1x is a few pixels of plate.
      car.camera = "stall"
      car.yaw = 0
      car.sheetScale = 0.25
      car.pixelScale = 1
      verify(car.numberH < car.numberMinPx, "the quarter-row roundel is under the floor")
      verify(!plate.visible, "no number on a plate too small to read")

      // And the host can switch it off outright.
      car.sheetScale = 1.0
      car.pixelScale = 3
      verify(plate.visible)
      car.showNumber = false
      verify(!plate.visible)
    }

    // ------------------------------------------------------------------
    // Nothing is ever smoothed, and the scale is a whole number however the
    // host asks for it.
    function test_05_never_smoothed_never_fractional() {
      var img = cellImage()
      var digits = digitsText()
      compare(car.smooth, false)
      compare(img.smooth, false)
      compare(img.mipmap, false)
      compare(digits.smooth, false)
      compare(img.fillMode, Image.Stretch)

      // `pixelScale` is an int property: a host cannot even hand it a
      // fraction. What it can hand it is out of range, and that clamps.
      car.pixelScale = 0
      compare(car.ps, 1)
      car.pixelScale = 9
      compare(car.ps, 3)
      car.pixelScale = 2
      car.sheetScale = 0.6
      compare(car.row, 1, "an off-contract scale snaps to the nearest row")
      compare(img.width, 96 * 2)
      car.sheetScale = 0.1
      compare(car.row, 2)
      for (var ps = 1; ps <= 3; ps++) {
        car.pixelScale = ps
        compare(img.width % car.cellW, 0, "width is a whole multiple of the cell")
        compare(img.height % car.cellH, 0, "height is a whole multiple of the cell")
      }
    }

    // ------------------------------------------------------------------
    // The row-and-upscale choice the track makes, from the width the
    // projection asks for.
    function test_06_fit_picks_the_nearest_row_and_a_whole_upscale() {
      var f = CarMeta.fit(461)
      compare(f.sheetScale, 1.0)
      compare(f.pixelScale, 2)
      compare(f.width, 384)
      f = CarMeta.fit(576)
      compare(f.sheetScale, 1.0)
      compare(f.pixelScale, 3)
      f = CarMeta.fit(50)
      compare(f.sheetScale, 0.25)
      compare(f.pixelScale, 1)
      compare(f.width, 48)
      f = CarMeta.fit(130)
      compare(f.sheetScale, 0.5)
      compare(f.pixelScale, 1)
      f = CarMeta.fit(1000)
      compare(f.width, 576, "clamped at three times the largest cell")
      f = CarMeta.fit(0)
      compare(f.width, 48, "clamped at the smallest cell")
      // Every answer over a sweep is one of the seven allowed widths.
      var allowed = [48, 96, 144, 192, 288, 384, 576]
      for (var px = 1; px <= 1200; px += 7) {
        var r = CarMeta.fit(px)
        verify(allowed.indexOf(r.width) >= 0, "fit(" + px + ") gave " + r.width)
        compare(r.pixelScale, Math.round(r.pixelScale))
        verify(r.pixelScale >= 1 && r.pixelScale <= 3)
      }
    }

    // The arithmetic only: a heading to the right counts the columns backwards
    // from 8, because the bake turned the car counter-clockwise. WHICH way the
    // sheet actually faces is not assumed here; test_12 reads it off the
    // sheet's pixels.
    function test_07_column_for_heading() {
      compare(CarMeta.columnForHeading(0), 0)
      compare(CarMeta.columnForHeading(22), 0)
      compare(CarMeta.columnForHeading(23), 7)
      compare(CarMeta.columnForHeading(45), 7)
      compare(CarMeta.columnForHeading(-45), 1)
      compare(CarMeta.columnForHeading(-30), 1)
      compare(CarMeta.columnForHeading(180), 4)
      compare(CarMeta.columnForHeading(-180), 4)
      compare(CarMeta.columnForHeading(400), 7)
      compare(CarMeta.columnForHeading(-400), 1)
    }

    // ------------------------------------------------------------------
    // Body and paint indices map to the contract's file names through Theme,
    // and wrap rather than escape the six-by-eight set.
    function test_08_sheet_file_from_body_and_paint() {
      car.body = 3
      car.paint = 5
      compare(car.bodyName, "saloon")
      compare(car.paintName, "purple")
      verify(String(car.sheetSource).indexOf("/saloon/purple.png") > 0, String(car.sheetSource))
      car.body = -1
      compare(car.bodyName, "pickup")
      car.paint = 8
      compare(car.paintName, "red")
      compare(Theme.bodySheetNames.length, Theme.bodyNames.length)
      compare(Theme.paintSheetNames.length, Theme.paints.length)
      compare(Theme.paintSheetNames.length, Theme.paintNames.length)
    }

    // The tail lamps come from the meta too, road camera only, and only
    // glow when asked.
    function test_09_lamps_from_meta() {
      var meta = CarMeta.forBody("coupe")
      car.camera = "road"
      car.yaw = 0
      if (!meta.lamps || !meta.lamps.road) {
        console.log("carsprite: coupe meta lists no lamps; the glow is not exercised")
        return
      }
      verify(car.lamps !== null)
      compare(car.lamps.length, meta.lamps.road[0].tail.length)
      car.yaw = 3
      compare(car.lamps.length, meta.lamps.road[3].tail.length, "the lamps follow the yaw")
      car.yaw = 0
      car.camera = "stall"
      if (meta.lamps.stall)
        compare(car.lamps.length, meta.lamps.stall[0].tail.length, "stall lamps where the meta lists them")
      else
        compare(car.lamps, null, "no lamps on the stall camera unless the meta lists them")
    }

    // ------------------------------------------------------------------
    // The sheet, if it is committed. A missing sheet is reported, not
    // asserted around: until the bake lands, this case says so and passes
    // nothing about pixels.
    function test_10_a_committed_sheet_loads_as_one_cell() {
      var img = cellImage()
      tryVerify(function () { return img.status !== Image.Loading && img.status !== Image.Null }, 5000)
      if (img.status !== Image.Ready) {
        skip("assets/karts/coupe/red.png did not load (" + img.status + "): the bake's sheets are not committed, so loading is unverified here")
        return
      }
      compare(img.implicitWidth, car.cellW, "the Image holds one cell, not the sheet")
      compare(img.implicitHeight, car.cellH)
    }

    // ------------------------------------------------------------------
    // The garage: the car in the child's roster row is the car on the dais.
    // Body, paint and number are read off the two CarSprites, not off the
    // settings that fed them.
    function test_11_roster_row_one_is_the_stall_car() {
      memory.data = { "version": 1,
                      "settings": { "kartBody": 3, "kartPaint": 5, "kartNumber": 42 },
                      "records": {}, "facts": {} }
      Store.reload()
      var garage = createTemporaryObject(garageFactory, root)
      verify(garage !== null, "the garage loads")
      var hero = findChild(garage, "heroCar")
      var slot = findChild(garage, "rosterYou")
      verify(hero !== null, "the dais car is reachable")
      verify(slot !== null, "the child's roster row is reachable")
      var thumb = findChild(slot, "carPreview")
      verify(thumb !== null, "the roster car is reachable")

      compare(hero.body, 3)
      compare(hero.paint, 5)
      compare(hero.number, 42)
      compare(thumb.body, hero.body, "roster body is the dais body")
      compare(thumb.paint, hero.paint, "roster paint is the dais paint")
      compare(thumb.number, hero.number, "roster number is the dais number")
      compare(String(thumb.sheetSource), String(hero.sheetSource), "the same sheet file")
      compare(thumb.camera, "stall")
      compare(hero.camera, "stall")
      compare(hero.yaw, 0)
      compare(thumb.yaw, 0)
      compare(hero.pixelScale, 3)
      compare(hero.sheetScale, 1.0)
      compare(thumb.sheetScale, 0.5)

      // The dais car stands on the turntable's contact point.
      var stall = findChild(garage, "garageStall")
      if (stall !== null) {
        compare(Math.round(hero.x), Math.round(stall.vx(stall.daisX)))
        compare(Math.round(hero.y), Math.round(stall.vy(stall.daisY)))
      }
      garage.destroy()
    }

    // ------------------------------------------------------------------
    // WHICH WAY A COLUMN FACES, READ OFF THE SHEET'S OWN PIXELS.
    //
    // On a BLUE car the only saturated red on the sheet is the tail-lamp bar
    // and the only warm pale is the headlights, so where those pixels sit in
    // a cell says where the tail and the nose are, with no sign convention
    // assumed anywhere in the test. A car heading to the viewer's right
    // (+45: the far cars on a right-hand bend) must be drawn from the column
    // whose tail is LEFT of the cell's centre, and at +135 from the column
    // whose headlights are RIGHT of it; the mirror for a left bend. Round one
    // had the sign of `columnForHeading` backwards and every far car turned
    // away from the bend it was in; this case fails on that sign.
    // The pixels of the cell the sprite is showing right now -- the sheet
    // file it names, at the clip rect test_01 pins to the column -- and, of
    // those, the centroid of the ones `keep` accepts, relative to the cell's
    // centre.
    function tintCentroid(img, keep) {
      var url = car.sheetSource
      if (!reader.isImageLoaded(url)) {
        reader.loadImage(url)
        tryVerify(function () { return reader.isImageLoaded(url) }, 5000)
      }
      verify(reader.isImageLoaded(url), "the reader loaded " + url)
      var w = car.cellW
      var h = car.cellH
      var ctx = reader.getContext("2d")
      ctx.clearRect(0, 0, reader.width, reader.height)
      ctx.drawImage(url, -img.sourceClipRect.x, -img.sourceClipRect.y)
      var px = ctx.getImageData(0, 0, w, h).data
      var n = 0
      var sx = 0
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var o = (y * w + x) * 4
          if (px[o + 3] === 255 && keep(px[o], px[o + 1], px[o + 2])) {
            n++
            sx += x + 0.5
          }
        }
      }
      return { count: n, dx: n > 0 ? sx / n - w / 2 : 0 }
    }
    function tailLampRed(r, g, b) { return r >= 200 && g <= 80 && b <= 80 }
    function headlightPale(r, g, b) { return r >= 240 && g >= 190 && g <= 230 && b >= 110 && b <= 165 }

    function test_12_far_cars_turn_into_the_bend_by_the_sheets_own_pixels() {
      car.body = 0
      car.paint = 4
      compare(car.paintName, "blue")
      car.camera = "road"
      car.sheetScale = 1.0
      car.pixelScale = 1
      var img = cellImage()
      tryVerify(function () { return img.status === Image.Ready }, 5000)
      verify(img.status === Image.Ready, "assets/karts/coupe/blue.png loads")

      // Column 0: the rear square on, tail centred, no headlights at all.
      car.yaw = 0
      var square = tintCentroid(img, tailLampRed)
      verify(square.count > 50, "column 0 shows the tail-lamp bar (" + square.count + " px)")
      verify(Math.abs(square.dx) < 6, "column 0's tail is centred (" + square.dx.toFixed(1) + ")")
      compare(tintCentroid(img, headlightPale).count, 0, "column 0 shows no headlight")

      var right = CarMeta.columnForHeading(45)
      var left = CarMeta.columnForHeading(-45)
      verify(right !== left && right !== 0 && left !== 0)
      car.yaw = right
      var tailR = tintCentroid(img, tailLampRed)
      verify(tailR.count > 50, "heading +45 -> column " + right + " shows the tail-lamp bar")
      verify(tailR.dx < -10, "heading +45 -> column " + right + ": tail " + tailR.dx.toFixed(1)
             + " px from centre must be LEFT, so the nose points right, into a right-hand bend")
      car.yaw = left
      var tailL = tintCentroid(img, tailLampRed)
      verify(tailL.count > 50, "heading -45 -> column " + left + " shows the tail-lamp bar")
      verify(tailL.dx > 10, "heading -45 -> column " + left + ": tail " + tailL.dx.toFixed(1)
             + " px from centre must be RIGHT, so the nose points left, into a left-hand bend")

      // Three-quarters on, the headlights show, and they are on the side the
      // nose points to.
      car.yaw = CarMeta.columnForHeading(135)
      var headR = tintCentroid(img, headlightPale)
      verify(headR.count > 30, "heading +135 -> column " + car.yaw + " shows headlights")
      verify(headR.dx > 10, "heading +135 -> column " + car.yaw + ": headlights " + headR.dx.toFixed(1) + " px from centre must be RIGHT")
      car.yaw = CarMeta.columnForHeading(-135)
      var headL = tintCentroid(img, headlightPale)
      verify(headL.count > 30, "heading -135 -> column " + car.yaw + " shows headlights")
      verify(headL.dx < -10, "heading -135 -> column " + car.yaw + ": headlights " + headL.dx.toFixed(1) + " px from centre must be LEFT")
    }

    // ------------------------------------------------------------------
    // The number is pixels, not a gradient: every drawn pixel of the digits
    // canvas is the one ink colour at full alpha, on the upscale's grid, and
    // there are exactly as many as the squares CarMeta asked for. The stall
    // plate is the hard case, because it is tilted.
    function test_13_the_number_is_pixels_not_a_gradient() {
      car.camera = "stall"
      car.yaw = 0
      car.sheetScale = 1.0
      car.pixelScale = 3
      car.number = 42
      var plate = plateItem()
      var digits = digitsText()
      verify(plate.visible, "the stall plate carries the number")
      verify(car.numberAngle !== 0, "the stall plate is tilted: the hard case")
      var squares = car.digitSquares
      verify(squares.length > 0)
      waitForRendering(digits)
      // The canvas's own pixels, read back through its context: what the
      // scene graph uploads as the number's texture.
      var w = digits.width
      var h = digits.height
      var slack = CarMeta.NUMBER_SLACK * 3
      compare(w, plate.width)
      compare(h, plate.height + 2 * slack, "the canvas is the rect plus the slack above and below")
      compare(digits.y, -slack)
      var px = digits.getContext("2d").getImageData(0, 0, w, h).data
      var ink = car.numberInk
      var r0 = Math.round(ink.r * 255), g0 = Math.round(ink.g * 255), b0 = Math.round(ink.b * 255)
      var inked = 0
      var other = 0
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var o = (y * w + x) * 4
          var a = px[o + 3]
          if (a === 0)
            continue
          if (a === 255 && px[o] === r0 && px[o + 1] === g0 && px[o + 2] === b0)
            inked++
          else
            other++
        }
      }
      compare(other, 0, "no pixel of the number is anything but the ink at full alpha")
      compare(inked, squares.length * 9, "every square is 3x3 of ink and nothing else is drawn")
      for (var s = 0; s < squares.length; s++) {
        compare(squares[s][0] % 3, 0, "square on the 3x grid (x)")
        compare(squares[s][1] % 3, 0, "square on the 3x grid (y)")
        for (var dy = 0; dy < 3; dy++)
          for (var dx = 0; dx < 3; dx++)
            compare(px[((squares[s][1] + slack + dy) * w + squares[s][0] + dx) * 4 + 3], 255, "square " + s + " is filled")
      }
      // And the two digits are two: the ink spans more than one glyph width
      // at the pitch used, so 42 is not drawn as one smear.
      var minX = 1e9, maxX = -1e9
      for (var q = 0; q < squares.length; q++) {
        minX = Math.min(minX, squares[q][0])
        maxX = Math.max(maxX, squares[q][0])
      }
      verify(maxX - minX >= 5 * 3, "two digits span at least two glyphs")
    }

    // ------------------------------------------------------------------
    // The number is hidden unless the meta says the panel faces the camera,
    // and even then not on a rect under four item pixels wide or under the
    // height floor at the current scale.
    function test_14_number_hidden_unless_visible_and_wide_enough() {
      var shown = { x: 10, y: 10, w: 12.4, h: 16.2, angle: 14, visible: true }
      verify(CarMeta.numberDrawable(shown, 1.0, 1, 9))
      verify(!CarMeta.numberDrawable({ x: 10, y: 10, w: 12.4, h: 16.2, visible: false }, 1.0, 3, 9),
             "visible: false hides the number at any scale")
      verify(!CarMeta.numberDrawable({ x: 10, y: 10, w: 12.4, h: 16.2 }, 1.0, 3, 9),
             "an unset flag is not visible: strict")
      verify(!CarMeta.numberDrawable({ x: 10, y: 10, w: 3.4, h: 16.2, visible: true }, 1.0, 1, 9),
             "a rect 3 px wide at 1x is not drawn though the meta says visible")
      verify(CarMeta.numberDrawable({ x: 10, y: 10, w: 3.4, h: 16.2, visible: true }, 1.0, 2, 9),
             "the same rect at 2x is 6 px wide: the width rule passes it on")
      verify(!CarMeta.numberDrawable({ x: 10, y: 10, w: 12.4, h: 16.2, visible: true }, 0.25, 1, 9),
             "the quarter row at 1x is 4 px tall: under the floor")
      verify(!CarMeta.numberDrawable(null, 1.0, 3, 9))
      // No rect the bake left unflagged or flagged hidden is drawn on any
      // body, either camera, at the largest scale.
      for (var b = 0; b < Theme.bodySheetNames.length; b++) {
        var meta = CarMeta.forBody(Theme.bodySheetNames[b])
        verify(meta !== null)
        var cams = ["stall", "road"]
        for (var c = 0; c < cams.length; c++)
          for (var yaw = 0; yaw < 8; yaw++) {
            var rect = meta.number[cams[c]][yaw]
            if (rect.visible !== true)
              verify(!CarMeta.numberDrawable(rect, 1.0, 3, 9),
                     Theme.bodySheetNames[b] + " " + cams[c] + " yaw " + yaw + " is not drawn")
          }
      }
      // The sprite follows the rule: the coupe's road yaw 4 is flagged hidden.
      var plate = plateItem()
      car.camera = "road"
      car.yaw = 4
      car.sheetScale = 1.0
      car.pixelScale = 3
      compare(CarMeta.forBody("coupe").number.road[4].visible, false)
      verify(!plate.visible, "road yaw 4: the meta hides the number and so does the sprite")
      // And where the meta says visible but the panel is a sliver at the
      // current scale -- the door roundel on the quarter row at 1x is 3 px
      // wide -- it is not drawn either.
      car.yaw = 1
      car.sheetScale = 0.25
      car.pixelScale = 1
      compare(CarMeta.forBody("coupe").number.road[1].visible, true)
      verify(car.numberW < 4, "the quarter-row roundel is under 4 px wide (" + car.numberW + ")")
      verify(!plate.visible, "no number on a panel under four pixels wide")
    }

    // The squares themselves: a whole-pixel pitch that fits the rect, two
    // digits with a gap, one digit centred, and an empty answer where no
    // pitch fits.
    function test_15_digit_squares_fit_the_rect_as_whole_pixels() {
      var plate = { x: 80.4, y: 84.9, w: 31.2, h: 10.4, angle: 0, visible: true }
      var sq = CarMeta.digitSquares(42, plate, 1.0, 1)
      verify(sq.length > 0)
      // Pitch 2 fits a 31x10 rect (block 7x5 font pixels): 14x10 sheet px.
      var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9
      for (var i = 0; i < sq.length; i++) {
        minX = Math.min(minX, sq[i][0]); maxX = Math.max(maxX, sq[i][0])
        minY = Math.min(minY, sq[i][1]); maxY = Math.max(maxY, sq[i][1])
        verify(sq[i][0] >= 0 && sq[i][0] < 31 && sq[i][1] >= 0 && sq[i][1] < 10, "inside the rect")
      }
      compare(maxX - minX + 1, 14, "42 at pitch 2 is 14 px wide")
      compare(maxY - minY + 1, 10, "and 10 px tall")
      // The gap column between the digits carries no ink.
      var gapX = minX + 6
      for (var g = 0; g < sq.length; g++)
        verify(sq[g][0] !== gapX && sq[g][0] !== gapX + 1, "the gap between 4 and 2 is empty")
      // At 3x the same squares, three times as far apart.
      var sq3 = CarMeta.digitSquares(42, plate, 1.0, 3)
      compare(sq3.length, sq.length)
      for (var k = 0; k < sq.length; k++) {
        compare(sq3[k][0], sq[k][0] * 3)
        compare(sq3[k][1], sq[k][1] * 3)
      }
      // One digit: fewer squares, still centred inside the rect.
      var one = CarMeta.digitSquares(7, plate, 1.0, 1)
      verify(one.length > 0 && one.length < sq.length)
      // A 7 is 5 lit font pixels at pitch 2 = 5 x 4 squares... exactly the
      // glyph's ink count times pitch squared.
      compare(one.length, 7 * 4, "a 7 has seven font pixels, four sheet pixels each at pitch 2")
      // Too narrow for even pitch 1 with two digits: nothing.
      compare(CarMeta.digitSquares(42, { w: 6, h: 10, angle: 0 }, 1.0, 1).length, 0)
      // The rear plate as the bake reports it, nine sheet pixels tall: the
      // ten-pixel block at pitch 2 is drawn, one row of slack above and
      // below the rect (the plate itself is taller than its rect), rather
      // than a five-pixel one.
      var nine = CarMeta.digitSquares(42, { x: 80.4, y: 84.9, w: 31.1, h: 9.1, angle: 0, visible: true }, 1.0, 1)
      compare(nine.length, (9 + 11) * 4, "pitch 2 on a nine-pixel plate")
      var nMinY = 1e9, nMaxY = -1e9
      for (var q9 = 0; q9 < nine.length; q9++) {
        nMinY = Math.min(nMinY, nine[q9][1])
        nMaxY = Math.max(nMaxY, nine[q9][1])
      }
      compare(nMinY, -CarMeta.NUMBER_SLACK, "one row into the slack above")
      compare(nMaxY, 8, "and down to the rect's last row")
      // But never sideways: a block that would need more width than the
      // rect has drops a pitch instead.
      var narrow = CarMeta.digitSquares(42, { w: 13, h: 30, angle: 0, visible: true }, 1.0, 1)
      compare(narrow.length, 9 + 11, "13 px wide holds pitch 1 only, however tall")
      // A tilt is a whole-pixel shear: every glyph column keeps all its
      // pixels and is stepped down along the plate's edge -- from pitch 2.
      // The road door roundel is 12 px wide, so it holds pitch 1 only, and
      // at pitch 1 the block is drawn upright: twenty pixels of 42, every
      // column on the same row.
      var door = { x: 70.2, y: 68.8, w: 12.4, h: 17.3, angle: 14.2, visible: true }
      var d = CarMeta.digitSquares(42, door, 1.0, 1)
      compare(d.length, 9 + 11, "42 at pitch 1: the 4 has nine font pixels, the 2 eleven")
      function colTop(list, x) {
        var top = 1e9
        for (var t = 0; t < list.length; t++)
          if (list[t][0] === x) top = Math.min(top, list[t][1])
        return top
      }
      var firstX = 1e9
      for (var f = 0; f < d.length; f++) firstX = Math.min(firstX, d[f][0])
      compare(colTop(d, firstX + 6) - colTop(d, firstX), 0, "at pitch 1 the tilt is not applied: upright")
      // The stall plate, tilted 23.3 degrees at pitch 2: the block is 14
      // wide, 10 tall plus a 5-px drop across, and every font pixel is a
      // whole 2x2 square -- eighty squares, not a resampled smear.
      var stallPlate = { x: 38.6, y: 76.8, w: 19.1, h: 15.5, angle: 23.3, visible: true }
      var s2 = CarMeta.digitSquares(42, stallPlate, 1.0, 1)
      compare(s2.length, (9 + 11) * 4, "42 at pitch 2 on the tilted plate: every font pixel is four sheet pixels")
      var sMinX = 1e9, sMaxX = -1e9, sMinY = 1e9, sMaxY = -1e9
      for (var u = 0; u < s2.length; u++) {
        sMinX = Math.min(sMinX, s2[u][0]); sMaxX = Math.max(sMaxX, s2[u][0])
        sMinY = Math.min(sMinY, s2[u][1]); sMaxY = Math.max(sMaxY, s2[u][1])
        verify(s2[u][0] >= 0 && s2[u][0] < 19 && s2[u][1] >= 0 && s2[u][1] < 16, "inside the plate")
      }
      compare(sMaxX - sMinX + 1, 14, "14 px wide")
      compare(sMaxY - sMinY + 1, 15, "10 px of glyph plus a 5 px drop along the tilt")
      compare(colTop(s2, sMinX + 12) - colTop(s2, sMinX), 5, "the right-hand column is five rows lower: the plate's edge")
    }
  }
}
