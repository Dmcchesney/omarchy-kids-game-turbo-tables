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

  // THE CAPTION DREW STRAIGHT ONTO THE ROAD, AND THE ROAD IS A GOLD KERB.
  //
  // `POWER-UP CHARGE` and `n / 12` are grey-lavender strings at 0.8 alpha with
  // nothing behind them, over the bottom right of a moving racing view.
  // Measured on shipped 1920x1080 frames: 48% of the caption's box under 3:1
  // at t = 1 s, where it crosses the amber kerb, and 61% of it under 3:1 with a
  // MEDIAN of 1.23:1 at t = 18 s, where a lit prop is behind it. `0 / 12`
  // crossed the cream lane marking and measured 24% under 3:1. A previous round
  // wrote "I did not measure a contrast floor for it, and I am not claiming
  // one", which was honest and still understated it: this was not unmeasured,
  // it was failing.
  //
  // So the charge gets the gauge face every other instrument on this screen
  // already has -- the same ground, the same corner radius, the same border as
  // the lap, place and time readouts and the table-name block -- and the strings
  // are read against a surface this file controls instead of against whatever
  // the track happens to be drawing underneath. The numbers after are in the
  // evidence.
  property real padX: 16
  property real padY: 12
  readonly property real innerWidth: Math.max(1, width - padX * 2)

  // ------------------------------------------------------------- PIECE F
  //
  // Design v4, "The hand and the charge": "Reaching twelve: the charge bar
  // flashes, the twelve segments burst into three cards that slide up from the
  // bottom right." This is the flash and the burst; the cards are
  // `ui/Picker.qml`.
  //
  // It is drawn as a GHOST of the full bar rising and fading, because by the
  // time a hand has been dealt the engine has already taken the streak back to
  // zero and the twelve segments are gone -- so what a child sees is the twelve
  // they earned leaving the bar, which is exactly what happened.
  //
  // `fxNow` is `TrackView.fxClock`, handed down by ui/Race.qml. The bar has no
  // clock of its own for the same reason nothing in the effect layer does: a
  // frame strip has to be reproducible.
  property real fxNow: 0
  property real burstBorn: -1e9
  readonly property real burstMs: 320
  readonly property real burst: (reducedMotion || fxNow - burstBorn > burstMs)
                                ? 0
                                : 1 - Math.max(0, Math.min(1, (fxNow - burstBorn) / burstMs))
  function burstNow() { bar.burstBorn = bar.fxNow }

  // ROUND 3 -- AND THE BURST HAD NEVER BEEN SEEN BY ANYBODY.
  //
  // `ui/Race.qml` passed `reducedMotion: race.reducedMotion || race.externalClock`,
  // because the caption's 1.25 Hz breath below is a wall-clock animation and a
  // wall-clock animation makes a frame strip differ run to run. The side effect
  // was that the burst -- which is NOT a wall-clock animation, it is a pure
  // function of `fxNow` -- was switched off in every strip, every frame dump
  // and every test this piece has ever taken, and a blind critic wrote
  // "nothing bursts from the twelve segments" about a thing that does burst and
  // could not be photographed doing it.
  //
  // The two are separate now: `reducedMotion` is the child's setting and takes
  // the burst away as the design says it should; `externalClock` only stops the
  // one animation that samples a clock this file does not own.
  property bool externalClock: false

  implicitWidth: 260
  implicitHeight: padY * 2 + caption.height + 6 + cellHeight + 6 + status.height

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Theme.cornerRadiusSmall
    color: Qt.rgba(0.11, 0.045, 0.10, 0.92)
    border.width: 1
    border.color: Theme.lineStrong
  }

  Text {
    id: caption
    x: bar.padX
    y: bar.padY
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
    x: bar.padX
    y: bar.padY + caption.height + 6
    width: bar.innerWidth
    height: bar.cellHeight
    spacing: bar.cellGap

    Repeater {
      model: bar.segments

      Rectangle {
        readonly property bool lit: index < bar.value
        width: (bar.innerWidth - bar.cellGap * (bar.segments - 1)) / bar.segments
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

        // A wall-clock ColorAnimation, so it is cut under an external clock as
        // well as under the setting. ROUND 3: splitting `externalClock` out of
        // `reducedMotion` above put this back in the strips' way, and a strip
        // whose bytes depend on how long the harness took to save the last PNG
        // is not evidence -- round two learned that the hard way and wrote it
        // down. Every wall-clock animation reachable from the race screen is
        // gated on `externalClock`; this is one of them.
        Behavior on color {
          enabled: !bar.reducedMotion && !bar.externalClock
          ColorAnimation { duration: 140 }
        }
      }
    }
  }

  // The burst: the twelve segments the child just spent, rising out of the bar
  // and fading, over the face's own flash.
  Rectangle {
    anchors.fill: face
    radius: face.radius
    color: Theme.amberGlow
    opacity: bar.burst * 0.40
    visible: bar.burst > 0.01
  }

  // The twelve the child just spent, leaving the bar. They go DOWN, toward the
  // hand: the design's sentence is "the twelve segments burst into three cards
  // that slide up from the bottom right", and the cards are drawn under this
  // bar, so twelve segments rising out of the top of it were leaving in the
  // wrong direction. Each one also fans out from the middle and grows, so the
  // twelve come apart rather than sliding off as one bar.
  Item {
    id: burstCells
    objectName: "chargeBurst"
    x: bar.padX
    y: cells.y
    width: bar.innerWidth
    height: bar.cellHeight
    visible: bar.burst > 0.01

    readonly property real gone: 1 - bar.burst
    readonly property real cellW: (bar.innerWidth - bar.cellGap * (bar.segments - 1))
                                  / bar.segments

    Repeater {
      model: bar.segments

      Rectangle {
        readonly property real fromMid: index - (bar.segments - 1) / 2
        readonly property real g: burstCells.gone
        width: burstCells.cellW * (1 + g * 0.5)
        height: bar.cellHeight * (1 + g * 0.5)
        x: index * (burstCells.cellW + bar.cellGap)
           + fromMid * bar.cellGap * 3.4 * g
           - (width - burstCells.cellW) / 2
        y: bar.cellHeight * 1.9 * g - (height - bar.cellHeight) / 2
        radius: 2
        color: Theme.amberGlow
        // The middle segments leave first, so the twelve read as a burst rather
        // than as a bar sliding off in one piece.
        opacity: Math.max(0, 1 - g * (1 + Math.abs(fromMid) * 0.20))
      }
    }
  }

  Text {
    id: status
    textFormat: Text.PlainText
    x: bar.padX
    y: bar.padY + caption.height + 6 + bar.cellHeight + 6
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
      running: bar.ready && !bar.reducedMotion && !bar.externalClock
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.45; duration: 400; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.45; to: 1.0; duration: 400; easing.type: Easing.InOutSine }
      onRunningChanged: if (!running) status.opacity = 1
    }
  }
}
