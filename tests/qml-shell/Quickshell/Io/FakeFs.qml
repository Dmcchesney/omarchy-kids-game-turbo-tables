pragma Singleton
import QtQuick

// A filesystem a test can shut, open, fill and replace underneath a running
// `shell/FileStore.qml`.
//
// ---------------------------------------------------------------------------
// WHAT THIS IS AND WHAT IT IS NOT
// ---------------------------------------------------------------------------
//
// `shell/FileStore.qml` is the only code in the repository that touches a disk,
// and until now the only place it could be run at all was the Omarchy VM: it
// imports Quickshell, which is not on the maintainer's Mac, so every claim
// about it was either a VM run or a reading. That is how a whole class of
// defect -- what happens *after* the plugin correctly refuses to write --
// stayed unaudited for four rounds, and it is why the VM being down cost a
// round's worth of evidence.
//
// So this is a model of the *shell*, not of the plugin. Nothing here restates a
// rule `shell/FileStore.qml` keeps; it answers the questions that file asks, the
// way Quickshell 0.3.1 was measured answering them in the VM.
//
// Reads (rounds 5 and 7, re-measured at b9fb591):
//
//   missing file                        text() == ""        loadFailed(FileNotFound=2)
//   readable file                       text() == contents  loaded()
//   file, chmod 000                     text() == ""        loadFailed(PermissionDenied=3)
//   a directory                         text() == ""        loadFailed(NotAFile=4)
//   file inside a chmod 000 directory   loadFailed(FileNotFound=2)
//   file inside a chmod 666 directory   loadFailed(FileNotFound=2)
//   `<dir>/.` for a traversable dir     loadFailed(NotAFile=4)
//   `<dir>/.` for chmod 666             loadFailed(FileNotFound=2)
//   an unchanged second read            no signal at all
//   a write with missing parents        the parents are created
//
// Writes (vm-b9fb591.md §4.5, one throwaway FileView per case):
//
//   chmod 000 file, atomicWrites on     saveFailed(PermissionDenied=3), file kept
//   chmod 000 file, atomicWrites off    saveFailed(PermissionDenied=3), file kept
//   chmod 444 file                      saveFailed(PermissionDenied=3), file kept
//   chmod 600 file                      saved; new inode, mode copied from the old
//   chmod 000 file in a chmod 555 dir   saveFailed(PermissionDenied=3)
//   no file, into a chmod 555 dir       saveFailed(Unknown=1), nothing created
//   no file, into a chmod 000 dir       saveFailed(PermissionDenied=3)  [seam r4]
//   no file, missing parents            saved, parents created
//   identical bytes over a good file    saved IS raised on this build
//
// ---------------------------------------------------------------------------
// WHY PERMISSIONS ARE A MODE AND NOT THREE BOOLEANS
// ---------------------------------------------------------------------------
//
// They were three booleans, and the model told the product a lie that shipped.
// `chmod(path, { "readable": false })` -- which every test wrote to mean
// "chmod 000" -- left `writable: true`, and `put()` then replaced the file and
// handed back one that could be read. So the test double said the way out of a
// read-side quarantine worked for the exact case that button is named after,
// while the runtime it models answers `saveFailed(PermissionDenied)` and leaves
// the file alone. Two rounds of evidence rested on it. A critic flagged the line
// as an assumption (R2-10); the VM then measured it false.
//
// The vocabulary is the defect. "readable: false" is a sentence about one bit
// that a reader hears as a sentence about a file, and nothing stops a caller
// describing a mode no chmod can produce. So a node now carries the owner's
// mode, exactly as chmod spells it, and every question this model can be asked
// is derived from it:
//
//   4  r   a file's bytes can be read; a directory can be listed
//   2  w   a file can be replaced; a directory can be written into
//   1  x   a directory can be walked into (a path component needs this)
//
// `chmod 000` is `0` and cannot be spelled any other way. chmod 111 and chmod
// 666 -- the pair that told a previous round its absence proof was real -- are
// `1` and `6`. A file at `4` is chmod 444: readable, and not replaceable, which
// is a row the VM measured and the booleans could not express.
QtObject {
  id: fs

  // The three bits, named where a test reads better for it. `chmod(path, 0)`
  // is already the clearest way to say chmod 000, so there is no name for that.
  readonly property int bitRead: 4
  readonly property int bitWrite: 2
  readonly property int bitEnter: 1

  // path -> { "kind": "file"|"dir", "text": string, "mode": int }
  property var nodes: ({})
  property int writes: 0
  property int reads: 0

  function clear() {
    fs.nodes = {}
    fs.writes = 0
    fs.reads = 0
  }

  function _modeOr(mode, fallback) {
    return (mode === undefined || mode === null) ? fallback : (Number(mode) & 7)
  }

  function canRead(node) { return node !== undefined && (node.mode & fs.bitRead) !== 0 }
  function canWrite(node) { return node !== undefined && (node.mode & fs.bitWrite) !== 0 }
  function canEnter(node) { return node !== undefined && (node.mode & fs.bitEnter) !== 0 }

  // chmod 755 for a directory a test does not say anything about.
  function dir(path, mode) {
    fs.nodes[path] = { "kind": "dir", "text": "", "mode": fs._modeOr(mode, 7) }
  }

  // Every directory from the root down to `path`, so a test says "the save
  // lives here" in one line rather than four.
  function dirs(path) {
    var parts = path.split("/")
    var at = ""
    for (var i = 1; i < parts.length; i++) {
      at = at + "/" + parts[i]
      if (fs.nodes[at] === undefined)
        fs.dir(at)
    }
  }

  // chmod 600 for a file a test does not say anything about.
  function file(path, text, mode) {
    fs.dirs(fs.parentOf(path))
    fs.nodes[path] = { "kind": "file", "text": text, "mode": fs._modeOr(mode, 6) }
  }

  function remove(path) { delete fs.nodes[path] }

  function textAt(path) {
    var node = fs.nodes[path]
    return (node === undefined || node.kind !== "file") ? null : node.text
  }

  function modeAt(path) {
    var node = fs.nodes[path]
    return node === undefined ? -1 : node.mode
  }

  // The owner's mode, as chmod spells it: 4 read, 2 write, 1 enter.
  function chmod(path, mode) {
    var node = fs.nodes[path]
    if (node === undefined)
      return
    node.mode = Number(mode) & 7
  }

  function parentOf(path) {
    var cut = path.lastIndexOf("/")
    if (cut < 0) return ""
    if (cut === 0) return "/"
    return path.substring(0, cut)
  }

  // Every directory that has to be walked into to reach `path`, root first.
  function _ancestorsOf(path) {
    var out = []
    var at = fs.parentOf(path)
    while (at !== "" && at !== "/") {
      out.unshift(at)
      at = fs.parentOf(at)
    }
    return out
  }

  // The kernel's answer, as Quickshell passes it on. A path component that
  // cannot be walked into makes `exists()` false, and Quickshell reports that
  // as FileNotFound -- which is the single measurement the whole absence proof
  // in `shell/FileStore.qml` is built to survive.
  function _walkFails(path) {
    var above = fs._ancestorsOf(path)
    for (var i = 0; i < above.length; i++) {
      var node = fs.nodes[above[i]]
      if (node === undefined || node.kind !== "dir" || !fs.canEnter(node))
        return true
    }
    return false
  }

  // What a read of `path` produces: `outcome` is -1 for a successful read and
  // a FileViewError otherwise.
  function lookup(path) {
    fs.reads += 1

    // `<dir>/.` can only be resolved by walking INTO <dir>, so <dir> is an
    // ancestor of the question rather than its subject.
    var asksToEnter = path.length > 2 && path.substring(path.length - 2) === "/."
    var target = asksToEnter ? path.substring(0, path.length - 2) : path

    if (fs._walkFails(target))
      return { "outcome": FileViewError.FileNotFound, "text": "" }

    var node = fs.nodes[target]
    if (node === undefined)
      return { "outcome": FileViewError.FileNotFound, "text": "" }

    if (node.kind === "dir") {
      if (asksToEnter && !fs.canEnter(node))
        return { "outcome": FileViewError.FileNotFound, "text": "" }
      return { "outcome": FileViewError.NotAFile, "text": "" }
    }

    if (asksToEnter)
      return { "outcome": FileViewError.FileNotFound, "text": "" }
    if (!fs.canRead(node))
      return { "outcome": FileViewError.PermissionDenied, "text": "" }
    return { "outcome": -1, "text": node.text }
  }

  // What a write of `path` produces. `outcome` -1 wrote, and anything >= 0 is a
  // FileViewError.
  //
  // The order of the questions is the measured one, and it is not the obvious
  // one: an existing file this user cannot write answers PermissionDenied
  // *before* anything is asked about the bytes or about the directory, because
  // `QSaveFile` refuses to open such a target at all. That is the row the way
  // out of a chmod 000 quarantine dies on.
  function put(path, text) {
    // An ancestor that cannot be entered means nothing about this path can be
    // established, including whether the file is there. Measured in the VM:
    // a write into a directory at chmod 000 answers PermissionDenied, while a
    // write into one at chmod 555 -- enterable, not writable -- answers
    // Unknown. Two different codes for what looks like one situation, and the
    // plugin's message to the family turns on which it is, so the split is
    // modelled rather than smoothed over.
    if (fs._walkFails(path))
      return FileViewError.PermissionDenied

    var existing = fs.nodes[path]
    if (existing !== undefined && existing.kind === "dir")
      return FileViewError.NotAFile
    if (existing !== undefined && !fs.canWrite(existing))
      return FileViewError.PermissionDenied

    // FileView creates missing parents on write, measured on the same build,
    // which is why a fresh install needs no mkdir. A parent that exists and
    // cannot be written into is a different answer, and the measured one is
    // Unknown rather than PermissionDenied.
    var parent = fs.parentOf(path)
    var holder = fs.nodes[parent]
    if (holder === undefined) {
      fs.dirs(parent)
      holder = fs.nodes[parent]
    }
    if (holder.kind !== "dir" || !fs.canWrite(holder))
      return FileViewError.Unknown

    // `atomicWrites: true`, so a save is a rename over the old file -- and the
    // measured build copies the original's permissions onto what lands
    // (chmod 600 in, chmod 600 out). It does NOT hand back a file with
    // ordinary permissions, which is what this model used to claim and what
    // made "the way out works over a chmod 000 save" true here and false in the
    // VM. A file this write created is chmod 600.
    //
    // A write of identical bytes still raises `saved` on this build, so it is a
    // write like any other here.
    fs.nodes[path] = {
      "kind": "file",
      "text": text,
      "mode": existing === undefined ? 6 : existing.mode
    }
    fs.writes += 1
    return -1
  }
}
