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
    102.4
   ],
   "stall": [
    96.0,
    97.3
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       80.4,
       71.9
      ],
      [
       111.6,
       71.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       116.8,
       71.7
      ],
      [
       135.7,
       70.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       137.1,
       69.7
      ],
      [
       133.4,
       67.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       131.0,
       67.4
      ],
      [
       112.1,
       66.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.9,
       66.2
      ],
      [
       84.1,
       66.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       79.9,
       66.3
      ],
      [
       61.0,
       67.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       58.6,
       67.7
      ],
      [
       54.9,
       69.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       56.3,
       70.1
      ],
      [
       75.2,
       71.7
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       59.4,
       68.0
      ],
      [
       78.8,
       70.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       84.0,
       70.4
      ],
      [
       113.6,
       70.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       118.4,
       69.9
      ],
      [
       134.3,
       67.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       135.1,
       66.9
      ],
      [
       129.8,
       64.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       127.3,
       64.0
      ],
      [
       108.8,
       62.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       104.8,
       62.5
      ],
      [
       82.8,
       62.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       79.0,
       62.8
      ],
      [
       62.0,
       64.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       59.9,
       64.9
      ],
      [
       57.8,
       67.5
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
     "h": 8.0,
     "on": "plate",
     "visible": true,
     "w": 25.5,
     "x": 83.2,
     "y": 77.8
    },
    {
     "angle": -7.2,
     "h": 9.3,
     "on": "plate",
     "visible": true,
     "w": 16.4,
     "x": 118.3,
     "y": 75.8
    },
    {
     "angle": 0.0,
     "h": 12.0,
     "on": "door",
     "visible": true,
     "w": 13.8,
     "x": 97.4,
     "y": 70.3
    },
    {
     "angle": 0,
     "h": 12.3,
     "on": "door",
     "visible": false,
     "w": 9.5,
     "x": 112.6,
     "y": 69.1
    },
    {
     "angle": 0,
     "h": 11.8,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 73.9,
     "y": 67.8
    },
    {
     "angle": 0,
     "h": 12.3,
     "on": "door",
     "visible": false,
     "w": 9.5,
     "x": 69.9,
     "y": 69.1
    },
    {
     "angle": -0.0,
     "h": 12.0,
     "on": "door",
     "visible": true,
     "w": 13.8,
     "x": 80.8,
     "y": 70.3
    },
    {
     "angle": 7.2,
     "h": 9.3,
     "on": "plate",
     "visible": true,
     "w": 16.4,
     "x": 57.3,
     "y": 75.8
    }
   ],
   "stall": [
    {
     "angle": 8.4,
     "h": 9.3,
     "on": "plate",
     "visible": true,
     "w": 16.8,
     "x": 60.5,
     "y": 73.6
    },
    {
     "angle": -0.6,
     "h": 7.8,
     "on": "plate",
     "visible": true,
     "w": 24.3,
     "x": 86.7,
     "y": 75.8
    },
    {
     "angle": -11.3,
     "h": 9.4,
     "on": "plate",
     "visible": true,
     "w": 14.0,
     "x": 119.5,
     "y": 73.0
    },
    {
     "angle": -0.5,
     "h": 11.4,
     "on": "door",
     "visible": true,
     "w": 13.1,
     "x": 98.7,
     "y": 67.9
    },
    {
     "angle": 0,
     "h": 11.8,
     "on": "door",
     "visible": false,
     "w": 8.3,
     "x": 112.4,
     "y": 66.3
    },
    {
     "angle": 0,
     "h": 11.4,
     "on": "door",
     "visible": false,
     "w": 1.2,
     "x": 75.1,
     "y": 64.8
    },
    {
     "angle": 0,
     "h": 11.8,
     "on": "door",
     "visible": false,
     "w": 9.6,
     "x": 71.7,
     "y": 66.6
    },
    {
     "angle": -0.5,
     "h": 11.5,
     "on": "door",
     "visible": true,
     "w": 13.1,
     "x": 83.1,
     "y": 68.0
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
    102.4
   ],
   "stall": [
    96.0,
    97.3
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       67.1,
       75.4
      ],
      [
       124.9,
       75.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       133.1,
       75.0
      ],
      [
       164.0,
       71.7
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       165.3,
       71.1
      ],
      [
       155.3,
       67.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       151.5,
       67.3
      ],
      [
       120.2,
       65.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       114.4,
       65.4
      ],
      [
       77.6,
       65.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       71.8,
       65.5
      ],
      [
       40.5,
       67.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       36.7,
       67.7
      ],
      [
       26.7,
       71.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       28.0,
       71.7
      ],
      [
       58.9,
       75.0
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       32.6,
       70.2
      ],
      [
       65.0,
       74.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       73.3,
       75.0
      ],
      [
       128.8,
       74.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       136.2,
       73.9
      ],
      [
       161.3,
       69.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       161.8,
       68.4
      ],
      [
       149.1,
       64.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       145.2,
       63.5
      ],
      [
       115.1,
       61.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       109.7,
       61.3
      ],
      [
       75.7,
       61.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       70.5,
       61.7
      ],
      [
       42.1,
       64.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       38.7,
       64.7
      ],
      [
       30.9,
       69.4
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
     "h": 9.5,
     "on": "plate",
     "visible": true,
     "w": 31.9,
     "x": 80.1,
     "y": 78.5
    },
    {
     "angle": 6.9,
     "h": 15.7,
     "on": "door",
     "visible": true,
     "w": 11.8,
     "x": 68.7,
     "y": 72.5
    },
    {
     "angle": 0.0,
     "h": 14.9,
     "on": "door",
     "visible": true,
     "w": 17.1,
     "x": 92.6,
     "y": 73.4
    },
    {
     "angle": -6.9,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 118.1,
     "y": 71.9
    },
    {
     "angle": 0,
     "h": 14.3,
     "on": "door",
     "visible": false,
     "w": 2.8,
     "x": 62.8,
     "y": 69.9
    },
    {
     "angle": 6.9,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 62.5,
     "y": 71.9
    },
    {
     "angle": -0.0,
     "h": 14.9,
     "on": "door",
     "visible": true,
     "w": 17.1,
     "x": 82.3,
     "y": 73.4
    },
    {
     "angle": -6.9,
     "h": 15.7,
     "on": "door",
     "visible": true,
     "w": 11.8,
     "x": 111.5,
     "y": 72.5
    }
   ],
   "stall": [
    {
     "angle": 9.4,
     "h": 11.0,
     "on": "plate",
     "visible": true,
     "w": 19.0,
     "x": 38.5,
     "y": 74.0
    },
    {
     "angle": -0.6,
     "h": 9.4,
     "on": "plate",
     "visible": true,
     "w": 30.7,
     "x": 85.9,
     "y": 77.6
    },
    {
     "angle": 8.0,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 12.0,
     "x": 71.5,
     "y": 70.3
    },
    {
     "angle": -0.6,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 16.3,
     "x": 95.1,
     "y": 71.3
    },
    {
     "angle": 0,
     "h": 14.7,
     "on": "door",
     "visible": false,
     "w": 9.8,
     "x": 118.4,
     "y": 69.2
    },
    {
     "angle": 0,
     "h": 13.8,
     "on": "door",
     "visible": false,
     "w": 1.9,
     "x": 64.8,
     "y": 66.9
    },
    {
     "angle": 8.0,
     "h": 14.8,
     "on": "door",
     "visible": true,
     "w": 11.5,
     "x": 65.2,
     "y": 69.6
    },
    {
     "angle": -0.6,
     "h": 14.3,
     "on": "door",
     "visible": true,
     "w": 16.3,
     "x": 85.3,
     "y": 71.4
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
    102.4
   ],
   "stall": [
    96.0,
    97.3
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       72.5,
       72.9
      ],
      [
       119.5,
       72.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       127.7,
       72.6
      ],
      [
       154.0,
       70.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       155.6,
       69.5
      ],
      [
       148.3,
       66.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       144.5,
       66.4
      ],
      [
       118.0,
       64.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       111.9,
       64.8
      ],
      [
       80.1,
       64.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       74.0,
       64.9
      ],
      [
       47.5,
       66.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       43.7,
       66.8
      ],
      [
       36.4,
       69.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       38.0,
       70.1
      ],
      [
       64.3,
       72.6
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       42.2,
       68.4
      ],
      [
       69.5,
       71.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       77.8,
       72.1
      ],
      [
       122.8,
       71.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       130.2,
       71.3
      ],
      [
       151.8,
       67.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       152.6,
       66.8
      ],
      [
       143.0,
       63.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       139.1,
       62.8
      ],
      [
       113.4,
       61.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.8,
       60.9
      ],
      [
       78.4,
       61.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       72.8,
       61.2
      ],
      [
       48.9,
       63.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       45.5,
       63.9
      ],
      [
       40.2,
       67.6
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
     "w": 28.5,
     "x": 81.7,
     "y": 77.2
    },
    {
     "angle": 6.8,
     "h": 14.7,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 71.6,
     "y": 73.0
    },
    {
     "angle": 0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 15.9,
     "x": 94.9,
     "y": 73.7
    },
    {
     "angle": 0,
     "h": 14.2,
     "on": "door",
     "visible": false,
     "w": 10.6,
     "x": 118.1,
     "y": 72.2
    },
    {
     "angle": 0,
     "h": 13.3,
     "on": "door",
     "visible": false,
     "w": 2.6,
     "x": 64.8,
     "y": 70.2
    },
    {
     "angle": 0,
     "h": 14.2,
     "on": "door",
     "visible": false,
     "w": 10.6,
     "x": 63.3,
     "y": 72.2
    },
    {
     "angle": -0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 15.9,
     "x": 81.2,
     "y": 73.7
    },
    {
     "angle": -6.8,
     "h": 14.7,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 109.2,
     "y": 73.0
    }
   ],
   "stall": [
    {
     "angle": 8.8,
     "h": 10.4,
     "on": "plate",
     "visible": true,
     "w": 17.8,
     "x": 47.8,
     "y": 73.0
    },
    {
     "angle": -0.6,
     "h": 9.0,
     "on": "plate",
     "visible": true,
     "w": 27.3,
     "x": 86.6,
     "y": 75.9
    },
    {
     "angle": 7.9,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 74.3,
     "y": 70.8
    },
    {
     "angle": -0.6,
     "h": 13.2,
     "on": "door",
     "visible": true,
     "w": 15.1,
     "x": 97.1,
     "y": 71.5
    },
    {
     "angle": 0,
     "h": 13.6,
     "on": "door",
     "visible": false,
     "w": 9.2,
     "x": 118.1,
     "y": 69.3
    },
    {
     "angle": 0,
     "h": 12.9,
     "on": "door",
     "visible": false,
     "w": 1.8,
     "x": 66.6,
     "y": 67.1
    },
    {
     "angle": 0,
     "h": 13.7,
     "on": "door",
     "visible": false,
     "w": 10.7,
     "x": 65.8,
     "y": 69.8
    },
    {
     "angle": -0.6,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 15.1,
     "x": 84.1,
     "y": 71.6
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
    102.4
   ],
   "stall": [
    96.0,
    97.3
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       69.6,
       83.3
      ],
      [
       122.4,
       83.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       138.4,
       82.5
      ],
      [
       166.1,
       78.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       168.5,
       77.1
      ],
      [
       159.0,
       73.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       151.6,
       72.2
      ],
      [
       123.5,
       70.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.4,
       69.9
      ],
      [
       79.6,
       69.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.5,
       70.2
      ],
      [
       40.4,
       72.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       33.0,
       73.3
      ],
      [
       23.5,
       77.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       25.9,
       78.6
      ],
      [
       53.6,
       82.5
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       30.8,
       77.0
      ],
      [
       59.9,
       81.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       76.1,
       82.9
      ],
      [
       126.9,
       82.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       141.3,
       81.0
      ],
      [
       163.6,
       75.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       164.4,
       73.8
      ],
      [
       152.6,
       69.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       145.0,
       67.9
      ],
      [
       118.0,
       65.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.7,
       65.3
      ],
      [
       77.5,
       65.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       67.4,
       66.0
      ],
      [
       41.9,
       68.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       35.2,
       70.1
      ],
      [
       27.8,
       75.1
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
     "h": 9.0,
     "on": "plate",
     "visible": true,
     "w": 32.5,
     "x": 79.7,
     "y": 69.0
    },
    {
     "angle": -5.8,
     "h": 9.8,
     "on": "plate",
     "visible": true,
     "w": 18.2,
     "x": 144.1,
     "y": 66.7
    },
    {
     "angle": 0.0,
     "h": 12.5,
     "on": "door",
     "visible": true,
     "w": 14.4,
     "x": 107.7,
     "y": 65.6
    },
    {
     "angle": 0,
     "h": 12.2,
     "on": "door",
     "visible": false,
     "w": 9.2,
     "x": 126.5,
     "y": 64.1
    },
    {
     "angle": 0,
     "h": 11.3,
     "on": "door",
     "visible": false,
     "w": 2.3,
     "x": 65.4,
     "y": 62.7
    },
    {
     "angle": 0,
     "h": 12.2,
     "on": "door",
     "visible": false,
     "w": 9.2,
     "x": 56.3,
     "y": 64.1
    },
    {
     "angle": -0.0,
     "h": 12.5,
     "on": "door",
     "visible": true,
     "w": 14.4,
     "x": 69.9,
     "y": 65.6
    },
    {
     "angle": 5.8,
     "h": 9.8,
     "on": "plate",
     "visible": true,
     "w": 18.2,
     "x": 29.7,
     "y": 66.7
    }
   ],
   "stall": [
    {
     "angle": 7.5,
     "h": 10.1,
     "on": "plate",
     "visible": true,
     "w": 19.1,
     "x": 34.7,
     "y": 65.8
    },
    {
     "angle": -0.5,
     "h": 9.0,
     "on": "plate",
     "visible": true,
     "w": 31.4,
     "x": 86.0,
     "y": 68.7
    },
    {
     "angle": 0,
     "h": 13.0,
     "on": "door",
     "visible": false,
     "w": 10.8,
     "x": 82.2,
     "y": 64.0
    },
    {
     "angle": -0.5,
     "h": 11.9,
     "on": "door",
     "visible": true,
     "w": 13.7,
     "x": 109.2,
     "y": 63.8
    },
    {
     "angle": 0,
     "h": 11.7,
     "on": "door",
     "visible": false,
     "w": 7.9,
     "x": 125.4,
     "y": 61.6
    },
    {
     "angle": 0,
     "h": 10.9,
     "on": "door",
     "visible": false,
     "w": 1.6,
     "x": 66.5,
     "y": 59.8
    },
    {
     "angle": 0,
     "h": 11.8,
     "on": "door",
     "visible": false,
     "w": 9.3,
     "x": 58.7,
     "y": 62.0
    },
    {
     "angle": -0.5,
     "h": 12.0,
     "on": "door",
     "visible": true,
     "w": 13.8,
     "x": 73.3,
     "y": 64.0
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
    102.4
   ],
   "stall": [
    96.0,
    97.3
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       70.8,
       74.1
      ],
      [
       121.2,
       74.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       145.2,
       73.1
      ],
      [
       170.7,
       70.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       173.9,
       68.8
      ],
      [
       164.4,
       66.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       153.3,
       65.1
      ],
      [
       127.2,
       63.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       111.1,
       63.5
      ],
      [
       80.9,
       63.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       64.8,
       63.8
      ],
      [
       38.7,
       65.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       27.6,
       66.2
      ],
      [
       18.1,
       68.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       21.3,
       70.4
      ],
      [
       46.8,
       73.1
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       26.5,
       69.4
      ],
      [
       53.4,
       73.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       77.8,
       74.2
      ],
      [
       126.5,
       73.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       148.1,
       72.2
      ],
      [
       168.4,
       68.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       169.3,
       66.1
      ],
      [
       157.6,
       62.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       146.3,
       61.3
      ],
      [
       121.3,
       59.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       106.2,
       59.4
      ],
      [
       78.5,
       59.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       63.8,
       60.1
      ],
      [
       40.0,
       61.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       30.0,
       63.5
      ],
      [
       22.3,
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
     "h": 9.9,
     "on": "plate",
     "visible": true,
     "w": 33.2,
     "x": 79.4,
     "y": 78.9
    },
    {
     "angle": 6.6,
     "h": 14.9,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 69.5,
     "y": 71.7
    },
    {
     "angle": 0.0,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 16.4,
     "x": 89.5,
     "y": 72.6
    },
    {
     "angle": -6.6,
     "h": 14.8,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 113.4,
     "y": 71.5
    },
    {
     "angle": 0,
     "h": 14.0,
     "on": "door",
     "visible": false,
     "w": 2.6,
     "x": 65.9,
     "y": 69.7
    },
    {
     "angle": 6.6,
     "h": 14.8,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 67.5,
     "y": 71.5
    },
    {
     "angle": -0.0,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 16.4,
     "x": 86.1,
     "y": 72.6
    },
    {
     "angle": -6.6,
     "h": 14.9,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 111.2,
     "y": 71.7
    }
   ],
   "stall": [
    {
     "angle": 9.8,
     "h": 11.4,
     "on": "plate",
     "visible": true,
     "w": 19.0,
     "x": 30.3,
     "y": 74.3
    },
    {
     "angle": -0.7,
     "h": 9.9,
     "on": "plate",
     "visible": true,
     "w": 32.1,
     "x": 86.2,
     "y": 78.4
    },
    {
     "angle": 7.7,
     "h": 14.4,
     "on": "door",
     "visible": true,
     "w": 11.5,
     "x": 72.0,
     "y": 69.4
    },
    {
     "angle": -0.6,
     "h": 13.6,
     "on": "door",
     "visible": true,
     "w": 15.5,
     "x": 91.9,
     "y": 70.5
    },
    {
     "angle": 0,
     "h": 14.2,
     "on": "door",
     "visible": false,
     "w": 9.7,
     "x": 114.0,
     "y": 68.8
    },
    {
     "angle": 0,
     "h": 13.5,
     "on": "door",
     "visible": false,
     "w": 1.7,
     "x": 67.9,
     "y": 66.8
    },
    {
     "angle": 7.7,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 69.9,
     "y": 69.2
    },
    {
     "angle": -0.6,
     "h": 13.6,
     "on": "door",
     "visible": true,
     "w": 15.5,
     "x": 88.7,
     "y": 70.5
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
    102.4
   ],
   "stall": [
    96.0,
    97.3
   ]
  },
  "lamps": {
   "road": [
    {
     "tail": [
      [
       68.8,
       76.7
      ],
      [
       123.2,
       76.7
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       138.8,
       76.0
      ],
      [
       167.1,
       72.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       169.5,
       71.6
      ],
      [
       159.6,
       68.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       152.4,
       67.6
      ],
      [
       123.5,
       65.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.8,
       65.7
      ],
      [
       79.2,
       65.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.5,
       65.9
      ],
      [
       39.6,
       67.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       32.4,
       68.4
      ],
      [
       22.5,
       71.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       24.9,
       72.8
      ],
      [
       53.2,
       76.0
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       29.7,
       71.4
      ],
      [
       59.6,
       75.7
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       75.4,
       76.5
      ],
      [
       127.7,
       76.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       141.8,
       74.9
      ],
      [
       164.6,
       70.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       165.4,
       68.7
      ],
      [
       153.1,
       64.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       145.8,
       63.7
      ],
      [
       118.0,
       61.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       108.1,
       61.4
      ],
      [
       77.0,
       61.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       67.3,
       62.0
      ],
      [
       41.1,
       64.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       34.6,
       65.5
      ],
      [
       26.8,
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
     "h": 7.8,
     "on": "plate",
     "visible": true,
     "w": 32.5,
     "x": 79.8,
     "y": 81.6
    },
    {
     "angle": 7.8,
     "h": 14.9,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 70.3,
     "y": 77.3
    },
    {
     "angle": 0.0,
     "h": 14.0,
     "on": "door",
     "visible": true,
     "w": 16.1,
     "x": 96.6,
     "y": 78.1
    },
    {
     "angle": 0,
     "h": 14.3,
     "on": "door",
     "visible": false,
     "w": 10.5,
     "x": 121.5,
     "y": 76.1
    },
    {
     "angle": 0,
     "h": 13.3,
     "on": "door",
     "visible": false,
     "w": 2.7,
     "x": 62.2,
     "y": 73.6
    },
    {
     "angle": 0,
     "h": 14.3,
     "on": "door",
     "visible": false,
     "w": 10.5,
     "x": 60.0,
     "y": 76.1
    },
    {
     "angle": -0.0,
     "h": 14.0,
     "on": "door",
     "visible": true,
     "w": 16.1,
     "x": 79.3,
     "y": 78.1
    },
    {
     "angle": -7.8,
     "h": 14.9,
     "on": "door",
     "visible": true,
     "w": 11.3,
     "x": 110.4,
     "y": 77.3
    }
   ],
   "stall": [
    {
     "angle": 10.0,
     "h": 9.7,
     "on": "plate",
     "visible": true,
     "w": 19.0,
     "x": 34.6,
     "y": 76.6
    },
    {
     "angle": -0.7,
     "h": 7.8,
     "on": "plate",
     "visible": true,
     "w": 31.3,
     "x": 86.1,
     "y": 80.8
    },
    {
     "angle": 8.9,
     "h": 14.4,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 73.3,
     "y": 74.9
    },
    {
     "angle": -0.7,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 15.2,
     "x": 98.9,
     "y": 75.8
    },
    {
     "angle": 0,
     "h": 13.7,
     "on": "door",
     "visible": false,
     "w": 9.1,
     "x": 121.4,
     "y": 73.0
    },
    {
     "angle": 0,
     "h": 12.9,
     "on": "door",
     "visible": false,
     "w": 1.9,
     "x": 64.0,
     "y": 70.3
    },
    {
     "angle": 0,
     "h": 13.8,
     "on": "door",
     "visible": false,
     "w": 10.7,
     "x": 62.7,
     "y": 73.5
    },
    {
     "angle": -0.7,
     "h": 13.4,
     "on": "door",
     "visible": true,
     "w": 15.3,
     "x": 82.5,
     "y": 75.9
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 }
}
