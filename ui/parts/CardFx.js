.pragma library

// The per-card beat table from `docs/design.md` v4, "Power-up feel".
//
// PIECE F. That section is the specification for what the screen does when a
// card lands, and it is written as three beats per card -- a telegraph the eye
// can catch BEFORE the impact, a hit-stop and a world reaction AT the impact,
// and an aftermath visible on the target FOR THE EFFECT'S LIFE. Every number
// in it is a millisecond duration, and every one of them is here, transcribed
// once, so that:
//
//   * `ui/TrackView.qml` and `ui/Race.qml` read the same numbers rather than
//     each carrying a copy that can drift from the other and from the design;
//   * a test can assert the table against the design's own words
//     (`tests/qml/tst_cardfx.qml`) instead of asserting that an animation
//     "looks right", which no test can do;
//   * a frame strip's step size can be chosen from the beats rather than
//     guessed at, so a 60 ms strip is guaranteed to land inside every phase.
//
// NOTHING HERE IS A RULE. Not one number below changes a delta, a stall, a
// tier or a schedule; those are `src/engine/cards.ts` and are frozen. This is
// a view of events the engine already emits, and if a duration here disagrees
// with the engine's own `stallMs` the engine wins -- see `stallMsFor` at the
// bottom, which reads the engine rather than restating it.
//
// THE CLOCK IS NOT A WALL CLOCK AND NOT AN ANIMATION. Every effect in this
// piece is a pure function of `now - startedAt` against the numbers below,
// stepped by `TrackView.advance(dtMs)`. There is no NumberAnimation, no
// SequentialAnimation and no Timer anywhere in the effect layer, because a
// frame strip that differs run to run is not evidence: at a given effect-clock
// reading the screen draws exactly the same pixels on every run.

// --------------------------------------------------------------- the table
//
// Per card, in the design's own order:
//
//   telegraph   how long the wind-up runs before the impact lands
//   hitStop     how long the WORLD freezes at the impact (the effect clock
//               does not freeze; the road, the karts and the camera do)
//   impact      how long the impact beat itself runs
//   aftermath   how long the aftermath runs when it is not open-ended.
//               `-1` means "until the effect ends", which the design defines
//               as the end of the victim's current lap and which the engine
//               tells us through `questionsNeededThisLap`; the view reads that
//               rather than counting down a duration of its own.
//
// The remaining fields are the specific things the design names for that card,
// so a reader can check the beat table against the section line by line.
var BEATS = {
  // "Nitro (skip 4)": telegraph 120, hit-stop 60, aftermath 700.
  nitro: {
    telegraph: 120,
    hitStop: 60,
    impact: 320,
    aftermath: 700,
    // the kart squats one pixel, exhaust flares blue-white
    squatPx: 1,
    exhaust: "#9fd8ff",
    // the sun blooms for 300
    bloom: 300,
    // the four next lap lamps light in a chase left to right with a tick each
    lampChase: 4,
    lampChaseMs: 400,
    speedLines: 0.55,
    tone: "#9fd8ff",
  },
  // "Turbo (skip 10)": telegraph 250, hit-stop 90, aftermath 1200.
  turbo: {
    telegraph: 250,
    hitStop: 90,
    // the road stretches: focal length bumps for 400
    impact: 400,
    aftermath: 1200,
    squatPx: 2,
    exhaust: "#ffd489",
    // one white frame at the impact
    whiteFrame: true,
    // the screen edges darken slightly through the telegraph
    edgeDarken: 0.34,
    // ten lap lamps chase in 500
    lampChase: 10,
    lampChaseMs: 500,
    speedLines: 1.0,
    // the horizon dips
    horizonDip: 0.030,
    tone: "#f2e6c4",
  },
  // "Oil Slick (everyone else +3)": telegraph 200, the decal grows for 400,
  // each rival fishtails for 800, three squeals staggered by 120.
  oilSlick: {
    telegraph: 200,
    hitStop: 0,
    impact: 400,
    aftermath: -1,
    decalGrow: 400,
    fishtail: 800,
    stagger: 120,
    tone: "#3a2740",
  },
  // "Wrench (one rival +5)": telegraph 500 (the projectile's flight), hit-stop
  // 80, smoke from the target's hood until the effect ends.
  wrench: {
    telegraph: 500,
    hitStop: 80,
    impact: 260,
    aftermath: -1,
    // four frames of a quarter turn, three turns over the flight
    spins: 3,
    // the jolt sideways one column and back
    joltMs: 220,
    sparks: 14,
    tone: "#ffd489",
  },
  // "Pothole (one rival +8)": telegraph 350, hit-stop 100, the kart bounces
  // twice, a hubcap flies off and rolls to the verge.
  pothole: {
    telegraph: 350,
    hitStop: 100,
    impact: 520,
    aftermath: -1,
    // the two-pixel dip and the two bounces
    dipPx: 2,
    bounces: 2,
    bounceMs: 520,
    // the hubcap's tumble out to the verge
    hubcapMs: 900,
    tone: "#d8a12a",
  },
  // "Pile-Up (one rival +15, legendary)": telegraph 600 with the sky flashing
  // amber twice, hit-stop 120, then 300 at half speed while the kart spins a
  // full turn.
  pileUp: {
    telegraph: 600,
    hitStop: 120,
    // 300 at half speed, then the spin settles
    impact: 300,
    slowMo: 0.5,
    aftermath: -1,
    skyFlashes: 2,
    spinMs: 700,
    // the tag flash every OTHER racer gets, so the field reads the event
    fieldFlash: 400,
    tone: "#f5a524",
  },
  // "Roll Cage (block next)": the frame draws itself over 300, then settles to
  // a soft amber pulse that stays as long as it is active.
  rollCage: {
    telegraph: 0,
    hitStop: 0,
    impact: 300,
    aftermath: -1,
    drawMs: 300,
    // 0.8 Hz, comfortably under the design's 3 Hz cap
    pulseMs: 1250,
    clicks: 4,
    tone: "#f5a524",
  },
  // "Tow Hook (swap with one rival)": telegraph 400 for the line's flight,
  // hit-stop 80 at the latch, impact 700 for the zip past, and the rival's tag
  // reads TOWED for 1.6 s.
  towHook: {
    telegraph: 400,
    hitStop: 80,
    impact: 700,
    aftermath: 1600,
    towedMs: 1600,
    // the camera whip, as a fraction of a full shake
    whip: 0.55,
    tone: "#39b3ad",
  },
}

// "Being hit, from the child's seat": hit-stop 80, a red-amber frame at the
// edges, a 200 ms shake with decay. The stall's own length is the engine's
// (2 s, 3 s for a Wrench) and is read from it, never restated here.
var HIT = {
  hitStop: 80,
  shakeMs: 200,
  edgeMs: 700,
  edgeTone: "#d8a12a",
  edgeHot: "#f7768e",
  // the extra lap lamps arrive with a rattle
  rattleMs: 420,
  tone: "#f7768e",
}

// "The hand and the charge".
var HAND = {
  // the twelve segments burst into three cards that slide up from the bottom
  // right, and POWER-UP READY reads once
  dealMs: 420,
  burstMs: 260,
  // an unused hand breathes gently: 0.4 Hz, an eighth of the 3 Hz cap
  breatheMs: 2600,
  // the chosen card enlarges for 150, then slams down
  enlargeMs: 150,
  slamMs: 160,
  // the other two flip face down and fly off
  flyMs: 260,
}

// The whole life of a card's sequence, telegraph through impact, in ms. Used
// to size a frame strip and to prune an effect that nothing else closes.
function span(card) {
  var b = BEATS[card]
  if (!b) return 0
  return b.telegraph + b.hitStop + b.impact
}

// The longest a card's own drawn state can run before the engine's own
// bookkeeping takes over. An open-ended aftermath (-1) is capped here only so
// a harness injection with no engine behind it still ends.
function drawnSpan(card) {
  var b = BEATS[card]
  if (!b) return 0
  return span(card) + (b.aftermath < 0 ? 2600 : b.aftermath)
}

// 0..1 through a phase, clamped. `t` is milliseconds since the phase began.
function phase(t, ms) {
  if (ms <= 0) return 1
  return Math.max(0, Math.min(1, t / ms))
}

function easeOut(u) { return 1 - Math.pow(1 - Math.max(0, Math.min(1, u)), 3) }
function easeIn(u) { var v = Math.max(0, Math.min(1, u)); return v * v * v }
// A rise and fall over one phase, peaking in the middle. The shape every
// flash, bloom and puff in this piece uses.
function bump(u) {
  var v = Math.max(0, Math.min(1, u))
  return Math.sin(v * Math.PI)
}
// A decaying oscillation: the shake, the rattle, the wheel chatter.
function decay(u, cycles) {
  var v = Math.max(0, Math.min(1, u))
  return Math.sin(v * Math.PI * 2 * cycles) * (1 - v)
}

// WHAT REDUCED MOTION TAKES AWAY, IN ONE PLACE.
//
// Design, Accessibility: "Reduced motion removes all shake, lurch, and streak
// lines"; Motion: it "replaces shakes and lurches with gauge and lamp changes
// and keeps position changes as cuts"; and the power-up section: it "replaces
// hit-stop, shake, and spins with flashes and tag changes".
//
// So with the setting on, none of the following is drawn at all: the hit-stop,
// the shake, the camera whip, the spins, the wobbles, the bounces, the dip,
// the speed lines, the afterimages, the projectile's flight and the debris'
// tumble. What replaces them is on the right-hand side: the flash, the decal,
// the tag and the smoke, all of which are still and all of which say the same
// thing. Every one of the eight cards keeps a readable outcome; the
// reduced-motion frame strips in the evidence are the check on that.
function reducedOut(name) {
  return ["hitStop", "shake", "whip", "spin", "wobble", "bounce", "dip",
          "speedLines", "afterimage", "flight", "tumble", "squat",
          "shimmer", "bloom"].indexOf(name) >= 0
}
