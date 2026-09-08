import QtQuick
import "../ui"
import "../ui/parts/Circuit.js" as Circuit

// A MEASUREMENT PROBE: the countdown's backdrop with nothing over it.
//
// PIECE 5, ROUND 3. `ui/Countdown.qml` is `ui/TrackView.qml` held still at the
// start line, and the decision that made that affordable turns on one number:
// what a FROZEN TrackView costs when its 890 drawn items are composed once into
// a layer and blitted after that. `--screen TrackView` cannot answer it, because
// it measures the view rasterised every frame; `--screen Countdown` cannot
// either, because it measures the type and the lamps as well.
//
// This is the backdrop alone, in exactly the arrangement the countdown ships:
// the same camera, the same still, the same cached layer.
//
//   npm run perf -- run --screen dev/StillTrack --size 1920x1080
//
// Measured on this Mac at 1920 x 1080, load 4.5-5.1: 0.336 wall and 0.672 cpu
// ms/frame here against 2.754 and 3.795 for `--screen TrackView` at the same
// camera. The whole difference is the cache, and what it buys is 8.3 MB of
// offscreen texture -- which is why the layer is worth arguing about and why
// this file exists to keep the argument reproducible.
Item {
  id: root
  property real travel: Circuit.START_TRAVEL

  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: false

    TrackView {
      anchors.fill: parent
      travel: root.travel
      lap: 1
      speed: 0
    }
  }
}
