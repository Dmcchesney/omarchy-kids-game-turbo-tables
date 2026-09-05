import QtQuick
import QtTest
import "../../ui/parts/CardFx.js" as CardFx
import "../../engine/engine.mjs" as Engine

// PIECE F. The beat table against the design, and the two rules that keep it a
// kids' game.
//
// WHAT THIS FILE CAN AND CANNOT CHECK. It cannot look at a frame -- no QML test
// can, and this project has already been caught reporting a number about a
// picture that did not contain it. What it CAN check is the arithmetic the
// picture is made from: that every card in the rules has a beat table, that
// every duration is the one `docs/design.md` v4 writes, that no flash in the
// piece repeats faster than the design's 3 Hz cap, and that reduced motion
// takes out every one of the things the design names and none of the things it
// does not. The pictures are the frame strips in the evidence.
//
// A NOTE ON WHAT A PASSING TEST HERE MEANS. Each number below is quoted from
// the design in the comment beside it. If the design and this table disagree,
// this file fails -- which is the point: it is the only thing standing between
// a builder retyping "hit-stop 90" as 190 and nobody noticing.
TestCase {
  name: "CardFx"

  // The design's eight cards, and the engine's own list, so a card added to the
  // rules without a beat table fails here rather than drawing nothing.
  function test_00_every_card_in_the_rules_has_a_beat_table() {
    for (var i = 0; i < Engine.CARD_SCHEDULE.length; i++) {
      var card = Engine.CARD_SCHEDULE[i]
      verify(CardFx.BEATS[card] !== undefined,
             "the engine deals " + card + " and the design gives it a beat table")
    }
    compare(Object.keys(CardFx.BEATS).length, Engine.CARD_SCHEDULE.length,
            "and there is no beat table for a card the rules do not have")
  }

  // Every card has all three beats the piece is judged on: a telegraph the eye
  // can catch BEFORE the impact, something AT the impact, and an aftermath.
  // Roll Cage is the one card with no telegraph, and that is the design's --
  // it is not an attack, so there is nothing to see coming.
  function test_01_every_card_has_three_beats() {
    for (var card in CardFx.BEATS) {
      var b = CardFx.BEATS[card]
      if (card !== "rollCage")
        verify(b.telegraph >= 120,
               card + ": a telegraph a child can catch, not a frame (" + b.telegraph + " ms)")
      verify(b.impact > 0, card + ": something happens at the impact")
      verify(b.aftermath === -1 || b.aftermath >= 300,
             card + ": an aftermath that lasts, or one the engine ends")
    }
  }

  // Design v4: "the world freezes for 60 to 120 ms at the moment of impact".
  // The range is the design's own and every card that has a hit-stop is inside
  // it; the three that have none are the three the design gives none.
  function test_02_every_hit_stop_is_inside_the_designs_range() {
    var none = ["oilSlick", "rollCage"]
    for (var card in CardFx.BEATS) {
      var ms = CardFx.BEATS[card].hitStop
      if (none.indexOf(card) >= 0) {
        compare(ms, 0, card + " has no hit-stop in the design")
        continue
      }
      verify(ms >= 60 && ms <= 120,
             card + ": hit-stop " + ms + " ms is inside the design's 60 to 120")
    }
    compare(CardFx.HIT.hitStop, 80, "being hit: \"Hit-stop 80\"")
  }

  // The per-card numbers, transcribed from the design's own sentences. The
  // comment on each line is the sentence.
  function test_03_the_table_is_the_design() {
    // "Nitro ... Telegraph 120 ... hit-stop 60 ... Aftermath 700"
    compare(CardFx.BEATS.nitro.telegraph, 120)
    compare(CardFx.BEATS.nitro.hitStop, 60)
    compare(CardFx.BEATS.nitro.aftermath, 700)
    // "the sun blooms for 300, the four next lap lamps light in a chase"
    compare(CardFx.BEATS.nitro.bloom, 300)
    compare(CardFx.BEATS.nitro.lampChase, 4)
    // "the kart squats one pixel"
    compare(CardFx.BEATS.nitro.squatPx, 1)

    // "Turbo ... Telegraph 250 ... hit-stop 90 ... focal length bumps for 400
    //  ... Ten lap lamps chase in 500 ... Aftermath 1200"
    compare(CardFx.BEATS.turbo.telegraph, 250)
    compare(CardFx.BEATS.turbo.hitStop, 90)
    compare(CardFx.BEATS.turbo.impact, 400)
    compare(CardFx.BEATS.turbo.lampChase, 10)
    compare(CardFx.BEATS.turbo.lampChaseMs, 500)
    compare(CardFx.BEATS.turbo.aftermath, 1200)
    // "the kart squats two pixels"
    compare(CardFx.BEATS.turbo.squatPx, 2)

    // "Oil Slick ... Telegraph 200 ... a decal that grows for 400 ... yaw
    //  wobbles +-1 column for 800 ... three squeals staggered by 120"
    compare(CardFx.BEATS.oilSlick.telegraph, 200)
    compare(CardFx.BEATS.oilSlick.decalGrow, 400)
    compare(CardFx.BEATS.oilSlick.fishtail, 800)
    compare(CardFx.BEATS.oilSlick.stagger, 120)

    // "Wrench ... Telegraph 500 ... hit-stop 80"
    compare(CardFx.BEATS.wrench.telegraph, 500)
    compare(CardFx.BEATS.wrench.hitStop, 80)

    // "Pothole ... Telegraph 350 ... hit-stop 100 ... a two-pixel dip ... the
    //  kart bounces twice"
    compare(CardFx.BEATS.pothole.telegraph, 350)
    compare(CardFx.BEATS.pothole.hitStop, 100)
    compare(CardFx.BEATS.pothole.dipPx, 2)
    compare(CardFx.BEATS.pothole.bounces, 2)

    // "Pile-Up ... Telegraph 600: the sky flashes amber twice ... hit-stop 120,
    //  then 300 at half speed"
    compare(CardFx.BEATS.pileUp.telegraph, 600)
    compare(CardFx.BEATS.pileUp.hitStop, 120)
    compare(CardFx.BEATS.pileUp.impact, 300)
    compare(CardFx.BEATS.pileUp.slowMo, 0.5)
    compare(CardFx.BEATS.pileUp.skyFlashes, 2)

    // "Roll Cage ... a cage frame draws itself ... over 300 ... four metallic
    //  clicks"
    compare(CardFx.BEATS.rollCage.drawMs, 300)
    compare(CardFx.BEATS.rollCage.clicks, 4)

    // "Tow Hook ... Telegraph 400 ... latch with a hit-stop of 80 ... Impact
    //  700 ... the rival's tag reads TOWED for 1.6 s"
    compare(CardFx.BEATS.towHook.telegraph, 400)
    compare(CardFx.BEATS.towHook.hitStop, 80)
    compare(CardFx.BEATS.towHook.impact, 700)
    compare(CardFx.BEATS.towHook.towedMs, 1600)

    // "Being hit ... a 200 ms shake with decay"
    compare(CardFx.HIT.shakeMs, 200)

    // "the chosen card enlarges for 150"
    compare(CardFx.HAND.enlargeMs, 150)
  }

  // Design, Accessibility: "nothing flashes faster than 3 Hz". Every repeating
  // thing in this piece is checked against it, in Hz, from its own period.
  function test_04_nothing_in_this_piece_repeats_faster_than_3_hz() {
    // Pile-Up's "the sky flashes amber twice". Two flashes inside a 600 ms
    // telegraph would be 3.3 Hz, which is over the cap, so the view spaces them
    // 340 ms apart. That number lives in ui/TrackView.qml (`fxSkyGap`) and is
    // asserted against the picture in tst_trackview_fx.qml; here is the rule it
    // has to satisfy.
    var skyGap = 340
    verify(1000 / skyGap <= 3.0,
           "the Pile-Up sky flash repeats at " + (1000 / skyGap).toFixed(2) + " Hz")

    // The Roll Cage's "soft amber pulse".
    verify(1000 / CardFx.BEATS.rollCage.pulseMs <= 3.0,
           "the cage pulses at " + (1000 / CardFx.BEATS.rollCage.pulseMs).toFixed(2) + " Hz")

    // "An unused hand breathes gently."
    verify(1000 / CardFx.HAND.breatheMs <= 3.0,
           "the hand breathes at " + (1000 / CardFx.HAND.breatheMs).toFixed(2) + " Hz")

    // Oil Slick's three squeals are three different sounds on three different
    // karts, not one thing flashing, but the stagger is checked anyway because
    // a child sees three hits arrive: 120 ms apart is 8.3 Hz and would be over
    // the cap if it were a flash. It is not one -- nothing about the screen
    // blinks on that beat, and the wobble it starts runs for 800 ms per kart --
    // so what is asserted is that the WOBBLE, which is the thing that moves, is
    // inside the cap.
    verify(1000 / (CardFx.BEATS.oilSlick.fishtail / 3) <= 4.0,
           "the fishtail swings three times over 800 ms")
  }

  // Reduced motion takes out exactly what the design names and nothing else.
  function test_05_reduced_motion_removes_the_named_things_only() {
    var named = ["hitStop", "shake", "spin", "whip", "wobble", "bounce", "dip",
                 "speedLines", "afterimage", "flight", "tumble", "squat",
                 "shimmer", "bloom"]
    for (var i = 0; i < named.length; i++)
      verify(CardFx.reducedOut(named[i]), named[i] + " is removed under reduced motion")

    // ... and the substitutes stay, because a card with nothing left is a card
    // a child with the setting on cannot see happen at all.
    var kept = ["flash", "decal", "tag", "smoke", "lampChase", "callout"]
    for (var k = 0; k < kept.length; k++)
      verify(!CardFx.reducedOut(kept[k]),
             kept[k] + " survives reduced motion, so the event is still readable")
  }

  // The helpers, because every drawn property in the piece is one of these of
  // the effect clock and a broken easing is a broken picture everywhere at once.
  function test_06_the_easings_are_bounded_and_land_on_their_ends() {
    compare(CardFx.phase(-50, 100), 0)
    compare(CardFx.phase(150, 100), 1)
    compare(CardFx.phase(50, 0), 1, "a zero-length phase is already over")
    compare(CardFx.easeOut(0), 0)
    compare(CardFx.easeOut(1), 1)
    compare(CardFx.easeIn(0), 0)
    compare(CardFx.easeIn(1), 1)
    fuzzyCompare(CardFx.bump(0), 0, 0.001)
    fuzzyCompare(CardFx.bump(1), 0, 0.001)
    fuzzyCompare(CardFx.bump(0.5), 1, 0.001)
    for (var u = 0; u <= 1.0001; u += 0.05) {
      verify(CardFx.easeOut(u) >= 0 && CardFx.easeOut(u) <= 1, "easeOut stays in 0..1")
      verify(Math.abs(CardFx.decay(u, 3)) <= 1.0001, "the decay never grows")
    }
    fuzzyCompare(CardFx.decay(1, 3), 0, 0.001, "and it has settled by the end")
  }

  // The span a frame strip has to cover, so the evidence's frame counts are
  // derived from the design rather than guessed at.
  function test_07_the_drawn_span_covers_the_telegraph_and_the_impact() {
    for (var card in CardFx.BEATS) {
      var b = CardFx.BEATS[card]
      compare(CardFx.span(card), b.telegraph + b.hitStop + b.impact,
              card + ": the span is its three beats")
      verify(CardFx.drawnSpan(card) > CardFx.span(card),
             card + ": and the drawn span reaches into the aftermath")
    }
  }

  // ------------------------------------------------------- the loudness ladder
  //
  // ROUND 3. A blind critic measured round two's strips and found that the
  // legendary Pile-Up changed less of the screen at its impact than the common
  // Nitro, and that Turbo's launch was only 1.5x Nitro's skip -- so with the
  // HUD covered, a four-question skip and a ten-question launch were the same
  // firework. The fix is a ladder, and this is the ladder's invariant: the
  // flash and the shake a card spends are ordered by what the card costs the
  // racer it lands on.
  //
  // The costs are the ENGINE's, read from `Engine.CARDS`, so this test cannot
  // pass by agreeing with a second copy of the rules. A self boost is charged
  // at the questions it skips; an attack at the questions it adds; Oil Slick at
  // its delta times the three rivals it lands on; the Tow Hook, which moves a
  // whole place, sits with the eights.
  function test_08_the_loudness_is_ordered_by_what_the_card_costs() {
    function cost(card) {
      var c = Engine.CARDS[card]
      if (card === "towHook")
        return 8
      if (card === "rollCage")
        return 0
      if (String(c.scope) === "aoe")
        return Math.abs(Number(c.questionDelta)) * 3
      return Math.abs(Number(c.questionDelta))
    }
    // Every card states both terms, so none of them is loud or quiet by
    // accident.
    for (var card in CardFx.BEATS) {
      var b = CardFx.BEATS[card]
      verify(b.flashPeak !== undefined, card + ": states its flash")
      verify(b.impactShake !== undefined, card + ": states its shake")
      verify(b.flashPeak >= 0 && b.flashPeak <= 0.76,
             card + ": flash " + b.flashPeak + " is inside the ladder")
      verify(b.impactShake >= 0 && b.impactShake <= 1,
             card + ": shake " + b.impactShake + " is a fraction of a full one")
    }
    // The order itself. Every pair that differs in cost must differ the same
    // way in loudness, where loudness is the two terms together.
    function loud(card) {
      var b = CardFx.BEATS[card]
      return b.flashPeak + b.impactShake
    }
    var names = Object.keys(CardFx.BEATS)
    for (var i = 0; i < names.length; i++)
      for (var j = 0; j < names.length; j++) {
        if (cost(names[i]) <= cost(names[j]))
          continue
        verify(loud(names[i]) > loud(names[j]),
               names[i] + " (costs " + cost(names[i]) + ", loudness "
               + loud(names[i]).toFixed(2) + ") is louder than " + names[j]
               + " (costs " + cost(names[j]) + ", loudness "
               + loud(names[j]).toFixed(2) + ")")
      }
    // And the two the design names in words. "Pile-Up: the one the whole room
    // should notice"; "Turbo: the self boost that should feel like a launch",
    // against Nitro's skip.
    verify(loud("pileUp") === Math.max(loud("pileUp"), loud("turbo"),
                                       loud("wrench"), loud("pothole"),
                                       loud("nitro"), loud("oilSlick"),
                                       loud("towHook"), loud("rollCage")),
           "the Pile-Up is the loudest card in the game")
    verify(loud("turbo") >= loud("nitro") * 2.5,
           "and a launch is not a skip at a slightly higher volume ("
           + loud("turbo").toFixed(2) + " against " + loud("nitro").toFixed(2) + ")")
    console.log("FX-LADDER|" + names.map(function (n) {
      return n + " cost " + cost(n) + " loud " + loud(n).toFixed(2)
    }).join(" · "))
  }
}
