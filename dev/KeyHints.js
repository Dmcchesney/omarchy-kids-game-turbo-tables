.pragma library

// PIECE M ROUND 2. THE GRAMMAR OF A PRINTED KEY, IN ONE PLACE.
//
// This game prints its keyboard on the screen -- `ESC  LEAVE`, `H  PIT CREW`,
// `⏎  USE IT      ESC  BACK`, and a keycap beside a word in the title band --
// and round one made some of those lines clickable and left others as paint. A
// critic found the consequence: the picker's `ESC  BACK` and the confirm
// sheet's `ESC  KEEP` were dead, and round one's gate could not see either,
// because both oracles it had can only find items that DECLARE themselves --
// an `Accessible.role`, or a place in a screen's `stops` array -- and a label
// declares nothing.
//
// So the third oracle reads the STRINGS. This file is what it reads them with,
// and it is a library rather than a method on the harness so that the harness's
// walk and `tests/qml/tst_mouse_parity.qml` ask the same question in the same
// words. Two copies of a grammar is one copy that drifts.
//
// It is also the check on the parity table's `key` column. Round one's gate
// asked only that the column was non-empty -- `key: "banana"` passed -- and it
// is the whole claim of the click -> key direction. `pressable` parses it
// against the very key table `--do key:<name>` posts events from.

// Every key name `dev/Pointer.qml` can post through the harness, by the name a
// `Clickable.key` column or a printed hint uses for it.
var KEY_WORDS = {
  "tab": true, "backtab": true, "up": true, "down": true, "left": true,
  "right": true, "enter": true, "return": true, "space": true, "esc": true,
  "escape": true, "backspace": true, "shift": true
}

// The same keys as they are PRINTED, glyphs included.
var KEYCAP_WORDS = {
  "esc": true, "escape": true, "enter": true, "return": true, "tab": true,
  "space": true, "backspace": true, "shift": true, "⏎": true, "⌫": true,
  "◀": true, "▶": true, "↑": true, "↓": true
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

/**
 * Is every word of this string a key name a child could press?
 *
 * `allowDigits` is false for a keycap standing on its own, because a lap
 * number, a place and a typed answer are all bare digits and none of them is a
 * promise about a key. Inside a hint line -- a group of keys followed by a
 * group that says what they do -- a digit IS a key, which is how
 * `1 2 3  CHOOSE A CARD` is read.
 */
function isKeycap(text, allowDigits) {
  var raw = String(text).trim()
  if (raw.length === 0 || raw.length > 12)
    return false
  var parts = raw.toLowerCase().split(/\s+/)
  var letters = 0
  for (var i = 0; i < parts.length; i++) {
    if (KEYCAP_WORDS[parts[i]] === true)
      continue
    if (allowDigits === true && parts[i].length === 1
        && parts[i] >= "0" && parts[i] <= "9")
      continue
    // A single letter is a key -- `S` on the garage door, `H` in the race --
    // but a single letter ALONE is also half the alphabet, so it only counts as
    // a keycap when something else in the string is a key name too, or when the
    // item beside it says what it does. The caller checks the second case.
    if (parts[i].length === 1 && parts[i] >= "a" && parts[i] <= "z") {
      letters += 1
      continue
    }
    return false
  }
  return parts.length > letters || letters === 1
}

/**
 * `ESC  BACK`: a group of key names, two or more spaces, and then a group that
 * is not. Two spaces is this game's own hint grammar and every screen prints it
 * that way; the wide gaps between groups on one line are the same separator.
 */
function isHintLine(text) {
  var raw = String(text)
  if (raw.indexOf("  ") < 0)
    return false
  var groups = raw.split(/\s{2,}|\n/)
  for (var i = 0; i < groups.length; i++) {
    var group = groups[i].trim()
    if (group.length === 0)
      continue
    if (!isKeycap(group, true))
      continue
    for (var j = i + 1; j < groups.length; j++) {
      var after = groups[j].trim()
      if (after.length === 0)
        continue
      if (!isKeycap(after, true))
        return true
      break
    }
  }
  return false
}
