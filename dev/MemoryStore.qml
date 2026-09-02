import QtQuick

// The development backing for ui/Store: the save file, held in a variable.
//
// It is the same duck-typed pair the real layer-3 store offers -- load() and
// save(object) -- so a screen cannot tell the difference, and nothing under
// dev/ or ui/ has to know how a file is written. It also keeps a counter and
// the last object written, which is what lets a test assert that a control
// actually persisted its change rather than only redrawing.
QtObject {
  id: memory

  // Seeded contents, so the harness can open a screen in a chosen state.
  property var data: null
  property int writes: 0
  property var lastWritten: null

  function load() {
    return memory.data
  }

  function save(snapshot) {
    memory.data = snapshot
    memory.lastWritten = snapshot
    memory.writes += 1
  }

  function reset() {
    memory.data = null
    memory.writes = 0
    memory.lastWritten = null
  }
}
