import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../ui/parts"
import "../../engine/engine.mjs" as Engine

// The race screen's keyboard, driven with real key events only.
//
// PIECE F ROUND 7. Design v4.1 gives the race one key map and this file is
// the record of it:
//
//   digits         only ever the answer, whatever the hand is doing
//   Enter          only ever the answer; with an empty field it does nothing
//   Backspace      edits the answer
//   H              the pit crew
//   Left, Right    move the hand's highlight (nothing with no hand)
//   Up, Down       change a targeted card's rival (nothing otherwise)
//   Space          fires the highlighted card (nothing with no hand)
//   Escape         only ever leaves the race
//
// PIECE F ROUND 8 adds the rule under the key: the panel REQUESTS a play and
// the engine's own `cardUsed` is what slams, sounds, resets the highlight and
// counts as a card played. So Space after the child has finished, Space while
// the deal is still drawing the cards, and Space on a targeted card with no
// rival left each change nothing at all and arm no guard (test_24 to test_26);
// `POWER-UP READY` reads on the charge bar at the deal (test_27); the pit
// crew's reveal holds digits like the wrong answer's (test_28); browsing the
// cards keeps the aim (test_29); and a three-digit answer is typed in full on
// the line with a hand held (test_30, the case round 7 dropped).
//
// Every case below is one row of that table, and every row is a claim that
// fails if the rule is changed: the first case is the strip the plan names --
// `1` on `2 × 3` with a hand held is a wrong answer and no card -- and it is
// written so that the OLD rule (a card key) fails it on two counts, not one.
//
// Nothing here calls `typeKey`, `fire`, `moveHighlight` or `send`: every
// assertion is made by `keyClick()`, which posts the events a window manager
// posts, so what passes is the keyboard a child meets.
//
// Two things are set up rather than played, and both are named where they are
// used: the seed (to rebuild the race between cases) and `race.rivals = null`
// (to stop the AI karts thinking, so a stall from a rival's Wrench cannot land
// in the middle of a measurement). Every keystroke of the CHILD's is real.
//
// Run it:
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
//     qmltestrunner -platform offscreen -import ui -import dev/imports -input tests/qml
//
// RUN THIS HEADLESS, AND WHY THAT IS NOT A PREFERENCE. A real key event needs
// a window that holds the keyboard. macOS gives keyboard activation to one
// window at a time; a second Qt window anywhere on the machine deactivates
// this one, `keyClick()` after that is delivered nowhere, and a case fails
// with a sentence about the child's keyboard that is not true. Measured: 65 of
// 100 windowed runs failed that way, 0 of 100 headless. Every key goes through
// `pressKey()`, which checks the precondition on every press.
Item {
  id: root
  width: 1920
  height: 1080

  Race {
    id: race
    anchors.fill: parent
    mode: "grandPrix"
    preset: "1-12"
    seed: 42
  }

  property int cardsPlayed: 0
  property int lastCardIndex: -1
  property string lastCardTarget: ""
  property int leaveRequests: 0

  Connections {
    target: race.handPanel
    function onCardUsed(index, targetId) {
      root.cardsPlayed += 1
      root.lastCardIndex = index
      root.lastCardTarget = targetId
    }
  }

  Connections {
    target: race
    function onLeaveRequested() { root.leaveRequests += 1 }
  }

  TestCase {
    id: tc
    name: "RaceKeys"
    when: windowShown

    // ------------------------------------------------------------- pressing
    function digitKey(d) { return Qt.Key_0 + d }

    function pressKey(code) {
      verify(race.focusTarget.activeFocus,
             "the race screen's key catcher lost active focus mid-case, so this keystroke"
             + " was delivered nowhere. Nothing below this line is a statement about the"
             + " keyboard. Run this spec headless (-platform offscreen).")
      keyClick(code)
    }

    // "12EBXH<>^vS" -> digits, Enter, Backspace, Escape, H, Left, Right, Up,
    // Down, Space.
    function press(script) {
      for (var i = 0; i < script.length; i++) {
        var c = script.charAt(i)
        if (c === "E") tc.pressKey(Qt.Key_Return)
        else if (c === "B") tc.pressKey(Qt.Key_Backspace)
        else if (c === "X") tc.pressKey(Qt.Key_Escape)
        else if (c === "H") tc.pressKey(Qt.Key_H)
        else if (c === "<") tc.pressKey(Qt.Key_Left)
        else if (c === ">") tc.pressKey(Qt.Key_Right)
        else if (c === "^") tc.pressKey(Qt.Key_Up)
        else if (c === "v") tc.pressKey(Qt.Key_Down)
        else if (c === "S") tc.pressKey(Qt.Key_Space)
        else tc.pressKey(tc.digitKey(Number(c)))
      }
    }

    // ---------------------------------------------------------------- setup
    function fresh(seedValue) {
      race.seed = seedValue
      race.rivals = null
      race.forceActiveFocus()
      verify(race.focusTarget.activeFocus, "the race screen's key catcher has focus")
      root.cardsPlayed = 0
      root.lastCardIndex = -1
      root.lastCardTarget = ""
      root.leaveRequests = 0
      Actions.clear()
    }

    function answerString() { return String(Engine.factAnswer(race.human.currentFact)) }

    // Answer the fact on screen correctly, by typing it.
    function answerNow() { tc.press(tc.answerString()) }

    // Twelve correct in a row deals the hand. Design: "At 12 in a row, one clean
    // lap's worth, the child is dealt a hand of three powerups."
    function dealHand() {
      var guard = 0
      while (race.hand.length === 0 && guard < 40) {
        tc.answerNow()
        guard += 1
      }
      compare(race.hand.length, 3, "a hand of three is held")
      // ROUND 8: the deal takes 672 ms to draw the cards and Space does
      // nothing until they are drawn. Every case below that fires starts once
      // the hand is a hand the child can see; test_25 is the one that presses
      // Space BEFORE that on purpose.
      tryVerify(function () { return !race.handPanel.dealing }, 3000,
                "the deal finished drawing the cards")
    }

    // Walk forward with the pit crew until the fact on screen has the answer we
    // want to test against. `H` neither grows nor resets the streak and never
    // touches the hand, so it moves the deck and nothing else.
    function hintUntil(wanted) {
      var guard = 0
      while (guard < 200 && !wanted(tc.answerString())) {
        tc.pressKey(Qt.Key_H)
        guard += 1
      }
      verify(wanted(tc.answerString()), "reached a fact whose answer fits the shape")
      // ROUND 8: the pit crew's 1200 ms reveal holds digits exactly as the
      // wrong answer's does, so a case that types the moment it arrives would
      // be typing into the queue. Every case starts on a line that is back.
      tryVerify(function () { return !race.holdsForReveal() }, 3000,
                "the pit crew's reveal cleared the line")
    }

    function streakTo(n) {
      var guard = 0
      while (race.human.streak < n && guard < 24) {
        tc.answerNow()
        guard += 1
      }
      compare(race.human.streak, n, "the streak is where the case wants it")
    }

    // The first slot in the hand holding a card that needs a rival, or -1.
    function targetedSlot() {
      for (var i = 0; i < race.hand.length; i++)
        if (Engine.isCard(race.hand[i]) && Engine.CARDS[race.hand[i]].scope === "targeted")
          return i
      return -1
    }

    // Move the highlight onto a slot with real Right presses.
    function highlightSlot(slot) {
      var guard = 0
      while (race.handPanel.highlighted !== slot && guard < 6) {
        tc.pressKey(Qt.Key_Right)
        guard += 1
      }
      compare(race.handPanel.highlighted, slot, "the highlight is on slot " + slot)
    }

    function needOf(racerId) {
      for (var b = 0; b < race.state.racers.length; b++)
        if (race.state.racers[b].id === racerId)
          return race.state.racers[b].questionsNeededThisLap
      return -1
    }

    // ---------------------------------------------------------------- rows
    function snap() {
      return {
        "streak": race.human.streak,
        "missed": race.human.missed.length,
        "attempts": race.human.attemptCount,
        "wrong": race.human.wrongCount,
        "hand": race.hand.length,
        "cards": root.cardsPlayed,
        "entry": race.shownEntry,
        "highlighted": race.handPanel.highlighted,
        "target": race.handPanel.targetIndex,
        "fact": Engine.factLabel(race.human.currentFact),
        "answer": tc.answerString()
      }
    }

    function row(id, shape, keys, before, after) {
      console.log("ROW|" + id
                  + "|" + shape
                  + "|" + keys
                  + "|" + before.fact + " = " + before.answer
                  + "|streak " + before.streak + "->" + after.streak
                  + "|missed " + before.missed + "->" + after.missed
                  + "|attempts " + before.attempts + "->" + after.attempts
                  + "|hand " + before.hand + "->" + after.hand
                  + "|card played " + (after.cards - before.cards)
                  + "|field '" + after.entry + "'"
                  + "|highlighted " + after.highlighted)
    }

    // A hand key cost nothing on the answer side.
    function costNothing(before, after, id) {
      compare(after.streak, before.streak, id + ": the streak is untouched")
      compare(after.missed, before.missed, id + ": no fact was recorded as missed")
      compare(after.attempts, before.attempts, id + ": no attempt was recorded")
      compare(after.entry, before.entry, id + ": the field is untouched")
      compare(after.fact, before.fact, id + ": the fact did not move")
    }

    // A wrong answer cost the streak and only the streak.
    function costStreakOnly(before, after, id) {
      compare(after.streak, 0, id + ": the streak is gone")
      compare(after.missed, before.missed + 1, id + ": the fact is recorded as missed")
      compare(after.attempts, before.attempts + 1, id + ": one attempt was recorded")
      compare(after.hand, before.hand, id + ": the hand is intact")
      compare(after.cards - before.cards, 0, id + ": no card was played")
    }

    // =====================================================================
    function test_00_the_race_takes_the_keyboard() {
      tc.fresh(101)
      verify(race.state !== null)
      compare(race.hand.length, 0, "a fresh race holds no hand")
      compare(race.pending, undefined, "the parked-digit machinery is gone")
      compare(race.provisional, undefined, "and the provisional claim with it")
    }

    // ---------------------------------------------------------------------
    // THE STRIP THE PLAN NAMES. `1` on `2 × 3` with a hand held: a wrong
    // answer, and no card. Under v4 the same press chose card one and parked
    // the digit; this row fails that rule twice -- the attempt is scored, and
    // the highlight has not moved to the card the digit named.
    // ---------------------------------------------------------------------
    function test_01_a_digit_with_a_hand_held_is_an_answer_and_never_a_card() {
      tc.fresh(102)
      tc.dealHand()
      tc.streakTo(2)
      // A one-digit answer that is not 2, so `2` is unambiguously wrong -- and
      // `2` rather than `1`, so a card key that "chose the card it names" would
      // move the highlight off the default and be caught by the row below.
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) !== 2 })
      compare(race.handPanel.highlighted, 0, "the first card is highlighted by default")
      var before = tc.snap()
      tc.press("2")
      var after = tc.snap()
      tc.row("STRIP", "1-digit fact, a wrong card-number digit, hand held", "2", before, after)
      tc.costStreakOnly(before, after, "STRIP")
      compare(after.highlighted, 0, "STRIP: the digit did not touch the highlight")
      compare(after.entry, "", "STRIP: the field cleared, as a wrong answer clears it")
      compare(after.fact, before.fact, "STRIP: the same fact stays, as the answer loop says")
    }

    // The same, on the exact fact the plan names, when the deck offers it, and
    // on every one-digit fact the deck offers otherwise: six seeds.
    function test_02_the_strip_on_six_decks() {
      var seeds = [103, 104, 105, 106, 107, 108]
      for (var i = 0; i < seeds.length; i++) {
        tc.fresh(seeds[i])
        tc.dealHand()
        tc.streakTo(1)
        tc.hintUntil(function (a) { return a.length === 1 && Number(a) !== 1 })
        var before = tc.snap()
        tc.press("1")
        var after = tc.snap()
        tc.costStreakOnly(before, after, "seed " + seeds[i])
        compare(after.highlighted, before.highlighted,
                "seed " + seeds[i] + ": `1` on " + before.fact + " did not move the highlight")
      }
    }

    // A digit that starts a two-digit answer, with a hand held: it is the
    // start of the answer, the field shows it, nothing else changes, and the
    // rest of the answer completes it.
    function test_03_a_card_number_digit_starts_a_two_digit_answer() {
      tc.fresh(109)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 2 && Number(a.charAt(0)) <= 3 })
      var before = tc.snap()
      tc.press(before.answer.charAt(0))
      var mid = tc.snap()
      compare(mid.entry, before.answer.charAt(0), "the digit is in the field")
      compare(mid.highlighted, 0, "and the highlight did not move")
      compare(mid.attempts, before.attempts, "and nothing was scored yet")
      tc.press(before.answer.charAt(1))
      var after = tc.snap()
      tc.row("C", "2-digit answer starting with a card number, typed in full",
             before.answer, before, after)
      compare(after.streak, before.streak + 1, "C: accepted as the answer")
      compare(after.hand, 3, "C: the hand is intact")
      compare(after.cards - before.cards, 0, "C: no card was played")
    }

    // ---------------------------------------------------------------------
    // SPACE
    // ---------------------------------------------------------------------

    // With no hand, Space changes nothing. Asserted as a snapshot of the whole
    // race plus the guard, not as an absent signal: a Space that quietly typed
    // a character, armed a guard or moved the deck would be caught here.
    function test_04_space_with_no_hand_changes_nothing() {
      tc.fresh(110)
      compare(race.hand.length, 0, "no hand is held")
      tc.press("7")
      var before = tc.snap()
      var armedBefore = JSON.stringify(Actions.armed)
      tc.press("S")
      var after = tc.snap()
      compare(JSON.stringify(after), JSON.stringify(before),
              "Space with no hand changed the race: " + JSON.stringify(after))
      compare(JSON.stringify(Actions.armed), armedBefore,
              "Space with no hand armed a guard, so the next press would be refused")
      compare(root.cardsPlayed, 0, "and no card was played")
    }

    // With a hand, Space fires the highlighted card -- the first, by default --
    // and costs the answer nothing.
    function test_05_space_with_a_hand_fires_the_highlighted_card() {
      tc.fresh(111)
      tc.dealHand()
      tc.streakTo(2)
      // A card that needs no rival in slot 0, or move on to a deck where it is:
      // the first hand of a race is always Nitro, Oil Slick, Wrench, so slot 0
      // is Nitro on every deck.
      compare(String(race.hand[0]), "nitro", "the first card of the first hand is Nitro")
      var before = tc.snap()
      tc.press("S")
      var after = tc.snap()
      tc.row("SPACE", "hand held, Space", "S", before, after)
      compare(after.cards - before.cards, 1, "SPACE: the card was played")
      compare(root.lastCardIndex, 0, "SPACE: and it was the highlighted card, slot 0")
      compare(after.hand, 0, "SPACE: using one spends all three")
      compare(after.streak, before.streak, "SPACE: the streak survived")
      compare(after.missed, before.missed, "SPACE: nothing was recorded as missed")
      compare(after.attempts, before.attempts, "SPACE: no attempt was recorded")
    }

    // Right, then Space: card 2.
    function test_06_right_then_space_fires_card_two() {
      tc.fresh(112)
      tc.dealHand()
      tc.streakTo(2)
      var before = tc.snap()
      tc.press(">")
      var mid = tc.snap()
      compare(mid.highlighted, 1, "Right moved the highlight to card 2")
      tc.costNothing(before, mid, "RIGHT")
      compare(mid.cards - before.cards, 0, "RIGHT: moving the highlight fires nothing")
      tc.press("S")
      var after = tc.snap()
      tc.row("RIGHT-SPACE", "hand held, Right then Space", "> S", before, after)
      compare(after.cards - before.cards, 1, "the card was played")
      compare(root.lastCardIndex, 1, "and it was card 2")
      compare(after.hand, 0, "using one spends all three")
    }

    // Left and Right wrap round the three cards, and a Right over a Right is
    // card three. Three presses of one key are three presses.
    function test_07_left_and_right_wrap_round_the_hand() {
      tc.fresh(113)
      tc.dealHand()
      compare(race.handPanel.highlighted, 0)
      tc.press("<")
      compare(race.handPanel.highlighted, 2, "Left from the first card wraps to the third")
      tc.press(">")
      compare(race.handPanel.highlighted, 0, "Right from the third wraps to the first")
      tc.press(">>")
      compare(race.handPanel.highlighted, 2, "two Rights are card three")
      tc.press(">")
      compare(race.handPanel.highlighted, 0, "and a third wraps")
      compare(root.cardsPlayed, 0, "none of it fired anything")
      compare(race.hand.length, 3, "and the hand is intact")
    }

    // With no hand, the arrows do nothing at all.
    function test_08_the_arrows_with_no_hand_change_nothing() {
      tc.fresh(114)
      compare(race.hand.length, 0)
      tc.press("4")
      var before = tc.snap()
      tc.press("<>^v")
      var after = tc.snap()
      compare(JSON.stringify(after), JSON.stringify(before),
              "an arrow with no hand changed the race: " + JSON.stringify(after))
    }

    // ---------------------------------------------------------------------
    // UP AND DOWN, AND THE RING
    // ---------------------------------------------------------------------

    // A targeted card: Up and Down change the rival, the ringed kart follows,
    // and Space fires at the one that is ringed -- proven by the engine's own
    // number on the victim, which no view state can fake.
    function test_09_up_and_down_change_the_target_and_space_fires_at_it() {
      tc.fresh(42)
      tc.dealHand()
      var slot = tc.targetedSlot()
      verify(slot >= 0, "the hand holds a card that needs a rival: " + JSON.stringify(race.hand))
      compare(race.aimedRivalId, "", "nothing is aimed while a self card is highlighted")
      compare(race.trackView.aimKart, -1, "and no kart is ringed")
      tc.highlightSlot(slot)
      verify(race.handPanel.targeting, "a targeted card opens the aim: " + race.handPanel.highlightedCard)
      compare(race.handPanel.targetIndex, 0, "the nearest rival is aimed at first")
      var first = race.handPanel.targetId
      compare(race.aimedRivalId, first, "the race hands the aim to the road")
      compare(race.trackView.fxKartIdOf(race.trackView.aimKart), first,
              "and the road rings that kart")

      tc.press("v")
      compare(race.handPanel.targetIndex, 1, "Down aims at the next rival")
      var second = race.handPanel.targetId
      verify(second !== first, "which is a different rival")
      compare(race.trackView.fxKartIdOf(race.trackView.aimKart), second, "and the ring moved")
      tc.press("^")
      compare(race.handPanel.targetIndex, 0, "Up aims back")
      tc.press("^")
      compare(race.handPanel.targetIndex, race.handPanel.rivals.length - 1, "and wraps")
      tc.press("v")
      tc.press("v")
      compare(race.handPanel.targetIndex, 1, "two Downs from the first is the second")
      var victim = race.handPanel.targetId
      var need = tc.needOf(victim)

      var before = tc.snap()
      tc.press("S")
      var after = tc.snap()
      console.log("ROW|AIM|" + race.handPanel.highlightedCard + " at " + victim
                  + " needed " + need + " -> " + tc.needOf(victim))
      compare(after.cards - before.cards, 1, "Space fired the card")
      compare(root.lastCardTarget, victim, "at the rival that was ringed")
      compare(after.hand, 0, "using one spends all three")
      compare(race.aimedRivalId, "", "and the ring is gone with the hand")
      compare(race.trackView.aimKart, -1)
      verify(tc.needOf(victim) > need,
             "and the rival it was aimed at really pays for it: " + victim
             + " needed " + need + ", now needs " + tc.needOf(victim))
    }

    // Up and Down with a self card highlighted change nothing.
    function test_10_up_and_down_do_nothing_on_a_self_card() {
      tc.fresh(115)
      tc.dealHand()
      compare(String(race.hand[0]), "nitro")
      var before = tc.snap()
      tc.press("^v^")
      var after = tc.snap()
      compare(JSON.stringify(after), JSON.stringify(before),
              "Up or Down on a self card changed the race: " + JSON.stringify(after))
    }

    // ---------------------------------------------------------------------
    // ENTER AND ESCAPE
    // ---------------------------------------------------------------------

    // Enter never fires a card: with a hand held and an empty field it does
    // nothing, and with digits in the field it sends the answer.
    function test_11_enter_is_only_ever_the_answer() {
      tc.fresh(116)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 2 })
      var before = tc.snap()
      tc.press("E")
      var mid = tc.snap()
      compare(JSON.stringify(mid), JSON.stringify(before),
              "Enter on an empty field with a hand held changed the race: "
              + JSON.stringify(mid))
      compare(root.cardsPlayed, 0, "and it fired no card")
      // A one-digit wrong start, then Enter: the answer is sent and scored.
      tc.press("9")
      compare(race.shownEntry, "9", "the digit is in the field")
      tc.press("E")
      var after = tc.snap()
      tc.row("ENTER", "2-digit fact, hand held, 9 then Enter", "9 E", before, after)
      tc.costStreakOnly(before, after, "ENTER")
      compare(race.handPanel.highlighted, 0, "and the hand was not touched")
    }

    // Escape only ever leaves, whatever the hand is doing.
    function test_12_escape_only_ever_leaves() {
      tc.fresh(117)
      tc.dealHand()
      var slot = tc.targetedSlot()
      verify(slot >= 0)
      tc.highlightSlot(slot)
      verify(race.handPanel.targeting, "a rival is being aimed at, the deepest state the hand has")
      var before = tc.snap()
      tc.press("X")
      compare(root.leaveRequests, 1, "the first Escape left the race")
      var after = tc.snap()
      compare(after.hand, 3, "and the hand is intact")
      compare(after.highlighted, slot, "and the highlight did not move")
      compare(after.cards - before.cards, 0, "and no card was played")
      // A second, deliberate Escape is a second press. Key after key is not
      // a repeat (`ui/parts/Actions.qml`).
      tc.press("X")
      compare(root.leaveRequests, 2, "a second Escape leaves again")
    }

    // ---------------------------------------------------------------------
    // WHAT THE PANEL PRINTS
    // ---------------------------------------------------------------------

    // The footer names the keys the design names and none it took away. Read
    // off the string the chips are built from, which is what the panel draws.
    function test_13_the_footer_prints_the_hands_keys_and_no_digit() {
      tc.fresh(118)
      tc.dealHand()
      var footer = race.handPanel.footerText
      console.log("FOOTER AS RENDERED: " + JSON.stringify(footer))
      verify(footer.indexOf("◀ ▶  PICK") >= 0, "the arrows pick: " + JSON.stringify(footer))
      verify(footer.indexOf("SPACE  USE IT") >= 0, "Space uses it: " + JSON.stringify(footer))
      verify(footer.indexOf("1 2 3") < 0, "no digit is printed as a key")
      verify(footer.indexOf("⏎") < 0, "Enter is not printed on the hand")
      verify(footer.indexOf("ESC") < 0, "Escape is not printed on the hand")
      verify(footer.indexOf("AIM") < 0, "and nothing about aiming while a self card is up")

      var slot = tc.targetedSlot()
      tc.highlightSlot(slot)
      footer = race.handPanel.footerText
      console.log("FOOTER WHILE AIMING: " + JSON.stringify(footer))
      verify(footer.indexOf("▲ ▼  AIM") >= 0, "Up and Down aim: " + JSON.stringify(footer))
      verify(footer.indexOf("SPACE  USE") >= 0, "and Space still uses")
      var spoken = String(race.handPanel.Accessible.description)
      verify(spoken.indexOf("Left and right") >= 0 && spoken.indexOf("Space") >= 0
             && spoken.indexOf("Up and down") >= 0,
             "a screen-reader user is told the same keys: " + JSON.stringify(spoken))
    }

    // The race's own two hints are key caps, in the garage's words.
    function test_14_the_race_key_hints_are_key_caps() {
      tc.fresh(119)
      var hints = []
      function walk(item) {
        if (!item)
          return
        if (item.isKeyHint === true)
          hints.push(item)
        var kids = item.children
        for (var i = 0; kids && i < kids.length; i++)
          walk(kids[i])
      }
      walk(race)
      var pit = null
      var leave = null
      for (var h = 0; h < hints.length; h++) {
        if (String(hints[h].keys) === "H")
          pit = hints[h]
        if (String(hints[h].keys) === "ESC")
          leave = hints[h]
      }
      verify(pit !== null, "the race prints an H hint")
      verify(leave !== null, "the race prints an ESC hint")
      verify(pit.cap === true, "the pit crew is drawn as a key cap")
      verify(leave.cap === true, "the way out is drawn as a key cap")
      compare(String(pit.text), "H  PIT CREW  ·  shows the answer",
              "the pit crew says what it does: " + pit.text)
      compare(String(leave.text), "ESC  LEAVE", "and the way out only ever leaves")
      // Neither hint changes its words with the hand.
      tc.dealHand()
      compare(String(leave.text), "ESC  LEAVE", "with a hand held the way out still says LEAVE")
      compare(String(leave.action), "LEAVE")
    }

    // ---------------------------------------------------------------------
    // THE LINE
    // ---------------------------------------------------------------------

    // The fact and the field are one line, and the reveal uses it.
    // The caret blinks at 1.25 Hz on a wall-clock timer, so the line is read
    // with the caret taken out and the caret is asserted on its own beat.
    function lineNoCaret() { return String(race.lineText).replace("▮", "") }
    function caretShowing() { return String(race.lineText).indexOf("▮") >= 0 }

    function test_15_the_answer_line_reads_as_one_line() {
      tc.fresh(120)
      tc.hintUntil(function (a) { return a.length === 2 })
      var label = Engine.factLabel(race.human.currentFact)
      var right = tc.answerString()
      // The pit crew that walked the deck here shows each answer for 1200 ms
      // on the same line; the case starts once that has cleared.
      tryVerify(function () { return race.revealText === "" }, 3000,
                "the pit crew's reveal cleared")
      compare(tc.lineNoCaret(), label + " = ", "the line is the fact and an equals sign")
      tryVerify(tc.caretShowing, 1000, "and the caret blinks in the empty answer")
      tc.press(right.charAt(0))
      compare(tc.lineNoCaret(), label + " = " + right.charAt(0),
              "a typed digit sits on the line after the equals sign")
      tryVerify(tc.caretShowing, 1000, "with the caret after it")
      tc.press("B")
      compare(tc.lineNoCaret(), label + " = ", "Backspace takes it back")

      // Two wrong answers: the same line shows the revealed fact and its
      // answer, then goes back to the new fact.
      tc.press("79E")
      tc.press("79E")
      verify(race.holdsForReveal(), "the second wrong answer put the reveal on the line")
      compare(race.lineText, label + " = " + right,
              "the reveal is the same line, and the caret is out of it: " + race.lineText)
      verify(Engine.factLabel(race.human.currentFact) !== label,
             "and the engine has already moved on behind it")
      tryVerify(function () { return !race.holdsForReveal() }, 3000, "the reveal let the line go")
      compare(tc.lineNoCaret(), Engine.factLabel(race.human.currentFact) + " = ",
              "and the line is the new fact again")
      tryVerify(tc.caretShowing, 1000, "with the caret back")
    }

    // A digit pressed into the reveal window waits for the line; Space does
    // not, because the hand is not the line.
    function test_16_the_reveal_holds_digits_and_not_the_hand() {
      tc.fresh(121)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 2 })
      tc.press("79E")
      tc.press("79E")
      verify(race.holdsForReveal(), "the reveal window is open")
      var covered = tc.snap()
      tc.press("1")
      var held = tc.snap()
      compare(race.revealQueue.length, 1, "the digit is waiting, not scored")
      compare(held.attempts, covered.attempts, "no attempt was recorded against a fact off screen")
      compare(held.hand, 3, "the hand is intact")
      tc.press("S")
      compare(root.cardsPlayed, 1, "Space fired the card through the reveal")
      compare(race.hand.length, 0, "and the hand is spent")
      tryVerify(function () { return !race.holdsForReveal() }, 3000, "the reveal let the line go")
      compare(race.revealQueue.length, 0, "the digit was replayed when the line came back")
    }

    // ---------------------------------------------------------------------
    // THE STALL, ON THE FIELD
    // ---------------------------------------------------------------------
    function stall(ms) {
      var stepped = Engine.step(race.state, { "kind": "tick" }, race.clockNow())
      var next = stepped.state
      for (var i = 0; i < next.racers.length; i++) {
        if (next.racers[i].id === next.humanId)
          next.racers[i].stalledUntilMs = next.nowMs + ms
      }
      race.state = next
      verify(race.stalled, "the field is locked, the way a Wrench locks it")
    }

    function unstall() {
      var stepped = Engine.step(race.state, { "kind": "tick" }, race.clockNow())
      var next = stepped.state
      for (var i = 0; i < next.racers.length; i++) {
        if (next.racers[i].id === next.humanId)
          next.racers[i].stalledUntilMs = 0
      }
      race.state = next
      verify(!race.stalled, "the stall is over")
    }

    function named(name) {
      var found = []
      function walk(item) {
        if (!item)
          return
        if (String(item.objectName) === name)
          found.push(item)
        var kids = item.children
        for (var i = 0; kids && i < kids.length; i++)
          walk(kids[i])
      }
      walk(race)
      return found
    }

    function drawn(item) {
      var node = item
      while (node && node !== root) {
        if (!node.visible || node.opacity <= 0.02)
          return false
        node = node.parent
      }
      return true
    }

    function textsOn(screen) {
      var out = []
      function walk(item) {
        if (!item)
          return
        if (typeof item.text === "string" && item.font !== undefined
            && item.text.length > 0 && tc.drawn(item))
          out.push(String(item.text))
        var kids = item.children
        for (var i = 0; kids && i < kids.length; i++)
          walk(kids[i])
      }
      walk(screen)
      return out
    }

    // A locked field is bolts on the answer slot and no banner anywhere; the
    // caret stops; Space still fires, because the hand is not the field.
    function test_17_the_stall_is_drawn_on_the_field_and_not_as_a_banner() {
      tc.fresh(122)
      tc.dealHand()
      var field = tc.named("answerField")[0]
      verify(field !== undefined, "the answer field is on the screen")
      compare(tc.named("caret").length, 1)
      var caretItem = tc.named("caret")[0]
      tryVerify(function () { return tc.drawn(caretItem) }, 1000,
                "the caret is drawn while the field is open")
      tc.stall(3000)
      verify(!tc.drawn(caretItem), "the caret stops while the field is locked")
      wait(450)
      verify(race.stalled && !tc.drawn(caretItem), "and stays stopped across a blink")
      var bolts = tc.named("stallBolt")
      compare(bolts.length, 4, "four bolts")
      var fieldBox = field.mapToItem(root, 0, 0, field.width, field.height)
      for (var b = 0; b < bolts.length; b++) {
        verify(tc.drawn(bolts[b]), "bolt " + b + " is drawn on the locked field")
        var box = bolts[b].mapToItem(root, 0, 0, bolts[b].width, bolts[b].height)
        verify(box.x + box.width > fieldBox.x - 40 && box.x < fieldBox.x + fieldBox.width + 40
               && box.y + box.height > fieldBox.y - 40 && box.y < fieldBox.y + fieldBox.height + 40,
               "bolt " + b + " sits on the answer field, not somewhere else: "
               + JSON.stringify(box) + " against " + JSON.stringify(fieldBox))
      }
      verify(tc.drawn(tc.named("stallBar")[0]), "and the lock bar is on the field")
      var texts = tc.textsOn(race)
      for (var t = 0; t < texts.length; t++)
        verify(texts[t].indexOf("ENGINE HIT") < 0, "no banner says ENGINE HIT: " + texts[t])
      // The hand is not the field.
      tc.press("S")
      compare(root.cardsPlayed, 1, "Space fired the card through the stall")
      tc.unstall()
    }

    // ---------------------------------------------------------------------
    // ONE CALLOUT, AND A PASS BY A RIVAL IS NOT ONE
    // ---------------------------------------------------------------------
    function callouts() {
      var found = []
      function walk(item) {
        if (!item)
          return
        if (item.isTransient === true)
          found.push(item)
        var kids = item.children
        for (var i = 0; kids && i < kids.length; i++)
          walk(kids[i])
      }
      walk(race)
      return found
    }

    function test_18_there_is_one_callout_slot_and_the_newest_wins() {
      tc.fresh(123)
      var slots = tc.callouts()
      compare(slots.length, 1, "exactly one callout on the race screen, not a stack")
      race.say("PASSED BOLT", Theme.lime)
      compare(String(slots[0].text), "PASSED BOLT")
      race.say("ROLL CAGE HELD", Theme.teal)
      compare(String(slots[0].text), "ROLL CAGE HELD", "the newest replaces the last")
      compare(tc.callouts().length, 1, "and there is still one")
      verify(slots[0].showing, "and it is showing")
    }

    function test_19_a_rival_passing_is_a_tag_and_a_pulse_not_a_sentence() {
      tc.fresh(124)
      var slot = tc.callouts()[0]
      var bolt = race.trackView.fxIndexOfId("bolt")
      verify(bolt >= 0, "Bolt is on the road")
      race.sayPass({ "otherId": "bolt", "gained": false })
      verify(!slot.showing || String(slot.text).indexOf("SLIPPED") < 0,
             "a rival passing did not become a callout: " + slot.text)
      compare(race.trackView.kartPlateText(bolt), "SLIPPED PAST",
              "Bolt's own tag says it")
      compare(race.trackView.minimapPulseKart, bolt, "and Bolt's dot pulses on the minimap")
      // The child passing IS a callout.
      race.sayPass({ "otherId": "bolt", "gained": true })
      compare(String(slot.text), "PASSED BOLT")
      verify(slot.showing)
    }

    // The ladder is gone, and with it the running last-place label the design's
    // Fairness list rules out.
    function test_20_there_is_no_standings_ladder() {
      tc.fresh(125)
      compare(race.ladder, undefined, "the ladder property is gone")
      var names = []
      function walk(item) {
        if (item === null || item === undefined)
          return
        if (item.Accessible !== undefined && item.Accessible.name !== undefined
            && String(item.Accessible.name).length > 0)
          names.push(String(item.Accessible.name))
        var kids = item.children
        if (kids === undefined)
          return
        for (var i = 0; i < kids.length; i++)
          walk(kids[i])
      }
      walk(race)
      for (var i = 0; i < names.length; i++) {
        verify(names[i].indexOf("Race order") < 0, "no 'Race order' strip is named")
        verify(!(names[i].indexOf("4th") === 0), "nothing is named starting '4th'")
      }
    }

    // The harness's key-press injection fires through the same functions the
    // keys reach.
    function test_21_the_harness_fires_a_card_the_way_the_keys_do() {
      tc.fresh(126)
      tc.dealHand()
      verify(race.injectEvent("fireCard", "2"), "fireCard:2 fired")
      compare(root.cardsPlayed, 1)
      compare(root.lastCardIndex, 1, "card 2")
      compare(race.hand.length, 0)
      verify(!race.injectEvent("fireCard", "1"), "and with no hand it refuses")
    }

    // ---------------------------------------------------------------------
    // ROUND 8. THE PANEL DOES NOT DECIDE A CARD WAS SPENT; THE ENGINE DOES.
    // ---------------------------------------------------------------------

    // Mark the child finished, the way `stall()` marks the field locked: a
    // step through the engine's own reducer, then the one flag. A finished
    // racer "cannot attack and cannot be attacked".
    function finishTheChild() {
      var stepped = Engine.step(race.state, { "kind": "tick" }, race.clockNow())
      var next = stepped.state
      for (var i = 0; i < next.racers.length; i++) {
        if (next.racers[i].id === next.humanId)
          next.racers[i].finished = true
      }
      race.state = next
      verify(race.human.finished, "the child has crossed the line")
    }

    // Every rival home, so a targeted card has nobody left to aim at.
    function finishEveryRival() {
      var stepped = Engine.step(race.state, { "kind": "tick" }, race.clockNow())
      var next = stepped.state
      for (var i = 0; i < next.racers.length; i++) {
        if (next.racers[i].id !== next.humanId)
          next.racers[i].finished = true
      }
      race.state = next
      compare(race.liveRivals.length, 0, "no rival is left in the fight")
    }

    function cardsUsedByChild() { return race.human.cardsUsed.length }

    // K9. Space after the child has finished: the hand stays, no slam plays,
    // no sound plays, nothing counts as played, and no guard is armed. Round 7
    // slammed, sounded, emitted `cardUsed`, and drew the hand back 570 ms
    // later when the engine refused.
    function test_24_space_after_the_finish_fires_nothing_and_says_nothing() {
      tc.fresh(129)
      tc.dealHand()
      tc.finishTheChild()
      Sfx.logging = true
      Sfx.clearLog()
      var before = tc.snap()
      var armedBefore = JSON.stringify(Actions.armed)
      var usedBefore = tc.cardsUsedByChild()
      verify(!race.canFire, "a finished child's hand cannot be fired")
      tc.press("S")
      var after = tc.snap()
      tc.row("K9", "child finished, hand held, Space", "S", before, after)
      compare(JSON.stringify(after), JSON.stringify(before),
              "Space after the finish changed the race: " + JSON.stringify(after))
      compare(after.hand, 3, "K9: the hand stays")
      compare(root.cardsPlayed, 0, "K9: nothing was played")
      compare(tc.cardsUsedByChild(), usedBefore, "K9: the engine took no card")
      verify(!race.handPanel.slamming, "K9: no slam plays")
      compare(Sfx.log.indexOf("slam"), -1, "K9: no slam sound: " + JSON.stringify(Sfx.log))
      compare(JSON.stringify(Actions.armed), armedBefore,
              "K9: a refused Space armed a guard: " + JSON.stringify(Actions.armed))
      // 700 ms later the hand is still the same three cards, drawn, not re-dealt.
      wait(700)
      compare(race.hand.length, 3)
      verify(!race.handPanel.slamming)
      // And the panel says why, in the words a screen reader hears.
      verify(String(race.handPanel.Accessible.description).indexOf("finished") >= 0,
             "the panel says the race is over for this hand: "
             + race.handPanel.Accessible.description)
      verify(race.handPanel.footerText.indexOf("USE") < 0,
             "and the USE chip is not printed: " + race.handPanel.footerText)
      Sfx.logging = false
    }

    // K7. Space while the deal is still drawing the cards does nothing; the
    // same press once they are drawn fires. Round 7 fired Nitro at dealT = 45 ms
    // with all three cards under the panel at opacity zero.
    function test_25_space_during_the_deal_waits_for_the_cards() {
      tc.fresh(130)
      tc.streakTo(race.state.streakThreshold - 1)
      compare(race.hand.length, 0, "no hand yet")
      Sfx.logging = true
      Sfx.clearLog()
      // The twelfth: the hand is dealt on this press and the deal begins.
      tc.answerNow()
      compare(race.hand.length, 3, "the twelfth dealt the hand")
      verify(race.handPanel.dealing, "and the cards are still sliding up: dealT = "
             + race.handPanel.dealT)
      var armedBefore = JSON.stringify(Actions.armed)
      var before = tc.snap()
      tc.press("S")
      var after = tc.snap()
      tc.row("K7", "Space on the frame the hand was dealt", "S", before, after)
      compare(JSON.stringify(after), JSON.stringify(before),
              "Space during the deal changed the race: " + JSON.stringify(after))
      compare(root.cardsPlayed, 0, "K7: nothing fired while the cards were being drawn")
      compare(race.hand.length, 3, "K7: the hand is intact")
      verify(!race.handPanel.slamming, "K7: no slam")
      compare(Sfx.log.indexOf("slam"), -1, "K7: no slam sound")
      compare(JSON.stringify(Actions.armed), armedBefore, "K7: nothing armed")
      // The cards arrive; now the same key fires.
      tryVerify(function () { return !race.handPanel.dealing }, 3000, "the deal finished")
      tc.press("S")
      compare(root.cardsPlayed, 1, "K7: Space fires once the cards are drawn")
      compare(race.hand.length, 0, "and the hand is spent")
      verify(race.handPanel.slamming, "and the slam is playing -- on the engine's answer")
      verify(Sfx.log.indexOf("slam") >= 0, "with its sound")
      Sfx.logging = false
    }

    // K8. A targeted card with every rival home: Space fires nothing and, unlike
    // round 7, arms nothing.
    function test_26_a_stranded_space_arms_no_guard() {
      tc.fresh(131)
      tc.dealHand()
      var slot = tc.targetedSlot()
      verify(slot >= 0)
      tc.highlightSlot(slot)
      tc.finishEveryRival()
      verify(race.handPanel.strandedTarget, "the card has nobody to aim at")
      verify(!race.canFire)
      var armedBefore = JSON.stringify(Actions.armed)
      var before = tc.snap()
      tc.press("S")
      var after = tc.snap()
      tc.row("K8", "targeted card, every rival finished, Space", "S", before, after)
      compare(JSON.stringify(after), JSON.stringify(before),
              "a stranded Space changed the race: " + JSON.stringify(after))
      compare(root.cardsPlayed, 0, "K8: nothing fired")
      compare(JSON.stringify(Actions.armed), armedBefore,
              "K8: a stranded Space armed a guard: " + JSON.stringify(Actions.armed))
      // A self card in the same hand still fires: the child is not finished.
      tc.highlightSlot(0)
      verify(race.canFire, "a self card can still be fired")
      tc.press("S")
      compare(root.cardsPlayed, 1)
    }

    // D2. `POWER-UP READY` reads on the charge bar at the instant of the deal,
    // although the streak is already back to zero, and stops reading after
    // the beat. Read off the Text items the bar draws.
    function chargeTexts() {
      var out = []
      var texts = tc.textsOn(race)
      for (var i = 0; i < texts.length; i++)
        if (texts[i].indexOf("POWER-UP") >= 0 || texts[i].indexOf("/ 12") >= 0
            || texts[i].indexOf("HAND HELD") >= 0)
          out.push(texts[i])
      return out
    }

    function test_27_power_up_ready_reads_on_the_charge_bar_at_the_deal() {
      tc.fresh(132)
      tc.streakTo(race.state.streakThreshold - 1)
      verify(tc.chargeTexts().indexOf("POWER-UP READY") < 0,
             "eleven does not read READY: " + JSON.stringify(tc.chargeTexts()))
      tc.answerNow()
      compare(race.hand.length, 3, "the twelfth dealt the hand")
      compare(race.human.streak, 0, "and the streak is back to zero in the same step")
      var atDeal = tc.chargeTexts()
      console.log("CHARGE AT THE DEAL: " + JSON.stringify(atDeal))
      verify(atDeal.indexOf("POWER-UP READY") >= 0,
             "the bar reads POWER-UP READY at the deal: " + JSON.stringify(atDeal))
      verify(atDeal.indexOf("HAND HELD  ·  12") < 0, "and not HAND HELD")
      // It reads once: gone after the beat, back to the count.
      tryVerify(function () { return tc.chargeTexts().indexOf("POWER-UP READY") < 0 }, 4000,
                "the words leave after the beat")
      verify(tc.chargeTexts().indexOf("0 / 12") >= 0,
             "and the count is back: " + JSON.stringify(tc.chargeTexts()))
    }

    // D9. A digit pressed into the pit crew's reveal waits for the line exactly
    // as one pressed into the wrong answer's does, and is replayed when it
    // comes back.
    function test_28_the_pit_crew_reveal_holds_digits_too() {
      tc.fresh(133)
      tc.hintUntil(function (a) { return a.length === 2 })
      tc.pressKey(Qt.Key_H)
      verify(race.holdsForReveal(), "the pit crew's reveal holds the line")
      verify(race.revealText.length > 0, "and the line is showing the answer: " + race.revealText)
      var afterH = tc.snap()
      var next = tc.answerString()
      tc.press(next.charAt(0))
      var held = tc.snap()
      compare(race.revealQueue.length, 1, "the digit is waiting, not scored")
      compare(held.attempts, afterH.attempts,
              "no attempt was recorded against a fact the line is not showing")
      compare(held.entry, "", "and the field is empty while the line is away")
      tryVerify(function () { return !race.holdsForReveal() }, 3000, "the line came back")
      compare(race.revealQueue.length, 0, "the digit was replayed")
      verify(race.shownEntry === next.charAt(0) || race.human.attemptCount > held.attempts,
             "and it landed on the fact the line now shows: entry '"
             + race.shownEntry + "', attempts " + race.human.attemptCount)
    }

    // D8. Down to the second rival, Right to a self card, Left back: the aim is
    // where the child put it. Round 7 forgot it on every highlight change.
    function test_29_browsing_the_cards_keeps_the_aim() {
      tc.fresh(134)
      tc.dealHand()
      var slot = tc.targetedSlot()
      verify(slot >= 0)
      tc.highlightSlot(slot)
      verify(race.handPanel.targeting)
      tc.press("v")
      compare(race.handPanel.targetIndex, 1, "Down aims at the second rival")
      var aimed = race.handPanel.targetId
      tc.press(">")
      verify(!race.handPanel.targeting, "Right is on a self card")
      compare(race.aimedRivalId, "", "and nothing is ringed while it is")
      tc.press("<")
      compare(race.handPanel.highlighted, slot, "Left is back on the targeted card")
      compare(race.handPanel.targetIndex, 1, "and the aim is still the second rival")
      compare(race.handPanel.targetId, aimed)
      compare(race.aimedRivalId, aimed, "and the ring is back on it")
      tc.press("<>")
      compare(race.handPanel.targetIndex, 1, "round the hand and back, still aimed")
      compare(root.cardsPlayed, 0)
    }

    // D12. A three-digit answer with a hand held: three digits, on the line,
    // scored once on the third, hand intact -- and the same with no hand.
    function test_30_three_digit_answers_are_typed_in_full_on_the_line() {
      tc.fresh(135)
      tc.dealHand()
      tc.streakTo(1)
      tc.hintUntil(function (a) { return a.length === 3 })
      var label = Engine.factLabel(race.human.currentFact)
      var before = tc.snap()
      tc.press(before.answer.charAt(0))
      tc.press(before.answer.charAt(1))
      var mid = tc.snap()
      compare(mid.entry, before.answer.substring(0, 2), "two digits are in the field")
      compare(tc.lineNoCaret(), label + " = " + before.answer.substring(0, 2),
              "and on the line: " + race.lineText)
      compare(mid.attempts, before.attempts, "nothing is scored yet")
      compare(mid.hand, 3, "the hand is intact")
      tc.press(before.answer.charAt(2))
      var after = tc.snap()
      tc.row("D12", "3-digit answer typed in full, hand held", before.answer, before, after)
      compare(after.streak, before.streak + 1, "D12: accepted as the answer on the third digit")
      compare(after.attempts, before.attempts + 1, "D12: scored once")
      compare(after.hand, 3, "D12: the hand was not spent")
      compare(after.cards - before.cards, 0, "D12: no card was played")
      compare(after.entry, "", "D12: the field cleared for the next fact")

      // And with no hand.
      tc.fresh(136)
      tc.hintUntil(function (a) { return a.length === 3 })
      var b2 = tc.snap()
      tc.press(b2.answer)
      var a2 = tc.snap()
      tc.row("D12b", "3-digit answer typed in full, no hand", b2.answer, b2, a2)
      compare(a2.streak, b2.streak + 1, "D12b: accepted")
      compare(a2.attempts, b2.attempts + 1, "D12b: scored once")
      compare(a2.hand, 0)
    }

    // The failure mode `pressKey()` exists for, and the reason every other row
    // in this file can be trusted.
    function test_22_a_keystroke_with_the_focus_elsewhere_reaches_nothing() {
      tc.fresh(127)
      var before = tc.snap()
      focusThief.forceActiveFocus()
      compare(race.focusTarget.activeFocus, false,
              "the precondition pressKey() checks cannot go false, so the guard is dead wood")
      keyClick(tc.digitKey(Number(before.answer.charAt(0))))
      var after = tc.snap()
      compare(after.attempts, before.attempts, "a key with the focus elsewhere was scored")
      compare(after.entry, before.entry, "a key with the focus elsewhere reached the field")
      race.forceActiveFocus()
      verify(race.focusTarget.activeFocus, "the case did not give the focus back")
    }

    function test_23_press_key_refuses_a_press_the_screen_cannot_receive() {
      tc.fresh(128)
      focusThief.forceActiveFocus()
      expectFail("", "pressKey() made a press the race screen could not receive")
      tc.pressKey(Qt.Key_1)
    }

    function cleanup() {
      race.externalClock = false
      Sfx.logging = false
      race.forceActiveFocus()
    }
  }

  // Somewhere for the focus to go that is not the race screen. See test_22.
  Item {
    id: focusThief
    width: 1
    height: 1
  }
}
