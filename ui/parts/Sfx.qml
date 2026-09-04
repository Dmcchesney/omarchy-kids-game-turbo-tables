pragma Singleton
import QtQuick
import "../"

// The sound cues, and the one seam a sound is played through.
//
// PIECE F. `docs/design.md` v4's "Power-up feel" gives every card a Sound row --
// "short whoosh, four rising ticks", "spool up, bang, sustained rush", "four
// metallic clicks" -- and `src/tools/bake-sfx.py` synthesises one PCM WAV per
// row under `assets/sfx/`. This file is the table that says which cue belongs
// to which event, and the single function the game calls to play one.
//
// ---------------------------------------------------------------------------
// WHAT IS HERE, AND WHAT IS DELIBERATELY NOT
// ---------------------------------------------------------------------------
//
// What is here: the cue table, the URL for each cue, the `sound` setting's
// gate, a re-trigger guard, and a log of what was asked for. Every effect in
// `ui/TrackView.qml` and `ui/Race.qml` calls `Sfx.play(cue)` on the beat the
// design puts the sound on, and `tests/qml/tst_sfx.qml` asserts the right cue
// fires on the right event -- so the WIRING is built and proved.
//
// What is NOT here: a `SoundEffect`, a `MediaPlayer`, or an `import QtMultimedia`.
// `voice` is the seam a host plugs a player into, and it is null, so the game
// is silent. Three reasons, all of which outrank "the piece would look more
// finished with it":
//
//   1. `docs/plan.md` v3 assigns the multimedia component to piece 6, at M6':
//      "the eight card sounds and engine loop behind `AudioLoader`, with the
//      README's audio sentences moved to present tense IN THE SAME COMMIT as
//      the `SoundEffect` lands, or the gate fails."
//   2. `npm run check:readme` enforces exactly that, and it is not a formality:
//      a multimedia token anywhere in the plugin makes README.md's "There is no
//      sound yet" and "no audio loader has been built" stale denials, and the
//      gate fails the build. Landing the token here without rewriting those
//      sentences would break `npm run check`; rewriting them is piece 6's job
//      and would put a present-tense audio claim in the README.
//   3. NOBODY IN THIS BUILD LOOP CAN HEAR. Wiring an unheard sound into the
//      shipping game and then telling a parent in the README that the game
//      plays sounds is precisely the kind of claim this project has been caught
//      making before. The files, the bake and the routing are reviewable as
//      text and provable by test; the sound itself is not, and it waits for
//      somebody with ears.
//
// A host that HAS an audio backend assigns `Sfx.voice` an object with a
// `play(url)` method, and every cue below starts working with no other change.
// With `voice` null the game plays exactly as it does today, silently, which is
// also the fallback a machine without Qt Multimedia gets.
QtObject {
  id: sfx

  // -------------------------------------------------------------- the table
  //
  // Cue name -> the file `src/tools/bake-sfx.py` writes for it. The names are
  // the script's own catalogue, and `npm run check:sfx` reads BOTH this table
  // and that catalogue and fails if either has a cue the other does not -- so
  // "a sound for every event" is a gate rather than a sentence in a report.
  //
  // The comment beside each is the design's own words for that beat.
  readonly property var cues: ({
    "nitro":         "nitro",          // short whoosh, four rising ticks
    "turbo":         "turbo",          // spool up, bang, sustained rush
    "oilslick":      "oilslick",       // splat
    "squeal":        "squeal",         // one of three, staggered by 120
    "wrench-flight": "wrench-flight",  // whirr in flight
    "wrench-clang":  "wrench-clang",   // clang on impact
    "pothole":       "pothole",        // thud, rattle
    "hubcap":        "hubcap",         // hubcap ring
    "pileup":        "pileup",         // siren blip, crash with debris, a long hiss
    "rollcage":      "rollcage",       // four metallic clicks
    "block":         "block",          // the clang when it earns its keep
    "towhook":       "towhook",        // winch, whip-crack, the doppler past
    "hit":           "hit",            // the crunch under the engine-hit banner
    "deal":          "deal",           // three cards dealt
    "slam":          "slam"            // the chosen card slams down
  })

  // The seam. Null in the shipping plugin; a host with an audio backend assigns
  // an object with `play(url)`. Nothing else in the game touches it.
  property var voice: null

  // What was last asked for, and the whole list since `clearLog()`. The log is
  // how `tests/qml/tst_sfx.qml` proves an event reaches the right cue: a test
  // cannot listen, so what it can check is that the call was made, once, on the
  // beat the design puts it on.
  property string lastCue: ""
  property var log: []
  property bool logging: false

  function clearLog() {
    sfx.log = []
    sfx.lastCue = ""
  }

  function url(cue) {
    return sfx.cues.hasOwnProperty(cue) ? (Theme.sfxRoot + sfx.cues[cue] + ".wav") : ""
  }

  // The one call. An unknown cue is dropped rather than played as silence, so a
  // typo in a call site is findable: `lastCue` does not change and the test
  // that names that cue fails.
  function play(cue) {
    if (!sfx.cues.hasOwnProperty(cue))
      return false
    if (sfx.logging) {
      var next = sfx.log.slice()
      next.push(cue)
      sfx.log = next
    }
    sfx.lastCue = cue
    // The `sound` setting is the design's Data row and it gates the seam, not
    // the bookkeeping above: a test can still see that the right cue fired with
    // the sound turned off, which is what makes the wiring checkable either way.
    if (Store.setting("sound") === false)
      return false
    if (sfx.voice && typeof sfx.voice.play === "function")
      sfx.voice.play(sfx.url(cue))
    return true
  }
}
