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
// way its own header records Quickshell 0.3.1 answering them, measured in the
// VM by two previous rounds:
//
//   missing file                        text() == ""        loadFailed(FileNotFound=2)
//   readable file                       text() == contents  loaded()
//   file, chmod 000                     text() == ""        loadFailed(PermissionDenied)
//   a directory                         text() == ""        loadFailed(NotAFile=4)
//   file inside a chmod 000 directory   loadFailed(FileNotFound=2)
//   file inside a chmod 666 directory   loadFailed(FileNotFound=2)
//   `<dir>/.` for a traversable dir     loadFailed(NotAFile=4)
//   `<dir>/.` for chmod 666             loadFailed(FileNotFound=2)
//   an unchanged second read            no signal at all
//   an unchanged write                  neither saved nor saveFailed
//   a write with missing parents        the parents are created
//
// Where this model is wrong about Quickshell, the tests built on it are wrong,
// and no run of it can replace the VM. What it can do is hold the whole of
// `shell/FileStore.qml` -- the real file, loaded from its own path -- against
// those answers on a machine that has no Quickshell, every time the suite runs.
//
// Modes are named the way the VM scenarios name them rather than as bits:
// a directory is `traversable` (+x, which is what a path component needs) and
// `readable` separately, because chmod 111 and chmod 666 are exactly the pair
// that told a previous round its absence proof was real.
QtObject {
  id: fs

  // path -> { "kind": "file"|"dir", "text": string, "readable": bool,
  //           "traversable": bool, "writable": bool }
  property var nodes: ({})
  property int writes: 0
  property int reads: 0

  function clear() {
    fs.nodes = {}
    fs.writes = 0
    fs.reads = 0
  }

  function dir(path, options) {
    var o = options === undefined ? {} : options
    fs.nodes[path] = {
      "kind": "dir",
      "text": "",
      "readable": o.readable !== false,
      "traversable": o.traversable !== false,
      "writable": o.writable !== false
    }
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

  function file(path, text, options) {
    var o = options === undefined ? {} : options
    fs.dirs(fs.parentOf(path))
    fs.nodes[path] = {
      "kind": "file",
      "text": text,
      "readable": o.readable !== false,
      "traversable": false,
      "writable": o.writable !== false
    }
  }

  function remove(path) { delete fs.nodes[path] }

  function textAt(path) {
    var node = fs.nodes[path]
    return (node === undefined || node.kind !== "file") ? null : node.text
  }

  function chmod(path, options) {
    var node = fs.nodes[path]
    if (node === undefined)
      return
    if (options.readable !== undefined) node.readable = options.readable
    if (options.traversable !== undefined) node.traversable = options.traversable
    if (options.writable !== undefined) node.writable = options.writable
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
      if (node === undefined || node.kind !== "dir" || !node.traversable)
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
      if (asksToEnter && !node.traversable)
        return { "outcome": FileViewError.FileNotFound, "text": "" }
      return { "outcome": FileViewError.NotAFile, "text": "" }
    }

    if (asksToEnter)
      return { "outcome": FileViewError.FileNotFound, "text": "" }
    if (!node.readable)
      return { "outcome": FileViewError.PermissionDenied, "text": "" }
    return { "outcome": -1, "text": node.text }
  }

  // What a write of `path` produces. `outcome` -1 wrote, -2 wrote nothing
  // because nothing had changed (which raises neither signal on the real one),
  // and anything >= 0 is a FileViewError.
  function put(path, text) {
    if (fs._walkFails(path))
      return FileViewError.PermissionDenied

    var existing = fs.nodes[path]
    if (existing !== undefined && existing.kind === "dir")
      return FileViewError.NotAFile
    if (existing !== undefined && existing.kind === "file" && existing.text === text)
      return -2
    if (existing !== undefined && !existing.writable)
      return FileViewError.PermissionDenied

    // FileView creates missing parents on write, measured on the same build,
    // which is why a fresh install needs no mkdir. A parent that exists and
    // cannot be written to is a different answer.
    var parent = fs.parentOf(path)
    var holder = fs.nodes[parent]
    if (holder === undefined) {
      fs.dirs(parent)
      holder = fs.nodes[parent]
    }
    if (holder.kind !== "dir" || !holder.writable)
      return FileViewError.PermissionDenied

    // `atomicWrites: true`, so a save is a rename over the old file: what lands
    // is a new file with ordinary permissions, not the old one edited. That is
    // why replacing a save file nobody could read leaves one that can be read,
    // and it is the difference between the way out working and the way out
    // needing a terminal.
    fs.nodes[path] = {
      "kind": "file",
      "text": text,
      "readable": true,
      "traversable": false,
      "writable": existing === undefined ? true : existing.writable
    }
    fs.writes += 1
    return -1
  }
}
