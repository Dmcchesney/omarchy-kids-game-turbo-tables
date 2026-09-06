.pragma library

// PIECE M. THE PARITY TABLE'S KEY COLUMN, PARSED RATHER THAN COUNTED.
//
// Round one's gate asked only that a `Clickable.key` column was NON-EMPTY, and
// a critic named what that is worth: `key: "banana"` passed -- on the column
// that IS the whole claim of the click -> key direction. So the column is
// parsed here against the very table `--do key:<name>` posts events from, and
// this is a library rather than a method on the harness so that the walk and
// `tests/qml/tst_mouse_parity.qml` ask the same question in the same words.
// Two copies of a grammar is one copy that drifts.
//
// ROUND 3 -- WHAT THIS FILE NO LONGER DOES.
//
// It also held a grammar for reading printed key hints OFF THE SCREEN:
// `isKeycap` and `isHintLine`, used by a third oracle that decided from the
// shape of a rendered string whether it was a promise about a key. A critic
// demonstrated that oracle wrong in both directions on this build -- scoreboard
// copy like `3  CORRECT` and `2  TO GO` flagged as dead hints, and `PAUSE  P`,
// `H\nPIT CREW`, `ESC BACK` and every glyph outside a hard-coded table
// invisible to it -- and a rule that guesses intent from appearance cannot be
// made right by widening its table.
//
// A hint now declares itself (`ui/parts/KeyHint.qml`'s `isKeyHint`) and the
// walk asks the component. The question the old grammar was really asking --
// may a printed key be written as a plain string at all -- is answered on the
// SOURCE by `src/tools/check-keyhints.ts`, inside `npm run check`. Nothing at
// runtime reads a label any more.
//
// What is left is the key column, which was never about appearance: it is a
// list of key names, and every one of them has to be a key this game can press.

// Every key name `dev/Pointer.qml` can post through the harness, by the name a
// `Clickable.key` column or a printed hint uses for it.
var KEY_WORDS = {
  "tab": true, "backtab": true, "up": true, "down": true, "left": true,
  "right": true, "enter": true, "return": true, "space": true, "esc": true,
  "escape": true, "backspace": true, "shift": true
}

/** Every key name in a `Clickable.key` column, split on the words that join them. */
function keyNames(spec) {
  var flat = String(spec).toLowerCase()
                         .replace(/[,\/]/g, " ")
                         .replace(/\bthen\b/g, " ")
                         .replace(/\bor\b/g, " ")
                         .replace(/\band\b/g, " ")
                         .replace(/⏎/g, " enter ")
                         .replace(/⌫/g, " backspace ")
                         .replace(/◀/g, " left ").replace(/▶/g, " right ")
                         .replace(/↑/g, " up ").replace(/↓/g, " down ")
  var parts = flat.split(/\s+/)
  var names = []
  for (var i = 0; i < parts.length; i++)
    if (parts[i].length > 0)
      names.push(parts[i])
  return names
}

/**
 * Can every key this string names actually be pressed? A single letter or digit
 * is a key; so is every name in KEY_WORDS. Nothing else is, which is what makes
 * this a check rather than a count.
 */
function pressable(spec) {
  var names = keyNames(spec)
  if (names.length === 0)
    return false
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    if (KEY_WORDS[name] === true)
      continue
    if (name.length === 1 && ((name >= "a" && name <= "z")
                              || (name >= "0" && name <= "9")))
      continue
    return false
  }
  return true
}
