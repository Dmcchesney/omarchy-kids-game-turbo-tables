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
            id: answer
            readonly property bool chosen: confirm.choice === modelData.index
            width: confirm.px(240)
            height: confirm.px(64)
            radius: Theme.cornerRadiusSmall
            color: chosen ? Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.22)
                          : (answerHit.hovered
                             ? Theme.hoverFill
                             : Qt.rgba(Theme.menuBorder.r, Theme.menuBorder.g, Theme.menuBorder.b, 0.06))
            border.width: chosen ? 2 : 1
            border.color: chosen ? Theme.focusRing
                                 : (answerHit.hovered ? Theme.hoverRing : Theme.lineStrong)

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

            // PIECE M. Named as a button, not only drawn as one. The parity
            // walk finds controls the click list might have missed by reading
            // `Accessible.role`, so a control that is silent there is invisible
            // to the very check that would catch it being forgotten -- and
            // these two were silent: the dialog announced itself and its two
            // answers did not.
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label + (answer.chosen ? ", chosen" : "")
            Accessible.description: confirm.question + " " + confirm.detail
            Accessible.onPressAction: answerHit.acted()

            // PIECE M -- A CLICK ON AN ANSWER IS THE ANSWER, AND ONLY ITS OWN.
            //
            // The keyboard reaches this dialog in two presses: an arrow to arm
            // the answer, then Enter to give it. A click is one press, and the
            // one press has to be unambiguous, so it arms the answer it landed
            // on and gives THAT one. It cannot give the other. Round-one
            // thinking here was to have a click arm and a second click confirm,
            // which is the shape every child has learned means "this is a
            // button that needs pressing twice" and is the shape nothing else
            // in this game has.
            //
            // This is the one modal in the game and there is no undo behind it,
            // so the safe answer is on the left, is where the selection starts,
            // and is where the pointer's own reading order lands first.
            Clickable {
              id: answerHit
              objectName: "clickConfirmAnswer"
              stop: confirm
              label: modelData.label
              does: "answer " + modelData.label
              key: "Left, Right, then Enter"
              onActed: {
                confirm.choice = modelData.index
                if (modelData.index === 1)
                  confirm.confirmed()
                else
                  confirm.cancelled()
              }
            }
          }
        }
      }

      // PIECE M ROUND 2. The same three groups, each one a control.
      //
      // This line printed the dialog's keyboard in the idiom the race screen
      // makes clickable, and it was paint -- and `ESC  KEEP` is the sentence a
      // child reads when they want out of a question they did not mean to open.
      // Each group now does what it says: CHOOSE moves the armed answer the way
      // the arrows do, ANSWER gives the armed one the way Enter does, KEEP is
      // Escape. ANSWER is marked destructive, so a double-click cannot answer
      // twice, and it can only ever give the answer that is already armed and
      // marked `▸` on screen -- which starts, every time, on KEEP.
      Flow {
        width: parent.width
        spacing: confirm.px(20)

        KeyHint {
          keys: "◀ ▶"
          action: "CHOOSE"
          textSize: confirm.fs(15)
          letterSpacing: confirm.px(1)
          bold: false
          padWidth: confirm.px(14)
          padHeight: confirm.px(8)
          name: "Choose the other answer"
          does: "arm the other answer"
          key: "Left, Right"
          help: "Moves to the other answer. Left and right do it too."
          onTapped: confirm.choice = confirm.choice === 0 ? 1 : 0
        }
        KeyHint {
          keys: "⏎"
          action: "ANSWER"
          textSize: confirm.fs(15)
          letterSpacing: confirm.px(1)
          bold: false
          padWidth: confirm.px(14)
          padHeight: confirm.px(8)
          name: "Give the armed answer"
          does: "answer " + (confirm.choice === 1 ? confirm.confirmLabel
                                                  : confirm.cancelLabel)
          key: "Enter"
          destructive: true
          help: "Gives the answer marked with the arrow, which is "
                + (confirm.choice === 1 ? confirm.confirmLabel : confirm.cancelLabel)
                + ". Enter does it too."
          onTapped: {
            if (confirm.choice === 1)
              confirm.confirmed()
            else
              confirm.cancelled()
          }
        }
        KeyHint {
          keys: "ESC"
          action: confirm.cancelLabel
          textSize: confirm.fs(15)
          letterSpacing: confirm.px(1)
          bold: false
          padWidth: confirm.px(14)
          padHeight: confirm.px(8)
          name: "Keep it"
          does: "answer " + confirm.cancelLabel
          key: "Escape"
          help: "Keeps everything and closes the question. Escape does it too."
          onTapped: confirm.cancelled()
        }
      }
    }
  }
}
