import QtQuick
import QtQuick.Controls.impl

// THE HOUR, ON A KART -- and the one shadow in this game that is painted into
// the art rather than drawn by the view.
//
// WHY THIS FILE EXISTS. Round 2 put the whole circuit into the tint pass and
// left the four things the child actually looks at out of it. Measured on the
// shipped frames, the world darkened 44-55% from lap 1 to lap 12 and the
// player's kart darkened 1.6% -- its red flank was byte-for-byte (235,130,110)
// at lap 1, at lap 6 and at lap 12 -- while a rival got 56% BRIGHTER, because
// the only thing on it that moved with the hour was its tail lamps. By lap 12
// the karts sat at four times the luminance of the ground under them and read
// as stickers over a photograph.
//
// The design's "paint stays its own hue under this light -- a red car reads
// red" is about the KEY LIGHT'S WARMTH, not about immunity from nightfall: a
// red car at dusk is a darker red, not the same red. A wash toward one dark
// purple is a per-pixel lerp of every tone toward that colour, so the flank
// keeps its hue and loses its value, which is exactly the sentence.
//
// It is `ColorImage` and a `Loader` for the same two reasons `PropWash.qml`
// is, and that file carries the argument: on a SOFTWARE scene graph -- which
// is what this project's evidence renders on and what a weak machine falls
// back to -- `ShaderEffect`, `MultiEffect` and `Qt5Compat.GraphicalEffects`
// draw nothing at all, and `QtQuick.Controls.impl` is a Qt-internal module
// that an `import` at the top of `CarSprite.qml` would let take every car in
// the game down with it.
Item {
  id: wash

  // The `CarSprite` this paints. Everything is read off it live, so the wash
  // follows the car through its yaw columns and its scale rows without a
  // property having to be pushed in from outside.
  property var host: null

  // THE BODY. One silhouette of the whole cell in the dusk's purple.
  ColorImage {
    id: body
    visible: wash.host !== null && wash.host.washAmount > 0.004
    source: wash.host ? wash.host.sheetSource : ""
    sourceClipRect: wash.host
                    ? Qt.rect(wash.host.cellX, wash.host.cellY,
                              wash.host.cellW, wash.host.cellH)
                    : Qt.rect(0, 0, 1, 1)
    color: wash.host ? wash.host.washColor : "#2b0c28"
    x: wash.host ? -wash.host.anchorDx : 0
    y: wash.host ? -wash.host.anchorDy : 0
    width: wash.host ? wash.host.drawnWidth : 0
    height: wash.host ? wash.host.drawnHeight : 0
    fillMode: Image.Stretch
    opacity: wash.host ? Math.min(1, wash.host.washAmount) : 0
    smooth: false
    antialiasing: false
    mipmap: false
    cache: true
    asynchronous: false
  }

  // ------------------------------- THE CONTACT SHADOW THAT LIGHTENED THE ROAD
  //
  // A critic measured the shadow under the player's kart at (64,28,62) against
  // a road of (31,18,29) and called it 90% brighter than the surface it falls
  // on: "a shadow that lightens the floor is worse than no shadow". The cause
  // is not in this view at all -- it is in the sheet. Read straight off
  // `assets/karts/coupe/red.png`, the rows under the wheels are literally
  // `(95,37,94)` at alpha 128: the design's `#5f255e` at half cover, an
  // ABSOLUTE colour baked at noon. `#5f255e` is a MID purple, so over a lap-12
  // tarmac of (25,15,24) it composites to (60,26,59) and glows.
  //
  // The kit is frozen art and so are the car sheets; a builder tints them and
  // never redraws them. So the baked shadow goes into the tint pass with
  // everything else: the same silhouette, clipped to the rows below the contact
  // point, filled with a tone derived from the road it lands on.
  //
  // TWO PASSES, AND THE ARITHMETIC IS WHY. The sheet's alpha there is 0.5, so
  // one `ColorImage` at full opacity can only ever reach half way: over the
  // already-composited (56,22,54) it lands at luminance 21 against a road at
  // 19, which is a shadow that has merely stopped glowing. A second pass takes
  // it to 12 against 19 -- a third darker than the tarmac, which is the
  // design's "darker, sharper contact shadows" and is where it should have been
  // all along.
  Repeater {
    model: (wash.host && wash.host.shadeAmount > 0.004
            && wash.host.shadeRows > 0) ? 2 : 0

    ColorImage {
      source: wash.host.sheetSource
      sourceClipRect: Qt.rect(wash.host.cellX,
                              wash.host.cellY + wash.host.shadeTopPx,
                              wash.host.cellW, wash.host.shadeRows)
      color: wash.host.shadeColor
      x: -wash.host.anchorDx
      y: wash.host.shadeTopPx * wash.host.ps - wash.host.anchorDy
      width: wash.host.drawnWidth
      height: wash.host.shadeRows * wash.host.ps
      fillMode: Image.Stretch
      opacity: Math.min(1, wash.host.shadeAmount)
      smooth: false
      antialiasing: false
      mipmap: false
      cache: true
      asynchronous: false
    }
  }
}
