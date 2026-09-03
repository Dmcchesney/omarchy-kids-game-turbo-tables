import QtQuick
import "../"

// The streak charge: twelve segments, glowing from nine, reading POWER-UP
// READY at twelve.
//
// Design, Streaks and the powerup hand: "The charge bar has twelve segments,
// glows from nine, and reads POWER-UP READY at twelve." The threshold is a
// single constant the engine owns, so both numbers are properties here and
// neither is spelled into the drawing.
//
// A lit segment is filled and an unlit one is an outline, so the bar is
// readable without colour, which is the design's accessibility rule.
Item {
  id: bar

  property int value: 0
  property int segments: 12
  property int glowFrom: 9
  property bool reducedMotion: false
  property int cellHeight: 26
  property real cellGap: 4
  property string title: "POWER-UP CHARGE"
  property int titleSize: 14
  property bool holdingHand: false

  readonly property bool ready: value >= segments
  readonly property bool glowing: value >= glowFrom
  readonly property color tone: ready ? Theme.amberGlow : (glowing ? Theme.amber : Theme.teal)

  implicitWidth: 260
  implicitHeight: caption.height + 6 + cellHeight + 6 + status.height

  Text {
    id: caption
    textFormat: Text.PlainText
    text: bar.title
    color: Theme.textLabel
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: bar.titleSize
    font.letterSpacing: 2
  }

  Row {
    id: cells
    y: caption.height + 6
    width: bar.width
    height: bar.cellHeight
    spacing: bar.cellGap

    Repeater {
      model: bar.segments

      Rectangle {
        readonly property bool lit: index < bar.value
        width: (bar.width - bar.cellGap * (bar.segments - 1)) / bar.segments
        height: bar.cellHeight
        radius: 2
        color: lit ? bar.tone : "transparent"
        border.width: lit ? 0 : 1
        border.color: Theme.lineStrong

        // The last lit segment carries a brighter cap, so the bar has a head
        // and a child can see it move by one without counting.
        Rectangle {
          visible: parent.lit && index === bar.value - 1
          anchors.fill: parent
          radius: 2
          color: Qt.rgba(1, 1, 1, 0.30)
        }

        Behavior on color {
          enabled: !bar.reducedMotion
          ColorAnimation { duration: 140 }
        }
      }
    }
  }

  Text {
    id: status
    textFormat: Text.PlainText
    y: caption.height + 6 + bar.cellHeight + 6
    text: bar.ready ? (bar.holdingHand ? "HAND HELD  ·  " + bar.value : "POWER-UP READY")
                    : (bar.value + " / " + bar.segments)
    color: bar.ready ? Theme.amberGlow : Theme.textLabel
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: bar.titleSize
    font.letterSpacing: 2

    // Design, Accessibility: "nothing flashes faster than 3 Hz". This is a
    // 1.25 Hz breath, and reduced motion removes it entirely.
    SequentialAnimation on opacity {
      running: bar.ready && !bar.reducedMotion
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.45; duration: 400; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.45; to: 1.0; duration: 400; easing.type: Easing.InOutSine }
      onRunningChanged: if (!running) status.opacity = 1
    }
  }
}
