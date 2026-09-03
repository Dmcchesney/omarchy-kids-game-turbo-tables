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
// summons, so the garage a child left is the garage they come back to. It
// keeps the QML items; it does not keep the window's Wayland surface, which is
// a separate decision this file makes below.
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
//     for. A critic A/B'd the two forms on minimal overlays and measured no
//     difference between them: this binding is not what makes an overlay slow
//     to take the keyboard, and an earlier round of this file was wrong to say
//     it was.
//   - The layer surface is never destroyed between summons. That is the whole
//     of the handover latency, and it is worth the paragraph it takes to say
//     why.
//
//     A layer-shell compositor applies keyboard interactivity when the surface
//     commits, and a surface that has just been created cannot commit until
//     the client has a first frame to put in it. Hiding a `PanelWindow`
//     destroys its surface, so `visible: root.opened` made every summon pay
//     that cost again -- and until it was paid the compositor was still
//     sending the keyboard to whatever was underneath. Measured in the Omarchy
//     VM, three trials, `hyprctl layers` polled from before the summon:
//
//       listed -> alpha 1   this file, window rebuilt per summon  362/432/492 ms
//                           the same, with the game visible:false 331/407/410 ms
//                           omarchy.emojis                          75/72/75 ms
//
//     Those 400 ms were not spent drawing the game -- the second row is the
//     same window with nothing in it -- so it is the window and its surface,
//     not the garage's first frame, and `keepLoaded` does not help because it
//     keeps items rather than surfaces. What it cost, on the oracle that
//     matters: five keys struck the instant the summon returned, three trials,
//     counted where they landed.
//
//       keys delivered to the desktop instead of the game
//         this file, window rebuilt per summon    5 of 5, in 5 of 5 trials
//         this file as it stands                  0 of 5, in 32 of 32 trials
//         omarchy.emojis                          2 to 5 of 5, every trial
//
//     A key struck in that window was not dropped -- it was typed into whatever
//     application had the keyboard, a terminal in the critic's reproduction,
//     which is worse than losing it.
//
//     A surface that outlives the summon has to earn its keep, and the way it
//     does that is by being one pixel. While the overlay is closed the window
//     drops its bottom and right anchors and becomes a 1x1 transparent surface
//     in the top-left corner: the Wayland surface, the GL context and the
//     scene graph all stay alive -- which is the whole point -- but there is
//     no fullscreen surface sitting over the desktop for the hours a day
//     nobody is playing. `mask: Region {}` empties its input region on top of
//     that, so even that pixel takes no clicks, and `WlrKeyboardFocus.None`
//     keeps it out of the keyboard path. `hyprctl layers` reads
//     `xywh: 0 0 1 1` closed and `0 0 1920 1200` open. Measured: 0 CPU ticks
//     over 20 s closed, and the desktop takes keys exactly as before.
//
//     What the one pixel costs is the resize on open, which blocks the event
//     loop while the first fullscreen frame is built: the child's first
//     keystroke is queued rather than misdirected, and reaches the game 221 to
//     571 ms after the summon -- at the same moment the garage first appears,
//     so the first frame they see already has it applied. Leaving the surface
//     full screen all session instead removes that queue (40-114 ms) and
//     measures identically on the leak oracle; the evidence file says why the
//     pixel won anyway.
//
//     The one-pixel form is deliberate belt-and-braces. `mask: Region {}` is
//     the pattern Omarchy's own OSD uses for exactly this, and its own comment
//     says so -- but the OSD is only mapped while it is on screen, and this
//     window is mapped all session. There is no pointer-injection tool in the
//     development VM, so the empty input region could not be proved with a
//     real click; sizing the closed surface to one pixel means that if the
//     mask ever stopped working, what it could swallow is one pixel at 0,0
//     rather than the whole screen.
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
  readonly property bool gameHasFocus: game.activeFocus

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
    game.forceActiveFocus()
    if (game.focusTarget)
      game.focusTarget.forceActiveFocus(Qt.TabFocusReason)
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

    // Mapped for the life of the session, not for the length of a summon. The
    // header says why at length; the short version is that creating this
    // surface costs 400 ms in the VM and the compositor sends the child's
    // keystrokes somewhere else for every one of them.
    visible: true

    // While the overlay is closed this window must not be in anybody's way.
    // An empty layer-shell input region means the compositor never routes a
    // click to it, so the desktop underneath behaves as though it were not
    // there; `null` restores the default whole-surface region when the game
    // is up. The same pattern, and the same one-line reason, as
    // omarchy/shell/plugins/osd/Osd.qml.
    mask: root.opened ? null : closedMask
    property Region closedMask: Region {}

    // Anchored to all four edges the layer surface is the whole screen;
    // anchored to two it is `implicitWidth` by `implicitHeight`. So a closed
    // overlay is one transparent pixel in the corner and an open one is the
    // screen, and the surface itself is never destroyed in between.
    anchors {
      top: true
      bottom: root.opened
      left: true
      right: root.opened
    }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "turbo-tables"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    // The flow paints its own ground edge to edge. This is under it so that
    // a frame between the surface being mapped and the screen being laid out
    // is the game's own dark rather than the desktop showing through.
    Rectangle {
      anchors.fill: parent
      visible: root.opened
      color: Theme.ground
    }

    // Swallows every click that is not on a control. Deliberately not a
    // dismiss: the emojis overlay closes on a click outside its card because
    // it is a picker, and a seven-year-old mis-clicking in the middle of a
    // race must not lose the race. Leaving is a control on the screen and the
    // Escape key, both of which say what they do.
    MouseArea {
      anchors.fill: parent
      visible: root.opened
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: function (mouse) { mouse.accepted = true }
    }

    FocusScope {
      id: keyCatcher

      anchors.fill: parent

      // Everything inside the window is gated on `opened` rather than the
      // window itself. `visible` is also what makes an item focusable, so the
      // order in `open()` matters: `opened` is set first and `takeFocus` runs
      // on `Qt.callLater`, by which time this scope and the game under it can
      // hold focus -- measured at 35 ms from the summon, with the game
      // holding the focus, which is one frame and change.
      visible: root.opened
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
        if (!game.activeFocus)
          Qt.callLater(root.takeFocus)
      }

      onActiveFocusChanged: {
        if (!activeFocus && root.opened)
          Qt.callLater(root.takeFocus)
      }

      // The flow, and the whole game under it. `ui/Game.qml` owns which screen
      // is up -- garage, countdown, race, results, settings -- and exposes the
      // same two things the garage did: a `focusTarget` for `takeFocus` to hand
      // focus to, and a `leaveRequested` for the way out. The overlay's job
      // stops at the boundary of the surface and the keyboard, which is what it
      // always was.
      Game {
        id: game

        anchors.fill: parent
        focus: true

        // The garage's own LEAVE control and its Escape key both come out
        // here, through the flow. `dismiss` rather than `close`, because the
        // game closing itself is exactly the case the host has to be told
        // about.
        onLeaveRequested: root.dismiss()
      }
    }
  }
}
