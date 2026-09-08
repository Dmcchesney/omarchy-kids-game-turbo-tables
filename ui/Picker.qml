import QtQuick
import "parts"
import "parts/CardFx.js" as CardFx
import "../engine/engine.mjs" as Engine

// The powerup hand, and the keys that spend it.
//
// Design v4.1, Streaks and the powerup hand: "digits never touch the hand; they
// are always the answer. While a hand is held, one card is highlighted (the
// first, by default), Left and Right move the highlight across the three
// cards, and Space fires the highlighted card. A targeted card fires at the
// nearest rival ahead; Up and Down change the target before firing, and the
// target's kart is ringed while it is chosen. Enter is only ever the answer
// key, Escape only ever leaves the race. Nothing is parked, deferred, or
// confirmed: choosing is a look, spending is one press of a key that can never
// be a digit."
//
// PIECE F ROUND 7 -- WHAT THIS FILE NO LONGER DOES, AND WHY.
//
// v4 gave `1`, `2` and `3` to the hand, and a third of the answers in the 1-12
// tables begin with one of them. Four rounds of `ui/Race.qml` arbitrated the
// collision -- a digit parked in the field, a digit deferred on the 23
// single-digit facts, Enter meaning "the card" or "the answer" depending on
// who typed what, Backspace meaning "it was a card", a one-beat line that said
// a choice had been let go -- and this panel printed every branch of it:
// `1 2 3  CHOOSE A CARD`, `⌫  BACK TO THE CARD`, `⏎  ANSWER 1`, `⏎  SEND THE
// ANSWER`, `ESC  BACK`. The maintainer played it and said the hand was
// unreliable to fire. He was right, and the fix is not a fifth explanation:
// every one of those states existed only because a card key was also a digit.
// None of them exists now. There is no `chosen` that can be -1 while a hand is
// held, no `pendingDigit`, no `enterSpends`, no `letGo` line, no back-out
// chip, and the panel's footer has exactly the keys the design names.
//
// NOT A MODAL, AND THIS FILE IS WHERE THAT IS TRUE OR NOT. There is no scrim
// here, no full-bleed rectangle, no fill on the root item at all: the only
// pixels this screen paints are inside one panel anchored to the bottom-right
// corner. Everything the race screen draws -- the fact, the field, the track,
// the karts -- keeps drawing behind it.
//
// THIS PANEL IS DRIVEN, NOT FOCUSED. `ui/Race.qml` owns every key of the race
// and calls `moveHighlight`, `stepTarget` and `fire` on this panel; it reads
// `highlighted`, `targeting` and `targetId` back, and hands `targetId` to the
// track so the aimed kart is ringed. The `Keys` handler below is the same
// three keys, so the panel is a complete screen on its own in the harness.
//
// PIECE F ROUND 8 -- THE PANEL DOES NOT DECIDE A CARD WAS SPENT. THE ENGINE
// DOES.
//
// Round 7's `fire()` played the slam sound, copied the hand into the fly-off,
// reset the highlight and emitted `cardUsed` on its own say-so, and only THEN
// did the race screen ask the engine. A blind critic pressed Space after the
// child had crossed the line: the slam played, the engine refused (a finished
// racer cannot attack), and 570 ms later the three cards were drawn back on
// the panel. The same shape let Space spend a hand the child had not yet seen
// (the cards were still under the panel at opacity zero) and armed the repeat
// guard for a press that fired nothing.
//
// So `fire()` now REQUESTS a play -- `playRequested(index, targetId)` -- and
// keeps a copy of what it asked for. Nothing on the panel changes until the
// host calls `accept()`, which it does from the engine's own `cardUsed` event
// and from nowhere else: that is where the slam starts, the sound plays, the
// highlight goes home and `cardUsed` is emitted. A request the engine does not
// take is a request that never happened on screen. `canFire` is the whole list
// of reasons a request would be pointless -- the hand still being dealt, a
// targeted card with nobody left to aim at, the child already finished, the
// slam already playing -- and both Space handlers read it BEFORE they take the
// repeat guard, so a refused press arms nothing.
//
// STANDING ALONE there is no engine to answer. `hosted` is false, and `fire()`
// accepts its own request on the spot, because the harness's panel has to be
// able to show its slam and the mouse suite counts `cardUsed` off it. The race
// screen sets `hosted: true`, and from then on the panel never accepts a play
// the rules did not.
FocusScope {
  id: picker

  readonly property Item focusTarget: picker

  // --------------------------------------------------------------- scaling
  readonly property real s: Math.max(0.42, Math.min(width / 1920, height / 1080))
  function px(v) { return Math.round(v * s) }
  function fs(v) { return Math.max(8, Math.round(v * s)) }
  // A floor for the lines that teach a child which key to press. `fs` alone
  // put the footer at 10 px and the tier word at 9 px on a 1366 x 768 screen,
  // which is the size this game is most likely to be played at. The panel is
  // allowed to be small; the instructions are not.
  function fsFloor(v, floor) { return Math.max(floor, Math.round(v * s)) }

  // The key rail as it is actually RENDERED. `footerHints` below is the model
  // the footer's chips are BUILT from -- each chip's printed line is
  // `keys + "  " + action` off one of these objects -- so joining them is
  // reading the same thing the panel draws, one step earlier.
  readonly property string footerText: {
    var line = ""
    var hints = picker.footerHints
    for (var i = 0; i < hints.length; i++) {
      if (i > 0)
        line += "      "
      line += hints[i].keys + "  " + hints[i].action
    }
    return line
  }

  // ------------------------------------------------------------- the panel
  // The dock's own geometry, so a host can line its charge bar up with the
  // panel instead of drawing on top of it.
  property int dockWidth: picker.px(500)
  property int dockMargin: picker.px(28)
  readonly property int dockHeight: picker.visible ? dock.height : 0

  // ------------------------------------------------------------- the hand
  //
  // The host hands the live hand down. Standing on its own -- in the harness,
  // or before a hand has ever been dealt -- it shows the hand the engine
  // actually deals first, off the shared round-robin cursor at zero. The
  // design fixes that hand: "The first hand of a race is always Nitro, Oil
  // Slick, Wrench."
  property var hand: Engine.dealHand(Engine.CARD_SCHEDULE, 0).hand

  // Who a targeted card can be aimed at, as { id, name, number }. The race
  // screen passes the racers who are still in the fight; a finished racer
  // "cannot attack and cannot be attacked", so it is the caller's list and not
  // a list this panel invents.
  property var rivals: [
    { "id": "bolt", "name": Theme.rivalNames[0], "number": Theme.rivalNumbers[0] },
    { "id": "piston", "name": Theme.rivalNames[1], "number": Theme.rivalNumbers[1] },
    { "id": "gasket", "name": Theme.rivalNames[2], "number": Theme.rivalNumbers[2] }
  ]

  property int seed: 42

  // THE ONE GUARD NAME ON THIS PANEL. `SPACE  USE IT` spends the whole hand and
  // cannot be undone, and the instant it acts the panel goes with the hand --
  // so the second half of a double-click on it lands on whatever the race
  // draws there next. The chip declares `handFooter`, and the Space key in
  // `ui/Race.qml` and in the handler below take the same name, so a click and
  // a press inside one double-click interval are one gesture whichever hand
  // made them. See `ui/parts/Actions.qml`.
  readonly property var fireGuards: ["handFooter"]

  // THE FOOTER, AS THE LIST OF CONTROLS IT IS.
  //
  // Every group of the printed key rail -- the keys, and what they do -- with
  // the mouse's own route to the same thing beside it. The `Flow` at the foot
  // of the panel renders one `KeyHint` per entry and `footerText` joins them,
  // so there is one place a footer state is written down and the words a child
  // reads are the words the click acts on.
  //
  //   ◀ ▶  PICK     moves the highlight. Not guarded: choosing is free and a
  //                 child hammering it means it every time.
  //   ▲ ▼  AIM      only while the highlighted card needs a rival. Not guarded,
  //                 for the same reason.
  //   SPACE  USE IT spends the hand. Destructive, guarded, and the only line on
  //                 this panel that costs anything.
  //
  // `act` is a name rather than a closure because a `var` model of closures is
  // rebuilt on every binding change and each rebuild would hand the delegates
  // new functions; `footerAct` below is the switch.
  readonly property var footerHints: {
    var hints = [{ "keys": "◀ ▶", "action": "PICK", "act": "nextCard",
                   "name": "Next card", "does": "highlight the next card",
                   "key": "Left, Right", "warn": false, "destructive": false,
                   // This chip highlights the NEXT card, so of the two keys it
                   // prints only Right does what it does; Left goes the other
                   // way and is on the chip because the child has both.
                   "keyRoute": ["right"],
                   "guards": [],
                   "help": "Highlights the next card. Left and right do it too." }]
    if (picker.targeting)
      hints.push({ "keys": "▲ ▼", "action": "AIM", "act": "nextRival",
                   "name": "Next rival", "does": "aim at the next rival",
                   "key": "Up, Down", "warn": false, "destructive": false,
                   "keyRoute": ["down"],
                   "guards": [],
                   "help": "Aims at the next rival. Up and down do it too." })
    if (!picker.strandedTarget && !picker.finished)
      hints.push(picker.useHint(picker.targeting ? "USE" : "USE IT"))
    return hints
  }

  // `USE` after the rival picker, `USE IT` without one: the two words this
  // panel has always printed on the one control that spends a hand.
  function useHint(word) {
    return { "keys": "SPACE", "action": word, "act": "use", "name": "Use the card",
             "does": "use " + (picker.highlightedCard.length > 0 && Engine.isCard(picker.highlightedCard)
                               ? String(Engine.CARDS[picker.highlightedCard].label)
                               : "the card"),
             "key": "Space", "warn": false, "destructive": true,
             "guards": picker.fireGuards,
             "help": "Uses the highlighted card. Using one spends all three."
                     + " The space bar does it too." }
  }

  function footerAct(act) {
    // NOTHING ON THIS PANEL ACTS WHILE THE HAND IS FLYING OFF. `shownHand`
    // keeps drawing the spent cards for the length of the slam, and a press on
    // a footer for a hand that has already been played is a press with no rule
    // behind it.
    if (picker.slamming)
      return
    if (act === "nextCard")
      picker.moveHighlight(1)
    else if (act === "nextRival")
      picker.stepTarget(1)
    else if (act === "use")
      picker.fire()
  }

  // The `SPACE  USE IT` chip is a click target, and a click on it while the
  // hand is still being dealt would take the repeat guard for a press that
  // fires nothing -- the same defect as the key's, by the other hand. The chip
  // is disabled for exactly the moments `canFire` is false and stays printed,
  // so the footer does not reflow under the pointer.
  readonly property bool useChipEnabled: picker.canFire

  // ======================================================== PIECE F: FEEL
  //
  // Design v4, "The hand and the charge", in full:
  //
  //   "Reaching twelve: the charge bar flashes, the twelve segments burst into
  //    three cards that slide up from the bottom right with a deal sound, and
  //    POWER-UP READY reads once. An unused hand breathes gently so the child
  //    remembers it.
  //    Choosing: the chosen card enlarges for 150, then slams down and
  //    dissolves into the telegraph. The other two flip face down and fly off;
  //    the charge bar shows empty."
  //
  // Three beats, and all three are pure functions of `fxNow` -- which is
  // `TrackView.fxClock`, handed down by ui/Race.qml. This panel starts no timer
  // and runs no animation, for the same reason nothing in the effect layer
  // does: a frame strip has to be reproducible, and an animation started on a
  // key press is not.
  //
  // THE HAND OUTLIVES ITSELF FOR 570 ms, ON PURPOSE. Spending a card spends the
  // whole hand, so by the time the slam should be drawn the engine has already
  // taken all three cards away and `hand` is empty. `fire()` therefore keeps a
  // copy -- the cards, and which one was highlighted -- and the panel draws
  // that copy until the fly-off is over.
  property real fxNow: 0

  property real dealBorn: -1e9
  readonly property real dealT: picker.fxNow - picker.dealBorn
  readonly property bool dealing: picker.dealT >= 0 && picker.dealT < CardFx.HAND.dealMs * 1.6
  function deal() { picker.dealBorn = picker.fxNow }

  property real slamBorn: -1e9
  property var slamHand: []
  property int slamChosen: -1
  readonly property real slamT: picker.fxNow - picker.slamBorn
  readonly property real slamSpan: CardFx.HAND.enlargeMs + CardFx.HAND.slamMs + CardFx.HAND.flyMs
  readonly property bool slamming: picker.slamT >= 0 && picker.slamT < picker.slamSpan

  // What the panel actually draws: the live hand, or the hand that is on its
  // way out.
  readonly property var shownHand: picker.hand.length > 0
                                   ? picker.hand
                                   : (picker.slamming ? picker.slamHand : [])

  // "An unused hand breathes gently so the child remembers it." 0.38 Hz -- an
  // eighth of the design's 3 Hz cap -- and it is a fade in the border rather
  // than a blink, so it never reads as an alarm. Every held hand is an unused
  // hand now: a highlight is a look, not a choice, so the breath stays.
  readonly property real breathe: (picker.reducedMotion
                                   || picker.hand.length === 0 || picker.slamming)
                                  ? 0
                                  : 0.5 + 0.5 * Math.sin(picker.fxNow / CardFx.HAND.breatheMs
                                                         * Math.PI * 2)
  property bool reducedMotion: false

  // ------------------------------------------------------- the highlight
  //
  // WHICH CARD SPACE WOULD FIRE. Never -1 while a hand is held: the design says
  // the first card is highlighted by default, so a child who has never pressed
  // an arrow can fire with one press of Space. Left and Right move it and wrap.
  property int highlighted: 0
  property int targetIndex: 0

  readonly property string highlightedCard: (picker.hand.length > 0
                                             && picker.highlighted >= 0
                                             && picker.highlighted < picker.hand.length)
                                            ? String(picker.hand[picker.highlighted]) : ""
  // Does the highlighted card need a rival at all? This is a property of the
  // card and nothing else, so it stays true when the rival list empties --
  // which is the whole point: a Pile-Up highlighted with every rival already
  // home is a card that cannot be fired, and the panel says so rather than
  // firing `cardUsed(index, "")` into an engine refusal.
  readonly property bool needsTarget: highlightedCard.length > 0
                                      && Engine.isCard(highlightedCard)
                                      && Engine.CARDS[highlightedCard].scope === "targeted"
  // Aiming is possible only when the card needs a rival AND one is left.
  readonly property bool targeting: needsTarget && picker.rivals.length > 0
  // True when the highlighted card can never be spent as things stand.
  readonly property bool strandedTarget: needsTarget && picker.rivals.length === 0

  // EVERY REASON A REQUEST WOULD BE POINTLESS, in one predicate, read by both
  // Space handlers before the repeat guard is taken. The engine would refuse
  // each of these; the panel refuses first, so nothing on screen pretends.
  //
  //   slamming   a hand is already flying off
  //   dealing    the cards are still sliding up under the panel: a child who
  //              has learned "Space fires" and taps it as the twelfth answer
  //              lands must not spend a hand blind
  //   finished   the child has crossed the line
  //   the highlight is past the end of the hand
  //   a targeted card with nobody left to aim at
  readonly property bool canFire: picker.hand.length > 0
                                  && !picker.slamming
                                  && !picker.dealing
                                  && !picker.finished
                                  && picker.highlighted >= 0
                                  && picker.highlighted < picker.hand.length
                                  && !(picker.needsTarget && picker.targetId.length === 0)

  readonly property string targetId: (picker.targeting
                                      && targetIndex >= 0 && targetIndex < rivals.length)
                                     ? String(rivals[targetIndex].id) : ""
  readonly property string targetName: (picker.targeting
                                        && targetIndex >= 0 && targetIndex < rivals.length)
                                       ? String(rivals[targetIndex].name) : ""

  // ROUND 8. The host answers requests; see the file comment. False on a panel
  // standing alone, where `fire()` is its own engine.
  property bool hosted: false

  // The host's racer has crossed the line. A finished racer "cannot attack and
  // cannot be attacked", so the hand it still holds is a hand it cannot play,
  // and the panel says so rather than firing into a refusal.
  property bool finished: false

  // What `fire()` asked for, kept until the engine answers: the hand as it was
  // (the engine empties `hand` in the same step that says yes, and the slam
  // needs the three cards to draw) and which slot was fired. -1 while nothing
  // is asked.
  property var pendingHand: []
  property int pendingIndex: -1

  // The request. index is the position in the hand, 0 to 2. targetId is "" for
  // a card that needs no rival. The host sends `useCard` to the engine with it.
  signal playRequested(int index, string targetId)

  // The answer. Emitted from `accept()` -- on the engine's `cardUsed`, or on
  // the spot when the panel stands alone -- and never from `fire()` itself.
  signal cardUsed(int index, string targetId)

  visible: picker.hand.length > 0 || picker.slamming

  // Two invariants, both reachable in a real Grand Prix.
  //
  //  - A rival crossing the line shrinks `rivals` under a live aim. The old
  //    `targetIndex` stayed where it was, `targetId` fell to "", and NO tile
  //    carried the `▸` marker. It is clamped back into range here.
  //  - A hand is dealt while a highlight is past its end. The highlight goes
  //    back to the first card, which is where a fresh hand starts.
  onRivalsChanged: if (picker.targetIndex >= picker.rivals.length) picker.targetIndex = 0
  onHandChanged: if (picker.highlighted >= picker.hand.length) picker.reset()

  Accessible.role: Accessible.Pane
  Accessible.name: "Power-up hand"
  Accessible.description: "Left and right highlight a card. "
    + (picker.finished
       ? "You have finished the race, so the hand cannot be used."
       : (picker.targeting
          ? "Up and down pick a rival. Space uses it on " + picker.targetName + "."
          : (picker.strandedTarget
             ? "There is no rival left to aim at, so this card cannot be used."
             : "Space uses it.")))
    + " Using a card costs the whole hand."

  // Put the highlight on one card, from a click or from the arrows landing
  // there. Choosing costs nothing and is never guarded.
  //
  // ROUND 8: THE AIM BELONGS TO THE HAND, NOT TO THE CARD. Round 7 put the aim
  // back on the nearest rival every time the highlight moved, so a child who
  // aimed a Wrench at Piston, glanced Right at the Nitro and came back Left
  // found the ring on Bolt again. The aim now stays where the child put it
  // across every highlight change; it goes home on a deal (`reset`) and is
  // clamped when a rival crosses the line (`onRivalsChanged`), and at no other
  // time.
  function highlight(index) {
    if (index < 0 || index >= picker.hand.length)
      return
    picker.highlighted = index
  }

  function moveHighlight(delta) {
    var count = picker.hand.length
    if (count === 0)
      return
    picker.highlight(((picker.highlighted + delta) % count + count) % count)
  }

  // A click on a card is the arrows landing on it, and nothing more. Spending
  // is the footer's own line, exactly as it is Space on the keyboard -- design
  // v4.2: "clicking a card chooses it and clicking the footer's own line
  // spends it". A double-click on a card therefore cannot spend a hand, which
  // is the round-2 defect of piece M and the maintainer's own complaint.
  function tapCard(index) {
    if (picker.slamming)
      return
    picker.highlight(index)
  }

  // Clicking a rival is Up or Down landing on that rival: it aims, it does
  // not fire.
  function tapRival(index) {
    if (!picker.targeting || index < 0 || index >= picker.rivals.length)
      return
    picker.targetIndex = index
  }

  function stepTarget(delta) {
    if (!picker.targeting)
      return
    var count = picker.rivals.length
    picker.targetIndex = ((picker.targetIndex + delta) % count + count) % count
  }

  // The host's way of putting the panel back to where a hand starts: the first
  // card highlighted, the nearest rival aimed at. A new race, a new hand.
  function reset() {
    picker.highlighted = 0
    picker.targetIndex = 0
  }

  // SPACE. True when a play was REQUESTED -- not spent. Every state in which
  // the engine would refuse is refused here first (`canFire`), with nothing on
  // screen changing and nothing armed. What the panel keeps is a copy of the
  // hand and the slot, for the slam the engine's answer will start.
  function fire() {
    if (!picker.canFire)
      return false
    var index = picker.highlighted
    var target = picker.needsTarget ? picker.targetId : ""
    picker.pendingHand = picker.hand.slice()
    picker.pendingIndex = index
    if (!picker.hosted) {
      // No engine to ask. The panel standing alone is its own rules.
      picker.accept(target)
      return true
    }
    picker.playRequested(index, target)
    return true
  }

  // THE ENGINE SAID YES. Called by the host on its `cardUsed` event for the
  // child's own play. Only a play this panel asked for gets the slam: a card
  // the harness injects straight into the engine (`--inject cardUsed:wrench`)
  // arrives here with nothing pending, and the panel goes back to where a hand
  // starts without pretending a child pressed anything.
  function accept(targetId) {
    var index = picker.pendingIndex
    var asked = picker.pendingHand
    picker.pendingHand = []
    picker.pendingIndex = -1
    if (index < 0) {
      picker.reset()
      return
    }
    // Keep the hand that has just been taken away, and which card of it was
    // fired, so the slam and the fly-off have something to draw.
    picker.slamHand = asked
    picker.slamChosen = index
    picker.slamBorn = picker.fxNow
    // "the chosen card enlarges for 150, then slams down". The sound is the
    // slam's: highlighting costs nothing and says nothing, and a request the
    // engine refused says nothing either.
    Sfx.play("slam")
    picker.reset()
    picker.cardUsed(index, targetId === undefined ? "" : String(targetId))
  }

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      picker.moveHighlight(event.key === Qt.Key_Left ? -1 : 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      if (picker.targeting) {
        picker.stepTarget(event.key === Qt.Key_Up ? -1 : 1)
        event.accepted = true
      }
      return
    }
    if (event.key === Qt.Key_Space) {
      // A press that could not fire anything takes no guard: the child's next
      // press must not be refused for it. Then the same guard the `SPACE  USE
      // IT` chip declares, so a click on the chip and this key inside one
      // double-click interval are one gesture.
      if (!picker.canFire) {
        event.accepted = true
        return
      }
      if (!Actions.take(picker.fireGuards, "key")) {
        event.accepted = true
        return
      }
      event.accepted = picker.fire()
      return
    }
    // Every other key is left unaccepted on purpose. The race screen behind
    // this panel is where the digits of an answer belong, and Escape is the
    // race's, and only ever leaves.
  }

  // ------------------------------------------------------------- the panel
  Item {
    id: dock
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: picker.dockMargin
    anchors.bottomMargin: picker.dockMargin
    width: picker.dockWidth
    height: body.height + picker.px(30)

    Rectangle {
      anchors.fill: parent
      radius: Theme.cornerRadius
      color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.94)
      border.width: 2
      border.color: picker.strandedTarget ? Theme.hazard : Theme.amberDeep
    }

    Column {
      id: body
      x: picker.px(15)
      y: picker.px(15)
      width: parent.width - picker.px(30)
      spacing: picker.px(9)

      // The rule the whole panel turns on sits beside the title where it fits
      // and drops to its own line where it does not.
      Flow {
        width: parent.width
        spacing: picker.px(10)

        Text {
          textFormat: Text.PlainText
          text: "POWER-UP HAND"
          color: Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: picker.fsFloor(18, 15)
          font.letterSpacing: picker.px(3)
        }
        Text {
          textFormat: Text.PlainText
          text: "USING ONE SPENDS ALL THREE"
          color: Theme.textLabel
          font.family: Theme.mono
          font.pixelSize: picker.fsFloor(13, 12)
          font.letterSpacing: picker.px(1)
        }
      }

      // THREE ACROSS, NOT THREE DOWN. `ui/parts/HandCard.qml` draws a portrait
      // card in playing-card proportions; this is the hand it is laid out in.
      Row {
        // NOT `id: hand`: a file-scope id beats the root object's own property
        // in QML's unqualified lookup, and that shadowing once disabled every
        // targeted card in the deck for a whole round.
        id: handRow
        width: parent.width
        spacing: picker.px(9)
        readonly property real cardWidth: Math.floor((width - spacing * 2) / 3)

      Repeater {
        model: picker.shownHand

        // PIECE F. The three beats of the hand, each one a function of the
        // panel's clock and of nothing else.
        //
        //   deal    the card slides up from the bottom right and fades in,
        //           staggered a sixth of the deal apart so three cards arrive
        //           as three cards
        //   breathe an unused hand's gentle fade
        //   slam    the fired card enlarges for 150 then slams down; the other
        //           two flip face down (a scale through zero in x, which is
        //           what a card turning over is) and fly off to the right
        Item {
          id: cardSlot
          readonly property int slot: index
          readonly property bool isChosen: picker.slamming
                                           ? picker.slamChosen === slot
                                           : picker.highlighted === slot
          readonly property real dealU: picker.dealing
                                        ? Math.max(0, Math.min(1,
                                            (picker.dealT - slot * CardFx.HAND.dealMs / 6)
                                            / CardFx.HAND.dealMs))
                                        : 1
          readonly property real slamU: picker.slamming
                                        ? picker.slamT / picker.slamSpan : -1
          readonly property real enlargeEnd: CardFx.HAND.enlargeMs / picker.slamSpan
          readonly property real slamEnd: (CardFx.HAND.enlargeMs + CardFx.HAND.slamMs)
                                          / picker.slamSpan

          width: handRow.cardWidth
          height: card.implicitHeight

          HandCard {
            id: card
            width: handRow.cardWidth
            cardId: String(modelData)
            index: cardSlot.slot + 1
            selected: cardSlot.isChosen && !picker.slamming
            scaleUnit: picker.s
            labelSize: picker.fsFloor(22, 18)
            detailSize: picker.fsFloor(14, 13)
            breathe: picker.breathe
            // The presses that put the highlight on THIS card from where it
            // is: none if it is already there, otherwise Right as many times
            // as it is round the hand. `test_29` presses exactly this and
            // demands the same screen the click left.
            keyRoute: {
              var count = picker.hand.length
              if (count <= 0)
                return []
              var steps = ((cardSlot.slot - picker.highlighted) % count + count) % count
              var route = []
              for (var i = 0; i < steps; i++)
                route.push("right")
              return route
            }

            // A click highlights, exactly as the arrows do. Dead while the hand
            // is flying off.
            onTapped: picker.tapCard(cardSlot.slot)

            // ROUND 8: NOT A CLICK TARGET WHILE IT IS BEING DEALT. The same
            // rule as Space's and the `USE IT` chip's, by the third hand: a
            // card still sliding up under the panel is a card the child has
            // not seen. It is also what keeps the pointer honest during the
            // slide -- the cards come up from under the footer's chips, and
            // Qt hands the hover to the chip on top even while that chip is
            // disabled, so a card mid-deal under the pointer could not report
            // it. `tests/qml/tst_mouse_parity.qml` test_32 sweeps the race
            // screen the moment it is shown and found exactly that.
            enabled: !picker.dealing

            // The deal: up from the bottom right.
            y: picker.reducedMotion ? 0
               : (1 - CardFx.easeOut(cardSlot.dealU)) * picker.dockWidth * 0.30
            opacity: Math.min(1, cardSlot.dealU * 2.4)
                     * (cardSlot.slamU < 0 ? 1
                        : (cardSlot.isChosen
                           ? (cardSlot.slamU < cardSlot.slamEnd ? 1
                              : 1 - (cardSlot.slamU - cardSlot.slamEnd)
                                    / Math.max(0.001, 1 - cardSlot.slamEnd))
                           : Math.max(0, 1 - cardSlot.slamU / Math.max(0.001, cardSlot.slamEnd + 0.35))))
            transformOrigin: Item.Center
            // The fired card: enlarge, then slam.
            scale: (picker.reducedMotion || cardSlot.slamU < 0) ? 1
                   : (cardSlot.isChosen
                      ? (cardSlot.slamU < cardSlot.enlargeEnd
                         ? 1 + 0.16 * CardFx.easeOut(cardSlot.slamU / cardSlot.enlargeEnd)
                         : (cardSlot.slamU < cardSlot.slamEnd
                            ? 1.16 - 0.30 * CardFx.easeIn((cardSlot.slamU - cardSlot.enlargeEnd)
                                                          / Math.max(0.001, cardSlot.slamEnd - cardSlot.enlargeEnd))
                            : 0.86))
                      : 1)
            // The other two: flip face down, then fly off to the right.
            transform: [
              Scale {
                origin.x: card.width / 2
                origin.y: card.height / 2
                xScale: (picker.reducedMotion || cardSlot.slamU < 0 || cardSlot.isChosen)
                        ? 1
                        : Math.max(0.02, Math.cos(Math.min(1, cardSlot.slamU / Math.max(0.001, cardSlot.slamEnd))
                                                  * Math.PI * 0.5))
              },
              Translate {
                x: (picker.reducedMotion || cardSlot.slamU < cardSlot.slamEnd || cardSlot.isChosen)
                   ? 0
                   : CardFx.easeIn((cardSlot.slamU - cardSlot.slamEnd)
                                   / Math.max(0.001, 1 - cardSlot.slamEnd)) * picker.dockWidth * 1.2
              }
            ]
          }
        }
      }
      }

      // ------------------------------------------------------- the target
      //
      // Only a targeted card asks this question, and it asks it in place rather
      // than in a second panel: the cards stay on screen, so a child who
      // highlighted the wrong one can see it and press Left or Right.
      Item {
        width: parent.width
        height: picker.needsTarget ? targetColumn.height + picker.px(10) : 0
        clip: true
        visible: picker.needsTarget

        Column {
          id: targetColumn
          y: picker.px(10)
          width: parent.width
          spacing: picker.px(6)

          Text {
            textFormat: Text.PlainText
            text: picker.strandedTarget ? "NOBODY LEFT TO AIM AT" : "AIM AT"
            color: picker.strandedTarget ? Theme.hazard : Theme.teal
            font.family: Theme.mono
            font.bold: true
            font.pixelSize: picker.fsFloor(14, 13)
            font.letterSpacing: picker.px(2)
          }

          Row {
            spacing: picker.px(8)
            visible: picker.rivals.length > 0

            Repeater {
              model: picker.rivals

              Rectangle {
                id: aimTile
                readonly property bool aimed: picker.targeting && picker.targetIndex === model.index
                width: Math.floor((targetColumn.width - picker.px(8) * Math.max(0, picker.rivals.length - 1))
                                  / Math.max(1, picker.rivals.length))
                height: picker.px(46)
                radius: Theme.cornerRadiusSmall
                color: aimed ? Theme.selectedFill
                             : (aimHit.hovered
                                ? Theme.hoverFill
                                : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.06))
                border.width: aimed ? 2 : 1
                border.color: aimed ? Theme.focusRing
                                    : (aimHit.hovered ? Theme.hoverRing : Theme.line)

                // Selection is not focus: "this is the rival you are aiming
                // at" and "your pointer is here" are two different facts and
                // the child wants both. A second ring inside the aimed one.
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: 3
                  visible: aimHit.hovered && aimTile.aimed
                  radius: Theme.cornerRadiusSmall
                  color: "transparent"
                  border.width: 1
                  border.color: Theme.hoverRing
                }

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  // The arrow is the state, not the colour: the design's
                  // accessibility rule again.
                  text: (parent.aimed ? "▸ " : "") + String(modelData.name)
                  color: parent.aimed ? Theme.textBright : Theme.textLabel
                  font.family: Theme.mono
                  font.bold: true
                  font.pixelSize: picker.fsFloor(16, 14)
                  font.letterSpacing: picker.px(1)
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Aim at " + String(modelData.name)
                    + (aimTile.aimed ? ", aimed" : "")
                Accessible.description: "Up and down pick a rival. Then use the card."
                Accessible.onPressAction: picker.tapRival(model.index)

                Clickable {
                  id: aimHit
                  objectName: "clickAimRival"
                  enabled: picker.targeting
                  stop: null
                  label: "aim " + String(modelData.name)
                  does: "aim at " + String(modelData.name)
                  key: "Up, Down"
                  // The arrows STEP round the rivals and a click LANDS on one,
                  // so the crossover presses Down as many times as this tag is
                  // round the ring from the aim that is on.
                  keyRoute: {
                    var count = picker.rivals ? picker.rivals.length : 0
                    if (count <= 0)
                      return []
                    var steps = ((model.index - picker.targetIndex) % count + count) % count
                    var route = []
                    for (var i = 0; i < steps; i++)
                      route.push("down")
                    return route
                  }
                  onActed: picker.tapRival(model.index)
                }
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Theme.line
      }

      // The keys, always visible, always the same three. A child who has never
      // held a hand before finds out what to press by looking at the panel.
      // Every group of the line is a `KeyHint`: the same words, the same
      // grammar, each one a control that does what it says. `footerHints` is
      // the single model both the chips and `footerText` are built from.
      Flow {
        id: footerFlow
        width: parent.width
        spacing: picker.px(18)

        Repeater {
          model: picker.footerHints

          KeyHint {
            keys: modelData.keys
            action: modelData.action
            cap: true
            textSize: picker.fsFloor(14, 15)
            letterSpacing: picker.px(1)
            idleColor: modelData.warn ? Theme.hazard : Theme.text
            liveColor: Theme.textBright
            padWidth: picker.px(14)
            padHeight: picker.px(8)
            name: modelData.name
            does: modelData.does
            key: modelData.key
            keyRoute: modelData.keyRoute !== undefined ? modelData.keyRoute : null
            guards: modelData.guards !== undefined ? modelData.guards : []
            destructive: modelData.destructive === true
            help: modelData.help
            enabled: modelData.act !== "use" || picker.useChipEnabled
            onTapped: picker.footerAct(modelData.act)
          }
        }
      }
    }
  }
}
