import QtQuick
import QtQuick.Shapes
import "parts"

// The honest picture of the race.
//
// Design, The view: "Minimap top right: the circuit as a loop with twelve
// sector ticks, every kart as a colored dot with its number, the child's dot
// emphasized. It is the honest picture of the race; the main view is the
// exciting one."
//
// So this is the one place where a kart that is half a lap behind looks half a
// lap behind, rather than simply being off the end of the road. The track view
// tells the child what is happening around them; this tells them where they
// are. Both read from the same effective-progress fraction the engine computes,
// so they cannot disagree.
//
// The loop is a closed parametric curve rather than a circle, because a circle
// with ticks on it reads as a clock. `pointAt(t)` is the only geometry in the
// file: the outline, the ticks, the start line and every dot are all sampled
// from it, so the circuit can be reshaped by changing two lines.
Item {
  id: minimap

  // The dots live in a ListModel rather than a JavaScript array for the same
  // reason the track view's karts do: assigning a new array to a Repeater
  // destroys and rebuilds every delegate, and these move ten times a second.
  // `setRacers` is called once and `setProgress` on every pulse.
  ListModel { id: dots }

  function setRacers(list) {
    dots.clear()
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      dots.append({
        "dotProgress": r.progress,
        "dotColor": String(r.color),
        "dotNumber": r.number,
        "dotHuman": r.isHuman === true,
        "dotGhost": r.ghost === true,
        "dotFinished": r.finished === true
      })
    }
  }

  function setProgress(values) {
    var n = Math.min(values.length, dots.count)
    for (var i = 0; i < n; i++)
      dots.setProperty(i, "dotProgress", values[i])
  }

  function setFinished(flags) {
    var n = Math.min(flags.length, dots.count)
    for (var i = 0; i < n; i++)
      dots.setProperty(i, "dotFinished", flags[i] === true)
  }

  property int sectors: 12
  // The lap the child is on, 1-based. Its arc is drawn brighter.
  property int activeSector: 1
  property bool reducedMotion: false
  property real dotSize: 18
  property color trackColor: Theme.panelSunken
  property color edgeColor: Theme.lineStrong

  implicitWidth: 260
  implicitHeight: 170

  // -------------------------------------------------------- the circuit
  // A kidney: two long straights, a wide left-hand sweep and a tighter right
  // one. Normalised to -1..1 in both axes and mapped into the box below.
  readonly property real padX: dotSize * 0.9 + 10
  readonly property real padY: dotSize * 0.9 + 8

  function shapeX(a) { return 0.98 * Math.cos(a) - 0.11 * Math.cos(2 * a) }
  function shapeY(a) { return 0.60 * Math.sin(a) + 0.17 * Math.sin(2 * a) }

  // t runs 0..1 from the start line, the way the race does.
  function pointAt(t) {
    var a = (t - 0.25) * 2 * Math.PI
    var hw = (width - padX * 2) / 2
    var hh = (height - padY * 2) / 2
    return Qt.point(padX + hw + shapeX(a) * hw / 1.09,
                    padY + hh - shapeY(a) * hh / 0.72)
  }

  function tangentAt(t) {
    var p0 = pointAt(t - 0.004)
    var p1 = pointAt(t + 0.004)
    var dx = p1.x - p0.x
    var dy = p1.y - p0.y
    var len = Math.sqrt(dx * dx + dy * dy)
    return len <= 0 ? Qt.point(1, 0) : Qt.point(dx / len, dy / len)
  }

  readonly property int samples: 132
  readonly property var outline: {
    var pts = []
    for (var i = 0; i <= samples; i++)
      pts.push(pointAt(i / samples))
    return pts
  }

  // -------------------------------------------------------------- drawing
  Shape {
    anchors.fill: parent
    antialiasing: true

    // the tarmac
    ShapePath {
      strokeColor: minimap.trackColor
      strokeWidth: Math.max(6, minimap.dotSize * 0.72)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: minimap.outline }
    }

    // its edge
    ShapePath {
      strokeColor: minimap.edgeColor
      strokeWidth: 1
      fillColor: "transparent"
      PathPolyline { path: minimap.outline }
    }
  }

  // Twelve sector ticks, one per lap-table, drawn across the tarmac. The tick
  // that begins the lap the child is on is amber; the rest are hairlines.
  Repeater {
    model: minimap.sectors

    Rectangle {
      readonly property real t: index / minimap.sectors
      readonly property point p: minimap.pointAt(t)
      readonly property point tan: minimap.tangentAt(t)
      readonly property bool active: index === ((minimap.activeSector - 1) % minimap.sectors)

      width: 2
      height: Math.max(8, minimap.dotSize * 0.86)
      color: active ? Theme.amber : Theme.textFaint
      x: p.x - width / 2
      y: p.y - height / 2
      rotation: Math.atan2(tan.y, tan.x) * 180 / Math.PI
      antialiasing: true
    }
  }

  // The start and finish line, in checkers, at t = 0.
  Row {
    readonly property point p: minimap.pointAt(0)
    readonly property point tan: minimap.tangentAt(0)
    x: p.x - width / 2
    y: p.y - height / 2
    rotation: Math.atan2(tan.y, tan.x) * 180 / Math.PI
    spacing: 0

    Repeater {
      model: 6
      Rectangle {
        width: 3
        height: Math.max(9, minimap.dotSize * 0.92)
        color: (index % 2 === 0) ? Theme.cream : Qt.rgba(0.08, 0.08, 0.09, 1)
      }
    }
  }

  // ------------------------------------------------------------- the dots
  Repeater {
    model: dots

    Item {
      readonly property color tint: dotColor
      readonly property point p: minimap.pointAt(Math.max(0, Math.min(0.99999, dotProgress)))
      readonly property real size: dotHuman ? minimap.dotSize * 1.24 : minimap.dotSize

      width: size
      height: size
      x: p.x - size / 2
      y: p.y - size / 2
      z: dotHuman ? 3 : 2

      // Position changes are a cut under reduced motion and a short slide
      // otherwise, which is the design's rule for the whole screen.
      Behavior on x {
        enabled: !minimap.reducedMotion
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
      Behavior on y {
        enabled: !minimap.reducedMotion
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }

      // The child's dot carries the theme's accent as a ring, so it is found
      // by shape as well as by size.
      Rectangle {
        visible: dotHuman
        anchors.centerIn: parent
        width: parent.width + 6
        height: parent.height + 6
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.focusRing
      }

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: dotGhost ? Qt.rgba(Theme.teal.r, Theme.teal.g, Theme.teal.b, 0.45) : tint
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.55)
        opacity: dotFinished ? 0.72 : 1.0

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(dotNumber)
          color: Theme.ink(parent.color)
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: Math.max(8, Math.round(parent.height * 0.60))
        }
      }
    }
  }
}
