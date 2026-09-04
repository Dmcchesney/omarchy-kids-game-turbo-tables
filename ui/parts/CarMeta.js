.pragma library

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
// heading, positive to the viewer's RIGHT -- the sign TrackView.kartHeadingDeg
// uses, where a right-hand bend is positive. Column 0 is the car's rear
// square to the camera. The bake turns the car by +column x 45 degrees about
// the vertical, COUNTER-clockwise seen from above (bake-cars.py sets
// rotation_euler z to +i x 45), and the cameras look down +Y, so from behind
// column 1's nose swings to the viewer's LEFT and column 7's to the right.
// That is measured on the sheet's own pixels in tests/qml/tst_carsprite.qml
// (the tail-lamp bar sits right of centre in column 1, left in column 7),
// not assumed. A heading to the right is therefore a column counted
// backwards from 8. Round one had this sign the other way, and every far car
// turned away from the bend it was in.
function columnForHeading(deg) {
  var c = Math.round(-deg / 45) % 8
  return c < 0 ? c + 8 : c
}

function forBody(name) {
  return META[name] || null
}

// ------------------------------------------------------------ the number
// The child's number is not baked. It is drawn over the blank roundel or
// plate as WHOLE SHEET PIXELS from a three-by-five pixel font, so it is
// pixels like the car around it: never a glyph, never anti-aliased, never
// rotated as an item (rotating a pixel grid resamples it). The tilt the bake
// reports for the panel is a whole-pixel SHEAR: each column of the digit
// block is stepped down (or up) along the panel's baseline by a whole number
// of sheet pixels, so every glyph column stays intact and readable and the
// number still sits along the plate's edge. A rotation sampled onto a 3x5
// font at two pixels a step scrambled the glyphs; a shear does not.
var GLYPH_W = 3
var GLYPH_H = 5
var GLYPHS = {
  "0": ["111", "101", "101", "101", "111"],
  "1": ["010", "110", "010", "010", "111"],
  "2": ["111", "001", "111", "100", "111"],
  "3": ["111", "001", "111", "001", "111"],
  "4": ["101", "101", "111", "001", "001"],
  "5": ["111", "100", "111", "001", "111"],
  "6": ["111", "100", "111", "101", "111"],
  "7": ["111", "001", "001", "001", "001"],
  "8": ["111", "101", "111", "101", "111"],
  "9": ["111", "101", "111", "001", "111"]
}

// Whether the number is drawn at all, for a META number rect at a row scale
// and a whole-number upscale. Only where the bake says the panel faces the
// camera -- `visible` must be true, not merely unset -- and only where the
// panel is at least four item pixels wide and `minH` tall: below that the
// digits are noise, and the roster's own badge already carries the number
// at that size.
function numberDrawable(rect, rowScale, ps, minH) {
  if (!rect || rect.visible !== true)
    return false
  var w = Math.round(rect.w * rowScale) * ps
  var h = Math.round(rect.h * rowScale) * ps
  return w >= 4 && h >= minH
}

// The squares that spell `number` inside a rect: [x, y] pairs in item pixels
// from the rect's top-left, each ps x ps, one per sheet pixel of ink.
//
// The digit block is `n x 3 + (n - 1)` font pixels wide (one column between
// digits) and 5 tall, drawn at a whole-number pitch of sheet pixels: the
// largest at which the block, sheared along the tilt, fits the rect's width
// and its height plus NUMBER_SLACK sheet pixels above and below. Under a
// pitch of 1 nothing fits and nothing is drawn. The block is centred on the
// rect.
//
// The slack: the bake's rect is the panel's bounding box shrunk to 0.8 x 0.7
// (a roundel) or 0.9 x 0.8 (the plate), so the panel runs on past the rect
// by at least a pixel top and bottom at every size the number is drawn at.
// A five-row font steps in fives, and the rear plate is nine sheet pixels
// tall: without the slack the plate would carry a five-pixel number under a
// ten-pixel one that overhangs it by half a pixel each way. Sideways there
// is no slack: a roundel is round, and a wider block would cut its edge.
//
// The shear: font column k (every column of every digit, gaps included) is
// shifted down by round(k x pitch x tan(tilt)) sheet pixels -- down for a
// positive tilt, which is clockwise on screen as Item.rotation reads it, so
// the block's baseline drops to the right the way the plate's edge does.
// Only from a pitch of 2: at pitch 1 a one-pixel step breaks a one-pixel
// stroke, so a block that cannot reach pitch 2 sheared is drawn upright at
// the largest upright pitch instead. Tilts past 45 degrees are held at 45:
// the bake never reports one.
var NUMBER_SLACK = 1

function digitSquares(number, rect, rowScale, ps) {
  var text = String(Math.abs(Math.round(number)))
  var n = text.length
  var w = Math.round(rect.w * rowScale)
  var h = Math.round(rect.h * rowScale)
  var bw = n * GLYPH_W + (n - 1)
  var bh = GLYPH_H
  var slope = rect.angle ? Math.tan(rect.angle * Math.PI / 180) : 0
  slope = Math.max(-1, Math.min(1, slope))
  // The sheared block is bw x pitch wide and bh x pitch + the last column's
  // drop tall; the pitch is the largest whole number at which that fits.
  var pitch = Math.floor(Math.min(w / bw,
                                  (h + 2 * NUMBER_SLACK) / (bh + (bw - 1) * Math.abs(slope))))
  if (pitch < 2) {
    slope = 0
    pitch = Math.floor(Math.min(w / bw, (h + 2 * NUMBER_SLACK) / bh))
  }
  if (pitch < 1)
    return []
  var drop = function (k) { return Math.round(k * pitch * slope) }
  var lowest = Math.min(0, drop(bw - 1))
  var highest = Math.max(0, drop(bw - 1))
  var blockH = bh * pitch + highest - lowest
  var x0 = Math.floor((w - bw * pitch) / 2)
  var y0 = Math.floor((h - blockH) / 2) - lowest
  var out = []
  for (var d = 0; d < n; d++) {
    var glyph = GLYPHS[text.charAt(d)]
    if (!glyph)
      continue
    for (var gx = 0; gx < GLYPH_W; gx++) {
      var k = d * (GLYPH_W + 1) + gx
      var dy = drop(k)
      for (var gy = 0; gy < GLYPH_H; gy++) {
        if (glyph[gy].charAt(gx) !== "1")
          continue
        for (var b = 0; b < pitch; b++) {
          for (var a = 0; a < pitch; a++) {
            var x = x0 + k * pitch + a
            var y = y0 + gy * pitch + dy + b
            if (x >= 0 && x < w && y >= -NUMBER_SLACK && y < h + NUMBER_SLACK)
              out.push([x * ps, y * ps])
          }
        }
      }
    }
  }
  return out
}

var META = {
 "buggy": {
  "anchor": "bottom-center",
  "body": "buggy",
  "cell": [
   [
    192,
    128
   ],
   [
    96,
    64
   ],
   [
    48,
    32
   ]
  ],
  "ground": {
   "road": [
    96.0,
    92.2
   ],
   "stall": [
    96.0,
    83.2
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       80.7,
       67.5
      ],
      [
       111.3,
       67.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       116.5,
       67.1
      ],
      [
       135.1,
       63.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       136.5,
       62.1
      ],
      [
       133.0,
       57.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       130.6,
       56.7
      ],
      [
       112.0,
       53.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.8,
       53.7
      ],
      [
       84.2,
       53.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       80.0,
       53.9
      ],
      [
       61.4,
       56.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       59.0,
       57.4
      ],
      [
       55.5,
       62.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       56.9,
       63.0
      ],
      [
       75.5,
       67.1
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       59.9,
       60.3
      ],
      [
       79.2,
       66.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       84.3,
       67.0
      ],
      [
       113.4,
       66.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       118.1,
       65.5
      ],
      [
       133.8,
       58.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       134.7,
       57.1
      ],
      [
       129.6,
       49.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       127.1,
       48.6
      ],
      [
       108.8,
       44.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       104.8,
       44.2
      ],
      [
       82.8,
       44.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       78.9,
       45.1
      ],
      [
       62.1,
       49.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       60.1,
       51.1
      ],
      [
       58.3,
       58.8
      ]
     ],
     "visible": false
    }
   ]
  },
  "number": {
   "road": [
    {
     "angle": -0.0,
     "h": 7.8,
     "on": "plate",
     "visible": true,
     "w": 25.0,
     "x": 83.5,
     "y": 73.2
    },
    {
     "angle": -14.1,
     "h": 10.8,
     "on": "plate",
     "visible": true,
     "w": 16.3,
     "x": 117.8,
     "y": 68.9
    },
    {
     "angle": 0.0,
     "h": 11.7,
     "on": "door",
     "visible": true,
     "w": 13.6,
     "x": 97.4,
     "y": 63.6
    },
    {
     "angle": 0,
     "h": 12.8,
     "on": "door",
     "visible": false,
     "w": 9.5,
     "x": 112.3,
     "y": 60.7
    },
    {
     "angle": 0,
     "h": 12.5,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 74.2,
     "y": 57.5
    },
    {
     "angle": 0,
     "h": 12.8,
     "on": "door",
     "visible": false,
     "w": 9.5,
     "x": 70.2,
     "y": 60.7
    },
    {
     "angle": -0.0,
     "h": 11.7,
     "on": "door",
     "visible": true,
     "w": 13.6,
     "x": 81.0,
     "y": 63.6
    },
    {
     "angle": 14.1,
     "h": 10.8,
     "on": "plate",
     "visible": true,
     "w": 16.3,
     "x": 58.0,
     "y": 68.9
    }
   ],
   "stall": [
    {
     "angle": 19.3,
     "h": 11.7,
     "on": "plate",
     "visible": true,
     "w": 16.7,
     "x": 61.2,
     "y": 66.0
    },
    {
     "angle": -1.5,
     "h": 7.7,
     "on": "plate",
     "visible": true,
     "w": 23.7,
     "x": 87.0,
     "y": 71.5
    },
    {
     "angle": -25.6,
     "h": 12.1,
     "on": "plate",
     "visible": true,
     "w": 14.0,
     "x": 119.0,
     "y": 64.4
    },
    {
     "angle": -1.4,
     "h": 11.0,
     "on": "door",
     "visible": true,
     "w": 12.9,
     "x": 98.7,
     "y": 60.0
    },
    {
     "angle": 0,
     "h": 12.8,
     "on": "door",
     "visible": false,
     "w": 8.4,
     "x": 112.2,
     "y": 55.2
    },
    {
     "angle": 0,
     "h": 12.7,
     "on": "door",
     "visible": false,
     "w": 1.3,
     "x": 75.3,
     "y": 50.9
    },
    {
     "angle": 0,
     "h": 12.7,
     "on": "door",
     "visible": false,
     "w": 9.7,
     "x": 71.9,
     "y": 56.1
    },
    {
     "angle": -1.4,
     "h": 11.1,
     "on": "door",
     "visible": true,
     "w": 13.0,
     "x": 83.3,
     "y": 60.4
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 },
 "coupe": {
  "anchor": "bottom-center",
  "body": "coupe",
  "cell": [
   [
    192,
    128
   ],
   [
    96,
    64
   ],
   [
    48,
    32
   ]
  ],
  "ground": {
   "road": [
    96.0,
    92.2
   ],
   "stall": [
    96.0,
    83.2
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       67.7,
       78.7
      ],
      [
       124.3,
       78.7
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       133.4,
       77.7
      ],
      [
       163.8,
       69.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       165.3,
       67.8
      ],
      [
       155.7,
       59.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       151.5,
       58.2
      ],
      [
       120.6,
       53.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       114.2,
       53.3
      ],
      [
       77.8,
       53.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       71.4,
       53.7
      ],
      [
       40.5,
       58.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       36.3,
       59.4
      ],
      [
       26.7,
       67.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       28.2,
       69.5
      ],
      [
       58.6,
       77.7
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       32.9,
       68.6
      ],
      [
       65.0,
       81.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       74.2,
       82.5
      ],
      [
       128.2,
       81.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       136.4,
       79.2
      ],
      [
       161.3,
       65.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       161.9,
       62.8
      ],
      [
       149.7,
       50.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       145.4,
       48.4
      ],
      [
       115.5,
       42.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       109.5,
       41.7
      ],
      [
       75.6,
       42.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       69.7,
       43.0
      ],
      [
       41.7,
       50.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       38.0,
       52.4
      ],
      [
       30.9,
       65.9
      ]
     ],
     "visible": false
    }
   ]
  },
  "number": {
   "road": [
    {
     "angle": -0.0,
     "h": 9.1,
     "on": "plate",
     "visible": true,
     "w": 31.1,
     "x": 80.4,
     "y": 86.0
    },
    {
     "angle": 13.9,
     "h": 16.3,
     "on": "door",
     "visible": true,
     "w": 11.7,
     "x": 69.7,
     "y": 67.6
    },
    {
     "angle": 0.0,
     "h": 14.3,
     "on": "door",
     "visible": true,
     "w": 16.8,
     "x": 92.7,
     "y": 69.8
    },
    {
     "angle": -13.9,
     "h": 15.9,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 117.1,
     "y": 66.2
    },
    {
     "angle": 0,
     "h": 15.2,
     "on": "door",
     "visible": false,
     "w": 2.8,
     "x": 63.9,
     "y": 61.5
    },
    {
     "angle": 13.9,
     "h": 15.9,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 63.5,
     "y": 66.2
    },
    {
     "angle": -0.0,
     "h": 14.3,
     "on": "door",
     "visible": true,
     "w": 16.8,
     "x": 82.5,
     "y": 69.8
    },
    {
     "angle": -13.9,
     "h": 16.3,
     "on": "door",
     "visible": true,
     "w": 11.7,
     "x": 110.6,
     "y": 67.6
    }
   ],
   "stall": [
    {
     "angle": 23.3,
     "h": 14.5,
     "on": "plate",
     "visible": true,
     "w": 19.0,
     "x": 39.2,
     "y": 77.7
    },
    {
     "angle": -1.8,
     "h": 9.2,
     "on": "plate",
     "visible": true,
     "w": 29.7,
     "x": 86.5,
     "y": 87.9
    },
    {
     "angle": 18.9,
     "h": 16.1,
     "on": "door",
     "visible": true,
     "w": 12.0,
     "x": 72.4,
     "y": 64.4
    },
    {
     "angle": -1.5,
     "h": 13.4,
     "on": "door",
     "visible": true,
     "w": 15.9,
     "x": 95.1,
     "y": 67.2
    },
    {
     "angle": 0,
     "h": 15.8,
     "on": "door",
     "visible": false,
     "w": 10.0,
     "x": 117.4,
     "y": 61.1
    },
    {
     "angle": 0,
     "h": 15.4,
     "on": "door",
     "visible": false,
     "w": 2.1,
     "x": 65.7,
     "y": 54.9
    },
    {
     "angle": 18.9,
     "h": 15.6,
     "on": "door",
     "visible": true,
     "w": 11.7,
     "x": 66.1,
     "y": 62.4
    },
    {
     "angle": -1.5,
     "h": 13.4,
     "on": "door",
     "visible": true,
     "w": 16.0,
     "x": 85.5,
     "y": 67.4
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 },
 "hatch": {
  "anchor": "bottom-center",
  "body": "hatch",
  "cell": [
   [
    192,
    128
   ],
   [
    96,
    64
   ],
   [
    48,
    32
   ]
  ],
  "ground": {
   "road": [
    96.0,
    92.2
   ],
   "stall": [
    96.0,
    83.2
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       73.1,
       75.2
      ],
      [
       118.9,
       75.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       127.0,
       74.4
      ],
      [
       152.9,
       67.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       154.5,
       66.4
      ],
      [
       147.6,
       59.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       143.8,
       58.3
      ],
      [
       117.7,
       54.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       111.8,
       54.0
      ],
      [
       80.2,
       54.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       74.3,
       54.4
      ],
      [
       48.2,
       58.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       44.4,
       59.4
      ],
      [
       37.5,
       66.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       39.1,
       67.9
      ],
      [
       65.0,
       74.4
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       43.3,
       66.2
      ],
      [
       70.4,
       76.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       78.5,
       77.2
      ],
      [
       122.2,
       76.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       129.4,
       74.6
      ],
      [
       150.9,
       63.7
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       151.7,
       61.3
      ],
      [
       142.6,
       50.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       138.7,
       49.0
      ],
      [
       113.3,
       43.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.7,
       43.1
      ],
      [
       78.3,
       43.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       72.8,
       44.3
      ],
      [
       49.2,
       50.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       45.9,
       52.6
      ],
      [
       41.2,
       63.8
      ]
     ],
     "visible": false
    }
   ]
  },
  "number": {
   "road": [
    {
     "angle": -0.0,
     "h": 8.7,
     "on": "plate",
     "visible": true,
     "w": 27.7,
     "x": 82.1,
     "y": 83.2
    },
    {
     "angle": 13.8,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 11.1,
     "x": 71.5,
     "y": 68.2
    },
    {
     "angle": 0.0,
     "h": 13.4,
     "on": "door",
     "visible": true,
     "w": 15.7,
     "x": 94.9,
     "y": 70.1
    },
    {
     "angle": 0,
     "h": 14.8,
     "on": "door",
     "visible": false,
     "w": 10.6,
     "x": 118.1,
     "y": 66.4
    },
    {
     "angle": 0,
     "h": 14.1,
     "on": "door",
     "visible": false,
     "w": 2.6,
     "x": 64.7,
     "y": 61.6
    },
    {
     "angle": 0,
     "h": 14.8,
     "on": "door",
     "visible": false,
     "w": 10.6,
     "x": 63.4,
     "y": 66.4
    },
    {
     "angle": -0.0,
     "h": 13.4,
     "on": "door",
     "visible": true,
     "w": 15.7,
     "x": 81.4,
     "y": 70.1
    },
    {
     "angle": -13.8,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 11.1,
     "x": 109.4,
     "y": 68.2
    }
   ],
   "stall": [
    {
     "angle": 22.0,
     "h": 13.4,
     "on": "plate",
     "visible": true,
     "w": 17.6,
     "x": 49.2,
     "y": 75.1
    },
    {
     "angle": -1.7,
     "h": 8.7,
     "on": "plate",
     "visible": true,
     "w": 26.3,
     "x": 87.1,
     "y": 83.2
    },
    {
     "angle": 18.8,
     "h": 15.1,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 74.2,
     "y": 65.1
    },
    {
     "angle": -1.5,
     "h": 12.5,
     "on": "door",
     "visible": true,
     "w": 14.9,
     "x": 97.2,
     "y": 67.4
    },
    {
     "angle": 0,
     "h": 14.7,
     "on": "door",
     "visible": false,
     "w": 9.3,
     "x": 118.1,
     "y": 61.1
    },
    {
     "angle": 0,
     "h": 14.4,
     "on": "door",
     "visible": false,
     "w": 1.9,
     "x": 66.4,
     "y": 55.0
    },
    {
     "angle": 0,
     "h": 14.6,
     "on": "door",
     "visible": false,
     "w": 10.9,
     "x": 65.9,
     "y": 62.4
    },
    {
     "angle": -1.5,
     "h": 12.6,
     "on": "door",
     "visible": true,
     "w": 14.9,
     "x": 84.4,
     "y": 67.7
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 },
 "pickup": {
  "anchor": "bottom-center",
  "body": "pickup",
  "cell": [
   [
    192,
    128
   ],
   [
    96,
    64
   ],
   [
    48,
    32
   ]
  ],
  "ground": {
   "road": [
    96.0,
    92.2
   ],
   "stall": [
    96.0,
    83.2
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       70.3,
       85.4
      ],
      [
       121.7,
       85.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       137.3,
       83.6
      ],
      [
       164.6,
       75.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       167.1,
       72.3
      ],
      [
       158.1,
       64.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       150.9,
       61.9
      ],
      [
       123.2,
       57.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.3,
       56.9
      ],
      [
       79.7,
       56.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.8,
       57.6
      ],
      [
       41.1,
       61.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       33.9,
       64.2
      ],
      [
       24.9,
       72.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       27.4,
       75.5
      ],
      [
       54.7,
       83.6
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       32.5,
       74.7
      ],
      [
       61.3,
       86.7
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       77.0,
       89.1
      ],
      [
       125.9,
       87.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       139.9,
       84.5
      ],
      [
       162.0,
       71.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       163.1,
       66.6
      ],
      [
       151.9,
       54.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       144.6,
       51.5
      ],
      [
       117.8,
       45.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.6,
       44.8
      ],
      [
       77.4,
       45.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       67.4,
       46.6
      ],
      [
       42.3,
       53.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       35.9,
       57.1
      ],
      [
       29.3,
       69.8
      ]
     ],
     "visible": false
    }
   ]
  },
  "number": {
   "road": [
    {
     "angle": -0.0,
     "h": 8.8,
     "on": "plate",
     "visible": true,
     "w": 31.8,
     "x": 80.1,
     "y": 71.3
    },
    {
     "angle": -14.7,
     "h": 11.9,
     "on": "plate",
     "visible": true,
     "w": 18.2,
     "x": 143.0,
     "y": 64.6
    },
    {
     "angle": 0,
     "h": 12.8,
     "on": "door",
     "visible": false,
     "w": 15.2,
     "x": 63.5,
     "y": 67.0
    },
    {
     "angle": 0,
     "h": 15.3,
     "on": "door",
     "visible": false,
     "w": 11.5,
     "x": 93.9,
     "y": 68.0
    },
    {
     "angle": 0,
     "h": 15.2,
     "on": "door",
     "visible": false,
     "w": 2.8,
     "x": 65.0,
     "y": 64.9
    },
    {
     "angle": 0,
     "h": 15.3,
     "on": "door",
     "visible": false,
     "w": 11.5,
     "x": 86.5,
     "y": 68.0
    },
    {
     "angle": 0,
     "h": 12.8,
     "on": "door",
     "visible": false,
     "w": 15.2,
     "x": 113.3,
     "y": 67.0
    },
    {
     "angle": 14.7,
     "h": 11.9,
     "on": "plate",
     "visible": true,
     "w": 18.2,
     "x": 30.8,
     "y": 64.6
    }
   ],
   "stall": [
    {
     "angle": 21.2,
     "h": 13.7,
     "on": "plate",
     "visible": true,
     "w": 19.3,
     "x": 35.9,
     "y": 65.6
    },
    {
     "angle": -1.6,
     "h": 8.9,
     "on": "plate",
     "visible": true,
     "w": 30.6,
     "x": 86.4,
     "y": 75.2
    },
    {
     "angle": 0,
     "h": 13.3,
     "on": "door",
     "visible": false,
     "w": 9.9,
     "x": 57.6,
     "y": 56.3
    },
    {
     "angle": 0,
     "h": 12.1,
     "on": "door",
     "visible": false,
     "w": 14.6,
     "x": 67.0,
     "y": 64.7
    },
    {
     "angle": 0,
     "h": 15.5,
     "on": "door",
     "visible": false,
     "w": 10.2,
     "x": 97.1,
     "y": 65.7
    },
    {
     "angle": 0,
     "h": 15.7,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 68.5,
     "y": 61.6
    },
    {
     "angle": 0,
     "h": 15.1,
     "on": "door",
     "visible": false,
     "w": 11.7,
     "x": 89.3,
     "y": 66.0
    },
    {
     "angle": 0,
     "h": 12.0,
     "on": "door",
     "visible": false,
     "w": 14.5,
     "x": 114.1,
     "y": 63.6
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 },
 "saloon": {
  "anchor": "bottom-center",
  "body": "saloon",
  "cell": [
   [
    192,
    128
   ],
   [
    96,
    64
   ],
   [
    48,
    32
   ]
  ],
  "ground": {
   "road": [
    96.0,
    92.2
   ],
   "stall": [
    96.0,
    83.2
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       69.6,
       81.8
      ],
      [
       122.4,
       81.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       142.8,
       79.6
      ],
      [
       169.9,
       71.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       172.8,
       67.9
      ],
      [
       163.1,
       60.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       153.7,
       57.7
      ],
      [
       126.0,
       53.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.1,
       52.9
      ],
      [
       79.9,
       52.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       66.0,
       53.7
      ],
      [
       38.3,
       57.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       28.9,
       60.3
      ],
      [
       19.2,
       67.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       22.1,
       71.8
      ],
      [
       49.2,
       79.6
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       27.4,
       72.0
      ],
      [
       56.3,
       84.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       76.8,
       87.0
      ],
      [
       127.3,
       85.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       145.6,
       81.5
      ],
      [
       167.5,
       68.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       168.5,
       62.5
      ],
      [
       156.6,
       51.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       147.0,
       47.3
      ],
      [
       120.2,
       41.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.2,
       40.7
      ],
      [
       77.3,
       41.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       64.5,
       42.8
      ],
      [
       39.3,
       49.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       30.9,
       53.6
      ],
      [
       23.5,
       65.9
      ]
     ],
     "visible": false
    }
   ]
  },
  "number": {
   "road": [
    {
     "angle": -0.0,
     "h": 9.4,
     "on": "plate",
     "visible": true,
     "w": 32.1,
     "x": 79.9,
     "y": 87.8
    },
    {
     "angle": 13.8,
     "h": 15.6,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 68.2,
     "y": 67.3
    },
    {
     "angle": 0.0,
     "h": 13.9,
     "on": "door",
     "visible": true,
     "w": 16.2,
     "x": 89.6,
     "y": 69.9
    },
    {
     "angle": -13.8,
     "h": 15.5,
     "on": "door",
     "visible": true,
     "w": 11.1,
     "x": 114.7,
     "y": 66.8
    },
    {
     "angle": 0,
     "h": 14.9,
     "on": "door",
     "visible": false,
     "w": 2.8,
     "x": 64.2,
     "y": 62.2
    },
    {
     "angle": 13.8,
     "h": 15.5,
     "on": "door",
     "visible": true,
     "w": 11.1,
     "x": 66.2,
     "y": 66.8
    },
    {
     "angle": -0.0,
     "h": 13.9,
     "on": "door",
     "visible": true,
     "w": 16.2,
     "x": 86.2,
     "y": 69.9
    },
    {
     "angle": -13.8,
     "h": 15.6,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 112.5,
     "y": 67.3
    }
   ],
   "stall": [
    {
     "angle": 24.3,
     "h": 14.9,
     "on": "plate",
     "visible": true,
     "w": 19.1,
     "x": 32.5,
     "y": 79.5
    },
    {
     "angle": -1.8,
     "h": 9.5,
     "on": "plate",
     "visible": true,
     "w": 30.7,
     "x": 86.8,
     "y": 91.1
    },
    {
     "angle": 18.8,
     "h": 15.4,
     "on": "door",
     "visible": true,
     "w": 11.5,
     "x": 70.9,
     "y": 63.8
    },
    {
     "angle": -1.5,
     "h": 13.0,
     "on": "door",
     "visible": true,
     "w": 15.4,
     "x": 92.1,
     "y": 67.3
    },
    {
     "angle": 0,
     "h": 15.5,
     "on": "door",
     "visible": false,
     "w": 9.8,
     "x": 115.2,
     "y": 62.0
    },
    {
     "angle": 0,
     "h": 15.1,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 66.2,
     "y": 56.0
    },
    {
     "angle": 18.8,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 68.8,
     "y": 63.2
    },
    {
     "angle": -1.5,
     "h": 13.0,
     "on": "door",
     "visible": true,
     "w": 15.4,
     "x": 88.9,
     "y": 67.4
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 },
 "wedge": {
  "anchor": "bottom-center",
  "body": "wedge",
  "cell": [
   [
    192,
    128
   ],
   [
    96,
    64
   ],
   [
    48,
    32
   ]
  ],
  "ground": {
   "road": [
    96.0,
    92.2
   ],
   "stall": [
    96.0,
    83.2
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       69.6,
       81.9
      ],
      [
       122.4,
       81.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       137.7,
       80.2
      ],
      [
       165.6,
       72.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       168.0,
       69.3
      ],
      [
       158.7,
       61.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       151.7,
       59.3
      ],
      [
       123.3,
       55.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.7,
       54.4
      ],
      [
       79.3,
       54.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.7,
       55.1
      ],
      [
       40.3,
       59.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       33.3,
       61.3
      ],
      [
       24.0,
       69.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       26.4,
       72.2
      ],
      [
       54.3,
       80.2
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       31.4,
       71.7
      ],
      [
       61.0,
       83.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       76.3,
       86.0
      ],
      [
       126.8,
       84.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       140.5,
       81.5
      ],
      [
       163.1,
       68.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       164.2,
       63.9
      ],
      [
       152.5,
       52.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       145.4,
       49.1
      ],
      [
       117.9,
       43.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.9,
       42.5
      ],
      [
       77.0,
       43.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       67.2,
       44.2
      ],
      [
       41.4,
       51.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       35.2,
       54.4
      ],
      [
       28.3,
       67.1
      ]
     ],
     "visible": false
    }
   ]
  },
  "number": {
   "road": [
    {
     "angle": -0.0,
     "h": 8.7,
     "on": "plate",
     "visible": true,
     "w": 31.5,
     "x": 80.3,
     "y": 88.1
    },
    {
     "angle": 14.4,
     "h": 15.5,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 70.8,
     "y": 70.7
    },
    {
     "angle": 0.0,
     "h": 13.5,
     "on": "door",
     "visible": true,
     "w": 15.8,
     "x": 96.6,
     "y": 72.6
    },
    {
     "angle": 0,
     "h": 14.8,
     "on": "door",
     "visible": false,
     "w": 10.5,
     "x": 120.9,
     "y": 68.3
    },
    {
     "angle": 0,
     "h": 14.1,
     "on": "door",
     "visible": false,
     "w": 2.7,
     "x": 62.6,
     "y": 63.1
    },
    {
     "angle": 0,
     "h": 14.8,
     "on": "door",
     "visible": false,
     "w": 10.5,
     "x": 60.6,
     "y": 68.3
    },
    {
     "angle": -0.0,
     "h": 13.5,
     "on": "door",
     "visible": true,
     "w": 15.8,
     "x": 79.6,
     "y": 72.6
    },
    {
     "angle": -14.4,
     "h": 15.5,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 110.1,
     "y": 70.7
    }
   ],
   "stall": [
    {
     "angle": 23.9,
     "h": 14.2,
     "on": "plate",
     "visible": true,
     "w": 19.0,
     "x": 36.5,
     "y": 79.5
    },
    {
     "angle": -1.8,
     "h": 8.8,
     "on": "plate",
     "visible": true,
     "w": 30.0,
     "x": 86.7,
     "y": 90.4
    },
    {
     "angle": 19.4,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 73.7,
     "y": 67.8
    },
    {
     "angle": -1.5,
     "h": 12.6,
     "on": "door",
     "visible": true,
     "w": 15.0,
     "x": 98.9,
     "y": 70.0
    },
    {
     "angle": 0,
     "h": 14.8,
     "on": "door",
     "visible": false,
     "w": 9.2,
     "x": 120.7,
     "y": 62.9
    },
    {
     "angle": 0,
     "h": 14.3,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 64.4,
     "y": 56.2
    },
    {
     "angle": 0,
     "h": 14.6,
     "on": "door",
     "visible": false,
     "w": 10.8,
     "x": 63.2,
     "y": 64.4
    },
    {
     "angle": -1.5,
     "h": 12.6,
     "on": "door",
     "visible": true,
     "w": 15.0,
     "x": 82.9,
     "y": 70.4
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 }
}
