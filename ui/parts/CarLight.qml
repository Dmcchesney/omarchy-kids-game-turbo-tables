import QtQuick
import QtQuick.Controls.impl

// THE ROOM'S LIGHT, ON A KART. The other half of `CarWash.qml`.
//
// WHY THIS FILE EXISTS. `CarWash` takes value AWAY from a car -- one silhouette
// of the whole cell in one dark tone, which is what nightfall does. Nothing put
// light BACK, so on the garage's turntable a critic measured the hero and found
// that the body was `rgb(224,72,58)` -- byte-for-byte the colour of the red chip
// in the menu's swatch grid, `Theme.paints[0]` -- while the room around it drew
// its shadows in purple at saturation 0.7 and its rims in `#f0b07a`. The car was
// not lit by the bay at all: it was the raw sheet, at UI chroma, pasted into a
// lit scene. Its own darks measured `rgb(107,114,145)` and `rgb(26,27,38)`, a
// blue-grey at saturation 0.26, in a room whose design rule is *shadow is purple
// `#5f255e`, never grey*.
//
// So this is the key and the rim, drawn the only way a frozen sheet can take
// them: as `ColorImage` passes of the car's own silhouette, clipped to the part
// of the cell the light reaches, at an alpha that lerps rather than replaces. It
// is a lighting model in four numbers -- where the key comes from, how far down
// the body it falls, which flank the sun rims, and how hard -- and it is the
// same model whatever paint the child picked, which is the point: the paint the
// room camouflages (purple on a purple dais) gets the same warm top and the same
// hot edge as the one it flatters.
//
// BANDED ON PURPOSE. A ColorImage fills one flat tone, so a falloff here is a
// staircase of clipped bands rather than a gradient. That is the medium: this
// is a pixel-art sheet whose own paint ramps are four stepped tones, and a
// banded key reads as the same drawing rather than as a photograph's gradient
// laid over it. `keySteps` is how many.
//
// It is `ColorImage`, and it is loaded by a `Loader` in the screen that wants
// it, for the two reasons `CarWash.qml` and `PropWash.qml` both carry: on a
// software scene graph -- which is what this project's evidence renders on and
// what a weak machine falls back to -- `ShaderEffect`, `MultiEffect` and
// `Qt5Compat.GraphicalEffects` draw nothing at all, and `QtQuick.Controls.impl`
// is a Qt-internal module that an `import` at the top of a screen would let take
// that whole screen down with it.
//
// COST. Every pass is one textured quad of the cell, blended once per REPAINT --
// there is no animation here and nothing is bound to a clock, so a garage
// sitting still pays for these exactly once. `keySteps` bands plus one rim is
// `keySteps + 1` quads over a region that is at most the cell.
Item {
  id: light

  // The `CarSprite` this lights. Everything is read off it live, so the light
  // follows the car through its yaw columns and its scale rows.
  property var host: null

  // THE KEY: the bay's work light, overhead, and the sun through the opening
  // above and to the sun side. One warm tone, strongest at the roof and stepped
  // down the body over `keyReach` of the cell's height.
  property color keyColor: "#ffb05a"
  property real keyStrength: 0.32
  property real keyReach: 0.52
  property int keySteps: 4

  // THE FILL: the room's purple, coming up off the floor into the underside.
  property color fillColor: "#5f255e"
  property real fillStrength: 0.30
  property real fillReach: 0.34
  property int fillSteps: 3

  // WHICH HALF OF THE LIGHT THIS INSTANCE IS. "key" is the bands, and it is
  // drawn OVER the car. "rim" is the sun's edge and it is drawn UNDER: a copy
  // of the same silhouette, offset a few pixels toward the sun, so what shows
  // is exactly the sliver of it the car does not cover -- an outline that
  // follows the real shape, in the room's own rim colour, without a single
  // pixel of the frozen sheet being repainted. A screen wanting both declares
  // two of these, the rim one before the sprite and the key one after.
  property string pass: "key"

  // THE RIM: `#f0b07a` is the room's own rim tone, and the offset is where the
  // sun is -- above and to the sun side of the turntable.
  property color rimColor: "#ffc189"
  property real rimStrength: 0.80
  property int rimDx: 2
  property int rimDy: -2

  readonly property int cellW: host ? host.cellW : 1
  readonly property int cellH: host ? host.cellH : 1
  readonly property int ps: host ? host.ps : 1
  readonly property bool ready: host !== null && host.cellW > 0

  // The bands, in CELL pixels, computed once per cell rather than per band per
  // frame: each is a clip row range and the alpha the key has by then.
  readonly property var bands: {
    var out = []
    if (!light.ready || light.pass !== "key")
      return out
    var i, y0, y1, step
    if (light.keyStrength > 0 && light.keySteps >= 1) {
      step = Math.max(1, Math.round(light.cellH * light.keyReach)) / light.keySteps
      for (i = 0; i < light.keySteps; i++) {
        y0 = Math.round(i * step)
        y1 = Math.round((i + 1) * step)
        if (y1 > y0)
          out.push({ y: y0, h: y1 - y0, c: light.keyColor,
                     a: light.keyStrength * (1 - i / light.keySteps) })
      }
    }
    // The shadow side, from the ground up. The floor is the one direction this
    // room has no light coming from, and the sheet's own darks are a blue-grey
    // the design forbids -- this is what makes the underside of a car in this
    // room purple instead.
    if (light.fillStrength > 0 && light.fillSteps >= 1) {
      var base = light.host.shadeRows > 0 ? light.host.shadeTopPx : light.cellH
      step = Math.max(1, Math.round(light.cellH * light.fillReach)) / light.fillSteps
      for (i = 0; i < light.fillSteps; i++) {
        y1 = Math.round(base - i * step)
        y0 = Math.round(base - (i + 1) * step)
        if (y0 < 0)
          y0 = 0
        if (y1 > y0)
          out.push({ y: y0, h: y1 - y0, c: light.fillColor,
                     a: light.fillStrength * (1 - i / light.fillSteps) })
      }
    }
    return out
  }

  Repeater {
    model: light.bands

    ColorImage {
      required property var modelData
      source: light.host ? light.host.sheetSource : ""
      sourceClipRect: Qt.rect(light.host.cellX, light.host.cellY + modelData.y,
                              light.cellW, modelData.h)
      color: modelData.c
      x: -light.host.anchorDx
      y: modelData.y * light.ps - light.host.anchorDy
      width: light.host.drawnWidth
      height: modelData.h * light.ps
      fillMode: Image.Stretch
      opacity: modelData.a
      smooth: false
      antialiasing: false
      mipmap: false
      cache: true
      asynchronous: false
    }
  }

  // The sun's edge: the whole silhouette, once, in the rim tone, offset toward
  // the sun. The sheet's own bake already breaks its outline ink where the sun
  // hits it; this is the light that step is a highlight OF, at a width a child
  // can see at 1x -- a critic measured the baked one at two to three pixels and
  // called it a loose orange fleck rather than light.
  ColorImage {
    // Down to the contact point and no further: the rows below it are the
    // bake's own contact shadow, and a shadow offset toward the light is a
    // second shadow in the wrong place.
    readonly property int rimRows: light.ready
                                   ? (light.host.shadeRows > 0
                                      ? light.host.shadeTopPx + 2 : light.cellH)
                                   : 1
    visible: light.ready && light.pass === "rim" && light.rimStrength > 0
    source: light.host ? light.host.sheetSource : ""
    sourceClipRect: light.ready
                    ? Qt.rect(light.host.cellX, light.host.cellY,
                              light.cellW, rimRows)
                    : Qt.rect(0, 0, 1, 1)
    color: light.rimColor
    x: (light.host ? -light.host.anchorDx : 0) + light.rimDx * light.ps
    y: (light.host ? -light.host.anchorDy : 0) + light.rimDy * light.ps
    width: light.host ? light.host.drawnWidth : 0
    height: rimRows * light.ps
    fillMode: Image.Stretch
    opacity: light.rimStrength
    smooth: false
    antialiasing: false
    mipmap: false
    cache: true
    asynchronous: false
  }
}
