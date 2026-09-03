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
  readonly property int lapsDone: human ? human.lapsComplete : 0
  readonly property int totalLaps: state ? state.totalLaps : 12
  readonly property string tableName: (state && human) ? Engine.currentTableName(state, human) : ""
  readonly property int place: {
    if (!state)
      return 1
    var order = Engine.raceOrder(state)
    var at = order.indexOf(state.humanId)
    return at < 0 ? order.length : at + 1
  }
  readonly property int elapsedMs: state ? Math.max(0, nowMs - state.startedAtMs) : 0
  readonly property bool stalled: (state && human) ? Engine.isStalled(human, nowMs) : false

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

    race.viewProgress = progress[0]
    race.smoothProgress = progress.slice()
    track.humanProgress = progress[0]
    track.setProgress(progress)
  }

  Component.onCompleted: buildRace()
  onSeedChanged: if (state) buildRace()

  // --------------------------------------------------------- the reducer
  function apply(result) {
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
    race.state = moved.state
    race.rivals = moved.rivals
    handleEvents(moved.events)
  }

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
      case "cardUsed":
        if (e.racerId === me) {
          picker.reset()
          var label = Engine.CARDS[e.card].label.toUpperCase()
          say(e.targetId === "" ? label : label + " ▸ " + nameOf(e.targetId), Theme.amber)
          if (e.card === "turbo" || e.card === "nitro")
            track.throwForward(e.card === "turbo" ? 1.0 : 0.55)
        }
        break
      case "handDealt":
        if (e.racerId === me)
          picker.reset()
        break
      case "hit":
        if (e.racerId === me) {
          if (e.questionDelta > 0) {
            track.pullBack(Math.min(1, 0.35 + e.questionDelta / 18))
            say(Engine.CARDS[e.card].label.toUpperCase() + " ◂ " + nameOf(e.fromId), Theme.urgent)
          }
        }
        break
      case "blocked":
        if (e.racerId === me)
          say("ROLL CAGE HELD", Theme.teal)
        break
      case "swap":
        if (e.racerId === me || e.withId === me)
          say("TOW HOOK ▸ " + nameOf(e.racerId === me ? e.withId : e.racerId), Theme.amber)
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
  function say(message, tone) {
    for (var i = 0; i < calloutSlots.count; i++) {
      var slot = calloutSlots.itemAt(i)
      if (slot && !slot.showing) {
        slot.say(message, tone)
        return
      }
    }
    var first = calloutSlots.itemAt(0)
    if (first)
      first.say(message, tone)
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

  FrameAnimation {
    id: frames
    running: race.visible
    onTriggered: race.frame(frameTime * 1000)
  }

  function frame(dtMs) {
    if (!state)
      return
    race.nowMs = clockNow()

    var lerp = race.reducedMotion ? 1 : Math.min(1, dtMs / 190)
    var values = []
    var targets = []
    var before = race.viewProgress
    for (var i = 0; i < state.racers.length; i++) {
      var target = Engine.effectiveProgress(state.racers[i], state.questionsPerLap)
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
    track.setProgress(values, Engine.raceOrder(state), targets)

    // Speed is effective-progress rate, in questions per second, plus the
    // idle roll: the design has the kart rolling while the child is thinking.
    var rate = dtMs > 0 ? (race.viewProgress - before) / dtMs * 1000 : 0
    var want = Math.max(0, Math.min(1, 0.30 + rate * 0.75 - (race.stalled ? 0.26 : 0)))
    race.smoothSpeed = race.smoothSpeed * 0.90 + want * 0.10
    track.speed = race.smoothSpeed

    // A pass is announced on the frame the karts cross, not the frame the
    // engine's order flips.
    race.releasePasses()

    track.advance(dtMs)
  }

  // ---------------------------------------------------------- the engine
  // 100 ms: the race clock, the rival deadlines and the stall expiries. The
  // design is explicit that the race clock is the only clock in the game.
  Timer {
    id: pulse
    interval: 100
    repeat: true
    running: race.visible && race.state !== null
    onTriggered: {
      race.nowMs = race.clockNow()
      apply(Engine.step(race.state, { "kind": "tick" }, race.nowMs))
      advanceRivals()
      race.refreshMap()
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
  }

  // A vignette, so the HUD sits on something and the road falls away at the
  // edges the way a headlight beam does.
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
      GradientStop { position: 0.30; color: Qt.rgba(0, 0, 0, 0.06) }
      GradientStop { position: 0.80; color: Qt.rgba(0, 0, 0, 0.0) }
      // 0.42 here was the whole "per-band brightness sawtooth" a critic
      // measured on the road: the road alone swings 1.3% within a rumble
      // band, this vignette took the composited frame to 37.7%.
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
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

    Item {
      width: tableBlock.width
      height: lapGauge.height

      Column {
        id: tableBlock
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
          lit: race.human ? race.human.correctInLap : 0
          total: race.human ? Math.max(1, race.human.questionsNeededThisLap) : 12
          cleanTotal: race.state ? race.state.questionsPerLap : 12
          cell: race.px(13)
          gap: race.px(4)
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
        reducedMotion: race.reducedMotion
        sectors: race.totalLaps
        activeSector: race.lapsDone + 1
        dotSize: race.px(20)
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
    var order = Engine.raceOrder(state)
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

  // ------------------------------------------------------- fact and field
  // Design, Pillars: "The question is the track. The fact is the largest thing
  // on screen at every moment of a race." It is, and it sits above the horizon
  // so it is never over a kart.
  Column {
    id: question
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
      anchors.horizontalCenter: parent.horizontalCenter
      width: race.px(214)
      height: race.px(98)

      Rectangle {
        id: fieldFace
        anchors.fill: parent
        radius: Theme.cornerRadiusSmall
        color: Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g, Theme.panelSunken.b, 0.92)
        border.width: 2
        border.color: reveal.active ? Theme.teal
                                    : (race.stalled ? Theme.hazard : Theme.focusRing)

        Behavior on border.color {
          enabled: !race.reducedMotion
          ColorAnimation { duration: 160 }
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
    running: race.visible
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
    y: question.y + question.height + race.px(22)
    spacing: race.px(8)

    Repeater {
      id: calloutSlots
      model: 3

      Callout {
        anchors.horizontalCenter: parent.horizontalCenter
        height: race.px(46)
        width: implicitWidth
        holdMs: Engine.CALLOUT_MS
        reducedMotion: race.reducedMotion
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
    visible: race.hand.length > 0
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
    reducedMotion: race.reducedMotion
    holdingHand: race.hand.length > 0
    cellHeight: race.px(24)
    cellGap: race.px(4)
    titleSize: race.fs(14)
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
