import QtQuick
import QtTest

// PIECE M. REAL SYNTHETIC MOUSE AND KEY EVENTS, HEADLESS, FROM A PLAIN `qml`
// PROCESS.
//
// The gate for the mouse piece is "a harness run that drives every screen by
// synthetic clicks alone, and one that drives it by keys alone, reaching the
// same states". `dev/Harness.qml` could already press Tab in the only way a
// plain QML process can -- by calling the same `moveFocus()` its Tab handler
// calls, which the harness itself is careful to say is one call SHORT of the
// key. That is not good enough for this piece: the whole finding is that
// controls were never wired to the pointer at all, and a "click" synthesised by
// calling the handler directly would prove nothing about whether a MouseArea
// exists, is on top, is enabled, or is the right size.
//
// `QtTest`'s event functions post REAL `QMouseEvent`s and `QKeyEvent`s into the
// window's delivery agent -- the same path a hand on a mouse takes -- and they
// work outside `qmltestrunner`: a `TestCase` with `when: false` never runs as a
// test and its `mouseClick`, `mouseMove` and `keyClick` are ordinary callable
// functions. Verified on this Mac under `-platform offscreen`: `containsMouse`
// goes false -> true -> false as the pointer is moved onto and off a 80x40
// rectangle, and the click lands.
//
// WHY IT IS ITS OWN FILE. `import QtTest` at the top of `dev/Harness.qml` would
// make every harness run in this repository -- every screenshot every other
// piece takes -- depend on the QtTest QML module being installed. It is loaded
// through a `Loader` that is only active when a drive is actually asked for, so
// a `--shot` run neither imports it nor pays for it.
//
// It is in `dev/`, which `src/tools/scope.ts` records as not the plugin: this
// file is never loaded by `TurboTables.qml` and never runs on a child's
// machine.
Item {
  id: pointer

  // The window's content item. Every coordinate below is in ITS space, which is
  // the same space `--dump-rects` prints boxes in, so a drive script and the
  // enumeration are talking about the same pixels.
  property Item root: null

  TestCase {
    id: events
    name: "turboTablesHarnessInput"
    // Never collected as a test, never run by anything. The functions are what
    // this is for.
    when: false
  }

  function moveTo(x, y) {
    events.mouseMove(pointer.root, x, y)
  }

  // A click is a move first, always. A press delivered to a window whose
  // pointer has never been anywhere leaves `containsMouse` false on the way in,
  // and a hover state that is only true for the duration of the press is not
  // the hover state a child sees.
  function clickAt(x, y) {
    events.mouseMove(pointer.root, x, y)
    events.mouseClick(pointer.root, x, y)
  }

  function pressKey(code, modifiers) {
    events.keyClick(code, modifiers === undefined ? Qt.NoModifier : modifiers)
  }
}
