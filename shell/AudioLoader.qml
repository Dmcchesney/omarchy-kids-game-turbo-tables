import QtQuick

// Sound, behind a loader, with silence as the failure mode.
//
// The design lists Qt Multimedia as an *optional* dependency: a machine
// without it must still run the game, and a child must never meet a QML error
// where a card sound should have been. So the multimedia types never appear in
// a file the overlay imports directly -- an unresolved import fails the whole
// component that carries it, which would take the overlay down with it. They
// live in a separate component this `Loader` pulls in at runtime, and if that
// component cannot load for any reason -- Qt Multimedia missing, no audio
// device, a broken WAV -- the loader stays empty and every call below returns
// false and does nothing.
//
// That silent state is not a stub object off to one side. It is this file: the
// interface a caller uses is `play`, `stop`, `stopAll`, `available` and
// `enabled`, and those five behave identically whether the bank loaded or not.
// A caller cannot tell, and never has to ask.
//
// ---------------------------------------------------------------------------
// WHAT IS HERE TODAY, PLAINLY
// ---------------------------------------------------------------------------
//
// PIECE 6, M6'. The `Loader` below names `shell/SoundBank.qml`, which is a
// `SoundEffect` per sound behind `import QtMultimedia`, and the fifteen cues
// of `assets/sfx/` play through it. That import is the whole reason for the
// loader: it is the only one in the tree, it lives in the one component
// nothing imports directly, and on a machine without Qt Multimedia it takes
// that component down and nothing else. The loader then reports `Loader.Error`,
// `available` is false, `unavailableReason` says so in one line, `play()`
// answers false, and the game runs silently -- which is the design's stated
// requirement that Qt Multimedia be an OPTIONAL dependency.
//
// NOBODY HAS LISTENED TO ANY OF IT. What is proved about this path is that Qt
// loads each WAV, reports it Ready, and reports `playing` when asked to play;
// that the right cue reaches it on the right event; and that switching sound
// off in Settings stops it. Whether any of it sounds right is the maintainer's
// to judge, and he has not judged it yet.
//
// HOW THE FAILURE BRANCH IS EXERCISED, since the bank is named literally and
// so cannot be pointed at a broken component from a test. Two ways, and
// together they cover it:
//
//   * `bankWanted: false` -- no bank is built, `available` is false, and every
//     function below takes exactly the same branch it takes on a machine with
//     no Qt Multimedia. `tests/qml/tst_sfx.qml` walks that.
//   * a copy of THIS FILE, byte for byte, placed beside a copy of
//     `shell/SoundBank.qml` whose only difference is that its import names a
//     module that is not installed. `source: "SoundBank.qml"` is relative to
//     the loader's own directory, so the copy loads the broken bank, and the
//     real `Loader.Error` path runs. Qt 6 resolves an installed library import
//     ahead of every import path, so on a machine that HAS Qt Multimedia this
//     is the only way to see that path at all; the evidence for piece 6 has the
//     run and the SHA-256 that says the copy is this file.
//
// ---------------------------------------------------------------------------
//
// A `QtObject` rather than an `Item`, and the `Loader` hangs off a property
// rather than off a scene. Sound is not a thing on screen, an `Item` here would
// shadow `QQuickItem.enabled` with the child's own sound switch, and a `Loader`
// loads its component whether or not it has a visual parent.
QtObject {
  id: audio

  // The child's own switch, off the settings screen. Sound that is switched
  // off is silent even when the bank loaded perfectly.
  property bool enabled: true

  // 0 to 1, handed to the bank if there is one.
  property real volume: 1.0

  // Whether to load the bank at all. False means "no sound bank is installed",
  // which is not an error and logs nothing: the game is silent, every function
  // below answers false, and no multimedia component is ever built.
  //
  // This used to be `bankSource`, a settable `url`, and the file it names used
  // to be an expression on the `Loader` below. `npm run check:readme` refused
  // it, and it was right to: "whatever it names is loaded and run; name it
  // literally". A plugin that runs unsandboxed in a child's session and loads
  // exactly one component should say which one in the source, not in a property
  // any later piece could point somewhere else. The bank is now named literally
  // at the `Loader`, and what is left settable is the only thing a caller
  // actually needs, which is whether to have sound.
  property bool bankWanted: true

  // What the bank should hold ready. Handed straight to the bank if it has
  // somewhere to put it. This file does not know what a sound is called: the
  // cue table lives in `ui/parts/Sfx.qml` and `TurboTables.qml` passes its
  // derived URL list through here, so the table is written down once.
  property var sources: []

  // True only when a bank loaded and offers the interface this file expects.
  // Untyped on purpose: what a sound bank is, is whatever the component below
  // turns out to be, and this file's whole job is to work when that is nothing
  // at all.
  readonly property var bankItem: bank.item

  readonly property bool available: bank.status === Loader.Ready
                                    && bankItem !== null
                                    && typeof bankItem.play === "function"

  // Why sound is silent, in one line, for a parent reading a log. Empty when
  // sound is working.
  //
  // Written as a function of a status rather than as a binding that reads one,
  // because the log line below needs the reason for the status it is HANDLING:
  // `onStatusChanged` runs before the binding that reads `bank.status` is
  // re-evaluated, so the warning printed on a load failure used to read "the
  // sound bank is still loading" -- the previous status, in the one line a
  // parent would ever see about sound.
  function reasonFor(status) {
    if (!audio.bankWanted)
      return "no sound bank is installed"
    if (status === Loader.Error)
      return "the sound bank could not be loaded; Qt Multimedia is probably not installed"
    if (status === Loader.Loading)
      return "the sound bank is still loading"
    if (status === Loader.Ready && !audio.available)
      return "the sound bank loaded but does not offer play()"
    return audio.available ? "" : "sound is unavailable"
  }

  readonly property string unavailableReason: audio.reasonFor(bank.status)

  // --------------------------------------------------------------- interface
  //
  // Identical in both states. Each answers whether a sound was actually
  // started, so a caller that cares can tell -- and no caller has to.
  function play(name) {
    if (!enabled || !available)
      return false
    return bankItem.play(String(name)) === true
  }

  function stop(name) {
    if (!available)
      return false
    if (typeof bankItem.stop !== "function")
      return false
    return bankItem.stop(String(name)) === true
  }

  function stopAll() {
    if (!available)
      return false
    if (typeof bankItem.stopAll !== "function")
      return false
    return bankItem.stopAll() === true
  }

  property Loader bank: Loader {
    active: audio.bankWanted
    // Named literally, and this is the whole of the optional-dependency
    // mechanism: `shell/SoundBank.qml` is the only file in the repository that
    // imports Qt Multimedia, an unresolvable import fails the component that
    // carries it and nothing else, and a `Loader` reports that as
    // `Loader.Error` rather than taking its caller down.
    source: "SoundBank.qml"
    asynchronous: true

    onStatusChanged: {
      if (status === Loader.Error)
        console.warn("TurboTables AudioLoader: sound is off -- " + audio.reasonFor(status))
    }

    onLoaded: {
      if (item && "volume" in item)
        item.volume = Qt.binding(function () { return audio.volume })
      if (item && "sources" in item)
        item.sources = Qt.binding(function () { return audio.sources })
    }
  }

  // Sound stops with the overlay, not a moment later.
  onEnabledChanged: if (!enabled) stopAll()
  Component.onDestruction: stopAll()
}
