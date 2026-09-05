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

// ------------------------------------------------------------ the palettes
// One pair per sector, in the design's landmark order: the pit, out of town,
// the scrub, the quarry, the lake, the pines, the roller door, the dunes, the
// overpass, the scrapyard, the billboards, the finish. `SOIL` is the ground's
// base and `SCRUB` what the coarse octave lifts it to -- dry grass out of town,
// ochre in the scrub, rock dust in the quarry, needles in the pines, sand in
// the dunes, rust in the scrapyard, and a pale salt flat under the billboards.
// Every one of them is a golden-hour tone: nothing here is grey, because the
// design's shadow is purple and never grey.
var SOIL = [
  [0.2353, 0.0706, 0.1569],
  [0.2824, 0.1255, 0.1725],
  [0.3059, 0.1255, 0.1569],
  [0.2902, 0.1412, 0.2039],
  [0.2275, 0.0863, 0.1882],
  [0.2000, 0.0902, 0.1882],
  [0.2392, 0.1176, 0.1804],
  [0.4196, 0.2275, 0.2039],
  [0.2275, 0.1020, 0.1647],
  [0.2627, 0.1255, 0.1647],
  [0.4824, 0.2902, 0.3059],
  [0.2353, 0.0706, 0.1569]
]
var SCRUB = [
  [0.2902, 0.1020, 0.1882],
  [0.3608, 0.1961, 0.1882],
  [0.4196, 0.2275, 0.1725],
  [0.4000, 0.2235, 0.2902],
  [0.3020, 0.1412, 0.2510],
  [0.1412, 0.0784, 0.1569],
  [0.3255, 0.1804, 0.2353],
  [0.5686, 0.3412, 0.2471],
  [0.2902, 0.1490, 0.2118],
  [0.3882, 0.2000, 0.1647],
  [0.5882, 0.3765, 0.3608],
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
  [0.0, 0.0, 0.0, 0.40],
  [0.0, 0.0, 1.0, 0.58],
  [0.0, 0.0, 0.0, 0.62],
  [0.0, 0.0, 0.0, 0.94],
  [0.0, 0.0, 0.0, 0.30],
  [1.0, 0.0, 0.0, 0.22]
]

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
// next one. Returns [sectorA, sectorB, blend]. The crossfade is the last sixth
// of a sector, so the ground changes at a place a child can see rather than at
// an invisible line.
function sectorMix(s) {
  var p = ((s % CIRCUIT_LENGTH) + CIRCUIT_LENGTH) % CIRCUIT_LENGTH / SECTOR_LENGTH
  var i = Math.floor(p)
  var f = p - i
  var t = (f - 0.84) / 0.16
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
    var wn = blockNoise(x + s * 0.4, s * 0.10, COARSE)
    var wl = 1.0 + wind * (wn - 0.5) * 0.34
    r *= wl; g *= wl; bl *= wl
  }
  return [r, g, bl]
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
