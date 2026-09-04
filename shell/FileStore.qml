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
// A fourth was added in round 4 of the seam audit, and it is the one that
// covers the ordinary case rather than a broken one:
//
//   4. Nothing is written over a file whose bytes are not the bytes this object
//      last read or last wrote. See "SOMEBODY ELSE'S BYTES" below.
//
// Directory creation is not a special case: FileView creates missing parents on
// write, measured on the same Quickshell build, so a fresh install needs no
// mkdir and this plugin never has to start anything to make one.
//
// The write side, measured the same way (evidence: vm-b9fb591.md §4.5, one
// throwaway FileView per case, `blockWrites: true`):
//
//   chmod 000 file, atomicWrites on   saveFailed(PermissionDenied=3), file kept
//   chmod 000 file, atomicWrites off  saveFailed(PermissionDenied=3), file kept
//   chmod 444 file                    saveFailed(PermissionDenied=3), file kept
//   chmod 600 file                    saved; new inode, mode copied from the old
//   chmod 000 file in a chmod 555 dir saveFailed(PermissionDenied=3)
//   no file, into a chmod 555 dir     saveFailed(Unknown=1), nothing created
//   no file, into a chmod 000 dir     saveFailed(PermissionDenied=3)  [seam r4]
//   no file, missing parents          saved, parents created, mode 644
//   identical bytes over a good file  saved IS raised on this build
//
// The first row is the one that decides what the way out can do: `QSaveFile`
// will not open a target this user cannot write, so a save file at mode 000
// cannot be replaced from inside the game at all. That is a dead end, and this
// file's job is to make it a dead end that says what to do -- see
// `_writeFailureReason()`. The last row contradicts the sentence under
// `writeNow()` about an unchanged write raising neither signal; nothing here
// depends on it either way, because `_wroteTheFile` is deliberately not
// conditioned on `_saves` moving.
//
// ---------------------------------------------------------------------------
// SOMEBODY ELSE'S BYTES
// ---------------------------------------------------------------------------
//
// The re-proof above was worn only over an `absent` verdict. A `present`
// verdict was sticky and trusted: the file was read once at shell start, the
// plugin stays loaded all session (`keepLoaded: true`), and `setText` then
// replaced whatever was on disk with this session's in-memory snapshot with no
// second look. Reproduced in the VM: a save written by another writer at t=2.0s,
// holding a record this session had never seen, was gone after one keystroke at
// t=4.5s -- no probe, no refusal, no message.
//
// That is not a theoretical writer. The design promises a file "human-readable,
// so a parent can see exactly what is kept", and the only remedy the product
// has for a save file that cannot be read is a parent putting a good one back
// by hand. Doing that while the child is logged in used to destroy it, which is
// what made an unreadable save file permanent.
//
// So every write now re-reads the file first and compares it against
// `_lastKnownText` -- the exact bytes this object last read from that path, or
// last wrote to it. They differ, or the file cannot be re-read: refuse, and
// stop writing for the session with a reason that says so. The file went away
// and its absence proves out: allow it, because there is nothing there to
// destroy. The cost is one blocking read per write, and writes are debounced at
// 400 ms, so it is at most two and a half reads a second of a file measured at
// well under a kilobyte.
//
// ---------------------------------------------------------------------------
// THE WAY OUT
// ---------------------------------------------------------------------------
//
// Refusals 1 and 2 are exactly the state a file that could not be *read* leaves
// this object in, and they have no expiry: `_everLoaded` is false and nothing
// in the session ever sets it. A family whose `garage.json` is corrupt would
// therefore never save again on that machine -- in this session or any later
// one -- because the way out the product offers, `Store.discardQuarantinedFile`,
// cleared a flag one layer up and was refused down here, silently, while the
// screen said "A NEW SAVE FILE HAS BEEN STARTED".
//
// `replaceUnreadableFile()` is the counterpart that was missing. It is the
// file layer's own record of a decision a person made -- the Confirm dialog in
// ui/Settings.qml, which names what is lost before it asks -- and it authorises
// exactly one act: refusals 1 and 2 stand aside for it, and once the write has
// landed this object owns the file and the ordinary rules apply again to the
// bytes it just put there. Nothing calls it except that decision.
//
// It authorises no more than that, and both halves of that sentence were wrong
// for a round:
//
//   * It never stood refusal 4, or the absence re-proof, down. An authorised
//     write was the only write in this file that put a byte on disk having
//     taken no look at all, and the two saves that cost were the two cases the
//     rest of this file exists for -- a chmod 000 save readable again by the
//     time the family reached the button, a shut home unlocked -- with the
//     screen still saying the file could not be read.
//     `_authorisedReplacementStillApplies()` is that look, and it is taken at
//     the moment of the write rather than inherited from the read that made
//     the family press.
//   * It is one *act*, not one landed write. It is spent by the attempt, and
//     cleared by anything that ends the act: a refusal (`stopWriting`), a read
//     that comes back either way (present or a proved absence),
//     `allowWritingAgain()`, and a new path.
//
// One exception it does keep, and it is written here because it is a permanent
// one: `_replacedTheFile`. After an authorised write lands, refusals 1 and 2
// are off for the life of the object, while `_everLoaded` is still false and
// `_verdict` is still "unreadable" -- because no read has happened and this
// file will not pretend one has. Refusal 4 carries that session on its own,
// over bytes this object wrote and therefore knows first-hand.
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
    // A new path is a new file: nothing is known about its bytes, and an
    // authorisation to replace the previous one does not travel to it.
    _lastKnownText = ""
    _lastKnownTextIsKnown = false
    _replaceAuthorised = false
    _replacedTheFile = false
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

  // The bytes this object last read off `path`, or last wrote to it. It is the
  // only thing that can tell "the file I am about to replace is the one I am
  // holding a newer version of" from "somebody else has written here since",
  // and the second of those is a parent hand-restoring a save while the child
  // is logged in. Empty and `_lastKnownTextIsKnown` false until a read or a
  // write has established it; while it is unknown, the absence re-proof above
  // is the guard that stands in its place.
  //
  // Held as text on both protocols on purpose: the object protocol's payload is
  // this exact string parsed, so the string is what is on disk either way, and
  // comparing what is on disk to what is on disk needs no parser to agree.
  property string _lastKnownText: ""
  property bool _lastKnownTextIsKnown: false

  // A person has decided, through the Confirm dialog in ui/Settings.qml, that
  // the file this object is refusing to touch may be replaced. It authorises
  // one overwrite; the write that lands consumes it and sets `_replacedTheFile`,
  // after which this object owns the file and the ordinary refusals apply again
  // -- to the bytes it put there, which it now knows.
  //
  // It is deliberately not spelled by setting `_everLoaded`, or by moving
  // `_verdict` to "present". Those two record what a *read* said, no read has
  // happened, and a file that lies to itself about having read something is the
  // exact shape of the five bugs this whole layer exists to refuse.
  readonly property bool replaceAuthorised: _replaceAuthorised
  property bool _replaceAuthorised: false
  property bool _replacedTheFile: false

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
    // `_probeComponent` is this object's own child, and refusal 4 now takes a
    // probe before *every* write -- including the one `Component.onDestruction`
    // asks for, by which time the children may already be gone. The same shape
    // as the `debounce.stop()` guard three functions down, and the same cost if
    // it is missed: a TypeError out of every teardown. "I could not build a
    // probe" is not a verdict either, so it answers the way silence does and
    // the write above is refused rather than taken on trust.
    //
    // In the shipping wiring this does not cost the child their last change:
    // `TurboTables.qml` flushes on `close()`, on `dismiss()` and from its own
    // `Component.onDestruction`, all while this object and its children are
    // alive, so the flush that matters has already happened and this object's
    // own destruction finds nothing pending.
    if (!_probeComponent)
      return { "outcome": -2, "text": "" }
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
      _remember(text)
      _readSupersedesAnyAuthorisation()
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
          _remember(again.text)
          _readSupersedesAnyAuthorisation()
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
      // This is a read that came back, and it retires an authorisation exactly
      // like the one above does. It used not to, and that made the invariant
      // this file states -- "retired unspent by a read that comes back" --
      // false for the one branch where it mattered most: a standing
      // authorisation then skipped the absence re-proof below and wrote over a
      // file that had appeared since.
      _readSupersedesAnyAuthorisation()
      return null
    }

    if (_verdict === "unreadable")
      throw new Error("the save file at " + path + " could not be read: " + _lastErrorName)

    throw new Error("the save file at " + path + " could not be read: the read produced no result")
  }

  // What is on disk at `path`, as far as this object knows: set by a read that
  // succeeded and by a write that landed, and by nothing else. Refusal 4 is
  // this and a comparison.
  function _remember(text) {
    _lastKnownText = typeof text === "string" ? text : ""
    _lastKnownTextIsKnown = true
  }

  // A read that came back supersedes an authorisation to replace a file that
  // could not be read. The person was asked about a file nothing could see; the
  // file this session can now see is a different question, and an unspent
  // authorisation left standing would let one write past refusal 4 without
  // anyone having decided that. `_replacedTheFile` is not cleared: that records
  // a write this object actually made, which is a fact, not a permission.
  function _readSupersedesAnyAuthorisation() {
    _replaceAuthorised = false
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
    //          "unreadable" -- unless a person has decided this file may be
    //          replaced, which is the one thing that can outrank a read that
    //          never came back. Without that exception these two refusals are
    //          permanent, and the way out of a quarantine is a button that
    //          reports success and does nothing.
    if (!(_replaceAuthorised || _replacedTheFile)) {
      if (!_everLoaded) {
        stopWriting("refused to write to " + path + " before the file had been read")
        return
      }
      if (_verdict === "unreadable") {
        stopWriting("refused to write over an unreadable save file at " + path)
        return
      }
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
    //
    // A write a person explicitly authorised takes a different look, not none.
    // It used to take none at all, and it was the only write in this file that
    // put a byte on disk having looked at nothing: see
    // `_authorisedReplacementStillApplies()` for the two saves that cost.
    var authorised = _replaceAuthorised
    if (authorised) {
      // Spent by the attempt, not by the landing. A write that failed has used
      // up the decision a person made; the next write is one nobody asked for,
      // and it used to inherit this. Set `_replacedTheFile` below only if the
      // write actually lands, because that flag records a fact about the disk
      // rather than a permission.
      _replaceAuthorised = false
      if (!_authorisedReplacementStillApplies())
        return
    } else {
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
      } else if (_lastKnownTextIsKnown && !_checkedTheBytesStillMatch()) {
        return
      }
    }

    var failuresBefore = _saveFailures
    var savesBefore = _saves
    _writeWasAuthorised = authorised
    file.setText(text)

    // `blockWrites: true`, so both signals have already fired by here
    // (measured: a write into a read-only directory raised saveFailed inside
    // setText). An unchanged file writes nothing and raises neither, which is
    // why only an explicit failure counts as one.
    if (_saveFailures > failuresBefore) {
      stopWriting(_writeFailureReason())
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

    // The bytes on disk are now the bytes just written, and that is a thing
    // this object knows first-hand rather than inferred. It is what refusal 4
    // compares against next time, and it is what lets an authorised replacement
    // hand the session back to the ordinary rules instead of needing to be
    // re-authorised on every keystroke afterwards.
    _remember(text)
    if (authorised)
      _replacedTheFile = true

    if (_saves > savesBefore)
      wrote()
  }

  // The look an authorised replacement takes, immediately before it lands.
  //
  // `replaceUnreadableFile()` may stand down refusals 1 and 2, because a person
  // decided about exactly the thing those two refuse -- a file this session
  // could not read. It may not stand down the question every other write in
  // this file is asked, which is *what is on that path right now*. It used to,
  // and both cases it lost are the two this whole file exists for, measured in
  // the shipping wiring:
  //
  //   a chmod 000 save that becomes readable before the family reaches the
  //   button -- defaults written over a record and 48 facts, no refusal;
  //   a shut home that unlocks, with the strip still reading "was not found"
  //   -- the same, and the premise on the screen was already false when it was
  //   read.
  //
  // Both are conditions the header lists as the realistic triggers -- an
  // fscrypt home not yet unlocked, a root-owned `~/.local/share`, a mount
  // briefly away -- and all three resolve on their own, which is exactly what
  // makes the gap between the read at shell start and the press the interesting
  // one. The consent is real; the premise it was given had expired.
  //
  // So the question is put in the only two ways this state can answer it:
  //
  //   the bytes are known    a read did come back. That is the write-side way
  //                          out (the file read perfectly and could not be
  //                          *written* to) and the read-side quarantine over a
  //                          file whose *contents* the Store rejected. Refusal
  //                          4 unchanged: the file about to be replaced has to
  //                          still be the file this session read.
  //   the bytes are unknown  no read ever came back, which is the premise the
  //                          family was shown. Ask the disk once more, here,
  //                          now. If it reads back, there is a save sitting on
  //                          that path and the screen was wrong: refuse, and
  //                          name the action that recovers it. Still unreadable
  //                          or still not found, the button does what it says.
  //
  // Cost: one `stat`, on a path that already builds probes.
  function _authorisedReplacementStillApplies() {
    if (_lastKnownTextIsKnown)
      return _checkedTheBytesStillMatch()

    var now = _probeRead(path)
    if (now.outcome === -1) {
      stopWriting("the save file at " + path + " could not be read when the game started"
                  + " and can be read now, so it is a save file rather than the wreck this"
                  + " session was told about. Refusing to write over it -- close the game"
                  + " and open it again to get the garage back")
      return false
    }
    return true
  }

  // Refusal 4. The file this object is about to replace has to still be the
  // file it is holding a newer version of. Answers false when the write must
  // not go ahead, and has already stopped the writing and said why.
  function _checkedTheBytesStillMatch() {
    var now = _probeRead(path)

    if (now.outcome === -1) {
      if (now.text === _lastKnownText)
        return true
      stopWriting("the save file at " + path + " changed on disk after this session read it,"
                  + " so what is in memory is not a newer version of what is there."
                  + " Refusing to write over it")
      return false
    }

    if (now.outcome === FileViewError.FileNotFound) {
      // It was there and it is not now. That is not automatically an absence --
      // a directory shutting answers the same way -- so it is put to the same
      // proof every other absence in this file is put to. Proved gone, there is
      // nothing on that path to destroy and the write goes ahead; unproved, the
      // honest answer is that this session no longer knows what is on disk.
      if (_absenceIsProven(path))
        return true
      stopWriting("the save file at " + path + " could not be found or shown to be absent"
                  + " before writing over it, so this session does not know what is on disk."
                  + " Refusing to write over it")
      return false
    }

    stopWriting("the save file at " + path + " could not be re-read before writing over it: "
                + (now.outcome >= 0 ? FileViewError.toString(now.outcome)
                                    : "the read produced no result")
                + ". Refusing to write over it")
    return false
  }

  // What a failed write says to the family, and it is the only message in the
  // plugin that has to survive being the last one.
  //
  // The way out of a read-side quarantine is one button, and there is a case it
  // cannot win: measured in the Omarchy VM on Quickshell 0.3.1, `setText` over a
  // `chmod 000` file raises `saveFailed(PermissionDenied)` and leaves the file,
  // with `atomicWrites` on or off, because `QSaveFile` will not open a target
  // this user cannot write. The test double had modelled that write as
  // succeeding, so for a round the way out was believed to work for the one case
  // it is named after.
  //
  // A dead end is an acceptable answer. A dead end that reads like an internal
  // note is not: the family is then holding a locked garage, a red strip, and a
  // sentence about a file mode. So when the file layer knows the kernel's own
  // reason, it says what a person can do about it -- named actions, on the path
  // this plugin actually owns, neither of which loses anything. Anything else is
  // reported with its error name and the one step that is always true.
  function _writeFailureReason() {
    // Two screens print this sentence and one of them, the RESET panel in
    // ui/Settings.qml, is a narrow column: a message that runs on climbs over
    // the button it is about. The path is named once at the front and once in
    // the command that recovers everything, and the second remedy is described
    // rather than spelled, which is what keeps it to four lines there.
    var act = _writeWasAuthorised ? "could not be replaced" : "could not be written to"
    if (_lastSaveError === FileViewError.PermissionDenied) {
      // Which thing is locked: the file, or the folder holding it? Measured in
      // the VM, both answer PermissionDenied on the write -- a save at chmod
      // 000, and a save that is not there at all behind a directory at chmod
      // 000 (an fscrypt home that has not unlocked is the realistic one). A
      // message that always named the file would send a parent to chmod
      // something that does not exist. One probe settles it, on the failure
      // path, where a stat costs nothing.
      var folder = _parentOf(path)
      if (_probe(path) === FileViewError.FileNotFound)
        return "the save file at " + path + " " + act + ": this computer will not let the game"
             + " write into " + folder + " (Permission denied), and there is no save file in"
             + " there to read either. A grown-up can put it right from a terminal:"
             + " chmod u+rwx " + folder + ". Then close the game and open it again."
      return "the save file at " + path + " " + act + ": this computer will not let the game"
           + " write to it (Permission denied). A grown-up can put it right from a terminal,"
           + " without losing anything: chmod u+rw " + path
           + " -- or move that file somewhere else to start fresh."
           + " Then close the game and open it again."
    }
    return "the save file at " + path + " " + act + ": " + _lastSaveErrorName
         + ". Nothing was written. A grown-up can look at that file; once it can be written"
         + " to, close the game and open it again."
  }

  function stopWriting(reason) {
    if (!_writable)
      return
    _writable = false
    _hasPending = false
    _pending = ""
    // A refusal ends the act the authorisation was for. It used to survive one,
    // unspent, for the life of the object: a write that failed left the
    // decision a person made lying around, and the next write -- an ordinary
    // keystroke, after `allowWritingAgain()` lifted this latch -- spent it on a
    // file nobody had been asked about.
    _replaceAuthorised = false
    // Guarded for the same reason `flushNow` is, and it was missed there:
    // `Component.onDestruction` -> `flushNow()` -> `writeNow()` -> here, by
    // which time this object's own children may already be gone.
    if (debounce)
      debounce.stop()
    console.warn("TurboTables FileStore: " + reason
                 + " -- this session will not write the save file again.")
    writeFailed(reason)
  }

  // Somebody has decided the unwritable file may be written to again. Called
  // from the wiring when the Store's quarantine clears; it lifts the latch a
  // failed write set and nothing else, which is right for a file that read
  // perfectly and could not be written.
  // It also ends any authorisation that is standing. `TurboTables.qml` calls
  // this on every quarantine-clear transition, which is a thing that happens
  // for reasons of its own -- so an authorisation still standing when it runs
  // is one that belongs to some earlier act, and the write that would spend it
  // is a write nobody asked for. `ui/Store.qml`'s `discardQuarantinedFile()`
  // therefore authorises *after* it raises the transition and immediately
  // before the write it authorised: the granting and the spending are adjacent,
  // which is what "one act" has to mean.
  function allowWritingAgain() {
    _writable = true
    _replaceAuthorised = false
  }

  // Somebody has decided the file this object is refusing to touch may be
  // replaced -- through the Confirm dialog in ui/Settings.qml, which names what
  // is lost before it asks. It is named for the case it exists for, a file that
  // could not be *read*, and `ui/Store.qml` calls it for the write-side
  // quarantine too, where it does no harm: that path has read the file, so
  // refusals 1 and 2 were never standing and only `_writable` was.
  //
  // See "THE WAY OUT" in the header. This is the only thing in the plugin that
  // can retire refusals 1, 2 and 4, it retires them for exactly one write, a
  // read that comes back retires it unspent, and it is called only from
  // `ui/Store.qml`'s `discardQuarantinedFile()`.
  function replaceUnreadableFile() {
    _replaceAuthorised = true
    _writable = true
  }

  property int _saveFailures: 0
  property int _saves: 0
  // The code as well as the name: the message a family is left with turns on
  // which failure it was, and a name comparison would be a second spelling of
  // the enum this file already compares against by value everywhere else.
  property int _lastSaveError: -1
  property string _lastSaveErrorName: ""
  // Whether the write that is landing is the one a person asked for through the
  // Confirm dialog, so a refusal can name the act rather than the mechanism.
  property bool _writeWasAuthorised: false

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
      fileStore._lastSaveError = error
      fileStore._lastSaveErrorName = FileViewError.toString(error)
    }
  }

  Component.onDestruction: flushNow()
}
