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
//       keys delivered to the desktop instead of the game, five struck per
//       trial, cold and warm counted separately because they differ and an
//       earlier round of this comment quoted only the warm one:
//
//                                              first summon    later summons
//                                              of a session    in that session
//         this file, window rebuilt per summon   5 of 5          5 of 5
//         this file at round 2                   1-3 of 5        0 of 5
//         this file as it stands                 0 of 5          0 of 5
//         omarchy.emojis                         5 of 5          5 of 5
//
//     Trial counts, all on the real host, all on the same oracle: ours 0 of
//     175 over 35 cold starts under the standard protocol, plus 0 of 30 over
//     6 more with the Qt pipeline and compiled-QML caches cleared first, so a
//     shell as cold as a machine that has never run the game -- 0 of 205 over
//     41 cold starts in total -- and 0 of 85 over 17 warm summons; the reference
//     50 of 50 over 10 cold starts and 80 of 80 over 16 warm ones; this file
//     with the startup warm-up taken back out again, in the same session,
//     3 of 25 over 5 cold starts. The round-2 figure "0 of 5, in 32 of 32
//     trials" was measured on a warm shell and read as if it covered both.
//

//     A key struck in that window was not dropped -- it was typed into whatever
//     application had the keyboard, a terminal in the critic's reproduction,
//     which is worse than losing it.
//
//     Keeping the surface is only half of it. The other half is that the
//     *first* full-size frame is expensive wherever it is paid, and until
//     round 3 it was paid at the child's first summon: a critic measured 12 of
//     13 first-summons-of-a-session putting 1 to 3 keys in the window
//     underneath, on the real host after every `omarchy-restart-shell`, while
//     the same shell warm leaked 0 of 50. The 1x1 surface was not the cause --
//     a full-screen-always variant leaked on its first summon too -- so it is
//     the first build and commit of the game's own scene at full size, and the
//     compositor is still routing the keyboard elsewhere while that happens.
//
//     So this file pays it at startup instead, where nobody is typing at the
//     game yet. `keepLoaded: true` means this item is constructed long before
//     it is first summoned; `warmingUp` below holds the window at full size
//     with the game rendered into it for a moment at plugin load, behind the
//     same empty input mask and with `WlrKeyboardFocus.None` throughout, then
//     lets it shrink back to one pixel. Nothing is shown -- the content is
//     rendered at an opacity of 1/255 rather than at 0, because Qt Quick skips
//     a subtree whose opacity node is fully transparent and a subtree that is
//     skipped is a subtree that was never built. Measured, same oracle, same
//     host: see the evidence file's cold-versus-warm table.
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
//     window is mapped all session, so sizing the closed surface to one pixel
//     means that if the mask ever stopped working, what it could swallow is
//     one pixel at 0,0 rather than the whole screen.
//
//     An earlier round of this comment said the empty input region could not
//     be proved with a real click, because there is no pointer-injection tool
//     in the development VM. That was true of the packaged tools and false of
//     the guest: a critic built a client for this Hyprland's
//     `zwlr_virtual_pointer_manager_v1` and injected real motion and real
//     buttons. The mask holds -- a click at (0,0) reaches the window below
//     with the mask on and is swallowed with it off -- and the hedge is
//     vindicated rather than merely argued: with the mask removed, the
//     full-screen-always variant swallows a click at (100,100) as well, which
//     is the difference between one pixel and the whole desktop.
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

  // True for a moment at plugin load, while the window is held at full size
  // with the game rendered into it so that the first expensive frame is paid
  // before any child is waiting on it. The header says why. It never makes the
  // overlay interactive: the input mask stays empty and the keyboard focus
  // stays `None` for the whole of it, and everything that reads "is the game
  // up" reads `opened`, which stays false.
  property bool warmingUp: false

  // How long the warm-up holds the window at full size *after the window is
  // actually at full size*, which is not the same moment as the plugin being
  // constructed: measured in the VM, the layer surface takes about 0.8 s from
  // `Component.onCompleted` to being mapped at all, so a plain timer from
  // construction spent most of its length on a window that had not appeared
  // yet. The timer below is restarted when the window's width first grows, so
  // this is a real window-at-full-size interval either way. It costs a
  // transparent, input-inert surface for that long, once, at shell start.
  readonly property int warmUpMs: 1500

  // 1/255. Not zero: `QSGOpacityNode` treats a fully transparent subtree as
  // blocked and never renders it, so an opacity of 0 would warm nothing. One
  // 8-bit level over a transparent window is not visible, and it is only up
  // for `warmUpMs`.
  readonly property real warmUpOpacity: 0.004

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

    // A summon during the warm-up is the real thing and takes it over, so that
    // "warming up" and "open" are never both true and nothing has to reason
    // about the pair.
    warmUp.stop()
    root.warmingUp = false
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
  // whose surface has moved twice under this file: the version this wiring was
  // first written against read parsed objects and had no quarantine, and the
  // one in the tree now reads the file's own text, quarantines, and declares
  // `writeFailed`. Every optional member is therefore looked up rather than
  // named against a type that would only be right for one of them -- which is
  // also why a comment here may not describe a Store that is not in the tree:
  // a round-2 critic caught this file's own comments describing one that had
  // not landed yet, and the safety argument in this plugin lives in its
  // comments.
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
      //
      // The Store in the tree now declares `writeFailed(string)` for exactly
      // this, and documents it as the shape this signal arrives in, so that is
      // what is called when it is there. `stopWriting(issues)` is the older
      // spelling and is still accepted: this file works with whichever Store
      // it is given rather than assuming one.
      var store = root.saveAdapter
      if (!store)
        return
      if (typeof store.writeFailed === "function")
        store.writeFailed(reason)
      else if (typeof store.stopWriting === "function")
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

  // The quarantine the Store was in the last time it said anything. A
  // quarantine that clears is the one Store transition this file has to act
  // on, and a bool is the only way to see a transition in a signal that only
  // ever says "something moved".
  property bool storeQuarantined: false

  Connections {
    target: Store
    function onChanged() {
      root.soundOn = Store.setting("sound") !== false

      // The way out of a quarantine, wired up. When the child decides through
      // Settings that the unreadable file may be replaced, the Store clears
      // its own refusal -- but `shell/FileStore.qml` has a refusal of its own,
      // set when the write failed, and it would go on refusing for the rest of
      // the session. `allowWritingAgain()` existed for this and had no caller;
      // this is the only place both halves are visible, which is the same
      // reason the format decision below lives here.
      //
      // What it does not do is write immediately: the Store's own flush runs
      // before it says anything, so it is refused, and the file layer's
      // pending payload was dropped when it stopped writing. The session
      // starts saving again from the child's next change. And because the
      // re-proof in `writeNow()` is now worn on every write over a path
      // believed absent rather than once, that next write is guarded rather
      // than taken on trust.
      var quarantined = (typeof Store.quarantined === "boolean") ? Store.quarantined : false
      if (root.storeQuarantined && !quarantined)
        saveFile.allowWritingAgain()
      root.storeQuarantined = quarantined
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
    root.storeQuarantined = (typeof Store.quarantined === "boolean") ? Store.quarantined : false

    // Pay the first full-size frame now rather than at the child's first
    // summon. See the header: this is the whole of the cold-start key leak.
    root.warmingUp = true
    warmUp.start()
  }

  property Timer warmUp: Timer {
    interval: root.warmUpMs
    repeat: false
    running: false
    onTriggered: root.warmingUp = false
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
    //
    // `warmingUp` is the third state and it is the first one that happens: at
    // plugin load the window goes to full size with the game rendered into it
    // once, so that the first full-size commit is not the one the child is
    // waiting on. Note what does *not* change with it -- the mask below stays
    // empty and `keyboardFocus` below stays `None`, both keyed on `opened`
    // alone, so a warming window is exactly as inert as a closed one.
    anchors {
      top: true
      bottom: root.opened || root.warmingUp
      left: true
      right: root.opened || root.warmingUp
    }
    implicitWidth: 1
    implicitHeight: 1

    // The warm-up is only worth anything while this window is really at full
    // size, and that lags the anchor change: the surface has to be created and
    // mapped first. Restarting the timer the moment the width grows is what
    // makes `warmUpMs` an interval of full-size rendering rather than an
    // interval that mostly elapsed before the window existed.
    onWidthChanged: {
      if (root.warmingUp && width > 1)
        root.warmUp.restart()
    }
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
      visible: root.opened || root.warmingUp
      opacity: root.opened ? 1 : root.warmUpOpacity
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
      //
      // It is also visible during the startup warm-up, at 1/255 opacity and
      // with the window's input region still empty and its keyboard focus
      // still `None`. That is the point of the warm-up: the scene under here
      // is what costs the first full-size frame, so it is the scene that has
      // to be built. `focus` follows `opened` rather than visibility, so a
      // warming key catcher never asks for the keyboard.
      visible: root.opened || root.warmingUp
      opacity: root.opened ? 1 : root.warmUpOpacity
      focus: true
      enabled: root.opened
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
