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

  // ------------------------------------------------------------- PIECE F
  //
  // Two HUD echoes from design v4's "Power-up feel", and both of them are a
  // number this item is handed rather than a state it keeps.
  //
  //   `chase`   1 at the start of a boost's lamp chase and 0 at its end, with
  //             `chaseCount` lamps in the wave. Nitro lights "the four next lap
  //             lamps ... in a chase left to right"; Turbo does ten in 500 ms.
  //             The wave runs over the lamps AFTER `lit`, because those are the
  //             ones the boost has just paid for -- the engine has already
  //             lowered `questionsNeededThisLap`, so the lamps the child no
  //             longer owes are the ones that light up and go out.
  //   `rattle`  1 at the moment of a hit and 0 when it has settled. "the extra
  //             lap lamps you now owe appear as dark lamps added to the row
  //             with a rattle": the lamps themselves arrive because `total`
  //             went up, and this is the rattle.
  //
  // Both are driven from `TrackView`'s effect clock, so the row shakes on the
  // same frame the road does and a frame strip catches them together. Reduced
  // motion takes the rattle out (it is a shake) and keeps the chase (it is a
  // lamp change, which is the design's named substitute).
  property real chase: 0
  property int chaseCount: 0
  property real rattle: 0
  property bool reducedMotion: false

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

      // An Item that holds the row's place and a lamp inside it that can be
      // jogged out of place. The lamp used to BE the row's child, and a `Row`
      // sets its children's `x` -- so a rattle written on the lamp itself was
      // fighting the layout for the same property, which is a binding loop
      // dressed as an animation.
      Item {
        readonly property bool on: index < lamps.lit
        readonly property bool extra: index >= lamps.cleanTotal
        // Where the chase wave has reached, in lamps past `lit`. The lamp is in
        // the wave while the front is on it and has not passed it by more than
        // one and a half lamps, which is what makes it a chase rather than a
        // block of light switching on.
        readonly property real front: (1 - lamps.chase) * (lamps.chaseCount + 2)
        readonly property real fromLit: index - lamps.lit
        readonly property bool chasing: lamps.chase > 0 && fromLit >= 0
                                        && fromLit < lamps.chaseCount
                                        && front >= fromLit && front < fromLit + 1.6
        readonly property bool shaking: !lamps.reducedMotion && extra && lamps.rattle > 0
        width: lamps.cell
        height: lamps.cell

        Rectangle {
          width: lamps.cell
          height: lamps.cell
          radius: 2
          color: parent.chasing ? Theme.cream
                                : (parent.on ? (parent.extra ? lamps.extraTone : lamps.tone)
                                             : "transparent")
          border.width: (parent.on || parent.chasing) ? 0 : 1
          border.color: parent.extra
                        ? Qt.rgba(lamps.extraTone.r, lamps.extraTone.g, lamps.extraTone.b, 0.55)
                        : Theme.lineStrong
          // The rattle, on the lamps a hit added and on no others: the row does
          // not move, the new debt does. Deterministic in `index`, so a frame
          // strip catches the same jitter on every run.
          x: parent.shaking
             ? Math.round(Math.sin(lamps.rattle * 22 + index * 1.7) * lamps.rattle * lamps.cell * 0.30)
             : 0
          y: parent.shaking
             ? Math.round(Math.cos(lamps.rattle * 27 + index * 2.1) * lamps.rattle * lamps.cell * 0.22)
             : 0
        }
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
