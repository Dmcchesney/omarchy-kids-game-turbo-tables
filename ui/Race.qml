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
  // The road, exposed so a host can pause it when the overlay closes and so a
  // test can ask it which path it took. Nothing outside drives it in play: the
  // lurch and the pull-back come from the engine's events.
  readonly property alias trackView: track

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

    var built = Engine.createRace({
      "seed": race.seed,
      "mode": race.mode,
      "preset": race.preset,
      "racers": seats,
      "humanId": "you"
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
          hand.reset()
          var label = Engine.CARDS[e.card].label.toUpperCase()
          say(e.targetId === "" ? label : label + " ▸ " + nameOf(e.targetId), Theme.amber)
          if (e.card === "turbo" || e.card === "nitro")
            track.throwForward(e.card === "turbo" ? 1.0 : 0.55)
        }
        break
      case "handDealt":
        if (e.racerId === me)
          hand.reset()
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
          say("PASSED " + nameOf(e.otherId), Theme.lime)
        break
      case "passedBy":
        if (e.racerId === me)
          say(nameOf(e.otherId) + " SLIPPED PAST", Theme.hazard)
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
    var before = race.viewProgress
    for (var i = 0; i < state.racers.length; i++) {
      var target = Engine.effectiveProgress(state.racers[i], state.questionsPerLap)
      var held = (race.smoothProgress.length > i) ? race.smoothProgress[i] : target
      var next = held + (target - held) * lerp
      values.push(next)
    }
    race.smoothProgress = values
    race.viewProgress = values.length > 0 ? values[0] : 0
    track.humanProgress = race.viewProgress
    track.setProgress(values)

    // Speed is effective-progress rate, in questions per second, plus the
    // idle roll: the design has the kart rolling while the child is thinking.
    var rate = dtMs > 0 ? (race.viewProgress - before) / dtMs * 1000 : 0
    var want = Math.max(0, Math.min(1, 0.30 + rate * 0.75 - (race.stalled ? 0.26 : 0)))
    race.smoothSpeed = race.smoothSpeed * 0.90 + want * 0.10
    track.speed = race.smoothSpeed

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
  // 1, 2 and 3 do two things at once, and they have to: the design gives them
  // to the powerup picker and also needs them as digits, because plenty of
  // answers begin with one of them. So they always type, and while a hand is
  // held they also move the picker's selection. Enter then decides: with
  // something typed it submits the answer, and with the entry empty it plays
  // the selected card. Nothing is ever spent by a keystroke that was meant as
  // a digit.
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
        if (hand.targeting)
          hand.cancelTarget()
        else if (hand.selected >= 0)
          hand.selected = -1
        else
          race.leaveRequested()
        event.accepted = true
        return
      }

      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        if (race.human && race.human.entry.length > 0) {
          hand.selected = -1
          hand.targeting = false
          race.send({ "kind": "submit" })
        } else if (hand.selected >= 0) {
          hand.confirm()
        }
        event.accepted = true
        return
      }

      if (key === Qt.Key_Backspace) {
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
        if (hand.targeting)
          hand.moveTarget(key === Qt.Key_Left ? -1 : 1)
        event.accepted = true
        return
      }

      if (key >= Qt.Key_0 && key <= Qt.Key_9) {
        var digit = key - Qt.Key_0
        if (digit >= 1 && digit <= 3 && hand.cards.length >= digit)
          hand.select(digit - 1)
        race.send({ "kind": "digit", "value": digit })
        event.accepted = true
        return
      }
    }
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
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.42) }
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
      // The largest type on the screen, and never below a tenth of its height.
      font.pixelSize: Math.max(Math.round(race.height * 0.115), race.fs(118))
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

  // -------------------------------------------------- charge and the hand
  Column {
    id: lowerRight
    anchors.right: parent.right
    anchors.rightMargin: race.px(30)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: race.px(28)
    spacing: race.px(16)
    width: race.px(320)

    ChargeBar {
      id: charge
      width: parent.width
      value: race.human ? Math.min(race.state.streakThreshold, race.human.streak) : 0
      segments: race.state ? race.state.streakThreshold : Engine.CHARGE_SEGMENTS
      glowFrom: Engine.CHARGE_GLOW_FROM
      reducedMotion: race.reducedMotion
      holdingHand: race.human ? race.human.hand.length > 0 : false
      cellHeight: race.px(24)
      cellGap: race.px(4)
      titleSize: race.fs(14)
      visible: race.state ? race.state.powerupsEnabled : false
    }

    // The picker, as the design describes it: a small panel in the lower
    // right, never a modal over the question.
    Rectangle {
      id: hand
      width: parent.width
      visible: cards.length > 0
      height: handColumn.implicitHeight + race.px(22)
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.92)
      border.width: 1
      border.color: selected >= 0 ? Theme.amber : Theme.line

      readonly property var cards: (race.human && race.human.hand) ? race.human.hand : []
      property int selected: -1
      property bool targeting: false
      property int targetAt: 0

      readonly property var targets: {
        if (!race.state)
          return []
        var out = []
        for (var i = 0; i < race.state.racers.length; i++) {
          var r = race.state.racers[i]
          if (r.kind === "human" || r.finished)
            continue
          out.push(r.id)
        }
        return out
      }

      function select(index) {
        if (index < 0 || index >= cards.length)
          return
        hand.selected = index
        hand.targeting = Engine.CARDS[cards[index]].scope === "targeted" && targets.length > 0
        hand.targetAt = 0
      }
      function moveTarget(delta) {
        if (!targeting || targets.length === 0)
          return
        hand.targetAt = ((hand.targetAt + delta) % targets.length + targets.length) % targets.length
      }
      function cancelTarget() {
        hand.targeting = false
        hand.selected = -1
      }
      function confirm() {
        if (selected < 0 || selected >= cards.length)
          return
        var card = cards[selected]
        var scope = Engine.CARDS[card].scope
        if (scope === "targeted") {
          if (targets.length === 0)
            return
          race.send({ "kind": "useCard", "index": selected, "targetId": targets[targetAt] })
        } else {
          race.send({ "kind": "useCard", "index": selected })
        }
        hand.selected = -1
        hand.targeting = false
      }

      // The selection is cleared by the two events that can invalidate it and
      // by nothing else. Watching the `cards` array instead would clear it ten
      // times a second, because the engine hands back a fresh state -- and a
      // fresh hand array -- on every step, whether the hand changed or not.
      function reset() {
        hand.selected = -1
        hand.targeting = false
      }

      Column {
        id: handColumn
        x: race.px(14)
        y: race.px(11)
        width: parent.width - race.px(28)
        spacing: race.px(6)

        Text {
          textFormat: Text.PlainText
          text: "HAND"
          color: Theme.textLabel
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: race.fs(14)
          font.letterSpacing: 2
        }

        Repeater {
          model: hand.cards

          Row {
            readonly property bool chosen: index === hand.selected
            spacing: race.px(10)

            Rectangle {
              width: race.px(24)
              height: race.px(24)
              radius: race.px(4)
              color: parent.chosen ? Theme.amber : "transparent"
              border.width: 1
              border.color: parent.chosen ? Theme.amber : Theme.lineStrong

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(index + 1)
                color: parent.parent.chosen ? Theme.ink(Theme.amber) : Theme.textLabel
                font.family: Theme.mono
                font.bold: true
                font.pixelSize: race.fs(15)
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Engine.CARDS[modelData].label
              color: parent.chosen ? Theme.amberGlow : Theme.textBright
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: race.fs(19)
              font.letterSpacing: 1
            }
          }
        }

        // The target row appears only for a card that needs one, which is the
        // design's rule: left and right pick a rival, Enter confirms.
        Row {
          visible: hand.targeting
          spacing: race.px(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "◂"
            color: Theme.amber
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: race.fs(16)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: hand.targets.length > 0 ? race.nameOf(hand.targets[hand.targetAt]) : ""
            color: Theme.amberGlow
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: race.fs(17)
            font.letterSpacing: 1
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "▸   ⏎"
            color: Theme.amber
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: race.fs(16)
          }
        }
      }
    }
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
