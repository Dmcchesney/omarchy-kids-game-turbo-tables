import QtQuick
import "../ui"

// A MEASUREMENT PROBE: TrackView with `travel` ADVANCING.
//
// `--screen TrackView` holds `travel` fixed, so every binding that depends on
// it is evaluated once at construction and what the instrument then measures is
// rasterisation and nothing else. A race is not that. A read-only investigation
// on 2026-09-05 measured the difference at +1.58 cpu ms a frame, +32%, which no
// TrackView figure in this project's reports contains -- so a parked-camera
// number has to be labelled as one, and this file is what gives the other.
//
// Twelve lines, no state of its own: one animation drives `travel` once round
// the 432-unit loop in twenty-four seconds, which is about race speed.
//
//   npm run perf -- run --screen dev/MovingTrack --size 1920x1080
//              -- pace vsync --redraw dirty      the game's own cadence
Item {
  id: root
  property real drive: 0
  property real seed: 0

  TrackView {
    id: view
    anchors.fill: parent
    travel: root.drive
    speed: 0.55
  }

  NumberAnimation on drive {
    from: 0; to: 432; duration: 24000; loops: Animation.Infinite; running: true
  }
}
