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
        if (e.racerId === me)
          reveal.show(Engine.factLabel(e.fact) + " = " + e.answer, e.revealMs, Theme.teal)
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
    // 2.8s, longer than a callout lives -- and the ladder could read
    // "3rd YOU / 4th GASKET" with Gasket drawn in front. The exact targets go
    // with it so a distance plate can print a gap that matches the ladder.
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
  //   With a hand held and the field empty, a press of 1, 2 or 3 is read
  //   against the answer that is on screen right now.
  //
  //   a. The answer is one digit and the key IS that answer (`1 x 1`, press 1).
  //      The press is unambiguously the answer. It types, the engine submits it,
  //      the child is right, and the hand is not touched.
  //   b. The answer is one digit and the key is NOT that answer (`1 x 6`, press
  //      1). Typing it would submit a wrong answer the instant it landed, which
  //      no child ever means to do, so it chooses the card and types nothing.
  //   c. The answer is two digits or more (`1 x 10`, press 1). It chooses the
  //      card AND types the digit, because the child may well be starting to
  //      type `10`. Nothing is submitted -- the entry is short -- and the digit
  //      is held as PROVISIONAL: it belongs to the card press, not to an answer.
  //
  //   Enter then decides, and `provisional` is what it decides on. If every
  //   character in the field was typed by the press that chose the card, the
  //   child meant the card: the digits are taken back with the engine's own
  //   backspace and the card is played. If the child typed anything of their
  //   own after choosing, the field is an answer and Enter submits it.
  //
  //   Escape takes the provisional digits back too, which is the other half of
  //   the same fix: round one left a stray `1` in the field after Escape, so the
  //   next digit the child typed was appended to a `1` they thought they had
  //   just undone.
  //
  // Nothing is ever spent by a keystroke that was meant as a digit, and no
  // answer in the tables has become untypable while a hand is held.
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
        if (picker.chosen >= 0) {
          race.takeBackProvisional()
          picker.reset()
        } else {
          race.leaveRequested()
        }
        event.accepted = true
        return
      }

      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        if (race.enterSpendsCard()) {
          race.takeBackProvisional()
          picker.confirm()
        } else if (race.entryLength() > 0) {
          race.clearProvisional()
          picker.reset()
          race.send({ "kind": "submit" })
        } else if (picker.chosen >= 0) {
          picker.confirm()
        }
        event.accepted = true
        return
      }

      if (key === Qt.Key_Backspace) {
        // A backspace of the child's own retires the provisional claim: what is
        // left in the field is theirs now.
        race.clearProvisional()
        race.send({ "kind": "backspace" })
        event.accepted = true
        return
      }

      if (key === Qt.Key_H) {
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

  function clearProvisional() { race.provisional = 0 }

  function entryLength() { return race.human ? race.human.entry.length : 0 }

  // The answer to the question on screen, as the string the child has to type.
  function expectedAnswer() {
    if (!race.human || race.human.currentFact < 0)
      return ""
    return String(Engine.factAnswer(race.human.currentFact))
  }

  // Enter spends the card exactly when the field holds nothing but the digits
  // the card press put there.
  function enterSpendsCard() {
    if (picker.chosen < 0)
      return false
    return race.entryLength() === race.provisional
  }

  function takeBackProvisional() {
    while (race.provisional > 0 && race.entryLength() > 0) {
      race.send({ "kind": "backspace" })
      race.provisional -= 1
    }
    race.provisional = 0
  }

  function typeKey(digit) {
    var typed = race.entryLength()
    var holding = race.hand.length >= digit
    if (digit >= 1 && digit <= 3 && typed === 0 && holding) {
      var expected = race.expectedAnswer()
      if (expected.length === 1) {
        if (expected === String(digit)) {
          // (a) the key is the answer. Type it and leave the hand alone.
          race.clearProvisional()
          race.send({ "kind": "digit", "value": digit })
          return
        }
        // (b) typing it would submit a wrong answer on the spot. Choose only.
        race.clearProvisional()
        picker.choose(digit - 1)
        return
      }
      // (c) two digits or more to come: choose, type, and hold the digit as
      // provisional so Enter can give it back.
      picker.choose(digit - 1)
      race.send({ "kind": "digit", "value": digit })
      race.provisional = race.entryLength()
      return
    }
    // A digit of the child's own, typed on top of something already in the
    // field. They are answering, not spending: the field is theirs from here,
    // and the card the first press chose is put back rather than left selected
    // under an Enter that would spend it once the answer clears the field.
    if (typed > 0) {
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

  // ---------------------------------------------------- the position ladder
  //
  // Design, the comparison table: "Looking down the track, positions visible at
  // a glance." At a glance was doing no work. The HUD said `PLACE 2nd` and the
  // minimap put four dots on one loop, and in the first seconds of a race those
  // dots sit on top of one another; between the left readouts and the minimap
  // ran 890 px of nothing. A critic's verdict on the whole screen was that you
  // cannot see the race.
  //
  // This is the standings, in the strip that was empty. It invents nothing: the
  // order is `Engine.raceOrder`, and the gap is the difference in effective
  // progress, which the design defines as position itself -- "Position is
  // effective progress". The number is therefore in questions, which is the
  // unit the child is already counting in, and it is the same number the karts
  // on the road are drawn from.
  //
  // It appears only when there is somebody to be ahead of or behind. In the
  // three solo modes the strip stays empty, because there are no positions and
  // a ladder of one would be furniture.
  readonly property var ladder: {
    var out = []
    if (!state || state.racers.length < 2)
      return out
    var order = Engine.raceOrder(state)
    var mine = 0
    for (var h = 0; h < state.racers.length; h++)
      if (state.racers[h].id === state.humanId)
        mine = Engine.effectiveProgress(state.racers[h], state.questionsPerLap)
    for (var i = 0; i < order.length; i++) {
      var index = race.indexOfRacer(order[i])
      if (index < 0)
        continue
      var racer = state.racers[index]
      out.push({
        "place": i + 1,
        "name": race.nameOf(racer.id),
        "number": race.numberOf(racer),
        "paint": race.paintOf(racer),
        "isHuman": racer.kind === "human",
        "finished": racer.finished === true,
        "gap": Engine.effectiveProgress(racer, state.questionsPerLap) - mine
      })
    }
    return out
  }

  Item {
    id: ladderStrip
    x: leftHud.x + leftHud.width + race.px(26)
    y: race.px(24)
    width: Math.max(0, rightHud.x - x - race.px(26))
    height: race.px(62)
    visible: race.ladder.length > 1

    Accessible.role: Accessible.StaticText
    Accessible.name: "Race order"

    Row {
      anchors.centerIn: parent
      spacing: race.px(10)

      Repeater {
        model: race.ladder

        Rectangle {
          readonly property bool self: modelData.isHuman === true
          height: race.px(54)
          width: rung.width + race.px(22)
          radius: Theme.cornerRadiusSmall
          color: self ? Theme.focusFill
                      : Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.80)
          border.width: self ? 2 : 1
          border.color: self ? Theme.focusRing : Theme.line

          Accessible.role: Accessible.StaticText
          Accessible.name: Engine.ordinal(modelData.place) + ", " + modelData.name
                           + (modelData.finished
                              ? ", home"
                              : (modelData.gap === 0
                                 ? ""
                                 : (modelData.gap > 0
                                    ? ", " + modelData.gap + " questions ahead of you"
                                    : ", " + (-modelData.gap) + " questions behind you")))

          Row {
            id: rung
            anchors.centerIn: parent
            spacing: race.px(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Engine.ordinal(modelData.place)
              color: Theme.textLabel
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: Math.max(11, race.fs(15))
              font.letterSpacing: 1
            }

            // The kart's own number plate, in the kart's own paint, so the
            // rung and the kart on the road are the same object.
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(race.px(30), plate.implicitWidth + race.px(10))
              height: race.px(26)
              radius: race.px(3)
              color: modelData.paint

              Text {
                id: plate
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(modelData.number)
                color: Theme.ink(modelData.paint)
                font.family: Theme.mono
                font.bold: true
                font.pixelSize: Math.max(11, race.fs(16))
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.name
              color: parent.parent.self ? Theme.amberGlow : Theme.textBright
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: Math.max(12, race.fs(18))
              font.letterSpacing: 1
            }

            // The gap, in questions, with an arrow so it is shape as well as
            // colour. The child's own rung has no gap to itself.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              visible: text.length > 0
              text: {
                if (modelData.isHuman === true)
                  return ""
                if (modelData.finished === true)
                  return "HOME"
                if (modelData.gap === 0)
                  return "LEVEL"
                return (modelData.gap > 0 ? "\u25B2 " : "\u25BC ") + Math.abs(modelData.gap)
              }
              color: modelData.finished === true
                     ? Theme.teal
                     : (modelData.gap > 0 ? Theme.hazard : Theme.lime)
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: Math.max(11, race.fs(16))
              font.letterSpacing: 1
            }
          }
        }
      }
    }
  }

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
    minimap.setProgress(values)
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
        text: (race.human ? race.human.entry : "") + (caret.on ? "_" : " ")
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
    onTriggered: reveal.active = false
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
    entryLength: race.entryLength()
    // The override the picker documents: the digits the card press itself put
    // in the field are not an answer the child is part-way through, so Enter
    // still spends.
    enterSpends: race.enterSpendsCard() || race.entryLength() === 0
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
