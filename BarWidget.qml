import QtQuick
import qs.Commons

// The kart button in the bar. Its only job is to toggle the overlay.
//
// It exists because there is no manifest mechanism for registering a
// keybinding or a launcher entry, and a child needs something to click. The
// README gives parents the keybinding line as well; this is the same action
// with a mark on it.
//
// ---------------------------------------------------------------------------
// THE BAR'S CONTRACT
// ---------------------------------------------------------------------------
//
// The bar host injects exactly three properties into a widget slot -- `bar`,
// `moduleName` and `settings` -- and it does not inject `shell` or `manifest`,
// which is why the id below has a fallback and why the toggle goes through
// `bar.shell`.
//
// Clicks are not delivered by the widget's own mouse area in the real bar. The
// bar covers every slot with one pointer handler so it can drag modules
// around, and dispatches a real click by calling `triggerPress(button)` on the
// nearest registered click target, falling back to the slot's own item. So
// this widget declares `triggerPress`, plus the `interactive`, `pressable` and
// `concealed` flags the bar reads before it will dispatch to it at all. The
// MouseArea underneath is for hosts that do not do that -- the entry-point
// fixture, a plain window -- and cannot double-fire, because the bar's own
// handler accepts the event whenever it found a target.
//
// The design's rule this widget is written against: the plugin starts nothing,
// runs no shell command, and ships no helper script. The first-party menu
// widget toggles itself by handing an `omarchy-shell shell toggle ...` line to
// `bar.run()`; this one calls the shell object the bar is already holding, so
// the plugin never composes a command line at all. `fakeBar.run()` in the
// entry-point fixture fails the test if anything here ever does.
Item {
  id: root

  // ------------------------------------------------- injected by the bar
  //
  // `bar` is untyped because it genuinely is: the bar host is a plugin like
  // this one and a third-party widget has no type for it, only the documented
  // set of members it offers. Every use below is guarded.
  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  // ------------------------------- injected by the entry-point fixture and
  // by hosts that inject the plugin contract into every kind
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  // ----------------------------------- the flags the bar reads before it
  // will dispatch a click here at all
  property bool interactive: true
  property bool pressable: true
  property bool concealed: false
  property string tooltipText: "Turbo Tables"

  readonly property string pluginId: {
    if (manifest && manifest.id)
      return String(manifest.id)
    if (moduleName.length > 0)
      return moduleName
    return "io.github.dmcchesney.turbo-tables-solo"
  }

  // The shell object, from wherever this host puts it.
  readonly property var shellObject: {
    if (root.shell)
      return root.shell
    if (root.bar && root.bar.shell)
      return root.bar.shell
    return null
  }

  readonly property bool canToggle: shellObject !== null
                                    && typeof shellObject.toggle === "function"

  // ------------------------------------------------------------ geometry
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property int pad: Style.space(7)
  readonly property color foreground: bar ? bar.barForeground : Color.bar.text

  implicitWidth: vertical ? barSize : kart.width + pad * 2
  implicitHeight: vertical ? kart.height + pad * 2 : barSize

  // ------------------------------------------------------------- the act
  function triggerPress(button) {
    if (button !== undefined && button !== Qt.LeftButton)
      return
    root.toggleOverlay()
  }

  function toggleOverlay() {
    if (!root.canToggle) {
      console.warn("TurboTables BarWidget: the bar did not hand this widget a shell, so the"
                   + " kart button cannot open the garage. The keybinding in the README still"
                   + " works.")
      return false
    }
    root.shellObject.toggle(root.pluginId, "{}")
    return true
  }

  // --------------------------------------------------------------- the mark
  //
  // Drawn rather than typed. A glyph would depend on the child's bar font
  // carrying a kart in it, and the one thing this button must never be is
  // absent: it is the only way in for a child who cannot use a keybinding.
  // Two boxes and two wheels at bar size read as a car and cost nothing.
  Item {
    id: kart

    anchors.centerIn: parent
    width: Style.space(18)
    height: Style.space(12)
    opacity: root.concealed ? 0 : (pointer.containsMouse ? 1 : 0.85)

    readonly property real wheel: Math.max(2, Math.round(height * 0.5))

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Cabin, set back from the nose the way a single-seater's is.
    Rectangle {
      x: Math.round(kart.width * 0.24)
      width: Math.round(kart.width * 0.42)
      y: 0
      height: Math.round(kart.height * 0.40)
      radius: Math.max(1, Style.space(2))
      color: root.foreground
    }

    // Body.
    Rectangle {
      x: 0
      width: kart.width
      y: Math.round(kart.height * 0.34)
      height: Math.round(kart.height * 0.32)
      radius: Math.max(1, Style.space(2))
      color: root.foreground
    }

    // Wheels, overlapping the body so they read as wheels under a car rather
    // than as legs under a bench.
    Rectangle {
      x: Math.round(kart.width * 0.10)
      y: kart.height - kart.wheel
      width: kart.wheel
      height: kart.wheel
      radius: width / 2
      color: root.foreground
    }

    Rectangle {
      x: Math.round(kart.width * 0.90) - kart.wheel
      y: kart.height - kart.wheel
      width: kart.wheel
      height: kart.wheel
      radius: width / 2
      color: root.foreground
    }
  }

  MouseArea {
    id: pointer

    anchors.fill: parent
    enabled: root.interactive && !root.concealed
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor

    onEntered: if (root.bar && typeof root.bar.showTooltip === "function")
      root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar && typeof root.bar.hideTooltip === "function")
      root.bar.hideTooltip(root)

    onClicked: function (mouse) {
      if (root.pressable)
        root.triggerPress(mouse.button)
      mouse.accepted = true
    }
  }

  onVisibleChanged: if (!visible && root.bar && typeof root.bar.hideTooltip === "function")
    root.bar.hideTooltip(root)
}
