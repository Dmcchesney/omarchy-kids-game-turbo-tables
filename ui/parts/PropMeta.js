.pragma library

// The prop kit's meta, mirrored as a JavaScript literal.
//
// GENERATED from assets/props/props-meta.json -- do not edit META by hand.
// Every prop is one indexed PNG at assets/props/<name>.png. Columns are the
// prop's views in META[name].views order: R and L are the prop standing on
// the right and left verge seen from the road camera (the sun stays on the
// right, so a left-verge prop is a different render, not a mirror); C is a
// centred view for things that span the road or fly over it; a trailing digit
// is the animation frame. Rows are scales 1, 0.5 and 0.25, packed from the
// left at each scale; META[name].rows holds the row's top y at scale 1.
//
// Cells are anchored at META[name].ground, in cell pixels at scale 1: the
// bottom-centre ground point of a standing prop, or null for an effect sprite,
// which is centred. META[name].bounds[view] is the opaque box at scale 1, so
// a small prop's transparent margin (the camera never comes closer than
// about half its stock distance) can be cropped away by a consumer.
//
// The kit is baked at FINE = 4 times the karts' pixels per world unit, so a
// prop drawn at the projection's size upscales by about half as much as a
// kart does near the camera: a step finer, by the maintainer's decision.

var FINE = 4
var PX_PER_UNIT = 192 / 6.26 * FINE

function forProp(name) {
  return META[name] || null
}

// The rectangle of one view at one scale step (0, 1, 2), in sheet pixels.
function cellRect(name, view, step) {
  var m = META[name]
  if (!m) return null
  var i = m.views.indexOf(view)
  if (i < 0) return null
  var div = [1, 2, 4][step]
  var w = Math.floor(m.cell[0] / div), h = Math.floor(m.cell[1] / div)
  return { x: i * w, y: m.rows[step], width: w, height: h }
}

// The scale step whose cell is nearest a requested cell width, by ratio.
function stepFor(name, targetPx) {
  var m = META[name]
  if (!m) return 0
  var best = 0, bestD = Number.POSITIVE_INFINITY
  for (var s = 0; s < 3; s++) {
    var d = Math.abs(Math.log(Math.max(1, targetPx) / (m.cell[0] / [1, 2, 4][s])))
    if (d < bestD) { bestD = d; best = s }
  }
  return best
}

var META = {
 "banner": {
  "bounds": {
   "L0": [
    18,
    40,
    429,
    309
   ],
   "R0": [
    43,
    40,
    454,
    309
   ]
  },
  "cell": [
   472,
   352
  ],
  "effect": false,
  "ground": [
   236.0,
   302.71999999999997
  ],
  "paints": [
   "red"
  ],
  "rows": [
   0,
   352,
   528
  ],
  "sheet": [
   944,
   616
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   3.2,
   2.2
  ]
 },
 "billboard": {
  "bounds": {
   "L0": [
    21,
    29,
    530,
    413
   ],
   "R0": [
    62,
    29,
    571,
    413
   ]
  },
  "cell": [
   592,
   472
  ],
  "effect": false,
  "ground": [
   296.0,
   405.92
  ],
  "paints": [],
  "rows": [
   0,
   472,
   708
  ],
  "sheet": [
   1184,
   826
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   3.8,
   3.0
  ]
 },
 "bridge": {
  "bounds": {
   "C0": [
    91,
    38,
    1346,
    693
   ]
  },
  "cell": [
   1408,
   792
  ],
  "effect": false,
  "ground": [
   704.0,
   681.12
  ],
  "paints": [],
  "rows": [
   0,
   792,
   1188
  ],
  "sheet": [
   1408,
   1386
  ],
  "views": [
   "C0"
  ],
  "world": [
   9.8,
   5.170000076293945
  ]
 },
 "cone": {
  "bounds": {
   "L0": [
    145,
    28,
    269,
    140
   ],
   "R0": [
    153,
    28,
    277,
    140
   ]
  },
  "cell": [
   422,
   152
  ],
  "effect": false,
  "ground": [
   211.0,
   130.72
  ],
  "paints": [
   "orange",
   "white"
  ],
  "rows": [
   0,
   152,
   228
  ],
  "sheet": [
   844,
   266
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   0.7,
   0.9
  ]
 },
 "crowd": {
  "bounds": {
   "L0": [
    53,
    58,
    594,
    292
   ],
   "L1": [
    53,
    64,
    595,
    292
   ],
   "L2": [
    53,
    56,
    595,
    292
   ],
   "L3": [
    53,
    48,
    594,
    292
   ],
   "R0": [
    40,
    58,
    579,
    292
   ],
   "R1": [
    42,
    64,
    579,
    292
   ],
   "R2": [
    41,
    56,
    579,
    292
   ],
   "R3": [
    40,
    48,
    579,
    292
   ]
  },
  "cell": [
   632,
   336
  ],
  "effect": false,
  "ground": [
   316.0,
   288.96
  ],
  "paints": [
   "red",
   "purple"
  ],
  "rows": [
   0,
   336,
   504
  ],
  "sheet": [
   5056,
   588
  ],
  "views": [
   "R0",
   "R1",
   "R2",
   "R3",
   "L0",
   "L1",
   "L2",
   "L3"
  ],
  "world": [
   4.2,
   2.1
  ]
 },
 "distanceBoard": {
  "bounds": {
   "L0": [
    113,
    28,
    275,
    266
   ],
   "L1": [
    113,
    28,
    275,
    266
   ],
   "R0": [
    147,
    28,
    309,
    266
   ],
   "R1": [
    147,
    28,
    309,
    266
   ]
  },
  "cell": [
   422,
   304
  ],
  "effect": false,
  "ground": [
   211.0,
   261.44
  ],
  "paints": [
   "red"
  ],
  "rows": [
   0,
   304,
   456
  ],
  "sheet": [
   1688,
   532
  ],
  "views": [
   "R0",
   "R1",
   "L0",
   "L1"
  ],
  "world": [
   1.3,
   1.9
  ]
 },
 "drum": {
  "bounds": {
   "L0": [
    147,
    39,
    269,
    169
   ],
   "R0": [
    153,
    39,
    275,
    169
   ]
  },
  "cell": [
   422,
   184
  ],
  "effect": false,
  "ground": [
   211.0,
   158.24
  ],
  "paints": [
   "blue"
  ],
  "rows": [
   0,
   184,
   276
  ],
  "sheet": [
   844,
   322
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   0.9,
   1.1
  ]
 },
 "gantry": {
  "bounds": {
   "C0": [
    104,
    50,
    1387,
    700
   ],
   "C1": [
    104,
    43,
    1385,
    700
   ]
  },
  "cell": [
   1464,
   800
  ],
  "effect": false,
  "ground": [
   732.0,
   688.0
  ],
  "paints": [],
  "rows": [
   0,
   800,
   1200
  ],
  "sheet": [
   2928,
   1400
  ],
  "views": [
   "C0",
   "C1"
  ],
  "world": [
   9.8,
   5.235000133514404
  ]
 },
 "hayBale": {
  "bounds": {
   "L0": [
    98,
    39,
    304,
    128
   ],
   "R0": [
    118,
    39,
    324,
    128
   ]
  },
  "cell": [
   422,
   136
  ],
  "effect": false,
  "ground": [
   211.0,
   116.96
  ],
  "paints": [
   "yellow"
  ],
  "rows": [
   0,
   136,
   204
  ],
  "sheet": [
   844,
   238
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   1.35,
   0.75
  ]
 },
 "hubcap": {
  "bounds": {
   "C0": [
    206,
    16,
    216,
    95
   ],
   "C1": [
    177,
    16,
    242,
    95
   ],
   "C2": [
    172,
    16,
    251,
    95
   ]
  },
  "cell": [
   422,
   112
  ],
  "effect": true,
  "ground": null,
  "paints": [],
  "rows": [
   0,
   112,
   168
  ],
  "sheet": [
   1266,
   196
  ],
  "views": [
   "C0",
   "C1",
   "C2"
  ],
  "world": [
   0.7,
   0.7
  ]
 },
 "jetty": {
  "bounds": {
   "L0": [
    183,
    31,
    549,
    184
   ],
   "R0": [
    59,
    31,
    425,
    184
   ]
  },
  "cell": [
   608,
   200
  ],
  "effect": false,
  "ground": [
   304.0,
   172.0
  ],
  "paints": [],
  "rows": [
   0,
   200,
   300
  ],
  "sheet": [
   1216,
   350
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   1.8,
   1.2
  ]
 },
 "markerPost": {
  "bounds": {
   "L0": [
    182,
    41,
    228,
    189
   ],
   "R0": [
    194,
    41,
    240,
    189
   ]
  },
  "cell": [
   422,
   216
  ],
  "effect": false,
  "ground": [
   211.0,
   185.76
  ],
  "paints": [
   "red",
   "white"
  ],
  "rows": [
   0,
   216,
   324
  ],
  "sheet": [
   844,
   378
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   0.3,
   1.3
  ]
 },
 "oilSlick": {
  "bounds": {
   "C0": [
    54,
    37,
    387,
    70
   ]
  },
  "cell": [
   424,
   72
  ],
  "effect": true,
  "ground": null,
  "paints": [],
  "rows": [
   0,
   72,
   108
  ],
  "sheet": [
   424,
   126
  ],
  "views": [
   "C0"
  ],
  "world": [
   2.2,
   0.3
  ]
 },
 "overpass": {
  "bounds": {
   "C0": [
    46,
    48,
    1354,
    657
   ]
  },
  "cell": [
   1400,
   736
  ],
  "effect": false,
  "ground": [
   700.0,
   632.96
  ],
  "paints": [],
  "rows": [
   0,
   736,
   1104
  ],
  "sheet": [
   1400,
   1288
  ],
  "views": [
   "C0"
  ],
  "world": [
   9.8,
   4.8
  ]
 },
 "pileUp": {
  "bounds": {
   "C0": [
    27,
    76,
    538,
    273
   ]
  },
  "cell": [
   624,
   288
  ],
  "effect": true,
  "ground": null,
  "paints": [
   "red",
   "white",
   "orange"
  ],
  "rows": [
   0,
   288,
   432
  ],
  "sheet": [
   624,
   504
  ],
  "views": [
   "C0"
  ],
  "world": [
   3.0,
   1.6
  ]
 },
 "pine": {
  "bounds": {
   "L0": [
    118,
    197,
    350,
    779
   ],
   "L1": [
    139,
    70,
    335,
    779
   ],
   "R0": [
    154,
    197,
    386,
    779
   ],
   "R1": [
    169,
    70,
    365,
    779
   ]
  },
  "cell": [
   504,
   896
  ],
  "effect": false,
  "ground": [
   252.0,
   770.56
  ],
  "paints": [],
  "rows": [
   0,
   896,
   1344
  ],
  "sheet": [
   2016,
   1568
  ],
  "views": [
   "R0",
   "R1",
   "L0",
   "L1"
  ],
  "world": [
   1.8,
   5.28125
  ]
 },
 "pitBoard": {
  "bounds": {
   "L0": [
    51,
    36,
    332,
    283
   ],
   "R0": [
    90,
    36,
    371,
    283
   ]
  },
  "cell": [
   422,
   320
  ],
  "effect": false,
  "ground": [
   211.0,
   275.2
  ],
  "paints": [],
  "rows": [
   0,
   320,
   480
  ],
  "sheet": [
   844,
   560
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   2.0,
   2.0
  ]
 },
 "pothole": {
  "bounds": {
   "C0": [
    70,
    37,
    343,
    86
   ]
  },
  "cell": [
   424,
   88
  ],
  "effect": true,
  "ground": null,
  "paints": [],
  "rows": [
   0,
   88,
   132
  ],
  "sheet": [
   424,
   154
  ],
  "views": [
   "C0"
  ],
  "world": [
   1.8,
   0.3
  ]
 },
 "rockWall": {
  "bounds": {
   "L0": [
    176,
    99,
    1210,
    556
   ],
   "R0": [
    181,
    99,
    1191,
    556
   ]
  },
  "cell": [
   1336,
   592
  ],
  "effect": false,
  "ground": [
   668.0,
   509.12
  ],
  "paints": [],
  "rows": [
   0,
   592,
   888
  ],
  "sheet": [
   2672,
   1036
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   6.5,
   3.8
  ]
 },
 "rollerDoor": {
  "bounds": {
   "C0": [
    56,
    52,
    1432,
    761
   ],
   "C1": [
    56,
    52,
    1432,
    761
   ]
  },
  "cell": [
   1488,
   856
  ],
  "effect": false,
  "ground": [
   744.0,
   736.16
  ],
  "paints": [],
  "rows": [
   0,
   856,
   1284
  ],
  "sheet": [
   2976,
   1498
  ],
  "views": [
   "C0",
   "C1"
  ],
  "world": [
   9.8,
   5.6
  ]
 },
 "scrapyard": {
  "bounds": {
   "L0": [
    68,
    146,
    606,
    382
   ],
   "R0": [
    136,
    146,
    660,
    382
   ]
  },
  "cell": [
   752,
   408
  ],
  "effect": false,
  "ground": [
   376.0,
   350.88
  ],
  "paints": [
   "red",
   "blue",
   "orange"
  ],
  "rows": [
   0,
   408,
   612
  ],
  "sheet": [
   1504,
   714
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   3.6,
   2.6
  ]
 },
 "tireWall": {
  "bounds": {
   "L0": [
    10,
    192,
    342,
    421
   ],
   "R0": [
    90,
    192,
    422,
    421
   ]
  },
  "cell": [
   432,
   424
  ],
  "effect": false,
  "ground": [
   216.0,
   364.64
  ],
  "paints": [
   "red",
   "white"
  ],
  "rows": [
   0,
   424,
   636
  ],
  "sheet": [
   864,
   742
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   3.0,
   1.3454515933990479
  ]
 },
 "towHook": {
  "bounds": {
   "C0": [
    171,
    13,
    251,
    121
   ],
   "C1": [
    171,
    13,
    251,
    121
   ]
  },
  "cell": [
   422,
   136
  ],
  "effect": true,
  "ground": null,
  "paints": [],
  "rows": [
   0,
   136,
   204
  ],
  "sheet": [
   844,
   238
  ],
  "views": [
   "C0",
   "C1"
  ],
  "world": [
   0.9,
   0.9
  ]
 },
 "waterTower": {
  "bounds": {
   "L0": [
    437,
    556,
    829,
    1448
   ],
   "R0": [
    467,
    556,
    860,
    1448
   ]
  },
  "cell": [
   1296,
   1640
  ],
  "effect": false,
  "ground": [
   648.0,
   1410.4
  ],
  "paints": [],
  "rows": [
   0,
   1640,
   2460
  ],
  "sheet": [
   2592,
   2870
  ],
  "views": [
   "R0",
   "L0"
  ],
  "world": [
   2.8,
   6.799999713897705
  ]
 },
 "wrench": {
  "bounds": {
   "C0": [
    186,
    17,
    236,
    201
   ],
   "C1": [
    131,
    28,
    293,
    191
   ],
   "C2": [
    119,
    85,
    303,
    136
   ],
   "C3": [
    129,
    28,
    291,
    191
   ]
  },
  "cell": [
   422,
   216
  ],
  "effect": true,
  "ground": null,
  "paints": [
   "white"
  ],
  "rows": [
   0,
   216,
   324
  ],
  "sheet": [
   1688,
   378
  ],
  "views": [
   "C0",
   "C1",
   "C2",
   "C3"
  ],
  "world": [
   1.4,
   1.440000057220459
  ]
 }
}
