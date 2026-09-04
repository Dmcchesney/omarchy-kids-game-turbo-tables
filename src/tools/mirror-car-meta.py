"""Mirror assets/karts/<body>/meta.json into ui/parts/CarMeta.js.

Layer 2 may not use XMLHttpRequest (the boundary check forbids the token
everywhere but layer 3), so a QML item cannot read meta.json at runtime. The
JS library is the same data as a JavaScript literal; tests/carmeta.test.ts
asserts the two agree, so a rebake that changes meta.json fails `npm test`
until this is re-run.

  python3 mirror_meta.py KARTS_DIR REPO/ui/parts/CarMeta.js
"""
import json, os, sys

BODIES = ["coupe", "hatch", "wedge", "saloon", "buggy", "pickup"]

HEAD = '''.pragma library

// The car sheets' meta.json, mirrored as a JavaScript literal.
//
// GENERATED from assets/karts/<body>/meta.json -- do not edit by hand. Layer 2
// may not read a file at runtime (the boundary check forbids the request
// object everywhere but layer 3), so the bake's per-body meta is carried here
// as data a QML file can import. tests/carmeta.test.ts asserts that META below
// equals the committed meta.json files byte for byte after parsing; when a
// rebake changes a number rect, that test fails until this file is
// regenerated from the new meta.
//
// The sheet layout is the piece C contract's and is fixed: six rows (stall
// 1.0, 0.5, 0.25, then road 1.0, 0.5, 0.25), eight yaw columns, cells of
// 192x128, 96x64 and 48x32, every cell anchored bottom-centre.

var SHEET_W = 1536
var SHEET_H = 448
var YAWS = 8
var CELL_W = [192, 96, 48]
var CELL_H = [128, 64, 32]
var ROW_SCALE = [1.0, 0.5, 0.25]
var ROW_Y = [0, 128, 192, 224, 352, 416]

// The scale step (0, 1, 2) nearest to a requested sheet scale.
function scaleStep(scale) {
  return scale >= 0.75 ? 0 : (scale >= 0.375 ? 1 : 2)
}

function rowOf(camera, scale) {
  return (camera === "road" ? 3 : 0) + scaleStep(scale)
}

// The row and the whole-number upscale for a car that the projection wants
// `targetPx` wide (as a 1.0-row cell width). The ROW is the one of the three
// whose cell is nearest the target, by ratio, so a car is drawn from the most
// detailed cell that is about its size; the UPSCALE is then the whole number
// nearest target / cell, clamped to 1..3. Never a fractional scale: a car is
// 48, 96, 144, 192, 288, 384 or 576 pixels of cell, and nothing in between.
function fit(targetPx) {
  var t = Math.max(1, targetPx)
  var s = 0
  var bestD = Number.POSITIVE_INFINITY
  for (var i = 0; i < 3; i++) {
    var d = Math.abs(Math.log(t / CELL_W[i]))
    if (d < bestD) {
      bestD = d
      s = i
    }
  }
  var p = Math.max(1, Math.min(3, Math.round(t / CELL_W[s])))
  return { sheetScale: ROW_SCALE[s], pixelScale: p, width: CELL_W[s] * p }
}

// The yaw column for a car heading `deg` degrees off the camera's own
// heading. Column 0 is the car's rear square to the camera; column 1 is the
// car turned 45 degrees clockwise seen from above, so from behind its nose
// swings to the viewer's right; column 7 turns it to the left. A road that
// bends right (positive curve) therefore reads as positive degrees.
function columnForHeading(deg) {
  var c = Math.round(deg / 45) % 8
  return c < 0 ? c + 8 : c
}

function forBody(name) {
  return META[name] || null
}

'''


def main(karts, out):
    meta = {}
    for body in BODIES:
        path = os.path.join(karts, body, "meta.json")
        with open(path) as f:
            meta[body] = json.load(f)
    text = HEAD + "var META = " + json.dumps(meta, indent=1, sort_keys=True) + "\n"
    with open(out, "w") as f:
        f.write(text)
    print("wrote", out, "from", karts)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
