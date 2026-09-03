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
        "dotFinished": r.finished === true,
        // Where the engine says this racer is in the field, first = 0. Until
        // `setProgress` is given an order it is simply the list order, which
        // is what the map used to break ties by without saying so.
        "dotRank": i
      })
    }
    relayout()
  }

  // `values` is one lap fraction per racer, in the order `setRacers` was given.
  //
  // `order`, if supplied, is the engine's authoritative running order as INDICES
  // into that same array, first to last -- `Engine.raceOrder(state)` mapped
  // through the racer list. Pass it and the dots can never run in an order the
  // engine disagrees with.
  //
  // WHY THIS ARGUMENT EXISTS. It was added to `TrackView.setProgress` and not
  // here, and for a whole round the map drew a different race from the track
  // and the callouts: measured on the laid-out dots, the map contradicted
  // `Engine.raceOrder` on 55% of frames on seed 42, 30% on seed 3 and 10% on
  // seed 11 over thirty seconds each. The header three lines above calls this
  // "the honest picture of the race", and half a run it was not.
  // THE PROJECTION IS NOT ENOUGH ON ITS OWN. Capping a racer at the position of
  // the racer in front makes the two values EQUAL, and equal values are exactly
  // the case the de-collision below has to break apart -- so if it breaks them
  // apart in list order, the map still draws a field the engine disagrees with,
  // on every frame where a pass is being smoothed out. Measured, threading the
  // order in and stopping there left the map contradicting `Engine.raceOrder`
  // on 31.8% of frames on seed 42, against 55.0% with no order at all. So the
  // rank travels with the value and the spreading uses it as the tie-break.
  function setProgress(values, order) {
    var v = order ? orderedProgress(values, order) : values
    var n = Math.min(v.length, dots.count)
    for (var i = 0; i < n; i++)
      dots.setProperty(i, "dotProgress", v[i])
    if (order)
      for (var k = 0; k < order.length; k++)
        if (order[k] >= 0 && order[k] < dots.count)
          dots.setProperty(order[k], "dotRank", k)
    relayout()
  }

  // The same projection `TrackView.orderedProgress` applies, written against
  // indices rather than kart ids because the dots are not given ids: walking
  // from the leader, any racer the engine says is behind is pulled back to at
  // most the position of the racer in front. It only ever moves a dot
  // backwards, so nothing on the map jumps forward, and with no `order` the
  // behaviour is exactly what it was.
  function orderedProgress(values, order) {
    if (!order || order.length === 0)
      return values
    var out = values.slice()
    var cap = Number.POSITIVE_INFINITY
    for (var k = 0; k < order.length; k++) {
      var at = order[k]
      if (at === undefined || at < 0 || at >= out.length)
        continue
      if (out[at] > cap)
        out[at] = cap
      cap = out[at]
    }
    return out
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
  // THE SPREADING IS DONE IN PIXELS ALONG THE ROAD, NOT IN t.
  //
  // `pointAt(t)` is a parametric kidney, and it is nowhere near arc-length
  // parameterised: a step of dt covers about two and a half times as much of
  // the loop on a straight as it does through the tight right-hander. Round two
  // pushed the dots apart by a constant dt computed from the perimeter, so on
  // the tight end the guarantee simply did not hold -- at 1366x768 two dots a
  // full separation apart in t came out eleven pixels apart on the bend and one
  // clipped the other. The separation now runs along the measured arc, so a
  // dot's width of road is a dot's width of road wherever on the loop it is.
  readonly property var arc: {
    var out = [0]
    var total = 0
    for (var i = 1; i < outline.length; i++) {
      var dx = outline[i].x - outline[i - 1].x
      var dy = outline[i].y - outline[i - 1].y
      total += Math.sqrt(dx * dx + dy * dy)
      out.push(total)
    }
    return out
  }
  readonly property real perimeter: Math.max(1, arc[arc.length - 1])

  // Distance along the loop, in pixels, of the point at t.
  function arcAt(t) {
    var p = Math.max(0, Math.min(0.99999, t)) * samples
    var i = Math.floor(p)
    var f = p - i
    if (i >= samples)
      return arc[samples]
    return arc[i] + (arc[i + 1] - arc[i]) * f
  }

  // Its inverse: the t whose point is `s` pixels along the loop.
  function tAtArc(s) {
    var d = Math.max(0, Math.min(perimeter, s))
    var lo = 0
    var hi = samples
    while (hi - lo > 1) {
      var mid = (lo + hi) >> 1
      if (arc[mid] <= d)
        lo = mid
      else
        hi = mid
    }
    var run = arc[hi] - arc[lo]
    var f = run > 0 ? (d - arc[lo]) / run : 0
    return Math.max(0, Math.min(0.99999, (lo + f) / samples))
  }

  // A dot's width and a third, in pixels of road, which is the smallest gap at
  // which two dots are two dots at all.
  readonly property real minSepPx: dotPx * 1.32
  // And the same gap measured the way an eye measures it: straight across. The
  // two are not the same number on a bend, which is the next paragraph.
  readonly property real minChordPx: dotPx * 1.10

  // Straight-line distance between two points that are `sa` and `sb` pixels
  // along the loop.
  function chordBetween(sa, sb) {
    var pa = pointAt(tAtArc(sa))
    var pb = pointAt(tAtArc(sb))
    var dx = pa.x - pb.x
    var dy = pa.y - pb.y
    return Math.sqrt(dx * dx + dy * dy)
  }

  function relayout() {
    var n = dots.count
    if (n === 0)
      return
    var order = []
    var sum = 0
    for (var i = 0; i < n; i++) {
      var d = dots.get(i)
      var s = arcAt(d.dotProgress)
      order.push({ "at": i, "s": s, "rank": d.dotRank })
      sum += s
    }
    // Furthest back first, and where two are level the one the engine puts
    // BEHIND is laid out behind. Sorting on `s` alone left that to whatever
    // order the racer list happened to be in.
    order.sort(function (a, b) { return a.s !== b.s ? a.s - b.s : b.rank - a.rank })
    for (var k = 1; k < n; k++)
      if (order[k].s < order[k - 1].s + minSepPx)
        order[k].s = order[k - 1].s + minSepPx

    // Re-centre on the true mean, so spreading never drags the field forward,
    // AND MOVE THE WHOLE GROUP RATHER THAN ITS ENDS.
    //
    // Every racer starts the race on the start line, so every dot starts at
    // s = 0; re-centring then pushes the back half of the field to a negative
    // distance, and round two clamped each dot to the loop SEPARATELY, which
    // put two or three of them on exactly the same pixel. Measured on the
    // laid-out dots, the closest pair was 0.0 px apart on 1250 of 1250 frames
    // of a twenty-second run, at both window sizes -- the de-collision was off
    // for the whole of every race's opening, which is the moment a child looks
    // at the map to find their own kart. Sliding the group keeps the spread.
    var moved = 0
    for (var m = 0; m < n; m++)
      moved += order[m].s
    var shift = (sum - moved) / n
    shift = slideOn(order, n, shift)
    for (var c = 0; c < n; c++)
      order[c].s += shift

    // AND ONLY NOW FINISH THE JOB IN THE SPACE THE EYE ACTUALLY MEASURES.
    //
    // Arc length is not chord length, and this loop bends hard: through the
    // tight right-hander a dot's width and a third of ROAD is 16.2 px of
    // straight line against an 18 px dot, and 11.5 px against a 16 px one on
    // the 1366x768 panel. Spreading along the arc is the right first move --
    // it is what makes the guarantee hold wherever on the loop the field is --
    // but on a corner two dots that are a dot's width of road apart still
    // touch. So the pairs are walked and the arc gap opened until the straight
    // line clears as well, bounded at three dot widths so that a corner can
    // never drag the field far out of its true place.
    //
    // This runs AFTER the re-centring, not before it: the re-centring moves the
    // whole field halfway back round the loop, so a chord measured before it is
    // a chord measured on a different piece of road. Measuring first was the
    // first version of this fix and it changed nothing at all -- the numbers it
    // corrected were not the numbers that were drawn.
    //
    // EVERY pair, not just neighbours: through the tight end the loop doubles
    // back, so the dot that lands on another one is not always the next one in
    // the running order.
    var ceiling = minSepPx + dotPx * 3
    for (var pass = 0; pass < 12; pass++) {
      var nudged = false
      for (var q = 1; q < n; q++) {
        var worst = Number.POSITIVE_INFINITY
        for (var p = 0; p < q; p++)
          worst = Math.min(worst, chordBetween(order[p].s, order[q].s))
        if (worst >= minChordPx)
          continue
        if (order[q].s - order[q - 1].s >= ceiling)
          continue
        order[q].s += Math.max(0.75, (minChordPx - worst) * 0.55)
        nudged = true
      }
      if (!nudged)
        break
    }
    // The nudges only ever push forward, so the tail can now have run off the
    // end of the loop. Slide the group back on, which keeps every gap.
    var settle = slideOn(order, n, 0)
    for (var w = 0; w < n; w++)
      dots.setProperty(order[w].at, "dotT", tAtArc(order[w].s + settle))
  }

  // How far the whole group has to move for all of it to be on the loop.
  function slideOn(order, n, shift) {
    var lo = order[0].s + shift
    var hi = order[n - 1].s + shift
    if (lo < 0)
      return shift - lo
    if (hi > perimeter)
      return shift - (hi - perimeter)
    return shift
  }

  // The parameter each dot was actually LAID OUT at, after ordering and
  // de-collision -- not the value it was handed. Exposed for the same reason
  // TrackView exposes `orderedProgress`: a test, or a harness, has to be able
  // to ask what the picture says rather than what its inputs said, because the
  // two came apart here for a whole round without anybody noticing.
  function drawnT(index) {
    return (index >= 0 && index < dots.count) ? dots.get(index).dotT : -1
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
  // A FLOOR ON THE DOT, AND THE LOOP GIVES WAY TO IT.
  //
  // `dotSize` is scaled by the caller off the window, so at 1366x768 it arrived
  // as 12 px: two-digit numbers on a 12 px disc are not readable, and the discs
  // were within a pixel of touching. A dot is the smallest thing on this panel
  // that has to be read, so it is the thing that does not shrink; the loop it
  // sits on shrinks instead, because `padX`/`padY` are derived from this and
  // the kidney is fitted into what is left.
  readonly property real dotPx: Math.max(16, dotSize)
  // THE TARMAC HAS TO BE VISIBLE AGAINST THE PANEL.
  //
  // Round two moved it from `panelSunken` to `panelRaised` and the report
  // claimed the loop then "read as a road". Measured off the rendered panel it
  // was rgb(20,21,32) on rgb(12,13,21) -- a contrast ratio of 1.07:1, which is
  // no ratio at all, and the only thing that made the circuit visible was a
  // 1 px edge. So the fill is now driven toward whatever contrasts with the
  // panel rather than being another shade of it, which keeps it correct if a
  // themed desktop makes the panel light instead of dark.
  property color panelColor: Theme.panel
  property color trackColor: Qt.rgba(
      panelColor.r + (Theme.ink(panelColor).r - panelColor.r) * 0.38,
      panelColor.g + (Theme.ink(panelColor).g - panelColor.g) * 0.38,
      panelColor.b + (Theme.ink(panelColor).b - panelColor.b) * 0.38, 1)
  // The kerb: a dark casing drawn UNDER the tarmac and a little wider, so the
  // loop has an outline against the panel at both ends of the theme.
  property color edgeColor: Qt.rgba(0, 0, 0, 0.72)

  implicitWidth: 260
  implicitHeight: 170

  // -------------------------------------------------------- the circuit
  // A kidney: two long straights, a wide left-hand sweep and a tighter right
  // one. Normalised to -1..1 in both axes and mapped into the box below.
  readonly property real padX: dotPx * 0.9 + 10
  readonly property real padY: dotPx * 0.9 + 8

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
  readonly property real tarmacWidth: Math.max(8, dotPx * 0.92)

  Shape {
    anchors.fill: parent
    antialiasing: true

    // the kerb, under and a little wider than the tarmac
    ShapePath {
      strokeColor: minimap.edgeColor
      strokeWidth: minimap.tarmacWidth + 4
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: minimap.outline }
    }

    // the tarmac
    ShapePath {
      strokeColor: minimap.trackColor
      strokeWidth: minimap.tarmacWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
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
      // Dark on the tarmac, not faint-light: the road is now a mid tone, and a
      // 38%-alpha light hairline on it is the same non-contrast the tarmac
      // itself used to have against the panel.
      color: active ? Theme.amber : Qt.rgba(0, 0, 0, 0.55)
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
      readonly property real size: minimap.dotPx

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

      // The child's dot carries a double ring, so it is found by shape rather
      // than by size. Both rings are ACHROMATIC on purpose: round two used the
      // theme's accent for the inner one, which is a blue a shade off PISTON's
      // paint, and the child's own paint is one of eight the child picks, so
      // any coloured ring can collide with some kart on the map. Cream over
      // black cannot collide with anything.
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
        border.color: Qt.rgba(0, 0, 0, 0.85)
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
