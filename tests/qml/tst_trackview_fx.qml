import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts"
import "../../ui/parts/CardFx.js" as CardFx
import "../../engine/engine.mjs" as Engine

// PIECE F. The effect layer, checked against the two rules that keep it a kids'
// game and against the beats it claims to draw.
//
// EVERY CASE HERE DRIVES A REAL RACE SCREEN. The screen is built, warmed up so
// there are rivals on the road, and put on an EXTERNAL CLOCK -- the same seam
// `dev/Harness.qml --strip` uses -- so the test steps the effect clock by hand
// and looks at what the screen is drawing at each millisecond it chooses. That
// is the difference between checking a table (tst_cardfx.qml does that) and
// checking the picture's geometry, which is what this file does.
//
// WHAT IT STILL CANNOT DO. It cannot say whether an impact FEELS like an
// impact. Nothing automated can, and the frame strips in the evidence exist for
// exactly that reason. What it can do is the part a strip is bad at: walk every
// effect item on the screen, on every frame of every card's whole sequence, and
// prove that not one of their boxes ever touches the fact or the answer field.
// A contact sheet shows one frame at a time and a reviewer's eye; this walks
// about nine hundred item-frames per card.
Item {
  id: root
  width: 1920
  height: 1080

  Race {
    id: race
    anchors.fill: parent
    mode: "grandPrix"
    preset: "1-12"
    seed: 42
    warmup: 6
    externalClock: true
  }

  // The two boxes nothing may cover, read off the screen rather than restated.
  readonly property rect factBox: race.factInkRect
  readonly property rect fieldBox: Qt.rect(race.trackView.fieldRect.x,
                                           race.trackView.fieldRect.y,
                                           race.trackView.fieldRect.width,
                                           race.trackView.fieldRect.height)

  // A depth-first walk, the same one dev/Harness.qml's --dump-rects makes, so
  // what this test measures and what the evidence prints are the same tree.
  function walk(node, visit) {
    if (!node)
      return
    visit(node)
    var kids = node.children
    if (!kids)
      return
    for (var i = 0; i < kids.length; i++)
      root.walk(kids[i], visit)
  }

  function drawn(item) {
    var node = item
    while (node && node !== root) {
      if (!node.visible || node.opacity <= 0.02)
        return false
      node = node.parent
    }
    return true
  }

  function overlaps(a, b) {
    if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0)
      return false
    return a.x < b.x + b.width && a.x + a.width > b.x
           && a.y < b.y + b.height && a.y + a.height > b.y
  }

  // TWO CLASSES OF EFFECT ITEM, AND ONLY ONE OF THEM IS AN OBJECT.
  //
  // Design v4's grammar table gives the piece five tools, and one of them is
  // "World flash and shake: one frame of colour over the road layer ... speed
  // lines on boosts". Those are LIGHT: a full-frame tint, a frame of darkening
  // at the edges, a radial burst of speed lines from the vanishing point, and
  // the sun's own bloom on a Nitro. None of them is a thing standing in front
  // of the fact -- they cover the whole frame by definition, they are painted
  // by `ui/TrackView.qml`, which `ui/Race.qml` declares BEFORE the fact and the
  // field, so the fact draws over them, and each is bounded in peak alpha.
  //
  // Everything else is an OBJECT: a sprite, a decal, a tag, a spark burst, a
  // puff, the cage, the tow line. An object crossing the fact WOULD cover it,
  // and `TrackView.fxTopFor` is what stops that. The two classes are checked
  // differently below, and the split is named here rather than left implicit,
  // because a test that quietly skipped the items it could not satisfy would be
  // the sort of thing this project has been caught doing before.
  //
  // The speed lines are NOT in this list, and that is the one place the split
  // was argued rather than assumed. They cover the whole frame as a fan but
  // they paint two-to-six-pixel cream strokes, and cream strokes behind cream
  // glyphs is a contrast problem however thin they are -- so each line is an
  // object with its own box, and a line whose box would meet the fact or the
  // field is simply not drawn. There are sixteen and the fan reads the same
  // with two missing.
  readonly property var washNames: ["fx.worldFlash", "fx.edges", "fx.sunBloom"]
  function isWash(name) { return root.washNames.indexOf(name) >= 0 }

  // Every drawn item whose objectName marks it as part of the effect layer,
  // with its box in the screen's own coordinates.
  function effectBoxes() {
    var out = []
    root.walk(race, function (item) {
      var name = String(item.objectName)
      if (name.indexOf("fx.") !== 0 || !root.drawn(item))
        return
      if (item.width <= 0 || item.height <= 0)
        return
      var p = item.mapToItem(root, 0, 0)
      // Three of the four washes paint through their children, so their own
      // `opacity` is 1 and says nothing; each publishes `washAlpha`, which is
      // the strongest alpha it actually puts on a pixel.
      var alpha = (item.washAlpha !== undefined) ? item.washAlpha : item.opacity
      out.push({ "name": name, "opacity": alpha,
                 "box": Qt.rect(p.x, p.y, item.width, item.height) })
    })
    return out
  }

  TestCase {
    name: "TrackViewFx"
    when: windowShown

    property var track: race.trackView

    function init() {
      race.seed = 42
      race.buildRace()
      Sfx.logging = true
      Sfx.clearLog()
    }

    function cleanupTestCase() {
      Sfx.logging = false
    }

    // A short pre-roll so the road is moving, exactly as a strip takes one.
    function preroll() {
      for (var i = 0; i < 20; i++)
        race.stepClock(16)
    }

    // ---------------------------------------------------------------- rule 1
    //
    // NOTHING EVER COVERS THE FACT.
    //
    // Design, Pillars: "The question is the track. The fact is the largest
    // thing on screen at every moment of a race", and design v4's power-up
    // section: "nothing ever covers the fact". Every card is played, its whole
    // sequence is stepped at the strip's own 60 ms, and on every one of those
    // frames every effect item's box is measured against the fact's ink and the
    // answer field's box.
    function test_01_no_effect_item_ever_touches_the_fact_or_the_field_data() {
      return [{ card: "nitro" }, { card: "turbo" }, { card: "oilSlick" },
              { card: "wrench" }, { card: "pothole" }, { card: "pileUp" },
              { card: "rollCage" }, { card: "towHook" }]
    }

    function test_01_no_effect_item_ever_touches_the_fact_or_the_field(data) {
      preroll()
      verify(race.injectEvent("cardUsed", data.card), data.card + " was delivered")
      var frames = Math.ceil(CardFx.drawnSpan(data.card) / 60) + 4
      var seen = 0
      var widest = 0
      for (var f = 0; f < frames; f++) {
        var boxes = root.effectBoxes()
        seen += boxes.length
        for (var i = 0; i < boxes.length; i++) {
          if (root.isWash(boxes[i].name))
            continue
          widest = Math.max(widest, boxes[i].box.width)
          verify(!root.overlaps(boxes[i].box, root.factBox),
                 data.card + " at t=" + (f * 60) + "ms: " + boxes[i].name
                 + " " + JSON.stringify(boxes[i].box)
                 + " is clear of the fact " + JSON.stringify(root.factBox))
          verify(!root.overlaps(boxes[i].box, root.fieldBox),
                 data.card + " at t=" + (f * 60) + "ms: " + boxes[i].name
                 + " " + JSON.stringify(boxes[i].box)
                 + " is clear of the answer field " + JSON.stringify(root.fieldBox))
        }
        race.stepClock(60)
      }
      verify(seen > 0, data.card + " drew at least one effect item at all")
      console.log("FX-CLEAR|" + data.card + "|" + seen + " item-frames|widest "
                  + Math.round(widest) + " px|fact "
                  + Math.round(root.factBox.x) + "," + Math.round(root.factBox.y)
                  + " " + Math.round(root.factBox.width) + "x" + Math.round(root.factBox.height)
                  + "|field " + Math.round(root.fieldBox.x) + "," + Math.round(root.fieldBox.y)
                  + " " + Math.round(root.fieldBox.width) + "x" + Math.round(root.fieldBox.height))
    }

    // And the same for being hit, which is the one sequence whose effects are
    // all on the child's own kart -- the nearest thing on the screen to the
    // field, and therefore the case most likely to reach it.
    function test_02_being_hit_never_touches_the_fact_or_the_field() {
      preroll()
      verify(race.injectEvent("hit", "pothole"), "the hit was delivered")
      var seen = 0
      for (var f = 0; f < 40; f++) {
        var boxes = root.effectBoxes()
        seen += boxes.length
        for (var i = 0; i < boxes.length; i++) {
          if (root.isWash(boxes[i].name))
            continue
          verify(!root.overlaps(boxes[i].box, root.factBox),
                 "hit at t=" + (f * 60) + "ms: " + boxes[i].name + " is clear of the fact")
          verify(!root.overlaps(boxes[i].box, root.fieldBox),
                 "hit at t=" + (f * 60) + "ms: " + boxes[i].name + " is clear of the field")
        }
        race.stepClock(60)
      }
      verify(seen > 0, "being hit drew effect items")
    }

    // ---------------------------------------------------------------- rule 2
    //
    // A WRONG ANSWER IS NEVER PUNISHED WITH MOTION.
    //
    // The design's second pillar is that a mistake costs the streak and nothing
    // else. The effect layer is reachable from `cardUsed`, `hit`, `blocked`,
    // `swap` and `handDealt` and from nothing else, and this is the check that
    // it stays that way: a wrong answer, then a second one that reveals the
    // fact, and the whole effect layer must be exactly as empty afterwards as
    // before -- no hit-stop, no shake, no flash, no cue, no item.
    function test_03_a_wrong_answer_starts_no_effect_at_all() {
      // THE RIVALS ARE FROZEN, and it is the same reason tst_race_keys freezes
      // them: a rival's Wrench landing on the child in the middle of this
      // measurement is a real event with a real shake, and it would be read
      // here as a wrong answer causing motion. The child's own wrong answer is
      // the only thing this case is about, and it is still entirely real.
      race.rivals = null
      preroll()
      var before = root.effectBoxes().length
      compare(before, 0, "nothing is in the air to begin with")
      var expected = String(Engine.factAnswer(race.human.currentFact))
      // A wrong answer of the right length, so the engine submits it.
      var wrong = expected.length === 1 ? "9" : "99"
      if (expected === wrong)
        wrong = expected.length === 1 ? "8" : "88"
      var streakBefore = race.human.streak
      for (var d = 0; d < wrong.length; d++)
        race.send({ "kind": "digit", "value": Number(wrong[d]) })
      race.send({ "kind": "submit" })
      verify(race.human.streak <= streakBefore, "the streak paid for it")

      for (var f = 0; f < 20; f++) {
        compare(root.effectBoxes().length, 0,
                "a wrong answer put nothing in the effect layer at t=" + (f * 60))
        compare(track.worldFrozen, false, "and it never froze the world")
        compare(track.shake, 0, "and it never shook the screen")
        race.stepClock(60)
      }
      compare(Sfx.log.length, 0, "and it played no power-up cue")
    }

    // The other half of "nothing ever covers the fact": the four full-frame
    // washes. Each is bounded in alpha, each is painted before the fact, and
    // the fact is therefore drawn over all of them at full strength.
    function test_03b_the_washes_are_light_and_are_painted_under_the_fact() {
      // The fact's block is declared after the track in ui/Race.qml, and the
      // order of `race.children` IS the paint order, so this is the picture's
      // own answer rather than an assertion about the source.
      var trackAt = -1
      var factAt = -1
      for (var i = 0; i < race.children.length; i++) {
        if (race.children[i] === race.trackView)
          trackAt = i
        if (String(race.children[i].objectName) === "factColumn")
          factAt = i
      }
      verify(trackAt >= 0 && factAt >= 0, "both were found in the screen")
      verify(factAt > trackAt,
             "the fact is painted after the whole effect layer (" + trackAt
             + " then " + factAt + ")")

      // And the alphas, at their peaks, over the whole of every card.
      preroll()
      var cards = ["nitro", "turbo", "oilSlick", "wrench", "pothole", "pileUp",
                   "rollCage", "towHook"]
      var peak = 0
      for (var c = 0; c < cards.length; c++) {
        race.buildRace()
        preroll()
        race.injectEvent("cardUsed", cards[c])
        for (var f = 0; f < 26; f++) {
          var boxes = root.effectBoxes()
          for (var k = 0; k < boxes.length; k++)
            if (root.isWash(boxes[k].name))
              peak = Math.max(peak, boxes[k].opacity)
          race.stepClock(60)
        }
      }
      // Turbo's "one white frame" is the loudest thing in the piece and it is
      // the number this bound is set by. Anything above it would be a wash the
      // fact has to fight rather than sit on.
      verify(peak <= 0.66, "the loudest wash in the piece measured " + peak.toFixed(3))
      console.log("FX-WASH|peak alpha across all eight cards|" + peak.toFixed(3))
    }

    // ------------------------------------------------------------- hit-stop
    //
    // Design v4: "hit-stop | the world freezes for 60 to 120 ms at the moment
    // of impact ... The FrameAnimation delta is held at zero". So `travel` --
    // the one number the whole camera is derived from -- must not move across
    // the freeze, and must move again on the other side of it.
    function test_04_the_impact_freezes_the_world_and_then_lets_it_go() {
      preroll()
      race.injectEvent("cardUsed", "wrench")
      var b = CardFx.BEATS.wrench
      // Up to the impact.
      var stepped = 0
      while (stepped < b.telegraph) {
        race.stepClock(20)
        stepped += 20
      }
      verify(track.worldFrozen, "the impact froze the world")
      var held = track.travel
      race.stepClock(20)
      compare(track.travel, held, "and the road did not move inside the freeze")
      // Out the other side.
      while (track.worldFrozen && stepped < b.telegraph + 400) {
        race.stepClock(20)
        stepped += 20
      }
      verify(!track.worldFrozen, "the freeze let go")
      race.stepClock(20)
      verify(track.travel > held, "and the road is moving again")
    }

    // -------------------------------------------------------- reduced motion
    //
    // Design, Accessibility: "Reduced motion removes all shake, lurch, and
    // streak lines", and design v4: it "replaces hit-stop, shake, and spins
    // with flashes and tag changes". Both halves are checked: what must be
    // gone, and what must still be there -- because a card a child with the
    // setting on cannot see happen at all is not accessible, it is deleted.
    function test_05_reduced_motion_takes_the_movement_and_leaves_the_event() {
      Store.setSetting("reducedMotion", true)
      race.buildRace()
      preroll()
      race.injectEvent("cardUsed", "pileUp")
      var sawItem = false
      var sawFlash = false
      for (var f = 0; f < 26; f++) {
        compare(track.worldFrozen, false, "no hit-stop under reduced motion (t=" + (f * 60) + ")")
        compare(track.shake, 0, "no shake")
        compare(track.lurch, 0, "no lurch")
        compare(track.boostNow, 0, "no speed lines")
        for (var k = 0; k < 4; k++)
          compare(track.fxKartYaw(k), 0, "no spin or wobble on any kart")
        if (root.effectBoxes().length > 0)
          sawItem = true
        if (track.flashNow > 0.01)
          sawFlash = true
        race.stepClock(60)
      }
      verify(sawFlash, "but the flash still happened, which is the substitute")
      verify(sawItem, "and the tag and the decal are still on the screen")
      Store.setSetting("reducedMotion", false)
      race.buildRace()
    }

    // ------------------------------------------------------------- the cues
    //
    // "a sound for every event", checked as ROUTING rather than as sound.
    // NOBODY IN THIS LOOP CAN HEAR: what is asserted is that playing a card
    // asks for the cue the design's Sound row names, on the beat it names it.
    function test_06_every_card_asks_for_its_own_cue_data() {
      return [
        { card: "nitro",    telegraph: "nitro",         impact: "" },
        { card: "turbo",    telegraph: "turbo",         impact: "" },
        { card: "oilSlick", telegraph: "oilslick",      impact: "squeal" },
        { card: "wrench",   telegraph: "wrench-flight", impact: "wrench-clang" },
        { card: "pothole",  telegraph: "",              impact: "pothole" },
        { card: "pileUp",   telegraph: "pileup",        impact: "" },
        { card: "rollCage", telegraph: "",              impact: "rollcage" },
        { card: "towHook",  telegraph: "towhook",       impact: "" }
      ]
    }

    function test_06_every_card_asks_for_its_own_cue(data) {
      preroll()
      Sfx.clearLog()
      race.injectEvent("cardUsed", data.card)
      if (data.telegraph.length > 0)
        compare(Sfx.log.indexOf(data.telegraph) >= 0, true,
                data.card + " opened with the cue " + data.telegraph
                + ", log " + JSON.stringify(Sfx.log))
      for (var f = 0; f < 24; f++)
        race.stepClock(60)
      if (data.impact.length > 0)
        verify(Sfx.log.indexOf(data.impact) >= 0,
               data.card + " reached the cue " + data.impact
               + ", log " + JSON.stringify(Sfx.log))
      for (var i = 0; i < Sfx.log.length; i++)
        verify(Sfx.cues.hasOwnProperty(Sfx.log[i]),
               "the cue " + Sfx.log[i] + " has a file behind it")
      console.log("FX-CUES|" + data.card + "|" + JSON.stringify(Sfx.log))
    }

    function test_07_being_hit_and_a_block_have_their_own_cues() {
      preroll()
      Sfx.clearLog()
      race.injectEvent("hit", "wrench")
      verify(Sfx.log.indexOf("hit") >= 0, "being hit has a cue: " + JSON.stringify(Sfx.log))
      Sfx.clearLog()
      race.injectEvent("blocked", "wrench")
      for (var f = 0; f < 12; f++)
        race.stepClock(60)
      verify(Sfx.log.indexOf("block") >= 0,
             "and the block that pays a Roll Cage back has one: " + JSON.stringify(Sfx.log))
    }

    // Oil Slick's "three squeals staggered by 120": three separate cues, not
    // one, so a child hears three hits.
    function test_08_the_oil_slick_squeals_three_times() {
      preroll()
      Sfx.clearLog()
      race.injectEvent("cardUsed", "oilSlick")
      for (var f = 0; f < 20; f++)
        race.stepClock(60)
      var squeals = 0
      for (var i = 0; i < Sfx.log.length; i++)
        if (Sfx.log[i] === "squeal")
          squeals += 1
      compare(squeals, 3, "one squeal per rival: " + JSON.stringify(Sfx.log))
    }

    // ------------------------------------------------------- the three beats
    //
    // The gate this piece is judged on: a telegraph the eye can catch BEFORE
    // the impact, something AT the impact, and an aftermath ON THE TARGET that
    // lasts. Checked as geometry: an item on the screen during the telegraph,
    // a world reaction at the impact, and the victim still marked afterwards.
    function test_09_a_wrench_has_all_three_beats() {
      preroll()
      var b = CardFx.BEATS.wrench
      race.injectEvent("cardUsed", "wrench")
      // Beat one: the projectile is in the air before anything has landed.
      race.stepClock(120)
      var flying = root.effectBoxes()
      var sawFlyer = false
      for (var i = 0; i < flying.length; i++)
        if (flying[i].name.indexOf("fx.flyer") === 0)
          sawFlyer = true
      verify(sawFlyer, "the wrench is on its way, 120 ms in")
      verify(!track.worldFrozen, "and nothing has landed yet")

      // Beat two: the impact freezes the world and puts sparks on the target.
      while (!track.worldFrozen)
        race.stepClock(20)
      var hitting = root.effectBoxes()
      var sawSparks = false
      var sawTag = false
      for (var k = 0; k < hitting.length; k++) {
        if (hitting[k].name.indexOf("fx.sparks") === 0)
          sawSparks = true
        if (hitting[k].name.indexOf("fx.tag") === 0)
          sawTag = true
      }
      verify(sawSparks || sawTag, "the impact is on the target kart")

      // Beat three: the aftermath is still on the victim a second later.
      for (var f = 0; f < 16; f++)
        race.stepClock(60)
      var smoking = false
      root.walk(race, function (item) {
        if (String(item.objectName) === "fx.hoodSmoke" && root.drawn(item))
          smoking = true
      })
      verify(smoking, "the target's hood is still smoking a second after the hit")
    }

    // The Roll Cage's outline is the whole of that card, so it gets its own
    // case: it draws itself over 300 ms and then stays up.
    function test_10_the_roll_cage_draws_itself_and_stays() {
      preroll()
      race.injectEvent("cardUsed", "rollCage")
      race.stepClock(20)
      verify(track.cageDraw < 1, "the cage is still drawing itself")
      var partial = track.cageDraw
      race.stepClock(160)
      verify(track.cageDraw > partial, "and it is further on")
      race.stepClock(220)
      fuzzyCompare(track.cageDraw, 1, 0.001, "it finished in 300 ms")
      for (var f = 0; f < 10; f++)
        race.stepClock(60)
      verify(track.cageBorn > -1e8, "and it is still up, because the effect is still up")
    }

    // The Pile-Up's sky flash, against the design's 3 Hz cap. Two flashes, and
    // the gap between their peaks measured off the screen's own property.
    function test_11_the_sky_flashes_twice_and_never_faster_than_3_hz() {
      preroll()
      race.injectEvent("cardUsed", "pileUp")
      var peaks = []
      var last = 0
      var rising = false
      for (var t = 0; t <= 900; t += 10) {
        var now = track.fxSkyFlash
        if (now > last + 0.0001)
          rising = true
        else if (rising && now < last - 0.0001) {
          peaks.push(t - 10)
          rising = false
        }
        last = now
        race.stepClock(10)
      }
      compare(peaks.length, 2, "the sky flashed twice: peaks at " + JSON.stringify(peaks))
      var gap = peaks[1] - peaks[0]
      verify(1000 / gap <= 3.0,
             "and " + gap + " ms apart is " + (1000 / gap).toFixed(2) + " Hz, under the cap")
    }
  }
}
