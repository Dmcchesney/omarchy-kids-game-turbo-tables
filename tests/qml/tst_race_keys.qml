import QtQuick
import QtTest
import qs.Commons
import "../../ui"
import "../../engine/engine.mjs" as Engine

// The race screen's keyboard, driven with real key events only.
//
// `1`, `2` and `3` are card keys and answer digits at the same time, and this
// file is the record of what every reachable combination of them costs a child.
// Nothing here calls `typeKey`, `choose`, `confirm` or `send`: every assertion
// is made by `keyClick()`, which posts the events a window manager posts, so
// what passes is the arbitration a child meets.
//
// Two things are set up rather than played, and both are named where they are
// used: the seed (to rebuild the race between cases) and `race.rivals = null`
// (to stop the AI karts thinking, so a stall from a rival's Wrench cannot land
// in the middle of a measurement). Every keystroke of the CHILD's is real.
//
// Run it:
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
//     qmltestrunner -platform offscreen -import dev/imports -input tests/qml
//
// ---------------------------------------------------------------------------
// RUN THIS HEADLESS, AND WHY THAT IS NOT A PREFERENCE
// ---------------------------------------------------------------------------
//
// This spec was reported flaky -- "3 failures in 20 runs alone at HEAD on a
// clean tree", across five different case names -- and worse, it was scoring
// other people's mutation runs: three `ui/Store.qml` mutations came back KILLED
// partly by cases in this file, which contains the string `Store` zero times.
//
// It is not flaky. It is a spec made entirely of real key events, and a real
// key event needs a window that holds the keyboard. Measured, four concurrent
// `qmltestrunner` processes, same tree, same HEAD, one variable:
//
//   windowed (cocoa)          65 of 100 runs failed, 17 different case names
//   headless (-platform offscreen)   0 of 100 runs failed
//   one process at a time, either platform   0 of 60 runs failed
//
// macOS gives keyboard activation to one window at a time. A second Qt window
// anywhere on the machine -- another spec, another agent's harness, anything --
// deactivates this one, every item's `activeFocus` goes false, and `keyClick()`
// after that is delivered nowhere. The engine sees no input, so `dealHand()`
// reports "a hand of three is held: 0", `streakTo()` reports "the streak is
// where the case wants it", `hintUntil()` reports "reached a fact whose answer
// fits the shape" -- three sentences about the child's keyboard, none of them
// true, and which case says them depends on when the other window appeared.
// That is the whole of the flake, and it is in the runner, not in the
// arbitration and not in `ui/Race.qml`.
//
// Two things follow, and both are in this file. Every key goes through
// `pressKey()`, which checks the precondition on every press and says exactly
// this when it is gone rather than letting a lost keystroke be read as a
// verdict. And the run line above is headless, which is the repository's rule
// for every Qt process on this Mac anyway.
//
// The two rules every row below is judged against:
//
//   A deliberate card choice must cost nothing -- no streak, no `missed` entry,
//   no attempt, no card.
//   A wrong answer must cost the streak and only the streak, and it must reach
//   the engine rather than being deleted on the way.
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
  property int leaveRequests: 0

  Connections {
    target: race.handPanel
    function onCardUsed(index, targetId) { root.cardsPlayed += 1 }
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

    // Every key in this file goes through here, and every key is checked
    // against the one precondition the whole spec rests on: the race screen's
    // key catcher still has active focus. See "RUN THIS HEADLESS" in the header
    // -- when it does not, `keyClick` is delivered nowhere, the engine sees no
    // input at all, and the assertion that fails is a row about the child's
    // keyboard rather than the truth, which is that the keystroke never
    // arrived. Sixty-five runs in a hundred failed that way, spread over
    // seventeen different case names, and every one of them read as a verdict
    // about the arbitration.
    function pressKey(code) {
      verify(race.focusTarget.activeFocus,
             "the race screen's key catcher lost active focus mid-case, so this keystroke"
             + " was delivered nowhere. Nothing below this line is a statement about the"
             + " arbitration. Run this spec headless (-platform offscreen): a windowed run"
             + " shares keyboard activation with every other window on the machine.")
      keyClick(code)
    }

    // "12EBXH" -> the digits 1 and 2, Enter, Backspace, Escape, H.
    function press(script) {
      for (var i = 0; i < script.length; i++) {
        var c = script.charAt(i)
        if (c === "E") tc.pressKey(Qt.Key_Return)
        else if (c === "B") tc.pressKey(Qt.Key_Backspace)
        else if (c === "X") tc.pressKey(Qt.Key_Escape)
        else if (c === "H") tc.pressKey(Qt.Key_H)
        else tc.pressKey(tc.digitKey(Number(c)))
      }
    }

    // ---------------------------------------------------------------- setup
    function fresh(seedValue) {
      race.seed = seedValue
      // The AI karts are frozen for the length of a case. A rival's Wrench is a
      // two-second field lock, and a lock landing mid-measurement would make
      // these rows say something about the rivals rather than about the keys.
      race.rivals = null
      race.forceActiveFocus()
      verify(race.focusTarget.activeFocus, "the race screen's key catcher has focus")
      root.cardsPlayed = 0
      root.leaveRequests = 0
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
    }

    function streakTo(n) {
      var guard = 0
      while (race.human.streak < n && guard < 24) {
        tc.answerNow()
        guard += 1
      }
      compare(race.human.streak, n, "the streak is where the case wants it")
    }

    function isLen(n) { return function (a) { return a.length === n } }
    function isExactly(s) { return function (a) { return a === s } }
    function startsWithNot(n) {
      // a two-digit answer that does NOT start with `n`, so `n` cannot be the
      // first digit of it
      return function (a) { return a.length === 2 && a.charAt(0) !== String(n) }
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
        "chosen": race.handPanel.chosen,
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
                  + "|chosen " + after.chosen)
    }

    // A deliberate card choice cost nothing.
    function costNothing(before, after, id) {
      compare(after.streak, before.streak, id + ": the streak is untouched")
      compare(after.missed, before.missed, id + ": no fact was recorded as missed")
      compare(after.attempts, before.attempts, id + ": no attempt was recorded")
      compare(after.hand, before.hand, id + ": the hand is intact")
      compare(after.cards - before.cards, 0, id + ": no card was played")
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
      compare(race.pending, "")
      compare(race.provisional, 0)
    }

    // A -- one-digit answer, and the key IS that answer. The press is the
    // answer, unambiguously, and the hand is not touched.
    function test_01_one_digit_answer_equal_to_the_card_key() {
      tc.fresh(102)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) <= 3 })
      var key = Number(tc.answerString())
      var before = tc.snap()
      tc.press(String(key))
      var after = tc.snap()
      tc.row("A", "1-digit answer = card key", String(key), before, after)
      compare(after.streak, before.streak + 1, "A: the answer was right and the streak grew")
      compare(after.hand, before.hand, "A: the hand is intact")
      compare(after.cards - before.cards, 0, "A: no card was played")
      compare(after.missed, before.missed, "A: nothing was recorded as missed")
    }

    // B -- one-digit answer, key is NOT the answer. This is the shape round two
    // deleted: no sputter, no streak reset, no `missed` entry, and then Enter
    // spent all three cards. The digit is now deferred and shown.
    function test_02_one_digit_answer_unequal_to_the_card_key_is_shown() {
      tc.fresh(103)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      var before = tc.snap()
      tc.press("1")
      var after = tc.snap()
      tc.row("B", "1-digit answer != card key, press only", "1", before, after)
      compare(after.entry, "1", "B: the child's keystroke is on screen, not deleted")
      compare(after.chosen, 0, "B: and the card is chosen, so both readings are visible")
      tc.costNothing(before, after, "B")
      compare(race.handPanel.enterSpends, false,
              "B: the panel says FINISH THE ANSWER FIRST while the digit stands")
    }

    // G -- the same shape, followed by the Enter a child is taught to press. It
    // must submit the answer: streak gone, a miss recorded, and no card played.
    function test_03_a_genuine_wrong_one_two_or_three_costs_the_streak_only() {
      tc.fresh(104)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      var before = tc.snap()
      tc.press("1E")
      var after = tc.snap()
      tc.row("G", "1-digit answer != card key, then Enter", "1 E", before, after)
      tc.costStreakOnly(before, after, "G")
      compare(after.fact, before.fact, "G: the same fact stays, as the answer loop says")
      compare(after.entry, "", "G: the field cleared")
    }

    // B2 -- and Backspace on that deferred digit puts the child one printed key
    // from the card, with nothing spent on the way.
    function test_04_backspace_on_a_deferred_digit_frees_the_card() {
      tc.fresh(105)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      var before = tc.snap()
      tc.press("1B")
      var mid = tc.snap()
      compare(mid.entry, "", "B2: the deferred digit is taken back")
      compare(mid.chosen, 0, "B2: the card is still chosen")
      compare(race.handPanel.enterSpends, true, "B2: the panel now says USE IT")
      tc.costNothing(before, mid, "B2")
      tc.press("E")
      var after = tc.snap()
      tc.row("B2", "1-digit answer != card key, Backspace, Enter", "1 B E", before, after)
      compare(after.cards - before.cards, 1, "B2: the card was played")
      compare(after.streak, before.streak, "B2: and the streak survived it")
      compare(after.missed, before.missed, "B2: nothing was recorded as missed")
      compare(after.hand, 0, "B2: using one spends all three")
    }

    // C -- a two-digit answer. The first card key types provisionally.
    function test_05_two_digit_answer_one_card_key_then_enter_plays_it() {
      tc.fresh(106)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("1")
      var mid = tc.snap()
      compare(mid.entry, "1", "C: the digit shows, held provisional")
      tc.costNothing(before, mid, "C")
      tc.press("E")
      var after = tc.snap()
      tc.row("C", "2-digit answer, one card key then Enter", "1 E", before, after)
      compare(after.cards - before.cards, 1, "C: the card was played")
      compare(after.streak, before.streak, "C: the streak survived")
      compare(after.missed, before.missed, "C: nothing was recorded as missed")
      compare(after.entry, "", "C: the provisional digit was given back")
    }

    // I -- THE ROUND-TWO DEFECT. Two different card keys on a two-digit answer.
    // `1` then `2` used to make `12`, which the engine submitted on the spot:
    // streak gone, a miss banked on a fact never attempted, and no card played.
    function test_06_two_different_card_keys_change_the_choice_and_cost_nothing() {
      tc.fresh(107)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) {
        // a two-digit answer that is neither `1x` nor exactly `12`, so `1` then
        // `2` cannot be the child typing this answer
        return a.length === 2 && a.charAt(0) !== "1"
      })
      var before = tc.snap()
      tc.press("12")
      var after = tc.snap()
      tc.row("I", "2-digit answer, two different card keys", "1 2", before, after)
      tc.costNothing(before, after, "I")
      compare(after.chosen, 1, "I: the second key is now the chosen card")
      compare(after.entry, "2", "I: and the field holds that card's digit, not 12")
    }

    // I, verbatim -- the critic's own reproduction: an answer whose FIRST digit
    // is the first card key, so that press is a live start of the answer, and
    // whose second digit is not the second card key. `1` then `2` on `1 x 10`.
    // Round two made `12`, `12`.length === `10`.length, and the engine submitted
    // it: streak 2 -> 0, missed 0 -> 1, no card played.
    function test_06b_the_second_card_key_over_a_live_first_digit() {
      tc.fresh(121)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) {
        return a.length === 2 && a.charAt(0) === "1" && a.charAt(1) !== "2"
      })
      var before = tc.snap()
      tc.press("1")
      var mid = tc.snap()
      compare(mid.entry, "1", "I: the first key is a live first digit of the answer")
      compare(mid.chosen, 0, "I: and it chose card one")
      tc.press("2")
      var after = tc.snap()
      tc.row("I·", "answer starts with the first card key, then a second", "1 2", before, after)
      tc.costNothing(before, after, "I·")
      compare(after.chosen, 1, "I: the second key is now the chosen card")
      compare(after.entry, "2", "I: and the field holds that card's digit, not 12")
      compare(after.fact, before.fact, "I: the fact did not move")

      // and the same key twice, over the same live first digit
      var b2 = tc.snap()
      tc.press("11")
      var a2 = tc.snap()
      tc.row("I2·", "the same card key twice over a live first digit", "1 1", b2, a2)
      tc.costNothing(b2, a2, "I2·")
      compare(a2.chosen, 0, "I2: back to card one")
      compare(a2.entry, "1", "I2: one digit in the field, not 11")
    }

    // I2 -- the same card key twice.
    function test_07_the_same_card_key_twice_costs_nothing() {
      tc.fresh(108)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("11")
      var after = tc.snap()
      tc.row("I2", "2-digit answer, same card key twice", "1 1", before, after)
      tc.costNothing(before, after, "I2")
      compare(after.chosen, 0, "I2: still card one")
      compare(after.entry, "1", "I2: one digit in the field, not 11")
    }

    // I3 -- three card keys running, which is what a child does with three cards
    // printed in front of them.
    function test_08_three_card_keys_running_cost_nothing() {
      tc.fresh(109)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("123")
      var after = tc.snap()
      tc.row("I3", "2-digit answer, three card keys running", "1 2 3", before, after)
      tc.costNothing(before, after, "I3")
      compare(after.chosen, 2, "I3: the last key chose")
      compare(after.entry, "3", "I3: one digit in the field, not 123")
    }

    // The other half of the same rule: no answer became untypable.
    function test_09_a_two_digit_answer_starting_with_a_card_key_is_still_typable() {
      tc.fresh(110)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 2 && Number(a.charAt(0)) <= 3 })
      var before = tc.snap()
      tc.press(before.answer)
      var after = tc.snap()
      tc.row("C2", "2-digit answer typed in full", before.answer, before, after)
      compare(after.streak, before.streak + 1, "C2: it was accepted as the answer")
      compare(after.hand, before.hand, "C2: the hand was not spent")
      compare(after.cards - before.cards, 0, "C2: no card was played")
    }

    // ... including one whose two digits are BOTH card keys, which is the
    // collision the round-two rule could not see.
    function test_10_an_answer_made_of_two_card_keys_is_still_typable() {
      tc.fresh(111)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) {
        return a.length === 2 && Number(a.charAt(0)) <= 3 && Number(a.charAt(1)) >= 1 && Number(a.charAt(1)) <= 3
      })
      var before = tc.snap()
      tc.press(before.answer)
      var after = tc.snap()
      tc.row("C3", "2-digit answer, both digits card keys", before.answer, before, after)
      compare(after.streak, before.streak + 1, "C3: accepted as the answer")
      compare(after.hand, before.hand, "C3: the hand was not spent")
      compare(after.cards - before.cards, 0, "C3: no card was played")
    }

    // L -- a card key, then the pit crew. Round two left the provisional claim
    // alive across the hint, so the next digit the child typed was backspaced
    // away by an Enter that spent the hand.
    function test_11_a_card_key_then_the_hint_leaves_no_claim_behind() {
      tc.fresh(112)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("1H")
      compare(race.provisional, 0, "L: the hint retired the provisional claim")
      compare(race.pending, "", "L: and any deferred digit with it")
      var next = tc.answerString()
      tc.press(next.charAt(0))
      var mid = tc.snap()
      verify(mid.entry.charAt(mid.entry.length - 1) === next.charAt(0),
             "L: the child's own digit is in the field")
      tc.press(next.substring(1))
      var after = tc.snap()
      tc.row("L", "card key, hint, then answer the new fact", "1 H " + next, before, after)
      compare(after.hand, before.hand, "L: the hand was not spent")
      compare(after.cards - before.cards, 0, "L: no card was played")
      compare(after.streak, before.streak + 1, "L: the new fact was answered correctly")
    }

    // F -- a card key then Backspace on a two-digit answer.
    function test_12_a_card_key_then_backspace() {
      tc.fresh(113)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("1B")
      var after = tc.snap()
      tc.row("F", "2-digit answer, card key then Backspace", "1 B", before, after)
      compare(after.entry, "", "F: the digit came back out")
      compare(after.chosen, 0, "F: the card is still chosen")
      tc.costNothing(before, after, "F")
      compare(race.handPanel.enterSpends, true, "F: Enter would play the card")
    }

    // E -- a card key then Escape. Escape is back-one: it puts the card back and
    // takes the digit with it, and only then does it mean leave the race.
    function test_13_a_card_key_then_escape() {
      tc.fresh(114)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("1X")
      var after = tc.snap()
      tc.row("E", "2-digit answer, card key then Escape", "1 X", before, after)
      compare(after.entry, "", "E: no stray digit is left in the field")
      compare(after.chosen, -1, "E: the card was put back")
      compare(root.leaveRequests, 0, "E: the first Escape did not leave the race")
      tc.costNothing(before, after, "E")
      tc.press("X")
      compare(root.leaveRequests, 1, "E: the second Escape left the race")
    }

    // E2 -- Escape on a DEFERRED digit, the one-digit shape.
    function test_14_escape_on_a_deferred_digit() {
      tc.fresh(115)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      var before = tc.snap()
      tc.press("1X")
      var after = tc.snap()
      tc.row("E2", "1-digit answer != card key, then Escape", "1 X", before, after)
      compare(after.entry, "", "E2: the deferred digit went with the card")
      compare(after.chosen, -1, "E2: the card was put back")
      compare(root.leaveRequests, 0, "E2: Escape did not leave the race")
      tc.costNothing(before, after, "E2")
    }

    // A wrong answer that is not a card key at all, for the comparison the two
    // rules are read against.
    function test_15_an_ordinary_wrong_answer_costs_the_streak_only() {
      tc.fresh(116)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) !== 9 })
      var before = tc.snap()
      tc.press("9")
      var after = tc.snap()
      tc.row("W", "1-digit fact, an ordinary wrong answer", "9", before, after)
      tc.costStreakOnly(before, after, "W")
    }

    // D -- three digits. The deck's three-digit answers live in the last laps,
    // so this case walks there with the pit crew and then types.
    function test_16_three_digit_answers() {
      tc.fresh(117)
      tc.dealHand()
      tc.hintUntil(tc.isLen(3))
      tc.streakTo(1)
      tc.hintUntil(tc.isLen(3))
      var before = tc.snap()
      tc.press(before.answer)
      var after = tc.snap()
      tc.row("D1", "3-digit answer typed in full", before.answer, before, after)
      compare(after.streak, before.streak + 1, "D1: accepted as the answer")
      compare(after.hand, before.hand, "D1: the hand was not spent")
      compare(after.cards - before.cards, 0, "D1: no card was played")

      tc.hintUntil(tc.isLen(3))
      var b2 = tc.snap()
      tc.press("1")
      var m2 = tc.snap()
      tc.costNothing(b2, m2, "D2")
      tc.press("E")
      var a2 = tc.snap()
      tc.row("D2", "3-digit answer, one card key then Enter", "1 E", b2, a2)
      compare(a2.cards - b2.cards, 1, "D2: the card was played")
      compare(a2.streak, b2.streak, "D2: the streak survived")
      compare(a2.missed, b2.missed, "D2: nothing was recorded as missed")
    }

    // H -- no hand held. 1, 2 and 3 are only digits, and a wrong one is a wrong
    // answer like any other.
    function test_17_with_no_hand_the_card_keys_are_only_digits() {
      tc.fresh(118)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      compare(race.hand.length, 0, "H: no hand is held")
      var before = tc.snap()
      tc.press("1")
      var after = tc.snap()
      tc.row("H", "no hand held, a wrong 1", "1", before, after)
      compare(after.missed, before.missed + 1, "H: it was submitted as the answer")
      compare(after.attempts, before.attempts + 1, "H: one attempt")
      compare(race.handPanel.chosen, -1, "H: nothing was chosen")
    }

    // J -- round one's finding, at the fact level: two card keys must not walk
    // the deck on. Round two's `1` `2` banked a miss and advanced the fact.
    function test_18_card_keys_never_walk_the_deck_on() {
      tc.fresh(119)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(tc.startsWithNot(1))
      var before = tc.snap()
      tc.press("12121212")
      var after = tc.snap()
      tc.row("J", "2-digit answer, four card-key pairs", "1 2 1 2 1 2 1 2", before, after)
      compare(after.fact, before.fact, "J: the same fact is still on screen")
      tc.costNothing(before, after, "J")
    }

    // The ladder is gone, and with it the running last-place label the design's
    // Fairness list rules out.
    function test_19_there_is_no_standings_ladder() {
      tc.fresh(120)
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
      console.log("A11Y NAMES ON THE RACE SCREEN: " + JSON.stringify(names))
    }

    // The failure mode `pressKey()` exists for, and the reason every other row
    // in this file can be trusted.
    //
    // It is reproduced by taking the focus away, not by opening a second window
    // -- the state is "the key catcher does not have active focus", and a test
    // can put the tree in that state directly. Reproducing the state beats
    // reproducing the race, and this repository does not open windows.
    //
    // Both halves matter. If the precondition can never go false the guard is
    // dead wood; if a keystroke with the focus elsewhere still reached the
    // engine there would have been nothing to guard. Measured windowed, before
    // the guard: 65 runs in 100 failed this way, in seventeen different case
    // names, every one of them phrased as a verdict about the child's keyboard.
    function test_20_a_keystroke_with_the_focus_elsewhere_reaches_nothing() {
      tc.fresh(122)
      var before = tc.snap()

      focusThief.forceActiveFocus()
      compare(race.focusTarget.activeFocus, false,
              "the precondition pressKey() checks cannot go false, so the guard is dead wood")

      // Deliberately raw: this is the press `pressKey()` now refuses to make.
      keyClick(tc.digitKey(Number(before.answer.charAt(0))))
      var after = tc.snap()
      compare(after.attempts, before.attempts, "a key with the focus elsewhere was scored")
      compare(after.streak, before.streak, "a key with the focus elsewhere moved the streak")
      compare(after.entry, before.entry, "a key with the focus elsewhere reached the field")

      race.forceActiveFocus()
      verify(race.focusTarget.activeFocus, "the case did not give the focus back")
    }

    // And the guard itself, in the same state. `expectFail` turns the refusal
    // above into the expected outcome, so a `pressKey()` that stopped checking
    // would be reported as a test that unexpectedly passed. Without this the
    // guard is a line nothing is watching -- which is exactly the standard this
    // round applied to two guards in `shell/FileStore.qml`.
    function test_21_press_key_refuses_a_press_the_screen_cannot_receive() {
      tc.fresh(123)
      focusThief.forceActiveFocus()
      expectFail("", "pressKey() made a press the race screen could not receive")
      tc.pressKey(Qt.Key_1)
    }

    function cleanup() {
      // Whatever a case did with the focus, the next one starts from the race.
      race.forceActiveFocus()
    }
  }

  // Somewhere for the focus to go that is not the race screen. See test_20.
  Item {
    id: focusThief
    width: 1
    height: 1
  }
}
