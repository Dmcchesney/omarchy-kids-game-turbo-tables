import QtQuick
import "../"

// The lap's questions, as lamps.
//
// Design, The answer loop 3: on a correct answer "the lap lamp for that
// question lights". Twelve lamps is a clean lap; an attack raises the lap's
// requirement above twelve and the extra lamps appear in the design's hazard
// colour, so a child can see the shape of what a Pile-Up did without being
// told a number. A boost lowers the requirement and the lamps beyond it go
// out, which is the same picture in reverse.
//
// Lit is filled, unlit is an outline, so the row reads without colour.
Item {
  id: lamps

  property int lit: 0
  property int total: 12
  // The lap's requirement before anything landed on it. Lamps past this one
  // were added by an attack.
  property int cleanTotal: 12
  property color tone: Theme.amber
  property color extraTone: Theme.hazard
  property real cell: 12
  property real gap: 3
  // Past about twenty lamps the row is wider than the HUD corner it lives in,
  // so it collapses to a count instead of running off the screen.
  property int maxCells: 20

  readonly property int shown: Math.min(total, maxCells)
  readonly property bool collapsed: total > maxCells

  implicitWidth: collapsed
                 ? overflow.implicitWidth
                 : shown * cell + Math.max(0, shown - 1) * gap
  implicitHeight: cell

  Row {
    visible: !lamps.collapsed
    spacing: lamps.gap

    Repeater {
      model: lamps.collapsed ? 0 : lamps.shown

      Rectangle {
        readonly property bool on: index < lamps.lit
        readonly property bool extra: index >= lamps.cleanTotal
        width: lamps.cell
        height: lamps.cell
        radius: 2
        color: on ? (extra ? lamps.extraTone : lamps.tone) : "transparent"
        border.width: on ? 0 : 1
        border.color: extra ? Qt.rgba(lamps.extraTone.r, lamps.extraTone.g, lamps.extraTone.b, 0.55)
                            : Theme.lineStrong
      }
    }
  }

  Text {
    id: overflow
    visible: lamps.collapsed
    textFormat: Text.PlainText
    text: lamps.lit + " / " + lamps.total
    color: lamps.total > lamps.cleanTotal ? lamps.extraTone : Theme.textLabel
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: Math.max(9, Math.round(lamps.cell * 1.05))
    font.letterSpacing: 1
  }
}
