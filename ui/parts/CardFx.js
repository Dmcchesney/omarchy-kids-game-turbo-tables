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
//
// ---------------------------------------------------------- THE LOUDNESS LADDER
//
// ROUND 3. `flashPeak`, `flashMs`, `flashTone` and `impactShake` are the two
// terms of the design's fourth tool -- "World flash and shake: one frame of
// colour over the road layer, a 200 ms shake with decay" -- given a number per
// card, in ONE place, because the thing a blind critic measured off round two's
// strips was that they had no order:
//
//     world change at impact, mean frame-to-frame difference over the road band
//     nitro 23.1 · turbo 34.7 · PILE-UP 13.4
//
// The legendary was quieter than the common. A child covering the HUD with a
// hand could not tell a four-question skip from a ten-question launch.
//
// So the two numbers below are ordered by WHAT THE CARD COSTS THE VICTIM, which
// is the only ordering a child can be expected to learn:
//
//     pileUp   15   the loudest thing in the game
//     turbo    10   a launch
//     oilSlick  9   three rivals at +3 each
//     pothole   8
//     towHook   8   a whole place, which is what a Pothole costs
//     wrench    5
//     nitro     4   a skip, and deliberately the quietest card that does
//                   anything at all
//     rollCage  0   costs nobody anything, and spends its noise on the BLOCK
//
// `tst_cardfx.qml`'s `test_08` asserts that order against `Engine.CARDS`, so
// the ladder cannot drift from the rules it is a picture of.
//
// AMPLITUDE AND THE FACT ARE NOT IN TENSION, and that is what makes this
// possible. `ui/Race.qml`'s `factGround` puts a dark plate behind the fact for
// exactly as long as a wash is up, at three times the wash's own alpha -- so
// the flash is painted UNDER a plate that gets more opaque as the flash gets
// brighter, and the fact measures MORE legible inside a loud flash than outside
// it. Round two proved that at 0.15; the plate does not care whether the number
// under it is 0.15 or 0.55. The seatbelt is what buys the amplitude.
//
// ---------------------------------------------- ROUND 5: EIGHT GESTURES
//
// A blind critic looked at four rounds of strips and reduced the whole piece to
// one sentence:
//
//     "Seven of eight cards resolve at impact to the same gesture -- tint the
//      whole framebuffer, different hue. The props do all the distinguishing
//      work."
//
// That is exactly what `flashPeak` above was: ONE tool, spent identically by
// every card, differing only in `flashTone`. The grammar table in design v4
// lists five tools and says they are "used in every card in DIFFERENT MIXES",
// and the per-card spec does not describe eight tints -- it describes eight
// different things happening.
//
// So the flash now has a SHAPE as well as a height, and the shape is a
// statement about where the light came from:
//
//   "full"   the whole frame. The child's own engine (Turbo's "one white
//            frame") and the legendary, whose light is already split over and
//            under the wreck. Two cards, and both are written that way in the
//            design.
//   "point"  a round light centred on the kart the event happened to, mostly
//            painted UNDER the sprites so the victim is a silhouette in it and
//            not a ghost inside it. The Wrench's clang, the Pothole's thud and
//            the Roll Cage's block.
//   "road"   the tarmac only, from the horizon down, near end strongest. The
//            Oil Slick, whose whole idea is that the ROAD changed -- and the
//            one card whose light goes DOWN rather than up.
//   "line"   the tow line itself goes white-hot and thick along its length,
//            with a flare at each end. Nothing else in the picture changes.
//   "none"   no light anywhere. The Roll Cage, which has never had one, and
//            the Nitro, which is motion: throw, speed lines, sun bloom,
//            exhaust flare, four lamps chasing.
//
// `pointGain` is why a point light may be brighter than the card's full-frame
// number: a disc of 0.24 of the frame height covers about a sixth of the
// screen, so the same alpha is a sixth of the light. `pointSpan` is the disc's
// radius as a multiple of the victim's own drawn sprite, and `pointFloor` is
// its floor as a fraction of the frame height -- see `fxMarkSize`, and see the
// distant victim in the round-5 report, which is the case that floor exists
// for.
//
// WHAT DOES BOUND THESE IS THE RATE, NOT THE HEIGHT. The design's accessibility
// rule is "nothing flashes faster than 3 Hz". Every card below flashes ONCE at
// its impact; only the Pile-Up flashes in its telegraph as well, and that pair
// is a hue shift with no luminance rise (see `fxSkyFlash`), spaced 340 ms peak
// to peak. `tst_trackview_fx.qml`'s `test_03c` counts the crossings over the
// whole of all eight cards and holds the piece to one loud flash per second.
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
    // The quietest card that does anything. A skip of four questions is a
    // nudge, and it has to stay a nudge or the ten-question launch above it has
    // nowhere to go: round two measured Turbo at only 1.5x Nitro on the road.
    throwForward: 0.34,
    flashTone: "#9fd8ff",
    flashPeak: 0.13,
    flashMs: 180,
    impactShake: 0.10,
    // ROUND 5: MOTION, NOT LIGHT, and that is the work order's own phrase for
    // this card. A Nitro used to tint the whole frame pale blue for 180 ms.
    // What it is instead is everything else it already does: the road throws
    // forward, sixteen speed lines come in from the corners, the sun blooms,
    // the exhaust flares blue-white off the child's own kart, and four lamps
    // chase left to right with a tick each. Cover the colour and a Nitro is a
    // frame full of lines pointing at the horizon. It is the quietest card in
    // the deck and the one that spends nothing at all on the framebuffer.
    //
    // `flashPeak` above is what the loudness ladder orders the deck by and it
    // is unchanged; `flashShape: "none"` is where that light is spent, which is
    // nowhere. `tst_cardfx`'s test_08 still reads the ladder.
    flashShape: "none",
    // ... EXCEPT WITH REDUCED MOTION ON, WHERE THE MOTION IS THE THING THAT IS
    // GONE. The design's substitution rule is that the setting "replaces
    // hit-stop, shake, and spins with FLASHES and tag changes", and a Nitro
    // whose entire gesture is motion has nothing left once the throw, the speed
    // lines, the bloom and the exhaust flare are all removed: `test_05c` walked
    // the deck with the setting on and found this card drawing nothing at all.
    // So with the setting on it gets back exactly what that sentence promises --
    // a light, on the child's own kart, small and still.
    reducedShape: "point",
    pointGain: 2.4,
    pointSpan: 1.2,
    pointFloor: 0.14,
    flashOver: 0.72,
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
    // the horizon dips. ROUND 2: 0.030 of the frame height is 32 px at 1080p
    // and a blind critic looking at the strips found "no camera work of any
    // kind". 0.055 is 59 px, which is a dip you can see happen.
    horizonDip: 0.055,
    tone: "#f2e6c4",
    // "one white frame". ROUND 3: 0.15 was the number round two turned this
    // down to in order to stop the flash veiling the fact, and it worked --
    // and then a blind critic measured the card and found that "nothing in B
    // hits hard". The plate behind the fact is what fixed the veiling; the
    // brightness never had to come down with it. One white frame at 0.55 for
    // 120 ms, once, is the loudest single frame the piece draws for the child's
    // own boost, and it is still under the Pile-Up's.
    //
    // MEASURED, on the round-3 strips: whole-frame mean luma 72.0 -> 127.1 at
    // 0.40, a 1.77x wash, against round one's 2.2x (which a blind critic called
    // the one thing in either build that "genuinely bangs") and round two's
    // 1.27x (which the same critic called "nothing in B hits hard").
    //
    // WHY IT IS 0.40 AND NOT MORE. White beats amber per unit of alpha on every
    // pixel-difference measure there is -- over this road a unit of white moves
    // nearly twice the pixel a unit of amber does -- so a Turbo free to use as
    // much white as it liked would always out-measure a legendary that has to
    // be its own colour. The ladder outranks the card: this is the number that
    // gave way so that the Pile-Up is the loudest thing in the game, and 1.75x
    // is still a bang by the standard the critic set.
    flashTone: "#ffffff",
    flashPeak: 0.40,
    flashMs: 120,
    // ROUND 5. The one card the design writes as a full-frame event in so many
    // words -- "hit-stop 90, ONE WHITE FRAME" -- and the only boost that earns
    // it. What tells a Turbo from a Nitro without colour is the geometry: the
    // focal length bumps, the horizon dips 59 px, the rivals stream past BOTH
    // sides of the frame, and the lap counter turns over.
    flashShape: "full",
    throwForward: 1.0,
    // On top of the 0.45 the lurch itself carries: a launch kicks the camera.
    impactShake: 0.42,
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
    // Three rivals at +3 each. The flash is the slick going down under the
    // whole field, so it is dark rather than bright -- a wash toward the
    // slick's own near-black, which reads as the road going greasy.
    flashTone: "#2b1830",
    flashPeak: 0.30,
    flashMs: 260,
    impactShake: 0.46,
    // ROUND 5. THE ROAD, AND ONLY THE ROAD. This card's idea is that the
    // TARMAC changed under the whole field, so the light goes down on the
    // tarmac and the sky is not touched at all -- the one card in the deck
    // whose world reaction makes the picture DARKER, and the only one below
    // the horizon line. Near end strongest, because the slick came off the
    // back of the child's own kart.
    flashShape: "road",
    // The whole of the flash, on the road band.
    groundBias: 1.0,
    roadNear: true,
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
    // The clang. A wrench is +5 and lands on one kart, so it is a hard, short,
    // warm hit rather than a wash: bright for 140 ms and a real kick, because
    // round two's Wrench measured below the road's own scroll and a child could
    // not feel their own bread-and-butter attack land.
    flashTone: "#ffd489",
    flashPeak: 0.26,
    flashMs: 140,
    impactShake: 0.34,
    // ROUND 5. A wrench is a thing that flies, arcs and STRIKES, and the light
    // of a strike is at the point of the strike. A round light on the victim,
    // mostly under the sprites, so the kart is a hard silhouette standing in
    // its own flare instead of a ghost inside a screen-wide tan wash.
    flashShape: "point",
    // 0.26 x 2.3 = 0.60 at the centre of a disc about two karts across. A wash
    // of 0.26 over two million pixels becomes a light of 0.60 over four hundred
    // thousand, and the second one is a thing that happened to a kart rather
    // than a thing that happened to the screen.
    pointGain: 2.3,
    pointSpan: 1.90,
    pointFloor: 0.21,
    flashOver: 0.30,
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
    // +8 costs more than the wrench's +5, so the thud is bigger than the clang
    // by the same margin the rules charge.
    flashTone: "#e7c489",
    flashPeak: 0.32,
    flashMs: 180,
    impactShake: 0.38,
    // ROUND 5. The light is in the HOLE -- low, on the road, at the kart that
    // fell into it -- and the camera drops with the kart rather than shaking
    // sideways. See `dropPx`.
    flashShape: "point",
    pointGain: 2.2,
    pointSpan: 1.80,
    pointFloor: 0.20,
    flashOver: 0.26,
    // ROUND 5: THE CAMERA FALLS IN TOO. Every other card shakes; this one
    // drops. A downward kick of 1.8% of the frame that recovers in two
    // bounces, so the Pothole is the one impact in the deck that moves the
    // whole picture in a single direction the eye can name.
    dropPx: 0.018,
    dropMs: 420,
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
    // "The one the whole room should notice", and in round two it was the
    // quietest card in the set. The amber is the card's own -- the flash is a
    // HUE swing into orange rather than a bleach toward white, which is why it
    // can be this big: measured whole-frame mean luma barely moves while every
    // pixel on the road changes colour. The shake is the wall of tyres and
    // barrels landing on the road in front of the child, and it is the biggest
    // camera move in the game.
    // 0.76 against Turbo's 0.40, and the two numbers are NOT comparable as
    // alphas: amber is a hue swing and white is a bleach, and over this road a
    // unit of white moves nearly twice the pixel a unit of amber does. What the
    // two numbers buy, measured off the round-3 strips at the impact frame:
    //
    //     road-band frame-to-frame difference   Pile-Up 94.2   Turbo 70.0
    //     whole-frame mean luma                 80 -> 162      72 -> 127
    //                                           (2.02x)        (1.77x)
    //
    // So the legendary is the louder card on both counts, which is the point,
    // and the brighter of the two -- 2.02x against round one's 2.2x, which is
    // the one thing a blind critic said "genuinely bangs" in either build. It
    // is ONE flash of 130 ms and the rate rule is unchanged.
    // The tone is a HOTTER amber than the card's own `#f5a524`, and that is
    // deliberate: this is the light of the impact, and the light a fire throws
    // is paler than the fire. `#f5a524` stays the colour of the two sky flashes
    // in the telegraph, of the ground light on the tarmac, of the `+15` tag and
    // of the callout, so the card's identity is unchanged -- what changed is
    // the one 130 ms beat where the world is lit BY the crash. Blue rises least
    // of the three channels, which is the test a blind critic applied to round
    // one's Pile-Up and found it failed ("blue rises most -- that is a pale
    // pink-white wash, not the specified amber").
    flashTone: "#ffc65e",
    flashPeak: 0.76,
    // ROUND 4 -- AND THIS IS THE NUMBER THAT ANSWERS "THE WASH ERASES ITS OWN
    // CRASH". Only 0.24 of the flash is painted over the objects standing in
    // it; the rest goes under them, so the ROAD still reaches 0.76 amber and
    // the wreck on it only 0.18. A blind critic measured round three's version
    // at roughly 85% composite over everything and reported the victim kart,
    // the tyre stack, the barrels and both tags as "ghosts inside the gold" for
    // 120 ms. The light is the same size; it now falls ON the crash instead of
    // over it. See `fx.worldFlash` in ui/TrackView.qml for the arithmetic that
    // keeps the composite over the road identical.
    flashOver: 0.24,
    // ROUND 5 leaves the legendary full-frame. It is the one card the design
    // says the whole room should notice, its light is already split so it
    // falls ON the wreck rather than over it, and it has a second helping laid
    // on the tarmac below. It is also, now, the ONLY card besides Turbo that
    // touches the whole frame at all -- which is what makes it the loudest.
    flashShape: "full",
    // THE LIGHT OF THE CRASH ON THE TARMAC. A second helping of the same amber,
    // laid from the horizon down and strongest where the wreck is, because a
    // wall of tyres and barrels landing on a road lights the ROAD -- not the
    // sky, which has already had its two flashes in the telegraph. It is the
    // beat that makes the Pile-Up the biggest thing that happens on the road
    // under any measurement, and it costs the fact nothing at all: it lies
    // entirely below the horizon and the fact lives in the sky, so it is the
    // one piece of amplitude in the piece that never reaches the glyphs.
    groundBias: 0.62,
    // 130, not 300: a crash is a bang and a bang has a fast edge. At 60 ms a
    // frame the 300 ms version rose over five frames and read as a fade, and a
    // strip sampled at 60 ms could not see it happen. 130 puts the whole rise
    // inside ONE frame at any sampling a child's eye or a contact sheet uses.
    flashMs: 130,
    // "hit-stop 120, then 300 at half speed". The design writes the pull-back
    // for being hit, and a legendary landing a wall of tyres on the road twenty
    // metres in front of the child is the nearest thing to it that happens to
    // somebody else: the camera sits back off the horizon and the whole road
    // re-projects. It is the geometry half of the loudest card, and it is what
    // makes the Pile-Up the biggest event on the road under any measurement
    // rather than only under one that likes bright colours.
    pullBack: 0.50,
    impactShake: 0.95,
    // "a smoke column rises" -- and the dust the pile throws up when it lands,
    // which is the beat that fills the road. Five puffs across the road width
    // at the wreck's own depth, sized off the ROAD rather than off the victim's
    // sprite, so a legendary landing on a kart at the vanishing point still
    // throws a wall of dust and not five dots.
    dustPuffs: 5,
    dustMs: 900,
    // Pale, because dust is pale, and because a wall of dust the colour of the
    // road it came off is a wall nobody sees.
    dustTone: "#f0dcc0",
    dustPeak: 0.62,
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
    // The cage going up costs nobody anything, so it is the one card with no
    // flash and no shake at all. What it spends instead is the block, below.
    flashTone: "#f5a524",
    flashPeak: 0,
    flashMs: 0,
    impactShake: 0,
    // Nothing at all, and that is the card. ROUND 5 leaves it alone: a blind
    // critic named it the best card in the set precisely because it does not
    // reach for a wash.
    flashShape: "none",
    // THE BLOCK. Design, Wrench: "the wrench shatters against the target's Roll
    // Cage with a white flash and a ring, the cage outline cracks and vanishes
    // ... the block is the payoff and must be loud." A blind critic found three
    // grey puffs. These are the numbers that make it the loudest DEFENSIVE beat
    // in the game: a white frame at the Wrench's own weight, a ring that
    // expands off the cage, and the outline cracking over 260 ms.
    blockFlash: 0.50,
    blockFlashMs: 150,
    // ROUND 5. The block's white flash is a POINT as well -- the light comes
    // off the bar the wrench hit, and it is the biggest point light in the
    // game because it is the payoff. `blockFlashFull` is what is left over for
    // the room, which is what a bright event at close range actually does to
    // a picture, and it is a quarter of what round 4 put over the whole frame.
    blockShape: "point",
    blockPointGain: 1.9,
    blockPointSpan: 2.6,
    blockPointFloor: 0.32,
    blockOver: 0.58,
    blockShake: 0.55,
    blockRingMs: 420,
    blockCrackMs: 260,
    // How long the victim's own cage is drawn for: it snaps on with the
    // shatter, holds, and is gone.
    blockCageMs: 620,
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
    // The latch. The whip is the card's real camera move and it is separate, so
    // the flash here is the line going taut and not a second shake.
    flashTone: "#39b3ad",
    flashPeak: 0.28,
    flashMs: 200,
    impactShake: 0.42,
    // ROUND 5. NOTHING TINTS. The line itself goes white-hot and thick along
    // its whole length at the latch, and the two karts trade places through
    // it. In greyscale a Tow Hook is the only frame in the game with a bright
    // taut cable running up the road from the child's kart to a rival's.
    flashShape: "line",
    // How much thicker and brighter the line gets at the latch, as a multiple
    // of its resting two pixels.
    lineGain: 7.0,
    // The flare at each end of it, on the two karts that are trading places.
    pointGain: 1.8,
    pointSpan: 1.30,
    pointFloor: 0.11,
    flashOver: 0.62,
  },
}

// The impact flash and the impact shake for one card, with the fields defaulted
// so a card that never states them is silent rather than undefined. Kept as a
// function so `ui/TrackView.qml` reads the ladder instead of restating it.
function flashOf(card) {
  var b = BEATS[card]
  if (!b || !b.flashPeak)
    return null
  return { tone: b.flashTone ? b.flashTone : b.tone,
           peak: b.flashPeak,
           ms: b.flashMs ? b.flashMs : 180,
           ground: b.groundBias ? b.groundBias : 0,
           // How much of the flash is painted over the world's OBJECTS rather
           // than under them. 1 is a flat tint over everything, which is right
           // for a boost -- the light comes from the child's own engine and
           // there is nowhere in the picture it does not reach -- and is what
           // every card here but the Pile-Up asks for.
           over: b.flashOver === undefined ? 1 : b.flashOver,
           // ROUND 5. THE SHAPE, which is the whole of this round's answer to
           // "seven cards resolve to the same gesture". See the block above the
           // table. A card that states no shape is full-frame, which is what
           // every card was.
           shape: b.flashShape === undefined ? "full" : b.flashShape,
           gain: b.pointGain === undefined ? 1 : b.pointGain,
           span: b.pointSpan === undefined ? 2.2 : b.pointSpan,
           floor: b.pointFloor === undefined ? 0.18 : b.pointFloor,
           lineGain: b.lineGain === undefined ? 1 : b.lineGain,
           roadNear: b.roadNear === true,
           // What this card's light becomes when reduced motion has taken the
           // movement away. Only the Nitro needs one; see its row.
           reducedShape: b.reducedShape === undefined ? "" : b.reducedShape }
}

// The same, for the Roll Cage's block -- which is not a card being played and
// therefore has its own row rather than a `flashPeak`. Kept beside `flashOf` so
// the two events that light the world read their numbers the same way.
function blockFlashOf() {
  var b = BEATS.rollCage
  return { tone: "#ffffff",
           peak: b.blockFlash,
           ms: b.blockFlashMs,
           ground: 0,
           over: b.blockOver === undefined ? 1 : b.blockOver,
           shape: b.blockShape === undefined ? "full" : b.blockShape,
           gain: b.blockPointGain === undefined ? 1 : b.blockPointGain,
           span: b.blockPointSpan === undefined ? 2.2 : b.blockPointSpan,
           floor: b.blockPointFloor === undefined ? 0.18 : b.blockPointFloor,
           lineGain: 1,
           roadNear: false }
}
function shakeOf(card) {
  var b = BEATS[card]
  return (b && b.impactShake) ? b.impactShake : 0
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

// ---------------------------------------------------- THE FLASH CEILING
//
// ROUND 4, AND IT IS THE ONE THING IN THIS PIECE THE SETTING WAS GETTING
// BACKWARDS.
//
// Reduced motion took a third off every flash, which is a MULTIPLIER: the
// quietest card came down to nothing and the loudest kept most of itself. A
// blind critic measured round three's reduced Pile-Up at +77% whole-frame
// against round two's +16% and said what that means plainly -- "the setting
// most likely to be switched on by a photosensitive child is the one keeping
// most of the flash."
//
// So there is a CEILING as well as the multiplier, and the ceiling is what
// binds on the cards that matter:
//
//     reduced peak = min(peak * 0.66, FLASH_CAP)
//
// 0.085 is chosen against the measurement and not by taste. The washes are
// composited over a scene whose whole-frame mean luma is about 75 and whose
// tones are near 200, so an alpha of a moves the frame by roughly 125a; the
// Pile-Up also lays `groundBias` of the same flash on the tarmac, which is
// a little over half the frame. 0.085 puts the reduced Pile-Up -- the loudest
// event in the game -- at about +16% whole-frame, which is round two's figure
// and the number the round-4 work order named as a reasonable target. Every
// other card is quieter than that already and the multiplier still governs it.
//
// The two amber sky flashes of the Pile-Up's telegraph are capped by the same
// argument, at `SKY_CAP` against a normal `fxSkyPeak` of 0.30. THE COUNT AND
// THE SPACING ARE UNTOUCHED -- they are a recorded maintainer decision in
// docs/open-questions.md section 4 and are not a builder's to change -- and
// with the setting off nothing here applies at all.
//
// WHAT REDUCED MOTION MUST NOT LOSE is the information. The decal, the tags,
// the plates, the callout, the hood smoke, the debris left on the road and the
// place change are all still drawn at full strength, and every one of them is
// still, so a child with the setting on is told exactly what happened without
// the screen doubling in brightness to say it.
var FLASH_CAP = 0.085
var SKY_CAP = 0.10

// ROUND 5, AND THE CAP IS ABOUT AREA, WHICH IS WHY A SHAPED LIGHT GETS ITS OWN.
//
// `FLASH_CAP` is 0.085 because a FULL-FRAME wash at alpha a moves the whole
// picture by roughly 125a, and 0.085 is where a reduced-motion Pile-Up lands at
// about +16% whole-frame. That arithmetic is about the whole frame, and it is
// the wrong arithmetic for a light that covers a sixth of it.
//
// A point light is a disc whose radius floors at 0.19 to 0.30 of the frame
// HEIGHT, so at 16:9 the largest of them covers about pi*0.30^2/(16/9) = 16% of
// the screen, and its alpha falls off as the square of the radius, so the mean
// alpha over even that disc is a third of the peak. The road band is below the
// horizon, which is a little over half the frame, and it makes the picture
// DARKER rather than brighter. The line is two pixels wide.
//
// So a shaped light keeps the reduced-motion MULTIPLIER (a third off, as every
// card always had) and is capped at 0.34 rather than 0.085. What that buys is
// measured in the round-5 report: every reduced strip stays inside the +16%
// whole-frame figure the round-4 work order named, and a child with the setting
// on still gets a light at the place the event happened rather than a tag and
// nothing else. The full-frame cards -- Turbo and the Pile-Up, the only two
// left -- are unchanged and still governed by `FLASH_CAP`.
var SHAPED_CAP = 0.34
