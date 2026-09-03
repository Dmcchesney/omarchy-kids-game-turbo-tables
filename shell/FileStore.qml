import QtQuick
import Quickshell
import Quickshell.Io

// The one file this plugin owns, and the only code in the repository that
// touches a disk.
//
//   ${XDG_DATA_HOME:-~/.local/share}/turbo-tables-solo/garage.json
//
// It is the backend `ui/Store` is handed at startup. Store decides what a save
// file may contain; this file decides nothing about content and everything
// about whether a byte on disk may be replaced.
//
// ---------------------------------------------------------------------------
// THE RULE THIS FILE EXISTS FOR
// ---------------------------------------------------------------------------
//
// The save layer has been destroyed three times by the same mistake, each time
// through a different door: **inferring "there is no file" from "I could not
// find out"**. A read that threw, a backend that could not be called, a load
// that returned undefined -- each was read as "fresh install", the defaults
// were adopted, and the child's next keystroke wrote 242 bytes over a real
// save holding a record and twelve facts.
//
// So `load()` here answers with exactly three outcomes and there is no fourth:
//
//   the file's text     the read succeeded. FileView said `loaded`.
//   null                the file is genuinely not there. FileView said
//                       `loadFailed(FileNotFound)` and nothing else.
//   a thrown Error      everything else, including silence.
//
// "Including silence" is the whole point. A permissions error, a path that is
// a directory, an unknown I/O failure, or a read that produced no verdict at
// all are all the same answer -- *I do not know what is on disk* -- and that
// answer is a throw, never a null. Store turns the throw into a quarantine:
// the file is left exactly as it is, the session runs from memory, and every
// write is refused until somebody decides what to do about it.
//
// Measured against Quickshell 0.3.1 in the Omarchy VM rather than assumed
// (evidence: piece7-ours.md, "FileView, measured"):
//
//   missing file   text() == ""        loadFailed(FileNotFound=2)   loaded=false
//   readable file  text() == contents  loaded()                     loaded=true
//   chmod 000      text() == ""        loadFailed(PermissionDenied) loaded=TRUE
//   a directory    text() == ""        loadFailed(NotAFile)         loaded=TRUE
//
// Note the third and fourth rows. FileView's `loaded` *property* is
// `isLoadedOrAsync` and reads true for a file that could not be read at all, so
// it is not a verdict and this file never consults it. The verdict comes only
// from the `loaded()` and `loadFailed(error)` signals, which -- also measured --
// fire synchronously inside `text()` while `blockLoading` is true.
//
// ---------------------------------------------------------------------------
// WRITING
// ---------------------------------------------------------------------------
//
// `atomicWrites: true`, so a save is a rename over the old file and a crash
// halfway through leaves the previous save intact rather than a truncated one.
// Writes are debounced 400 ms: the garage's steppers fire a save per keypress
// and a child holding an arrow key would otherwise write forty times a second.
// The debounce is flushed explicitly when the overlay closes and when this
// object is destroyed, so a change made a tenth of a second before Escape is
// still on disk.
//
// Three refusals guard the write side, and each is a door the save layer has
// been destroyed through before:
//
//   1. Nothing is ever written before a `load()` has returned an outcome.
//      A hot reload rebuilds this object and re-reads the file; until that read
//      answers, this object has no idea what is on disk and will not write.
//   2. Nothing is written once a read has come back unreadable.
//   3. An empty or blank payload is never written at all.
//
// Directory creation is not a special case: FileView creates missing parents on
// write, measured on the same Quickshell build, so a fresh install needs no
// mkdir and this plugin never has to start anything to make one.
QtObject {
  id: fileStore

  // ------------------------------------------------------------- the path
  //
  // The design's Data row, verbatim, and the only path this plugin knows.
  readonly property string dataHome: {
    var xdg = Quickshell.env("XDG_DATA_HOME")
    if (xdg && xdg.length > 0)
      return xdg
    return Quickshell.env("HOME") + "/.local/share"
  }
  property string path: dataHome + "/turbo-tables-solo/garage.json"

  // ---------------------------------------------------------- the protocol
  //
  // "text"   load() hands back the file's own bytes and save() takes the text
  //          to write. This is the real protocol: the design promises a file a
  //          parent can read, and only the engine's serialiser fixes the key
  //          order and the two-space indent that promise is about.
  //
  // "object" load() hands back a parsed object and save() takes one. The
  //          protocol the development harness speaks.
  //
  // TurboTables.qml sets this from what the Store in the tree can actually
  // read, rather than this file assuming. Handing a text payload to a Store
  // that expects an object is not a harmless mismatch: that Store reads the
  // string as "not an object", adopts the defaults, and writes them over the
  // file on the next keystroke. Whoever wires the two together is the only
  // one who can see both halves, so the decision lives there.
  property string format: "text"

  // ------------------------------------------------------------ the verdict
  //
  // What the last completed read said about the file. Sticky on purpose:
  // FileView serves a cached read when nothing has changed and emits no signal
  // at all in that case (measured), so clearing this before each read would
  // turn a perfectly good second read into "I could not find out".
  //
  //   "unknown"     no read has completed. Nothing may be written.
  //   "present"     the file was read.
  //   "absent"      the file is genuinely not there.
  //   "unreadable"  the file is there and could not be read.
  readonly property string verdict: _verdict
  property string _verdict: "unknown"
  property int _lastError: -1
  property string _lastErrorName: ""

  // False until a read has produced "present" or "absent". Every write is
  // refused while it is false. This is the file-layer half of the guard the
  // design asks for -- "so a hot reload cannot overwrite live state with an
  // empty file" -- and it holds even if the Store above it has been replaced
  // by one that does not keep its own.
  readonly property bool everLoaded: _everLoaded
  property bool _everLoaded: false

  // False once a write has failed. A full disk or a directory the process no
  // longer owns must not be retried on every keystroke for the rest of the
  // session.
  readonly property bool writable: _writable
  property bool _writable: true

  // Raised when a write fails, with the reason in the schema's own prose.
  // TurboTables connects this to the Store's own write-side quarantine; a
  // FileView write is reported by signal rather than by exception, so the
  // Store's `try` around `save()` cannot see it and has to be told.
  signal writeFailed(string reason)

  // Raised after a write actually lands. Nothing needs it yet; the entry-point
  // fixture counts it.
  signal wrote()

  property int debounceMs: 400

  // --------------------------------------------------------------- reading
  //
  // Three outcomes, no fourth. See the header.
  function load() {
    var text = file.text()

    if (_verdict === "present") {
      _everLoaded = true
      if (format === "text")
        return text
      // The object protocol still refuses to guess: a file that does not parse
      // is a throw, which the Store turns into a quarantine, not a null that
      // it would read as "fresh install".
      var parsed = null
      try {
        parsed = JSON.parse(text)
      } catch (error) {
        throw new Error("the save file at " + path + " is not JSON: " + error)
      }
      if (parsed === null || typeof parsed !== "object")
        throw new Error("the save file at " + path + " is not a JSON object")
      return parsed
    }

    if (_verdict === "absent") {
      // The one case that may mean "fresh install", and it is the one case
      // where the operating system said so in as many words.
      _everLoaded = true
      return null
    }

    if (_verdict === "unreadable")
      throw new Error("the save file at " + path + " could not be read: " + _lastErrorName)

    throw new Error("the save file at " + path + " could not be read: the read produced no result")
  }

  // --------------------------------------------------------------- writing
  function save(payload) {
    var text = ""
    if (typeof payload === "string") {
      text = payload
    } else if (payload !== null && payload !== undefined) {
      try {
        text = JSON.stringify(payload, null, 2) + "\n"
      } catch (error) {
        stopWriting("the save could not be encoded: " + error)
        return
      }
    }

    // 3. Nothing blank is ever written. A save that serialised to nothing is a
    //    bug upstream, and writing it would be the exact 242-bytes-of-defaults
    //    failure with the bytes removed.
    if (typeof text !== "string" || text.replace(/\s+/g, "").length === 0) {
      stopWriting("refused to write an empty save file over " + path)
      return
    }

    // 1 and 2. Never before a read has answered, never after it answered
    //          "unreadable".
    if (!_everLoaded) {
      stopWriting("refused to write to " + path + " before the file had been read")
      return
    }
    if (_verdict === "unreadable") {
      stopWriting("refused to write over an unreadable save file at " + path)
      return
    }
    if (!_writable)
      return

    _pending = text
    _hasPending = true
    debounce.restart()
  }

  property string _pending: ""
  property bool _hasPending: false

  // Write whatever is waiting, now. Called when the overlay closes and when
  // this object is destroyed, so the last change before Escape is on disk.
  function flushNow() {
    debounce.stop()
    writeNow()
  }

  function writeNow() {
    if (!_hasPending || !_writable)
      return
    var text = _pending
    _hasPending = false
    _pending = ""

    var failuresBefore = _saveFailures
    var savesBefore = _saves
    file.setText(text)

    // `blockWrites: true`, so both signals have already fired by here
    // (measured: a write into a read-only directory raised saveFailed inside
    // setText). An unchanged file writes nothing and raises neither, which is
    // why only an explicit failure counts as one.
    if (_saveFailures > failuresBefore) {
      stopWriting("the save file at " + path + " could not be written: " + _lastSaveErrorName)
      return
    }
    if (_saves > savesBefore)
      wrote()
  }

  function stopWriting(reason) {
    if (!_writable)
      return
    _writable = false
    _hasPending = false
    _pending = ""
    debounce.stop()
    console.warn("TurboTables FileStore: " + reason
                 + " -- this session will not write the save file again.")
    writeFailed(reason)
  }

  // Somebody has decided the unreadable or unwritable file may be replaced.
  // Nothing calls this on its own; it exists so a screen can offer the way out
  // once one is built.
  function allowWritingAgain() {
    _writable = true
  }

  property int _saveFailures: 0
  property int _saves: 0
  property string _lastSaveErrorName: ""

  property Timer debounce: Timer {
    interval: fileStore.debounceMs
    repeat: false
    running: false
    onTriggered: fileStore.writeNow()
  }

  property FileView file: FileView {
    path: fileStore.path
    // Blocking reads, so `load()` can answer synchronously: the Store's
    // contract is a return value, not a callback, and an async read would make
    // "I have not found out yet" indistinguishable from "there is no file",
    // which is the mistake this whole file is built against.
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    // The plugin reports its own file problems in its own words; Quickshell's
    // stderr line for a missing file on a fresh install is not an error.
    printErrors: false
    // Deliberately off. A file replaced underneath a running session would
    // otherwise be adopted mid-race, and this plugin's own writes are the only
    // ones it expects. What it costs is written down in the evidence.
    watchChanges: false

    onLoaded: {
      fileStore._verdict = "present"
      fileStore._lastError = -1
      fileStore._lastErrorName = ""
    }

    onLoadFailed: function (error) {
      fileStore._lastError = error
      if (error === FileViewError.FileNotFound) {
        fileStore._verdict = "absent"
        fileStore._lastErrorName = "no such file"
      } else {
        fileStore._verdict = "unreadable"
        fileStore._lastErrorName = FileViewError.toString(error)
      }
    }

    onSaved: fileStore._saves += 1

    onSaveFailed: function (error) {
      fileStore._saveFailures += 1
      fileStore._lastSaveErrorName = FileViewError.toString(error)
    }
  }

  Component.onDestruction: flushNow()
}
