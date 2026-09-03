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
//   null                the file is *proved* not to be there. See below: a
//                       not-found verdict is where that proof starts, never
//                       where it ends.
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
//   a directory    text() == ""        loadFailed(NotAFile=4)       loaded=TRUE
//
// Note the third and fourth rows. FileView's `loaded` *property* is
// `isLoadedOrAsync` and reads true for a file that could not be read at all, so
// it is not a verdict and this file never consults it. The verdict comes only
// from the `loaded()` and `loadFailed(error)` signals, which -- also measured --
// fire synchronously inside `text()` while `blockLoading` is true.
//
// ---------------------------------------------------------------------------
// WHY `FileNotFound` IS NOT PROOF OF ABSENCE
// ---------------------------------------------------------------------------
//
// An earlier version of this file believed it was, and a critic destroyed a
// real save with it in the VM: a 260-byte defaults file over a save holding a
// record and a child's fact history. Measured, on this Quickshell build
// (evidence: piece7-ours.md, "the parent-directory probe"):
//
//   file inside a chmod 000 directory      loadFailed(FileNotFound=2)
//   file inside a chmod 666 directory      loadFailed(FileNotFound=2)
//   file that genuinely is not there       loadFailed(FileNotFound=2)
//
// The kernel returns EACCES for a path whose directory component cannot be
// walked into; Quickshell asks `exists()` first, `exists()` answers false, and
// every one of those cases arrives here as the same number. So
// `FileNotFound` means "I did not find it", and "I did not find it" is the
// exact sentence this whole file exists to stop being read as "it is not
// there". The realistic triggers are ordinary: an fscrypt home not yet
// unlocked when the shell starts, `~/.local/share` left root-owned by a sudo
// mishap, `$XDG_DATA_HOME` on a network mount that is briefly away.
//
// Absence is therefore *earned*, by `_absenceIsProven()`, and the proof is
// positive rather than inferential:
//
//   0. Ask about the path itself, again, with a fresh view. A proof of absence
//      that reuses an older reading is not a proof: the reading and the proof
//      would then have been taken under different conditions, and the gap
//      between them is exactly where a directory unlocks. Anything but
//      "not found" -- a file that reads, a permissions error, silence --
//      ends the proof here.
//   1. Walk up from the path. For each ancestor directory, ask FileView what
//      it is. `NotAFile` means "this exists and is not a regular file" -- the
//      directory is there.
//   2. For the first ancestor that is there, ask FileView about `<ancestor>/.`
//      as well. That path can only be resolved by walking *into* the ancestor,
//      so `NotAFile` for it is positive proof of a directory this process can
//      traverse -- measured to track the +x bit exactly, including the
//      awkward modes: chmod 111 (traversable, unreadable) proves traversable,
//      chmod 666 (readable, untraversable) does not.
//   3. Only then is a `FileNotFound` below that ancestor genuine absence.
//      Every other outcome -- a shut directory, a `PermissionDenied`, an
//      ancestor that turns out to be a regular file, a walk that runs out of
//      steps -- is "I could not find out", which is a throw.
//
// Step 0 is round 3's, and it closes a door a critic opened by asking for the
// same file twice. The verdict below is sticky, and `_absenceIsProven()` used
// to interrogate only the ancestors -- so a not-found reading taken while the
// directory was shut, combined with a traversability proof taken after it
// opened, answered `null` with `absenceProven` true for a path holding a
// readable save. The verdict outlived the conditions it was taken under.
// Nothing reached the disk, because the write side probed again, but the whole
// claim of this file is that absence is established rather than inherited, and
// in that case it was inherited. A proof now re-establishes every reading it
// rests on, including the one it started from.
//
// And because a directory can unlock between the read and the write -- which
// is precisely how the save was destroyed: locked when the shell started, open
// by the time the child pressed a key -- the proof is taken again, from
// scratch, before *every* write over a path this object believes is absent and
// has not itself written. If that second look finds a readable file where
// there was supposed to be nothing, the write is refused and the session stops
// writing. A save that reappears is a save, not an empty slot. That re-proof
// used to latch after one pass; it does not any more, because the pass that
// matters is not necessarily the first one.
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

  // Nothing in the plugin moves the path at runtime; the entry-point fixture
  // does, and so would anyone testing this file. Without this the verdict is
  // sticky across the move and FileView serves the *previous* file's text with
  // no signal, so a store pointed at a new path would answer with file A's
  // contents and, worse, write them to path B. A new path is a new file and
  // nothing is known about it until it has been read.
  onPathChanged: {
    _verdict = "unknown"
    _lastError = -1
    _lastErrorName = ""
    _everLoaded = false
    _absenceProven = false
    _wroteTheFile = false
    _writable = true
    _hasPending = false
    _pending = ""
    if (debounce)
      debounce.stop()
  }

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
  //   "absent"      FileView did not find the file. On its own this is not a
  //                 claim that the file is not there -- see the header. Only
  //                 `_absenceIsProven()` turns it into one.
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

  // True once `_absenceIsProven()` has agreed with an "absent" verdict, which
  // is the only way `load()` may answer null. Read by the entry-point fixture.
  readonly property bool absenceProven: _absenceProven
  property bool _absenceProven: false

  // True once this object has written the file itself. Only then may a write
  // over an "absent" verdict skip the re-proof -- because from that point the
  // file this object would find is the one it put there.
  //
  // This used to be `_absenceReproven`, set by the first re-proof that passed,
  // which made the guard a single shot. It is the only guard standing between
  // a stale absence and a real save, so it is now worn on every write until
  // this object owns the file.
  property bool _wroteTheFile: false

  // How many directory levels the walk may climb before it gives up and calls
  // the answer "I could not find out". A save path is four levels below the
  // home directory; twenty is far more than the design can ever need and
  // bounds the number of blocking stat calls this file makes on the GUI
  // thread, which matters on a save path that lives on a slow mount.
  readonly property int maxAncestorProbes: 20

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

  // ------------------------------------------------- proving absence
  //
  // One throwaway FileView per question. A fresh object is used rather than
  // this store's own `file` because FileView caches: a second read of an
  // unchanged path emits no signal at all, so a reused view cannot be asked a
  // second question and be trusted to answer it. Measured, both ways.
  property Component _probeComponent: Component {
    FileView {
      // -1 means the read succeeded; anything >= 0 is a FileViewError; -2
      // means the read produced no verdict at all, which is also an answer.
      property int outcome: -2
      blockLoading: true
      blockWrites: true
      printErrors: false
      watchChanges: false
      onLoaded: outcome = -1
      onLoadFailed: function (error) { outcome = error }
    }
  }

  function _probeRead(probePath) {
    var probe = _probeComponent.createObject(null, { "path": probePath })
    if (!probe)
      return { "outcome": -2, "text": "" }
    var text = ""
    try {
      text = probe.text()
    } catch (error) {
      // A throw out of text() is not a verdict either; `outcome` still holds
      // whatever the signals said, and -2 if they said nothing.
    }
    var answer = { "outcome": probe.outcome, "text": text }
    probe.destroy()
    return answer
  }

  function _probe(probePath) {
    return _probeRead(probePath).outcome
  }

  function _parentOf(childPath) {
    var cut = childPath.lastIndexOf("/")
    if (cut < 0)
      return ""
    if (cut === 0)
      return "/"
    return childPath.substring(0, cut)
  }

  // Positive proof that nothing lives at `targetPath`. See the header for why
  // a not-found verdict is only ever the beginning of this question.
  //
  // Every reading this answer rests on is taken here, now, including the
  // reading of the file itself. Absence is a claim about a moment, and a claim
  // about a moment may not be assembled out of readings taken at two different
  // ones: the store's `absent` verdict may have been recorded seconds ago,
  // while the home directory was still locked, and a caller that trusted it
  // and only checked the ancestors would call an unlocked directory holding a
  // real save "empty".
  function _absenceIsProven(targetPath) {
    // Step 0. The file itself, from a fresh view with no cache to serve from.
    var here = _probe(targetPath)
    if (here !== FileViewError.FileNotFound)
      return false

    var child = targetPath
    for (var step = 0; step < maxAncestorProbes; step++) {
      var parent = _parentOf(child)
      if (parent === "" || parent === child)
        return false                       // walked off the top of the path

      var parentOutcome = _probe(parent)

      if (parentOutcome === FileViewError.NotAFile) {
        // The directory is there. Whether this process may walk into it is a
        // different question, and the only one that decides this: a directory
        // that cannot be entered answers FileNotFound for everything inside
        // it, which is exactly the lie that destroyed a save. `<parent>/.`
        // can only be resolved by entering `<parent>`.
        return _probe(parent + "/.") === FileViewError.NotAFile
      }

      if (parentOutcome === FileViewError.FileNotFound) {
        // Either the directory is missing -- in which case nothing beneath it
        // exists and the proof continues one level up -- or its own parent
        // cannot be walked into, which the next turn of this loop catches.
        child = parent
        continue
      }

      // A readable regular file where a directory should be, a permissions
      // error, or no verdict at all. All of them are "I could not find out".
      return false
    }
    return false
  }

  // --------------------------------------------------------------- reading
  //
  // Three outcomes, no fourth. See the header.
  function load() {
    var text = file.text()

    // FileView serves a cached read and emits nothing at all when it believes
    // the answer has not changed. Measured on this build: after `path` moves,
    // neither `text()` nor `reload()` followed by `text()` produces a verdict
    // for the new path -- the view stays on the old answer and stays silent
    // about it. Silence is not a verdict, so the question is put to a fresh
    // view, which has no cache to serve from. Nothing in the plugin moves the
    // path; the fixture does, and a store that answered for the wrong file
    // would write one file's contents to another's name.
    if (_verdict === "unknown") {
      file.reload()
      text = file.text()
    }
    if (_verdict === "unknown") {
      var reread = _probeRead(path)
      if (reread.outcome === -1) {
        _verdict = "present"
        _lastError = -1
        _lastErrorName = ""
        text = reread.text
      } else if (reread.outcome === FileViewError.FileNotFound) {
        _verdict = "absent"
        _lastError = reread.outcome
        _lastErrorName = "no such file"
      } else if (reread.outcome >= 0) {
        _verdict = "unreadable"
        _lastError = reread.outcome
        _lastErrorName = FileViewError.toString(reread.outcome)
      }
    }

    if (_verdict === "present") {
      _everLoaded = true
      return _decode(text)
    }

    if (_verdict === "absent") {
      // The one case that may mean "fresh install" -- and the one case that
      // has to be earned, because FileView answers FileNotFound both for a
      // path that is not there and for a path it was not allowed to look at.
      // `_absenceIsProven` re-reads the path itself as well as its ancestors,
      // so this is a claim about now rather than about whenever the verdict
      // above was recorded.
      if (!_absenceIsProven(path)) {
        // It failed for one of two very different reasons and the caller is
        // owed the right one. Either an ancestor could not be read into, or
        // the verdict is older than the file: a directory that was shut when
        // this store first looked can be open by the time it is asked again,
        // and behind it is a real save. That case is not an error at all --
        // the file is there and readable, so it is read.
        var again = _probeRead(path)
        if (again.outcome === -1) {
          _verdict = "present"
          _lastError = -1
          _lastErrorName = ""
          _everLoaded = true
          return _decode(again.text)
        }
        if (again.outcome >= 0 && again.outcome !== FileViewError.FileNotFound) {
          _verdict = "unreadable"
          _lastError = again.outcome
          _lastErrorName = FileViewError.toString(again.outcome)
          throw new Error("the save file at " + path + " could not be read: "
                          + _lastErrorName)
        }
        throw new Error("the save file at " + path + " was not found, and its absence"
                        + " could not be established: a directory above it could not be"
                        + " read into. Refusing to treat this as a fresh install.")
      }
      _absenceProven = true
      _everLoaded = true
      return null
    }

    if (_verdict === "unreadable")
      throw new Error("the save file at " + path + " could not be read: " + _lastErrorName)

    throw new Error("the save file at " + path + " could not be read: the read produced no result")
  }

  // The file's own bytes, in whichever protocol the Store speaks. Shared by
  // the two ways a present file can be reached: the ordinary read, and a read
  // that had to correct a stale "absent" verdict.
  function _decode(text) {
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
    // `typeof [] === "object"`, so the array has to be named or a JSON array
    // walks straight through a check whose message says it did not. A Store
    // handed an array reads every key off it as undefined, adopts the
    // defaults, and writes them over the file on the next keystroke -- the
    // same destruction with different bytes in front of it.
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
      throw new Error("the save file at " + path + " is not a JSON object")
    return parsed
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
    // `Component.onDestruction` calls this, and by then the object's own
    // children may already be gone: an unguarded `debounce.stop()` raises
    // "TypeError: Cannot read property 'stop' of null" out of every teardown.
    // It was harmless -- the exception escapes after the last write is
    // irrelevant -- but a file whose argument is made of its own log lines
    // should not be printing a TypeError on the way out.
    if (debounce)
      debounce.stop()
    writeNow()
  }

  function writeNow() {
    if (!_hasPending || !_writable)
      return
    var text = _pending
    _hasPending = false
    _pending = ""

    // The last look before a byte lands on a path this object was told is
    // empty. The save that was destroyed in the VM was destroyed in exactly
    // this gap: the directory was shut when the shell started and open by the
    // time the child pressed a key, so the read said "nothing here" and the
    // write found a real file to land on.
    //
    // This runs before *every* such write, not once. It used to latch on the
    // first pass, on the reasoning that after one write this object owns the
    // file -- but the thing that makes that true is the write, not the proof,
    // and a first write that never landed left the guard spent and the second
    // write unguarded. `_wroteTheFile` is set below, by a write that did not
    // fail, which is the condition the reasoning actually wanted.
    if (_verdict === "absent" && !_wroteTheFile) {
      var second = _probe(path)
      if (second === -1) {
        stopWriting("the save file at " + path + " was not found when the game started"
                    + " and is readable now, so the defaults in memory are not what is"
                    + " on disk. Refusing to write over it")
        return
      }
      if (second !== FileViewError.FileNotFound || !_absenceIsProven(path)) {
        stopWriting("the save file at " + path + " could not be shown to be absent a"
                    + " second time, so this session does not know what is on disk."
                    + " Refusing to write over it")
        return
      }
    }

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

    // A write that did not fail is what makes "this object owns the file" true,
    // and it is the only thing that may retire the re-proof above. Note that it
    // is deliberately not conditioned on `_saves` moving: an unchanged file
    // writes nothing and raises neither signal, and a write that put nothing
    // new on disk is still a write this object made over this path.
    //
    // `_verdict` is left alone. It records what a *read* said, and no read has
    // happened; inferring "present" from a write would be the same shape of
    // reasoning this file exists to refuse.
    _wroteTheFile = true

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
