import QtQuick
import "../"
import "PropMeta.js" as PropMeta

// One cell of a baked prop-kit sheet, anchored at the centre of its opaque box.
//
// PIECE F. The kit under `assets/props/` is frozen art (`docs/prop-kit.md`):
// "a build agent places, scales, animates, tints and crops these; it never
// redraws one, edits a PNG, or adds a file". This item is the placing, the
// scaling, the frame-animating and the cropping, and it does nothing else.
// The six cells it exists for are the effect sprites -- `wrench` (4 frames),
// `pileUp`, `oilSlick`, `pothole`, `towHook` (2 frames) and `hubcap`
// (3 frames) -- but nothing here is specific to them.
//
// THE ANCHOR IS THE OPAQUE BOX, NOT THE CELL. Every effect prop has
// `ground: null` in the meta, which the kit's contract defines as "centred".
// Centred on WHAT is the part that matters: the cells carry a transparent
// margin (the wrench's C0 frame is 50 opaque pixels inside a 422-wide cell),
// so centring on the cell would put a wrench a hundred pixels from where the
// caller asked for it, and the offset would CHANGE between frames of the same
// animation as the frame's silhouette changes. `META[kind].bounds[view]` is
// the opaque box at scale 1; this item centres that, so a four-frame spin
// stays on its own axis.
//
// THE SIZE IS THE OPAQUE BOX TOO. `boundsWidth` is how many pixels wide the
// visible thing should be. That is the honest handle for a caller working in
// the road projection: `sizeAt(worldWidth, z)` says how wide the object is on
// screen, and the object is what is inside the box, not the margin around it.
//
// WHOLE-NUMBER ROWS, NEAREST NEIGHBOUR. The kit is baked at three scales
// (rows 1, 0.5, 0.25); `PropMeta.stepFor` picks the row whose cell is nearest
// the size being asked for, and the Image is drawn `smooth: false` as the kit
// requires. Unlike `CarSprite` the upscale is NOT forced to a whole number:
// an effect sprite is in flight for 400 ms and is never the thing a child is
// reading a number off, and quantising its size makes a projectile visibly
// step as it travels.
Item {
  id: sprite

  // A key of `PropMeta.META`, e.g. "wrench".
  property string kind: "wrench"
  // A view of that prop, e.g. "C0". Out-of-range indexes wrap, so a caller can
  // drive an animation with a raw counter.
  property int frame: 0
  // How wide the opaque box should be drawn, in pixels.
  property real boundsWidth: 64
  // Rotation about the anchor, degrees.
  property real spin: 0
  property real amount: 1.0
  // Where the sheets are. Bound to Theme so the harness can redirect the kit;
  // the plugin never writes it.
  property url sheetRoot: Theme.propSheetRoot

  readonly property var meta: PropMeta.forProp(sprite.kind)
  readonly property var viewNames: meta ? meta.views : []
  readonly property string viewName: viewNames.length > 0
                                     ? String(viewNames[((frame % viewNames.length) + viewNames.length) % viewNames.length])
                                     : ""
  // The opaque box at scale 1, as [x0, y0, x1, y1] in cell pixels.
  readonly property var box: (meta && meta.bounds && meta.bounds[viewName])
                             ? meta.bounds[viewName] : null
  // THE SIZE REFERENCE IS THE WHOLE ANIMATION, NOT THE FRAME ON SCREEN.
  //
  // The wrench's four frames are a quarter turn, so its opaque box is 50 px
  // wide edge-on (C0) and 162 wide flat (C1). Scaling each frame to the same
  // BOX width therefore made the sprite 3.2 times bigger on the frames where it
  // is thin -- a wrench that swelled to a tower every quarter turn, which is
  // what the first strip of this piece showed. The reference is the widest box
  // any of the prop's views has, so a spin is a spin at a constant size.
  //
  // The ANCHOR is still the current frame's own box, and that is not
  // inconsistent: the bake already turns each prop about a fixed point (the
  // wrench's four boxes centre on 211, 109 to within a pixel and a half, the
  // hubcap's three on 211, 55), so the two agree.
  readonly property real refBoxW: {
    if (!meta || !meta.bounds)
      return meta ? meta.cell[0] : 1
    var w = 1
    for (var i = 0; i < meta.views.length; i++) {
      var b = meta.bounds[meta.views[i]]
      if (b)
        w = Math.max(w, b[2] - b[0])
    }
    return w
  }
  readonly property real refBoxH: {
    if (!meta || !meta.bounds)
      return meta ? meta.cell[1] : 1
    var h = 1
    for (var i = 0; i < meta.views.length; i++) {
      var b = meta.bounds[meta.views[i]]
      if (b)
        h = Math.max(h, b[3] - b[1])
    }
    return h
  }
  readonly property real boxW: refBoxW
  readonly property real boxH: refBoxH
  // How much the sheet has to be scaled for the opaque box to be `boundsWidth`.
  readonly property real want: sprite.boundsWidth / Math.max(1, boxW)
  // The row whose cell is nearest that: `stepFor` takes a target CELL width,
  // so the box target is converted back through the cell.
  readonly property int step: meta ? PropMeta.stepFor(sprite.kind, meta.cell[0] * want) : 0
  readonly property var cell: meta ? PropMeta.cellRect(sprite.kind, viewName, step) : null
  readonly property real div: [1, 2, 4][step]
  // What is left over after choosing the row: the upscale (or downscale) the
  // Image itself does.
  readonly property real up: want * div

  readonly property real drawnW: cell ? cell.width * up : 0
  readonly property real drawnH: cell ? cell.height * up : 0
  // The opaque box's centre, in the drawn cell's own pixels.
  readonly property real anchorDx: box ? ((box[0] + box[2]) / 2) / div * up : drawnW / 2
  readonly property real anchorDy: box ? ((box[1] + box[3]) / 2) / div * up : drawnH / 2
  // How tall the opaque box is drawn. Callers that need to sit a sprite ON
  // something (the hubcap on the verge) read this rather than guessing.
  readonly property real drawnBoundsHeight: boxH * up / div

  width: 0
  height: 0
  visible: sprite.amount > 0.004 && sprite.drawnW > 0.5 && cell !== null

  Image {
    id: cellImage
    visible: sprite.cell !== null
    source: sprite.cell ? sprite.sheetRoot + sprite.kind + ".png" : ""
    sourceClipRect: sprite.cell ? Qt.rect(sprite.cell.x, sprite.cell.y,
                                          sprite.cell.width, sprite.cell.height)
                                : Qt.rect(0, 0, 1, 1)
    width: sprite.drawnW
    height: sprite.drawnH
    x: -sprite.anchorDx
    y: -sprite.anchorDy
    smooth: false
    mipmap: false
    cache: true
    asynchronous: false
    opacity: sprite.amount
    transform: Rotation {
      origin.x: sprite.anchorDx
      origin.y: sprite.anchorDy
      angle: sprite.spin
    }
  }
}
