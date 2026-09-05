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

  // PIECE F ROUND 2 -- THE HOLD, ON WHICHEVER CLOCK THE CALLER IS USING.
  //
  // The 1.6 s hold was a `Timer`, which is the WALL clock, and a frame strip
  // steps a clock of its own -- so whether a callout was still on screen at
  // frame 18 depended on how long the harness had taken to save seventeen
  // PNGs. Two runs of the eighteen strips came back with fifty-nine files
  // differing, all of them in the callout stack's box and all of them on late
  // frames. A strip that differs run to run is not evidence.
  //
  // With `fxNow` set (in milliseconds, by the caller) the hold is measured on
  // that clock instead and the Timer never runs. Left at -1, which is what the
  // garage and a real race use, nothing about this file changes.
  property real fxNow: -1
  readonly property bool external: fxNow >= 0
  property real bornAt: -1e9

  readonly property bool showing: external ? fade.opacity > 0
                                           : (hold.running || fade.opacity > 0)

  function say(message, colour) {
    callout.text = message
    if (colour !== undefined)
      callout.tone = colour
    fade.opacity = 1
    callout.bornAt = callout.fxNow
    if (!callout.external)
      hold.restart()
  }

  onFxNowChanged: {
    if (callout.external && fade.opacity > 0
        && callout.fxNow - callout.bornAt > callout.holdMs)
      fade.opacity = 0
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
