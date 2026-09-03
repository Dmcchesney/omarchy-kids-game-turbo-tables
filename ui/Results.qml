import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

// The end of a race, drawn exactly as the design's wireframe draws it.
//
// ```
// PODIUM FINISH                                  2nd of 4
//
// TIME          8:41            LAPS   12 / 12
// CORRECT       144             PIT CREW   3
// ACCURACY      91%             BEST STREAK   27
// POWER-UPS     Nitro · Wrench ▸ Bolt · Roll Cage
//
// FACTS TO LOOK AT    7 × 8 = 56    6 × 9 = 54    12 × 7 = 84
// TABLES LIT          ▮▮▮▮▮▮▮▮▮▯▯▯   9 of 12
//
// [ RACE AGAIN ⏎ ]   [ GARAGE  Esc ]
// ```
//
// THE SCREEN HAS NO BOTTOM. Design, Fairness: "The results screen has no
// bottom: it names the child's own place and the top three, nothing else." That
// is why this file reads `resultsBoard` and never `rankRacers`. The engine has
// both on purpose: `rankRacers` will tell you a racer came fourth of four
// because the live HUD and the pass callouts need the whole order, and
// `resultsBoard` hands back the child's own place, the headline for it, and the
// podium, and nothing below third exists in the object at all. A fourth place
// here is a number in "4th of 4" and a headline that says RACE COMPLETE, and
// there is no word anywhere on this screen for being last.
//
// Headlines are the engine's `headlineForPlace`, which is the design's rule --
// VICTORY LAP for first, PODIUM FINISH for second and third, RACE COMPLETE
// otherwise -- so the three strings live in one place and this screen cannot
// disagree with the ranking that produced them.
//
// Best streak is this race only: it is read off the racer the race just
// finished with and nothing on this screen is written anywhere.
FocusScope {
  id: results

  readonly property Item focusTarget: stops.length > 0 ? stops[0] : null

  signal raceAgainRequested()
  signal garageRequested()

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }

  // ------------------------------------------------------------ the race
  //
  // The host hands the finished race down. `racerId` is the child; it defaults
  // to whoever the race calls its human.
  property var raceState: null
  property string racerId: ""
  property int seed: 42

  // A results screen with no race behind it would have nothing true to say, so
  // rather than invent numbers it plays one. `demoRace()` below runs a real
  // race through the real engine -- the same reducer, the same rivals, the same
  // shared card cursor -- with a seeded stand-in for the child at the keyboard,
  // and every figure on the screen then comes out of that race. It exists for
  // the development harness and for the moment before a race has been wired in;
  // a hosted screen never reaches it. It is not a mock: change the seed and the
  // place, the time, the missed facts and the podium all change together,
  // because they came from one race.
  readonly property var fallbackState: raceState === null ? demoRace(results.seed) : null
  readonly property var race: raceState !== null ? raceState : fallbackState
  readonly property string subjectId: racerId.length > 0
                                      ? racerId
                                      : (race ? String(race.humanId) : "")

  readonly property var rivalSeats: [
    { "id": "bolt", "personality": "bolt" },
    { "id": "piston", "personality": "piston" },
    { "id": "gasket", "personality": "gasket" }
  ]
  readonly property var presetIds: ["2-5", "2-10", "1-12"]
  readonly property var modeIds: ["practice", "timeTrial", "ghost", "grandPrix"]
  readonly property var levelIds: ["rookie", "pro", "champion"]

  function demoRace(raceSeed) {
    var preset = presetIds[Math.max(0, Math.min(2, Store.setting("mathSet")))]
    var mode = modeIds[Math.max(0, Math.min(3, Store.setting("raceMode")))]
    var level = levelIds[Math.max(0, Math.min(2, Store.setting("rivalLevel")))]
    var withRivals = mode === "grandPrix"
    var seats = [{ "id": "you", "kind": "human" }]
    if (withRivals) {
      for (var r = 0; r < rivalSeats.length; r++)
        seats.push({ "id": rivalSeats[r].id, "kind": "rival" })
    }

    var state = Engine.createRace({ "seed": raceSeed, "preset": preset,
                                    "mode": mode, "racers": seats })
    state = Engine.step(state, { "kind": "start" }, 0).state
    var rivals = withRivals
                 ? Engine.createRivals(state, rivalSeats.map(function (seat) {
                     return { "id": seat.id, "personality": seat.personality, "level": level }
                   }))
                 : null

    // The stand-in child: one pace and one accuracy, both drawn once from the
    // race seed through the engine's own generator, so a seed is a whole race
    // and two runs of the same seed are the same race.
    var rng = Engine.forkRng(raceSeed, "demo-child")
    var pace = 2200 + Math.floor(Engine.nextFloat(rng) * 2200)
    var accuracy = 80 + Math.floor(Engine.nextFloat(rng) * 18)
    var due = pace
    var asked = 0
    var tick = 500
    var now = 0

    for (var guard = 0; guard < 4000; guard++) {
      now += tick
      if (rivals !== null) {
        var stepped = Engine.rivalStep(state, rivals, now)
        state = stepped.state
        rivals = stepped.rivals
      } else {
        state = Engine.step(state, { "kind": "tick" }, now).state
      }
      if (state.status === "finished")
        break
      var me = Engine.racerById(state, "you")
      if (me === null || me.finished || now < due)
        continue
      due = now + pace
      asked += 1

      if (me.hand.length > 0) {
        // Spend the first card in the hand, aimed at the leading rival still in
        // the fight when it needs a target. Enough policy to make the POWER-UPS
        // line real, and no more.
        var card = String(me.hand[0])
        // Reset every time round. `var` is function-scoped, so a target left
        // over from an earlier card would be handed to a self card, and the
        // engine refuses a self card that names a target.
        var target = ""
        var needsTarget = Engine.CARDS[card].scope === "targeted"
        if (needsTarget) {
          var order = Engine.positionOrder(state.racers, state.questionsPerLap)
          for (var o = 0; o < order.length; o++) {
            var other = Engine.racerById(state, order[o])
            if (other !== null && other.id !== "you" && !other.finished) {
              target = String(other.id)
              break
            }
          }
        }
        if (!needsTarget || target.length > 0) {
          var played = Engine.step(state, { "kind": "useCard", "index": 0, "targetId": target }, now).state
          // Only take the step if it actually spent the hand. A refused card --
          // every rival home, so an attack has nowhere to land -- would
          // otherwise be retried on every turn for the rest of the race, and
          // the child would never answer another question.
          if (Engine.racerById(played, "you").hand.length === 0) {
            state = played
            continue
          }
        }
        // The hand could not be spent, so it is held, which the design allows,
        // and the child answers the question in front of them instead.
      }
      if (asked % 19 === 0) {
        state = Engine.step(state, { "kind": "hint" }, now).state
        continue
      }
      var right = Engine.factAnswer(me.currentFact)
      var value = (Engine.nextFloat(rng) * 100) < accuracy
                  ? right
                  : right + 1 + Math.floor(Engine.nextFloat(rng) * 3)
      state = Engine.step(state, { "kind": "answer", "value": value }, now).state
    }
    return state
  }

  // ----------------------------------------------------------- the numbers
  readonly property var board: race
    ? Engine.resultsBoard(race.racers, results.subjectId, race.questionsPerLap)
    : null
  readonly property var me: race ? Engine.racerById(race, results.subjectId) : null

  readonly property string headline: board ? String(board.headline) : "RACE COMPLETE"
  readonly property color headlineColor: {
    if (!board)
      return Theme.cream
    if (board.place === 1)
      return Theme.amber
    if (board.place === 2 || board.place === 3)
      return Theme.lime
    return Theme.cream
  }
  // The child's own place, which the design's wireframe puts on the right of
  // the headline as "2nd of 4". Naming your own place is not a bottom.
  readonly property string placeText: board && board.place > 0
                                      ? (Engine.ordinal(board.place) + " of " + board.total)
                                      : ""

  function clockText(ms) {
    var whole = Math.max(0, Math.round(ms / 1000))
    var minutes = Math.floor(whole / 60)
    var seconds = whole % 60
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
  }

  readonly property string timeText: {
    if (!race || !me)
      return "-"
    var ms = me.finished ? me.finishTimeMs : (race.nowMs - race.startedAtMs)
    return clockText(ms)
  }
  readonly property string lapsText: (race && me)
                                     ? (me.lapsComplete + " / " + race.totalLaps) : "-"
  readonly property string correctText: me ? String(me.correctCount) : "-"
  readonly property string pitCrewText: me ? String(me.pitCrewCount) : "-"
  readonly property string accuracyText: me ? (Engine.accuracyPercent(me) + "%") : "-"
  readonly property string bestStreakText: me ? String(me.bestStreak) : "-"

  function racerName(id) {
    if (race && id === race.humanId)
      return "YOU"
    return String(id).toUpperCase()
  }

  // Design's wireframe: "Nitro · Wrench ▸ Bolt · Roll Cage". A card that needed
  // a rival says which one; a card that did not, does not.
  readonly property string powerupsText: {
    if (!me || me.cardsUsed.length === 0)
      return race && race.powerupsEnabled ? "NONE SPENT" : "OFF IN THIS MODE"
    // Written out a piece at a time rather than joined. `npm run check:readme`
    // fails any plugin QML file that assembles a string with Array.join or
    // concat, on the grounds that this game has no honest reason to build a
    // name at runtime, and the shape is the defect rather than what it spells.
    var line = ""
    for (var i = 0; i < me.cardsUsed.length; i++) {
      var used = me.cardsUsed[i]
      var label = Engine.isCard(String(used.card)) ? String(Engine.CARDS[used.card].label)
                                                   : String(used.card)
      var target = String(used.targetId)
      if (target.length > 0 && target !== results.subjectId)
        label += " ▸ " + racerName(target)
      line += (i === 0 ? "" : " · ") + label
    }
    return line
  }

  // Design, Laps decks presets: the fact history "drives the mastery lamps in
  // the garage and the order of pit-lane re-asks". The same ordering picks the
  // three facts printed here, so the ones the child is least sure of are the
  // ones named -- not the first three that happen to be in the list.
  readonly property var lookAtFacts: {
    if (!me || me.missed.length === 0)
      return []
    var ordered = Engine.orderByFactHistory(me.missed, me.factHistory)
    return ordered.slice(0, 3)
  }
  readonly property string lookAtText: {
    if (lookAtFacts.length === 0)
      return "NONE — EVERY FACT FIRST TIME"
    var line = ""
    for (var i = 0; i < lookAtFacts.length; i++)
      line += (i === 0 ? "" : "     ")
              + Engine.factLabel(lookAtFacts[i]) + " = " + Engine.factAnswer(lookAtFacts[i])
    return line
  }

  // A table is lit when the child drove that lap and never missed one of its
  // facts. Pit-crew answers do not put a fact out: the design counts them
  // separately and says they always count for progress, and a lamp that went
  // dark for asking for help would make the pit crew something to avoid.
  readonly property var missedTables: {
    var seen = ({})
    if (me) {
      for (var i = 0; i < me.missed.length; i++)
        seen[Engine.factLeft(me.missed[i])] = true
    }
    return seen
  }
  readonly property int tablesLit: {
    if (!race || !me)
      return 0
    var count = 0
    for (var i = 0; i < race.tables.length && i < me.lapsComplete; i++) {
      if (!missedTables[race.tables[i]])
        count += 1
    }
    return count
  }
  // One entry per table in this race: true where the lamp is lit. Drawn as
  // rectangles rather than printed as the wireframe's block characters,
  // because the shell hands down whatever monospace family the child's theme
  // names and nothing guarantees U+25AE is in it -- the same reason the garage
  // draws its icons on a pixel grid instead of reaching for a symbol font. A
  // row of empty boxes where the lamps should be is not a lamp row.
  readonly property var tableLamps: {
    var lamps = []
    if (!race || !me)
      return lamps
    for (var i = 0; i < race.tables.length; i++)
      lamps.push(i < me.lapsComplete && !missedTables[race.tables[i]])
    return lamps
  }

  readonly property var podium: board ? board.podium : []
  // Practice, Time trial and Ghost have nobody to stand on a podium with.
  readonly property bool showPodium: board && board.total > 1

  // ---------------------------------------------------------- focus chain
  readonly property var stops: [againButton, garageButton]

  function stopIndex() {
    for (var i = 0; i < stops.length; i++)
      if (stops[i] && stops[i].activeFocus)
        return i
    return -1
  }

  function moveFocus(delta) {
    var current = stopIndex()
    var count = stops.length
    var next = current < 0 ? (delta > 0 ? 0 : count - 1)
                           : ((current + delta) % count + count) % count
    stops[next].forceActiveFocus(delta > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason)
  }

  function focusStop(index) {
    var count = stops.length
    stops[((index % count) + count) % count].forceActiveFocus(Qt.TabFocusReason)
  }

  function focusName(index) {
    var item = stops[index]
    if (!item)
      return ""
    try {
      return String(item.Accessible.name)
    } catch (error) {
      return ""
    }
  }

  function focusedName() {
    var index = stopIndex()
    return index < 0 ? "" : focusName(index)
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Race results"
  Accessible.description: results.headline + ". " + results.placeText
                          + ". Enter races again, Escape goes back to the garage."

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      results.garageRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // Only reaches here when focus is somewhere that did not want it.
      results.raceAgainRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      results.moveFocus(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      results.moveFocus(-1)
      event.accepted = true
    }
    // Left and Right are deliberately not here. One arrow contract runs across
    // the whole flow -- Tab and up/down move, left and right change a value --
    // and this screen has no value to change, so left and right do nothing,
    // exactly as they do on the settings screen's reset buttons. Round one had
    // them moving focus here and changing a value there, which is two key maps
    // in one game.
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.ground
  }

  Panel {
    id: page
    anchors.fill: parent
    anchors.margins: results.px(16)
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.55)
    border.color: Theme.lineStrong

    readonly property int pad: results.px(40)
    readonly property int contentX: pad
    readonly property int contentW: width - pad * 2

    // =====================================================  headline
    Item {
      id: headlineRow
      x: page.contentX
      y: page.pad
      width: page.contentW
      height: results.px(84)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: results.headline
        color: results.headlineColor
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: results.fs(58)
        font.letterSpacing: results.px(5)
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: results.placeText
        color: Theme.cream
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: results.fs(38)
        font.letterSpacing: results.px(3)
      }
    }

    Rectangle {
      id: headlineRule
      x: page.contentX
      y: headlineRow.y + headlineRow.height + results.px(6)
      width: page.contentW
      height: 2
      color: Qt.rgba(results.headlineColor.r, results.headlineColor.g,
                     results.headlineColor.b, 0.55)
    }

    // =====================================================  the stats block
    readonly property int columnW: Math.floor((contentW - results.px(48)) / 2)

    Column {
      id: leftStats
      x: page.contentX
      y: headlineRule.y + results.px(36)
      width: page.columnW
      spacing: 0

      StatRow {
        width: parent.width
        label: "TIME"
        value: results.timeText
        labelSize: results.fs(19)
        valueSize: results.fs(42)
        labelWidth: results.px(290)
      }
      StatRow {
        width: parent.width
        label: "CORRECT"
        value: results.correctText
        labelSize: results.fs(19)
        valueSize: results.fs(42)
        labelWidth: results.px(290)
      }
      StatRow {
        width: parent.width
        label: "ACCURACY"
        value: results.accuracyText
        labelSize: results.fs(19)
        valueSize: results.fs(42)
        labelWidth: results.px(290)
      }
    }

    Column {
      id: rightStats
      x: page.contentX + page.columnW + results.px(48)
      y: leftStats.y
      width: page.columnW
      spacing: 0

      StatRow {
        width: parent.width
        label: "LAPS"
        value: results.lapsText
        labelSize: results.fs(19)
        valueSize: results.fs(42)
        labelWidth: results.px(290)
      }
      StatRow {
        width: parent.width
        label: "PIT CREW"
        value: results.pitCrewText
        valueColor: Theme.teal
        labelSize: results.fs(19)
        valueSize: results.fs(42)
        labelWidth: results.px(290)
      }
      StatRow {
        width: parent.width
        label: "BEST STREAK"
        value: results.bestStreakText
        valueColor: Theme.amber
        labelSize: results.fs(19)
        valueSize: results.fs(42)
        labelWidth: results.px(290)
      }
    }

    StatRow {
      id: powerupsRow
      x: page.contentX
      y: leftStats.y + leftStats.height + results.px(10)
      width: page.contentW
      label: "POWER-UPS"
      value: results.powerupsText
      labelSize: results.fs(19)
      valueSize: results.fs(26)
      labelWidth: results.px(290)
      wide: true
    }

    Rectangle {
      id: statsRule
      x: page.contentX
      y: powerupsRow.y + powerupsRow.height + results.px(22)
      width: page.contentW
      height: 1
      color: Theme.line
    }

    // =====================================================  facts and lamps
    StatRow {
      id: lookAtRow
      x: page.contentX
      y: statsRule.y + results.px(28)
      width: page.contentW
      label: "FACTS TO LOOK AT"
      value: results.lookAtText
      valueColor: Theme.teal
      labelSize: results.fs(19)
      valueSize: results.fs(34)
      labelWidth: results.px(360)
      wide: true
    }

    Item {
      id: tablesRow
      x: page.contentX
      y: lookAtRow.y + lookAtRow.height + results.px(10)
      width: page.contentW
      height: results.px(58)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: results.px(360)
        textFormat: Text.PlainText
        text: "TABLES LIT"
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: results.fs(19)
        font.letterSpacing: 1.4
      }
      Row {
        id: lamps
        anchors.verticalCenter: parent.verticalCenter
        x: results.px(360)
        spacing: results.px(7)

        Repeater {
          model: results.tableLamps

          // Lit is filled; unlit is an outline. Design, Accessibility: "Every
          // state has shape or text as well as color: lit lamps are filled."
          //
          // ROUND 2. The unlit outline was a one-pixel `Theme.textFaint` line --
          // 0.38 alpha menu text on `Theme.ground` -- and in a 1366 and a 2560
          // frame ten of twelve lamps were all but invisible, so `2 of 12` was
          // carried by the number alone and the shape rule failed in practice.
          // The unlit lamp is now a sunken face with a two-pixel `textLabel`
          // edge: still unmistakably an outline against a filled amber lamp,
          // and still there when you look at it.
          Rectangle {
            width: results.px(26)
            height: results.px(34)
            radius: 2
            color: modelData ? Theme.amber : Theme.panelSunken
            border.width: modelData ? 0 : 2
            border.color: Theme.textLabel
          }
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: lamps.x + lamps.width + results.px(24)
        textFormat: Text.PlainText
        text: results.tablesLit + " of " + (results.race ? results.race.tables.length : 0)
        color: Theme.cream
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: results.fs(26)
        font.letterSpacing: 1
      }
    }

    // =====================================================  the podium
    //
    // The top three, and the screen stops there. There is no fourth row here
    // and no place for one: `resultsBoard` never hands one down.
    Item {
      id: podiumBlock
      visible: results.showPodium
      x: page.contentX
      y: tablesRow.y + tablesRow.height + results.px(30)
      width: page.contentW
      height: results.px(160)

      Text {
        id: podiumLabel
        textFormat: Text.PlainText
        text: "PODIUM"
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: results.fs(18)
        font.letterSpacing: 1.4
      }

      Row {
        y: podiumLabel.height + results.px(10)
        spacing: results.px(16)

        Repeater {
          model: results.podium

          Rectangle {
            readonly property bool isYou: results.race
                                          && String(modelData.id) === String(results.race.humanId)
            width: results.px(320)
            height: results.px(88)
            radius: Theme.cornerRadiusSmall
            color: isYou ? Theme.selectedFill
                         : Qt.rgba(Theme.panelSunken.r, Theme.panelSunken.g, Theme.panelSunken.b, 0.9)
            border.width: isYou ? 2 : 1
            border.color: isYou ? Theme.focusRing : Theme.line

            Accessible.role: Accessible.StaticText
            Accessible.name: Engine.ordinal(modelData.place) + ", "
                             + results.racerName(String(modelData.id))

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: results.px(16)
              textFormat: Text.PlainText
              text: Engine.ordinal(modelData.place)
              color: modelData.place === 1 ? Theme.amber : Theme.textLabel
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: results.fs(24)
              font.letterSpacing: 1
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: results.px(16)
              textFormat: Text.PlainText
              text: results.racerName(String(modelData.id))
              color: parent.isYou ? Theme.textBright : Theme.cream
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: results.fs(26)
              font.letterSpacing: results.px(2)
            }
          }
        }
      }
    }

    // =====================================================  the two actions
    Row {
      id: actions
      x: page.contentX
      y: page.height - page.pad - height
      spacing: results.px(24)

      ActionButton {
        id: againButton
        width: results.px(520)
        height: results.px(128)
        art: Glyphs.flag
        tone: "go"
        variant: "primary"
        label: "RACE AGAIN ⏎"
        sublabel: "SAME SETUP, NEW RACE"
        labelSize: results.fs(34)
        sublabelSize: results.fs(16)
        iconSize: results.px(38)
        Accessible.name: "Race again"
        Accessible.description: "Starts another race with the same setup. Enter does it too."
        onActivated: results.raceAgainRequested()
      }

      ActionButton {
        id: garageButton
        width: results.px(400)
        height: results.px(128)
        art: Glyphs.exit
        tone: "quit"
        variant: "secondary"
        label: "GARAGE"
        sublabel: "Esc"
        labelSize: results.fs(26)
        sublabelSize: results.fs(16)
        iconSize: results.px(30)
        Accessible.name: "Garage"
        Accessible.description: "Back to the garage. Escape does it too."
        onActivated: results.garageRequested()
      }
    }

    // Nothing is written from this screen. Records and the fact history are the
    // race's business and are committed by whoever owned the race; the design
    // says so in as many words and this file keeps to it.
    Text {
      anchors.right: parent.right
      anchors.rightMargin: page.pad
      anchors.verticalCenter: actions.verticalCenter
      textFormat: Text.PlainText
      text: "THIS RACE ONLY"
      color: Theme.textLabel
      font.family: Theme.mono
      font.pixelSize: results.fs(15)
      font.letterSpacing: results.px(2)
    }
  }
}
