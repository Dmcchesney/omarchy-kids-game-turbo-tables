import QtQml
import QtQuick
import QtMultimedia

// The one file in this plugin that makes a noise, and the only file anywhere
// in the tree that imports Qt Multimedia.
//
// PIECE 6, M6'. `shell/AudioLoader.qml` has always been the loader; this is
// the bank it loads. Everything about the split is in that file's header, and
// the short version is the reason this file exists at all: an unresolved
// `import` fails the WHOLE component that carries it, so a machine without Qt
// Multimedia would lose whichever file held the import. Holding it here, and
// reaching it only through a `Loader`, means the failure is confined to this
// one component. The loader sees `Loader.Error`, `available` goes false, and
// the game plays on in silence with no error a child can meet.
//
// ---------------------------------------------------------------------------
// WHAT A "SOUND" IS TO THIS FILE
// ---------------------------------------------------------------------------
//
// A URL, and nothing else. This file holds no cue names, no table and no
// knowledge of what any of these WAVs is for. `ui/parts/Sfx.qml` owns the cue
// table, derives one URL per cue from it, and that list arrives here as
// `sources`; `play(source)` is handed one of those URLs back. So the cue table
// is written down once, in one file, and `npm run check:sfx` holds it to the
// bake catalogue and to the files on disk. A second list here is a list that
// could drift, so there is not one.
//
// ---------------------------------------------------------------------------
// WHY THERE ARE THREE VOICES PER SOUND
// ---------------------------------------------------------------------------
//
// `SoundEffect.play()` on an effect that is already playing RESTARTS it; it
// does not layer. Design v4's Oil Slick is "splat, then three squeals
// staggered by 120", and `ui/TrackView.qml` duly asks for `squeal` three times
// 120 ms apart -- which, through one effect, is one squeal restarted twice.
// Three effects per source, handed out round-robin, let a cue overlap itself
// as many times as any cue in the design's Sound rows asks for.
//
// It is cheap. Qt decodes a WAV once per URL into `QSampleCache` and every
// `SoundEffect` naming that URL shares that sample, so the voices cost objects
// and not audio. The 15 committed cues are 418,410 bytes on disk: 9.473
// seconds of 22.05 kHz mono 16-bit PCM in total, so a decoded copy of the
// whole bank is under half a megabyte before Qt resamples it to the device.
//
// ---------------------------------------------------------------------------
// WHAT NOBODY HAS DONE, STATED HERE AND NOT ONLY IN A REPORT
// ---------------------------------------------------------------------------
//
// NOBODY HAS LISTENED TO ANY OF THIS. Not one of the fifteen WAVs has been
// heard by anyone in the build loop, and no test in this repository can hear
// one. What is checked is format, length, byte hash, routing, and that Qt
// reports each effect Ready and reports `playing` true when it is asked to
// play. Whether a file sounds like a clang, a whoosh or a siren -- and whether
// three voices is the right number, or a mercy -- is the maintainer's ears'
// to decide, and until he has used them this file's claim is only that a
// sound was started.
QtObject {
  id: bank

  // The WAVs to hold ready, as URLs. Assigned by `shell/AudioLoader.qml` from
  // whatever it was given; in the shipping plugin that is `Sfx.sources`.
  property var sources: []

  // 0 to 1, driven by the loader, which drives it from the overlay.
  property real volume: 1.0

  // How many times one cue may overlap itself. Three is the largest number the
  // design's Sound rows ask for (Oil Slick's three squeals).
  readonly property int voices: 3

  // `sources` x `voices`, flattened: voice v of source i sits at
  // `i * voices + v`. A flat model because `Instantiator` takes one.
  readonly property var voiceSources: {
    var flat = []
    for (var i = 0; i < bank.sources.length; i++)
      for (var v = 0; v < bank.voices; v++)
        flat.push(String(bank.sources[i]))
    return flat
  }

  // URL -> its index in `sources`, so `play()` is a lookup rather than a scan.
  readonly property var indexBySource: {
    var map = ({})
    for (var i = 0; i < bank.sources.length; i++)
      map[String(bank.sources[i])] = i
    return map
  }

  // Whose turn it is, per source. Rebuilt when `sources` moves and then
  // written in place: `play()` runs on a game event, and a fresh array per
  // call would be an allocation on a path the child triggers.
  property var voiceTurn: []

  onSourcesChanged: {
    var turns = []
    for (var i = 0; i < bank.sources.length; i++)
      turns.push(0)
    bank.voiceTurn = turns
  }

  // Declared, not constructed: `Qt.createQmlObject` and `Qt.createComponent`
  // are both on this repository's dynamic-code-construction list and
  // `npm run check:readme` fails on either in any plugin file.
  property Instantiator pool: Instantiator {
    model: bank.voiceSources
    delegate: SoundEffect {
      required property string modelData
      source: modelData
      volume: bank.volume
    }
  }

  // --------------------------------------------------------------- interface
  //
  // The three functions `shell/AudioLoader.qml` looks for, each answering
  // whether it did something.

  /** Start `source`, on the next free-ish voice. False when this bank does not
      hold that URL, or when Qt could not load it. */
  function play(source) {
    var key = String(source)
    if (!bank.indexBySource.hasOwnProperty(key))
      return false
    var at = bank.indexBySource[key]
    var turn = (at < bank.voiceTurn.length) ? bank.voiceTurn[at] : 0
    var effect = bank.pool.objectAt(at * bank.voices + turn)
    if (!effect)
      return false
    if (at < bank.voiceTurn.length)
      bank.voiceTurn[at] = (turn + 1) % bank.voices
    if (effect.status === SoundEffect.Error)
      return false
    effect.play()
    return true
  }

  /** Silence every voice of one source. */
  function stop(source) {
    var key = String(source)
    if (!bank.indexBySource.hasOwnProperty(key))
      return false
    var at = bank.indexBySource[key]
    for (var v = 0; v < bank.voices; v++) {
      var effect = bank.pool.objectAt(at * bank.voices + v)
      if (effect)
        effect.stop()
    }
    return true
  }

  /** Silence everything. The overlay closing, or sound being switched off. */
  function stopAll() {
    for (var i = 0; i < bank.pool.count; i++) {
      var effect = bank.pool.objectAt(i)
      if (effect)
        effect.stop()
    }
    return true
  }

  /** How many voices Qt has loaded and would play. Nothing in the game reads
      this; `tests/qml/tst_sfx.qml` does, because "the bank is ready" is one of
      the few things about sound that can be asserted without ears. */
  function readyVoices() {
    var ready = 0
    for (var i = 0; i < bank.pool.count; i++) {
      var effect = bank.pool.objectAt(i)
      if (effect && effect.status === SoundEffect.Ready)
        ready += 1
    }
    return ready
  }

  /** How many voices Qt says are sounding right now. The same test reads this,
      and it is as close to hearing as anything here gets: `play()` returning
      true says the call was made, and this says Qt started the sound. It still
      says nothing whatever about what came out. */
  function playingVoices() {
    var playing = 0
    for (var i = 0; i < bank.pool.count; i++) {
      var effect = bank.pool.objectAt(i)
      if (effect && effect.playing)
        playing += 1
    }
    return playing
  }
}
