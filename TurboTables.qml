import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var omarchyPath: null
  property bool opened: false

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && root.manifest && typeof root.shell.hide === "function")
      root.shell.hide(root.manifest.id)
  }

  PanelWindow {
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "#ee11141a"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "turbo-tables"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.dismiss()
      onActiveFocusChanged: {
        if (!activeFocus && root.opened)
          Qt.callLater(forceActiveFocus)
      }

      Column {
        anchors.centerIn: parent
        spacing: 16

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          color: "#f4b740"
          font.bold: true
          font.pixelSize: 42
          text: "TURBO TABLES"
          textFormat: Text.PlainText
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          color: "#f4f1e8"
          font.pixelSize: 20
          text: "Garage systems are online."
          textFormat: Text.PlainText
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          color: "#a8adb7"
          font.pixelSize: 15
          text: "Press Escape to close"
          textFormat: Text.PlainText
        }
      }
    }
  }
}
