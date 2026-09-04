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
        compare(plate.rotation, rect.angle || 0, cam + ": number tilt")
        compare(digits.text, "7")
        car.number = 42
        compare(digits.text, "42")

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

    function test_07_column_for_heading() {
      compare(CarMeta.columnForHeading(0), 0)
      compare(CarMeta.columnForHeading(22), 0)
      compare(CarMeta.columnForHeading(23), 1)
      compare(CarMeta.columnForHeading(45), 1)
      compare(CarMeta.columnForHeading(-45), 7)
      compare(CarMeta.columnForHeading(-30), 7)
      compare(CarMeta.columnForHeading(180), 4)
      compare(CarMeta.columnForHeading(-180), 4)
      compare(CarMeta.columnForHeading(400), 1)
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
  }
}
