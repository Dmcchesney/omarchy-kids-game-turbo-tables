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
     "h": 8.3,
     "on": "plate",
     "visible": true,
     "w": 25.0,
     "x": 83.5,
     "y": 72.9
    },
    {
     "angle": 12.3,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 10.4,
     "x": 81.2,
     "y": 63.0
    },
    {
     "angle": 0.0,
     "h": 12.1,
     "on": "door",
     "visible": true,
     "w": 14.1,
     "x": 97.1,
     "y": 63.8
    },
    {
     "angle": -12.3,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 9.8,
     "x": 111.3,
     "y": 60.9
    },
    {
     "angle": 0,
     "h": 13.0,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 75.2,
     "y": 57.9
    },
    {
     "angle": 12.3,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 9.8,
     "x": 70.9,
     "y": 60.9
    },
    {
     "angle": -0.0,
     "h": 12.1,
     "on": "door",
     "visible": true,
     "w": 14.1,
     "x": 80.8,
     "y": 63.8
    },
    {
     "angle": -12.3,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 10.4,
     "x": 100.4,
     "y": 63.0
    }
   ],
   "stall": [
    {
     "angle": 19.3,
     "h": 12.2,
     "on": "plate",
     "visible": true,
     "w": 16.7,
     "x": 61.2,
     "y": 65.7
    },
    {
     "angle": -1.5,
     "h": 8.2,
     "on": "plate",
     "visible": true,
     "w": 23.8,
     "x": 87.0,
     "y": 71.3
    },
    {
     "angle": 17.2,
     "h": 13.7,
     "on": "door",
     "visible": true,
     "w": 10.5,
     "x": 83.0,
     "y": 59.3
    },
    {
     "angle": -1.4,
     "h": 11.4,
     "on": "door",
     "visible": true,
     "w": 13.4,
     "x": 98.4,
     "y": 60.1
    },
    {
     "angle": -22.5,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 8.6,
     "x": 111.2,
     "y": 55.3
    },
    {
     "angle": 0,
     "h": 13.2,
     "on": "door",
     "visible": false,
     "w": 1.3,
     "x": 76.2,
     "y": 51.2
    },
    {
     "angle": 17.2,
     "h": 13.1,
     "on": "door",
     "visible": true,
     "w": 10.0,
     "x": 72.5,
     "y": 56.2
    },
    {
     "angle": -1.4,
     "h": 11.4,
     "on": "door",
     "visible": true,
     "w": 13.4,
     "x": 83.0,
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
       70.7,
       78.8
      ],
      [
       121.3,
       78.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       135.9,
       77.3
      ],
      [
       163.0,
       70.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       165.4,
       67.2
      ],
      [
       156.7,
       59.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       149.9,
       57.8
      ],
      [
       122.5,
       53.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.2,
       53.2
      ],
      [
       79.8,
       53.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       69.5,
       53.9
      ],
      [
       42.1,
       57.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       35.3,
       59.8
      ],
      [
       26.6,
       67.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       29.0,
       70.0
      ],
      [
       56.1,
       77.3
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       33.9,
       69.4
      ],
      [
       62.5,
       80.6
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       77.1,
       82.7
      ],
      [
       125.5,
       81.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       138.6,
       78.6
      ],
      [
       160.6,
       66.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       161.7,
       62.0
      ],
      [
       150.8,
       50.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       143.9,
       47.9
      ],
      [
       117.3,
       42.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.6,
       41.6
      ],
      [
       77.5,
       42.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.0,
       43.3
      ],
      [
       43.1,
       49.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       37.1,
       53.0
      ],
      [
       30.8,
       65.0
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
     "h": 10.4,
     "on": "plate",
     "visible": true,
     "w": 31.2,
     "x": 80.4,
     "y": 84.9
    },
    {
     "angle": 14.2,
     "h": 17.3,
     "on": "door",
     "visible": true,
     "w": 12.4,
     "x": 70.2,
     "y": 68.8
    },
    {
     "angle": 0.0,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 17.8,
     "x": 92.2,
     "y": 71.1
    },
    {
     "angle": -14.2,
     "h": 16.9,
     "on": "door",
     "visible": true,
     "w": 12.0,
     "x": 115.9,
     "y": 67.4
    },
    {
     "angle": 0,
     "h": 16.2,
     "on": "door",
     "visible": false,
     "w": 2.9,
     "x": 64.9,
     "y": 62.7
    },
    {
     "angle": 14.2,
     "h": 16.9,
     "on": "door",
     "visible": true,
     "w": 12.0,
     "x": 64.1,
     "y": 67.4
    },
    {
     "angle": -0.0,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 17.8,
     "x": 82.1,
     "y": 71.1
    },
    {
     "angle": -14.2,
     "h": 17.3,
     "on": "door",
     "visible": true,
     "w": 12.4,
     "x": 109.4,
     "y": 68.8
    }
   ],
   "stall": [
    {
     "angle": 23.3,
     "h": 15.5,
     "on": "plate",
     "visible": true,
     "w": 19.1,
     "x": 38.6,
     "y": 76.8
    },
    {
     "angle": -1.8,
     "h": 10.3,
     "on": "plate",
     "visible": true,
     "w": 29.8,
     "x": 86.5,
     "y": 87.0
    },
    {
     "angle": 19.1,
     "h": 17.0,
     "on": "door",
     "visible": true,
     "w": 12.7,
     "x": 72.8,
     "y": 65.4
    },
    {
     "angle": -1.5,
     "h": 14.1,
     "on": "door",
     "visible": true,
     "w": 16.8,
     "x": 94.5,
     "y": 68.2
    },
    {
     "angle": -25.1,
     "h": 16.8,
     "on": "door",
     "visible": true,
     "w": 10.5,
     "x": 116.2,
     "y": 62.1
    },
    {
     "angle": 0,
     "h": 16.5,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 66.7,
     "y": 56.0
    },
    {
     "angle": 19.1,
     "h": 16.6,
     "on": "door",
     "visible": true,
     "w": 12.3,
     "x": 66.6,
     "y": 63.4
    },
    {
     "angle": -1.5,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 16.9,
     "x": 85.0,
     "y": 68.4
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
       72.9,
       72.2
      ],
      [
       119.1,
       72.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       126.7,
       71.5
      ],
      [
       152.8,
       65.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       154.4,
       63.9
      ],
      [
       147.4,
       57.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       143.9,
       56.1
      ],
      [
       117.5,
       52.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       111.9,
       52.1
      ],
      [
       80.1,
       52.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       74.5,
       52.4
      ],
      [
       48.1,
       56.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       44.6,
       57.1
      ],
      [
       37.6,
       63.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       39.2,
       65.2
      ],
      [
       65.3,
       71.5
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
       63.7
      ],
      [
       70.6,
       73.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       78.2,
       74.5
      ],
      [
       122.3,
       73.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       129.2,
       72.0
      ],
      [
       150.8,
       61.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       151.7,
       59.1
      ],
      [
       142.4,
       48.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       138.8,
       47.1
      ],
      [
       113.1,
       41.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.8,
       41.3
      ],
      [
       78.2,
       41.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       73.0,
       42.5
      ],
      [
       49.1,
       48.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       46.1,
       50.5
      ],
      [
       41.3,
       61.5
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
     "h": 10.0,
     "on": "plate",
     "visible": true,
     "w": 30.0,
     "x": 81.0,
     "y": 79.5
    },
    {
     "angle": 13.9,
     "h": 15.8,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 72.2,
     "y": 68.4
    },
    {
     "angle": 0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 16.1,
     "x": 94.7,
     "y": 70.3
    },
    {
     "angle": -13.9,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 10.9,
     "x": 117.0,
     "y": 66.6
    },
    {
     "angle": 0,
     "h": 14.6,
     "on": "door",
     "visible": false,
     "w": 2.6,
     "x": 65.7,
     "y": 62.0
    },
    {
     "angle": 13.9,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 10.9,
     "x": 64.1,
     "y": 66.6
    },
    {
     "angle": -0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 16.1,
     "x": 81.2,
     "y": 70.3
    },
    {
     "angle": -13.9,
     "h": 15.8,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 108.3,
     "y": 68.4
    }
   ],
   "stall": [
    {
     "angle": 21.6,
     "h": 14.7,
     "on": "plate",
     "visible": true,
     "w": 19.0,
     "x": 47.4,
     "y": 71.8
    },
    {
     "angle": -1.7,
     "h": 9.9,
     "on": "plate",
     "visible": true,
     "w": 28.5,
     "x": 86.1,
     "y": 80.1
    },
    {
     "angle": 18.8,
     "h": 15.5,
     "on": "door",
     "visible": true,
     "w": 11.7,
     "x": 74.8,
     "y": 65.2
    },
    {
     "angle": -1.5,
     "h": 12.9,
     "on": "door",
     "visible": true,
     "w": 15.3,
     "x": 96.9,
     "y": 67.4
    },
    {
     "angle": -24.7,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 9.6,
     "x": 117.1,
     "y": 61.2
    },
    {
     "angle": 0,
     "h": 14.9,
     "on": "door",
     "visible": false,
     "w": 1.9,
     "x": 67.4,
     "y": 55.2
    },
    {
     "angle": 18.8,
     "h": 15.0,
     "on": "door",
     "visible": true,
     "w": 11.2,
     "x": 66.5,
     "y": 62.5
    },
    {
     "angle": -1.5,
     "h": 12.9,
     "on": "door",
     "visible": true,
     "w": 15.3,
     "x": 84.1,
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
       86.2
      ],
      [
       121.7,
       86.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       137.3,
       84.4
      ],
      [
       164.5,
       76.2
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       167.1,
       73.0
      ],
      [
       158.1,
       64.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       150.9,
       62.5
      ],
      [
       123.2,
       58.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.3,
       57.4
      ],
      [
       79.7,
       57.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.8,
       58.1
      ],
      [
       41.1,
       62.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       33.9,
       64.7
      ],
      [
       24.9,
       73.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       27.5,
       76.2
      ],
      [
       54.7,
       84.4
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
       75.3
      ],
      [
       61.4,
       87.4
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       77.0,
       89.8
      ],
      [
       125.9,
       88.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       139.9,
       85.1
      ],
      [
       162.0,
       71.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       163.1,
       67.1
      ],
      [
       151.9,
       55.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       144.5,
       52.0
      ],
      [
       117.8,
       46.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.6,
       45.2
      ],
      [
       77.4,
       45.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       67.4,
       47.1
      ],
      [
       42.3,
       54.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       35.9,
       57.6
      ],
      [
       29.3,
       70.4
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
     "w": 31.8,
     "x": 80.1,
     "y": 71.0
    },
    {
     "angle": 12.4,
     "h": 14.4,
     "on": "door",
     "visible": true,
     "w": 10.3,
     "x": 56.1,
     "y": 57.9
    },
    {
     "angle": 0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 16.3,
     "x": 63.0,
     "y": 63.0
    },
    {
     "angle": -12.4,
     "h": 16.3,
     "on": "door",
     "visible": true,
     "w": 12.3,
     "x": 92.7,
     "y": 64.0
    },
    {
     "angle": 0,
     "h": 16.2,
     "on": "door",
     "visible": false,
     "w": 2.9,
     "x": 66.0,
     "y": 61.3
    },
    {
     "angle": 12.4,
     "h": 16.3,
     "on": "door",
     "visible": true,
     "w": 12.3,
     "x": 87.0,
     "y": 64.0
    },
    {
     "angle": -0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 16.3,
     "x": 112.7,
     "y": 63.0
    },
    {
     "angle": -12.4,
     "h": 14.4,
     "on": "door",
     "visible": true,
     "w": 10.3,
     "x": 125.7,
     "y": 57.9
    }
   ],
   "stall": [
    {
     "angle": 21.2,
     "h": 14.2,
     "on": "plate",
     "visible": true,
     "w": 19.4,
     "x": 35.8,
     "y": 65.4
    },
    {
     "angle": -1.6,
     "h": 9.5,
     "on": "plate",
     "visible": true,
     "w": 30.7,
     "x": 86.4,
     "y": 74.9
    },
    {
     "angle": 17.5,
     "h": 14.2,
     "on": "door",
     "visible": true,
     "w": 10.6,
     "x": 57.9,
     "y": 52.9
    },
    {
     "angle": -1.4,
     "h": 13.0,
     "on": "door",
     "visible": true,
     "w": 15.7,
     "x": 66.4,
     "y": 61.0
    },
    {
     "angle": -23.0,
     "h": 16.6,
     "on": "door",
     "visible": true,
     "w": 10.9,
     "x": 95.9,
     "y": 61.9
    },
    {
     "angle": 0,
     "h": 16.8,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 69.5,
     "y": 58.2
    },
    {
     "angle": 17.5,
     "h": 16.2,
     "on": "door",
     "visible": true,
     "w": 12.6,
     "x": 89.6,
     "y": 62.2
    },
    {
     "angle": -1.4,
     "h": 12.9,
     "on": "door",
     "visible": true,
     "w": 15.5,
     "x": 113.5,
     "y": 59.9
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
       70.4,
       79.8
      ],
      [
       121.6,
       79.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       144.4,
       77.4
      ],
      [
       170.5,
       70.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       173.7,
       65.9
      ],
      [
       164.2,
       58.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       153.7,
       55.9
      ],
      [
       126.9,
       52.2
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       111.5,
       51.3
      ],
      [
       80.5,
       51.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       65.1,
       52.2
      ],
      [
       38.3,
       55.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       27.8,
       58.7
      ],
      [
       18.3,
       65.9
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       21.5,
       70.0
      ],
      [
       47.6,
       77.4
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       26.8,
       70.6
      ],
      [
       54.7,
       82.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       77.7,
       85.4
      ],
      [
       126.7,
       84.0
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       147.2,
       79.5
      ],
      [
       168.2,
       67.1
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       169.3,
       60.5
      ],
      [
       157.7,
       49.7
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       146.9,
       45.6
      ],
      [
       121.1,
       40.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       106.6,
       39.3
      ],
      [
       77.8,
       39.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       63.6,
       41.4
      ],
      [
       39.2,
       47.6
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       29.8,
       52.3
      ],
      [
       22.5,
       63.9
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
     "h": 10.7,
     "on": "plate",
     "visible": true,
     "w": 32.4,
     "x": 79.8,
     "y": 85.3
    },
    {
     "angle": 13.9,
     "h": 16.1,
     "on": "door",
     "visible": true,
     "w": 11.6,
     "x": 68.9,
     "y": 67.5
    },
    {
     "angle": 0.0,
     "h": 14.3,
     "on": "door",
     "visible": true,
     "w": 16.7,
     "x": 89.3,
     "y": 70.1
    },
    {
     "angle": -13.9,
     "h": 16.0,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 113.7,
     "y": 67.0
    },
    {
     "angle": 0,
     "h": 15.4,
     "on": "door",
     "visible": false,
     "w": 2.8,
     "x": 65.2,
     "y": 62.6
    },
    {
     "angle": 13.9,
     "h": 16.0,
     "on": "door",
     "visible": true,
     "w": 11.4,
     "x": 66.9,
     "y": 67.0
    },
    {
     "angle": -0.0,
     "h": 14.3,
     "on": "door",
     "visible": true,
     "w": 16.7,
     "x": 86.0,
     "y": 70.1
    },
    {
     "angle": -13.9,
     "h": 16.1,
     "on": "door",
     "visible": true,
     "w": 11.6,
     "x": 111.5,
     "y": 67.5
    }
   ],
   "stall": [
    {
     "angle": -24.7,
     "h": 16.1,
     "on": "door",
     "visible": true,
     "w": 10.2,
     "x": 112.4,
     "y": 62.8
    },
    {
     "angle": -1.8,
     "h": 10.7,
     "on": "plate",
     "visible": true,
     "w": 31.0,
     "x": 86.8,
     "y": 89.2
    },
    {
     "angle": 18.8,
     "h": 15.8,
     "on": "door",
     "visible": true,
     "w": 11.8,
     "x": 71.5,
     "y": 63.9
    },
    {
     "angle": -1.5,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 15.8,
     "x": 91.8,
     "y": 67.3
    },
    {
     "angle": -24.7,
     "h": 15.9,
     "on": "door",
     "visible": true,
     "w": 10.1,
     "x": 114.2,
     "y": 62.1
    },
    {
     "angle": 0,
     "h": 15.6,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 67.2,
     "y": 56.3
    },
    {
     "angle": 18.8,
     "h": 15.7,
     "on": "door",
     "visible": true,
     "w": 11.7,
     "x": 69.4,
     "y": 63.2
    },
    {
     "angle": -1.5,
     "h": 13.3,
     "on": "door",
     "visible": true,
     "w": 15.8,
     "x": 88.6,
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
       84.9
      ],
      [
       122.4,
       84.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       137.6,
       83.2
      ],
      [
       165.5,
       74.9
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       167.9,
       71.8
      ],
      [
       158.6,
       63.5
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       151.6,
       61.4
      ],
      [
       123.2,
       57.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       112.6,
       56.3
      ],
      [
       79.4,
       56.3
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       68.8,
       57.0
      ],
      [
       40.4,
       61.4
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       33.4,
       63.5
      ],
      [
       24.1,
       71.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       26.5,
       74.9
      ],
      [
       54.4,
       83.2
      ]
     ],
     "visible": true
    }
   ],
   "stall": [
    {
     "tail": [
      [
       31.6,
       74.1
      ],
      [
       61.1,
       86.5
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       76.4,
       88.7
      ],
      [
       126.7,
       87.3
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       140.3,
       84.2
      ],
      [
       162.9,
       70.8
      ]
     ],
     "visible": true
    },
    {
     "tail": [
      [
       163.9,
       66.1
      ],
      [
       152.4,
       54.0
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       145.2,
       51.0
      ],
      [
       117.8,
       45.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       107.9,
       44.2
      ],
      [
       77.0,
       44.8
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       67.3,
       46.0
      ],
      [
       41.6,
       53.1
      ]
     ],
     "visible": false
    },
    {
     "tail": [
      [
       35.4,
       56.4
      ],
      [
       28.5,
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
     "h": 9.2,
     "on": "plate",
     "visible": true,
     "w": 31.5,
     "x": 80.3,
     "y": 89.3
    },
    {
     "angle": 14.6,
     "h": 16.0,
     "on": "door",
     "visible": true,
     "w": 11.5,
     "x": 71.8,
     "y": 72.1
    },
    {
     "angle": 0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 16.2,
     "x": 96.3,
     "y": 74.0
    },
    {
     "angle": -14.6,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 10.8,
     "x": 119.5,
     "y": 69.7
    },
    {
     "angle": 0,
     "h": 14.6,
     "on": "door",
     "visible": false,
     "w": 2.7,
     "x": 64.1,
     "y": 64.5
    },
    {
     "angle": 14.6,
     "h": 15.3,
     "on": "door",
     "visible": true,
     "w": 10.8,
     "x": 61.7,
     "y": 69.7
    },
    {
     "angle": -0.0,
     "h": 13.8,
     "on": "door",
     "visible": true,
     "w": 16.2,
     "x": 79.5,
     "y": 74.0
    },
    {
     "angle": -14.6,
     "h": 16.0,
     "on": "door",
     "visible": true,
     "w": 11.5,
     "x": 108.7,
     "y": 72.1
    }
   ],
   "stall": [
    {
     "angle": -25.6,
     "h": 16.0,
     "on": "door",
     "visible": true,
     "w": 10.1,
     "x": 110.1,
     "y": 67.9
    },
    {
     "angle": -1.8,
     "h": 9.3,
     "on": "plate",
     "visible": true,
     "w": 30.0,
     "x": 86.7,
     "y": 91.5
    },
    {
     "angle": 19.5,
     "h": 15.7,
     "on": "door",
     "visible": true,
     "w": 11.7,
     "x": 74.7,
     "y": 68.9
    },
    {
     "angle": -1.5,
     "h": 12.9,
     "on": "door",
     "visible": true,
     "w": 15.3,
     "x": 98.6,
     "y": 71.0
    },
    {
     "angle": -25.6,
     "h": 15.2,
     "on": "door",
     "visible": true,
     "w": 9.5,
     "x": 119.3,
     "y": 64.0
    },
    {
     "angle": 0,
     "h": 14.8,
     "on": "door",
     "visible": false,
     "w": 2.0,
     "x": 65.9,
     "y": 57.4
    },
    {
     "angle": 19.5,
     "h": 15.0,
     "on": "door",
     "visible": true,
     "w": 11.1,
     "x": 64.2,
     "y": 65.4
    },
    {
     "angle": -1.5,
     "h": 12.9,
     "on": "door",
     "visible": true,
     "w": 15.4,
     "x": 82.6,
     "y": 71.4
    }
   ]
  },
  "rects": "top-left origin, cell px at scale 1.0",
  "yaws": 8
 }
}
