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
        "dotT": r.progress,
        "dotColor": String(r.color),
        "dotNumber": r.number,
        "dotHuman": r.isHuman === true,
        "dotGhost": r.ghost === true,
        "dotFinished": r.finished === true
      })
    }
    relayout()
  }

  function setProgress(values) {
    var n = Math.min(values.length, dots.count)
    for (var i = 0; i < n; i++)
      dots.setProperty(i, "dotProgress", values[i])
    relayout()
  }

  // ---------------------------------------------------------- de-collision
  // WHY THE DOTS ARE NOT DRAWN WHERE THE NUMBERS SAY.
  //
  // The loop is the whole race, twelve sectors for twelve lap-tables, which is
  // what the design asks for. That makes the whole picture 144 questions long,
  // so four racers within a few questions of one another -- which is most of a
  // race -- land inside one dot's width of one another. Round one drew them
  // straight and the shipped frame contained exactly two visible dots out of
  // four: the child's disc was drawn 24% larger and on top, and it covered the
  // other two completely. A map of a four-kart race that shows two karts is
  // worse than no map.
  //
  // So the dots are pushed apart along the track until each has a dot's width
  // of room, in order, from the racer who is furthest back. Three properties
  // hold, and they are the ones that make this a legibility device rather than
  // a lie:
  //
  //   * the ORDER is never changed -- the dot in front is the racer in front;
  //   * the displacement is BOUNDED by (n-1) x one dot width, which is the
  //     smallest gap at which two dots are two dots at all;
  //   * the group is re-centred on its own true mean, so the field as a whole
  //     still sits where it really is on the lap.
  //
  // The exact gaps are the HUD's job to state in questions; this is the
  // picture, and a picture that hides half the field is not honest either.
  readonly property real perimeter: {
    var total = 0
    for (var i = 1; i < outline.length; i++) {
      var dx = outline[i].x - outline[i - 1].x
      var dy = outline[i].y - outline[i - 1].y
      total += Math.sqrt(dx * dx + dy * dy)
    }
    return Math.max(1, total)
  }
  readonly property real minSepT: (dotSize * 1.32) / perimeter

  function relayout() {
    var n = dots.count
    if (n === 0)
      return
    var order = []
    var sum = 0
    for (var i = 0; i < n; i++) {
      var t = Math.max(0, Math.min(0.99999, dots.get(i).dotProgress))
      order.push({ "at": i, "t": t })
      sum += t
    }
    order.sort(function (a, b) { return a.t - b.t })
    for (var k = 1; k < n; k++)
      if (order[k].t < order[k - 1].t + minSepT)
        order[k].t = order[k - 1].t + minSepT
    // Re-centre on the true mean, so spreading never drags the field forward.
    var moved = 0
    for (var m = 0; m < n; m++)
      moved += order[m].t
    var shift = (sum - moved) / n
    for (var w = 0; w < n; w++)
      dots.setProperty(order[w].at, "dotT",
                       Math.max(0, Math.min(0.99999, order[w].t + shift)))
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
  // The tarmac reads as a road only if it is lighter than the panel it sits
  // on. Round one used panelSunken, which is darker than the panel, so the
  // loop read as a hole cut in the HUD rather than as a circuit.
  property color trackColor: Theme.panelRaised
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
  readonly property real tarmacWidth: Math.max(8, dotSize * 0.92)

  Shape {
    anchors.fill: parent
    antialiasing: true

    // the tarmac
    ShapePath {
      strokeColor: minimap.trackColor
      strokeWidth: minimap.tarmacWidth
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

      // Exactly the tarmac's width. Round one drew the ticks taller than the
      // road they cross, so one on a tight bend read as a mark floating beside
      // the loop rather than a sector line on it.
      width: 2
      height: minimap.tarmacWidth
      color: active ? Theme.amber : Theme.textFaint
      x: p.x - width / 2
      y: p.y - height / 2
      rotation: Math.atan2(tan.y, tan.x) * 180 / Math.PI
      antialiasing: true
    }
  }

  // The start and finish line, at t = 0. Two rows of squares, not one row of
  // bars: round one drew six 3 px columns the full height of the road, which
  // reads as three slashes rather than as a chequered flag.
  Grid {
    readonly property point p: minimap.pointAt(0)
    readonly property point tan: minimap.tangentAt(0)
    readonly property real cell: Math.max(3, Math.round(minimap.tarmacWidth / 2))
    columns: 4
    rows: 2
    x: p.x - width / 2
    y: p.y - height / 2
    rotation: Math.atan2(tan.y, tan.x) * 180 / Math.PI
    spacing: 0

    Repeater {
      model: 8
      Rectangle {
        width: parent.cell
        height: parent.cell
        color: ((index % 4) + Math.floor(index / 4)) % 2 === 0
               ? Theme.cream : Qt.rgba(0.06, 0.06, 0.07, 1)
      }
    }
  }

  // ------------------------------------------------------------- the dots
  Repeater {
    model: dots

    Item {
      readonly property color tint: dotColor
      readonly property point p: minimap.pointAt(Math.max(0, Math.min(0.99999, dotT)))
      // Every dot is the same size now. The child's is found by its ring and
      // by the accent, not by being the biggest thing on the map -- a bigger
      // disc on top is exactly what erased two of the four racers.
      readonly property real size: minimap.dotSize

      width: size
      height: size
      x: p.x - size / 2
      y: p.y - size / 2
      // The child's dot is drawn UNDER the rivals, not over them. If two are
      // ever coincident despite the spreading, the one that loses is the one
      // the child already knows the position of.
      z: dotHuman ? 2 : 3

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

      // The child's dot carries a double ring in cream and the theme's accent,
      // so it is found by shape rather than by size. Round one used the same
      // blue for the emphasis ring that a rival dot was painted in.
      Rectangle {
        visible: dotHuman
        anchors.centerIn: parent
        width: parent.width + 9
        height: parent.height + 9
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.cream
      }
      Rectangle {
        visible: dotHuman
        anchors.centerIn: parent
        width: parent.width + 5
        height: parent.height + 5
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
        border.color: Qt.rgba(0, 0, 0, 0.72)
        opacity: dotFinished ? 0.72 : 1.0

        // A two-digit number in a disc has to be sized off the chord it sits
        // on, not off the diameter, or the second digit is clipped by the
        // curve -- which is what happened to the `34` in round one.
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(dotNumber)
          color: Theme.ink(parent.color)
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: Math.max(8, Math.round(parent.height
                                                 * (String(dotNumber).length > 1 ? 0.50 : 0.62)))
        }
      }
    }
  }
}
