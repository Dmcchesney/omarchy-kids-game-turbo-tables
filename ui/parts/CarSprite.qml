import QtQuick
import "../"
import "CarMeta.js" as CarMeta

// One car, as one cell of its baked sheet. The only thing in the game that
// draws a car.
//
// PIECE C. The garage turntable, the roster thumbnails, the countdown and the
// track all used to draw a car live -- three renderers, three cameras, three
// karts that never quite matched. Now there is one sheet per body per paint,
// baked offline (src/tools/bake-cars.py, never shipped, never run on a
// child's machine), and this item shows exactly one cell of it: an Image with
// a `sourceClipRect`, scaled by a whole number, never smoothed. A frame with
// four cars in it is four textured quads and no drawing at all.
//
// THE SHEET, from the piece C contract: six rows by eight columns. Rows are
// the `stall` camera (off the rear-right shoulder at a little above hub
// height, the bar's eye level: the garage, roster and countdown view) at
// 1.0, 0.5 and 0.25 scale, then the `road` camera (directly behind, a little
// above the roof line: the track) at the same three.
// Columns are yaws, the car turned `column x 45` degrees, column 0 its rear
// square to the camera. Cells are 192x128, 96x64 and 48x32, and the car
// stands on the bottom edge of its cell, centred.
//
// THE ANCHOR is that contact point. `x` and `y` are where the car touches the
// ground, the same convention the track's projection already returns, so a
// host never has to know how tall a car is. The item itself has no size; the
// cell hangs around its origin, `drawnWidth` wide and `drawnHeight` tall,
// with the contact point `anchorDx`, `anchorDy` in from the cell's top-left.
// The bake may say where in the cell the wheels actually touch (`ground` in
// meta.json -- the baked contact shadow runs on below them toward the
// camera); where it does not, the contact point is the cell's bottom
// centre, as the contract says.
//
// THE NUMBER IS NOT BAKED. The door roundel and the rear plate are cream and
// blank on the sheet, and meta.json (mirrored in CarMeta.js -- layer 2 may not
// read a file) gives, per camera and yaw, the rect in cell pixels where the
// child's number goes and the tilt to draw it at. It is drawn here as
// PIXELS, not text: CarMeta.digitSquares rasterises a three-by-five pixel
// font into the rect on the cell's own grid, tilt included, and a Canvas
// fills those squares once in one ink colour. Round one overlaid a Text and
// rotated it, which resampled the glyphs into a hundred-odd colours against
// the sheet's fifteen. The number is not drawn where the meta says the panel
// faces away at that yaw (`visible` must be true, not merely unset), nor
// where the rect is under four pixels wide or under the height floor at the
// current scale.
Item {
  id: car

  // Which car: body 0..5, paint 0..7, number 1..99. Theme maps the two indices
  // to the sheet's file names.
  property int body: 0
  property int paint: 0
  property int number: 7

  // Which cell: "stall" or "road"; yaw 0..7; the row's scale, 1.0, 0.5 or
  // 0.25 (anything else snaps to the nearest); and the whole-number upscale,
  // 1, 2 or 3. `sheetScale` rather than `scale`, because Item.scale already
  // exists and is the one thing this item must never use.
  property string camera: "stall"
  property int yaw: 0
  property real sheetScale: 1.0
  property int pixelScale: 1

  property bool showNumber: true
  // PIECE F ROUND 6. What the drawn cell calls itself in `--dump-rects` and in
  // `findChild`. It defaults to "cell", which is what every existing caller
  // and `tst_carsprite` already look for; the track overrides it per racer
  // (`kart.bolt`) so a measurement can ask which box belongs to which car.
  // Round 6's first defect -- a victim's tag drawn on top of a different kart
  // -- could not be measured at all while every car's box had the same name.
  property string cellName: "cell"
  // 0..1: how brightly the tail lamps glow, on the road camera, from the
  // lamp centres meta.json lists. The track drives it from a hit.
  property real lampGlow: 0.0
  // Where the sheets are. Bound to Theme so the harness can redirect every
  // car at once; a host may override it for one car.
  property url sheetRoot: Theme.carSheetRoot

  // ----------------------------------------------------------- the cell
  readonly property int bodyIndex: ((body % 6) + 6) % 6
  readonly property int paintIndex: ((paint % 8) + 8) % 8
  readonly property int column: ((yaw % 8) + 8) % 8
  readonly property int scaleStep: CarMeta.scaleStep(sheetScale)
  readonly property real rowScale: CarMeta.ROW_SCALE[scaleStep]
  readonly property int row: CarMeta.rowOf(camera, sheetScale)
  readonly property int cellW: CarMeta.CELL_W[scaleStep]
  readonly property int cellH: CarMeta.CELL_H[scaleStep]
  readonly property int cellX: column * cellW
  readonly property int cellY: CarMeta.ROW_Y[row]
  readonly property int ps: Math.max(1, Math.min(3, Math.round(pixelScale)))
  readonly property int drawnWidth: cellW * ps
  readonly property int drawnHeight: cellH * ps
  readonly property string bodyName: Theme.bodySheetName(bodyIndex)
  readonly property string paintName: Theme.paintSheetName(paintIndex)
  readonly property url sheetSource: sheetRoot + bodyName + "/" + paintName + ".png"
  readonly property bool loaded: cell.status === Image.Ready

  // ------------------------------------------------------------ the meta
  readonly property var meta: CarMeta.forBody(bodyName)
  readonly property var numberRect: (meta && meta.number && meta.number[camera]
                                     && meta.number[camera].length > column)
                                    ? meta.number[camera][column] : null
  // A rect scaled to the row and the upscale, in item pixels, whole numbers.
  function scaled(v) { return Math.round(v * rowScale) * ps }
  readonly property int numberX: numberRect ? scaled(numberRect.x) : 0
  readonly property int numberY: numberRect ? scaled(numberRect.y) : 0
  readonly property int numberW: numberRect ? scaled(numberRect.w) : 0
  readonly property int numberH: numberRect ? scaled(numberRect.h) : 0
  // The panel's tilt from the meta. Informational: the tilt is rasterised
  // into `digitSquares`, and no item is ever rotated by it.
  readonly property real numberAngle: numberRect && numberRect.angle ? numberRect.angle : 0
  // Below this many pixels of plate the digits are noise, not a number: the
  // roster's own badge already carries the number at that size.
  readonly property int numberMinPx: 9
  readonly property bool numberVisible: showNumber
                                        && CarMeta.numberDrawable(numberRect, rowScale, ps, numberMinPx)
  // The ink: the sheet's own outline colour, so the number adds no colour to
  // the cell. One square per sheet pixel of ink, in item pixels from the
  // rect's top-left; empty where no whole-pixel pitch fits the rect.
  readonly property color numberInk: "#280e27"
  readonly property var digitSquares: numberVisible
                                      ? CarMeta.digitSquares(number, numberRect, rowScale, ps) : []
  readonly property var lamps: (meta && meta.lamps && meta.lamps[camera]
                                && meta.lamps[camera].length > column
                                && meta.lamps[camera][column].tail)
                               ? meta.lamps[camera][column].tail : null
  // The contact point, in cell pixels at scale 1.0, then in item pixels.
  readonly property var groundPoint: (meta && meta.ground && meta.ground[camera]
                                      && meta.ground[camera].length === 2)
                                     ? meta.ground[camera] : null
  readonly property int anchorDx: groundPoint ? scaled(groundPoint[0]) : drawnWidth / 2
  readonly property int anchorDy: groundPoint ? scaled(groundPoint[1]) : drawnHeight

  width: 0
  height: 0
  smooth: false
  antialiasing: false

  // The cell. `sourceClipRect` loads the one cell of the sheet and nothing
  // else; width and height are the cell times the whole-number upscale, so
  // the stretch is exact and, with `smooth: false`, nearest-neighbour.
  Image {
    id: cell
    objectName: car.cellName
    x: -car.anchorDx
    y: -car.anchorDy
    width: car.drawnWidth
    height: car.drawnHeight
    source: car.sheetSource
    sourceClipRect: Qt.rect(car.cellX, car.cellY, car.cellW, car.cellH)
    fillMode: Image.Stretch
    smooth: false
    antialiasing: false
    mipmap: false
    cache: true
    asynchronous: false
  }

  // The tail lamps, lit. Two flat squares per lamp: a wider dim one for the
  // glow, a tight bright one for the lamp. Only on a hit, only on the road,
  // and only where the meta says a lamp is.
  Repeater {
    model: (car.lampGlow > 0.01 && car.lamps) ? car.lamps.length : 0

    Item {
      readonly property var at: car.lamps[index]
      readonly property int lampSize: Math.max(2, Math.round(10 * car.rowScale)) * car.ps
      x: cell.x + car.scaled(at[0])
      y: cell.y + car.scaled(at[1])
      width: 0
      height: 0

      Rectangle {
        x: -parent.lampSize
        y: -parent.lampSize / 2
        width: parent.lampSize * 2
        height: parent.lampSize
        color: "#ff4a3c"
        opacity: 0.40 * car.lampGlow
        antialiasing: false
      }
      Rectangle {
        x: -parent.lampSize / 2
        y: -parent.lampSize / 4
        width: parent.lampSize
        height: parent.lampSize / 2
        color: "#ffb0a0"
        opacity: car.lampGlow
        antialiasing: false
      }
    }
  }

  // The number, over the blank roundel or plate: the squares CarMeta
  // rasterised, filled once in one ink on a canvas the size of the rect. The
  // canvas repaints only when the squares change -- a new number, a new yaw,
  // a new row or upscale -- never per frame, and it is never rotated or
  // scaled: at rest it is one more textured quad.
  Item {
    id: plate
    objectName: "plate"
    visible: car.numberVisible && car.digitSquares.length > 0
    x: cell.x + car.numberX
    y: cell.y + car.numberY
    width: car.numberW
    height: car.numberH
    smooth: false

    // The canvas is the rect plus the slack CarMeta allows the block above
    // and below it (one sheet pixel each way; the panel runs on past the
    // rect by more), so a square at y = -1 lands on the plate, not off it.
    Canvas {
      id: digits
      objectName: "digits"
      readonly property int slack: CarMeta.NUMBER_SLACK * car.ps
      x: 0
      y: -slack
      width: parent.width
      height: parent.height + 2 * slack
      smooth: false
      antialiasing: false
      renderStrategy: Canvas.Immediate

      readonly property var squares: car.digitSquares
      readonly property color ink: car.numberInk
      readonly property int square: car.ps
      onSquaresChanged: requestPaint()
      onInkChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = ink
        for (var i = 0; i < squares.length; i++)
          ctx.fillRect(squares[i][0], squares[i][1] + slack, square, square)
      }
    }
  }
}
