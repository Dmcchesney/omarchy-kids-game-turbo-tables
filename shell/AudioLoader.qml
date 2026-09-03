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
// `bankSource` is empty, so no bank is loaded and the game is silent. That is
// not a placeholder standing in for work: `assets/sfx/` holds no sounds yet.
// The eight card sounds and the engine loop are M6, and the component that
// plays them -- `shell/SoundBank.qml`, a `SoundEffect` per sound behind
// `import QtMultimedia` -- lands in the same commit as the WAV files it plays,
// because that is the commit where README.md's Dependencies section stops
// saying there is no audio and starts describing this path. Setting
// `bankSource` to that file is the whole of the wiring; nothing else here
// changes.
//
// Until then the loader is exercised in exactly the state it ships in, and its
// failure branch is exercised too: point `bankSource` at a component that
// cannot load and `available` goes false, `unavailableReason` says why, and
// `play()` keeps answering false.
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

  // The component that actually makes noise. Empty means "no sound bank is
  // installed", which is not an error and logs nothing.
  property url bankSource: ""

  // True only when a bank loaded and offers the interface this file expects.
  // Untyped on purpose: what a sound bank is, is whatever component
  // `bankSource` names, and this file's whole job is to work when that is
  // nothing at all.
  readonly property var bankItem: bank.item

  readonly property bool available: bank.status === Loader.Ready
                                    && bankItem !== null
                                    && typeof bankItem.play === "function"

  // Why sound is silent, in one line, for a parent reading a log. Empty when
  // sound is working.
  readonly property string unavailableReason: {
    if (String(bankSource).length === 0)
      return "no sound bank is installed"
    if (bank.status === Loader.Error)
      return "the sound bank at " + bankSource + " could not be loaded"
    if (bank.status === Loader.Loading)
      return "the sound bank is still loading"
    if (bank.status === Loader.Ready && !available)
      return "the sound bank loaded but does not offer play()"
    return available ? "" : "sound is unavailable"
  }

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
    active: String(audio.bankSource).length > 0
    source: audio.bankSource
    asynchronous: true

    onStatusChanged: {
      if (status === Loader.Error)
        console.warn("TurboTables AudioLoader: sound is off -- " + audio.unavailableReason)
    }

    onLoaded: {
      if (item && "volume" in item)
        item.volume = Qt.binding(function () { return audio.volume })
    }
  }

  // Sound stops with the overlay, not a moment later.
  onEnabledChanged: if (!enabled) stopAll()
  Component.onDestruction: stopAll()
}
