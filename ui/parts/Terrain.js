.pragma library

// THE CIRCUIT'S GROUND, WRITTEN ONCE FOR THREE RENDERERS.
//
// `shaders/road.frag` colours the ground per pixel; `ui/CanvasRoad.qml` colours
// it per band on machines with no shader pipeline; `ui/TrackView.qml` places the
// prop kit and tints it by the same haze. Design v4, The circuit: "the ground
// plane becomes terrain, not grid ... a sector uniform picks the palette".
//
// The three used to hold three copies of the palette. They hold one now: this
// file, and a mirror of it inside `road.frag` that `npm run check:terrain`
// compares number by number, so a palette cannot be changed in one renderer and
// not the other. That check is the reason the tables below are written as
// literal float triples rather than as hex strings -- the shader has no hex.
//
// THE NOISE IS AN INTEGER HASH ON A WORLD LATTICE, AND THAT IS DELIBERATE.
//
// The obvious value noise -- `fract(sin(dot(p, k)) * 43758.5)`, bilinearly
// interpolated -- cannot be reproduced by the fallback: `sin` at those
// magnitudes differs between a GPU, llvmpipe and JavaScript's doubles, and a
// smooth gradient cannot be painted by a renderer that fills quads anyway. So
// the noise is `hashCell(floor(worldX / size), floor(worldS / size))`: a 32-bit
// integer hash of a lattice cell, which wraps identically in GLSL's `uint` and
// in JavaScript's `Math.imul`, and which is FLAT ACROSS THE CELL. Two octaves of
// it are two grids of blocks, which is what a pixel-art ground is made of and
// what the fallback can fill exactly. The critic of the piece before this one
// wrote that the effects were "smooth full-resolution gaussians floating over a
// world that resolves into clean 4-pixel blocks -- there is not one dithered
// edge among them". The ground answers that in the same currency.
//
// Distances here are world units down the track (`s`) and across it (`x`), the
// same two the projection in TrackView.qml and road.frag invert to.

// ------------------------------------------------------------- the circuit
var SECTOR_COUNT = 12
var SECTOR_LENGTH = 36.0
var CIRCUIT_LENGTH = SECTOR_COUNT * SECTOR_LENGTH

// Two long straights, one wide left-hand sweep, one tighter right-hander,
// which is the shape the minimap draws. Positive bends the road right.
var SECTOR_CURVE = [0.00, 0.10, -0.45, -1.00, -0.80, -0.20,
                    0.00, 0.55, 1.00, 0.62, 0.15, -0.10]
var SECTOR_HILL = [0.00, 0.30, 0.72, 0.40, 0.00, -0.40,
                   -0.75, -0.35, 0.10, 0.55, 0.25, -0.20]

// What a SECTOR_CURVE entry of 1.0 means in the projection: the road's lateral
// offset at distance z is `CURVE_AMPLITUDE * curveNorm * z^2`. It lives here
// rather than in TrackView because `ui/Minimap.qml` integrates the table into
// the loop it draws, and a heading integrated from the raw table without this
// factor is out by a factor of forty -- which is exactly the defect the first
// cut of that map had: the "loop" wound round several times and normalised into
// a scribble that happened to fit the panel.
var CURVE_AMPLITUDE = 0.0255

// ------------------------------------------------------------ the palettes
// One pair per sector, in the design's landmark order: the pit, out of town,
// the scrub, the quarry, the lake, the pines, the roller door, the dunes, the
// overpass, the scrapyard, the billboards, the finish. `SOIL` is the ground's
// base and `SCRUB` what the coarse octave lifts it to -- dry grass out of town,
// ochre in the scrub, rock dust in the quarry, needles in the pines, a pale
// CONCRETE APRON at the roller door, sand in the dunes, blue GRAVEL under the
// overpass, rust in the scrapyard, and a pale salt flat under the billboards.
//
// The apron and the gravel are round 2's, and they are the answer to "6 and 8 --
// the roller door and the overpass are the same grey-blue slab spanning the
// road". Two of the twelve sectors stood on the same ground within 0.02 of every
// channel; a garage forecourt is swept concrete and a bridge stands on ballast,
// so one is now the second palest ground on the circuit and the other the
// bluest, and the two sectors no longer share a floor as well as a silhouette.
// Every one of them is a golden-hour tone: nothing here is grey, because the
// design's shadow is purple and never grey.
var SOIL = [
  [0.2353, 0.0706, 0.1569],
  [0.2902, 0.1098, 0.1882],
  [0.3216, 0.1255, 0.1882],
  [0.2980, 0.1412, 0.2196],
  [0.2353, 0.0863, 0.2039],
  [0.2000, 0.0902, 0.2039],
  [0.3255, 0.2118, 0.2745],
  [0.5490, 0.3529, 0.2196],
  [0.2196, 0.1098, 0.2196],
  [0.2824, 0.1333, 0.1804],
  [0.5412, 0.2706, 0.3608],
  [0.2353, 0.0706, 0.1569]
]
var SCRUB = [
  [0.2902, 0.1020, 0.1882],
  [0.3922, 0.1882, 0.2431],
  [0.4706, 0.2196, 0.2353],
  [0.4196, 0.2275, 0.3216],
  [0.3216, 0.1412, 0.2667],
  [0.1490, 0.0784, 0.1804],
  [0.4157, 0.2902, 0.3529],
  [0.6588, 0.4706, 0.2745],
  [0.2941, 0.1725, 0.2902],
  [0.4314, 0.2118, 0.2039],
  [0.6549, 0.3529, 0.4235],
  [0.2902, 0.1020, 0.1882]
]

// Per sector: [grid, water, wind, scrubAmount].
//
//   grid    the diagnostic floor grid, which the design keeps ONLY at the pit:
//           "the diagnostic grid kept only at the pit (sectors 1 and 12) where
//           it belongs". Those are laps 1 and 12, sectors 0 and 11 here.
//   water   the lake, on the right of the road, where the sun reflects.
//   wind    the dunes' wind lines, long and diagonal across the sand.
//   scrub   how strongly the coarse octave lifts SOIL toward SCRUB: near zero
//           on the pit's flat floor, high in the scrub and the scrapyard.
var FLAGS = [
  [1.0, 0.0, 0.0, 0.22],
  [0.0, 0.0, 0.0, 0.72],
  [0.0, 0.0, 0.0, 1.00],
  [0.0, 0.0, 0.0, 0.66],
  [0.0, 1.0, 0.0, 0.54],
  [0.0, 0.0, 0.0, 0.88],
  [0.0, 0.0, 0.0, 0.30],
  [0.0, 0.0, 1.0, 0.58],
  [0.0, 0.0, 0.0, 0.74],
  [0.0, 0.0, 0.0, 0.94],
  [0.0, 0.0, 0.0, 0.30],
  [1.0, 0.0, 0.0, 0.22]
]

// -------------------------------------------------------------- the hour
// WHAT THE GROUND DOES AS THE SUN GOES DOWN, AND WHY IT IS A TABLE HERE.
//
// The sky loses half its value between lap 1 and lap 12; before this the ground
// lost seven per cent and the quarry lost nothing at all, so the last lap was a
// night sky over a daylit desert. A critic called it "the most expensive-looking
// mistake in the set", and it was one number missing rather than a hard problem:
// `nightfall` already drove the sky, the haze, the shadows and the lamps, and
// simply was not applied to the floor.
//
// DUSK is what one unit of nightfall multiplies the ground by. It is a TRIPLE
// and not a scalar on purpose: dividing the channels unevenly is what makes
// dusk read as dusk rather than as a dimmer switch. Red and green fall further
// than blue, so a sunlit ochre at H 352 walks toward the design's purple as it
// darkens instead of turning into grey ochre. Measured on the dunes' own soil,
// (0.478, 0.251, 0.282) V 0.478 becomes (0.239, 0.100, 0.175) V 0.239 -- the
// same halving the sky takes, and thirty degrees of hue with it.
//
// The road, the kerbs and the lane markings are NOT this: they are uniforms
// TrackView hands both renderers, and it dims them by less, because the design's
// haze rule already says the road is the thing the eye must be able to follow.
// `shaders/road.frag` mirrors this triple and `npm run check:terrain` compares
// them, exactly as it does the palettes.
var DUSK = [0.50, 0.40, 0.62]

// The multiplier at a given nightfall, 0..1. Both renderers apply it to the
// finished terrain colour, after the two octaves, the ruts and the wind lines
// and before the grid, the water and the haze -- those three carry the hour in
// their own uniforms already.
function duskMul(nightfall) {
  return [1 + (DUSK[0] - 1) * nightfall,
          1 + (DUSK[1] - 1) * nightfall,
          1 + (DUSK[2] - 1) * nightfall]
}

// ------------------------------------------------------------- the lattice
// Block sizes in world units. COARSE is scrub bands and patches; FINE is the
// grit that keeps the bottom of the frame from being a flat wash. FINE is faded
// out with distance (see `fineFade`) because a half-unit block past twenty units
// is under a pixel and would be a moire rather than a texture.
var COARSE = 2.0
var FINE = 0.5
var RUT = 1.0

// A 32-bit integer hash of a lattice cell, 0..1.
//
// Written so that GLSL's `uint` arithmetic and JavaScript's `Math.imul` produce
// THE SAME BITS: every multiply is 32-bit wrapping, every shift is logical, and
// nothing transcendental is involved. This is the one function the shader and
// the fallback have to agree on exactly, and it is the reason the ground of the
// two paths differences to zero away from the polygon edges.
function hashCell(cx, cy) {
  var h = (Math.imul(cx | 0, 374761393) + Math.imul(cy | 0, 668265263)) | 0
  h = Math.imul(h ^ (h >>> 13), 1274126177) | 0
  h = h ^ (h >>> 16)
  return (h >>> 16) / 65536.0
}

// Value noise on a lattice of `size` world units: flat within a cell.
function blockNoise(x, s, size) {
  return hashCell(Math.floor(x / size), Math.floor(s / size))
}

// How much of the fine octave survives at this distance: 1 near the camera,
// gone by twenty-two world units. road.frag's `smoothstep(22.0, 6.0, z)`.
function fineFade(z) {
  var t = (z - 22.0) / (6.0 - 22.0)
  t = t < 0 ? 0 : (t > 1 ? 1 : t)
  return t * t * (3 - 2 * t)
}

// ------------------------------------------------------------- the sectors
function wrapSector(i) {
  var n = i % SECTOR_COUNT
  return n < 0 ? n + SECTOR_COUNT : n
}

// Which sector world-distance `s` is in, and how far into the crossfade to the
// next one. Returns [sectorA, sectorB, blend]. The crossfade runs over the last
// 38% of a sector -- fourteen world units -- because at a sixth it projected to a
// band a few pixels tall in the middle distance and read as a ruled line across
// the ground rather than as one country becoming another.
function sectorMix(s) {
  var p = ((s % CIRCUIT_LENGTH) + CIRCUIT_LENGTH) % CIRCUIT_LENGTH / SECTOR_LENGTH
  var i = Math.floor(p)
  var f = p - i
  var t = (f - 0.62) / 0.38
  t = t < 0 ? 0 : (t > 1 ? 1 : t)
  return [wrapSector(i), wrapSector(i + 1), t * t * (3 - 2 * t)]
}

// The sector table, sampled and smoothstep-blended at the boundaries: the same
// function `TrackView.sectorBlend` is, and TrackView reads it from here.
function sectorBlend(table, at) {
  var p = at / SECTOR_LENGTH
  var i = Math.floor(p)
  var f = p - i
  var sm = f * f * (3 - 2 * f)
  var a = table[wrapSector(i)]
  var b = table[wrapSector(i + 1)]
  return a + (b - a) * sm
}

// The normalised bend at a point down the track, -1..1. Used for the kerbs,
// which the design puts on the inside of a corner and nowhere else, and for the
// skid marks at a corner's exit.
function curveNormAt(s) { return sectorBlend(SECTOR_CURVE, s) }

// ------------------------------------------------------------- the ground
// The floor's colour at (x, s), before the grid, the road and the haze.
// `z` only chooses how much fine grit survives.
//
// Two octaves, then ruts. The ruts run PARALLEL TO THE ROAD -- their lattice is
// long in `s` and short in `x` -- which is what makes the verge read as a
// surface a car has been driven along rather than as a noise field.
function groundAt(x, s, z) {
  var m = sectorMix(s)
  var a = m[0], b = m[1], t = m[2]
  var soilR = SOIL[a][0] + (SOIL[b][0] - SOIL[a][0]) * t
  var soilG = SOIL[a][1] + (SOIL[b][1] - SOIL[a][1]) * t
  var soilB = SOIL[a][2] + (SOIL[b][2] - SOIL[a][2]) * t
  var scrubR = SCRUB[a][0] + (SCRUB[b][0] - SCRUB[a][0]) * t
  var scrubG = SCRUB[a][1] + (SCRUB[b][1] - SCRUB[a][1]) * t
  var scrubB = SCRUB[a][2] + (SCRUB[b][2] - SCRUB[a][2]) * t
  var amount = FLAGS[a][3] + (FLAGS[b][3] - FLAGS[a][3]) * t

  var coarse = blockNoise(x, s, COARSE)
  var fine = blockNoise(x, s, FINE)
  var ff = fineFade(z)
  // The coarse octave decides scrub or soil; the fine one dithers the boundary,
  // so the two tones interlock in blocks instead of meeting on a smooth ramp.
  var mask = coarse * 0.78 + fine * 0.22 * ff
  mask = mask < 0.42 ? 0 : (mask > 0.72 ? 1 : (mask - 0.42) / 0.30)
  mask *= amount

  var r = soilR + (scrubR - soilR) * mask
  var g = soilG + (scrubG - soilG) * mask
  var bl = soilB + (scrubB - soilB) * mask

  // Ruts: a long, thin lattice, low contrast, and a little of the fine grit.
  var rut = blockNoise(x, s * 0.24, RUT)
  var lift = 0.90 + 0.20 * rut + 0.10 * (fine - 0.5) * ff
  r *= lift; g *= lift; bl *= lift

  // The dunes' wind lines: long ridges running diagonally across the sand.
  // The lattice is sheared in `s` rather than scaled in `x`, so a wind block is
  // still exactly COARSE world units wide and still lands on the same lattice
  // every other octave uses -- which is what lets the fallback fill it exactly.
  var wind = FLAGS[a][2] + (FLAGS[b][2] - FLAGS[a][2]) * t
  if (wind > 0.001) {
    var wn = blockNoise(x + s * 0.65, s * 0.10, COARSE)
    var wl = 1.0 + wind * (wn - 0.5) * 0.52
    r *= wl; g *= wl; bl *= wl
  }
  return [r, g, bl]
}

// ------------------------------------------- THE ROW, FOR THE FALLBACK ONLY
//
// `groundAt` is the honest statement of the ground and it is what road.frag
// evaluates per pixel. `ui/CanvasRoad.qml` evaluates it per BLOCK, in rows, and
// most of what it does is the same for every block in a row: which sector, how
// the two palettes blend, how much scrub the sector carries, how much of the
// fine octave survives at that depth. Calling `groundAt` per cell recomputed
// all of it every time, and measured on this Mac's software scene graph that
// cost 15.7 ms a frame -- the Race screen fell from 62.8 fps to 23.
//
// So a row is set up once and each block is a handful of multiplies after that.
// `rowContext(s, z)` and `rowGround(ctx, x, out)` together compute EXACTLY what
// `groundAt(x, s, z)` computes -- the same lattices, the same order of
// operations -- and `tst_trackview_road` holds them to that, sample by sample,
// so this cannot quietly become a second, cheaper ground.
function rowContext(s, z) {
  var m = sectorMix(s)
  var a = m[0], b = m[1], t = m[2]
  var ff = fineFade(z)
  return {
    "s": s,
    "ff": ff,
    "soil": mix3(SOIL[a], SOIL[b], t),
    "scrub": mix3(SCRUB[a], SCRUB[b], t),
    "amount": FLAGS[a][3] + (FLAGS[b][3] - FLAGS[a][3]) * t,
    "wind": FLAGS[a][2] + (FLAGS[b][2] - FLAGS[a][2]) * t,
    "water": FLAGS[a][1] + (FLAGS[b][1] - FLAGS[a][1]) * t,
    "grid": FLAGS[a][0] + (FLAGS[b][0] - FLAGS[a][0]) * t,
    // The three lattices' `s` cells, which do not change across a row.
    "coarseS": Math.floor(s / COARSE),
    "fineS": Math.floor(s / FINE),
    "rutS": Math.floor(s * 0.24 / RUT),
    "windS": Math.floor(s * 0.10 / COARSE),
    "windShear": s * 0.65
  }
}

// The ground colour at `x` in a row, written into `out` as three 0..1 numbers.
// `out` is the caller's scratch array, so a row of two hundred blocks allocates
// nothing at all.
function rowGround(c, x, out) {
  var coarse = hashCell(Math.floor(x / COARSE), c.coarseS)
  var fine = hashCell(Math.floor(x / FINE), c.fineS)
  var ff = c.ff
  var mask = (coarse * 0.78 + fine * 0.22 * ff - 0.42) / 0.30
  mask = (mask < 0 ? 0 : (mask > 1 ? 1 : mask)) * c.amount
  var soil = c.soil, scrub = c.scrub
  var r = soil[0] + (scrub[0] - soil[0]) * mask
  var g = soil[1] + (scrub[1] - soil[1]) * mask
  var b = soil[2] + (scrub[2] - soil[2]) * mask
  var rut = hashCell(Math.floor(x / RUT), c.rutS)
  var lift = 0.90 + 0.20 * rut + 0.10 * (fine - 0.5) * ff
  r *= lift; g *= lift; b *= lift
  if (c.wind > 0.001) {
    var wn = hashCell(Math.floor((x + c.windShear) / COARSE), c.windS)
    var wl = 1.0 + c.wind * (wn - 0.5) * 0.52
    r *= wl; g *= wl; b *= wl
  }
  out[0] = r; out[1] = g; out[2] = b
  return out
}

// ----------------------------------------------------------------- helpers
function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }
function smooth(edge0, edge1, v) {
  var t = clamp01((v - edge0) / (edge1 - edge0))
  return t * t * (3 - 2 * t)
}
function mix3(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

// --------------------------------------------------- THE SAME, WITHOUT A NEW
//
// `sectorMix`, `mix3` and `rowContext` each build a fresh array or object, and
// `ui/CanvasRoad.qml` calls them once per band on every repaint of the road --
// which, on a scene graph with no shader, is every frame. Measured on the Race
// screen at 480x270 with `qt.qml.gc.allocatorStats`, disabling the repaint
// alone took garbage collections from 184.5 to 81.2 per thousand animation
// ticks: over half of all the allocation pressure in the game is here. Plan v3
// forbids per-frame allocation outright.
//
// These write into a buffer the caller owns and reuses. The ARITHMETIC IS
// COPIED, not re-derived -- same order of operations, same constants -- so a
// band comes out at the same bits it did before, and `tst_trackview_road`
// still holds `rowContext`/`rowGround` to `groundAt` sample by sample.
function sectorMixInto(s, out) {
  var p = ((s % CIRCUIT_LENGTH) + CIRCUIT_LENGTH) % CIRCUIT_LENGTH / SECTOR_LENGTH
  var i = Math.floor(p)
  var f = p - i
  var t = (f - 0.62) / 0.38
  t = t < 0 ? 0 : (t > 1 ? 1 : t)
  out[0] = wrapSector(i)
  out[1] = wrapSector(i + 1)
  out[2] = t * t * (3 - 2 * t)
  return out
}

function mix3Into(a, b, t, out) {
  out[0] = a[0] + (b[0] - a[0]) * t
  out[1] = a[1] + (b[1] - a[1]) * t
  out[2] = a[2] + (b[2] - a[2]) * t
  return out
}

// The buffer `rowContextInto` fills. Its `mix` slot is scratch for the sector
// blend, so a row needs no allocation at all once this exists.
function newRowContext() {
  return {
    "s": 0, "ff": 0, "soil": [0, 0, 0], "scrub": [0, 0, 0], "mix": [0, 0, 0],
    "amount": 0, "wind": 0, "water": 0, "grid": 0,
    "coarseS": 0, "fineS": 0, "rutS": 0, "windS": 0, "windShear": 0
  }
}

function rowContextInto(s, z, c) {
  var m = sectorMixInto(s, c.mix)
  var a = m[0], b = m[1], t = m[2]
  c.s = s
  c.ff = fineFade(z)
  mix3Into(SOIL[a], SOIL[b], t, c.soil)
  mix3Into(SCRUB[a], SCRUB[b], t, c.scrub)
  var fa = FLAGS[a], fb = FLAGS[b]
  c.amount = fa[3] + (fb[3] - fa[3]) * t
  c.wind = fa[2] + (fb[2] - fa[2]) * t
  c.water = fa[1] + (fb[1] - fa[1]) * t
  c.grid = fa[0] + (fb[0] - fa[0]) * t
  c.coarseS = Math.floor(s / COARSE)
  c.fineS = Math.floor(s / FINE)
  c.rutS = Math.floor(s * 0.24 / RUT)
  c.windS = Math.floor(s * 0.10 / COARSE)
  c.windShear = s * 0.65
  return c
}
