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
// gate, and a log of what was asked for. Every effect in `ui/TrackView.qml`,
// `ui/Race.qml` and `ui/Picker.qml` calls `Sfx.play(cue)` on the beat the
// design puts the sound on, and `tests/qml/tst_sfx.qml` and
// `tests/qml/tst_trackview_fx.qml` assert the right cue fires on the right
// event -- so the WIRING is proved by test rather than by assertion.
//
// What is NOT here, and deliberately: a `SoundEffect`, a `MediaPlayer`, or an
// `import QtMultimedia`. `voice` is the seam, and in the shipping plugin
// `TurboTables.qml` fills it with `shell/AudioLoader.qml`, whose bank
// (`shell/SoundBank.qml`) holds the only multimedia import in the tree. That
// split is the design's "Qt Multimedia behind a loader, so a machine without it
// gets a silent game rather than a broken one": an unresolved import fails the
// whole component carrying it, so it is kept in the one component nothing
// imports directly. If it fails, `voice.play()` answers false and everything
// on this side of the seam carries on unchanged.
//
// With `voice` null -- the harness, the tests, a host with no audio -- the game
// plays exactly as it always has, silently, and the cue log still records what
// was asked for. That is what makes the routing checkable without ears.
//
// AND NOBODY HAS USED ANY EARS. Not one of the fifteen WAVs has been heard by
// anybody in the build loop, and nothing in this repository can hear one. Every
// claim made about sound here is about format, length, hash, routing and
// whether Qt reports a sound started. Whether these files sound like a clang, a
// whoosh or a siren is the maintainer's to judge and he has not judged it yet.
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

  // Every cue's URL, in one list, derived from the table above so the table
  // stays the only place a cue is written down. `TurboTables.qml` hands this to
  // `shell/AudioLoader.qml`, which hands it to the bank, which loads one
  // `SoundEffect` per entry. A second list of file names anywhere else is a
  // list that could drift from this one, so there is not one.
  readonly property var sources: {
    var list = []
    for (var cue in sfx.cues)
      list.push(sfx.url(cue))
    return list
  }

  // The seam. Null until something fills it -- which the harness and the tests
  // never do, and `TurboTables.qml` always does, with `shell/AudioLoader.qml`.
  // Whatever is here offers `play(url)`. Nothing else in the game touches it.
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
