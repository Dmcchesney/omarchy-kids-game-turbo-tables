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

// ===========================================================================
// ROUND 4 -- A NET UNDER THE STRUCTURAL RULE, AND IT NEVER GUESSES AT A DIGIT.
// ===========================================================================
//
// Round three moved the whole question to `isKeyHint`: a hint is a hint because
// the component says so. That is right, and it leaves one hole that a critic
// walked straight through. They wrote four printed key hints into a screen by
// hand; three were invisible to BOTH gates and the fourth was caught only until
// it was wrapped in a `Repeater`:
//
//   text: keys + "  " + action        assembled at runtime -- no literal
//   keycap + word in a Repeater       the literal moved into the model
//   Canvas.fillText("SPACE  FIRE …")  not a `text:` binding at all
//   text: someProperty                a binding, not a string
//
// A SOURCE check cannot see three of those, because two thirds of the strings
// this game draws are assembled at runtime. A RUNTIME check can see all four,
// because by then they are words on the screen -- which is what round two did,
// and round two's rule was wrong in both directions.
//
// WHY THIS ONE IS NOT THAT ONE. Every false positive the critic listed against
// round two's rule was a BARE DIGIT: `3  CORRECT`, `7  LAPS`, `5  IN A ROW`,
// `2  TO GO`, `9  BEST TIME`. A lap number, a place, a streak and a typed answer
// are all bare digits, and a maths racing game prints digits beside words on
// every screen it has. So this rule never reads one digit as a key. What it
// reads is:
//
//   a HARD key word or glyph -- `ESC`, `ENTER`, `TAB`, `⏎`, `⌫`, `◀ ▶` -- next
//   to words that say what it does. `SPACE`, `RETURN`, `LEFT`, `HOME`, `END`,
//   `UP` and `DOWN` are deliberately NOT hard: they are ordinary English, and
//   `TIME LEFT` is not a promise about a key. The source check still reads
//   those, where a false positive costs a rename rather than a red gate on a
//   shipped screen.
//
//   a SINGLE LETTER separated by the game's own hint grammar -- two spaces or a
//   newline -- from at least one word of three letters or more: `H  PIT CREW`,
//   `S  SETTINGS AND RESETS`, and the critic's own `P  PAUSE` and
//   `H  SHOW ME THE ANSWER`. One space is not enough for a letter, because
//   `A LAP` would be.
//
//   a RUN of two or more single digits -- `1 2 3  CHOOSE A CARD` -- which is
//   this game's card-key idiom and which no scoreboard prints.
//
// It is a net, not the rule. The rule is `isKeyHint`; this catches the hand-
// drawn ones the rule cannot see, and the one thing in the game that prints keys
// and is deliberately not a control declares itself (`ui/parts/KeyLegend.qml`)
// rather than being guessed about.

var HARD_KEY_WORDS = {
  "esc": true, "escape": true, "enter": true, "tab": true, "backtab": true,
  "backspace": true, "shift": true, "ctrl": true, "alt": true, "cmd": true,
  "pgup": true, "pgdn": true, "pageup": true, "pagedown": true,
  "f1": true, "f2": true, "f3": true, "f4": true, "f5": true, "f6": true,
  "f7": true, "f8": true, "f9": true, "f10": true, "f11": true, "f12": true
}

var KEYCAP_GLYPHS = /[⏎↵⌫⎋⇧⇥␣⌥⌘⌃↑↓←→◀▶]/g

function wordsOf(group) {
  var parts = String(group).trim().split(/\s+/)
  var out = []
  for (var i = 0; i < parts.length; i++)
    if (parts[i].length > 0)
      out.push(parts[i])
  return out
}

/** A key nobody could mistake for an English word: a hard name, or a glyph. */
function isHardKeyToken(token) {
  var bare = String(token).toLowerCase().replace(KEYCAP_GLYPHS, "")
  if (bare.length === 0)
    return true
  return HARD_KEY_WORDS[bare] === true
}

/** Every token is a hard key, or the group is a run of two or more digits. */
function isHardKeyGroup(group) {
  var parts = wordsOf(group)
  if (parts.length === 0)
    return false
  var digits = 0
  for (var i = 0; i < parts.length; i++)
    if (parts[i].length === 1 && parts[i] >= "0" && parts[i] <= "9")
      digits += 1
  if (digits === parts.length)
    return parts.length >= 2
  for (var j = 0; j < parts.length; j++) {
    var part = parts[j]
    var isDigit = part.length === 1 && part >= "0" && part <= "9"
    if (!isHardKeyToken(part) && !isDigit)
      return false
  }
  return true
}

/** Does this group say what a key DOES -- a word, not another key? */
function isActionWords(group) {
  var parts = wordsOf(group)
  if (parts.length === 0 || isHardKeyGroup(group))
    return false
  for (var i = 0; i < parts.length; i++)
    if (parts[i].length >= 3 && !isHardKeyToken(parts[i]))
      return true
  return false
}

function isSingleLetter(group) {
  var parts = wordsOf(group)
  return parts.length === 1 && parts[0].length === 1
         && parts[0].toLowerCase() >= "a" && parts[0].toLowerCase() <= "z"
}

/**
 * Does this rendered string promise that pressing a key does something?
 *
 * Never true of one bare digit beside a word. See the block above.
 */
function looksLikePrintedKey(text) {
  var raw = String(text)
  if (raw.trim().length === 0)
    return false

  // The game's own hint grammar: two or more spaces, a newline, a pipe, or the
  // mid-dot the screens join clauses with.
  var wide = raw.split(/\s{2,}|\n|\s*[|│]\s*|\s+·\s+/)
  var groups = []
  for (var i = 0; i < wide.length; i++)
    if (wide[i].trim().length > 0)
      groups.push(wide[i].trim())

  for (var g = 0; g + 1 < groups.length; g++) {
    var a = groups[g]
    var b = groups[g + 1]
    if ((isHardKeyGroup(a) || isSingleLetter(a)) && isActionWords(b))
      return true
    if ((isHardKeyGroup(b) || isSingleLetter(b)) && isActionWords(a))
      return true
  }

  // One group, single spaces: a HARD key only. `ESC BACK` is a promise;
  // `A LAP` and `TIME LEFT` are not, which is why a single letter and the soft
  // key words never reach here.
  if (groups.length === 1) {
    var parts = wordsOf(groups[0])
    if (parts.length >= 2) {
      if (isHardKeyToken(parts[0]) && isActionWords(parts.slice(1).join(" ")))
        return true
      if (isHardKeyToken(parts[parts.length - 1])
          && isActionWords(parts.slice(0, parts.length - 1).join(" ")))
        return true
    }
  }
  return false
}
