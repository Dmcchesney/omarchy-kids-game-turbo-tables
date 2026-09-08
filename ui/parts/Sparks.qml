import QtQuick

// A spark burst: hard little squares thrown out from a point and falling.
//
// Drawn in QML for the same reason `Puff` is (see `docs/prop-kit.md`, "What is
// deliberately not here"). Unlike the puff these ARE hard-edged -- a spark is
// a hot chip of metal and reads right as a pixel -- so they are unantialiased
// squares on the game layer's own palette.
//
// NOTHING ANIMATES ITSELF. `t` runs 0 at the burst to 1 when it is over and is
// driven by the caller from the effect clock in `ui/TrackView.qml`, never by a
// NumberAnimation. That is what makes a frame strip reproducible: at a given
// `t` this item draws exactly the same pixels on every run, on any machine, at
// any frame rate. Every scatter below is a deterministic function of `index`
// and `seed` -- there is no Math.random in the game layer at all.
Item {
  id: sparks

  // 0..1 through the burst's life. Outside that range nothing is drawn.
  property real t: 0
  property int count: 10
  property color tone: "#ffd489"
  // How far the furthest spark reaches, in pixels.
  property real reach: 60
  // The size of one spark at the moment of the burst.
  property real grain: 4
  // Which burst this is, so two bursts in one frame do not draw the same fan.
  property int seed: 0
  // How much the sparks fall relative to `reach` over the burst's life.
  property real gravity: 0.55
  // ROUND 6. One internal pixel, in screen pixels. A spark was already a hard
  // unantialiased square -- it just was not the SIZE of a road pixel, nor on
  // the road's grid, so a burst was made of chips a quarter of a block across.
  // 0 (the default) leaves it as it was.
  property real pixel: 0
  readonly property bool blocky: pixel > 1.05
  function snap(v) { return blocky ? Math.round(v / pixel) * pixel : v }

  width: 0
  height: 0
  visible: t > 0 && t < 1

  // Gated on `visible` for the reason `Puff` is: a hidden item's bindings still
  // run, and a burst that is over must cost nothing.
  Repeater {
    model: sparks.visible ? sparks.count : 0

    Rectangle {
      // A fixed fan rather than a circle: sparks come off a struck panel
      // mostly sideways and up, so the angles are spread over 260 degrees
      // centred on straight up, and the per-spark jitter is the golden-ratio
      // sequence, which is even at any count and needs no random source.
      // TWO SEQUENCES, NOT ONE. The first cut drove the angle and the speed off
      // the same number, so every spark at a given angle went the same distance
      // and the burst drew a perfectly even ring -- an ornament, not an impact.
      // The angle and the speed now come from two different irrationals, so the
      // fan scatters in both at once and still needs no random source: at a
      // given `t` this draws the same pixels on every run, which is what a
      // frame strip has to be able to promise.
      readonly property real jitter: ((index * 0.6180339887 + sparks.seed * 0.31830988) % 1)
      readonly property real spread: ((index * 0.7548776662 + sparks.seed * 0.56984029) % 1)
      readonly property real ang: -Math.PI / 2 + (jitter - 0.5) * 4.54
      readonly property real speed: 0.22 + spread * spread * 0.92
      // Ease out: fast off the panel, slowing as it goes.
      readonly property real e: 1 - Math.pow(1 - Math.max(0, Math.min(1, sparks.t)), 2.2)
      readonly property real dist: sparks.reach * speed * e
      readonly property real drop: sparks.reach * sparks.gravity * e * e

      readonly property real rawSize: sparks.grain * (0.55 + spread * 0.65)
                                      * (1 - sparks.t * 0.6)
      width: sparks.blocky
             ? Math.max(sparks.pixel, Math.round(rawSize / sparks.pixel) * sparks.pixel)
             : Math.max(1, Math.round(rawSize))
      height: width
      antialiasing: false
      color: sparks.tone
      opacity: Math.max(0, 1 - sparks.t) * (0.60 + spread * 0.40)
      x: sparks.snap(Math.cos(ang) * dist - width / 2)
      y: sparks.snap(Math.sin(ang) * dist + drop - height / 2)
    }
  }
}
