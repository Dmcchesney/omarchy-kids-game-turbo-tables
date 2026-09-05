import QtQuick

// A soft round light: the flare an impact throws, and the sun's own bloom.
//
// ROUND 5 OF PIECE F, AND IT EXISTS BECAUSE `Puff` COULD NOT BE THIS BIG.
//
// `Puff` builds a soft disc out of `rings` concentric antialiased rectangles
// whose alphas sum to a smooth falloff. That is the right trick at the size a
// puff of smoke is drawn -- 12 to 260 px, over which the steps between rings
// are a pixel or two apart and disappear. It is the wrong trick at the size a
// light is drawn. The step between two rings is `amount * falloff / rings`
// however wide the disc is, so a 670 px bloom at seven rings steps by 0.086 of
// alpha every 48 px, and what that draws is a set of concentric circles: the
// exact "modern UI effect pasted over a retro scene" the rubric warns about.
// Round 5's first cut of the impact light drew it at 917 px and the rings were
// the first thing visible in the crop. Getting the steps under the eye's
// threshold that way needs fifty-odd rings, and fifty stacked discs of that
// size is more fill than the whole rest of the frame.
//
// So a light is a Canvas with one radial gradient, which is what
// `ui/parts/CountdownScene.qml` and `ui/parts/GarageStall.qml` already draw the
// sun and its halo with. It is smooth by construction and it costs one fill.
//
// THE CANVAS IS A FIXED 256 PX AND IS SCALED, NOT RESIZED. The disc's size is a
// projection of the victim's own depth, so it changes on every frame; resizing
// a Canvas reallocates its image and repaints it, and doing that sixty times a
// second for a 300 px light is the one way this could be expensive. Painted
// once at 256 and scaled, it repaints only when the COLOUR changes -- once per
// card -- and the bilinear upscale makes it smoother still.
//
// DETERMINISM. `Canvas.Immediate` and `Canvas.Image`: the paint happens in the
// GUI thread, synchronously, so a frame grabbed by the harness has it. Every
// frame strip in this piece's evidence is byte-identical across three complete
// runs, and that is the check on this paragraph.
Item {
  id: light

  // The light's colour. Alpha is ignored; `amount` is the whole opacity.
  property color tone: "#ffffff"
  // 0..1. The alpha at the centre of the light.
  property real amount: 0
  // How fast it falls off to nothing at the rim. 1 is a linear cone; higher
  // pulls the light in toward its centre. 1.8 is a lamp.
  property real falloff: 1.8
  // How many stops the gradient is built from. Sixteen is well below the point
  // where a stop is visible in an upscaled 256 px disc.
  readonly property int stops: 16

  Canvas {
    id: face
    anchors.centerIn: parent
    width: 256
    height: 256
    scale: light.width > 0 ? light.width / 256 : 1
    smooth: true
    opacity: Math.max(0, Math.min(1, light.amount))
    visible: opacity > 0.004 && light.width > 1
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    // Repaint on the colour and the shape, and never on the size or the alpha:
    // the first two are the only things the painted image depends on.
    readonly property color tone: light.tone
    readonly property real falloff: light.falloff
    onToneChanged: requestPaint()
    onFalloffChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128)
      for (var i = 0; i <= light.stops; i++) {
        var u = i / light.stops
        g.addColorStop(u, Qt.rgba(face.tone.r, face.tone.g, face.tone.b,
                                  Math.pow(1 - u, face.falloff)))
      }
      ctx.fillStyle = g
      ctx.fillRect(0, 0, 256, 256)
    }
  }
}
