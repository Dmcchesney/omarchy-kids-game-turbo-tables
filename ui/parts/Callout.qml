import QtQuick
import "../"

// The 1.6 second callout the design specifies for the race view, used in the
// garage for the two messages that have nowhere else to live: the preview of
// a preset signal, and the reason the RACE A FRIEND tile is not available.
//
// Reduced motion is honoured here rather than at the call site: with it on,
// the callout cuts in and out instead of sliding and fading.
Item {
  id: callout

  property string text: ""
  property color tone: Theme.amber
  property int holdMs: 1600
  property bool reducedMotion: false
  // PIECE F. Design v4, Pile-Up: "the callout is in the large type reserved for
  // this card." One card in the game sets this, and the size below is the only
  // thing it changes -- the ground, the rule and the hold are the same, so a
  // legendary card reads as the same object shouted rather than as a different
  // object.
  property bool big: false
  readonly property bool showing: hold.running || fade.opacity > 0

  function say(message, colour) {
    callout.text = message
    if (colour !== undefined)
      callout.tone = colour
    fade.opacity = 1
    hold.restart()
  }

  implicitWidth: fade.implicitWidth
  implicitHeight: fade.implicitHeight
  visible: fade.opacity > 0

  Timer {
    id: hold
    interval: callout.holdMs
    onTriggered: fade.opacity = 0
  }

  Rectangle {
    id: fade
    anchors.fill: parent
    opacity: 0
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(Theme.panelRaised.r, Theme.panelRaised.g, Theme.panelRaised.b, 0.96)
    border.width: callout.big ? 3 : 1
    border.color: callout.tone
    implicitWidth: message.implicitWidth + message.font.pixelSize * 2.2
    implicitHeight: message.implicitHeight + message.font.pixelSize * 1.2

    Behavior on opacity {
      enabled: !callout.reducedMotion
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Rectangle {
      width: parent.width
      height: 2
      anchors.bottom: parent.bottom
      color: callout.tone
      radius: 1
    }

    Text {
      id: message
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: callout.text
      color: Theme.textBright
      font.family: Theme.mono
      font.bold: true
      font.pixelSize: Math.max(10, Math.round(callout.height * (callout.big ? 0.56 : 0.34)))
      font.letterSpacing: 1
    }
  }
}
