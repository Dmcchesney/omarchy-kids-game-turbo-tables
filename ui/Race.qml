import QtQuick
import "parts"
import "parts/Circuit.js" as Circuit
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
  // walkthrough has to be able to ask which card is highlighted, who is aimed
  // at and what the panel is printing, and reading it off the panel is the only
  // way to check the screen rather than a second copy of its state. Nothing
  // outside drives it; the key handler below is the only caller.
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

  // UNDER AN EXTERNAL CLOCK THE FRAME ANIMATION CONTRIBUTES NOTHING.
  //
  // ROUND 2. `frames` is stopped when `externalClock` is set, but a stopped
  // FrameAnimation keeps whatever `elapsedTime` it had reached before it was
  // stopped -- a fraction of a millisecond, on the frame between the screen
  // loading and the harness setting the flag. That fraction reached the race
  // clock, and one strip in eighteen came back different bytes: the answer
  // field's lock tint is a lerp on `stallProgress`, so a sub-millisecond
  // difference in `nowMs` moved a blend by one part in 255 over the field's
  // box and nowhere else. 1236 pixels, all inside (853,309,214,98). A strip
  // that differs run to run is not evidence, so the residue is cut off at the
  // source rather than rounded away downstream.
  function clockNow() {
    return race.externalClock ? clockBase : clockBase + frames.elapsedTime * 1000
  }

  function nameOf(racerId) {
    if (!state)
      return ""
    if (racerId === state.humanId)
      return "YOU"
    for (var i = 0; i < state.racers.length; i++)
      if (state.racers[i].id === racerId)
        return Theme.rivalFace(state.racers[i].seat).name
    return ""
  }

  // WHICH CAR A RIVAL IS: `Theme.rivalFace`, because the countdown stands the
  // same field on the same grid one second earlier and two copies of these
  // three expressions is how two screens come to hold different races.
  function paintOf(racer) {
    if (racer.kind === "human")
      return Theme.paint(Store.setting("kartPaint"))
    return Theme.rivalFace(racer.seat).paint
  }
  function numberOf(racer) {
    if (racer.kind === "human")
      return Store.setting("kartNumber")
    return Theme.rivalFace(racer.seat).number
  }
  function bodyOf(racer) {
    if (racer.kind === "human")
      return Store.setting("kartBody")
    return Theme.rivalFace(racer.seat).body
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
    race.pendingSay = []
    race.echoHold = null
    race.priorState = null
    race.mapDue = 0

    race.viewProgress = progress[0]
    race.smoothProgress = progress.slice()
    track.humanProgress = progress[0]
    track.setProgress(progress)
    // WHERE A RACE OPENS. It is the start line, and until this line existed it
    // was a rock quarry: see `startTravel` above.
    track.travel = race.startTravel
  }

  // ============================================ WHERE A RACE OPENS, AND IT IS
  // ============================================ THE PLACE THE COUNTDOWN PAINTS
  //
  // THE BUG THIS ANSWERS. `ui/TrackView.qml` declares `property real travel:
  // 120`, `advance()` only ever adds to it, and this file never assigned it --
  // the word did not appear anywhere in it. 120 is a good REDUCED-MOTION STILL
  // and the comment at that line says so in as many words: a third of the way
  // into sector 3's left-hander, "a road in a corner rather than a ruler",
  // chosen by a round that needed one frame to look at. Nothing then moved it
  // back for the start of a race.
  //
  // So the cut a child actually got was: `GO`, over a start line under a
  // chequered gantry, and then one frame later a rock quarry -- polygonal walls
  // both sides, a `200` distance board, three rivals abreast on a curve, no
  // gantry, no chequer, no crowd -- with the clock reading `TIME 0:00`. It is
  // not two views of one place; it was two places, and it shipped that way
  // through six rounds because the harness always passes `--travel` explicitly,
  // so nobody ever rendered the frame a race actually opens on.
  //
  // WHY -6.5 AND NOT 0. `Circuit.PLACEMENTS` stands the start gantry at s = 3.5
  // and the shader paints the start grid at s = 2..5; the camera carries the
  // child's kart `TrackView.playerZ` = 3.20 units ahead of itself. Four values
  // were rendered as this screen's own first frame and measured:
  //
  //     travel   the arch's drawn box, 1920 x 1080       what the frame is
  //     -----    ---------------------------------       -----------------
  //        0     2209 wide, box top at y = -199           under the arch, no sky
  //     -3.0     1190 wide, board across the fact         the fact over the sign
  //     -5.0      910 wide, board still under the fact    the fact over the sign
  //     -6.5      773 wide, board clear below the fact    the countdown's frame
  //
  // At -6.5 the arch is whole and ahead with `TURBO TABLES` legible under the
  // fact rather than behind it, the chequered grid is a band of road ahead of
  // the field, the crowd, the tyre walls and the `P1` pit board are along both
  // sides, and the sun sits to the right of the arch where the countdown's sun
  // is. The countdown's own gantry is 521 px in the same frame, so the two
  // screens now differ by half an arch rather than by a rock quarry. The first
  // thing the child does is cross the line under the sign.
  //
  // NEGATIVE IS NOT A SPECIAL CASE. Everything downstream of `travel` wraps the
  // circuit: `Terrain.sectorBlend` and `sectorMix` fold any real into 0..432,
  // and `propZ` folds a negative difference back into the loop. -3.0 and 429.0
  // are the same place by every one of them; the negative is written because
  // `travel` is monotonic from here and crossing zero IS crossing the line.
  //
  // `tests/qml/tst_race_start.qml` renders this screen's own first frame and
  // asserts what is in it, because every previous round's evidence was a frame
  // somebody had passed a travel to.
  //
  // ROUND 3 MOVED THE NUMBER TO THE CIRCUIT. The countdown stands at this exact
  // camera for the second before this screen exists, so -6.5 written here and
  // -6.5 written there is two screens agreeing by coincidence. It is
  // `Circuit.START_TRAVEL` now -- the circuit says where a race opens on it,
  // once -- and the table of rendered arch boxes that chose the value moved
  // with it.
  readonly property real startTravel: Circuit.START_TRAVEL

  // WHERE THE CAMERA ACTUALLY IS, published so a spec can read it back off the
  // running screen rather than off this file's own constant. The two are only
  // equal if `buildRace()` assigned it, which is the whole defect: `startTravel`
  // could have been right and unassigned and nothing would have noticed.
  readonly property real trackTravel: track.travel
  // The other two numbers a cut is measured by. `ui/Countdown.qml` stands at
  // this camera for the second before this screen exists, and
  // `tests/qml/tst_race_start.qml` compares the pair off the two RUNNING
  // screens rather than off a shared constant -- a constant proves nothing if
  // one of the two files stops reading it, which is exactly how `travel: 120`
  // survived six rounds.
  readonly property real trackHorizon: track.horizon
  readonly property real archLeftX: track.startArchBox.x

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
    // If the reveal that was covering the line has just gone, the keys the
    // child pressed into it are replayed here rather than inside
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
          // PIECE T. THE BILLBOARDS IN SECTOR 11.
          //
          // Design v4, The circuit: "a row of boards that show the last three
          // facts the child got right, painted on", and, of the same three
          // boards, "the passion-project idea I would fight for: the
          // environment shows the child their own answers on the way to the
          // finish. It is decoration that teaches."
          //
          // This is the whole of the feed. Most recent first, three kept, and
          // the source is the engine's own `correct` event -- so a board can
          // only ever carry a fact this child actually got right, in the
          // engine's own words (`factLabel` is what the fact panel prints).
          // No free text ever reaches it, which is the design's rule, and
          // nothing here is persisted: the boards are blank again next race.
          //
          // Written as a push loop rather than `[new].concat(old).slice(0, 3)`
          // because `check:readme` refuses `Array.prototype.concat` in a plugin
          // file on sight -- "a plugin file in this repository has no reason to
          // build a name, a URL or an object at runtime; whatever it spells,
          // the shape is the defect" -- and the gate is right to be blunt about
          // it even here, where what is being assembled is three sums.
          var boards = [Engine.factLabel(e.fact) + " = " + e.answer]
          for (var b = 0; b < race.factBoards.length && boards.length < 3; b++)
            boards.push(race.factBoards[b])
          race.factBoards = boards
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
          reveal.show(Engine.factLabel(e.fact), String(e.answer), e.revealMs, Theme.teal)
          // The field is the child's and this took it away from them mid-answer.
          // Everything they press until it comes back waits in `revealQueue`.
          race.revealHolds = true
        }
        break
      case "pitCrew":
        if (e.racerId === me)
          reveal.show(Engine.factLabel(e.fact), String(e.answer), 1200, Theme.teal)
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
          // POWER-UP READY reads once." The words are the charge bar's own
          // state (`ui/parts/ChargeBar.qml` prints them at twelve), not a
          // callout: design v4.1 gives the callout slot to the road's events.
          picker.deal()
          charge.burstNow()
          Sfx.play("deal")
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
          // A rival's attack breaking on the child's own cage. There is no
          // projectile to wait for -- the view does not draw a rival's throw --
          // so the verdict and the flash are the same frame.
          say("ROLL CAGE HELD", Theme.teal)
          track.fxBlockedMe(e.card, e.fromId)
        } else if (e.fromId === me) {
          // "the callout reads ROLL CAGE HELD on their side" -- ON THE FRAME
          // THE WRENCH ARRIVES. See `sayAtImpact`.
          sayAtImpact("ROLL CAGE HELD  ·  " + nameOf(e.racerId), Theme.teal)
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
  // child presses Space. Every event the strip reacts to is then the engine's
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

    // `fireCard:<n>` is not an engine event and does not pretend to be one:
    // it presses the keys. The hand's slam is a keyboard beat, so the only
    // honest way to shoot it is through the same functions a child's presses
    // reach -- Right until the highlight is on slot n, then Space, exactly as
    // this file's own handler calls them.
    if (kind === "fireCard") {
      var slot = Math.max(1, Math.min(3, parseInt(name || "1", 10)))
      if (race.hand.length < slot)
        return false
      while (picker.highlighted !== slot - 1)
        picker.moveHighlight(1)
      return race.fireKey()
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
  // Design v4.1, The view: callouts for 1.6 s, ONE AT A TIME -- "a single slot
  // under the fact line, the newest replacing the last, never stacked over the
  // road". The maintainer counted four boxes in the child's eye line after one
  // hit (`docs/open-questions.md` §5.3); there is one `Callout` on this screen
  // now and `say` writes it.
  //
  // PIECE F -- `big` is the third argument and it is used by exactly one card.
  // Design v4, Pile-Up: "the callout is in the large type reserved for this
  // card." Reserved means reserved: `say(..., true)` is called from the
  // `cardUsed` branch for `pileUp` and from nowhere else in the file.
  //
  // A CALLOUT THAT BELONGS TO AN IMPACT WAITS FOR THE IMPACT. The `blocked`
  // event arrives in the same engine step as the `cardUsed` that caused it,
  // and the view queues the block's flash and ring behind the wrench's 500 ms
  // flight so the shatter happens where the wrench is. The words wait with
  // them: a payoff said first is not a payoff. Held here rather than inside
  // `say` because most callouts are NOT impacts: the card the child fired is
  // announced when they fire it, a pass when the karts cross, a rival's signal
  // when it is sent.
  property var pendingSay: []
  function sayAtImpact(message, tone, big) {
    if (!track.cueTelegraphing) {
      say(message, tone, big)
      return
    }
    var next = race.pendingSay.slice()
    next.push({ "message": message, "tone": String(tone), "big": big === true })
    race.pendingSay = next
  }
  function releaseSay() {
    for (var i = 0; i < race.pendingSay.length; i++) {
      var entry = race.pendingSay[i]
      say(entry.message, entry.tone, entry.big)
    }
    race.pendingSay = []
  }

  function say(message, tone, big) {
    callout.big = big === true
    callout.say(message, tone)
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

  // Design v4.1: "`PASSED BOLT` belongs there; `BOLT SLIPPED PAST` does not:
  // a pass by a rival is a tag on that rival's kart and a pulse of its dot on
  // the minimap, not a sentence." The words on the tag are the design's own
  // for the event, on the kart it happened to, for the callout's 1.6 s.
  function sayPass(entry) {
    if (entry.gained)
      say("PASSED " + nameOf(entry.otherId), Theme.lime)
    else
      track.fxPassedBy(indexOfRacer(entry.otherId), "SLIPPED PAST", Theme.hazard,
                       Engine.CALLOUT_MS)
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
  //
  // Design v4.1, in full: digits are only ever the answer; Enter is only ever
  // the answer key; Backspace edits it; `H` is the pit crew; Escape only ever
  // leaves the race. The hand is Left, Right, Up, Down and Space, and nothing
  // else. There is no field to type into: the entry is the engine's
  // `racer.entry` string, drawn on the answer line, and the digits go through
  // `step` like everything else.
  //
  // ---------------------------------------------------------------------------
  // PIECE F ROUND 7 -- THE DIGIT ARBITRATION IS GONE, AND THIS IS WHERE IT WAS
  // ---------------------------------------------------------------------------
  //
  // Four rounds of this file settled what a press of `1` meant while a hand was
  // held: a card, a digit, a provisional digit that the card press had put in
  // the field, a deferred digit parked on screen and kept from the engine
  // because sending it would submit a wrong answer, an Enter that meant the
  // card if every character in the field was the card press's own and the
  // answer otherwise, a Backspace that meant "it was a card", a reveal window
  // that queued all of it. Every branch was measured, every branch was right
  // about the branch before it, and the maintainer's verdict on the whole was
  // "launching a power up feels weird, I had to attempt to trigger it multiple
  // times" (`docs/open-questions.md` §5.2). A card key that is also a digit
  // cannot be made unambiguous on the 23 single-digit facts, and it was the
  // design's own key choice that made it one.
  //
  // So the design changed rather than the explanation. `provisional`,
  // `pending`, `takeBackProvisional`, `dropPending`, `flushPending`,
  // `enterSpendsCard`, `reconcileClaims`, `expectedAnswer` and the card
  // branches of `typeKey` are deleted, not disabled: there is no state on this
  // screen that a digit can leave behind, because a digit now goes to the
  // engine on the press, whatever the hand is doing. `tests/qml/tst_race_keys.qml`
  // is the record of what every key costs under the new rule, and the one row
  // the plan names -- `1` on `2 × 3` with a hand held is a wrong answer and no
  // card -- is its first case.
  //
  // WHAT THE REVEAL WINDOW STILL HOLDS. A second wrong answer shows the fact's
  // answer for 1500 ms while the engine has already moved the deck on, so a
  // digit pressed into that window would be scored against a question the
  // child cannot see. Those digits, and an Enter behind them, still wait in
  // `revealQueue` and are replayed the instant the line comes back. The hand's
  // keys do not wait: the hand is on screen throughout, and a card has nothing
  // to do with the fact behind it.

  /** Show this fact's answer and move on. `H`, and the printed `H` line. */
  function pitCrewRequested() {
    if (!race.state)
      return
    // The child's held keystrokes belong to the fact they were typed at, and
    // this moves the fact on.
    race.clearRevealQueue()
    race.send({ "kind": "hint" })
  }

  /** Leave the race. `Escape`, and the printed `ESC` line. Only ever this. */
  function leaveNow() {
    if (!race.state)
      return
    race.clearRevealQueue()
    race.leaveRequested()
  }

  // Space, from the key or from the hand panel's own `SPACE  USE IT` line:
  // fire the highlighted card. With no hand held it does nothing at all, and
  // nothing on screen changes -- `tests/qml/tst_race_keys.qml` asserts that
  // with a fingerprint of the race, not with an absence of an event.
  readonly property bool handHeld: race.hand.length > 0 && !picker.slamming

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
        // ONE MEANING, and the guard is the action's: `escape` is the name the
        // printed `ESC  LEAVE` line declares, so a click on it and this key
        // inside one double-click interval are one gesture whichever hand made
        // them. Key after key is not guarded -- a second Escape is a second
        // deliberate press -- and with one meaning there is nothing for a
        // lockout to defend anyway. See `ui/parts/Actions.qml`.
        if (!Actions.take(["escape"], "key")) {
          event.accepted = true
          return
        }
        race.leaveNow()
        event.accepted = true
        return
      }

      // ------------------------------------------------------ the hand's keys
      // Before the reveal window, on purpose: the hand is on screen throughout
      // a reveal and a card play has nothing to do with the fact behind it.
      if (key === Qt.Key_Left || key === Qt.Key_Right) {
        if (race.handHeld)
          picker.moveHighlight(key === Qt.Key_Left ? -1 : 1)
        event.accepted = true
        return
      }
      if (key === Qt.Key_Up || key === Qt.Key_Down) {
        if (race.handHeld && picker.targeting)
          picker.stepTarget(key === Qt.Key_Up ? -1 : 1)
        event.accepted = true
        return
      }
      if (key === Qt.Key_Space) {
        race.fireKey()
        event.accepted = true
        return
      }

      // ------------------------------------------------- the reveal window
      // While the line is showing a fact's answer back to the child, the deck
      // has already moved and the answer is not on screen. Keys that belong to
      // the answer wait here for it.
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
          // them.
          race.queueForReveal(-1)
          event.accepted = true
          return
        }
        // `H` is not handled here: it clears the queue inside
        // `pitCrewRequested()`, AFTER the guard below has decided whether this
        // press acts at all, so a refused press does not throw digits away.
      }

      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        race.submitKey()
        event.accepted = true
        return
      }

      if (key === Qt.Key_Backspace) {
        race.send({ "kind": "backspace" })
        event.accepted = true
        return
      }

      if (key === Qt.Key_H) {
        // The same guard the printed `H  PIT CREW` line takes, for the same
        // reason: this spends one of the child's questions and there is no
        // undo, so a press that is the tail of a press already made -- from
        // either hand -- does nothing.
        if (!Actions.take(["pitCrew"], "key")) {
          event.accepted = true
          return
        }
        race.pitCrewRequested()
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

  // Space. The same guard the panel's `SPACE  USE IT` chip declares, taken by
  // the key route, so a click on the chip and a press of the bar inside one
  // double-click interval are one gesture. With no hand there is nothing to
  // take and nothing is armed: a press that could not fire anything must not
  // refuse the child's next press either.
  function fireKey() {
    if (!race.handHeld)
      return false
    if (!Actions.take(picker.fireGuards, "key"))
      return false
    return picker.fire()
  }

  function entryLength() { return race.human ? race.human.entry.length : 0 }

  // What the answer field shows: the engine's entry, and nothing else. The
  // name survives from the rounds in which it was the entry plus a parked
  // digit; there is no parked digit any more, so it is the entry.
  readonly property string shownEntry: race.human ? race.human.entry : ""

  // THE LINE, AS IT READS. `7 × 8 = ▮` while the child is typing, `7 × 8 = 56`
  // through a reveal, `7 × 8 = 5▮` half-way. Published so a test and the
  // harness can assert what the child is looking at off the items that draw
  // it, rather than off a second copy of the state. The caret is drawn as a
  // block and read as `▮`; it is absent while the line is locked or revealed.
  readonly property string lineText: factWord.words + " "
                                     + answerWord.words + (caretMark.visible ? "▮" : "")
  // What the line is revealing, if anything: `7 × 8 = 56` for the reveal's
  // hold, "" otherwise. The pit crew's reveal and the wrong answer's both.
  readonly property string revealText: reveal.text

  // ------------------------------------------------------ the reveal window
  //
  // Design, The answer loop 5: a second wrong answer on the same fact "shows the
  // answer for a moment" and the deck moves on. The engine moves it in the same
  // step; the line on screen is handed over to `7 × 8 = 56` for 1500 ms. For
  // that window the child is being shown one thing and the engine is holding
  // another, and a key pressed into it went straight through: a digit landed
  // as an answer to a question whose line was not on screen.
  //
  // Keys that belong to the answer wait here instead and are replayed the
  // moment the line comes back, so they cost what they would have cost had the
  // child pressed them one beat later, and nothing is scored against a
  // question they were not being shown.
  //
  // The pit crew's reveal is deliberately NOT held. `H` is the child's own
  // request to be shown the answer and move on; holding their next keystroke
  // would put a 1.2 s wall in front of a key they pressed on purpose. Only the
  // reveal a wrong answer imposes takes the line away from a child who was in
  // the middle of using it.
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

  // Called the instant the reveal stops covering the line, by whichever of the
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
  // replays through exactly the branch a live press would have taken: the
  // answer, if there is one in the field, and nothing otherwise. It never
  // touches the hand.
  function submitKey() {
    if (race.entryLength() > 0)
      race.send({ "kind": "submit" })
  }

  // A digit. It goes to the engine, whatever the hand is doing: `typeDigit`
  // applies the leading-zero rule and submits the instant the entry is as long
  // as the answer, so a wrong `1` on `2 × 3` costs the streak and only the
  // streak, exactly as it does with no hand held.
  function typeKey(digit) {
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

  // The last three facts the child got right, most recent first, for the
  // billboards in sector 11. Filled by the `correct` case in `apply` above and
  // by nothing else; empty in the garage, in the countdown and in the harness,
  // where the boards stay blank cream as the kit baked them.
  property var factBoards: []

  TrackView {
    id: track
    anchors.fill: parent
    reducedMotion: race.reducedMotion
    // PIECE T. Golden hour passes over the twelve laps: the sun sinks, the
    // haze deepens, headlamps come on around lap 8 and the first stars are out
    // by lap 11. One number drives all of it, and it is the lap counter the
    // child is already reading.
    lap: race.lapsDone + 1
    lapCount: race.totalLaps
    factBoards: race.factBoards
    // The answer field's own box, so a road-spanning prop can be measured
    // against the object the plan's acceptance line names -- not against the
    // fact, which is a different object further up the screen and is what
    // round four measured instead. The field yields for the frames a crossbar
    // is over it; see `fieldYield` in TrackView.qml and `fieldFace` below.
    fieldRect: Qt.rect(question.x + answerSlot.x, question.y + answerSlot.y,
                       answerSlot.width, answerSlot.height)
    factRect: race.lineGuardRect
    // The kart the hand is aimed at, ringed for as long as it is. See
    // `aimedRivalId` below.
    aimKartId: race.aimedRivalId
    // The one thing this screen listens to the road for: a callout that belongs
    // to an impact, released on the frame the impact lands. See `sayAtImpact`.
    onFxImpactFired: race.releaseSay()
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

  // ----------------------------------------------------- the line's ink
  //
  // The probe draws the widest LINE in the game at a fixed size and reports the
  // tight bounding box of the glyphs -- the ink, not the em box. The ratio is
  // the face's own, so the size below follows the shell's font rather than a
  // constant measured once on this Mac. The probe's own size is fixed, so
  // nothing here is circular.
  //
  // PIECE F ROUND 7: the widest line is `12 × 12 = 144`, not `12 × 12`. The
  // fact and the field are one line now (design v4.1, The view), so the width
  // cap below has to be measured on the whole of what is drawn, or the answer
  // to the widest fact runs off the right of a narrow screen.
  TextMetrics {
    id: inkProbe
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: 200
    text: "12 × 12 = 144"
  }
  readonly property real factInkRatio: inkProbe.tightBoundingRect.height > 0
                                       ? inkProbe.tightBoundingRect.height / 200
                                       : 0.73
  readonly property int factPixelSize: {
    // A tenth of the screen height in ink, with a hair over it so rounding
    // never lands under the floor.
    var wanted = Math.ceil((race.height * 0.105) / Math.max(0.25, race.factInkRatio))
    // ... and never so wide that the widest line runs off the screen.
    var widest = inkProbe.advanceWidth > 0
                 ? Math.floor((race.width - race.px(120)) * 200 / inkProbe.advanceWidth)
                 : wanted
    return Math.max(race.fs(100), Math.min(wanted, widest))
  }

  // The fact's ink AS IT IS ON THE SCREEN NOW: the tight bounding box of the
  // glyphs currently drawn, in this screen's own coordinates. `factGround`
  // below is what the line yields with when a road-spanning prop is behind it,
  // and the evidence quotes the ink as a fraction of the frame height. The
  // design's floor is "never smaller than a tenth of the screen height", and a
  // round of this project already reported `font.pixelSize` as that number and
  // was caught: the em box carries ascent, descent and leading, and this face
  // draws about 0.73 of it. `tightBoundingRect` is measured from the BASELINE,
  // so its `y` is negative for anything above it; the Text item's own top is
  // `ascent` above that baseline.
  TextMetrics {
    id: factInkNow
    font: factWord.faceFont
    text: factWord.words
  }
  FontMetrics {
    id: factFace
    font: factWord.faceFont
  }
  // The fact's own ink: `7 × 8 =`.
  readonly property rect factInkRect: {
    var r = factInkNow.tightBoundingRect
    return Qt.rect(question.x + factWord.x + r.x,
                   question.y + factWord.y + factFace.ascent + r.y,
                   r.width, r.height)
  }
  // The whole line's ink AS DRAWN: the fact through the last thing on the
  // answer -- the caret, or the last digit -- one box. This is what the plate
  // answers for; it tightens and loosens with what is on the line so the
  // plate is never a slab over an empty third of the sky.
  readonly property rect lineInkRect: Qt.rect(race.factInkRect.x, race.factInkRect.y,
                                              (question.x + answerSlot.x
                                               + Math.max(caretMark.x + caretMark.width,
                                                          answerWord.width))
                                              - race.factInkRect.x,
                                              race.factInkRect.height)
  // The whole line's RESERVE: the fact through the full answer slot, where the
  // digits will be. This is what the effect layer's guard band keeps clear,
  // because the design's rule is about the LINE -- "never over the karts",
  // "nothing ever covers the fact" -- and a tag pushed under the empty slot
  // would be under the third digit a moment later.
  readonly property rect lineGuardRect: Qt.rect(race.factInkRect.x, race.factInkRect.y,
                                                (question.x + answerSlot.x + answerSlot.width)
                                                - race.factInkRect.x,
                                                race.factInkRect.height)

  // -------------------------------------------------- the line's own ground
  //
  // The line is drawn over every prop -- it is declared after the track, so a
  // gantry can never cover a glyph -- and what a road-spanning prop takes from
  // it is contrast, not visibility: the gantry's beam is a cream-and-ink
  // chequer and the fact is cream. So for the frames a crossbar is behind the
  // ink, and only those, the line gets a ground. The same plate comes up with a
  // card's world flash (`track.fxWashOverFact` is the alpha of the light
  // actually reaching the middle of the frame) and with a Turbo's horizon dip,
  // and goes back to zero with each. It is BEHIND the ink -- declared before
  // the line's own Row -- so nothing here covers anything.
  //
  // The INK box as an item, so a rect dump can print it. It paints nothing.
  Item {
    objectName: "factInk"
    x: race.lineInkRect.x
    y: race.lineInkRect.y
    width: race.lineInkRect.width
    height: race.lineInkRect.height
  }
  Item {
    objectName: "lineGuard"
    x: race.lineGuardRect.x
    y: race.lineGuardRect.y
    width: race.lineGuardRect.width
    height: race.lineGuardRect.height
  }

  // The plate's own opacity, published so a test can assert that the seatbelt
  // is fastened on every frame the light is up rather than asserting that the
  // source contains a multiplier.
  readonly property real factGroundAlpha: factGround.opacity

  Rectangle {
    id: factGround
    objectName: "factGround"
    visible: opacity > 0.004
    readonly property real wash: track.fxWashOverFact
    // Three times the wash, capped. The plate has to take back more ground
    // than the wash put on, because the wash also lifts the plate itself.
    // Measured on the frames, WCAG 2.1 contrast between the fact's ink and the
    // ground it is on: 3.47:1 with nothing happening, 3.32:1 inside a Turbo's
    // white frame with the plate at 1.5x, and above the resting figure at 3x.
    // `stretchNow` is Turbo's horizon dip, which lifts the bright half of the
    // sky into the line's box for 400 ms.
    opacity: Math.max(track.factYield * 0.86,
                      Math.min(0.92, wash * 3.0),
                      track.stretchNow * 0.62)
    x: race.lineInkRect.x - race.px(22)
    y: race.lineInkRect.y - race.px(14)
    width: race.lineInkRect.width + race.px(44)
    height: race.lineInkRect.height + race.px(28)
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(0.235, 0.071, 0.157, 0.80)
  }

  // ------------------------------------------------------- the answer line
  //
  // Design v4.1, The view: "The fact and the field are one line: `7 × 8 = ▮`,
  // the equals sign and the answer at the same size as the fact, the caret
  // blinking in the empty answer, in the upper centre at the largest type on
  // screen, over the horizon, never over the karts. A separate box below the
  // fact was read as an empty panel, not as the place to type."
  //
  // PIECE F ROUND 7. What stood here was a Column: the fact, and under it a
  // 214 x 98 dark rectangle with the digits in it and no equals sign. The
  // maintainer's first finding on the race screen was that the box did not say
  // it was the answer (`docs/open-questions.md` §5.3.1). The box is gone. The
  // line is one Row: the fact with its equals sign, then a slot the width of
  // the widest answer, holding the typed digits and a block caret, all in the
  // fact's own type and the fact's own keyline treatment (`LitWord`), so the
  // answer is the same object as the question and not a panel under it.
  //
  // THE SLOT IS FIXED WIDTH, on purpose. The Row is centred, so a slot that
  // grew with the digits would slide the fact left as the child typed. The
  // slot is as wide as three digits and a caret, and the digits fill it from
  // the left, so `7 × 8 =` stays exactly where it was for every keystroke.
  //
  // WHERE IT SITS. Under the HUD's top row, and clear of the minimap panel:
  // with the answer on the same line as the fact, the widest line is about
  // two thirds of a 1080p frame wide, and at the old y = 118 it ran under the
  // map. The top of the em box is at the map panel's bottom edge plus a
  // hand's margin, which keeps the whole of the ink in the sky and above the
  // horizon at every one of the three sizes this game is played at; the frames
  // in the evidence are the proof, per size.
  //
  // THE STALL IS ON THE FIELD. Design v4.1: "the stall after a hit is shown on
  // the answer field itself, as the bolts overlay the feel section describes,
  // not as a banner." The `ENGINE HIT · 3s` band that used to sit under the
  // fact is gone; the four bolts on the answer slot are the whole of it, and
  // the caret stops while the field is locked.
  //
  // THE REVEAL USES THE SAME LINE. A second wrong answer shows `7 × 8 = 56` in
  // teal for 1500 ms: the fact word takes the revealed fact, the slot takes its
  // answer in the reveal's tone, and the line the child was typing on is the
  // line that tells them. Nothing appears anywhere else.
  Row {
    id: question
    // Named for the rect dump and for `tests/qml/tst_trackview_fx.qml`, which
    // reads its position in `race.children` to prove the line is painted AFTER
    // the track and therefore over every effect in it.
    objectName: "factColumn"
    anchors.horizontalCenter: parent.horizontalCenter
    y: rightHud.y + mapPanel.height + race.px(12)
    spacing: race.px(28)

    // THE FACT IS DRAWN THE WAY THE COUNTDOWN DRAWS IT, AND IT IS THE SAME
    // OBJECT ONE SECOND APART. `ui/parts/LitWord.qml`: a cast shadow, an
    // opaque keyline and a warm rim on the sun side, in one cached layer, so
    // what the race pays per frame is one textured quad.
    LitWord {
      id: factWord
      // Through a reveal the line shows the fact being revealed, which the
      // engine has already moved past; the moment the reveal clears, the fact
      // on screen is the engine's.
      words: reveal.active
             ? reveal.factLabel + " ="
             : ((race.human && race.human.currentFact >= 0)
                ? Engine.factLabel(race.human.currentFact) + " =" : "")
      // The largest type on the screen, and never below a tenth of its height
      // -- measured as INK, which is the only reading of that rule a child can
      // see. `font.pixelSize` is an em box; `12 x 12` in this face draws about
      // 0.73 of it, so the size is derived from the ink the face actually
      // draws, at every screen size and in any font the shell hands down.
      size: race.factPixelSize
      spacing: race.px(6)
      drop: race.px(6)
      contour: Math.max(2, race.px(5))
      rimOffset: Math.max(1, Math.round(Math.max(2, race.px(5)) * 0.55))
      faceTone: reveal.active ? reveal.tone : Theme.cream
      shadowTone: Qt.rgba(0.235, 0.07, 0.157, 0.82)
      bodyTone: "#280e27"
      rimTone: "#f0b07a"
    }

    // The field. It is a readout, not something to type into: the digits the
    // child presses go through the engine and come back as `racer.entry`, so
    // there is no text-entry control anywhere in this game.
    Item {
      id: answerSlot
      // The box the effect layer's guard band is measured against and the box
      // `dev/Harness.qml --dump-rects` prints beside every effect item's, so
      // the two can be shown not to intersect. `TrackView.fieldRect` is this.
      objectName: "answerField"
      // Three digits and a caret, whatever is typed.
      width: answerProbe.advanceWidth + caretMark.width + race.px(8)
      height: factWord.height
      anchors.verticalCenter: parent.verticalCenter

      TextMetrics {
        id: answerProbe
        font: factWord.faceFont
        text: "144"
      }

      // THE ANSWER BOX ANSWERS "IS THIS THING ALIVE", AND NOTHING ELSE. A click
      // puts the keyboard here and shows the caret; it takes no action, because
      // the design forbids free text and there is no keypad (v4.2).
      Clickable {
        id: fieldHit
        objectName: "clickAnswerField"
        stop: keys
        focusOnly: true
        label: "answer box"
        does: "put the keyboard in the answer box"
        key: ""
      }

      FocusRing {
        on: fieldHit.hovered
        hover: true
        radius: Theme.cornerRadiusSmall
        wash: false
        gap: 4
      }

      // The typed digits, or the revealed answer, in the fact's own treatment.
      // The face is the charge's amber for the child's own digits -- the one
      // thing on the line the child put there -- and the reveal's teal when
      // the line is telling them. `x` is what the sputter shakes.
      Item {
        id: answerInk
        x: 0
        y: 0
        width: parent.width
        height: parent.height

        LitWord {
          id: answerWord
          x: 0
          y: 0
          words: reveal.active ? reveal.answer : race.shownEntry
          size: race.factPixelSize
          spacing: race.px(6)
          drop: race.px(6)
          contour: Math.max(2, race.px(5))
          rimOffset: Math.max(1, Math.round(Math.max(2, race.px(5)) * 0.55))
          faceTone: reveal.active ? reveal.tone : Theme.amberGlow
          shadowTone: Qt.rgba(0.235, 0.07, 0.157, 0.82)
          bodyTone: "#280e27"
          rimTone: "#f0b07a"
        }

        // THE CARET IS A BLOCK, `▮`, as the design draws it: a bar the height
        // of a digit's ink, after the last digit, blinking at 1.25 Hz. It goes
        // while a reveal holds the line and while the field is locked, because
        // in both states a keystroke would not land here.
        Rectangle {
          id: caretMark
          objectName: "caret"
          x: answerWord.width + (race.shownEntry.length > 0 ? race.px(10) : 0)
          // The top of a digit's ink: the baseline is `ascent` down the em box
          // and the tight box's `y` is measured up from it.
          y: factFace.ascent + answerCap.tightBoundingRect.y
          width: Math.max(6, Math.round(race.factPixelSize * 0.16))
          height: Math.max(8, Math.round(answerCap.tightBoundingRect.height))
          radius: 2
          color: Theme.amberGlow
          visible: caret.on && !reveal.active && !race.stalled
                   && race.shownEntry.length < 3
          border.width: Math.max(1, race.px(2))
          border.color: "#280e27"
        }
        TextMetrics {
          id: answerCap
          font: factWord.faceFont
          text: "8"
        }
      }

      // ------------------------------------------------------------ PIECE F
      //
      // "The answer field locks with a mechanical overlay of bolts that spin
      // off over the stall duration (2 s, 3 s for a Wrench) so the lock reads
      // as a thing happening, not a bug."
      //
      // Four bolts, one per corner of the answer slot, spinning and then flying
      // off as the stall runs out. The stall's length is the ENGINE's -- it
      // comes off the `hit` event that caused it, and `stalledUntilMs` is the
      // engine's own deadline -- so the last bolt leaves on the frame the field
      // comes back, whatever the card was and whatever the rules say next.
      // Sized off the line's type, so on a 156 px line they are bolts and not
      // specks. Under reduced motion they do not spin or fly; they are four
      // bolts that go out one at a time.
      Repeater {
        model: 4

        Item {
          readonly property real u: race.stallProgress
          // Each bolt leaves a quarter of the stall after the one before it.
          readonly property real mine: Math.max(0, Math.min(1, (u - index * 0.22) / 0.34))
          readonly property real cx: (index % 2 === 0 ? 1 : -1)
          readonly property real cy: (index < 2 ? 1 : -1)
          readonly property real d: Math.max(13, Math.round(race.factPixelSize * 0.20))

          objectName: "stallBolt"
          visible: race.stalled && mine < 1
          width: d
          height: d
          x: (index % 2 === 0 ? -d * 0.3 : answerSlot.width - d * 0.7)
             + (race.reducedMotion ? 0 : cx * mine * mine * race.px(90))
          y: (index < 2 ? factFace.ascent + answerCap.tightBoundingRect.y - d * 0.3
                        : factFace.ascent - d * 0.7)
             + (race.reducedMotion ? 0 : -cy * mine * mine * race.px(70))
          opacity: 1 - mine
          rotation: race.reducedMotion ? 0 : (u * 900 + index * 40)

          // A hex head: a square with its corners cut by a rotated square over
          // it, which is as much of a bolt as thirty pixels can be.
          Rectangle {
            anchors.fill: parent
            radius: 3
            color: Theme.hazard
            border.width: Math.max(1, race.px(2))
            border.color: Qt.rgba(0, 0, 0, 0.55)
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.42
            height: Math.max(2, race.px(3))
            color: Qt.rgba(0, 0, 0, 0.65)
          }
        }
      }

      // The lock itself, under the bolts: a hazard bar the width of the slot
      // at the baseline, so the locked field is a state a child can see between
      // bolts and not only four things in motion. Reduced motion keeps it.
      Rectangle {
        objectName: "stallBar"
        visible: race.stalled
        x: 0
        y: factFace.ascent + race.px(8)
        width: answerSlot.width
        height: Math.max(3, race.px(6))
        radius: 2
        color: Theme.hazard
        opacity: 0.85
      }

      // Design, The answer loop 4: a 500 ms sputter, and nothing else. No
      // message, no red mark, no reveal -- the digits shake the way an engine
      // coughs and the streak is gone. The ink shakes; the slot, and so the
      // fact beside it, does not move.
      SequentialAnimation {
        id: sputter
        running: false
        loops: 4
        NumberAnimation { target: answerInk; property: "x"; to: race.reducedMotion ? 0 : -race.px(7); duration: 62 }
        NumberAnimation { target: answerInk; property: "x"; to: race.reducedMotion ? 0 : race.px(7); duration: 62 }
        onFinished: answerInk.x = 0
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

  // The reveal: the fact being shown and its answer, as two strings, because
  // the line draws them in two places -- the fact word and the answer slot --
  // and one string would have to be split again to get there.
  QtObject {
    id: reveal
    property string factLabel: ""
    property string answer: ""
    // What the line reads while it is up, published for the tests and the
    // harness: `7 × 8 = 56`.
    readonly property string text: reveal.active ? reveal.factLabel + " = " + reveal.answer : ""
    property color tone: Theme.teal
    property bool active: false

    function show(label, value, holdMs, colour) {
      reveal.factLabel = label
      reveal.answer = value
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
      // The line is back. Anything the child pressed into the window it was
      // gone for is replayed now, against the fact they can finally see.
      race.releaseReveal()
    }
  }

  // ------------------------------------------------------------- the callout
  // ONE SLOT, under the line. Newest replaces last; never stacked; never over
  // the line, because it hangs off the line's own ink box. See `say`.
  Callout {
    id: callout
    objectName: "callout"
    anchors.horizontalCenter: parent.horizontalCenter
    y: race.lineInkRect.y + race.lineInkRect.height + race.px(14)
    // The large type Pile-Up reserves needs a box to sit in; every other
    // callout is the height it always was.
    height: race.px(big ? 74 : 46)
    width: implicitWidth
    holdMs: Engine.CALLOUT_MS
    // The fade is wall-time, so under an external clock it is a cut. See
    // `externalClock` above.
    reducedMotion: race.reducedMotion || race.externalClock
    // ... and so is the 1.6 s HOLD: under an external clock the hold is
    // measured on the effect clock instead, so a strip is the same bytes twice.
    fxNow: race.externalClock ? track.fxClock : -1
  }

  // --------------------------------------------- charge, and the one picker
  //
  // ONE PANEL. `ui/Picker.qml` is the hand, and the race screen drives it: the
  // race keeps every key (`keys` above) and calls the panel's `moveHighlight`,
  // `stepTarget` and `fire`; the panel's own `Keys` handler is the same three
  // keys for the harness, where it stands alone.
  Picker {
    id: picker
    anchors.fill: parent
    hand: race.hand
    rivals: race.liveRivals
    // PIECE F. The panel's three beats -- the deal, the breath and the slam --
    // run on the effect clock, not on a timer of their own, so the hand and the
    // road are the same event and a frame strip catches both.
    fxNow: track.fxClock
    reducedMotion: race.reducedMotion
    dockWidth: race.px(500)
    dockMargin: race.px(30)
    // The hand outlives itself for the length of the slam: spending a card
    // empties the hand on the frame the child presses Space, and a panel bound
    // to `hand.length > 0` alone took the cards off the screen before the beat
    // that shows them going.
    visible: race.hand.length > 0 || picker.slamming
    onCardUsed: function (index, targetId) {
      race.send({ "kind": "useCard", "index": index, "targetId": targetId })
    }
  }

  // THE AIMED KART IS RINGED. Design v4.1: "the target's kart is ringed while
  // it is chosen". The panel says who; the road draws it. "" when nothing is
  // aimed, which is every moment a targeted card is not highlighted.
  readonly property string aimedRivalId: (race.handHeld && picker.targeting) ? picker.targetId : ""

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
    // under an external clock for the same reason the caret's blink is -- and
    // ONLY that: the twelve-segment burst is a pure function of the effect
    // clock and reproducible, and folding the external clock into
    // `reducedMotion` switched it off in every strip for two rounds.
    reducedMotion: race.reducedMotion
    externalClock: race.externalClock
    holdingHand: race.hand.length > 0
    // PIECE F: "the charge bar flashes, the twelve segments burst".
    fxNow: track.fxClock
    cellHeight: race.px(24)
    cellGap: race.px(4)
    titleSize: race.fs(14)
    padX: race.px(16)
    padY: race.px(12)
    visible: race.state ? race.state.powerupsEnabled : false
  }

  // ------------------------------------------------------------ pit crew
  // Always available, and it says so, because the design's fairness list makes
  // it a promise: "A child can never be trapped on a fact."
  //
  // THE TWO THINGS THE RACE DOES THAT ARE NOT TYPING, drawn as KEY CAPS.
  // Design v4.1, Accessibility: "Key hints in the race are drawn as key caps,
  // the way the garage draws them: `[H] PIT CREW · shows the answer`". The
  // maintainer read `H  PIT CREW` as cryptic (`docs/open-questions.md` §5.3.7);
  // `ui/parts/KeyHint.qml`'s `cap` is the garage's own construction, and the
  // clause after the mid-dot says what the key does in words a child reads.
  // Each one calls the exact function its key's branch calls.
  Column {
    anchors.left: parent.left
    anchors.leftMargin: race.px(30)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: race.px(28)
    // Two DESTRUCTIVE controls, one above the other, and the lower one abandons
    // the race. The targets are 24 px square at minimum (`ui/parts/KeyHint.qml`),
    // which needs room between the words or the two hit areas grow into each
    // other and the pointer is on the one the child is not reading.
    spacing: Math.max(10, race.px(8))

    KeyHint {
      id: pitCrewHint
      keys: "H"
      action: "PIT CREW"
      sub: "shows the answer"
      cap: true
      textSize: race.fs(17)
      letterSpacing: 2
      padWidth: race.px(16)
      padHeight: race.px(9)
      idleColor: Theme.text
      name: "Pit crew"
      does: "show the answer and move on"
      key: "H"
      help: "Shows the answer and moves on. The H key does it too."
      // THIS SPENDS SOMETHING THE CHILD CANNOT GET BACK. The pit crew consumes
      // the question in front of the child, adds to the count the results
      // screen prints as ANSWERS SHOWN, and feeds the standings tiebreak. There
      // is no undo, and it stays exactly where it is after it acts -- so the
      // second half of a double-click always reaches it, and it is guarded.
      destructive: true
      guards: ["pitCrew"]
      // THE SAME FUNCTION the `H` branch calls, not the same calls: the prose
      // version of that claim was false for a whole round.
      onTapped: race.pitCrewRequested()
    }

    KeyHint {
      id: leaveHint
      keys: "ESC"
      action: "LEAVE"
      cap: true
      textSize: race.fs(17)
      letterSpacing: 2
      padWidth: race.px(16)
      padHeight: race.px(9)
      idleColor: Theme.text
      name: "Leave the race"
      does: "go back to the garage"
      key: "Escape"
      // Leaving a race cannot be undone. `escape` is the name the Escape key's
      // branch takes too, so a key and a click inside one double-click interval
      // are one gesture whichever hand made them.
      destructive: true
      guards: ["escape"]
      help: "Back to the garage. The Escape key does it too."
      onTapped: race.leaveNow()
    }
  }
}
