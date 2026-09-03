import QtQuick
import "parts"
import "../engine/engine.mjs" as Engine

// The powerup hand, and the keys that spend it.
//
// Design, Streaks and the powerup hand: "Keys: `1`, `2`, `3` choose a card; for
// a targeted card, left and right pick a rival, Enter confirms, Escape backs
// out. The picker is a small panel in the lower right, not a modal over the
// question, so the race stays visible."
//
// NOT A MODAL, AND THIS FILE IS WHERE THAT IS TRUE OR NOT. There is no scrim
// here, no full-bleed rectangle, no fill on the root item at all: the only
// pixels this screen paints are inside one panel anchored to the bottom-right
// corner. Everything the race screen draws -- the fact, the field, the track,
// the karts -- keeps drawing behind it. A hand arriving in the middle of a lap
// must not take the question off the screen, because the child is still
// answering it.
//
// ENTER CONFIRMS, FOR EVERY CARD. The design names Enter in the targeted case,
// where there is a rival to pick first. It is required here for the self and
// every-rival cards too, and that is a deliberate reading rather than an
// oversight: a hand costs the whole hand, `1` is next to the digits the child
// is typing at speed for the entire race, and a mistyped answer that fires a
// Turbo and throws away a Pile-Up is exactly the kind of loss the design's
// fairness section spends its length preventing. Choosing is one key; spending
// is two.
//
// ROUND 2 -- THIS PANEL IS DRIVEN, NOT FOCUSED. `ui/Race.qml` owns every key of
// the race, because the race screen is the only place that knows the expected
// answer and can therefore tell a card key from a digit. It calls `choose`,
// `stepTarget`, `confirm` and `back` on this panel and reads `chosen`,
// `needsTarget` and `targeting` back. The `Keys` handler below is still here
// and still correct, so the panel is a complete screen on its own in the
// harness, but in the game it never has focus and never fires.
//
// ROUND 2 -- ESCAPE HAS ONE MEANING AND NO ONE-WAY DOOR. The previous version
// emitted `dismissed()` when Escape was pressed with no card chosen, and
// printed `ESC HIDE` in the footer, and defined no key anywhere that brought
// the panel back. A held hand is not something a child can lose: the design
// says "You may hold a hand as long as you like", and the panel is not a modal,
// so there is nothing to hide from. Escape now backs out of a *choice* and
// nothing else, and with no choice made it is left unaccepted so the screen
// behind can use it to leave the race. That is the same "back one" meaning
// Escape has on every other screen in this game.
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

  // How many digits the child has already typed into the answer, which the host
  // reads off the engine's `racer.entry`. It is the arbiter between Enter the
  // submit key and Enter the spend key, and it is the host's to tell us because
  // the entry belongs to the race, not to this panel.
  property int entryLength: 0

  // Does Enter spend the card as things stand, or does the half-typed answer
  // own it? Standing on its own this panel's rule is the simple one -- an empty
  // field lets Enter spend -- and that is the default binding. `ui/Race.qml`
  // overrides it, because only the race screen knows which of the digits in the
  // field were typed by the very press that chose the card, and those digits
  // are not an answer the child is in the middle of.
  property bool enterSpends: picker.entryLength === 0

  // ROUND 4 -- THE DEFERRED DIGIT, AND THE KEY THAT WAS NEVER PRINTED.
  //
  // On the 23 facts in the 1-12 deck whose answer is a single digit, a card key
  // is ambiguous in a way no other press is: `1` on `2 x 3` is either "play card
  // one" or "the answer is 1", and handing it to the engine settles it as a
  // wrong answer on the spot. `ui/Race.qml` therefore parks the digit -- draws
  // it in the field, keeps it out of the engine -- and waits for the child to
  // say which it was. Enter says "it was my answer" and costs the streak.
  // Backspace says "it was a card" and costs nothing.
  //
  // Round three printed only the first of those. The footer read
  // `FINISH THE ANSWER FIRST      ESC  BACK`, which names the two keys that take
  // something away and hides the one that does not, and tells the child to do
  // the single most expensive thing available to them: finishing a one-digit
  // answer means typing one digit, and that flushes the parked digit as a wrong
  // answer FIRST -- streak gone, a `missed` entry and a darkened mastery lamp on
  // a fact the child then gets right on the very next keystroke. Backspace
  // appeared in no string on this panel, in its `Accessible.description`, or
  // anywhere else in the game. On 16% of the deck a child holding a hand had no
  // discoverable way to spend it.
  //
  // The host tells us the parked digit, because the field belongs to the race
  // and not to this panel. "" means there is none. Everything below is printing:
  // the arbitration in `ui/Race.qml` is unchanged by it.
  property string pendingDigit: ""
  readonly property bool deferred: picker.pendingDigit.length > 0

  // The deferred footer is the longest line this panel ever prints, and it is
  // the one line a child must be able to read. It goes on one row where the
  // panel is wide enough for it and breaks between two of its three groups
  // where it is not -- measured in the face the shell handed down rather than
  // guessed, and broken by hand rather than by `WordWrap`, which put `ANSWER`
  // and its digit on separate rows at 1366 x 768.
  readonly property int footerWidth: picker.dockWidth - picker.px(30)
  readonly property string deferredHead: "⌫  BACK TO THE CARD      ⏎  ANSWER " + picker.pendingDigit
  readonly property string deferredFooter: (deferredProbe.advanceWidth > 0
                                            && deferredProbe.advanceWidth <= picker.footerWidth)
                                           ? (picker.deferredHead + "      ESC  BACK")
                                           : (picker.deferredHead + "\nESC  BACK")

  TextMetrics {
    id: deferredProbe
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: picker.fsFloor(14, 15)
    font.letterSpacing: picker.px(1)
    text: picker.deferredHead + "      ESC  BACK"
  }

  // -1 is "no card chosen yet", which is the state a hand sits in for as long
  // as the child likes. The design: "You may hold a hand as long as you like."
  property int chosen: -1
  property int targetIndex: 0

  readonly property string chosenCard: (chosen >= 0 && chosen < hand.length)
                                       ? String(hand[chosen]) : ""
  // Does the chosen card need a rival at all? This is a property of the card
  // and nothing else, so it stays true when the rival list empties -- which is
  // the whole point. The old `targeting` folded "this card is targeted" and
  // "there is someone to aim at" into one flag, so a Pile-Up chosen with every
  // rival already home read as an untargeted card, printed `⏎ USE IT`, and
  // fired `cardUsed(index, "")` into a refusal the child never saw.
  readonly property bool needsTarget: chosenCard.length > 0
                                      && Engine.isCard(chosenCard)
                                      && Engine.CARDS[chosenCard].scope === "targeted"
  // Aiming is possible only when the card needs a rival AND one is left.
  readonly property bool targeting: needsTarget && picker.rivals.length > 0
  // True when the child has chosen a card that can never be spent as things
  // stand. The panel says so rather than swallowing the press.
  readonly property bool strandedTarget: needsTarget && picker.rivals.length === 0

  readonly property string targetId: (picker.targeting
                                      && targetIndex >= 0 && targetIndex < rivals.length)
                                     ? String(rivals[targetIndex].id) : ""
  readonly property string targetName: (picker.targeting
                                        && targetIndex >= 0 && targetIndex < rivals.length)
                                       ? String(rivals[targetIndex].name) : ""

  // index is the position in the hand, 0 to 2. targetId is "" for a card that
  // needs no rival.
  signal cardUsed(int index, string targetId)

  visible: hand.length > 0

  // Two invariants the previous version did not keep, and both were reachable
  // in a real Grand Prix.
  //
  //  - A rival crossing the line shrinks `rivals` under a live aim. The old
  //    `targetIndex` stayed where it was, `targetId` fell to "", and NO tile
  //    carried the `▸` marker -- a targeting panel aiming at nothing, with no
  //    shape and no text saying so. It is clamped back into range here.
  //  - A hand is dealt while a card is chosen. `chosen` was a plain writable
  //    int with no invariant, so a stale index survived into a hand that no
  //    longer had that card.
  onRivalsChanged: if (picker.targetIndex >= picker.rivals.length) picker.targetIndex = 0
  onHandChanged: if (picker.chosen >= picker.hand.length) picker.reset()

  Accessible.role: Accessible.Pane
  Accessible.name: "Power-up hand"
  // The deferred sentence comes first, because while a digit is parked it is the
  // only rule on this panel that costs anything, and a screen-reader user got no
  // version of it at all before. It names all three keys and what each one does.
  Accessible.description: picker.deferred
    ? ("The digit " + picker.pendingDigit + " is waiting in the answer box. "
       + "Backspace takes it back out and keeps the card chosen. "
       + "Enter answers " + picker.pendingDigit + " instead. "
       + "Escape puts the card back and takes the digit with it. "
       + "One, two and three still change which card is chosen."
       + (picker.targeting ? " Left and right pick a rival." : "")
       + " Using a card costs the whole hand.")
    : ("Press one, two or three to choose a card."
       + (picker.targeting
          ? " Left and right pick a rival, Enter uses it on " + picker.targetName + "."
          : (picker.strandedTarget
             ? " There is no rival left to aim at, so this card cannot be used."
             : " Enter uses it."))
       + " Escape puts the card back. Using a card costs the whole hand.")

  function choose(index) {
    if (index < 0 || index >= picker.hand.length)
      return
    picker.chosen = index
    picker.targetIndex = 0
  }

  function stepTarget(delta) {
    if (!picker.targeting)
      return
    var count = picker.rivals.length
    picker.targetIndex = ((picker.targetIndex + delta) % count + count) % count
  }

  function reset() {
    picker.chosen = -1
    picker.targetIndex = 0
  }

  // True when the card was actually spent. The old version returned nothing and
  // guarded only `chosen < 0`, so three reachable states fired `cardUsed` into
  // an engine refusal with nothing on screen changing: a stale index past the
  // end of a new hand, a targeted card with every rival home, and a targeted
  // card whose aim had fallen off a shrunk list.
  function confirm() {
    if (picker.chosen < 0 || picker.chosen >= picker.hand.length)
      return false
    if (picker.needsTarget && picker.targetId.length === 0)
      return false
    var index = picker.chosen
    var target = picker.needsTarget ? picker.targetId : ""
    picker.reset()
    picker.cardUsed(index, target)
    return true
  }

  // Backing out of a choice is free and always was. With nothing chosen there
  // is nothing to back out of, and the caller is told so, so the same Escape
  // can go on to mean "leave the race" on the screen behind.
  function back() {
    if (picker.chosen < 0)
      return false
    picker.reset()
    return true
  }

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3) {
      picker.choose(event.key - Qt.Key_1)
      // Deliberately NOT accepted: the same press is also the digit 1, 2 or 3,
      // and the screen behind has to see it. In the game the race screen sees
      // it first and arbitrates; this path is the standalone one.
      return
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
      if (picker.targeting) {
        picker.stepTarget(event.key === Qt.Key_Left ? -1 : 1)
        event.accepted = true
      }
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // A half-typed answer owns Enter. Only an empty field lets Enter spend a
      // card, which is what stops a submit from costing a hand.
      if (picker.enterSpends && picker.chosen >= 0)
        event.accepted = picker.confirm()
      return
    }
    if (event.key === Qt.Key_Escape) {
      event.accepted = picker.back()
      return
    }
    // Every other key is left unaccepted on purpose. The race screen behind
    // this panel is where the digits of an answer belong, and a picker that
    // swallowed them would stall the child mid-fact.
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
      border.color: picker.strandedTarget ? Theme.hazard
                                          : (picker.chosen >= 0 ? Theme.focusRing : Theme.amberDeep)
    }

    Column {
      id: body
      x: picker.px(15)
      y: picker.px(15)
      width: parent.width - picker.px(30)
      spacing: picker.px(9)

      // The rule the whole panel turns on sits beside the title where it fits
      // and drops to its own line where it does not. A `Row` clipped it
      // mid-word against the panel border at 1366 x 768, and the one line a
      // child must not lose is the one that says a card costs the hand.
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

      Repeater {
        model: picker.hand

        HandCard {
          width: body.width
          cardId: String(modelData)
          index: model.index + 1
          selected: picker.chosen === model.index
          scaleUnit: picker.s
          labelSize: picker.fsFloor(22, 18)
          detailSize: picker.fsFloor(14, 13)
        }
      }

      // ------------------------------------------------------- the target
      //
      // Only a targeted card asks this question, and it asks it in place rather
      // than in a second panel: the cards stay on screen, so a child who picked
      // the wrong one can see it and press Escape.
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
                readonly property bool aimed: picker.targeting && picker.targetIndex === model.index
                width: Math.floor((targetColumn.width - picker.px(8) * Math.max(0, picker.rivals.length - 1))
                                  / Math.max(1, picker.rivals.length))
                height: picker.px(46)
                radius: Theme.cornerRadiusSmall
                color: aimed ? Theme.selectedFill
                             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.06)
                border.width: aimed ? 2 : 1
                border.color: aimed ? Theme.focusRing : Theme.line

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

      // The keys, always visible, always the same. A child who has never held a
      // hand before finds out what to press by looking at the panel -- and when
      // a card cannot be spent, this line is where it says why, rather than the
      // press going nowhere in silence.
      //
      // ROUND 4 -- EVERY LINE NAMES KEYS AND WHAT THEY DO, not what the child
      // has failed to do. `FINISH THE ANSWER FIRST` was an instruction with a
      // price on it and no alternative printed beside it; it is gone. The
      // deferred line below names all three keys that reach the parked digit,
      // and it says what Enter would actually send -- `⏎  ANSWER 1`, with the
      // digit in it -- so the child can read the cost off the panel while the
      // fact is still on screen above them.
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        text: picker.chosen < 0
              ? "1 2 3  CHOOSE A CARD"
              : (picker.deferred
                 ? picker.deferredFooter
                 : (picker.strandedTarget
                    ? "ESC  BACK"
                    : (!picker.enterSpends
                       ? "⏎  SEND THE ANSWER      ESC  BACK"
                       : (picker.targeting
                          ? "◀ ▶  RIVAL      ⏎  USE      ESC  BACK"
                          : "⏎  USE IT      ESC  BACK"))))
        color: (picker.strandedTarget && !picker.deferred) ? Theme.hazard : Theme.text
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: picker.fsFloor(14, 15)
        font.letterSpacing: picker.px(1)
        lineHeight: 1.25
      }
    }
  }
}
