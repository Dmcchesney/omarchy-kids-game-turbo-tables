import QtQuick
import "parts"
import "parts/CardFx.js" as CardFx
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

  // The key rail as it is actually RENDERED. A round of this project shipped
  // the claim that "the panel prints the way back" over a key that appeared in
  // no string a child could see, so this may never be a second copy of the
  // footer's words.
  //
  // ROUND 2: it is not one. `footerHints` below is the model the footer's chips
  // are BUILT from -- each chip's printed line is `keys + "  " + action` off one
  // of these objects -- so joining them is reading the same thing the panel
  // draws, one step earlier. And the claim is now checked from outside as well:
  // `dev/Harness.qml --print-controls` walks the rendered item tree, finds every
  // visible Text that is shaped like a printed key hint, and fails the screen
  // when one of them has no click target over it.
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
  // The same, for the one-beat line above it: "" whenever it is not showing.
  readonly property string letGoLineText: letGoLine.visible ? letGoLine.text : ""

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

  // ======================================================== PIECE M ROUND 2
  //
  // THE FOOTER, AS THE LIST OF CONTROLS IT IS.
  //
  // Every group of the printed key rail -- the keys, and what they do -- with
  // the mouse's own route to the same thing beside it. The `Flow` at the foot
  // of the panel renders one `KeyHint` per entry and `footerText` joins them,
  // so there is one place a footer state is written down and the words a child
  // reads are the words the click acts on.
  //
  // `act` is a name rather than a closure because a `var` model of closures is
  // rebuilt on every binding change and each rebuild would hand the delegates
  // new functions; `footerAct` below is the switch, and it calls the same
  // functions the panel's own key handler calls.
  //
  // The deferred line used to need a `TextMetrics` probe to decide whether it
  // fitted on one row. The `Flow` wraps between groups on its own, at any panel
  // width, which is what the probe was approximating.
  readonly property var footerHints: {
    if (picker.chosen < 0)
      return [{ "keys": "1 2 3", "action": "CHOOSE A CARD", "act": "chooseFirst",
                "name": "Choose a card", "does": "choose the first card",
                "key": "1", "warn": false, "destructive": false,
                "guards": ["handFooter"],
                "help": "Choose the first card. The 1, 2 and 3 keys choose a card each." }]
    if (picker.deferred)
      return [{ "keys": "⌫", "action": "BACK TO THE CARD", "act": "undoDigit",
                "name": "Back to the card",
                "does": "take the digit back out of the answer and keep the card",
                "key": "Backspace", "warn": false, "destructive": false,
                "guards": ["handFooter"],
                "help": "Takes the " + picker.pendingDigit + " back out of the answer"
                        + " box and keeps the card chosen. Backspace does it too." },
              { "keys": "⏎", "action": "ANSWER " + picker.pendingDigit, "act": "submit",
                "name": "Answer the parked digit",
                "does": "send " + picker.pendingDigit + " as the answer",
                "key": "Enter", "warn": false, "destructive": true,
                "guards": ["handFooter"],
                "help": "Sends " + picker.pendingDigit + " as the answer instead."
                        + " Enter does it too." },
              picker.backHint()]
    if (picker.strandedTarget)
      return [picker.backHint(true)]
    if (!picker.enterSpends)
      return [{ "keys": "⏎", "action": "SEND THE ANSWER", "act": "submit",
                "name": "Send the answer", "does": "send what is in the answer box",
                "key": "Enter", "warn": false, "destructive": true,
                "guards": ["handFooter"],
                "help": "Sends what is in the answer box. Enter does it too." },
              picker.backHint()]
    if (picker.targeting)
      return [{ "keys": "◀ ▶", "action": "RIVAL", "act": "nextRival",
                "name": "Next rival", "does": "aim at the next rival",
                "key": "Left, Right", "warn": false, "destructive": false,
                // ROUND 4. This chip aims at the NEXT rival, so of the two keys
                // it prints only Right does what it does; Left goes the other
                // way and is on the chip because the child has both. The
                // crossover presses the one that matches. See
                // `ui/parts/Clickable.qml`.
                "keyRoute": ["right"],
                // AND NOT GUARDED, on purpose. This is a CHOOSING control: a
                // child clicking it three times means "three rivals on", and a
                // guard here would be the maintainer's other complaint -- a
                // control that has to be pressed several times -- pointing the
                // other way. It also does not replace the footer, so nothing
                // takes its place under the pointer.
                "guards": [],
                "help": "Aims at the next rival. Left and right do it too." },
              picker.useHint("USE"),
              picker.backHint()]
    return [picker.useHint("USE IT"), picker.backHint()]
  }

  // `USE` after the rival picker, `USE IT` without one: the two strings this
  // panel has always printed, and the one control that spends a hand.
  function useHint(word) {
    return { "keys": "⏎", "action": word, "act": "use", "name": "Use the card",
             "does": "use " + (picker.chosenCard.length > 0 && Engine.isCard(picker.chosenCard)
                               ? String(Engine.CARDS[picker.chosenCard].label)
                               : "the card"),
             "key": "Enter", "warn": false, "destructive": true,
             "guards": ["handFooter"],
             "help": "Uses the chosen card. Using one spends all three."
                     + " Enter does it too." }
  }

  function backHint(warn) {
    return { "keys": "ESC", "action": "BACK", "act": "back",
             "name": "Put the card back", "does": "put the chosen card back",
             "key": "Escape", "warn": warn === true, "destructive": false,
             // ROUND 4 -- THE CHIP A CRITIC BROKE THE RACE WITH, TWICE.
             //
             // Putting a card back costs nothing, so this is not destructive and
             // never was. It is guarded all the same, and by two names, because
             // of what happens AROUND it:
             //
             //   `escape` -- it is the same back-out gesture the race's own ESC
             //   line and the Escape key perform. Click this, press Escape, and
             //   the race used to END: the card was already back, so the key
             //   took the other branch. Measured, `raceLeaves = 1`.
             //
             //   `handFooter` -- this chip REPLACES ITSELF. The instant the card
             //   goes back the footer redraws as `1 2 3  CHOOSE A CARD` at the
             //   same pixel, and the second half of a double-click chose card 1.
             //   That is round two's walking-repeat defect, verbatim, one
             //   control to the left of where round two fixed it.
             "guards": ["escape", "handFooter"],
             "help": "Puts the chosen card back. All three cards are still yours."
                     + " Escape does it too." }
  }

  function footerAct(act) {
    // NOTHING ON THIS PANEL ACTS WHILE THE HAND IS FLYING OFF.
    //
    // The cards have had this guard since piece F (`onTapped: if
    // (!picker.slamming)`), and the footer needed it for a sharper reason that
    // the round-2 repeat sweep found: the chips CHANGE under the pointer the
    // instant a card is spent. `⏎  USE IT` is replaced at the same pixel by
    // `1 2 3  CHOOSE A CARD`, so the second press of a double-click on USE
    // landed on the chip that had taken its place and chose a card the child
    // never asked for. In the game the hand empties and the panel goes with it,
    // which is why the same sweep reads SAME on the race screen; standing alone
    // in the harness the hand stays and the walk-through is visible. It is the
    // same defect either way and this is where it stops.
    if (picker.slamming)
      return
    if (act === "chooseFirst")
      picker.tapCard(0)
    else if (act === "use")
      picker.useChosen()
    else if (act === "back") {
      picker.handTouched()
      picker.back()
    } else if (act === "nextRival")
      picker.stepTarget(1)
    else if (act === "submit")
      picker.submitRequested()
    else if (act === "undoDigit")
      picker.undoDigitRequested()
  }

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
  // taken all three cards away and `hand` is empty. `confirm()` therefore keeps
  // a copy -- the cards, and which one was chosen -- and the panel draws that
  // copy until the fly-off is over. Without it the design's most-used beat
  // ("the chosen card enlarges, then slams down") would be a card that vanished
  // on the frame the child pressed Enter, which is what shipped before.
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
  // than a blink, so it never reads as an alarm. It stops the moment a card is
  // chosen, because a chosen card is not an unused hand.
  readonly property real breathe: (picker.reducedMotion || picker.chosen >= 0
                                   || picker.hand.length === 0 || picker.slamming)
                                  ? 0
                                  : 0.5 + 0.5 * Math.sin(picker.fxNow / CardFx.HAND.breatheMs
                                                         * Math.PI * 2)
  property bool reducedMotion: false

  // -1 is "no card chosen yet", which is the state a hand sits in for as long
  // as the child likes. The design: "You may hold a hand as long as you like."
  property int chosen: -1
  property int targetIndex: 0

  // ROUND 5 -- A CARD THAT STOPS BEING CHOSEN SAYS SO.
  //
  // Round three's defect #5: on `2 x 6` a child holding a hand presses `1` then
  // `2` -- two card keys -- and the pair spells 12, which is the answer. The
  // race screen submits it as a correct answer, which is the least-bad reading
  // of two keys that are also the right answer, and drops the card choice on
  // the way past. The critic's finding was not the arbitration but the silence:
  // "the hand vanishing without explanation". The same silence follows every
  // other route by which a choice is let go -- Enter on a deferred digit,
  // Escape, a digit of the child's own typed over a provisional one.
  //
  // The panel is where a child looks for the state of their hand, so the panel
  // is where it is said, and saying it here means every one of those routes is
  // covered without the race screen having to remember to call anything: the
  // callers already call `reset()`.
  //
  // The wording is the one thing that must not be sloppy. The hand is NOT
  // spent by any of those routes -- all three cards are still held -- so a
  // banner reading CARD GONE would be a lie in the direction that matters. It
  // says the card went back, and the footer under it still names the keys.
  //
  // Short on purpose. Every route that lets a choice go is reached in the
  // middle of an answer, and the panel has to be back to naming keys by the
  // time the child's next keystroke lands. The commonest route by far is not
  // the collision the critic found but the ordinary one beside it -- ANY answer
  // whose first digit is 1, 2 or 3, typed while a hand is held, highlights that
  // card tile on the first press and unhighlights it on the second, and this
  // line is what says why the highlight went. See
  // `test_28_an_ordinary_answer_that_starts_with_a_card_key_says_it_too`.
  readonly property int letGoMs: 900
  property bool letGoShowing: false
  readonly property string letGoText: "CARD PUT BACK  ·  ALL THREE STILL YOURS"

  Timer {
    id: letGoTimer
    interval: picker.letGoMs
    onTriggered: picker.letGoShowing = false
  }

  // A choice cleared without being spent. `confirm()` does not come through
  // here, because a card that was actually played is not a card put back.
  function clearChoice() {
    picker.chosen = -1
    picker.targetIndex = 0
  }

  function sayLetGo() {
    if (!picker.visible)
      return
    picker.letGoShowing = true
    letGoTimer.restart()
  }

  // ROUND 4 -- `picker.hand`, QUALIFIED, AND FOUR OF THE EIGHT CARDS DEPEND ON IT.
  //
  // This read `hand[chosen]` unqualified, and round three's "three across"
  // rewrite of the panel below introduced `Row { id: handRow }` -- which was
  // `id: hand`. A file-scope id BEATS the root object's own property in QML's
  // unqualified lookup, so from that commit on `hand` here was a Row: its
  // `.length` is undefined, `chosen < undefined` is false, and `chosenCard`
  // was the empty string on every frame of every race.
  //
  // What that cost, because it is not a cosmetic bug: `needsTarget` is false
  // for the empty string, so `targeting`, `targetId` and `strandedTarget` fell
  // with it, the panel never offered a rival to aim at, and `confirm()` sent
  // `cardUsed(index, "")` for a TARGETED card. The engine refuses that. So the
  // Wrench, the Pothole, the Pile-Up and the Tow Hook -- half the deck, and
  // every card that attacks anybody -- could be chosen, would print `USE IT`,
  // and then did nothing at all: the hand came back and the child's twelve-in-
  // a-row bought them nothing. A blind critic saw exactly that in the
  // `hand-slam` strip and was right about it.
  //
  // The id is renamed AND this reads `picker.` explicitly. Either alone fixes
  // it; both together mean the next id cannot bring it back.
  readonly property string chosenCard: (picker.chosen >= 0
                                        && picker.chosen < picker.hand.length)
                                       ? String(picker.hand[picker.chosen]) : ""
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

  // PIECE M -- THE ONE THING A MOUSE NEEDS THE HOST TO KNOW.
  //
  // In the game this panel never has focus: `ui/Race.qml` owns every key of the
  // race, because only the race screen knows the expected answer and can tell a
  // card key from a digit. That arbitration leaves state behind it -- a
  // PROVISIONAL digit (one the card press itself put in the field) and a
  // DEFERRED one (parked because it might be the answer to a one-digit fact) --
  // and both exist only because `1`, `2` and `3` are also digits.
  //
  // A click is not a digit. It is the one press in this game with no ambiguity
  // in it at all, so choosing a card by clicking it must clear whatever the
  // keyboard's ambiguity left in the field, or a child who typed `1` and then
  // reached for the mouse would leave a `1` sitting in the answer box that they
  // never meant as an answer. This signal is how the panel says "a mouse did
  // that": the race screen drops the parked digit and retires the provisional
  // claim, and standing on its own in the harness nothing is listening because
  // there is no arbitration to undo.
  signal handTouched()

  // PIECE M ROUND 2. The two footer keys that belong to the ANSWER rather than
  // to the hand, asked of the host because the answer is the race's.
  //
  // `⏎  SEND THE ANSWER` and `⏎  ANSWER n` are printed on this panel in the two
  // states where Enter is not the hand's key, and `⌫  BACK TO THE CARD` is the
  // press that takes a parked digit out of the field. All three are the race
  // screen's arbitration, not this panel's -- see the deferred-digit block
  // above -- so the chip asks and `ui/Race.qml` answers through the same
  // `submitKey()` and `dropPending()` a real key press reaches. Standing alone
  // in the harness neither state can arise: both need an entry, and an entry
  // needs a race.
  signal submitRequested()
  signal undoDigitRequested()

  visible: picker.hand.length > 0 || picker.slamming

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
  //    A hand replaced under a chosen index is not a card put back -- the hand
  //    it belonged to is gone -- so this one clears the choice silently. And a
  //    line about the hand that has just been replaced does not belong over the
  //    one that replaced it, or over the first hand of the next race, so the
  //    beat is dropped here rather than left to run out on its timer.
  //
  // AND `hand` CHANGES WHEN THE HAND DOES NOT. The host hands it down off the
  // engine's racer, and the engine clones its state on every step, so the array
  // is a new object several times a second while the three cards in it stand
  // still. `onHandChanged` therefore has to ask whether the CARDS changed --
  // measured: bound to the identity, the one-beat line below was cleared by the
  // next keystroke and a critic would have read it as never drawn at all.
  property var lastHand: []
  function sameCards(a, b) {
    if (!a || !b || a.length !== b.length)
      return false
    for (var i = 0; i < a.length; i++) {
      if (String(a[i]) !== String(b[i]))
        return false
    }
    return true
  }
  onHandChanged: {
    if (picker.sameCards(picker.hand, picker.lastHand))
      return
    picker.lastHand = picker.hand
    picker.letGoShowing = false
    letGoTimer.stop()
    if (picker.chosen >= picker.hand.length)
      picker.clearChoice()
  }

  Accessible.role: Accessible.Pane
  Accessible.name: "Power-up hand"
  // The deferred sentence comes first, because while a digit is parked it is the
  // only rule on this panel that costs anything, and a screen-reader user got no
  // version of it at all before. It names all three keys and what each one does.
  Accessible.description: (picker.letGoShowing
                           ? "The card you had chosen has been put back. All three cards are"
                             + " still yours. "
                           : "")
    + (picker.deferred
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
       + " Escape puts the card back. Using a card costs the whole hand."))

  function choose(index) {
    if (index < 0 || index >= picker.hand.length)
      return
    picker.chosen = index
    picker.targetIndex = 0
  }

  // PIECE M. What a click on a card means, in one place, so the three routes
  // into it -- the card, the harness's drive script and a screen reader's press
  // action -- cannot drift apart.
  //
  // ================================================================== ROUND 2
  //
  // A CLICK ON A CARD CHOOSES IT, AND CANNOT SPEND IT. THAT IS THE WHOLE FIX.
  //
  // Round one collapsed the keyboard's two presses onto the card: an unchosen
  // card was chosen, and a card that was already chosen was USED. A critic
  // drove two real clicks sixteen milliseconds apart -- `click:card 3,
  // click:card 3` -- and the hand was gone. The same key twice, `key:3, key:3`,
  // merely left the card chosen.
  //
  // Everything about that is wrong in the same direction. Spending a card costs
  // all three and there is no undo anywhere in this plugin. A double-click is
  // not a child's mistake; it is what children do with a mouse. Nothing on
  // screen ever said "click it again to use it" -- the second press was
  // discoverable only from the screen reader's description -- so the gesture
  // was undiscoverable AND destructive, which is the worst pair. And it was on
  // the one mechanic the maintainer has already complained about: "launching a
  // power up feels weird, I had to attempt to trigger it multiple times."
  //
  // The keyboard has always spent a card with a SECOND, DIFFERENT press --
  // Enter, not the digit again -- and the panel has always printed that key.
  // The mouse now has the same shape: the card chooses, and the footer's
  // `⏎  USE IT` is the control that spends. It is a separate target, it says
  // what it does in the words already on the screen, and it is marked
  // `destructive`, so `ui/parts/Clickable.qml` refuses a second press inside
  // the double-click interval as well.
  //
  // A repeat is therefore harmless on both halves: clicking a card five times
  // chooses it five times, and the second click of a double-click on `USE IT`
  // is refused by the guard and lands, in any case, on a footer that no longer
  // offers it.
  function tapCard(index) {
    picker.handTouched()
    picker.choose(index)
  }

  // Spending the chosen card, from the footer's `⏎  USE IT`. `handTouched()`
  // first for the same reason a card click sends it: a click is not a digit, so
  // whatever the keyboard's digit arbitration parked in the answer field has to
  // come back out before the hand is spent.
  function useChosen() {
    if (picker.slamming)
      return false
    picker.handTouched()
    return picker.confirm()
  }

  // Clicking a rival is the Left/Right arrow landing on that rival, and nothing
  // more: it aims, it does not fire. Firing is the card's second press, which
  // is where the keyboard fires from too.
  function tapRival(index) {
    if (!picker.targeting || index < 0 || index >= picker.rivals.length)
      return
    picker.handTouched()
    picker.targetIndex = index
  }

  function stepTarget(delta) {
    if (!picker.targeting)
      return
    var count = picker.rivals.length
    picker.targetIndex = ((picker.targetIndex + delta) % count + count) % count
  }

  // The host's way of putting a chosen card back, from any of the routes above.
  // It is called on states where nothing was chosen too -- a new race, a new
  // hand -- and those say nothing, because nothing went anywhere.
  function reset() {
    var had = picker.chosen >= 0
    picker.clearChoice()
    if (had)
      picker.sayLetGo()
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
    // PIECE F. Keep the hand that is about to be taken away, and which card of
    // it was chosen, so the slam and the fly-off have something to draw. See
    // the block at the top of this file.
    picker.slamHand = picker.hand.slice()
    picker.slamChosen = index
    picker.slamBorn = picker.fxNow
    // "the chosen card enlarges for 150, then slams down". The sound is the
    // slam's, not the choice's: choosing costs nothing and says nothing.
    Sfx.play("slam")
    // No `letGoShowing = false` here, deliberately. Spending a card empties the
    // hand, and `onHandChanged` below drops the line for that reason -- a
    // second clear on this path would be a line no test could ever falsify.
    picker.clearChoice()
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
      // ROUND 4 of piece M. The same `escape` guard the footer's `ESC  BACK`
      // chip and the race's own ESC line take: one back-out gesture, one guard,
      // whichever hand the press came from. In the game this handler never
      // fires -- `ui/Race.qml` owns every key of a race -- and the race's own
      // Escape branch takes the same name; this is the standalone path, and it
      // has to obey the same rule or the panel means something different in the
      // harness from what it means in the game.
      if (!Actions.take(["escape"])) {
        event.accepted = true
        return
      }
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

      // ROUND 3: THREE ACROSS, NOT THREE DOWN.
      //
      // A blind critic called this "a dark list panel ... These are not cards".
      // The design's whole paragraph on the hand is in the language of cards --
      // dealt, slid up, slammed down, flipped face down, flown off -- and none
      // of it means anything to a six-year-old about three rows of a settings
      // menu. `ui/parts/HandCard.qml` draws a portrait card in playing-card
      // proportions; this is the hand it is laid out in.
      Row {
        // NOT `id: hand`. See `chosenCard` above: that id shadowed the root's
        // own `hand` property for every unqualified binding in this file and
        // silently disabled every targeted card in the deck for a whole round.
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
        //   slam    the chosen card enlarges for 150 then slams down; the other
        //           two flip face down (a scale through zero in x, which is
        //           what a card turning over is) and fly off to the right
        Item {
          id: cardSlot
          readonly property int slot: index
          readonly property bool isChosen: picker.slamming
                                           ? picker.slamChosen === slot
                                           : picker.chosen === slot
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

            // PIECE M. Choose it, or -- if it is already chosen -- use it. The
            // click goes through `tapCard`, which calls the panel's own
            // `choose` and `confirm`: the same two functions `ui/Race.qml`
            // calls for the `1 2 3` keys and for Enter.
            //
            // Dead while the hand is flying off. `shownHand` keeps drawing the
            // spent cards for 570 ms so the slam has something to draw, and a
            // click on a card that has already been played would be a press
            // with no rule behind it.
            onTapped: if (!picker.slamming) picker.tapCard(cardSlot.slot)

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
            // The chosen card: enlarge, then slam.
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
                // A flip is a scale through zero in x. It is the whole of what
                // "flip face down" can be without a second face to draw, and it
                // reads as a turn rather than as a shrink because the height
                // does not change.
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

                // ROUND 4 OF PIECE M -- THE ONE TILE THE POINTER DID NOTHING TO.
                //
                // The fill and the border above are `aimed ? ... : hovered ?
                // ...`, so the tag that is ALREADY aimed drew the same picture
                // whether the pointer was on it or not. Pointing at it changed
                // nothing on the screen -- which is the exact defect this
                // component's own doctrine is against, and it went unseen for
                // three rounds because the pixel sweep walked two screens that
                // have no aim tags on them.
                //
                // Selection is not focus. `ui/parts/ActionButton.qml` suppresses
                // hover under FOCUS on purpose -- where the keyboard is standing
                // is the more important fact, and a child needs one answer, not
                // two -- but "this is the rival you are aiming at" and "your
                // pointer is here" are two different facts and the child wants
                // both. Drawn as a second ring inside the aimed one, the way
                // `ui/parts/PaintGrid.qml` draws hover over the chosen swatch,
                // so the aimed picture is not taken away to make room for it.
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

                // PIECE M. Design v4.1: "a rival's kart tag as a target". This
                // is that tag -- the rival's name, in the panel, in the moment
                // the game asks a child who to aim at -- and it is the only
                // place in the running game where the question is put. The
                // rival tags `ui/TrackView.qml` draws on the road belong to
                // piece T this round and are not touched here; the aim is
                // reachable by mouse in the panel that asks for it, which is
                // where the arrow keys reach it too.
                Accessible.role: Accessible.Button
                Accessible.name: "Aim at " + String(modelData.name)
                    + (aimTile.aimed ? ", aimed" : "")
                Accessible.description: "Left and right pick a rival. Then use the card."
                Accessible.onPressAction: picker.tapRival(model.index)

                Clickable {
                  id: aimHit
                  objectName: "clickAimRival"
                  enabled: picker.targeting
                  stop: null
                  label: "aim " + String(modelData.name)
                  does: "aim at " + String(modelData.name)
                  key: "Left, Right"
                  // ROUND 4. The arrows STEP round the rivals and a click LANDS
                  // on one, so the crossover presses Right as many times as this
                  // tag is round the ring from the aim that is on. See
                  // `ui/parts/Clickable.qml`.
                  keyRoute: {
                    var count = picker.rivals ? picker.rivals.length : 0
                    if (count <= 0)
                      return []
                    var steps = ((model.index - picker.targetIndex) % count + count) % count
                    var route = []
                    for (var i = 0; i < steps; i++)
                      route.push("right")
                    return route
                  }
                  onActed: picker.tapRival(model.index)
                }
              }
            }
          }
        }
      }

      // ROUND 5 -- the one-beat line that says a chosen card went back.
      //
      // The row is ALWAYS here and always the same height, empty or not. A line
      // that appeared and disappeared would grow and shrink the dock, and
      // `ui/Race.qml` hangs the charge bar off `picker.dockHeight`, so a
      // message about a card would have made the charge bar jump twice a race.
      Item {
        width: parent.width
        height: letGoLine.implicitHeight

        Text {
          id: letGoLine
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          visible: picker.letGoShowing
          text: picker.letGoText
          color: Theme.amber
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: picker.fsFloor(13, 12)
          font.letterSpacing: picker.px(1)

          // Read out on its own, because a screen-reader user gets no colour
          // and no beat: the pane's description below carries the same sentence
          // while it stands.
          Accessible.role: Accessible.StaticText
          Accessible.name: picker.letGoText
          Accessible.ignored: !picker.letGoShowing
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
      // PIECE M ROUND 2 -- THE FOOTER IS THE CONTROLS, NOT A PICTURE OF THEM.
      //
      // This was one `Text`. It printed `⏎  USE IT      ESC  BACK` in the same
      // grey mono type the race's `ESC  LEAVE` is printed in, and the race's
      // line was a click target while this one was paint. It is the only place
      // in the game that tells a child how to put a card back, and the only
      // place that names the key which spends the hand -- and a mouse could
      // press neither.
      //
      // Every group of the line is now a `KeyHint`: the same words, the same
      // grammar, in the same order, each one a control that does what it says.
      // `footerHints` below is the single model both the chips and `footerText`
      // are built from, so the string the panel publishes cannot say something
      // the panel does not draw. The wrapping the deferred line needed a
      // `TextMetrics` probe for is now the `Flow`'s own.
      Flow {
        id: footerFlow
        width: parent.width
        spacing: picker.px(18)

        Repeater {
          model: picker.footerHints

          KeyHint {
            keys: modelData.keys
            action: modelData.action
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
            onTapped: picker.footerAct(modelData.act)
          }
        }
      }
    }
  }
}
