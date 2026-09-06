import QtQuick
import "../"

// ONE BIG WORD IN THIS LIGHT: cast shadow, keyline, warm rim, cream face.
//
// WHY IT IS A PART. It was a `component LitWord` inside `ui/Countdown.qml`, used
// twice there -- the numeral and the first fact. The race draws the SAME STRING
// one second later and drew it as a plain cream `Text`, so the one object the
// design says must carry across the cut was redesigned across the cut. It is a
// file now because two screens have to draw the same word the same way, and a
// component private to one of them cannot be what makes them agree.
//
// WHAT THE TREATMENT IS FOR, unchanged from the round that measured it: cream
// over a sky that is pink and a sun that is cream. Measured on the shipped
// 1920 x 1080 GO frame, the cream face is 3.10 : 1 mean and 1.26 : 1 worst
// against the ground under it -- raw, that fails. What makes it read is the
// keyline: an opaque near-black purple contour all the way round, 5.32 : 1 mean
// and 2.57 : 1 worst against the same ground, with the cream at ~14 : 1 inside
// it. The cast shadow is thrown down and LEFT, which is where a sun low and
// behind-right puts one, and the warm rim is `#f0b07a` up and to the right,
// inside the keyline, so the word is lit from where the frame is lit from.
//
// ============================== WHAT CHANGED: THE SAME PICTURE, DRAWN ONCE
//
// THE KEYLINE IS SIXTEEN COPIES OF THE WORD, and that is still the right
// drawing. Eight copies at the axes and the corners is a square dilation: the
// diagonal copies land 1.41 keylines out, so every convex corner grows a square
// step and a diagonal stroke -- the `x` of `1 x 6` -- stairsteps against the
// sky. Sixteen on a circle put the diagonals where they belong.
//
// WHAT WAS WRONG WAS PAYING FOR IT EVERY FRAME. Twenty `Text` items per word,
// forty on the GO beat, is forty full-size glyph composites of 484 px and
// 155 px type on every frame of a screen whose stated floor is a software
// renderer in a VM. Measured with `npm run perf` at 1920 x 1080 on the GO beat:
// 5.90 cpu ms/frame with the ring, 3.22 with the thirty-two contour copies
// deleted. The keyline alone was 2.68 cpu ms/frame -- 45% of the whole screen.
//
// So the shadow, the ring and the rim are inside one `layer.enabled` item. Qt
// re-renders a layer when its subtree changes and blits the cached texture
// otherwise, and this subtree changes when the WORD changes -- four times in
// the life of a countdown -- so the sixteen composites happen on a beat and
// every frame in between costs one textured quad. The pixels are the same
// pixels: the same `Text` items, the same font, the same offsets.
//
// A CANVAS WAS TRIED FIRST AND IS THE INTERESTING FAILURE. `strokeText` draws
// the true glyph outline in one pass, which is cheaper still and has no
// stairstep to answer for at all. It cannot be used here, and the reason is
// worth keeping: a `Canvas`'s font comes from a CSS string and Qt resolves that
// string through a different path than `Text` resolves `font.family`. With the
// shell's own face handed down they agree; with the fallback family this
// repository ships -- `Theme.fontFamily` is "monospace", which this Mac does
// not have -- they do NOT. Measured in one frame, `1 x 6` at 126 px: the canvas
// laid it out 379 px wide and the `Text` beside it 304 px. The keyline traced a
// different, narrower `6` than the cream one over it and left the real glyph's
// sun-side edge bare -- one cream pixel of the fact ended up bordering the sun's
// core at 1366 x 768, which is exactly what
// `test_08_no_cream_of_the_type_sits_straight_on_the_sun` exists to catch. A
// keyline drawn by a different font engine from the face it is keying is not a
// keyline. The layer keeps one engine and buys most of the same saving.
//
// THE FACE IS OUTSIDE THE LAYER, and that is the one thing about the structure
// worth reading twice. The numeral's beat pulse scales this whole item by a
// tenth for 260 ms; a layer scales as a TEXTURE, so the ink would resample for
// that quarter second, while the face, being a live `Text`, re-rasterises at the
// scaled size and stays crisp. The ink softening for 260 ms under a crisp face
// is invisible; the cream softening would not be.
Item {
  id: word

  property string words: ""
  property int size: 10
  property int spacing: 0
  // The cast shadow's throw, and the keyline's width, both already in frame
  // pixels: the caller owns them because the caller is what fits the word to
  // the board it must clear.
  property int drop: 0
  property int contour: 0
  property int rimOffset: 0
  property color faceTone: "#f2e6c4"
  property color shadowTone: "#000000"
  property color bodyTone: "#000000"
  property color rimTone: "#f0b07a"
  // WHETHER THE CACHED INK IS FILTERED WHEN IT IS SCALED, AND IT IS OFF BY
  // DEFAULT BECAUSE FILTERING IS THE EXPENSIVE STATE. Bound by the caller to
  // "this word is mid-pulse"; see `ui/Countdown.qml`'s beat surge.
  property bool inkSmooth: false

  width: wordFace.implicitWidth
  height: wordFace.implicitHeight

  // The face's own font, published. A caller that has to MEASURE this word --
  // `ui/Race.qml` sizes the answer field and the fact's contrast plate off the
  // fact's tight bounding box -- needs the font the cream is actually drawn in,
  // and reading it off a private id is what makes two files drift.
  readonly property alias faceFont: wordFace.font

  // Where the ink pass reaches outside the face's own box: the keyline every
  // way, the cast shadow left and down under it, the rim up and right. The
  // layer is given that margin explicitly, because a layer is clipped to its
  // item's rectangle and the ring hangs outside the word's box by design.
  readonly property int padL: word.contour + word.drop
  readonly property int padR: word.contour + word.rimOffset
  readonly property int padT: word.contour + word.rimOffset
  readonly property int padB: word.contour + word.drop

  // THE INK, CACHED. Everything under the face, composited once per word into
  // one texture and blitted every frame after that.
  Item {
    id: ink
    x: -word.padL
    y: -word.padT
    width: Math.max(1, word.width + word.padL + word.padR)
    height: Math.max(1, word.height + word.padT + word.padB)
    z: -1
    layer.enabled: true
    layer.smooth: word.inkSmooth

    // The cast shadow: long, down and toward the camera, away from the sun.
    Text {
      textFormat: Text.PlainText
      text: word.words
      color: word.shadowTone
      font: wordFace.font
      x: word.padL - word.drop
      y: word.padT + word.drop
    }

    // The body contour: the same word, opaque, offset one keyline out around a
    // CIRCLE. This is the pair the contrast figure is measured on.
    readonly property var contourRing: {
      var ring = []
      for (var i = 0; i < 16; i++) {
        var a = i * Math.PI / 8
        ring.push([Math.round(Math.cos(a) * word.contour),
                   Math.round(Math.sin(a) * word.contour)])
      }
      return ring
    }
    Repeater {
      model: ink.contourRing
      Text {
        required property var modelData
        textFormat: Text.PlainText
        text: word.words
        color: word.bodyTone
        font: wordFace.font
        x: word.padL + modelData[0]
        y: word.padT + modelData[1]
      }
    }

    // The warm rim, on the sun side: up and to the right, inside the contour.
    Text {
      textFormat: Text.PlainText
      text: word.words
      color: word.rimTone
      font: wordFace.font
      x: word.padL + word.rimOffset
      y: word.padT - word.rimOffset
    }
  }

  Text {
    id: wordFace
    textFormat: Text.PlainText
    text: word.words
    color: word.faceTone
    font.family: Theme.mono
    font.bold: true
    font.pixelSize: word.size
    font.letterSpacing: word.spacing
  }
}
