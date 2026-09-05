import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

// The race.
//
// This screen holds one `RaceState`, calls `Engine.step(state, input, now)`
// and `Engine.rivalStep(state, rivals, now)`, and drives every animation from
// the events those two hand back. It never re-derives a rule: the place comes
// from `raceOrder`, the charge from `streak`, the lap lamps from
// `correctInLap` and `questionsNeededThisLap`, the callouts from `passed`,
// `passedBy`, `blocked` and `cardUsed`. If a number on this screen disagrees
// with the engine, the screen is wrong.
//
// THE CLOCK IS NOT A WALL CLOCK. `now` comes from a FrameAnimation's
// `elapsedTime`, which is a monotonic animation clock, offset by whatever the
// race had already banked. Nothing here reads the date, the time of day, or
// the epoch, and the save file has no dates in it for the same reason.
//
// TWO TIMEBASES, on purpose and as the plan specifies. A 100 ms `Timer` steps
// the engine -- the race clock, the rival think-time deadlines, the stall
// expiries -- and a `FrameAnimation` drives the view. Both stop when the
// overlay closes, so a closed game costs the shell nothing. The engine is
// therefore stepped ten times a second whatever the frame rate is, and the
// view interpolates between those steps, which is why a dropped frame slows
// the picture and never the race.
FocusScope {
  id: race

  // --------------------------------------------------------------- inputs
  property int seed: 42
  property string mode: "grandPrix"
  property string preset: "1-12"
  property string rivalLevel: "pro"
  // Advance the race by this many of the child's answers before showing it,
  // stepping the rivals alongside. It is how a screenshot can be taken of a
  // race in progress -- lamps lit, a hand held, a charge part-full -- without
  // anyone having to play for a minute first. Zero in play.
  property int warmup: 0
  // How long each warm-up answer takes. Four seconds is the pace the design's
  // rival gate scripts a child at, so a warmed-up race is a race a child could
  // plausibly be in.
  property int warmupPaceMs: 4000
  // Forces the CanvasRoad fallback, for a side-by-side with the shader.
  property alias forceCanvas: track.forceCanvas

  // ----------------------------------------------------- the save-file seam
  //
  // The load half of the fact history. `RaceConfig.factHistory` is the engine's
  // own seam (`src/engine/race.ts`): the child's saved per-fact record goes in
  // here and `factHistoryOf(state)` hands it back at the flag. The host reads it
  // off `Store.factHistoryForRace()`, which remembers the same array as the
  // baseline it will later declare -- and `commitRace` refuses any commit whose
  // baseline is not the file it is being folded into, so a race that is not
  // seeded from the file cannot be banked at all. A race created without it is
  // exactly the race it was before the seam existed, which is what the harness
  // and the screenshot runs still get.
  property var factHistory: []

  // The write half of the record. Design, Data, `records`: "per preset: best
  // clean time, correct, attempted, answer timeline for the ghost." The
  // timeline is the ghost, and it can only be built while the race is running,
  // one sample per answer, so it is accumulated here through the engine's own
  // `recordStep` and read off by the host at the flag. Nothing on this screen
  // writes it anywhere.
  readonly property var ghostTimeline: race.timeline
  property var timeline: Engine.emptyTimeline()
  // The road, exposed so a host can pause it when the overlay closes and so a
  // test can ask it which path it took. Nothing outside drives it in play: the
  // lurch and the pull-back come from the engine's events.
  readonly property alias trackView: track
  // The powerup panel, exposed for the same reason the road is: a keyboard
  // walkthrough has to be able to ask which card is chosen and what the panel
  // is telling the child, and reading it off the panel is the only way to check
  // the screen rather than a second copy of its state. Nothing outside drives
  // it; the digit arbitration below is the only caller.
  readonly property alias handPanel: picker

  readonly property bool reducedMotion: Store.setting("reducedMotion") === true

  readonly property Item focusTarget: keys
  signal finished(var board)
  signal leaveRequested()

  // -------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.40, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ----------------------------------------------------------- race state
  property var state: null
  property var rivals: null
  property real clockBase: 0
  property real nowMs: 0

  readonly property var human: state ? Engine.humanRacer(state) : null
  readonly property int totalLaps: state ? state.totalLaps : 12

  // ------------------------------- PIECE F ROUND 2: THE PAYOFF FOLLOWS THE CAUSE
  //
  // A card resolves in ONE engine step: the `cardUsed` and every `hit`, `swap`
  // and `lapComplete` it causes come back together, and the lap requirement,
  // the order and the progress have all already moved by the time this screen
  // is told. The design's beat, though, is a TELEGRAPH the eye catches first
  // and an IMPACT the world reacts on -- so a view bound straight to the engine
  // shows the reward while the wind-up is still playing. A blind critic caught
  // exactly that on a rival build: "the lap counter goes 1/12 to 2/12 and 4th
  // to 1st 300 ms BEFORE the impact and simultaneous with the telegraph. The
  // payoff precedes the cause."
  //
  // So the VIEW -- never the rules -- holds at the race as it was until the
  // telegraph lands. One snapshot, taken from the state as it was before the
  // step, read by the lap gauge, the table name, the lamps, the place, the
  // kart positions and the minimap; released on the frame `ui/TrackView.qml`'s
  // cue reaches its impact, which is the same frame the hit-stop, the flash and
  // the victim's reaction fire on. Nothing is swallowed and nothing is
  // invented: the engine is still the only authority, and the most this can
  // ever defer a number by is one card's telegraph (600 ms, the Pile-Up's).
  //
  // It is the same shape as `pendingPasses` below, which defers a pass until
  // the karts have visibly crossed, and for the same reason: a HUD that
  // contradicts the road is a HUD a child cannot read.
  property var echoHold: null
  readonly property bool echoHeld: echoHold !== null && track.cueTelegraphing

  function snapshotOf(from) {
    if (!from)
      return null
    var progress = []
    for (var i = 0; i < from.racers.length; i++)
      progress.push(Engine.effectiveProgress(from.racers[i], from.questionsPerLap))
    var self = Engine.humanRacer(from)
    var order = Engine.raceOrder(from)
    var at = order.indexOf(from.humanId)
    return {
      "progress": progress,
      "order": order,
      "lapsDone": self ? self.lapsComplete : 0,
      "table": self ? Engine.currentTableName(from, self) : "",
      "lit": self ? self.correctInLap : 0,
      "needed": self ? Math.max(1, self.questionsNeededThisLap) : 12,
      "place": at < 0 ? order.length : at + 1
    }
  }

  readonly property int lapsDone: echoHeld ? echoHold.lapsDone
                                           : (human ? human.lapsComplete : 0)
  readonly property string tableName: echoHeld
                                      ? echoHold.table
                                      : ((state && human) ? Engine.currentTableName(state, human) : "")
  readonly property int place: {
    if (!state)
      return 1
    if (echoHeld)
      return echoHold.place
    var order = Engine.raceOrder(state)
    var at = order.indexOf(state.humanId)
    return at < 0 ? order.length : at + 1
  }
  readonly property int elapsedMs: state ? Math.max(0, nowMs - state.startedAtMs) : 0
  readonly property bool stalled: (state && human) ? Engine.isStalled(human, nowMs) : false
  // PIECE F. How far through the stall the field is, 0 at the lock and 1 when
  // it opens, for the bolts that spin off over it. The LENGTH is the engine's,
  // taken off the `hit` event that caused the lock, and the deadline is the
  // engine's `stalledUntilMs`; nothing here counts. With no length recorded --
  // a screen opened straight into a stall, which a harness can do -- it falls
  // back to the longest stall in the rules so the bolts still run out.
  property real lastStallMs: 0
  readonly property real stallProgress: {
    if (!race.stalled || !race.human)
      return 0
    var span = race.lastStallMs > 0 ? race.lastStallMs : 3000
    return Math.max(0, Math.min(1, 1 - (race.human.stalledUntilMs - race.nowMs) / span))
  }

  // The hand the child is holding, and the rivals a targeted card may be aimed
  // at. Both are handed to `ui/Picker.qml`, and the rival list is the caller's
  // job rather than the panel's: the design puts a finished racer out of reach,
  // so a racer who has crossed the line is not in this list, and the picker
  // clamps its aim when the list shrinks under it.
  readonly property var hand: (human && human.hand) ? human.hand : []
  readonly property var liveRivals: {
    var out = []
    if (!state)
      return out
    for (var i = 0; i < state.racers.length; i++) {
      var r = state.racers[i]
      if (r.kind === "human" || r.finished)
        continue
      out.push({ "id": r.id, "name": race.nameOf(r.id), "number": race.numberOf(r) })
    }
    return out
  }

  function clockNow() { return clockBase + frames.elapsedTime * 1000 }

  function nameOf(racerId) {
    if (!state)
      return ""
    if (racerId === state.humanId)
      return "YOU"
    for (var i = 0; i < state.racers.length; i++)
      if (state.racers[i].id === racerId)
        return Theme.rivalNames[Math.max(0, state.racers[i].seat - 1) % Theme.rivalNames.length]
    return ""
  }

  function paintOf(racer) {
    if (racer.kind === "human")
      return Theme.paint(Store.setting("kartPaint"))
    return Theme.paint(Theme.rivalPaints[(racer.seat - 1) % Theme.rivalPaints.length])
  }
  function numberOf(racer) {
    if (racer.kind === "human")
      return Store.setting("kartNumber")
    return Theme.rivalNumbers[(racer.seat - 1) % Theme.rivalNumbers.length]
  }
  function bodyOf(racer) {
    if (racer.kind === "human")
      return Store.setting("kartBody")
    return (racer.seat + 1) % 6
  }

  // ------------------------------------------------------------ the build
  function buildRace() {
    var withRivals = (mode === "grandPrix")
    var seats = [{ "id": "you", "kind": "human" }]
    var configs = []
    if (withRivals) {
      var personalities = ["bolt", "piston", "gasket"]
      for (var i = 0; i < personalities.length; i++) {
        seats.push({ "id": personalities[i], "kind": "rival" })
        configs.push({ "id": personalities[i], "personality": personalities[i], "level": race.rivalLevel })
      }
    }

    race.timeline = Engine.emptyTimeline()
    race.clearRevealQueue()
    reveal.clear()
    var built = Engine.createRace({
      "seed": race.seed,
      "mode": race.mode,
      "preset": race.preset,
      "racers": seats,
      "humanId": "you",
      "factHistory": (race.factHistory instanceof Array) ? race.factHistory : []
    })
    var started = Engine.step(built, { "kind": "start" }, 0)
    built = started.state
    var minds = withRivals ? Engine.createRivals(built, configs) : null

    // The warm-up. Scripted correct answers at a steady pace, with the rivals
    // stepped to the same clock, so the state the screen opens on is a state
    // the engine could actually have reached.
    var at = 0
    for (var n = 0; n < race.warmup; n++) {
      at += race.warmupPaceMs
      var self = Engine.humanRacer(built)
      if (self.finished || self.currentFact < 0)
        break
      var answered = Engine.step(built, { "kind": "answer", "value": Engine.factAnswer(self.currentFact) }, at)
      built = answered.state
      if (minds) {
        var moved = Engine.rivalStep(built, minds, at)
        built = moved.state
        minds = moved.rivals
      }
    }

    race.clockBase = at
    race.state = built
    race.rivals = minds
    race.nowMs = at

    var list = []
    var progress = []
    for (var r = 0; r < built.racers.length; r++) {
      var racer = built.racers[r]
      list.push({
        "id": racer.id,
        "name": nameOf(racer.id),
        "number": numberOf(racer),
        "body": bodyOf(racer),
        "seat": racer.seat,
        "paint": paintOf(racer),
        "progress": Engine.effectiveProgress(racer, built.questionsPerLap),
        "isHuman": racer.kind === "human",
        "ghost": false
      })
      progress.push(Engine.effectiveProgress(racer, built.questionsPerLap))
    }
    track.setKarts(list)
    var length = Engine.raceLength(built.totalLaps, built.questionsPerLap)
    var dots = []
    for (var d = 0; d < list.length; d++) {
      dots.push({
        "progress": Math.max(0, Math.min(1, progress[d] / Math.max(1, length))),
        "color": list[d].paint,
        "number": list[d].number,
        "isHuman": list[d].isHuman,
        "finished": false,
        "ghost": false
      })
    }
    minimap.setRacers(dots)
    // A new race is a new hand. A card chosen against the race that was here
    // before this one is a stale index into a hand that no longer exists, and a
    // pass waiting to be shown belongs to a race that is over.
    picker.reset()
    race.pendingPasses = []
    race.echoHold = null
    race.priorState = null
    race.mapDue = 0

    race.viewProgress = progress[0]
    race.smoothProgress = progress.slice()
    track.humanProgress = progress[0]
    track.setProgress(progress)
  }

  Component.onCompleted: buildRace()
  onSeedChanged: if (state) buildRace()

  // --------------------------------------------------------- the reducer
  function apply(result) {
    // The race as it was before this step, kept for exactly one purpose: the
    // pre-card snapshot `echoHold` holds the view at through a telegraph. It
    // is read only inside `handleEvents`, on the `cardUsed` branch.
    race.priorState = race.state
    race.state = result.state
    handleEvents(result.events)
    // Every claim the keyboard holds over the field is checked against the
    // field the engine just handed back. This is the one funnel every input
    // goes through, so no key handler can leave a stale claim behind.
    race.reconcileClaims()
    // ... and if the reveal that was covering the field has just gone, the keys
    // the child pressed into it are replayed here rather than inside
    // `handleEvents`, so the whole step has landed before the first of them is
    // read against it.
    if (race.revealHolds && !reveal.active)
      race.releaseReveal()
  }

  function send(input) {
    if (!state)
      return
    apply(Engine.step(state, input, clockNow()))
    advanceRivals()
  }

  function advanceRivals() {
    if (!rivals || !state)
      return
    var moved = Engine.rivalStep(state, rivals, clockNow())
    race.priorState = race.state
    race.state = moved.state
    race.rivals = moved.rivals
    handleEvents(moved.events)
  }

  property var priorState: null

  // Every animation and every message on this screen comes from here.
  function handleEvents(events) {
    if (!events || events.length === 0)
      return
    var me = state.humanId
    // One ghost sample per answer of the child's, taken from the state the
    // answer produced. `recordStep` filters the events by racer itself, so the
    // rivals' steps come through here and add nothing.
    race.timeline = Engine.recordStep(race.timeline, race.state, events, me)
    for (var i = 0; i < events.length; i++) {
      var e = events[i]
      switch (e.type) {
      case "correct":
        if (e.racerId === me) {
          track.throwForward(0.10)
          reveal.clear()
        }
        break
      case "wrong":
        if (e.racerId === me) {
          sputter.restart()
          reveal.clear()
        }
        break
      case "reveal":
        if (e.racerId === me) {
          reveal.show(Engine.factLabel(e.fact) + " = " + e.answer, e.revealMs, Theme.teal)
          // The field is the child's and this took it away from them mid-answer.
          // Everything they press until it comes back waits in `revealQueue`.
          race.revealHolds = true
        }
        break
      case "pitCrew":
        if (e.racerId === me)
          reveal.show(Engine.factLabel(e.fact) + " = " + e.answer, 1200, Theme.teal)
        break
      // ------------------------------------------------------------ PIECE F
      //
      // The five events the design's "Power-up feel" section is written
      // against. This screen is the only thing that translates them: it says
      // WHICH card landed on WHICH kart and hands that to `ui/TrackView.qml`,
      // which draws it. No rule is re-derived here and none is invented -- the
      // card, the racers, the delta and the stall all come off the event.
      //
      // ROUND 1 -- THE WORLD REACTION MOVED TO THE IMPACT. What stood here
      // called `track.throwForward` on the frame the card was played, so a
      // Turbo's road-throw happened 250 ms BEFORE the telegraph the design
      // asks for had finished, which is to say the game reacted before it
      // wound up. The cue now owns the schedule; this line only starts it.
      case "cardUsed":
        if (e.racerId === me) {
          picker.reset()
          var label = Engine.CARDS[e.card].label.toUpperCase()
          say(e.targetId === "" ? label : label + " ▸ " + nameOf(e.targetId),
              Theme.amber, e.card === "pileUp")
          // The view holds at the race as it was for the length of this card's
          // telegraph. See `echoHold` above; a card with no telegraph (the Roll
          // Cage) releases on the same frame, because `cueTelegraphing` is
          // already false by the time anything reads it.
          race.echoHold = race.snapshotOf(race.priorState)
          track.fxCardUsed(e.card, e.racerId, e.targetId)
        }
        break
      case "handDealt":
        if (e.racerId === me) {
          picker.reset()
          // "Reaching twelve: the charge bar flashes, the twelve segments burst
          // into three cards that slide up from the bottom right ... and
          // POWER-UP READY reads once."
          picker.deal()
          charge.burstNow()
          Sfx.play("deal")
          say("POWER-UP READY", Theme.amberGlow)
        }
        break
      case "hit":
        if (e.racerId === me) {
          if (e.questionDelta > 0) {
            say(Engine.CARDS[e.card].label.toUpperCase() + " ◂ " + nameOf(e.fromId), Theme.urgent)
            // The pull-back, the shake, the edge frame and the hood smoke are
            // all inside this one call now, so being hit reads as one event
            // rather than as a camera move with a caption.
            race.lastStallMs = e.stallMs
            track.fxHitMe(e.card, e.fromId, e.questionDelta, e.stallMs)
          }
        } else if (e.fromId === me) {
          // The child's own attack arriving on a rival. It is queued behind the
          // telegraph by the cue; see `fxLandedOn`.
          track.fxLandedOn(e.racerId, e.card, e.questionDelta)
        }
        break
      case "blocked":
        if (e.racerId === me) {
          say("ROLL CAGE HELD", Theme.teal)
          track.fxBlockedMe(e.card, e.fromId)
        } else if (e.fromId === me) {
          // "the callout reads ROLL CAGE HELD on their side"
          say("ROLL CAGE HELD  ·  " + nameOf(e.racerId), Theme.teal)
          track.fxBlockedOn(e.racerId, e.card)
        }
        break
      case "swap":
        if (e.racerId === me || e.withId === me) {
          // The child's OWN Tow Hook has already been announced by the
          // `cardUsed` branch above -- both events arrive in the same step --
          // and printing it twice put two identical callouts on the screen for
          // the same event, which is the sort of duplication the deleted
          // standings ladder was removed for. A swap the child did not cause
          // still says so.
          if (e.racerId !== me)
            say("TOW HOOK ◂ " + nameOf(e.racerId), Theme.amber)
          track.fxSwapped(e.racerId === me ? e.withId : e.racerId, "")
        }
        break
      case "passed":
        if (e.racerId === me)
          holdCallout(e.otherId, true)
        break
      case "passedBy":
        if (e.racerId === me)
          holdCallout(e.otherId, false)
        break
      case "signal":
        say(signalText(e.signal) + "  ·  " + nameOf(e.racerId), Theme.teal)
        break
      case "finished":
        if (e.racerId === me)
          race.finished(race.state)
        break
      default:
        break
      }
    }
  }

  // ------------------------------------------------------ PIECE F: INJECTION
  //
  // ONE ENTRY POINT, AND ROUND TWO MADE IT THE GAME.
  //
  // `dev/Harness.qml --inject <event>[:<card>[+<aim>]]` calls this so a frame
  // strip of one card can be reproduced in one command, by anybody, without
  // playing a race until that card happens to be dealt and happens to land.
  //
  // WHAT ROUND ONE DID, AND WHY IT WAS WRONG. It built an event object to the
  // shape in `src/engine/events.ts` and pushed it through `handleEvents`
  // WITHOUT calling `Engine.step`. The source said so plainly, and the source
  // was honest about the wrong thing: a strip taken that way is evidence about
  // the VIEW and not about the GAME. A blind critic found it from the outside
  // -- a Turbo that skips ten questions of twelve left the HUD reading `1/12`,
  // `3rd` and six lit lamps, so Nitro and Turbo were indistinguishable, "a
  // firework that changes nothing in the race". A test that asserts an effect,
  // in an environment that can produce that effect by another route, is testing
  // the environment.
  //
  // WHAT IT DOES NOW. It puts the race into the situation the strip is about
  // and then lets the REAL RULES run: `race.send({ kind: "useCard", ... })`,
  // which is the identical call `ui/Picker.qml`'s `onCardUsed` makes when the
  // child presses Enter. Every event the strip reacts to is then the engine's
  // own `cardUsed`, `hit`, `blocked`, `swap`, `lapComplete` and `passed`. The
  // lap counter really moves, the place really changes, the hand really
  // empties, the stall really starts, and the aftermath really ends when the
  // engine says the victim's lap is clean again.
  //
  // THE ONE WRITE THAT PLAY NEVER DOES is `injectSetupHand` below: putting a
  // chosen card into a hand. A hand comes off a shared round-robin cursor and
  // no sequence of legal inputs can be relied on to put a Pile-Up in it, so a
  // strip of the Pile-Up needs a fixture. It is one named function, it is
  // documented where it lives, and nothing in the game can reach it: the only
  // callers are the four branches below, and the only caller of those is
  // `dev/Harness.qml --inject`.
  //
  // It is here and not in dev/ because `send` and `handleEvents` are private to
  // this screen, and a harness reaching into them would be a second copy of
  // the switch above.

  // The fixture, and the whole of it. `Engine.CARD_SCHEDULE` fills the other
  // two slots so the panel has a real three-card hand to deal and to slam,
  // exactly as `Engine.dealHand` would have handed it over.
  function injectSetupHand(racer, card) {
    var hand = [card]
    for (var i = 0; i < Engine.CARD_SCHEDULE.length && hand.length < 3; i++) {
      var other = Engine.CARD_SCHEDULE[i]
      if (other !== card)
        hand.push(other)
    }
    racer.hand = hand
  }

  // WHO AN ATTACK IS AIMED AT, AND WHY THE HARNESS GETS TO CHOOSE.
  //
  // `near` (the default) is the nearest rival still in the fight. `leader` is
  // the racer furthest up the road, which at a Grand Prix's saturating tail is
  // a kart at the vanishing point -- the realistic worst case a child gets
  // handed when the race decides the distance rather than the harness. Both
  // are strips in the evidence, deliberately, because an effect that only
  // reads when the victim is close does not read.
  //
  // In play NOTHING calls this: the child's aim is `ui/Picker.qml`'s, and a
  // rival's is `src/engine/rivals.ts`'s.
  function injectAim(mode) {
    if (!state || !race.human)
      return ""
    var mine = Engine.effectiveProgress(race.human, state.questionsPerLap)
    var pick = ""
    var best = mode === "leader" ? -1 : Number.POSITIVE_INFINITY
    for (var i = 0; i < state.racers.length; i++) {
      var candidate = state.racers[i]
      if (candidate.kind === "human" || candidate.finished)
        continue
      var at = Engine.effectiveProgress(candidate, state.questionsPerLap)
      if (mode === "leader") {
        if (at > best) {
          best = at
          pick = candidate.id
        }
      } else {
        var away = Math.abs(at - mine)
        if (away < best) {
          best = away
          pick = candidate.id
        }
      }
    }
    return pick
  }

  function injectEvent(kind, arg) {
    if (!state || !race.human)
      return false
    var me = state.humanId
    var plus = (arg || "").indexOf("+")
    var name = plus >= 0 ? arg.slice(0, plus) : (arg || "")
    var aimMode = plus >= 0 ? arg.slice(plus + 1) : "near"
    var card = Engine.isCard(name) ? name : "wrench"
    var victim = injectAim(aimMode)
    var targeted = Engine.CARDS[card].scope === "targeted"

    // The child plays the card. One line, because it is the child's own line.
    if (kind === "cardUsed" || kind === "swap") {
      var played = kind === "swap" ? "towHook" : card
      if (Engine.CARDS[played].scope === "targeted" && victim === "")
        return false
      injectSetupHand(race.human, played)
      race.send({ "kind": "useCard", "index": 0,
                  "targetId": Engine.CARDS[played].scope === "targeted" ? victim : "" })
      return true
    }

    // The child's attack meeting a rival's Roll Cage. The cage is given to the
    // rival and then the rules decide: `attackOne` sees a cage, spends it, and
    // emits `blocked` instead of `hit`. Nothing here fabricates the block.
    if (kind === "blocked") {
      if (!targeted || victim === "")
        return false
      for (var b = 0; b < state.racers.length; b++)
        if (state.racers[b].id === victim)
          state.racers[b].rollCages = Math.max(1, state.racers[b].rollCages)
      injectSetupHand(race.human, card)
      race.send({ "kind": "useCard", "index": 0, "targetId": victim })
      return true
    }

    // A rival attacking the child, through the engine's own `useCard` with the
    // rival as the actor -- which is exactly what `src/engine/rivals.ts` sends
    // when a rival mind decides to spend. The stall, the extra lamps and the
    // hood smoke are then the engine's fields, written by the engine, and the
    // one mutation round one had to make by hand is gone.
    if (kind === "hit") {
      var attacker = ""
      for (var a = state.racers.length - 1; a >= 0; a--) {
        if (state.racers[a].kind !== "human" && !state.racers[a].finished) {
          attacker = state.racers[a].id
          break
        }
      }
      if (attacker === "" || !targeted)
        return false
      for (var h = 0; h < state.racers.length; h++)
        if (state.racers[h].id === attacker)
          injectSetupHand(state.racers[h], card)
      apply(Engine.step(race.state,
                        { "kind": "useCard", "racerId": attacker,
                          "index": 0, "targetId": me },
                        clockNow()))
      return true
    }

    // The hand arriving. Nothing to set up: with the streak one short of the
    // threshold the honest way to see a hand is to answer the question, so
    // `--warmup 11 --inject handDealt` is a child getting their twelfth in a
    // row. If the streak is not there, this refuses rather than faking it.
    if (kind === "handDealt") {
      if (race.human.finished || race.human.currentFact < 0)
        return false
      if (race.human.streak + 1 < state.streakThreshold) {
        console.log("Race: handDealt needs a streak of " + (state.streakThreshold - 1)
                    + "; this race has " + race.human.streak + " -- use --warmup "
                    + (state.streakThreshold - 1))
        return false
      }
      race.send({ "kind": "answer", "value": Engine.factAnswer(race.human.currentFact) })
      return true
    }

    // `chooseCard:<n>` is not an engine event and does not pretend to be one:
    // it presses the keys. The hand's slam is a keyboard beat, so the only
    // honest way to shoot it is through the same arbitration a child's press
    // goes through -- the picker's own choose, then `submitKey`, exactly as
    // ui/Race.qml's own handler calls them.
    if (kind === "chooseCard") {
      var slot = Math.max(1, Math.min(3, parseInt(name || "1", 10)))
      if (race.hand.length < slot)
        return false
      picker.choose(slot - 1)
      race.submitKey()
      return true
    }
    return false
  }

  function signalText(signal) {
    if (signal === "niceRun")
      return "NICE RUN"
    if (signal === "goodGame")
      return "GOOD GAME"
    if (signal === "goodLuck")
      return "GOOD LUCK"
    return "SO CLOSE"
  }

  // ---------------------------------------------------------- the callouts
  // Design, The view: callouts for 1.6 s. Three slots, used round-robin, so
  // two events in the same step do not overwrite one another.
  //
  // PIECE F -- `big` is the third argument and it is used by exactly one card.
  // Design v4, Pile-Up: "the callout is in the large type reserved for this
  // card." Reserved means reserved: `say(..., true)` is called from the
  // `cardUsed` branch for `pileUp` and from nowhere else in the file.
  function say(message, tone, big) {
    for (var i = 0; i < calloutSlots.count; i++) {
      var slot = calloutSlots.itemAt(i)
      if (slot && !slot.showing) {
        slot.big = big === true
        slot.say(message, tone)
        return
      }
    }
    var first = calloutSlots.itemAt(0)
    if (first) {
      first.big = big === true
      first.say(message, tone)
    }
  }

  // -------------------------------------------- passes, said when they show
  //
  // `passed` and `passedBy` come out of the engine the instant the ORDER flips,
  // and the order flips on effective progress. The karts on screen are drawn
  // from `smoothProgress`, which eases toward that target over roughly two
  // hundred milliseconds -- so round one printed PASSED GASKET while Gasket was
  // still visibly in front, and a child reading the road saw the HUD contradict
  // it. A callout that describes the race has to describe the race the child
  // can see.
  //
  // So a pass is held until the two karts have actually crossed on screen, and
  // released at the latest after `passHoldMs` -- because the engine is still the
  // authority and a pass must never be swallowed, only deferred. Under reduced
  // motion the smoothing is off, the karts cut, and the hold releases on the
  // very next frame.
  property var pendingPasses: []
  property int passHoldMs: 900

  function holdCallout(otherId, gained) {
    var next = race.pendingPasses.slice()
    next.push({ "otherId": otherId, "gained": gained, "atMs": race.nowMs })
    race.pendingPasses = next
  }

  function indexOfRacer(racerId) {
    if (!state)
      return -1
    for (var i = 0; i < state.racers.length; i++)
      if (state.racers[i].id === racerId)
        return i
    return -1
  }

  function sayPass(entry) {
    if (entry.gained)
      say("PASSED " + nameOf(entry.otherId), Theme.lime)
    else
      say(nameOf(entry.otherId) + " SLIPPED PAST", Theme.hazard)
  }

  function releasePasses() {
    if (race.pendingPasses.length === 0)
      return
    var mine = indexOfRacer(state.humanId)
    var keep = []
    for (var i = 0; i < race.pendingPasses.length; i++) {
      var entry = race.pendingPasses[i]
      var other = indexOfRacer(entry.otherId)
      var expired = (race.nowMs - entry.atMs) >= race.passHoldMs
      var visible = false
      if (mine >= 0 && other >= 0
          && race.smoothProgress.length > mine && race.smoothProgress.length > other) {
        visible = entry.gained
                  ? race.smoothProgress[mine] >= race.smoothProgress[other]
                  : race.smoothProgress[other] >= race.smoothProgress[mine]
      }
      if (visible || expired)
        race.sayPass(entry)
      else
        keep.push(entry)
    }
    race.pendingPasses = keep
  }

  // ------------------------------------------------------------ the view
  // Smoothed progress, so a kart glides between the engine's discrete steps
  // instead of jumping ten times a second. Under reduced motion the smoothing
  // is switched off and every position change is a cut, which is exactly what
  // the design asks for.
  property real viewProgress: 0
  property var smoothProgress: []
  property real smoothSpeed: 0.35

  // PIECE F -- AN EXTERNAL CLOCK, AND WHY THE EVIDENCE NEEDS ONE.
  //
  // The frame strips this piece is judged on have to be REPRODUCIBLE: a strip
  // that differs run to run is an anecdote, not evidence. Everything the effect
  // layer draws is already a pure function of `TrackView.fxClock` rather than
  // of a NumberAnimation, but that clock is stepped from a FrameAnimation,
  // which samples the wall clock -- so two runs step it by different amounts
  // and land between different beats.
  //
  // With `externalClock` set, this screen's two timebases stop and the caller
  // steps them by hand through `stepClock(ms)`. `dev/Harness.qml --strip` does
  // exactly that, a fixed number of milliseconds per frame, and grabs a frame
  // after each step. Nothing else in the game ever sets it, and the property is
  // never persisted: it is a development seam, in the same spirit as `warmup`.
  //
  // It also stops the two things on this screen that animate on wall time and
  // would otherwise smear a strip: the caret's blink and the callouts' fade.
  // Both are switched to their reduced-motion behaviour, which is a cut.
  property bool externalClock: false

  // A step is delivered in SLICES OF AT MOST TWENTY MILLISECONDS, and that is
  // a correctness rule rather than a smoothing one. `TrackView.advance` clamps
  // its own delta at 80 ms -- a real frame is never longer than that and a
  // dropped one must not teleport the road -- so a single `stepClock(160)` used
  // to advance the world by 80 and the caller had no way to know. A strip at
  // 90 ms steps was therefore drawing a world 10 ms behind its own label. The
  // slices are 20 ms, which is about a frame, so the world integrates exactly
  // as it does in play and the label on a strip frame is the truth.
  function stepClock(dtMs) {
    if (!race.externalClock || !state)
      return
    var left = Math.max(0, dtMs)
    while (left > 0) {
      var slice = Math.min(20, left)
      race.clockBase += slice
      race.frame(slice)
      left -= slice
    }
  }

  FrameAnimation {
    id: frames
    running: race.visible && !race.externalClock
    onTriggered: race.frame(frameTime * 1000)
  }

  function frame(dtMs) {
    if (!state)
      return
    race.nowMs = clockNow()

    // PIECE F -- THE ENGINE, NOT A DURATION, SAYS WHEN AN EFFECT ENDS.
    //
    // Design v4: "Aftermath lasts until the effect ends, which the rules define
    // as the end of the victim's current lap." The engine already publishes
    // that, per racer, as `questionsNeededThisLap` against the clean lap, so
    // the smoke on a hood is leased from it every frame rather than counted
    // down here. A racer who clears the extra questions stops smoking on the
    // frame they clear them; nothing in the view has to be told.
    var clean = race.state.questionsPerLap
    for (var a = 0; a < race.state.racers.length; a++) {
      var racer = race.state.racers[a]
      // ... and not before the attack has landed: through a telegraph the
      // victim is a kart nothing has happened to yet. `fxLand` starts the
      // smoke on the impact; this lease keeps it alive from there.
      var afflicted = !racer.finished && !race.echoHeld
                      && racer.questionsNeededThisLap > clean
      track.fxAfflicted(a, afflicted)
      if (!afflicted)
        track.fxClearLow(a)
    }
    // ... and the same for the Roll Cage outline around the child's own car:
    // it is up exactly while the engine says a cage is held.
    track.fxSetCages(race.human ? race.human.rollCages : 0)

    // THE HIT-STOP HOLDS THE KARTS TOO.
    //
    // The freeze lived in `TrackView.advance`, which stops the road, the camera
    // and the shake -- but the karts are positioned from `setProgress`, called
    // here, so through every hit-stop in round one the victim carried on
    // sliding backwards over a road that had stopped. A freeze that only some
    // of the world obeys is a dropped frame, which is exactly what the design
    // says a hit-stop must not read as.
    //
    // `fxSettleMs` is how long a kart takes to reach the position the card gave
    // it: longer through an impact, so a knock-back is a shove rather than a
    // cut. See `TrackView.fxSettleMs`.
    var lerp = race.reducedMotion ? 1 : Math.min(1, dtMs / track.fxSettleMs)
    if (track.worldFrozen)
      lerp = 0
    var values = []
    var targets = []
    var before = race.viewProgress
    // Through a telegraph the karts stay where the card found them, so a
    // victim does not start sliding backwards before the wrench reaches them
    // and the child does not surge before the launch. See `echoHold`.
    var frozen = race.echoHeld ? race.echoHold.progress : null
    for (var i = 0; i < state.racers.length; i++) {
      var target = frozen && frozen.length > i
                   ? frozen[i]
                   : Engine.effectiveProgress(state.racers[i], state.questionsPerLap)
      var held = (race.smoothProgress.length > i) ? race.smoothProgress[i] : target
      var next = held + (target - held) * lerp
      values.push(next)
      targets.push(target)
    }
    race.smoothProgress = values
    race.viewProgress = values.length > 0 ? values[0] : 0
    track.humanProgress = race.viewProgress
    // The engine's order, not the drawn order. Smoothed progress lags the
    // truth, so the two disagreed on 402 of 1875 frames -- longest run about
    // 2.8s, longer than a callout lives -- and a readout taken from the drawn
    // order could put the child third with the third kart drawn in front. The
    // exact targets go with it so the road's gap tags print the engine's gap.
    // ... AND THE ORDER CLAMP IS LIFTED WHILE A KART IS BEING SHOVED.
    //
    // `TrackView.orderedProgress` pulls every drawn position down to the
    // engine's order, which closes a rounding seam worth 5e-5 of a question on
    // about one frame in fifteen thousand. Through a card's impact it does
    // something else entirely: a Wrench sends a rival from one question ahead
    // to four behind, the engine's order flips on the same frame, and the clamp
    // teleports that kart from the middle of the road to behind the camera in
    // ONE FRAME -- so the shove the design asks for ("a Pile-Up visibly shoves
    // a kart backwards") never happens and the sparks land on an empty road.
    // Measured: the wrench's victim was drawn at +480 ms and gone at +540.
    //
    // So for the length of the settle the karts are drawn where they actually
    // are and cross each other in the open. The HUD still reads the engine on
    // the frame of the impact -- that is the payoff -- and `pendingPasses`
    // below still holds each callout until the two karts have visibly crossed.
    track.setProgress(values,
                      race.echoHeld ? race.echoHold.order
                                    : (track.cueSettling ? null : Engine.raceOrder(state)),
                      targets)

    // Speed is effective-progress rate, in questions per second, plus the
    // idle roll: the design has the kart rolling while the child is thinking.
    var rate = dtMs > 0 ? (race.viewProgress - before) / dtMs * 1000 : 0
    var want = Math.max(0, Math.min(1, 0.30 + rate * 0.75 - (race.stalled ? 0.26 : 0)))
    race.smoothSpeed = race.smoothSpeed * 0.90 + want * 0.10
    track.speed = race.smoothSpeed

    // A pass is announced on the frame the karts cross, not the frame the
    // engine's order flips.
    race.releasePasses()

    // THE MAP IS REFRESHED ON THE FRAME CLOCK, AT THE PULSE'S OWN CADENCE.
    //
    // ROUND 2. It used to be refreshed from the 100 ms engine `pulse` alone,
    // and the pulse is stopped under `externalClock` -- so in every frame strip
    // this piece has ever produced the minimap was frozen at the race's opening
    // positions. A blind critic read four dots that never moved through a Tow
    // Hook and called the swap "a line of text", correctly: the picture did not
    // move. The cadence was the intent and the pulse was only where it happened
    // to live, so the accumulator below keeps the ten-a-second and works under
    // either timebase.
    race.mapDue -= dtMs
    if (race.mapDue <= 0) {
      race.mapDue = 100
      race.refreshMap()
    }

    track.advance(dtMs)
  }
  // Milliseconds until the minimap's next refresh. Not a timer: it is counted
  // down by whatever clock is driving the frame, so a strip and a race refresh
  // it on the same schedule.
  property real mapDue: 0

  // ---------------------------------------------------------- the engine
  // 100 ms: the race clock, the rival deadlines and the stall expiries. The
  // design is explicit that the race clock is the only clock in the game.
  Timer {
    id: pulse
    interval: 100
    repeat: true
    // PIECE F. Under an external clock the caller owns both timebases; a strip
    // is a picture of the effect layer, and an engine tick landing between two
    // grabs would move the karts on a schedule the caller did not ask for.
    running: race.visible && race.state !== null && !race.externalClock
    onTriggered: {
      race.nowMs = race.clockNow()
      apply(Engine.step(race.state, { "kind": "tick" }, race.nowMs))
      advanceRivals()
    }
  }

  // ------------------------------------------------------------- keyboard
  // Digits, Enter, Backspace, H, 1 2 3, arrows, Escape -- the design's whole
  // key list and nothing else. There is no field to type into: the entry is
  // the engine's `racer.entry` string, drawn below, and the digits go through
  // `step` like everything else.
  //
  // ---------------------------------------------------------------------------
  // 1, 2 AND 3 ARE BOTH CARD KEYS AND DIGITS, AND THIS IS WHERE THAT IS SETTLED
  // ---------------------------------------------------------------------------
  //
  // The design gives 1, 2 and 3 to the powerup hand and also needs them as
  // digits, because a third of the answers in the 1-12 tables begin with one of
  // them. Round one sent the digit unconditionally and also moved the hand's
  // selection, and `Engine.typeDigit` submits the instant the entry is as long
  // as the answer. Two things followed, both measured on this file with real key
  // events:
  //
  //   - fact `1 x 6`, a hand held, one press of `1`: submitted as the answer to
  //     a question the child had not attempted. Streak gone, a `missed` fact
  //     recorded, that fact printed under FACTS TO LOOK AT on the results
  //     screen, and its mastery lamp put out. Nine of the twelve answers in the
  //     ones lap are one digit.
  //   - fact `1 x 10`, a hand held, `1` then Enter -- and Enter is the only key
  //     the panel printed: the stray `1` was submitted as the answer, the streak
  //     went, a miss was recorded, and the card was not played. Three losses and
  //     no gain. The working sequence was `1 Backspace Enter`, and nothing on
  //     the screen mentioned Backspace.
  //
  // That broke the design's second pillar -- "Mistakes cost the streak, never
  // the position" -- by charging the streak for a deliberate, correct action.
  // The race screen is the only place that can fix it, because it is the only
  // place that knows the expected answer; the picker cannot see it and should
  // not. The arbitration, in full:
  //
  // ROUND TWO FIXED THE FIRST PRESS AND LEFT THE SECOND. The rule below used to
  // read the key against an EMPTY field only, so once one card key had put its
  // digit in the field the next card key fell through to the ordinary-digit
  // path: `1` then `2` on `1 x 10` made `12`, `Engine.typeDigit` submits the
  // instant the entry is as long as the answer, and the child who changed their
  // mind between two of the three keys the panel prints lost the streak, banked
  // a miss on a fact they never attempted, put out a mastery lamp and played no
  // card. 121 of the 144 facts in the 1-12 deck have a two-or-more-digit answer,
  // and there is no other way to change which card is chosen. So the rule below
  // is written against the WHOLE of what the card presses have put in the field,
  // not against the first press only.
  //
  //   A press of 1, 2 or 3, with that card in the hand and NOTHING OF THE
  //   CHILD'S OWN in the field, is read against the answer on screen. Write
  //   `cand` for what the field would show if the press were typed.
  //
  //   a. `cand` IS the answer (`1 x 1`, press 1; `3 x 4`, press 1 then 2). The
  //      press is unambiguously the answer. It types, the engine submits it, the
  //      child is right, and the hand is not touched.
  //   b. `cand` is a shorter start of the answer (`1 x 10`, press 1; `11 x 11`,
  //      press 1 then 2). It chooses the card AND types the digit, because the
  //      child may well be typing the answer. Nothing can be submitted -- the
  //      entry is still short -- and the digits are held PROVISIONAL: they
  //      belong to the card presses, not to an answer.
  //   c. `cand` cannot be the answer (`1 x 10`, press 1 then 2; `1 x 6`, press
  //      1). Whatever else it is, it is not the child typing this answer, so it
  //      is a card choice -- possibly a change of one. The digits the earlier
  //      presses put in are taken back first, so the field never accumulates
  //      two card keys into a number, and then:
  //        - the answer is two digits or more: the digit is typed and held
  //          provisional, exactly as in (b). It cannot submit, because one digit
  //          is shorter than the answer.
  //        - the answer is ONE digit: typing it would submit a wrong answer on
  //          the spot. The digit is DEFERRED instead -- `pending` below. It is
  //          drawn in the field so the child can see the key landed, and it is
  //          handed to the engine only when the child says it is an answer.
  //
  //   Enter decides, and `pending` decides first. A deferred digit is the
  //   child's answer as far as Enter is concerned: it goes to the engine, the
  //   engine submits it, and a wrong one costs the streak and nothing else --
  //   the sputter, the reset and the recorded miss the design's answer loop
  //   step 4 asks for. Round two swallowed that press entirely: no sputter, no
  //   streak reset, no `missed` entry, and then Enter spent all three cards on a
  //   card and a rival the child had never confirmed.
  //
  //   With no deferred digit, Enter is the design's confirm key: if every
  //   character in the field was typed by the presses that chose the card, the
  //   child meant the card, the digits are taken back with the engine's own
  //   backspace and the card is played. If the child typed anything of their
  //   own, the field is an answer and Enter submits it.
  //
  //   Backspace, Escape and `H` all retire the claim. Backspace on a deferred
  //   digit simply drops it and leaves the card chosen, so the panel's own
  //   footer turns from the deferred line to `⏎ USE IT`. Escape drops it and
  //   puts the card back. `H` drops it because the hint moves the fact, and a
  //   claim that outlives its fact eats the next digit the child types -- round
  //   two's `1` `H` `4` `⏎`, which backspaced the child's own `4` away and spent
  //   the hand.
  //
  // ROUND 4 -- WHAT ROUND THREE GOT WRONG ABOUT ITS OWN RULE.
  //
  // The rule above is a fork with two branches, and round three printed one of
  // them. The comment that used to sit here said the card was "one printed key
  // away". It was not printed anywhere: the footer read
  // `FINISH THE ANSWER FIRST      ESC  BACK`, Backspace appeared in no string a
  // child could see or hear, and the sentence the footer DID print pointed at
  // the branch that costs a streak, a `missed` entry and a mastery lamp on a
  // fact the child is about to get right. `ui/Picker.qml` now prints both
  // branches and names the digit Enter would send; the arbitration below is
  // unchanged by that.
  //
  // Three things below it did change, and all three are about time rather than
  // about which key was pressed:
  //
  //   - An engine hit locks the field. A deferred digit handed over while the
  //     field is locked is refused by the engine and was cleared here anyway, so
  //     the digit AND the card both vanished on a rival's timing. `flushPending`
  //     now asks whether the engine can take the digit before it lets go of it,
  //     and says whether it succeeded, so Enter under a stall leaves the child
  //     exactly where they were.
  //   - Under that same lock, a card key equal to a one-digit answer used to run
  //     case (a) -- reset the panel, hand the digit over, watch the engine refuse
  //     it -- and did nothing at all, not even choose the card. Case (a) is now
  //     guarded on the lock and falls through to the card choice, which is the
  //     only reading left when the field cannot be typed into.
  //   - A second wrong answer on a fact reveals it for 1500 ms. The engine moves
  //     the deck on at once and the FIELD keeps the old fact's answer for that
  //     window, so a key pressed into it was arbitrated -- and could be submitted
  //     and credited -- against a question whose answer box the child could not
  //     see. Those keystrokes are held in `revealQueue` and replayed the instant
  //     the field comes back.
  //
  // Nothing is ever spent by a keystroke that was meant as a digit; a card
  // choice, and a change of card choice, costs nothing at all; no answer in the
  // tables has become untypable while a hand is held; and no keystroke of the
  // child's is thrown away -- under a stall it waits for the field, and under a
  // reveal it waits for the fact.
  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem

    Keys.onPressed: function (event) {
      if (!race.state)
        return
      var key = event.key

      if (key === Qt.Key_Escape) {
        // One meaning: back out of a card choice if there is one, and otherwise
        // leave the race. Round one had three, and the middle one neither left
        // nor cleared the digit it had caused.
        race.clearRevealQueue()
        if (picker.chosen >= 0) {
          race.dropPending()
          race.takeBackProvisional()
          picker.reset()
        } else {
          race.dropPending()
          race.leaveRequested()
        }
        event.accepted = true
        return
      }

      // ------------------------------------------------- the reveal window
      // While the field is showing a fact's answer back to the child, the deck
      // has already moved and the answer box is not on screen. Keys that belong
      // to the answer wait here for it. Escape above is not one of them -- back
      // one is back one, at every moment of the game.
      if (race.holdsForReveal()) {
        if (key >= Qt.Key_0 && key <= Qt.Key_9) {
          race.queueForReveal(key - Qt.Key_0)
          event.accepted = true
          return
        }
        if (key === Qt.Key_Backspace && race.revealQueue.length > 0) {
          // The child taking back a digit they cannot see yet. It is theirs to
          // take back, and it never reached the engine.
          race.revealQueue = race.revealQueue.slice(0, race.revealQueue.length - 1)
          event.accepted = true
          return
        }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && race.revealQueue.length > 0) {
          // Enter after digits belongs to those digits, so it queues behind
          // them. A bare Enter with nothing queued still plays a chosen card at
          // once: the hand is on screen throughout the reveal and a card play
          // has nothing to do with the fact behind it.
          race.queueForReveal(-1)
          event.accepted = true
          return
        }
        if (key === Qt.Key_H)
          race.clearRevealQueue()
      }

      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        race.submitKey()
        event.accepted = true
        return
      }

      if (key === Qt.Key_Backspace) {
        // A backspace of the child's own retires the provisional claim: what is
        // left in the field is theirs now. On a deferred digit it takes back the
        // digit and leaves the card chosen, which is the printed way to a card
        // on a one-digit fact: the panel's footer turns to `⏎ USE IT`.
        if (race.pending.length > 0) {
          race.dropPending()
          event.accepted = true
          return
        }
        race.clearProvisional()
        race.send({ "kind": "backspace" })
        event.accepted = true
        return
      }

      if (key === Qt.Key_H) {
        // The hint moves the fact on. Every claim on the old fact's field dies
        // with it, or it eats the first digit the child types at the new one.
        race.dropPending()
        race.clearProvisional()
        race.send({ "kind": "hint" })
        event.accepted = true
        return
      }

      if (key === Qt.Key_Left || key === Qt.Key_Right) {
        if (picker.targeting)
          picker.stepTarget(key === Qt.Key_Left ? -1 : 1)
        event.accepted = true
        return
      }

      if (key >= Qt.Key_0 && key <= Qt.Key_9) {
        race.typeKey(key - Qt.Key_0)
        event.accepted = true
        return
      }
    }
  }

  // ------------------------------------------------- the digit arbitration
  //
  // How many digits currently in the field were typed by the press that chose
  // the card. 0 or 1 in practice: the second digit a child types is their own
  // and retires the claim.
  property int provisional: 0

  // A digit a card press put on screen that the engine has NOT been given,
  // because handing it over would have submitted a wrong answer on the spot.
  // Never more than one character: it only ever arises against a one-digit
  // answer, and any second keystroke resolves it one way or the other. It is
  // drawn in the field, so it is visible to the child rather than swallowed.
  property string pending: ""

  function clearProvisional() { race.provisional = 0 }

  function dropPending() { race.pending = "" }

  // Will the engine take a digit right now? This mirrors the engine's own
  // `canAnswer`, which is private to `src/engine/race.ts`, and it is asked
  // BEFORE a deferred digit is let go of rather than after. Round three cleared
  // `pending` and then sent; under an engine hit the send was refused, the
  // follow-up submit was skipped because the entry was empty, and the child's
  // keystroke and their card choice were both gone with nothing on screen
  // saying so. A stall is two to three seconds long and lands on a rival's
  // clock, not the child's.
  function fieldTakesDigits() {
    if (!race.state || !race.human)
      return false
    if (race.state.status !== "racing" && race.state.status !== "settling")
      return false
    if (race.human.finished)
      return false
    if (race.human.currentFact < 0)
      return false
    return !race.stalled
  }

  // Hand the deferred digit to the engine. It goes through `typeDigit` like
  // every other digit -- same leading-zero rule, same automatic submit -- so a
  // deferred wrong answer costs exactly what a typed one costs: the streak, a
  // sputter, a `missed` entry, and nothing else.
  //
  // Returns true only when the digit actually left this file. False means the
  // field is locked and the digit is still deferred, still drawn, and still one
  // printed key from the card.
  function flushPending() {
    if (race.pending.length === 0)
      return false
    if (!race.fieldTakesDigits())
      return false
    var value = Number(race.pending)
    race.pending = ""
    race.clearProvisional()
    race.send({ "kind": "digit", "value": value })
    // Belt and braces: if the engine took the digit without submitting (it
    // cannot, on a one-digit answer, but the field is not this file's to
    // assume), Enter still means submit.
    if (race.entryLength() > 0)
      race.send({ "kind": "submit" })
    return true
  }

  function entryLength() { return race.human ? race.human.entry.length : 0 }

  // What the field shows: the engine's entry plus any deferred digit. This is
  // the string the arbitration reads, the picker measures, and the readout below
  // draws, so all three agree about what the child is looking at.
  readonly property string shownEntry: (race.human ? race.human.entry : "") + race.pending

  // The answer to the question on screen, as the string the child has to type.
  function expectedAnswer() {
    if (!race.human || race.human.currentFact < 0)
      return ""
    return String(Engine.factAnswer(race.human.currentFact))
  }

  // Enter spends the card exactly when the field holds nothing but the digits
  // the card presses put there -- and a deferred digit is never one of them: it
  // is on screen precisely because it might be an answer, so Enter reads it as
  // one and the panel prints `⏎  ANSWER n` beside the Backspace that takes it
  // back while it is there.
  function enterSpendsCard() {
    if (picker.chosen < 0)
      return false
    if (race.pending.length > 0)
      return false
    return race.entryLength() === race.provisional
  }

  function takeBackProvisional() {
    // The count is held locally: `reconcileClaims` below rewrites
    // `race.provisional` under every send, and a loop that trusted the property
    // it is mutating would be counting two things at once.
    var left = race.provisional
    while (left > 0 && race.entryLength() > 0) {
      race.send({ "kind": "backspace" })
      left -= 1
    }
    race.provisional = 0
  }

  // The field belongs to the fact it was typed at. The engine clears the entry
  // in five places -- a correct answer, a wrong one, a reveal, a hint, a fresh
  // lap -- and every one of them would otherwise leave a claim behind that eats
  // the child's next digit. This runs after every step, so no path can forget.
  function reconcileClaims() {
    if (race.provisional > race.entryLength())
      race.provisional = race.entryLength()
    if (race.pending.length > 0 && race.entryLength() > 0)
      race.pending = ""
  }

  // The fact moving is the other half of the same rule, and it is the one the
  // hint used to slip through.
  readonly property int factOnScreen: race.human ? race.human.currentFact : -1
  onFactOnScreenChanged: {
    race.pending = ""
    race.provisional = 0
  }

  // ------------------------------------------------------ the reveal window
  //
  // Design, The answer loop 5: a second wrong answer on the same fact "shows the
  // answer for a moment" and the deck moves on. The engine moves it in the same
  // step; the field on screen is handed over to `7 x 8 = 56` for 1500 ms
  // (`fieldBox` below draws the entry only while `!reveal.active`). For that
  // window the child is being shown one thing and the arbitration is reading
  // another, and a key pressed into it went straight through: a card key landed
  // as a CORRECT ANSWER to a question whose answer box was not on screen, took
  // the streak up and lit that fact's mastery lamp.
  //
  // Keys that belong to the answer wait here instead and are replayed through
  // the whole arbitration the moment the field comes back, so they cost what
  // they would have cost had the child pressed them one beat later, and nothing
  // is scored against a question they were not being shown.
  //
  // The pit crew's reveal is deliberately NOT held. `H` is the child's own
  // request to be shown the answer and move on; they pressed the key that moved
  // the deck, the new fact is already drawn above them at a tenth of the screen
  // height, and holding their next keystroke would put a 1.2 s wall in front of
  // a key they pressed on purpose. Only the reveal a wrong answer imposes takes
  // the field away from a child who was in the middle of using it.
  property bool revealHolds: false
  property var revealQueue: []

  function holdsForReveal() { return race.revealHolds && reveal.active }

  function queueForReveal(digitOrEnter) {
    // Four is more than a child can press inside 1500 ms with intent, and it is
    // longer than the longest answer in the deck. Past it the presses are a
    // mash, and a mash should not become a replayed answer.
    if (race.revealQueue.length >= 4)
      return
    var queue = race.revealQueue.slice()
    queue.push(digitOrEnter)
    race.revealQueue = queue
  }

  function clearRevealQueue() {
    race.revealHolds = false
    race.revealQueue = []
  }

  // Called the instant the reveal stops covering the field, by whichever of the
  // three things ends it: the hold timer, a correct answer, or another wrong one.
  function releaseReveal() {
    if (!race.revealHolds)
      return
    race.revealHolds = false
    var queued = race.revealQueue
    race.revealQueue = []
    for (var i = 0; i < queued.length; i++) {
      if (race.revealHolds) {
        // A replayed key was itself a second wrong answer and opened a new
        // window. The rest of the queue belongs to that one, not to this one.
        // Nothing can have been queued in between: a replay posts no key events.
        race.revealQueue = queued.slice(i)
        return
      }
      if (queued[i] < 0) {
        race.submitKey()
        continue
      }
      race.typeKey(queued[i])
    }
  }

  // What Enter means, in one place, so a key held back by the reveal window
  // replays through exactly the branch a live press would have taken.
  function submitKey() {
    if (race.pending.length > 0) {
      // A deferred digit is the child's answer. It goes to the engine now,
      // which submits it and charges a wrong one the streak -- and only the
      // streak. It never becomes a card play.
      //
      // ROUND 4. Unless the engine cannot take it: an engine hit locks the
      // field for two or three seconds, and round three cleared the digit,
      // reset the panel and sent into the lock, so a rival's timing deleted the
      // child's keystroke and their card choice together. If the digit did not
      // land, nothing here moves and the panel still prints both keys.
      if (race.flushPending())
        picker.reset()
      return
    }
    if (race.enterSpendsCard()) {
      race.takeBackProvisional()
      picker.confirm()
      return
    }
    if (race.entryLength() > 0) {
      race.clearProvisional()
      picker.reset()
      race.send({ "kind": "submit" })
      return
    }
    if (picker.chosen >= 0)
      picker.confirm()
  }

  function typeKey(digit) {
    var expected = race.expectedAnswer()
    var holding = digit >= 1 && digit <= 3 && race.hand.length >= digit
    // Nothing of the child's own in the field: everything in it, deferred digit
    // included, was put there by a card press.
    var clean = race.entryLength() === race.provisional

    if (holding && clean && expected.length > 0) {
      var cand = race.shownEntry + String(digit)

      if (cand === expected && !race.stalled) {
        // (a) the press completes the correct answer. Type it, let the engine
        // submit it, and leave the hand alone.
        //
        // ROUND 4 -- `!race.stalled`. With the field locked by an engine hit
        // this branch reset the panel, handed the digit over and watched the
        // engine refuse it: on `2 x 1` a press of `2` did NOTHING for the two or
        // three seconds of the hit -- no card chosen, no digit, no refusal said
        // out loud, and any card already chosen quietly dropped. The press
        // cannot be this answer while the answer cannot be given, so it falls
        // through to (c), which chooses the card and prints `⏎  USE IT`.
        race.dropPending()
        race.clearProvisional()
        picker.reset()
        race.send({ "kind": "digit", "value": digit })
        return
      }

      if (cand.length < expected.length && expected.indexOf(cand) === 0) {
        // (b) the press could be building the answer, and it cannot submit.
        // Choose the card and type it, provisionally.
        picker.choose(digit - 1)
        race.send({ "kind": "digit", "value": digit })
        race.provisional = race.entryLength()
        return
      }

      // (c) `cand` cannot be this answer, so the press is a card choice or a
      // change of one. Take back what the earlier presses put in FIRST -- this
      // is the line round two did not have, and without it two card keys ran
      // together into a number and submitted themselves.
      race.dropPending()
      race.takeBackProvisional()
      picker.choose(digit - 1)
      if (expected.length > 1 && !race.stalled) {
        // A single digit is shorter than the answer, so it cannot submit: show
        // it, held provisional, and Enter still gives it back.
        race.send({ "kind": "digit", "value": digit })
        race.provisional = race.entryLength()
      } else if (!race.stalled) {
        // One digit expected. Handing it over would submit a wrong answer, so
        // defer it: on screen, in the child's hands, and one Enter from the
        // engine.
        race.pending = String(digit)
      }
      return
    }

    // A digit of the child's own. Any deferred digit is theirs too, and it goes
    // to the engine first so the keystrokes reach it in the order they were
    // pressed -- exactly what typing those two digits does with no hand held.
    race.flushPending()
    if (race.entryLength() > 0) {
      // ROUND 5, AND IT COST A STREAK IN SIX RUNS OUT OF SIX.
      //
      // This branch used to call `clearProvisional()`, which zeroes the COUNT
      // and leaves the DIGIT in the field. On `4 x 12 = 48` with a hand held,
      // `1` chooses card one and prints a provisional `1` (branch (c) below is
      // the one that put it there); the child then types their answer, `4`,
      // which is not a card key -- 4 is past the end of a hand of three -- so
      // it lands here. The `1` stayed, the field became `14`, and a two-digit
      // answer submits itself the moment it is two digits long: streak to 0,
      // one `missed`, one attempt, on a question the child answered right.
      // Reproduced with real key events on seeds 140 to 145; the file's own
      // claim that "no answer in the tables has become untypable while a hand
      // is held" was false for every two-digit answer whose first digit is
      // past the hand.
      //
      // Branch (c) has taken the digit back since round two -- but only when
      // the NEXT key is also a card key, which is the shape every neighbouring
      // test covers and this one is not.
      //
      // What decides it is whether the provisional digits are still part of
      // the answer being typed. On `2 x 12 = 24` a provisional `2` followed by
      // `4` IS the answer and must stay, which is why this is a prefix test
      // and not an unconditional take-back. `takeBackProvisional()` only ever
      // removes digits a card press put there, so a field of the child's own
      // digits (`provisional` is 0) is untouched either way.
      var cand = race.shownEntry + String(digit)
      var expected = race.expectedAnswer()
      if (race.provisional > 0
          && !(expected.length > 0 && expected.indexOf(cand) === 0))
        race.takeBackProvisional()
      else
        race.clearProvisional()
      picker.reset()
    }
    race.send({ "kind": "digit", "value": digit })
  }

  // Digits the child typed on the countdown's GO beat, handed over by the flow.
  // `ui/Countdown.qml` prints TYPE THE ANSWER on that beat, so the keys pressed
  // on it are the child's answer to the first fact and they arrive here rather
  // than being dropped on the floor between two screens.
  function typeAhead(digits) {
    if (!digits || digits.length === 0)
      return
    for (var i = 0; i < digits.length; i++)
      race.typeKey(Number(digits[i]))
  }

  // =========================================================== the picture
  Rectangle {
    anchors.fill: parent
    color: Theme.ground
  }

  TrackView {
    id: track
    anchors.fill: parent
    reducedMotion: race.reducedMotion
    // The answer field's own box, so a road-spanning prop can be measured
    // against the object the plan's acceptance line names -- not against the
    // fact, which is a different object further up the screen and is what
    // round four measured instead. The field yields for the frames a crossbar
    // is over it; see `fieldYield` in TrackView.qml and `fieldFace` below.
    fieldRect: Qt.rect(question.x + fieldBox.x,
                       question.y + fieldBox.y,
                       fieldBox.width, fieldBox.height)
    factRect: race.factInkRect
  }

  // THE SKY IS NEVER BLACK, AND THIS USED TO MAKE IT BLACK.
  //
  // What stood here was a full-frame gradient with `rgba(0, 0, 0, 0.55)` at
  // the top, described as "a vignette, so the HUD sits on something". It sat
  // over the sky, which is the 40% of the frame the direction is most explicit
  // about: plan v2, Composition -- "the sky is 40% of the frame and is never
  // black" -- and the plan's own per-screen list names it as a defect left by
  // the prototype, "Race.qml's 0.55 vignette darkens the sky top to ~#2a0c24".
  // Measured on the shipped 1920x1080 frame, the mean of the top twelve rows
  // was #4b1937 where the sky beneath it paints #9c3174: a 55% black wash
  // across the brightest band of a retrowave sunset.
  //
  // The wash is gone. What it was actually needed for was the one HUD element
  // that had no panel of its own -- the table name and its lap lamps -- and
  // that is fixed where the problem is, by giving that block the same panel
  // the readouts either side of it already have. Everything else in the HUD
  // (the two gauges, the minimap, the clock, the picker, the charge) draws on
  // its own ground and never needed the sky darkened.
  //
  // What survives is the bottom falloff, and it is purple rather than black,
  // because the light rule says shadow is `#5f255e` and never grey. It is the
  // near floor running out of the sun's reach at the bottom corners of the
  // frame, which is a thing the reference does; it does not touch the sky.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: parent.height * 0.26
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(0.373, 0.145, 0.369, 0.0) }
      GradientStop { position: 1.0; color: Qt.rgba(0.373, 0.145, 0.369, 0.24) }
    }
  }

  // ------------------------------------------------------------- HUD left
  Row {
    id: leftHud
    x: race.px(30)
    y: race.px(24)
    spacing: race.px(16)

    HudReadout {
      id: lapGauge
      label: "LAP"
      value: race.lapsDone + 1 + " / " + race.totalLaps
      tone: Theme.cream
      labelSize: race.fs(13)
      valueSize: race.fs(34)
      padX: race.px(16)
    }

    // The table name and its lap lamps, on the same gauge face as the readouts
    // either side of them. It is the one HUD element that used to draw
    // straight onto the sky, and the reason the sky was being washed 55% black
    // to keep amber on hot pink legible. The panel is local rather than a
    // HudReadout because the block is a name over a row of lamps, not a
    // caption over a number, but it is the same face colour, the same corner
    // radius and the same border, so the top-left of the HUD reads as one row
    // of three instruments.
    Item {
      width: tableBlock.width + race.px(32)
      height: lapGauge.height

      Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusSmall
        color: Qt.rgba(0.11, 0.045, 0.10, 0.92)
        border.width: 1
        border.color: Theme.lineStrong
      }

      Column {
        id: tableBlock
        x: race.px(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: race.px(7)

        Text {
          textFormat: Text.PlainText
          text: race.tableName
          color: Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: race.fs(30)
          font.letterSpacing: 3
        }

        LapLamps {
          id: lamps
          // Held at the pre-card reading through a telegraph, so the ten lamps
          // a Turbo pays out light on the chase rather than before it. See
          // `echoHold`.
          lit: race.echoHeld ? race.echoHold.lit
                             : (race.human ? race.human.correctInLap : 0)
          total: race.echoHeld ? race.echoHold.needed
                               : (race.human ? Math.max(1, race.human.questionsNeededThisLap) : 12)
          cleanTotal: race.state ? race.state.questionsPerLap : 12
          cell: race.px(13)
          gap: race.px(4)
          // PIECE F. The boost's HUD echo: "the four next lap lamps light in a
          // chase left to right" (Nitro), "Ten lap lamps chase in 500" (Turbo).
          // Both numbers and both durations are the effect layer's, off the
          // same beat table the road is using, so the lamps and the road are
          // one event.
          chase: track.lampChase
          chaseCount: track.lampChaseCount
          // "the extra lap lamps you now owe appear as dark lamps added to the
          // row with a rattle, and light as you clear them". The lamps are
          // already added by `total` -- that is the engine's own
          // `questionsNeededThisLap` -- so what is added here is the rattle,
          // driven off the same hit the road's shake is.
          rattle: track.lampRattle
          reducedMotion: race.reducedMotion
        }
      }
    }

    HudReadout {
      id: placeGauge
      label: "PLACE"
      value: Engine.ordinal(race.place)
      tone: race.place === 1 ? Theme.amberGlow : Theme.cream
      labelSize: race.fs(13)
      valueSize: race.fs(34)
      padX: race.px(16)
    }

    // Design, HUD: "Roll Cage count as small icons by the place." One shield
    // per cage, because the design's accessibility rule wants a count to be
    // countable rather than a number beside an icon.
    Item {
      width: race.px(26)
      height: placeGauge.height
      visible: race.human ? race.human.rollCages > 0 : false

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: race.px(3)

        Repeater {
          model: race.human ? Math.min(4, race.human.rollCages) : 0

          PixelIcon {
            width: race.px(22)
            height: race.px(22)
            color: Theme.teal
            art: ["..XXXX..",
                  ".XXXXXX.",
                  "XX....XX",
                  "XX....XX",
                  "XX....XX",
                  ".XX..XX.",
                  "..XXXX..",
                  "...XX..."]
          }
        }
      }
    }
  }

  // ---------------------------------------------------- the empty strip
  //
  // Between the left readouts and the minimap run about 890 px of nothing, and
  // round two filled them with a standings ladder: four rungs, `1st 21 BOLT`
  // through `4th 7 YOU`, ringed on the child's own rung and named to a screen
  // reader as "4th, YOU" on every frame of the race.
  //
  // It is gone, and the rule it broke is not a HUD-inventory rule but the
  // design's Fairness list: "the callouts only ever say PASSED BOLT or BOLT
  // SLIPPED PAST, never a running last-place label." A four-rung ordered strip
  // naming who is last IS that label, printed continuously rather than for the
  // 900 ms a callout lives, and reading it aloud on a view the design says "is
  // visual by nature and is not claimed" made it worse rather than better. It
  // was also the third copy of one standings on one screen -- the ladder, the
  // gap tags `ui/TrackView.qml` draws on the road, and the minimap's four dots.
  //
  // What the design does sanction is here already and stays: `PLACE 4th` in the
  // HUD ("lap and table name top left, place beside it"), the minimap, and the
  // pass callouts. The band is left empty on purpose. An empty band costs a
  // child nothing; a rule broken on every frame costs them the thing the
  // Fairness list exists to protect.

  // ------------------------------------------------------------ HUD right
  // The wireframe's order along the top: the minimap, then the clock in the
  // corner.
  Row {
    id: rightHud
    anchors.right: parent.right
    anchors.rightMargin: race.px(30)
    y: race.px(24)
    spacing: race.px(14)

    Rectangle {
      id: mapPanel
      width: race.px(300)
      height: race.px(196)
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.86)
      border.width: 1
      border.color: Theme.line

      Text {
        id: mapCaption
        x: race.px(12)
        y: race.px(8)
        textFormat: Text.PlainText
        text: "CIRCUIT"
        color: Theme.textLabel
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: race.fs(12)
        font.letterSpacing: 2
      }

      Minimap {
        id: minimap
        anchors.fill: parent
        anchors.topMargin: race.px(24)
        anchors.margins: race.px(8)
        reducedMotion: race.reducedMotion || race.externalClock
        sectors: race.totalLaps
        activeSector: race.lapsDone + 1
        dotSize: race.px(20)
        // PIECE F. Design v4, Pile-Up: "The minimap pulses on the victim." The
        // index is a racer index, which is what `setRacers` was given, so the
        // dot that pulses is the dot of the kart that was hit.
        pulseIndex: track.minimapPulseKart
        pulse: track.minimapPulse
      }
    }

    HudReadout {
      label: "TIME"
      value: race.clockText
      tone: Theme.cream
      labelSize: race.fs(13)
      valueSize: race.fs(34)
      padX: race.px(16)
      // A fixed width, so a clock rolling from 9:59 to 10:00 does not move the
      // panel beside it.
      width: race.px(148)
    }
  }

  readonly property string clockText: {
    var total = Math.floor(elapsedMs / 1000)
    var mm = Math.floor(total / 60)
    var ss = total % 60
    return mm + ":" + (ss < 10 ? "0" : "") + ss
  }

  // The minimap is refreshed on the pulse rather than on the frame: it is the
  // honest picture of the race, not the exciting one, and ten times a second
  // is more than a dot crossing a 300 pixel loop over ten minutes needs.
  function refreshMap() {
    if (!state)
      return
    var length = Engine.raceLength(state.totalLaps, state.questionsPerLap)
    var values = []
    var flags = []
    for (var i = 0; i < state.racers.length; i++) {
      var held = (smoothProgress.length > i)
                 ? smoothProgress[i]
                 : Engine.effectiveProgress(state.racers[i], state.questionsPerLap)
      values.push(Math.max(0, Math.min(1, held / Math.max(1, length))))
      flags.push(state.racers[i].finished)
    }
    // The engine's order goes to the map for the same reason it goes to the
    // track view on line 490. It was threaded into one and not the other, and
    // the map spent up to half of every run drawing the field in an order the
    // callouts and the road disagreed with. The map takes it as indices into
    // `values`, because a dot has no kart id.
    var order = race.echoHeld ? race.echoHold.order : Engine.raceOrder(state)
    var rank = []
    for (var k = 0; k < order.length; k++)
      for (var r = 0; r < state.racers.length; r++)
        if (state.racers[r].id === order[k])
          rank.push(r)
    minimap.setProgress(values, rank)
    minimap.setFinished(flags)
  }

  // ----------------------------------------------------- the fact's ink
  //
  // The probe draws the widest fact in the game at a fixed size and reports the
  // tight bounding box of the glyphs -- the ink, not the em box. The ratio is
  // the face's own, so the size below follows the shell's font rather than a
  // constant measured once on this Mac. The probe's own size is fixed, so
  // nothing here is circular.
  TextMetrics {
    id: inkProbe
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: 200
    text: "12 \u00D7 12"
  }
  readonly property real factInkRatio: inkProbe.tightBoundingRect.height > 0
                                       ? inkProbe.tightBoundingRect.height / 200
                                       : 0.73
  readonly property int factPixelSize: {
    // A tenth of the screen height in ink, with a hair over it so rounding
    // never lands under the floor.
    var wanted = Math.ceil((race.height * 0.105) / Math.max(0.25, race.factInkRatio))
    // ... and never so wide that the widest fact runs off the screen.
    var widest = inkProbe.advanceWidth > 0
                 ? Math.floor((race.width - race.px(120)) * 200 / inkProbe.advanceWidth)
                 : wanted
    return Math.max(race.fs(118), Math.min(wanted, widest))
  }

  // The fact's ink AS IT IS ON THE SCREEN NOW: the tight bounding box of the
  // glyphs currently drawn, in this screen's own coordinates. Two things read
  // it, and both are the reason it is a live measurement of the item rather
  // than a constant:
  //
  //   * `factGround` below, which is what the fact yields with when a
  //     road-spanning prop is behind it -- `7 x 8` and `12 x 12` are not the
  //     same width, so a ground sized off a constant would be the wrong shape
  //     on most facts;
  //   * the evidence, which quotes the ink as a fraction of the frame height.
  //     The design's floor is "never smaller than a tenth of the screen
  //     height", and a round of this project already reported `font.pixelSize`
  //     as that number and was caught: the em box carries ascent, descent and
  //     leading, and this face draws about 0.73 of it.
  // `tightBoundingRect` is measured from the BASELINE, so its `y` is negative
  // for anything above it; the Text item's own top is `ascent` above that
  // baseline. Getting this wrong put the fact's ink at y = 5 on a frame where
  // the glyphs start at y = 140, which is the kind of number this project has
  // been caught quoting before -- so the evidence checks it against the pixels
  // rather than trusting the arithmetic.
  TextMetrics {
    id: factInkNow
    font: factText.font
    text: factText.text
  }
  FontMetrics {
    id: factFace
    font: factText.font
  }
  readonly property rect factInkRect: {
    var r = factInkNow.tightBoundingRect
    return Qt.rect(question.x + factText.x + r.x,
                   question.y + factText.y + factFace.ascent + r.y,
                   r.width, r.height)
  }

  // -------------------------------------------------- the fact's own ground
  //
  // THE OTHER HALF OF GIVING THE ARCHES BACK.
  //
  // The fact is drawn over every prop -- it is declared after the track, so a
  // gantry can never cover a glyph -- and what a road-spanning prop takes from
  // it is contrast, not visibility: the gantry's beam is a cream-and-ink
  // chequer and the fact is cream. So for the frames a crossbar is behind the
  // ink, and only those, the fact gets a ground.
  //
  // It is the floor's own near-black purple, at the alpha the light rule
  // allows, and it is NOT the round-three vignette coming back: that was a
  // full-frame 0.55 BLACK wash over the whole sky on every frame of every
  // race. This is a box the size of the glyphs, in purple, for about a second
  // a lap, and it is at zero the rest of the time. `race.factInkRect` is the
  // ink as it is on the screen now, so the ground is the shape of the fact
  // that is actually there.
  // PIECE F. The fact's INK box as an item, so a rect dump can print it. It
  // paints nothing at all -- it is `factInkRect` given a geometry a walk of the
  // tree can read, and `factInkRect` is what the effect layer's guard band and
  // the arches' yield are both measured against. A number in a report is not
  // evidence that a box is where the report says; this is the box.
  Item {
    objectName: "factInk"
    x: race.factInkRect.x
    y: race.factInkRect.y
    width: race.factInkRect.width
    height: race.factInkRect.height
  }

  //
  // PIECE F ROUND 2 -- AND FOR EVERY FRAME OF EVERY WORLD FLASH, FOR THE SAME
  // REASON. A wash is not a crossbar but it does the same thing to the same
  // glyphs: a blind critic measured the cream fact sitting on a cream-to-pale
  // bloom through a Turbo's white frame and both of the Pile-Up's amber
  // flashes, "the largest, most important thing on screen" reduced to a one-
  // pixel outline at the exact moment a child has to hold the question in their
  // head. `track.fxWashOverFact` is the alpha of the light actually reaching
  // the middle of the frame, so the ground comes up with the wash, in step with
  // it, and goes back to zero with it. The ground is BEHIND the ink -- it is
  // declared before the fact's own Column, which is the same argument the whole
  // effect layer's paint order rests on -- so nothing here covers anything.
  Rectangle {
    id: factGround
    visible: opacity > 0.004
    readonly property real wash: track.fxWashOverFact
    // Three times the wash, capped. The multiplier is not a taste: the plate
    // has to take back more ground than the wash put on, because the wash also
    // lifts the plate itself. Measured on the frames, WCAG 2.1 contrast between
    // the fact's ink and the ground it is on, inside the ink box: 3.47:1 with
    // nothing happening, 3.32:1 inside a Turbo's white frame with the plate at
    // 1.5x, and above the resting figure at 3x. The rule the design writes is
    // that the fact is the most legible thing on screen at every moment; a
    // number that goes DOWN during the loudest 120 ms of the game fails it.
    opacity: Math.max(track.factYield * 0.86, Math.min(0.92, wash * 3.0))
    x: race.factInkRect.x - race.px(22)
    y: race.factInkRect.y - race.px(14)
    width: race.factInkRect.width + race.px(44)
    height: race.factInkRect.height + race.px(28)
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(0.235, 0.071, 0.157, 0.80)
  }

  // ------------------------------------------------------- fact and field
  // Design, Pillars: "The question is the track. The fact is the largest thing
  // on screen at every moment of a race." It is, and it sits above the horizon
  // so it is never over a kart.
  Column {
    id: question
    // Named for the rect dump: the fact and the field are the two boxes the
    // effect layer's guard band is measured against, and this is the block
    // that holds them. Its position in `race.children` is also what proves the
    // fact is painted AFTER the track and therefore over every effect in it.
    objectName: "factColumn"
    anchors.horizontalCenter: parent.horizontalCenter
    y: race.px(118)
    spacing: race.px(14)

    Text {
      id: factText
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: (race.human && race.human.currentFact >= 0)
            ? Engine.factLabel(race.human.currentFact) : ""
      color: Theme.cream
      font.family: Theme.mono
      font.bold: true
      // The largest type on the screen, and never below a tenth of its height
      // -- measured as INK, which is the only reading of that rule a child can
      // see. `font.pixelSize` is an em box with ascent, descent and leading in
      // it; `12 x 12` in this face draws about 0.73 of it. Round one set the em
      // box to 124 px on a 1080 screen and called the floor met, and the ink on
      // the frame measured 91 px -- 8.4% of the screen, under the design's
      // tenth. The size below is derived from the ink the face actually draws,
      // so the rule holds at every screen size and in any font the shell hands
      // down.
      font.pixelSize: race.factPixelSize
      font.letterSpacing: race.px(6)
      style: Text.Outline
      styleColor: Qt.rgba(0, 0, 0, 0.85)
    }

    // The field. It is a readout, not something to type into: the digits the
    // child presses go through the engine and come back as `racer.entry`, so
    // there is no text-entry control anywhere in this game.
    Item {
      id: fieldBox
      // PIECE F. The two boxes the effect layer's guard band is measured
      // against, named so `dev/Harness.qml --dump-rects` prints them beside
      // every effect item's box and the two can be shown not to intersect.
      // The fact's own box is the INK, not this item, and it is `factInkProbe`
      // below.
      objectName: "answerField"
      anchors.horizontalCenter: parent.horizontalCenter
      width: race.px(214)
      height: race.px(98)

      // THE FIELD WAS A HOLE CUT IN THE SKY.
      //
      // `Theme.panelSunken` is the shell background driven to 0.22, which on
      // the tokyo-night the harness and the VM both hand down is rgb(6, 6, 8):
      // at 0.92 over a sunset the field measured #08080a on the shipped frame
      // -- a 214 x 98 near-black rectangle sitting on the horizon, a hand's
      // width from the sun, in the one part of the picture the direction says
      // is never black. It is the game layer, not the chrome the plan exempts,
      // and the light rule applies to it: a dark purple body with a warm rim
      // on the sun side, which is what every other object in this view has.
      //
      // The tone is the floor's own `#3c1228` driven down, so the field reads
      // as the same material as the road it belongs to rather than as a hole,
      // and the top edge carries the rim `#f0b07a` the sun would put on it.
      Rectangle {
        id: fieldFace
        anchors.fill: parent
        radius: Theme.cornerRadiusSmall
        // THE FIELD YIELDS FOR THE FRAME.
        //
        // Plan v2's remedy for road-spanning props against the fixed answer
        // field, taken as written. `TrackView.fieldYield` is 1 while a gantry
        // or a roller door's crossbar is over this box, and for that second or
        // so the FACE goes -- the ground, the border and the sun rim -- while
        // the digits, the caret and the reveal above stay at full strength.
        // Nothing the child typed moves or disappears; what goes is the slab
        // the arch was being sliced by, so the landmark passes over the screen
        // whole. The floor of 0.06 keeps a whisper of the box on screen so it
        // never reads as having been deleted.
        opacity: Math.max(0.06, 1 - track.fieldYield)
        // 0.74, not opaque: enough of the sunset comes through that the field
        // reads as smoked glass in front of the sky rather than as a slab cut
        // out of it, and `Theme.amberGlow` digits at 72 px still stand at more
        // than five to one against it. Measured on the shipped frame in the
        // evidence, with the empty field and with four digits in it.
        color: Qt.rgba(0.157, 0.055, 0.125, 0.74)
        border.width: 2
        border.color: reveal.active ? Theme.teal
                                    : (race.stalled ? Theme.hazard : Theme.focusRing)

        Behavior on border.color {
          enabled: !race.reducedMotion
          ColorAnimation { duration: 160 }
        }

        // The rim the one key light puts on the field's upper edge. `#f0b07a`
        // is the palette's rim tone; it is on the top because the sun is low
        // and behind, so its light lands on what faces up and away.
        Rectangle {
          x: fieldFace.radius
          y: 2
          width: parent.width - fieldFace.radius * 2
          height: Math.max(1, race.px(2))
          color: Qt.rgba(0.941, 0.690, 0.478, 0.42)
        }
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        visible: !reveal.active
        text: race.shownEntry + (caret.on ? "_" : " ")
        color: Theme.amberGlow
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: race.fs(72)
        font.letterSpacing: race.px(4)
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        visible: reveal.active
        text: reveal.text
        color: reveal.tone
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: race.fs(52)
        font.letterSpacing: race.px(2)
      }

      // ------------------------------------------------------------ PIECE F
      //
      // "The answer field locks with a mechanical overlay of bolts that spin
      // off over the stall duration (2 s, 3 s for a Wrench) so the lock reads
      // as a thing happening, not a bug."
      //
      // Four bolts, one per corner of the field, spinning and then flying off
      // as the stall runs out. The stall's length is the ENGINE's -- it comes
      // off the `hit` event that caused it, and `stalledUntilMs` is the engine's
      // own deadline -- so the last bolt leaves on the frame the field comes
      // back, whatever the card was and whatever the rules say next.
      //
      // They are at the CORNERS and outside the digits' box on purpose: the
      // field is the child's, and a lock drawn over the number they typed would
      // be the third thing this screen has done that hides what a child is
      // looking at. Under reduced motion they do not spin or fly; they are four
      // bolts that go out one at a time, which is the same countdown as a state
      // change rather than as a movement.
      Repeater {
        model: 4

        Item {
          readonly property real u: race.stallProgress
          // Each bolt leaves a quarter of the stall after the one before it.
          readonly property real mine: Math.max(0, Math.min(1, (u - index * 0.22) / 0.34))
          readonly property real cx: (index % 2 === 0 ? 1 : -1)
          readonly property real cy: (index < 2 ? 1 : -1)
          readonly property real d: race.px(13)

          visible: race.stalled && mine < 1
          width: d
          height: d
          x: (index % 2 === 0 ? race.px(7) : fieldBox.width - d - race.px(7))
             + (race.reducedMotion ? 0 : cx * mine * mine * race.px(90))
          y: (index < 2 ? race.px(7) : fieldBox.height - d - race.px(7))
             + (race.reducedMotion ? 0 : -cy * mine * mine * race.px(70))
          opacity: 1 - mine
          rotation: race.reducedMotion ? 0 : (u * 900 + index * 40)

          // A hex head: a square with its corners cut by a rotated square over
          // it, which is as much of a bolt as thirteen pixels can be.
          Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.hazard
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.55)
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.42
            height: race.px(2)
            color: Qt.rgba(0, 0, 0, 0.65)
          }
        }
      }

      // Design, The answer loop 4: a 500 ms sputter, and nothing else. No
      // message, no red mark, no reveal -- the field shakes the way an engine
      // coughs and the streak is gone.
      SequentialAnimation {
        id: sputter
        running: false
        loops: 4
        NumberAnimation { target: fieldBox; property: "x"; to: race.reducedMotion ? 0 : -race.px(7); duration: 62 }
        NumberAnimation { target: fieldBox; property: "x"; to: race.reducedMotion ? 0 : race.px(7); duration: 62 }
        onFinished: fieldBox.x = 0
      }
    }
  }

  // The blink is on a timer rather than an animation so it is exactly 1.25 Hz
  // whatever the frame rate is, which keeps it under the design's 3 Hz cap.
  QtObject {
    id: caret
    property bool on: true
  }

  Timer {
    interval: 400
    repeat: true
    // Wall-time, so it stops under an external clock and the caret is drawn in
    // the same state on every frame of a strip. 1.25 Hz in play, well under the
    // design's 3 Hz cap.
    running: race.visible && !race.externalClock
    onTriggered: caret.on = !caret.on
  }

  QtObject {
    id: reveal
    property string text: ""
    property color tone: Theme.teal
    property bool active: false

    function show(message, holdMs, colour) {
      reveal.text = message
      reveal.tone = colour
      reveal.active = true
      revealHold.interval = holdMs
      revealHold.restart()
    }
    function clear() {
      reveal.active = false
      revealHold.stop()
    }
  }

  Timer {
    id: revealHold
    onTriggered: {
      reveal.active = false
      // The field is back. Anything the child pressed into the window it was
      // gone for is replayed now, against the fact they can finally see.
      race.releaseReveal()
    }
  }

  // ------------------------------------------------------------- callouts
  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    // PIECE F. The engine-hit band lives on this exact line and is drawn over
    // the callouts, so `ENGINE HIT · 3s` used to sit on top of `WRENCH ◂ BOLT`
    // -- the two halves of one event, printed over each other, on the frame a
    // child most needs to read them. The callouts step down while the band is
    // up and step back when it goes.
    y: question.y + question.height + race.px(22)
       + (race.stalled ? race.px(64) : 0)
    spacing: race.px(8)

    Repeater {
      id: calloutSlots
      model: 3

      Callout {
        anchors.horizontalCenter: parent.horizontalCenter
        // PIECE F. The large type Pile-Up reserves needs a box to sit in; every
        // other callout is the height it always was.
        height: race.px(big ? 74 : 46)
        width: implicitWidth
        holdMs: Engine.CALLOUT_MS
        // The fade is wall-time, so under an external clock it is a cut. See
        // `externalClock` above.
        reducedMotion: race.reducedMotion || race.externalClock
      }
    }
  }

  // ------------------------------------------------------- engine-hit band
  // Design, The answer loop 8: an unblocked Wrench, Pothole or Pile-Up locks
  // the field for two or three seconds with the engine-hit banner.
  Rectangle {
    visible: race.stalled
    anchors.horizontalCenter: parent.horizontalCenter
    y: question.y + question.height + race.px(22)
    width: stallText.implicitWidth + race.px(44)
    height: race.px(52)
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(0, 0, 0, 0.80)
    border.width: 2
    border.color: Theme.hazard
    z: 6

    Text {
      id: stallText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "ENGINE HIT  ·  " + (race.human
            ? Math.max(0, Math.ceil((race.human.stalledUntilMs - race.nowMs) / 1000)) : 0) + "s"
      color: Theme.hazard
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: race.fs(24)
      font.letterSpacing: 2
    }
  }

  // --------------------------------------------- charge, and the one picker
  //
  // ROUND 2 -- ONE PANEL, NOT TWO. This file used to draw its own hand panel
  // here while `ui/Picker.qml` sat unused beside it, and the two disagreed on
  // everything that mattered. The inline panel printed `HAND`, three keycaps and
  // a bare `◂ NAME ▸ ⏎` and taught a child none of the keys; it had no footer
  // and no way at all to find out that Backspace was the key that saved a
  // streak. `ui/Picker.qml` prints the keys on every frame, names the effect and
  // the tier of every card, marks the aim with an arrow rather than a colour,
  // and says so when a card cannot be spent. The inline panel is gone and this
  // is the plan's shape: the picker is the panel, and the race screen drives it.
  //
  // The race screen keeps every key. The picker's own `Keys` handler is intact
  // for the harness, but here it never has focus -- `keys` above does -- because
  // the digit arbitration needs the expected answer and only this file has it.
  Picker {
    id: picker
    anchors.fill: parent
    hand: race.hand
    rivals: race.liveRivals
    entryLength: race.shownEntry.length
    // PIECE F. The panel's three beats -- the deal, the breath and the slam --
    // run on the effect clock, not on a timer of their own, so the hand and the
    // road are the same event and a frame strip catches both.
    fxNow: track.fxClock
    reducedMotion: race.reducedMotion
    // The override the picker documents: the digits the card press itself put
    // in the field are not an answer the child is part-way through, so Enter
    // still spends. A DEFERRED digit is the exception, and it is why this reads
    // `shownEntry` rather than the engine's entry: that digit might be the
    // child's answer, so Enter belongs to it until Backspace or Enter settles
    // it.
    enterSpends: race.enterSpendsCard() || race.shownEntry.length === 0
    // ROUND 4. The panel could not print the way back because it was never told
    // there was one: `enterSpends` alone says "Enter is not yours", which is
    // what produced `FINISH THE ANSWER FIRST` and nothing else. The parked digit
    // itself goes down now, so the footer can name Backspace, and say what Enter
    // would send if the child chose it.
    pendingDigit: race.pending
    dockWidth: race.px(500)
    dockMargin: race.px(30)
    // PIECE F. The hand outlives itself for the length of the slam: spending a
    // card empties the hand on the frame the child presses Enter, so a panel
    // bound to `hand.length > 0` alone took the cards off the screen before the
    // beat that shows them going. `picker.slamming` is the panel's own answer
    // to "am I still drawing the hand that just went", and this binding used to
    // override it -- the Picker's default already had it right.
    visible: race.hand.length > 0 || picker.slamming
    onCardUsed: function (index, targetId) {
      race.send({ "kind": "useCard", "index": index, "targetId": targetId })
    }
  }

  // The charge sits directly above the picker's dock, so the two read as one
  // right-hand column and neither is ever drawn over the other.
  ChargeBar {
    id: charge
    anchors.right: parent.right
    anchors.rightMargin: race.px(30)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: race.px(28)
                          + (picker.visible ? picker.dockHeight + race.px(16) : 0)
    width: race.px(500)
    value: race.human ? Math.min(race.state.streakThreshold, race.human.streak) : 0
    segments: race.state ? race.state.streakThreshold : Engine.CHARGE_SEGMENTS
    glowFrom: Engine.CHARGE_GLOW_FROM
    // The caption's 1.25 Hz breath is a wall-clock animation, so it is cut
    // under an external clock for the same reason the caret's blink is.
    reducedMotion: race.reducedMotion || race.externalClock
    holdingHand: race.hand.length > 0
    // PIECE F: "the charge bar flashes, the twelve segments burst".
    fxNow: track.fxClock
    cellHeight: race.px(24)
    cellGap: race.px(4)
    titleSize: race.fs(14)
    // The gauge face's padding, on the same scale as the readouts along the
    // top: the charge is an instrument like the rest and now reads like one.
    padX: race.px(16)
    padY: race.px(12)
    visible: race.state ? race.state.powerupsEnabled : false
  }

  // ------------------------------------------------------------ pit crew
  // Always available, and it says so, because the design's fairness list makes
  // it a promise: "A child can never be trapped on a fact."
  Text {
    anchors.left: parent.left
    anchors.leftMargin: race.px(30)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: race.px(28)
    textFormat: Text.PlainText
    text: "H  PIT CREW"
    color: Theme.textLabel
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: race.fs(17)
    font.letterSpacing: 2
  }
}
