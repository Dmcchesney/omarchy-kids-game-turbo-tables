import QtQuick
import QtQuick.Controls.impl

// THE SHADOW HALF OF THE LIGHT RULE ON A KIT PROP: one flat silhouette of the
// cell, in the design's purple, composited over it. `PropKey.qml` is the other
// half and stands underneath.
//
// WHY THERE IS A TINT AT ALL. `docs/prop-kit.md` and `docs/plan.md` both say a
// builder "places, scales, animates, TINTS and crops" the kit, and never redraws
// it. The round before this one read the freeze as forbidding the tint as well,
// and so left the three biggest set pieces on the circuit -- the quarry's rock
// walls, the roller door and the overpass -- in the bake's own neutral ramp.
// Measured off the PNGs, that ramp is seven tones from (11,12,18) to
// (107,114,145), every one in hue band 227-237 at saturation 0.26-0.39:
// BLUE-GREY. The design's shadow is `#5f255e`, hue 301, "never grey".
//
// HOW IT IS DONE WITHOUT A SHADER, WHICH IS THE WHOLE PROBLEM. This project's
// evidence renders on a software scene graph (`GraphicsInfo.Software`), so
// `ShaderEffect`, `MultiEffect` and everything in `Qt5Compat.GraphicalEffects`
// draw NOTHING here: they would tint the picture on a machine with a GPU and
// leave every frame a critic judges untouched. `ColorImage` is the one primitive
// that recolours on the CPU -- it loads the cell and fills it in one colour
// through the image's own alpha -- and it behaves identically on both paths. A
// flat silhouette is useless alone and is exactly right on top: composited at
// opacity a it is a per-pixel lerp of every tone toward one colour, which is
// what tinting is. Measured on `rockWall` at a = 0.45 the ramp moves from
// H 228.9 S 0.26 to H 288.0 S 0.37, and from H 235.0 to H 307.7 -- either side
// of the design's own 301.
//
// AND IT IS LOADED, NOT IMPORTED, BY THE ITEM THAT USES IT. `QtQuick.Controls
// .impl` is a Qt-internal module. An import at the top of `KitProp.qml` would
// take the WHOLE ROADSIDE down on a Qt that does not ship it; a component
// created by URL at run time fails on its own, once, and the circuit keeps its
// props with no tint on them. `Theme.propWash` is that component.
ColorImage {
  id: wash

  // The `KitProp` this paints. Everything is read off it live, so the tint
  // follows the cell through its scale rows and its animation frames without a
  // property having to be pushed in from outside.
  property var host: null
  readonly property var cell: host ? host.cell : null

  // Not drawn once the haze has taken the prop: at clarity 0.10 the wash is
  // three hundredths of an alpha over a sprite that is itself a tenth there, and
  // it is a full-size textured quad either way. See the note in PropKey.qml on
  // what these cost and how that was measured.
  visible: cell !== null && host.washAmount > 0.004 && host.clarity > 0.10
  source: cell ? host.sheetRoot + host.kind + ".png" : ""
  sourceClipRect: cell ? Qt.rect(cell.x, cell.y, cell.width, cell.height)
                       : Qt.rect(0, 0, 1, 1)
  color: host ? host.washColor : "#7a2260"
  width: host ? host.drawnW : 0
  height: host ? host.drawnH : 0
  x: host ? -host.anchorDx : 0
  y: host ? -host.anchorDy : 0
  opacity: host ? host.clarity * host.washAmount : 0
  smooth: false
  mipmap: false
  cache: true
  asynchronous: false
}
