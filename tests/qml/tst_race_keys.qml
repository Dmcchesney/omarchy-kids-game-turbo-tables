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

    // Wait out any one-beat line the SET-UP left on the panel, so a case that
    // asserts the line is drawn cannot pass on a leftover from `streakTo()`.
    // The line is short-lived on purpose, and this is the price of that.
    function quiet() {
      tryCompare(race.handPanel, "letGoLineText", "", 2000)
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
      // ROUND 5: the message this line carried named `FINISH THE ANSWER FIRST`,
      // which round four deleted. A test's name is a claim, and a claim about a
      // string is checked against the string. See test_22.
      compare(race.handPanel.enterSpends, false,
              "B: Enter would answer the parked digit, not spend the card")
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

    // =====================================================================
    // ROUND 5 -- the four things round four changed, and the one round five
    // added. Round four landed in `ui/Picker.qml` and `ui/Race.qml` with no
    // case in this file behind any of it: four behaviours a critic had found by
    // driving, fixed, and then guarded by nothing. These are those guards.
    // =====================================================================

    // ROUND 4, defect 1 -- THE KEY THAT WAS PRINTED NOWHERE.
    //
    // This case reads the string the panel DRAWS, off the Text item that draws
    // it, because the claim it checks is the one this project got wrong by
    // reading an expression instead of a frame: round three's commit said "the
    // panel prints the way back" while the footer read FINISH THE ANSWER FIRST
    // and Backspace appeared in no visible or spoken string in the game.
    function test_22_the_deferred_footer_prints_all_three_keys() {
      tc.fresh(130)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      tc.press("1")
      compare(race.pending, "1", "the digit is parked, which is the state under test")

      var footer = race.handPanel.footerText
      var spoken = String(race.handPanel.Accessible.description)
      console.log("DEFERRED FOOTER AS RENDERED: " + JSON.stringify(footer))
      console.log("DEFERRED DESCRIPTION AS SPOKEN: " + JSON.stringify(spoken))

      verify(footer.indexOf("⌫") >= 0,
             "the Backspace key is printed on the panel: " + JSON.stringify(footer))
      verify(footer.indexOf("BACK TO THE CARD") >= 0,
             "and it is printed with what it does: " + JSON.stringify(footer))
      verify(footer.indexOf("⏎  ANSWER 1") >= 0,
             "Enter is printed with what it would send: " + JSON.stringify(footer))
      verify(footer.indexOf("ESC") >= 0, "and Escape is still printed")
      verify(footer.indexOf("FINISH THE ANSWER FIRST") < 0,
             "the sentence that cost a child their streak is gone")
      verify(spoken.indexOf("Backspace takes it back out") >= 0,
             "a screen-reader user is told the free key too: " + JSON.stringify(spoken))
    }

    // ROUND 4, defect 2 -- THE REVEAL WINDOW.
    //
    // A fact missed twice is covered by `7 x 8 = 56` for 1500 ms while the deck
    // has already moved on. A card key pressed into that window was read
    // against the engine's new fact, which the child could not see, and was
    // credited as a CORRECT ANSWER to a question never shown. Round four queues
    // those keys instead. Every press here is real; the only wait is the
    // reveal's own.
    function test_23_a_card_key_during_a_reveal_is_held_not_scored() {
      tc.fresh(131)
      tc.dealHand()
      tc.streakTo(2)
      // A two-digit fact, so `7` `9` submits itself. 79 is prime, so it is not
      // the answer to anything in the 1-12 deck: a guaranteed wrong answer that
      // uses no card key.
      tc.hintUntil(tc.isLen(2))
      var factUnderTest = Engine.factLabel(race.human.currentFact)
      tc.press("79")
      tc.press("79")
      verify(race.holdsForReveal(),
             "the second wrong answer put the reveal over the field")
      var covered = tc.snap()
      verify(Engine.factLabel(race.human.currentFact) !== factUnderTest,
             "and the engine's fact has already moved on behind it, which is the trap")

      tc.press("1")
      var held = tc.snap()
      compare(race.revealQueue.length, 1, "the card key is waiting, not spent and not scored")
      compare(held.streak, covered.streak, "nothing was credited to a fact off screen")
      compare(held.attempts, covered.attempts, "no attempt was recorded against it")
      compare(held.hand, 3, "the hand is intact")
      compare(held.cards - covered.cards, 0, "no card was played")
      compare(held.chosen, -1, "and nothing was chosen while the field was covered")

      // WAIT FOR THE WINDOW, NOT FOR A NUMBER OF MILLISECONDS.
      //
      // This read `tc.wait(1700)` against a reveal the engine holds for 1500,
      // which is two hundred milliseconds of slack -- and on a loaded machine
      // the whole of this file has been measured taking anywhere between 108
      // and 448 seconds, so a Qt Timer can and does land outside it. The test
      // then failed on "the queue was replayed", which is not the rule it is
      // about: the rule is that the keys wait for the FIELD and are replayed
      // when it comes back, and the field coming back is a state, not a
      // duration. `tryVerify` polls for that state and then the assertions
      // below are made against it, so the check is stricter than it was rather
      // than looser -- nothing about what must be true has changed, only what
      // the test waits on. Three seconds is twice the reveal's own hold.
      tryVerify(function () { return !race.holdsForReveal() }, 3000,
                "the reveal let the field go")
      compare(race.revealQueue.length, 0, "the queue was replayed when the field came back")
      verify(!race.holdsForReveal(), "and the window is closed")
      var after = tc.snap()
      tc.row("R", "two wrong answers, then a card key inside the reveal",
             "7 9 7 9 1", covered, after)
      compare(after.cards - covered.cards, 0, "R: no card was played by the replay either")
    }

    // ROUND 4, defects 3 and 4 -- THE STALL.
    //
    // WHAT IS SET UP AND WHAT IS PLAYED. A stall is the world's, not the
    // child's: it arrives when a rival's Wrench lands, and there is no key a
    // child can press to be hit. The rivals are frozen in this file on purpose
    // (see the header), so `stall()` writes the field the engine's own
    // `applyCard` writes -- `stalledUntilMs` on the human, which is what
    // `Engine.isStalled` reads and what `race.stalled` is bound to -- through a
    // real `Engine.step`. Every keystroke in the two cases below is still real.
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

    // N -- a stall landing between a card key and Enter. Round three cleared
    // the parked digit before the send, the engine refused it because the field
    // was locked, and the child lost the keystroke AND the card together.
    function test_24_a_stall_between_a_card_key_and_enter_destroys_neither() {
      tc.fresh(132)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      var before = tc.snap()
      tc.press("1")
      compare(race.pending, "1", "N: the digit is parked and the card is chosen")
      compare(race.handPanel.chosen, 0, "N: the card is chosen")

      tc.stall(3000)
      tc.press("E")
      var locked = tc.snap()
      compare(race.pending, "1", "N: the parked digit survived the locked Enter")
      compare(locked.chosen, 0, "N: and so did the card choice")
      verify(race.handPanel.footerText.indexOf("⌫") >= 0,
             "N: the panel still prints both keys: "
             + JSON.stringify(race.handPanel.footerText))
      tc.costNothing(before, locked, "N")

      tc.unstall()
      tc.press("B")
      compare(race.pending, "", "N: Backspace takes the digit back once the field returns")
      compare(race.handPanel.chosen, 0, "N: with the card still chosen")
      tc.press("E")
      var after = tc.snap()
      tc.row("N", "card key, stall, Enter, unstall, Backspace, Enter",
             "1 [stall] E [end] B E", before, after)
      compare(after.cards - before.cards, 1, "N: and the card the child chose was played")
      compare(after.streak, before.streak, "N: with the streak untouched")
    }

    // M -- a card key equal to a one-digit answer, pressed while the field is
    // locked. Round three did NOTHING with it: no card, no digit, no refusal
    // said out loud, for the two or three seconds of the hit.
    function test_25_a_card_key_that_is_the_answer_still_chooses_during_a_stall() {
      tc.fresh(133)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) >= 1 && Number(a) <= 3 })
      var key = Number(tc.answerString())
      var before = tc.snap()
      tc.stall(3000)
      tc.press(String(key))
      var after = tc.snap()
      tc.row("M", "1-digit answer = card key, pressed during a stall", String(key),
             before, after)
      compare(after.chosen, key - 1, "M: the press chose the card it names")
      compare(after.entry, "", "M: and nothing was typed into a locked field")
      compare(race.handPanel.enterSpends, true, "M: Enter would spend it")
      // `⏎  USE IT` for a self card, `⏎  USE` after the rival picker for a
      // targeted one -- which of the three the round-robin dealt is not this
      // case's business. What is: Enter is printed as the key that spends it.
      verify(race.handPanel.footerText.indexOf("⏎  USE") >= 0,
             "M: and the panel says so: " + JSON.stringify(race.handPanel.footerText))
      tc.costNothing(before, after, "M")
      tc.unstall()
    }

    // ROUND 5 -- defect 5 of round three, the silence.
    //
    // Two card keys that happen to spell the answer are submitted as that
    // answer, which is the least-bad reading, and the card choice goes with
    // them. The critic's finding was the hand "vanishing without explanation".
    // The panel now says what happened, and says the true thing: the CHOICE
    // went back, the hand did not.
    function test_26_a_card_put_back_by_a_pair_of_card_keys_is_announced() {
      tc.fresh(134)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) {
        return a.length === 2 && Number(a.charAt(0)) <= 3
               && Number(a.charAt(1)) >= 1 && Number(a.charAt(1)) <= 3
      })
      tc.quiet()
      var before = tc.snap()
      tc.press(before.answer.charAt(0))
      compare(race.handPanel.chosen, Number(before.answer.charAt(0)) - 1,
             "the first key chose a card, provisionally")
      tc.press(before.answer.charAt(1))
      var after = tc.snap()
      tc.row("P", "2-digit answer, both digits card keys, the choice let go",
             before.answer, before, after)
      compare(after.chosen, -1, "the choice went when the pair became the answer")
      compare(after.hand, 3, "but the hand did not")
      compare(after.streak, before.streak + 1, "and the pair was accepted as the answer")

      var line = race.handPanel.letGoLineText
      console.log("LET-GO LINE AS RENDERED: " + JSON.stringify(line))
      verify(line.indexOf("CARD PUT BACK") >= 0,
             "the panel says the card went back: " + JSON.stringify(line))
      verify(line.indexOf("ALL THREE STILL YOURS") >= 0,
             "and that the hand is still held: " + JSON.stringify(line))
      var spoken = String(race.handPanel.Accessible.description)
      verify(spoken.indexOf("put back") >= 0,
             "and a screen-reader user is told the same: " + JSON.stringify(spoken))
      verify(spoken.indexOf("All three cards are still yours") >= 0,
             "including the half that matters: " + JSON.stringify(spoken))
    }

    // The same line must NOT appear when a card was actually spent -- "put
    // back" over a hand that is gone would be the one lie this panel must never
    // tell -- and must not appear when nothing was chosen at all.
    function test_27_the_let_go_line_stays_off_when_a_card_was_spent() {
      tc.fresh(135)
      tc.dealHand()
      compare(race.handPanel.letGoLineText, "",
              "a hand just dealt says nothing: nothing has been chosen or let go")
      tc.hintUntil(function (a) { return a.length === 1 && Number(a) > 3 })
      compare(race.handPanel.letGoLineText, "",
              "and the pit crew walking the deck on says nothing either")
      tc.press("1B")
      compare(race.handPanel.chosen, 0, "the card is chosen with an empty field")
      compare(race.handPanel.letGoLineText, "",
              "choosing a card is not letting one go")
      tc.press("E")
      compare(root.cardsPlayed, 1, "the card was played")
      compare(race.hand.length, 0, "using one spends all three")
      compare(race.handPanel.letGoLineText, "",
              "a card that was SPENT is never announced as put back")
    }

    // The commonest route to the same line, recorded rather than discovered: an
    // ordinary two-digit answer whose FIRST digit is 1, 2 or 3, typed while a
    // hand is held. The first press highlights that card tile -- `ui/Race.qml`
    // chooses it provisionally, because it cannot yet know -- and the second
    // press takes the highlight away again. The line is what says why, and it
    // says the true thing: nothing was spent.
    function test_28_an_ordinary_answer_that_starts_with_a_card_key_says_it_too() {
      tc.fresh(136)
      tc.dealHand()
      tc.streakTo(2)
      tc.hintUntil(function (a) {
        return a.length === 2 && Number(a.charAt(0)) <= 3 && Number(a.charAt(1)) > 3
      })
      tc.quiet()
      var before = tc.snap()
      tc.press(before.answer.charAt(0))
      compare(race.handPanel.chosen, Number(before.answer.charAt(0)) - 1,
              "the first digit lights the card tile it names")
      compare(race.handPanel.letGoLineText, "", "and says nothing yet")
      tc.press(before.answer.charAt(1))
      var after = tc.snap()
      tc.row("P2", "2-digit answer starting with a card key", before.answer, before, after)
      compare(after.streak, before.streak + 1, "P2: the answer was accepted")
      compare(after.hand, 3, "P2: the hand is intact")
      compare(after.cards - before.cards, 0, "P2: no card was played")
      verify(race.handPanel.letGoLineText.indexOf("ALL THREE STILL YOURS") >= 0,
             "P2: and the panel says the highlight going does not mean the hand went: "
             + JSON.stringify(race.handPanel.letGoLineText))
    }

    // Q -- THE HOLE BETWEEN THE ROWS ABOVE, AND IT COST A STREAK.
    //
    // Every shape either side of this one is guarded: a card key followed by
    // another card key (I1..I3), a card key followed by Enter (D), Backspace
    // (F), Escape (M), the hint (L), and an answer whose FIRST digit is itself
    // a card key (C2, C3, P2). The one in the middle was not: a card key, then
    // an answer digit that is NOT a card key.
    //
    // `4 x 12 = 48`. `1` chooses card one and prints a provisional `1`. `4` is
    // past the end of a hand of three, so it is not a card key at all and goes
    // straight to the engine -- and the provisional `1` was still in the field.
    // `14` is two digits long, so it submitted itself: the streak gone, one
    // `missed`, one attempt, on a question the child got right. Six runs out of
    // six before the fix.
    function test_29_a_card_key_then_an_answer_the_hand_cannot_type() {
      tc.fresh(140)
      tc.dealHand()
      tc.streakTo(3)
      // A two-digit answer whose first digit is past a hand of three, so the
      // press that follows the card key cannot be read as another card.
      tc.hintUntil(function (a) { return a.length === 2 && Number(a.charAt(0)) > 3 })
      tc.quiet()
      var before = tc.snap()
      tc.press("1")
      compare(race.handPanel.chosen, 0, "Q: the card key chose card one")
      compare(after0(), "1", "Q: and printed its digit, provisionally")
      tc.press(before.answer.charAt(0))
      compare(after0(), before.answer.charAt(0),
              "Q: the card's digit came back out, so the field is the child's own first"
              + " digit and nothing else")
      tc.press(before.answer.charAt(1))
      var after = tc.snap()
      tc.row("Q", "2-digit answer, card key then an answer starting past the hand",
             "1 " + before.answer, before, after)
      compare(after.streak, before.streak + 1, "Q: the answer was accepted")
      compare(after.missed, before.missed, "Q: nothing was recorded as missed")
      compare(after.attempts, before.attempts + 1,
              "Q: one attempt, for the one answer that was given")
      compare(after.hand, before.hand, "Q: the hand is intact")
      compare(after.cards - before.cards, 0, "Q: no card was played")
      compare(after.chosen, -1, "Q: and the card choice was let go of")
    }

    // The same shape on five more seeds, because the bug it guards depended on
    // which fact the deck happened to be showing and a single seed could hide
    // it again.
    function test_30_the_same_on_five_more_decks() {
      var seeds = [141, 142, 143, 144, 145]
      for (var i = 0; i < seeds.length; i++) {
        tc.fresh(seeds[i])
        tc.dealHand()
        tc.streakTo(3)
        tc.hintUntil(function (a) { return a.length === 2 && Number(a.charAt(0)) > 3 })
        var before = tc.snap()
        tc.press("1" + before.answer)
        var after = tc.snap()
        compare(after.streak, before.streak + 1,
                "seed " + seeds[i] + ": `1` then " + before.answer
                + " on " + before.fact + " = " + before.answer
                + " is the answer, not " + ("1" + before.answer.charAt(0)))
        compare(after.missed, before.missed,
                "seed " + seeds[i] + ": and nothing was missed")
        compare(after.cards - before.cards, 0,
                "seed " + seeds[i] + ": and no card was played")
      }
    }

    function after0() { return race.shownEntry }

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
