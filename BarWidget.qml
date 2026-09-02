import QtQuick

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var omarchyPath: null
  implicitWidth: 32
  implicitHeight: 32

  Text {
    anchors.centerIn: parent
    color: "#f4b740"
    font.pixelSize: 20
    text: "🏎"
    textFormat: Text.PlainText
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.shell && root.manifest && typeof root.shell.toggle === "function")
        root.shell.toggle(root.manifest.id)
    }
  }
}
