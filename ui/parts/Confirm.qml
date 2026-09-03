import QtQuick
import "../"

// The one question the settings screen asks before it throws anything away.
//
// Design, Data: the three keys of the save file are reset from three different
// places, and each of those is a door with no handle on the other side -- a
// child who clears the fact history has cleared the mastery lamps and the
// pit-lane ordering that a term of racing built up, and there is no undo
// anywhere in this plugin. So every reset asks, once, and the answer it starts
// on is KEEP.
//
// It is deliberately the only modal thing in the game. The powerup picker is a
// side panel because the race must stay visible behind it; this is the
// opposite case -- nothing else on the screen matters while the question is
// open, and a scrim that swallows every key is what makes "asks once" true
// rather than "asks once unless a stray keystroke gets past it".
FocusScope {
  id: confirm

  property string question: ""
  property string detail: ""
  property string confirmLabel: "RESET"
  property string cancelLabel: "KEEP"
  property real scaleUnit: 1.0
  // 0 is KEEP and 1 is the destructive one. It opens on KEEP every time: a
  // child holding Enter down must not be able to walk through the question.
  property int choice: 0

  signal confirmed()
  signal cancelled()

  readonly property Item focusTarget: confirm

  function px(v) { return Math.round(v * confirm.scaleUnit) }
  function fs(v) { return Math.max(8, Math.round(v * confirm.scaleUnit)) }

  function ask() {
    confirm.choice = 0
    confirm.forceActiveFocus(Qt.TabFocusReason)
  }

  Accessible.role: Accessible.Dialog
  Accessible.name: confirm.question
  Accessible.description: confirm.detail
                          + " Left and right choose, Enter answers, Escape keeps it."

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Up || event.key === Qt.Key_Down
        || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      confirm.choice = confirm.choice === 0 ? 1 : 0
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
               || event.key === Qt.Key_Space) {
      if (confirm.choice === 1)
        confirm.confirmed()
      else
        confirm.cancelled()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      confirm.cancelled()
      event.accepted = true
    } else {
      // Nothing else reaches the screen behind. While the question is open it
      // is the only thing the keyboard talks to.
      event.accepted = true
    }
  }

  // The scrim. Dark enough that the settings behind read as out of reach and
  // light enough that the child can still see which screen they are on.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.72)
  }

  Rectangle {
    id: sheet
    anchors.centerIn: parent
    width: Math.min(parent.width - confirm.px(80), confirm.px(720))
    height: column.height + confirm.px(56)
    radius: Theme.cornerRadius
    color: Theme.panelRaised
    border.width: 2
    border.color: Theme.amber

    Column {
      id: column
      x: confirm.px(32)
      y: confirm.px(28)
      width: parent.width - confirm.px(64)
      spacing: confirm.px(14)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        text: confirm.question
        color: Theme.cream
        font.family: Theme.mono
        font.bold: true
        font.pixelSize: confirm.fs(30)
        font.letterSpacing: confirm.px(2)
      }

      Text {
        textFormat: Text.PlainText
        visible: confirm.detail.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: confirm.detail
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: confirm.fs(17)
        lineHeight: 1.3
      }

      Item { width: 1; height: confirm.px(6) }

      Row {
        spacing: confirm.px(16)

        // KEEP first, and first is where the selection starts. The order is the
        // safe answer on the left, which is the way the eye reads and the way a
        // child who is not reading at all will land.
        Repeater {
          model: [ { index: 0, label: confirm.cancelLabel, tone: Theme.text },
                   { index: 1, label: confirm.confirmLabel, tone: Theme.urgent } ]

          Rectangle {
            readonly property bool chosen: confirm.choice === modelData.index
            width: confirm.px(240)
            height: confirm.px(64)
            radius: Theme.cornerRadiusSmall
            color: chosen ? Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.22)
                          : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.06)
            border.width: chosen ? 2 : 1
            border.color: chosen ? Theme.focusRing : Theme.lineStrong

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              // The chosen one carries a marker as well as the ring, so which
              // answer is armed survives a screenshot in greyscale.
              text: (parent.chosen ? "▸ " : "  ") + modelData.label
              color: parent.chosen ? Theme.textBright : Theme.textLabel
              font.family: Theme.mono
              font.bold: true
              font.pixelSize: confirm.fs(24)
              font.letterSpacing: confirm.px(2)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "◀ ▶  CHOOSE      ⏎  ANSWER      ESC  KEEP"
        color: Theme.textLabel
        font.family: Theme.mono
        font.pixelSize: confirm.fs(15)
        font.letterSpacing: confirm.px(1)
      }
    }
  }
}
