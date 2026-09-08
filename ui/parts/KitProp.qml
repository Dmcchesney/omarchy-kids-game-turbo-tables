import QtQuick
import "../"
import "PropMeta.js" as PropMeta

// One cell of a baked prop-kit sheet, standing on the ground.
//
// PIECE T. `EffectSprite` is this item's twin for the six cells that fly
// through the air: it anchors on the centre of the opaque box because an
// effect spins about its own axis. A roadside prop does not spin; it STANDS,
// and where it stands is `META[kind].ground` -- the bake's own contact point,
// bottom-centre with room under it for the shadow. So this item's origin is
// that point, which is exactly what the road projection hands a caller:
// `uAt(x, z)`, `vAt(z)` is where the ground is, and the prop is put there.
//
// THE SCALE IS WORLD UNITS, NOT THE OPAQUE BOX. The kit is baked at a fixed
// density -- `PropMeta.PX_PER_UNIT` sheet pixels per world unit, FINE = 4 times
// the karts' -- so a prop is drawn at `pxPerUnit / PX_PER_UNIT` of its sheet
// size and nothing else has to be known about it. That is why a tyre wall and a
// water tower placed by the same two lines come out at the sizes the kit says
// they are, and why `bounds` is used here only for culling, never for scaling:
// scaling by the opaque box would make a prop's size depend on how much
// transparent margin its bake happened to leave.
//
// ATMOSPHERIC PERSPECTIVE, BY OPACITY, AND THE DESIGN SAYS SO. Design v4, The
// circuit: "every ground and road colour lerps toward the sky colour at the
// horizon by distance. SPRITES GET THE SAME TREATMENT WITH AN OPACITY OR A TINT
// OVERLAY BY Z." A tint overlay needs a mask of the sprite's own alpha, which
// needs a shader, which the software scene graph this project's harness runs
// under does not have. Opacity is the other half of the sentence, and it is
// exact here rather than approximate: what is BEHIND a prop at depth z is the
// ground at depth z, which both renderers have already hazed by the same
// amount. Fading the prop toward it is the same arithmetic, done by the
// compositor. The one place it is not exact is a prop tall enough to stand
// against the sky, where the sprite fades toward the sky rather than toward the
// haze -- and near the horizon those two are the same colour by construction
// (`TrackView.fogTone` is `SunsetSky.skyLow`).
//
// The kit is frozen art. This item places, scales, animates by frame, fades and
// crops. It never redraws anything.
Item {
  id: prop

  // A key of `PropMeta.META`, e.g. "tireWall".
  property string kind: "tireWall"
  // A view name of that prop: side plus frame, e.g. "R0", "L2", "C1". An
  // unknown name draws nothing rather than the wrong cell.
  property string viewName: "R0"
  // The view's COLUMN INDEX in the prop's own sheet, when the caller knows it.
  // -1 means "work it out from `viewName`", which is what `EffectSprite`'s kind
  // of caller does; the circuit knows it already and hands it over, which saves
  // a string search per prop per frame.
  property int viewIndex: -1
  // Screen pixels per world unit at this prop's depth. The caller has it
  // already: it is `TrackView.sizeAt(1, z)`.
  property real pxPerUnit: 40
  // 0..1: how much of the prop survives the haze at its distance. 1 is the
  // prop at full strength; 0 is a prop that has become the horizon.
  property real clarity: 1.0
  // WHETHER THIS PROP IS IN FRONT OF THE CAMERA AT ALL, AND IT IS NOT A
  // CONVENIENCE.
  //
  // `ui/parts/Circuit.js` places 133 props on a 432-unit loop and the draw
  // distance is 190, so at any moment about a hundred of them are behind the
  // camera. A QML binding is re-evaluated when its dependencies change whether
  // or not the item is drawn, and every one of these delegates depends on
  // `travel` -- so the chain below (`stepFor`, which takes three logarithms;
  // `cellRect`, which allocates; the eight box properties) ran a hundred times
  // a frame for props nobody could see. Measured on the Race screen at
  // 1920x1080 on this Mac's software scene graph, that alone was 6.2 ms a
  // frame: 62.8 fps with the roadside removed against 45.2 with it.
  //
  // `live` is the delegate's own visibility test, and everything expensive
  // below short-circuits on it.
  property bool live: true
  // Where the sheets are. Bound to Theme so the harness can redirect the kit;
  // the plugin never writes it.
  property url sheetRoot: Theme.propSheetRoot

  // ------------------------------------------------------------- THE TINT
  // The kit may be tinted and this is where it is: `ui/parts/PropKey.qml` is
  // the warm rim underneath and `ui/parts/PropWash.qml` the purple shadow on
  // top, and both of those files say why they are `ColorImage` rather than a
  // shader. The four numbers are authored per prop in `ui/parts/Circuit.js`
  // (`TINT`) and driven by the hour in `ui/TrackView.qml`; nothing is decided
  // here, because a light rule that lives in the item that draws one sprite is
  // a light rule twenty-five props can disagree about.
  //
  // The design's shadow, `#5f255e` at hue 301, is the target the wash pulls
  // toward; `#7a2260` is the colour that LANDS there once it is composited over
  // the bake's own blue-grey rather than replacing it.
  property color washColor: "#7a2260"
  property real washAmount: 0
  // The design's warm rim, "one low sun, warm rim #f0b07a".
  property color keyColor: "#f0b07a"
  property real keyAmount: 0
  // How far the warm rim reaches in from the prop's sun-facing edge, as a
  // share of its drawn width -- so a rock wall and the same rock wall four
  // times further away are lit the same.
  property real keyReach: 0.030

  readonly property var meta: PropMeta.forProp(prop.kind)
  readonly property int column: prop.viewIndex >= 0
                                ? prop.viewIndex
                                : (meta ? meta.views.indexOf(prop.viewName) : -1)
  readonly property bool known: live && meta !== null && column >= 0
                                && column < meta.views.length
  // How much the sheet is scaled to put the prop at its world size.
  readonly property real want: pxPerUnit / PropMeta.PX_PER_UNIT
  readonly property int step: (live && meta) ? PropMeta.stepForFast(prop.kind, meta.cell[0] * want) : 0
  readonly property var cell: known ? PropMeta.cellRectAt(prop.kind, column, step) : null
  readonly property real div: [1, 2, 4][step]
  readonly property real up: want * div

  readonly property real drawnW: cell ? cell.width * up : 0
  readonly property real drawnH: cell ? cell.height * up : 0
  // The contact point, in the drawn cell's own pixels. `ground` is null only
  // for the effect props, which use EffectSprite instead; the fallback is the
  // cell's bottom centre, which is what the kit's contract says it means.
  readonly property var foot: (meta && meta.ground) ? meta.ground : null
  readonly property real anchorDx: foot ? foot[0] * up / div : drawnW / 2
  readonly property real anchorDy: foot ? foot[1] * up / div : drawnH

  // The opaque box, in the drawn cell's pixels and relative to the contact
  // point. A caller measuring where a prop actually is on the screen -- the
  // fact's guard band, a critic's frame audit -- reads these rather than the
  // cell, because the cell carries a transparent margin the camera never sees.
  readonly property var box: (known && meta.bounds)
                             ? meta.bounds[meta.views[column]] : null
  readonly property real boxLeft: box ? box[0] * up / div - anchorDx : -drawnW / 2
  readonly property real boxTop: box ? box[1] * up / div - anchorDy : -drawnH
  readonly property real boxWidth: box ? (box[2] - box[0]) * up / div : drawnW
  readonly property real boxHeight: box ? (box[3] - box[1]) * up / div : drawnH

  width: 0
  height: 0
  visible: known && clarity > 0.004 && drawnW > 0.5

  // THE SUN, UNDER THE CELL. Declared before the cell, so the warm silhouettes
  // are painted first and all that survives of them is the rim outside the
  // prop's own outline.
  //
  // LOADED BY NAME, AND THAT IS THE POINT OF THE LOADER. The only primitive
  // that can recolour a baked sprite on a SOFTWARE scene graph -- which is what
  // this project's evidence renders on, and what a weak machine may well fall
  // back to -- is `ColorImage`, and it lives in `QtQuick.Controls.impl`, a
  // Qt-internal module. An `import` of it at the top of THIS file would take the
  // whole roadside down on a Qt build that does not ship it. Behind a `Loader`
  // the failure is contained: the loader logs and stays empty, and the circuit
  // keeps its props with the kit drawn as baked. The URL is a literal, which is
  // what `npm run check:readme` requires of anything a plugin loads, and Qt
  // compiles it once for all hundred and thirty-eight props.
  //
  // It is never toggled. A prop crosses in and out of the draw distance many
  // times a lap and constructing two items each time would be allocation in a
  // path that runs every frame, which plan v3 forbids; what turns off inside is
  // `visible`, on numbers that are already zero when the prop is not live.
  Loader {
    source: "PropKey.qml"
    onLoaded: item.host = prop
  }

  Image {
    id: cellImage
    objectName: prop.kind
    visible: prop.cell !== null
    source: prop.cell ? prop.sheetRoot + prop.kind + ".png" : ""
    sourceClipRect: prop.cell ? Qt.rect(prop.cell.x, prop.cell.y,
                                        prop.cell.width, prop.cell.height)
                              : Qt.rect(0, 0, 1, 1)
    width: prop.drawnW
    height: prop.drawnH
    x: -prop.anchorDx
    y: -prop.anchorDy
    opacity: prop.clarity
    smooth: false
    mipmap: false
    cache: true
    asynchronous: false
  }

  // THE SHADOW, OVER THE CELL. Same contract as the key above.
  Loader {
    source: "PropWash.qml"
    onLoaded: item.host = prop
  }
}
