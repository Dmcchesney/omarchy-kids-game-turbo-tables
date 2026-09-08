import QtQuick

// A soft round puff: smoke, dust, a heat bloom.
//
// WHY THIS IS NOT A SPRITE. `docs/prop-kit.md`, "What is deliberately not
// here": smoke, sparks, speed lines, the tow line, the Roll Cage outline and
// dust are drawn in QML on purpose, because "a hard-edged bake of a soft thing
// reads as gravel". The kit is frozen art and this is the other half of that
// decision -- nothing here may ever become a file under `assets/props/`.
//
// HOW IT IS SOFT WITHOUT A GRADIENT SHADER. Qt Quick's own gradients are
// linear, and the radial ones live in Qt5Compat.GraphicalEffects, which is not
// a dependency this plugin may take (and which the software scene graph this
// game is measured on renders badly anyway). So a puff is `rings` concentric
// circles, each a plain antialiased Rectangle at `radius: width / 2`, whose
// alphas sum to a smooth falloff from the centre to the rim. Seven quads, no
// texture, no repaint, no allocation on any frame: every property below is a
// binding, so a puff that is growing and fading costs the scene graph seven
// moves.
//
// THE RINGS ARE SOLVED, NOT GUESSED, AND THE FIRST VERSION WAS BACKWARDS.
//
// What each ring must paint is not the opacity wanted at its radius: the rings
// are stacked, so the disc at radius r has every ring larger than it painted
// underneath. The target is the COMPOSITE -- `T(r) = amount * r'^falloff`,
// rising from almost nothing at the rim to `amount` at the centre -- and the
// alpha one ring has to carry follows from the composite under it:
//
//     a_k = (T_k - T_{k-1}) / (1 - T_{k-1})
//
// which is what the delegate below computes. The first cut of this file gave
// the OUTERMOST ring the highest alpha and divided by the ring count, so a
// puff was a flat even disc that never got brighter toward the middle: an
// impact flare drew as a grey smudge over the kart it was supposed to light
// up, which is what the second frame strip of this piece showed.
//
// Squaring (`falloff` 2) is what stops the stack reading as a set of rings: a
// linear ramp leaves visible steps at this ring count, and a cubic one
// collapses to a dot.
Item {
  id: puff

  // The puff's colour. Alpha is ignored; `amount` is the whole opacity.
  property color tone: "#f0b07a"
  // 0..1. The peak alpha at the centre of the puff.
  property real amount: 0.55
  // The diameter of the outermost ring, in pixels.
  property real size: 40
  // How many rings. Seven is the fewest that reads as smoke rather than as a
  // target at the sizes this game draws (12 to 260 px).
  property int rings: 7
  // How hard the edge is: 1 is the documented squared falloff, higher values
  // pull the visible mass toward the centre (a tighter, denser puff).
  property real falloff: 2.0
  // ROUND 6 OF PIECE F. How many screen pixels one internal pixel is -- four,
  // at 1080p on the 480 x 270 plane. Given it, every ring's diameter is a whole
  // number of road pixels and no ring is antialiased, so a puff is built out of
  // the same blocks as the road under it rather than out of soft 1080p circles
  // floating over it. 0 (the default) leaves it exactly as it was.
  property real pixel: 0
  readonly property bool blocky: pixel > 1.05

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size
  visible: amount > 0.004 && size > 0.5

  // GATED ON `visible`, AND IT IS A PERFORMANCE RULE RATHER THAN A TIDINESS
  // ONE. A hidden item's BINDINGS still run: the hood smoke draws three of
  // these per kart, so four karts that are not smoking still cost 84 colour
  // evaluations on every frame, and the race screen measured 39.3 fps against
  // the garage's 62.5 with exactly that going on. An empty model costs nothing
  // at all, and the rings come back on the frame the puff does.
  Repeater {
    model: puff.visible ? puff.rings : 0

    Rectangle {
      // Ring 0 is the outermost and is painted first, so ring k sits on top of
      // every ring before it.
      readonly property int n: Math.max(1, puff.rings)
      readonly property real raw: puff.size * (1 - index / n)
      readonly property real d: puff.blocky
                                ? Math.max(puff.pixel,
                                           Math.round(raw / puff.pixel) * puff.pixel)
                                : raw
      // The composite this ring has to reach, and the one under it.
      readonly property real target: puff.amount * Math.pow((index + 1) / n, puff.falloff)
      readonly property real under: index === 0
                                    ? 0
                                    : puff.amount * Math.pow(index / n, puff.falloff)
      anchors.centerIn: parent
      width: d
      height: d
      radius: d / 2
      antialiasing: !puff.blocky
      smooth: !puff.blocky
      color: Qt.rgba(puff.tone.r, puff.tone.g, puff.tone.b,
                     Math.max(0, Math.min(1, (target - under) / Math.max(0.001, 1 - under))))
    }
  }
}
