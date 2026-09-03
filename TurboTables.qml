import QtQuick
import Quickshell
import Quickshell.Wayland
import "ui"
import "shell"

// The overlay entry point: the whole game, in one fullscreen layer-shell
// window the child summons from the bar or a keybinding.
//
// This file and BarWidget.qml and shell/ are the only three places in the
// repository allowed to name Quickshell or `qs.*`; `npm run check:boundary`
// greps every other file for those tokens and fails on a hit. Everything under
// `ui/` is written against two plain adapters -- `ui/Theme` and `ui/Store` --
// and this file is what puts a real shell behind them.
//
// ---------------------------------------------------------------------------
// THE HOST CONTRACT
// ---------------------------------------------------------------------------
//
// `omarchy-shell` loads the entry point named in manifest.json as a QML `Item`
// inside its own long-lived process, injects `shell`, `manifest` and
// `omarchyPath` if the root declares them, and calls `open(payloadJson)` and
// `close()`. `dismiss()` is the other direction: when the game closes itself,
// the host has to be told, or its toggle command goes on thinking the overlay
// is up and the next press does nothing.
//
// `keepLoaded: true` in the manifest is what keeps this item alive between
// summons, so the garage a child left is the garage they come back to.
//
// ---------------------------------------------------------------------------
// KEYBOARD, WHICH IS THE WHOLE GAME
// ---------------------------------------------------------------------------
//
// A child types for the entire race, so the keyboard has to be theirs from the
// first frame the overlay is up and the desktop's again the instant it is not.
//
//   - `WlrKeyboardFocus.Exclusive` only while `opened`, `None` otherwise. The
//     first-party emojis overlay leaves it Exclusive unconditionally and
//     relies on the window being hidden; binding it to `opened` says the same
//     thing to the compositor in as many words, and is what the design asks
//     for.
//   - `open()` puts focus on the key catcher and then hands it straight down
//     to the hosted screen's own `focusTarget`, on `Qt.callLater` so it lands
//     after the layer surface is mapped. No click is needed and none is
//     possible: a summon has no pointer event in it.
//   - The key catcher re-grabs focus if it ever loses it while open. A
//     layer-shell surface can be handed focus back by the compositor after a
//     lock screen, an OSD or a notification, and without this the child would
//     be typing at nothing with the game still on screen.
//
// One honest note about `Keys.priority: Keys.BeforeItem`, which the design
// spells out and which is set below. The design sketched the key catcher as a
// leaf that handled digits, Enter, Backspace, Space, Escape and the arrows
// itself, because at the time there was no screen under it. There is now, and
// Qt delivers a key to the focused item first and only then up the parent
// chain -- so the garage sees every key before this catcher does, which is
// exactly right: the screen that owns the control owns its keys. What this
// catcher is for is the two things a screen cannot do: closing the overlay
// when nothing under it wanted Escape, and putting focus back into the game
// when a key arrives with focus somewhere the game does not own.
Item {
  id: root

  // ------------------------------------------------------- host injection
  //
  // Defaults rather than nulls where a default is meaningful, so the overlay
  // is testable outside a shell. `manifest` legitimately has no default: a
  // plugin cannot invent its own manifest.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

  // The id the host knows us by. From the injected manifest when there is one,
  // and from the manifest's own id when there is not, because a `hide()` call
  // with an empty id leaves the host believing the overlay is still up.
  readonly property string pluginId: (manifest && manifest.id)
                                     ? String(manifest.id)
                                     : "io.github.dmcchesney.turbo-tables-solo"

  // Read by the entry-point fixture. Not chrome: it is the answer to "is the
  // keyboard actually in the game", which is the one question this file exists
  // to get right.
  readonly property bool gameHasFocus: garage.activeFocus

  // ------------------------------------------------------------- the API
  function open(payloadJson) {
    // The payload is accepted and ignored. There is nothing a caller can ask
    // this game to do differently, and a summon must not be able to fail on a
    // malformed one.
    root.opened = true
    Qt.callLater(root.takeFocus)
  }

  function close() {
    root.opened = false
    saveFile.flushNow()
  }

  function dismiss() {
    root.opened = false
    saveFile.flushNow()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  // Some hosts call `toggle` on the item rather than routing through the
  // shell; the first-party emojis overlay offers it, so this does too.
  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  function takeFocus() {
    if (!root.opened)
      return
    keyCatcher.forceActiveFocus()
    garage.forceActiveFocus()
    if (garage.focusTarget)
      garage.focusTarget.forceActiveFocus(Qt.TabFocusReason)
  }

  // The save adapter, held untyped on purpose. `ui/Store` is a plain adapter
  // whose surface is still moving: the version in the tree today reads parsed
  // objects and has no quarantine, and the reviewed replacement reads the
  // file's own text and does. This file works with either and asks which it
  // has rather than assuming, so the two optional members below are looked up
  // rather than named against a type that would only be right for one of them.
  readonly property var saveAdapter: Store

  // ------------------------------------------------------------ the theme
  ThemeBridge { id: themeBridge }

  // ------------------------------------------------------- the save file
  //
  // One JSON file under the child's data directory, and the only thing this
  // plugin reads or writes. See shell/FileStore.qml for the rule it keeps.
  FileStore {
    id: saveFile
    onWriteFailed: function (reason) {
      // A FileView reports a failed write by signal, so the Store's own `try`
      // around `save()` never sees it and has to be told, or it would keep
      // handing changes to a file that is not taking them.
      var store = root.saveAdapter
      if (store && typeof store.stopWriting === "function")
        store.stopWriting([{ "path": "", "problem": reason }])
    }
  }

  // ----------------------------------------------------------------- sound
  AudioLoader {
    id: audio
    enabled: root.soundOn
  }

  // `Store.setting()` is a function, so it cannot be bound to; the Store
  // raises `changed()` whenever anything it holds moves, which can be.
  property bool soundOn: true

  Connections {
    target: Store
    function onChanged() {
      root.soundOn = Store.setting("sound") !== false
    }
  }

  Component.onCompleted: {
    // Which protocol to speak to the Store in. A Store that can read the
    // file's own text says so by offering `backendFormat()`; one that cannot
    // gets parsed objects instead. Guessing here is not a harmless mismatch:
    // an object-protocol Store handed a string reads it as "not an object",
    // adopts the defaults, and writes them over the child's file on the next
    // keystroke. The wiring is the only place both halves are visible.
    var store = root.saveAdapter
    saveFile.format = (store && typeof store.backendFormat === "function") ? "text" : "object"

    // Assigning the backend makes the Store read the file, and a file it
    // cannot read is a thrown error by design -- the Store above turns that
    // into a quarantine, and a Store that does not catch it leaves `loaded`
    // false, which refuses every write. Both outcomes keep the file. Neither
    // may take the overlay down with it.
    try {
      Store.backend = saveFile
    } catch (error) {
      console.warn("TurboTables: the save file was not read and will not be written this"
                   + " session: " + error)
    }

    root.soundOn = Store.setting("sound") !== false
  }

  Component.onDestruction: saveFile.flushNow()

  // ----------------------------------------------------------- the window
  PanelWindow {
    id: panel

    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "turbo-tables"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    // The garage paints its own ground edge to edge. This is under it so that
    // a frame between the surface being mapped and the screen being laid out
    // is the game's own dark rather than the desktop showing through.
    Rectangle {
      anchors.fill: parent
      color: Theme.ground
    }

    // Swallows every click that is not on a control. Deliberately not a
    // dismiss: the emojis overlay closes on a click outside its card because
    // it is a picker, and a seven-year-old mis-clicking in the middle of a
    // race must not lose the race. Leaving is a control on the screen and the
    // Escape key, both of which say what they do.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: function (mouse) { mouse.accepted = true }
    }

    FocusScope {
      id: keyCatcher

      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem

      Keys.onPressed: function (event) {
        // A key only reaches here when the focused control under it did not
        // want it.
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
          return
        }
        // Anything else means focus is somewhere the game does not own -- so
        // put it back, and let this key go by unaccepted rather than
        // swallowing it. The next one lands in the game.
        if (!garage.activeFocus)
          Qt.callLater(root.takeFocus)
      }

      onActiveFocusChanged: {
        if (!activeFocus && root.opened)
          Qt.callLater(root.takeFocus)
      }

      Garage {
        id: garage

        anchors.fill: parent
        focus: true

        // The garage's own LEAVE control and its Escape key both come out
        // here. `dismiss` rather than `close`, because the game closing itself
        // is exactly the case the host has to be told about.
        onLeaveRequested: root.dismiss()

        // READY starts a race. The race screen and the screen flow that owns
        // the handover are another piece's work and are landing in `ui/` while
        // this is written, so this overlay hosts the garage and nothing else:
        // when the flow exists, the screen is loaded here and handed the same
        // `focusTarget` treatment `takeFocus` already gives the garage, and
        // that is the whole of the change. Nothing is stubbed in its place --
        // a screen that pretends to start a race and does not is worse than a
        // control that is honestly not wired yet.
        onRaceRequested: {}
      }
    }
  }
}
