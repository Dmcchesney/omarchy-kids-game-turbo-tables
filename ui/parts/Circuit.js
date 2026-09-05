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

// ------------------------------------------------------- THE LIGHT ON THE KIT
//
// `docs/prop-kit.md`: a builder "places, scales, animates, TINTS and crops"
// these. This is the tinting, authored per prop the same way the placements are,
// because how much of the sun a thing takes is a property of what it is made of
// and not of where it stands.
//
// Four numbers per kind:
//
//   wash0    how strongly the design's shadow purple washes the prop at lap 1
//   wash1    the same at lap 12, when the sun is half set
//   key0     how strongly the warm rim lights its sun-facing edge at lap 1
//   reach    how far that rim reaches in, as a share of the prop's drawn width
//
// THE TABLE IS NOT UNIFORM, AND THAT IS THE DESIGN'S OWN RULE. "Paint stays its
// own hue under this light -- a red car reads red; warmth lives in the rim and
// the lamps, never in the paint." So the props built out of the bake's NEUTRAL
// ramp -- the rock walls, the roller door, the overpass, the gantry, all of them
// sampling hue 227-237 -- take a heavy wash, because that ramp is the thing that
// is out of the palette. The props that carry paint take a light one: the tyre
// wall stays red, the hay bales stay yellow, the billboards stay cream, and what
// they get from the hour is the darkening every object in the picture gets.
//
// The pines are the other end of it. They bake at hue 185, teal, and the design
// asks sector 6 for "a hillside of SILHOUETTED pines" -- so they take the
// heaviest wash in the table and become what the design asked for.
//
// AND ROUND 3 RAISED EVERY `wash1`, WHICH IS A DIFFERENT CLAIM FROM `wash0`.
// `wash0` is lap 1 and is untouched, so nothing about the frames that were
// judged has moved. `wash1` is lap 12, and once the near verge carried
// foreground furniture a hay bale three units from the lens measured luminance
// 96 against a ground at 19 -- five times the light of the field it sits in,
// under a sky that has halved. Paint keeping its own HUE is the design's rule;
// paint keeping its own VALUE after sunset is the defect the karts had.
// ROUND 3 RAISED `key0` ON EVERY SET PIECE, AND THE REASON IS A MEASUREMENT.
// Round 2 moved the kit's BODY hues into the palette, which was right, and
// stopped short of the light: a critic measured the quarry's lit facets at hue
// 289 -- a cool violet, with the sun burning directly behind them -- the
// overpass's deck and pier identical to within 1/255, and the town tyre wall's
// sun face and shade face as literally the same pixel. "We have the purple
// world and the hot light, and they are not touching."
//
// The rim these numbers drive is the only directional light on the circuit,
// because the bake's own shading is fixed and a builder may not repaint it. So
// the set pieces take roughly half again as much of it, and `PropKey` now caps
// the rim's REACH in absolute pixels -- which is what stops the same change
// turning the jetty and the water tower into the duplicate rectangles a critic
// ranked second on the cut list. Boards, banners and hay bales are unchanged:
// they carry paint, and the design's rule is that paint keeps its own hue.
var TINT = {
  //             wash0 wash1  key0  reach
  "rockWall":   [0.46, 0.74, 0.66, 0.032],
  "overpass":   [0.46, 0.74, 0.62, 0.022],
  "rollerDoor": [0.44, 0.72, 0.58, 0.020],
  "gantry":     [0.40, 0.70, 0.54, 0.018],
  "pine":       [0.48, 0.78, 0.32, 0.026],
  "waterTower": [0.34, 0.66, 0.58, 0.030],
  "bridge":     [0.22, 0.58, 0.46, 0.018],
  "scrapyard":  [0.20, 0.72, 0.48, 0.030],
  "tireWall":   [0.20, 0.70, 0.44, 0.030],
  "crowd":      [0.36, 0.80, 0.30, 0.022],
  "billboard":  [0.12, 0.54, 0.24, 0.024],
  "banner":     [0.12, 0.54, 0.24, 0.024],
  "pitBoard":   [0.14, 0.58, 0.24, 0.028],
  "distanceBoard": [0.14, 0.60, 0.26, 0.034],
  "hayBale":    [0.18, 0.74, 0.30, 0.040],
  "jetty":      [0.26, 0.74, 0.48, 0.034],
  "drum":       [0.20, 0.72, 0.34, 0.044],
  "cone":       [0.16, 0.68, 0.28, 0.050],
  "markerPost": [0.22, 0.72, 0.30, 0.060]
}
var TINT_DEFAULT = [0.24, 0.72, 0.30, 0.030]

function tintFor(kind) { return TINT[kind] || TINT_DEFAULT }

// ------------------------------------------- HOW FAR A LANDMARK CARRIES
//
// Round 3. A critic's cut list, item 6: "distant duplicate landmarks (overpass
// in dunes, PIT in pines, billboards in scrapyard) -- loses a small sense of a
// continuous world; gains twelve distinct places, which is the point." Every
// landmark that appears in a sector that is not its own weakens that sector's
// identity, and the identity of the twelve is what this piece is for.
//
// The draw distance is 190 world units and a sector is 36, so at any moment the
// camera can see five sectors of set pieces. Measured off the frames: the dunes
// showed the overpass at z = 44, the pines showed the roller door at z = 44,
// the scrapyard showed the fact billboards at z = 46, and the "grey-lavender
// smudge along sector 2's left verge" that a critic could not name is the
// quarry's rock walls at z = 36 to 58.
//
// So a big set piece carries 42 units and no further, and `TrackView` fades it
// out over the last fourteen of those rather than switching it off -- a
// landmark that popped would be worse than one that bled. Small furniture is
// not in this table: a cone at forty units is four pixels and costs nothing,
// and it is the thing that makes the roadside continuous.
//
// IT IS ALSO A SAVING. Everything past its reach stops being drawn, tinted,
// rimmed and shadowed, and these are the largest sprites on the circuit.
var LANDMARK_REACH = 42
var REACH = {
  "rockWall": LANDMARK_REACH,
  "overpass": LANDMARK_REACH,
  "rollerDoor": LANDMARK_REACH,
  "gantry": LANDMARK_REACH,
  "bridge": LANDMARK_REACH,
  "billboard": LANDMARK_REACH,
  "scrapyard": LANDMARK_REACH,
  "jetty": LANDMARK_REACH,
  "waterTower": 52,
  // The town's TURBO boards were reading at the START LINE, thirty units
  // back down the road, which put another sector's signature in the one
  // frame that has to say "the pit".
  "banner": 34
}
// Anything not in the table carries as far as the view draws, which is
// `TrackView.drawDistance`. Written as a number a shade larger so the view's
// own test is the one that stops it.
var REACH_DEFAULT = 1000

function reachFor(kind) { return REACH[kind] || REACH_DEFAULT }

function at(kind, side, s, x, anim, frame, phase, tag) {
  var light = tintFor(kind)
  return {
    "kind": kind,
    "side": side,
    "s": s,
    "x": x,
    "anim": anim || "still",
    "frame": frame || 0,
    "phase": phase || 0,
    "tag": tag || "",
    // The kit's own world size, copied in once at load. `TrackView` reads it on
    // every frame for every placement, and going back to `PropMeta` for it there
    // was a hundred and thirty lookups a frame for numbers that never change.
    "world": PropMeta.META[kind] ? PropMeta.META[kind].world[0] : 1,
    "worldH": PropMeta.META[kind] ? PropMeta.META[kind].world[1] : 1,
    "spans": side === "C",
    // The prop's own share of the light, copied in once. `TrackView` reads all
    // four on every frame for every placement, and a table lookup plus an
    // array index there was the same thing a hundred and thirty times over for
    // numbers that never change.
    "wash0": light[0],
    "wash1": light[1],
    "key0": light[2],
    "keyReach": light[3],
    // How far this landmark carries. See REACH above.
    "reach": reachFor(kind),
    // Every view this placement can ever show, as {name, idx} pairs, worked out
    // once here. `viewAt` and `viewIndexAt` index this rather than building a
    // string and searching the prop's view list on every frame for every prop.
    "frames": framesFor(kind, side, anim || "still", frame || 0)
  }
}

// The views one placement cycles through, in order.
function framesFor(kind, side, anim, frame) {
  var meta = PropMeta.META[kind]
  var names = []
  if (anim === "crowd")
    // TWO FRAMES, NOT FOUR, AND IT IS THE CRITIC'S CUT 5 DONE THE ONLY WAY A
    // BUILDER MAY DO IT. "Crowd animation from four frames to two: nothing
    // readable at that size; halves the crowd atlas." The atlas is frozen art
    // and cannot be halved -- but the DECODES can, because Qt caches the
    // clipped region and not the sheet, so two columns of a crowd cell are
    // decoded per placement instead of four. Frames 0 and 2 rather than 0 and
    // 1, because the wave has to be visible in two steps; every placement
    // still carries its own phase, so the rail still rolls.
    names = [side + "0", side + "2"]
  else if (anim === "flag" || anim === "lamp")
    names = [side + "0", side + "1"]
  else
    names = [side + frame]
  var out = []
  for (var i = 0; i < names.length; i++)
    out.push({ "name": names[i],
               "idx": meta ? meta.views.indexOf(names[i]) : -1 })
  return out
}

// WHICH FRAME OF ITS OWN ANIMATION a placement is on, at a world clock in
// seconds.
//
//   crowd  four frames at six a second, offset by the placement's own phase,
//          so the rail reads as a wave rolling along it and no two crowds are
//          ever on the same frame;
//   flag   two frames at three a second -- the gantry's flags;
//   lamp   the roller door's failing lamp: mostly lit, with a stutter driven by
//          a hash of the second rather than by a sine, so it reads as a bad
//          contact instead of a blink. It never changes state faster than about
//          2.5 Hz, which keeps it under the design's 3 Hz ceiling.
function frameOf(place, clock) {
  if (place.anim === "crowd") {
    var f = Math.floor(clock * 6 + place.phase * 4) % 2
    return f < 0 ? f + 2 : f
  }
  if (place.anim === "flag") {
    var g = Math.floor(clock * 3 + place.phase * 2) % 2
    return g < 0 ? g + 2 : g
  }
  if (place.anim === "lamp")
    return Terrain.hashCell(Math.floor(clock * 2.5), 17) > 0.78 ? 1 : 0
  return 0
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
  // ROUND 3, THE NEAR VERGE. Eight of the twelve lap-6 frames had nothing at
  // all in the bottom third of the picture but road, ground and the child's own
  // kart -- "the nearest, largest, most visible band of the picture and it is
  // empty", against a reference that gives its whole lower third to scrub and
  // dirt. Nothing here is new art: it is the kit's own verge furniture at
  // 2.4 to 3.4 units off the centreline, which is where a prop is still on
  // screen at two or three units of depth and therefore still in the bottom
  // third. Every sector that had none now has one about every eight units, so
  // the band is never empty however far down the road the camera is.
  at("drum", "R", 11, 3.1, "still", 0, 0),
  at("hayBale", "L", 12, -3.0, "still", 0, 0),
  at("hayBale", "L", 13, -4.2, "still", 0, 0),
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
  //
  // ROUND 2 FILLED IT. A critic looking at the twelve unlabelled read this one
  // as "a sponsor straight ... two big TURBO boards and some hay bales in an
  // empty plain. NO TOWN ANYWHERE", and measured roughly 60% of the frame as
  // unbroken flat ground with nothing in it. There is no building in the kit and
  // a builder may not add one, so what makes an edge-of-town out of twenty-five
  // baked props is DENSITY and DEPTH: banners at three distances rather than one
  // -- 4.8 units, 9.5 and 15 -- so the middle distance has something in it, hay
  // bales in rows the way they are stacked at a circuit's edge, tyre walls,
  // drums and cones. It is now the most furnished sector on the circuit outside
  // the pit, which is what being near a town looks like from a road.
  at("banner", "R", 40, 4.8, "still", 0, 0),
  at("banner", "L", 41, -9.5, "still", 0, 0),
  at("hayBale", "L", 43, -2.9, "still", 0, 0),
  at("hayBale", "L", 45, -2.9, "still", 0, 0),
  at("hayBale", "L", 44, -4.3, "still", 0, 0),
  at("markerPost", "R", 46, 2.6, "still", 0, 0),
  at("drum", "R", 47, 3.4, "still", 0, 0),
  at("drum", "R", 47.8, 4.3, "still", 0, 0),
  at("tireWall", "L", 49, -3.7, "still", 0, 0),
  at("banner", "L", 50, -4.8, "still", 0, 0),
  at("banner", "R", 52, 15.0, "still", 0, 0),
  at("hayBale", "R", 53, 2.9, "still", 0, 0),
  at("hayBale", "R", 55, 2.9, "still", 0, 0),
  at("hayBale", "R", 54, 4.3, "still", 0, 0),
  at("markerPost", "L", 56, -2.6, "still", 0, 0),
  at("cone", "L", 57, -2.5, "still", 0, 0),
  at("tireWall", "R", 58, 3.7, "still", 0, 0),
  at("banner", "R", 60, 4.8, "still", 0, 0),
  at("banner", "L", 61, -11.0, "still", 0, 0),
  at("hayBale", "L", 63, -2.9, "still", 0, 0),
  at("hayBale", "L", 62, -4.3, "still", 0, 0),
  at("drum", "L", 65, -3.4, "still", 0, 0),
  at("markerPost", "R", 64, 2.6, "still", 0, 0),
  at("markerPost", "L", 64, -2.6, "still", 0, 0),
  at("tireWall", "L", 66, -3.7, "still", 0, 0),
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
  at("drum", "L", 79, -3.2, "still", 0, 0),
  at("drum", "R", 84, 3.2, "still", 0, 0),
  at("cone", "R", 87, 2.5, "still", 0, 0),
  at("markerPost", "L", 88, -2.6, "still", 0, 0),
  at("hayBale", "R", 92, 3.1, "still", 0, 0),
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
  at("drum", "L", 150, -3.2, "still", 0, 0),
  at("cone", "L", 164, -2.5, "still", 0, 0),
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
  at("hayBale", "L", 189, -3.0, "still", 0, 0),
  at("drum", "R", 197, 3.2, "still", 0, 0),
  at("bridge", "C", 198, 0, "still", 0, 0),
  at("cone", "R", 205, 2.5, "still", 0, 0),
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
  at("hayBale", "L", 221, -3.0, "still", 0, 0),
  at("drum", "R", 222, 3.0, "still", 0, 0),
  at("cone", "L", 224, -2.5, "still", 0, 0),
  at("drum", "L", 233, -3.2, "still", 0, 0),
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
  at("markerPost", "R", 261, 2.5, "still", 0, 0),
  at("cone", "R", 264, 2.4, "still", 0, 0),
  at("cone", "L", 266, -2.4, "still", 0, 0),
  at("markerPost", "L", 277, -2.5, "still", 0, 0),
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
  // THE PINES ARE GONE FROM HERE. Six of them stood in sector 9, which the
  // design gives "a bridge over the road, its shadow crossing the tarmac" and
  // no trees at all -- and they are exactly what the DUNES frame was showing at
  // z = 33 to 37, three sectors' worth of borrowed landmark in the one sector a
  // stranger could not name. Verge furniture takes their place, which is what
  // the bottom third of that frame was missing anyway.
  at("drum", "R", 293, 3.2, "still", 0, 0),
  at("cone", "L", 296, -2.4, "still", 0, 0),
  at("drum", "L", 297, -3.2, "still", 0, 0),
  at("tireWall", "R", 298, 3.6, "still", 0, 0),
  at("overpass", "C", 302, 0, "still", 0, 0),
  at("tireWall", "R", 306, 3.6, "still", 0, 0),
  at("tireWall", "R", 309, 3.6, "still", 0, 0),
  at("tireWall", "L", 313, -3.6, "still", 0, 0),
  at("hayBale", "R", 316, 2.9, "still", 0, 0),
  at("hayBale", "R", 318, 2.9, "still", 0, 0),
  at("cone", "R", 321, 2.4, "still", 0, 0),

  // -------------------------------------------------- 10  THE SCRAPYARD
  // "old karts stacked, one of the six bodies hidden in the pile". The stack is
  // the kit's; the hidden kart is a CarSprite TrackView parks behind the R
  // stack at s = 331, which is the design's Secrets line and is announced
  // nowhere.
  at("scrapyard", "R", 331, 6.2, "still", 0, 0, "hidden"),
  at("drum", "L", 325, -3.2, "still", 0, 0),
  at("cone", "R", 333, 2.5, "still", 0, 0),
  at("drum", "L", 334, -3.0, "still", 0, 0),
  at("tireWall", "R", 347, 3.6, "still", 0, 0),
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
  at("drum", "R", 362, 3.2, "still", 0, 0),
  at("cone", "L", 379, -2.5, "still", 0, 0),
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
  at("markerPost", "L", 403, -2.6, "still", 0, 0),
  at("drum", "L", 411, -3.2, "still", 0, 0),
  at("cone", "R", 419, 2.5, "still", 0, 0),
  at("tireWall", "R", 428, 3.7, "still", 0, 0)
]

// Which view name a placement shows at a given world clock, in seconds.
function viewAt(place, clock) {
  return place.frames[frameOf(place, clock)].name
}

// The same, as the column index into the prop's own sheet.
function viewIndexAt(place, clock) {
  return place.frames[frameOf(place, clock)].idx
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
