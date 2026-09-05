.pragma library

.import "PropMeta.js" as PropMeta
.import "Terrain.js" as Terrain

// WHERE EVERY ROADSIDE OBJECT ON THE CIRCUIT STANDS.
//
// Design v4, The circuit, "Twelve landmarks, one per table": "Each sector gets
// one authored set piece: a few sprites plus its ground palette. Written so a
// child learns the circuit and knows where they are in the race by sight."
//
// This is that authoring, and it is a TABLE rather than a rule. The version
// before it generated the roadside from `index % 3` against a six-entry filler
// list, which is why the old circuit had a drum in the quarry, a drum at the
// overpass and a drum at the finish and no two sectors that looked like
// different places. Every entry below is written out, so the twelve landmarks
// in the design's own table are twelve things a reader can check against it,
// and a critic asking "what is that object" can trace it to a kit cell by
// grepping one file.
//
// THE KIT IS FROZEN ART AND THIS FILE IS THE PLACING. Nothing here draws
// anything. `kind` is a key of `PropMeta.META`; `side` plus `frame` is a view
// name in that prop's own sheet -- and R and L are DIFFERENT RENDERS, never
// mirrored, because the sun stays on the right. `ui/parts/KitProp.qml` puts the
// cell on the ground at `s`, `x`.
//
//   kind   the prop's name under assets/props/
//   side   "R", "L" or "C" -- the right verge, the left verge, or spanning
//   s      where it stands on the 432-unit loop, world units
//   x      how far off the centreline, world units, signed (right is positive)
//   frame  which animation frame it rests on when it does not animate
//   anim   "still", "crowd" (four-frame wave), "flag" (two-frame flap),
//          "lamp" (two-frame flicker)
//   phase  0..1, the animation's offset. NO TWO CROWDS ARE IN PHASE: the
//          design asks for "a wave of jumps and raised arms rolling along the
//          rail", and a rail of crowds all jumping together is a chorus line.
//   tag    what this object is for, when it is for something: "fact0".."fact2"
//          are the billboards the child's own answers are painted on;
//          "hidden" is the kart in the scrapyard.
//
// The road's edge is at roadHalf + rumbleHalf = 2.20 world units, so nothing
// here is closer to the centreline than about 2.4.

var SECTOR_LENGTH = Terrain.SECTOR_LENGTH
var CIRCUIT_LENGTH = Terrain.CIRCUIT_LENGTH

// The design's own landmark table, for the minimap's sector labels and for a
// report that has to say what each sector is.
var SECTOR_NAMES = [
  "THE PIT", "OUT OF TOWN", "THE SCRUB", "THE QUARRY",
  "THE LAKE", "THE PINES", "THE ROLLER DOOR", "THE DUNES",
  "THE OVERPASS", "THE SCRAPYARD", "THE BILLBOARDS", "THE FINISH"
]

function at(kind, side, s, x, anim, frame, phase, tag) {
  return {
    "kind": kind,
    "side": side,
    "s": s,
    "x": x,
    "anim": anim || "still",
    "frame": frame || 0,
    "phase": phase || 0,
    "tag": tag || "",
    "world": PropMeta.META[kind] ? PropMeta.META[kind].world[0] : 1,
    "spans": side === "C"
  }
}

var PLACEMENTS = [
  // ---------------------------------------------------------- 1  THE PIT
  // "gantry, tyre walls, pit boards, the grid floor, a silhouetted crowd with
  // flags". The grid floor is the shader's; everything else is here. The
  // gantry stands over the start grid the shader paints at s = 2..5.
  at("gantry", "C", 3.5, 0, "flag", 0, 0.00),
  at("crowd", "R", 5, 6.6, "crowd", 0, 0.00),
  at("crowd", "L", 7, -6.6, "crowd", 0, 0.37),
  at("tireWall", "R", 8, 3.7, "still", 0, 0),
  at("tireWall", "L", 8, -3.7, "still", 0, 0),
  at("crowd", "R", 11, 6.6, "crowd", 0, 0.62),
  at("pitBoard", "L", 12, -3.3, "still", 0, 0),
  at("crowd", "L", 14, -6.6, "crowd", 0, 0.19),
  at("tireWall", "R", 16, 3.7, "still", 0, 0),
  at("crowd", "R", 17, 6.6, "crowd", 0, 0.81),
  at("drum", "L", 20, -3.0, "still", 0, 0),
  at("drum", "R", 21, 3.0, "still", 0, 0),
  at("markerPost", "R", 24, 2.6, "still", 0, 0),
  at("markerPost", "L", 24, -2.6, "still", 0, 0),
  at("cone", "R", 28, 2.5, "still", 0, 0),
  at("markerPost", "R", 30, 2.6, "still", 0, 0),
  at("markerPost", "L", 30, -2.6, "still", 0, 0),
  at("distanceBoard", "L", 33, -3.4, "still", 0, 0),

  // -------------------------------------------------- 2  OUT OF TOWN
  // "sponsor-style banners with the game's own marks, hay bales". The banners
  // carry the kit's own baked TURBO mark; nothing is printed on them.
  at("banner", "R", 40, 4.8, "still", 0, 0),
  at("hayBale", "L", 43, -2.9, "still", 0, 0),
  at("hayBale", "L", 45, -2.9, "still", 0, 0),
  at("markerPost", "R", 46, 2.6, "still", 0, 0),
  at("banner", "L", 50, -4.8, "still", 0, 0),
  at("hayBale", "R", 53, 2.9, "still", 0, 0),
  at("hayBale", "R", 55, 2.9, "still", 0, 0),
  at("markerPost", "L", 56, -2.6, "still", 0, 0),
  at("banner", "R", 60, 4.8, "still", 0, 0),
  at("hayBale", "L", 63, -2.9, "still", 0, 0),
  at("markerPost", "R", 64, 2.6, "still", 0, 0),
  at("markerPost", "L", 64, -2.6, "still", 0, 0),
  at("distanceBoard", "R", 68, 3.4, "still", 0, 0),
  at("distanceBoard", "R", 70, 3.4, "still", 1, 0),

  // ------------------------------------------------------ 3  THE SCRUB
  // "scrub silhouettes, distance boards, a lone water tower". The scrub itself
  // is the shader's terrain -- this sector's SCRUB palette is the ochre one --
  // and the tower stands a long way off the road so it is visible for most of
  // the sector before it arrives.
  at("waterTower", "R", 88, 15.0, "still", 0, 0),
  at("markerPost", "L", 76, -2.6, "still", 0, 0),
  at("markerPost", "L", 82, -2.6, "still", 0, 0),
  at("drum", "R", 84, 3.2, "still", 0, 0),
  at("markerPost", "L", 88, -2.6, "still", 0, 0),
  at("hayBale", "L", 94, -3.1, "still", 0, 0),
  at("hayBale", "L", 96, -3.1, "still", 0, 0),
  at("hayBale", "L", 98, -3.1, "still", 0, 0),
  at("markerPost", "R", 100, 2.6, "still", 0, 0),
  at("distanceBoard", "L", 103, -3.4, "still", 0, 0),
  at("distanceBoard", "L", 105, -3.4, "still", 1, 0),

  // ----------------------------------------------------- 4  THE QUARRY
  // "rock walls close on both sides, dust hanging in the light". The walls are
  // R and L, which are different banks in the bake, and they are close: at 5.2
  // units a 6.5-unit wall crowds the frame from both edges, which is the
  // sector's whole idea.
  at("rockWall", "R", 112, 5.4, "still", 0, 0),
  at("rockWall", "L", 114, -5.4, "still", 0, 0),
  at("drum", "R", 118, 3.0, "still", 0, 0),
  at("rockWall", "R", 121, 5.4, "still", 0, 0),
  at("rockWall", "L", 124, -5.4, "still", 0, 0),
  at("tireWall", "L", 127, -3.6, "still", 0, 0),
  at("drum", "L", 130, -3.0, "still", 0, 0),
  at("rockWall", "R", 131, 5.4, "still", 0, 0),
  at("rockWall", "L", 134, -5.4, "still", 0, 0),
  at("cone", "L", 137, -2.5, "still", 0, 0),
  at("distanceBoard", "R", 140, 3.4, "still", 0, 0),

  // ------------------------------------------------------- 5  THE LAKE
  // "water beside the road, the sun reflected, a jetty, birds crossing once".
  // The water and the reflection are the shader's; the jetty runs away from the
  // road over them, and the birds are drawn in QML by TrackView because a baked
  // flock would read as gravel.
  at("markerPost", "L", 148, -2.6, "still", 0, 0),
  at("jetty", "R", 152, 5.6, "still", 0, 0),
  at("markerPost", "L", 154, -2.6, "still", 0, 0),
  at("hayBale", "L", 158, -2.9, "still", 0, 0),
  at("jetty", "R", 162, 6.4, "still", 0, 0),
  at("markerPost", "L", 160, -2.6, "still", 0, 0),
  at("markerPost", "L", 166, -2.6, "still", 0, 0),
  at("cone", "L", 170, -2.5, "still", 0, 0),
  at("markerPost", "L", 172, -2.6, "still", 0, 0),
  at("distanceBoard", "L", 176, -3.4, "still", 0, 0),

  // ------------------------------------------------------ 6  THE PINES
  // "a hillside of silhouetted pines, a wooden bridge". Two silhouettes from
  // one model, frame 1 taller and thinner, at four distances off the road: a
  // hillside is made of the same tree at different sizes, which is exactly what
  // the projection does for free.
  at("pine", "L", 182, -7.5, "still", 0, 0),
  at("pine", "L", 184, -11.0, "still", 1, 0),
  at("pine", "R", 185, 8.0, "still", 1, 0),
  at("pine", "L", 187, -9.0, "still", 0, 0),
  at("pine", "R", 189, 12.5, "still", 0, 0),
  at("pine", "L", 191, -14.0, "still", 1, 0),
  at("pine", "R", 193, 9.5, "still", 0, 0),
  at("bridge", "C", 198, 0, "still", 0, 0),
  at("pine", "L", 202, -8.5, "still", 1, 0),
  at("pine", "R", 204, 10.5, "still", 1, 0),
  at("pine", "L", 206, -12.5, "still", 0, 0),
  at("hayBale", "R", 207, 2.9, "still", 0, 0),
  at("pine", "R", 209, 7.5, "still", 0, 0),
  at("pine", "L", 211, -10.0, "still", 0, 0),
  at("pine", "R", 213, 13.5, "still", 1, 0),

  // ------------------------------------------------ 7  THE ROLLER DOOR
  // "the long garage from the design, roller door open, lamps flickering". The
  // sevens run under it, which the design names by name. Frame 1 of the bake
  // has one lamp out; `anim: "lamp"` is what makes it flicker.
  at("drum", "R", 222, 3.0, "still", 0, 0),
  at("cone", "L", 224, -2.5, "still", 0, 0),
  at("rollerDoor", "C", 230, 0, "lamp", 0, 0.00),
  at("drum", "L", 236, -3.0, "still", 0, 0),
  at("drum", "R", 237, 3.0, "still", 0, 0),
  at("cone", "R", 240, 2.5, "still", 0, 0),
  at("markerPost", "L", 242, -2.6, "still", 0, 0),
  at("tireWall", "L", 246, -3.6, "still", 0, 0),
  at("markerPost", "R", 248, 2.6, "still", 0, 0),

  // ------------------------------------------------------ 8  THE DUNES
  // "sand, wind lines, the road half buried at the edges". All three are the
  // shader's; what stands here is deliberately sparse, because a dune sector
  // with furniture in it is not a dune sector. The posts are the only thing
  // keeping the road's edge legible where the sand takes it.
  at("markerPost", "R", 256, 2.5, "still", 0, 0),
  at("markerPost", "L", 258, -2.5, "still", 0, 0),
  at("cone", "R", 264, 2.4, "still", 0, 0),
  at("markerPost", "R", 268, 2.5, "still", 0, 0),
  at("markerPost", "L", 272, -2.5, "still", 0, 0),
  at("cone", "L", 276, -2.4, "still", 0, 0),
  at("markerPost", "R", 280, 2.5, "still", 0, 0),
  at("distanceBoard", "R", 283, 3.4, "still", 0, 0),
  at("distanceBoard", "R", 285, 3.4, "still", 1, 0),

  // --------------------------------------------------- 9  THE OVERPASS
  // "a bridge over the road, its shadow crossing the tarmac". The shadow is
  // drawn by TrackView, because it is a soft thing and a hard-edged bake of a
  // soft thing reads as gravel.
  at("pine", "R", 292, 9.0, "still", 0, 0),
  at("pine", "L", 295, -8.0, "still", 1, 0),
  at("tireWall", "R", 298, 3.6, "still", 0, 0),
  at("overpass", "C", 302, 0, "still", 0, 0),
  at("tireWall", "R", 306, 3.6, "still", 0, 0),
  at("tireWall", "R", 309, 3.6, "still", 0, 0),
  at("pine", "R", 312, 11.0, "still", 1, 0),
  at("hayBale", "R", 316, 2.9, "still", 0, 0),
  at("hayBale", "R", 318, 2.9, "still", 0, 0),
  at("pine", "L", 320, -10.0, "still", 0, 0),

  // -------------------------------------------------- 10  THE SCRAPYARD
  // "old karts stacked, one of the six bodies hidden in the pile". The stack is
  // the kit's; the hidden kart is a CarSprite TrackView parks behind the R
  // stack at s = 331, which is the design's Secrets line and is announced
  // nowhere.
  at("scrapyard", "R", 331, 6.2, "still", 0, 0, "hidden"),
  at("drum", "L", 334, -3.0, "still", 0, 0),
  at("scrapyard", "L", 340, -6.2, "still", 0, 0),
  at("drum", "R", 343, 3.0, "still", 0, 0),
  at("drum", "R", 344, 3.9, "still", 0, 0),
  at("scrapyard", "R", 350, 6.2, "still", 0, 0),
  at("cone", "L", 354, -2.5, "still", 0, 0),
  at("markerPost", "R", 356, 2.6, "still", 0, 0),
  at("distanceBoard", "L", 358, -3.4, "still", 0, 0),

  // ------------------------------------------------- 11  THE BILLBOARDS
  // "a row of boards that show the last three facts the child got right,
  // painted on". The blank cream board is the kit's `billboard`; the facts are
  // printed onto it by TrackView from the engine's own fact history. This is
  // the design's passion-project idea, and it is decoration that teaches.
  at("markerPost", "L", 364, -2.6, "still", 0, 0),
  at("billboard", "R", 368, 5.6, "still", 0, 0, "fact0"),
  at("markerPost", "L", 372, -2.6, "still", 0, 0),
  at("billboard", "L", 376, -5.6, "still", 0, 0, "fact1"),
  at("markerPost", "R", 380, 2.6, "still", 0, 0),
  at("billboard", "R", 384, 5.6, "still", 0, 0, "fact2"),
  at("markerPost", "L", 388, -2.6, "still", 0, 0),
  at("markerPost", "R", 390, 2.6, "still", 0, 0),
  at("distanceBoard", "R", 393, 3.4, "still", 0, 0),

  // ----------------------------------------------------- 12  THE FINISH
  // "the grid again, the crowd, the finish gantry lit". The last gantry stands
  // twelve units before the line, so a child comes under it and then over the
  // grid, and the crowd on both rails is at its densest here.
  at("tireWall", "R", 400, 3.7, "still", 0, 0),
  at("tireWall", "L", 400, -3.7, "still", 0, 0),
  at("crowd", "L", 404, -6.6, "crowd", 0, 0.11),
  at("crowd", "R", 406, 6.6, "crowd", 0, 0.53),
  at("pitBoard", "R", 409, 3.3, "still", 0, 0),
  at("crowd", "L", 411, -6.6, "crowd", 0, 0.74),
  at("crowd", "R", 413, 6.6, "crowd", 0, 0.28),
  at("tireWall", "L", 416, -3.7, "still", 0, 0),
  at("crowd", "L", 418, -6.6, "crowd", 0, 0.92),
  at("gantry", "C", 420, 0, "flag", 0, 0.50),
  at("crowd", "R", 423, 6.6, "crowd", 0, 0.06),
  at("crowd", "L", 425, -6.6, "crowd", 0, 0.44),
  at("tireWall", "R", 428, 3.7, "still", 0, 0)
]

// Which view name a placement shows at a given world clock, in seconds.
//
//   crowd  four frames at six a second, offset by the placement's own phase,
//          so the rail reads as a wave rolling along it and no two crowds are
//          ever on the same frame;
//   flag   two frames at three a second -- the gantry's flags;
//   lamp   the roller door's failing lamp: mostly lit, with a stutter that is
//          driven by a hash of the second rather than a sine, so it reads as a
//          bad contact instead of a blink. It never changes state faster than
//          about 2.5 Hz, which keeps it under the design's 3 Hz ceiling.
function viewAt(place, clock) {
  if (place.anim === "crowd") {
    var f = Math.floor(clock * 6 + place.phase * 4) % 4
    return place.side + (f < 0 ? f + 4 : f)
  }
  if (place.anim === "flag") {
    var g = Math.floor(clock * 3 + place.phase * 2) % 2
    return place.side + (g < 0 ? g + 2 : g)
  }
  if (place.anim === "lamp") {
    var tick = Math.floor(clock * 2.5)
    var h = Terrain.hashCell(tick, 17)
    return place.side + (h > 0.78 ? 1 : 0)
  }
  return place.side + place.frame
}

// Every kit prop this circuit uses, once each. A report that has to prove "no
// prop is drawn in code" reads this and checks it against `docs/prop-kit.md`.
function kindsUsed() {
  var seen = {}
  var out = []
  for (var i = 0; i < PLACEMENTS.length; i++) {
    var k = PLACEMENTS[i].kind
    if (!seen[k]) {
      seen[k] = true
      out.push(k)
    }
  }
  return out.sort()
}

// How many placements fall in each sector. Used by the test that holds every
// sector to having a landmark rather than being an empty verge.
function countBySector() {
  var counts = []
  for (var i = 0; i < Terrain.SECTOR_COUNT; i++)
    counts.push(0)
  for (var j = 0; j < PLACEMENTS.length; j++)
    counts[Math.floor(PLACEMENTS[j].s / SECTOR_LENGTH) % Terrain.SECTOR_COUNT]++
  return counts
}

// The placements carrying a tag, in order. `fact0`..`fact2` are the three
// billboards; `hidden` is the scrapyard's kart.
function tagged(tag) {
  var out = []
  for (var i = 0; i < PLACEMENTS.length; i++)
    if (PLACEMENTS[i].tag === tag)
      out.push(i)
  return out
}
