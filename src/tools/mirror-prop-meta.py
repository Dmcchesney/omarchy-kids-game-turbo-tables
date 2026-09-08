"""Mirror assets/props/props-meta.json into ui/parts/PropMeta.js.

Layer 2 may not read a file at runtime (the boundary check forbids the request
object everywhere but layer 3), so the prop kit's meta is carried into QML as
a JavaScript literal, the way CarMeta.js carries the car sheets' meta.
tests/propmeta.test.ts holds the two equal, so a rebake that changes a cell
fails `npm test` until this is re-run -- and bake-props.ts re-runs it itself.

  python3 mirror-prop-meta.py PROPS_DIR REPO/ui/parts/PropMeta.js

Only the `var META = ...` block is generated; everything above it is kept from
the file as it stands, so a rebake never undoes an edit to a helper.
"""
import json, os, sys

HEAD = '''.pragma library

// The prop kit's meta, mirrored as a JavaScript literal.
//
// GENERATED from assets/props/props-meta.json -- do not edit META by hand.
// Every prop is one indexed PNG at assets/props/<name>.png. Columns are the
// prop's views in META[name].views order: R and L are the prop standing on
// the right and left verge seen from the road camera (the sun stays on the
// right, so a left-verge prop is a different render, not a mirror); C is a
// centred view for things that span the road or fly over it; a trailing digit
// is the animation frame. Rows are scales 1, 0.5 and 0.25, packed from the
// left at each scale; META[name].rows holds the row's top y at scale 1.
//
// Cells are anchored at META[name].ground, in cell pixels at scale 1: the
// bottom-centre ground point of a standing prop, or null for an effect sprite,
// which is centred. META[name].bounds[view] is the opaque box at scale 1, so
// a small prop's transparent margin (the camera never comes closer than
// about half its stock distance) can be cropped away by a consumer.
//
// The kit is baked at FINE = 4 times the karts' pixels per world unit, so a
// prop drawn at the projection's size upscales by about half as much as a
// kart does near the camera: a step finer, by the maintainer's decision.

var FINE = 4
var PX_PER_UNIT = 192 / 6.26 * FINE

function forProp(name) {
  return META[name] || null
}

// The rectangle of one view at one scale step (0, 1, 2), in sheet pixels.
function cellRect(name, view, step) {
  var m = META[name]
  if (!m) return null
  var i = m.views.indexOf(view)
  if (i < 0) return null
  var div = [1, 2, 4][step]
  var w = Math.floor(m.cell[0] / div), h = Math.floor(m.cell[1] / div)
  return { x: i * w, y: m.rows[step], width: w, height: h }
}

// The scale step whose cell is nearest a requested cell width, by ratio.
function stepFor(name, targetPx) {
  var m = META[name]
  if (!m) return 0
  var best = 0, bestD = Number.POSITIVE_INFINITY
  for (var s = 0; s < 3; s++) {
    var d = Math.abs(Math.log(Math.max(1, targetPx) / (m.cell[0] / [1, 2, 4][s])))
    if (d < bestD) { bestD = d; best = s }
  }
  return best
}

'''


def main(props, out):
    with open(os.path.join(props, "props-meta.json")) as f:
        meta = json.load(f)
    head = HEAD
    if os.path.exists(out):
        current = open(out).read()
        i = current.find("\nvar META = ")
        if i >= 0:
            head = current[:i + 1]
    with open(out, "w") as f:
        f.write(head + "var META = " + json.dumps(meta, indent=1, sort_keys=True) + "\n")
    print("wrote", out, "from", props)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
