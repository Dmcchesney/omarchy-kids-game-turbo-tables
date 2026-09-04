import QtQuick

// Quickshell.Io.FileView, as much of it as `shell/FileStore.qml` uses, over the
// modelled filesystem in FakeFs.qml. See that file for what this is and is not.
//
// The two behaviours that are easy to get wrong and are load-bearing:
//
//   THE SIGNALS FIRE INSIDE `text()`. Measured with `blockLoading: true`, which
//   is what makes `FileStore.load()` able to answer with a return value at all.
//
//   A SECOND READ OF AN UNCHANGED PATH EMITS NOTHING. Also measured. It is the
//   reason `FileStore` builds a throwaway view per question instead of asking
//   its own view twice, and a model that re-answered every time would let a
//   version of that file which reuses one view pass.
QtObject {
  id: view

  property string path: ""
  property bool blockLoading: false
  property bool blockWrites: false
  property bool atomicWrites: false
  property bool printErrors: true
  property bool watchChanges: false

  // FileView's own `loaded` property is `isLoadedOrAsync` and reads true for a
  // file that could not be read at all. `shell/FileStore.qml` says in its
  // header that it never consults it; it is here so that staying true stays
  // testable.
  property bool loadedProperty: false

  signal loaded()
  signal loadFailed(int error)
  signal saved()
  signal saveFailed(int error)

  property string _answeredFor: ""
  property bool _hasAnswered: false
  property string _cached: ""

  onPathChanged: {
    view._hasAnswered = false
    view._cached = ""
  }

  function text() {
    if (view._hasAnswered && view._answeredFor === view.path)
      return view._cached          // the cached read, and no signal at all

    var answer = FakeFs.lookup(view.path)
    view._answeredFor = view.path
    view._hasAnswered = true
    view._cached = answer.text

    if (answer.outcome === -1) {
      view.loadedProperty = true
      view.loaded()
    } else {
      // True for PermissionDenied and NotAFile, false for FileNotFound: the
      // third and fourth rows of the measured table, and the reason the
      // property is not a verdict.
      view.loadedProperty = answer.outcome !== FileViewError.FileNotFound
      view.loadFailed(answer.outcome)
    }
    return answer.text
  }

  function reload() {
    view._hasAnswered = false
    view._cached = ""
  }

  // A write of identical bytes used to be modelled as raising neither signal.
  // The build that ships raises `saved` for it (vm-b9fb591.md §4.5, W9), so
  // there is no such case here any more and `put()` answers -1 or an error.
  function setText(t) {
    var outcome = FakeFs.put(view.path, t)
    if (outcome === -1) {
      view._answeredFor = view.path
      view._hasAnswered = true
      view._cached = t
      view.saved()
      return
    }
    view.saveFailed(outcome)
  }
}
