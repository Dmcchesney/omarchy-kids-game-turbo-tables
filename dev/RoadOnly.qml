import QtQuick
import "../ui"
import "../ui/parts"

// The road plane on its own, at its own internal size, with nothing else in
// front of it.
//
// PIECE T. The gate on this piece includes "shader and canvas fallback
// identical -- the same frame from both paths, differenced", and on this Mac
// the shader path cannot run at all: `-platform offscreen` reports
// `GraphicsInfo.Software`, so `TrackView.shaderMode` is false and every frame
// the harness takes is `ui/CanvasRoad.qml`. Measuring the two against each
// other therefore needs a CPU reference of `shaders/road.frag`, and a reference
// is only worth anything if it is fed EXACTLY the uniforms the shipped screen
// feeds the shader.
//
// So this rig holds a real `TrackView` -- invisible, but fully bound, so every
// uniform is the one the race view computes -- and draws a `CanvasRoad` of the
// plane's own size beside it, bound to the same values. `--dump-uniforms`
// prints them as one JSON line for the reference renderer to read, and `--shot`
// grabs the plane at 528 x 286 with no sky, no props and no karts over it.
//
// It is in `dev/` and is loaded by `--screen dev/RoadOnly`, so it never ships.
//
//   qml -platform offscreen -I dev/imports dev/Harness.qml -- \
//       --screen dev/RoadOnly --travel 120 --size 528x286 --hud off \
//       --shot canvas.png --exit
Item {
  id: rig

  // The harness assigns this when `--travel` is given.
  property real travel: 120
  // The lap, for the uniforms that pass with the hour.
  property int lap: 1

  // The reference camera. Invisible and never rendered, but every binding in it
  // runs, so `planeHorizon`, `planeFocal`, `planeAspect`, `planeSunU`,
  // `fogTone`, `waterTone` and the rest are the shipped screen's own numbers
  // rather than a second opinion about them.
  TrackView {
    id: camera
    width: 1920
    height: 1080
    visible: false
    reducedMotion: false
    travel: rig.travel
    lap: rig.lap
  }

  // The plane, at its own resolution, filling whatever the harness window is.
  CanvasRoad {
    id: plane
    objectName: "plane"
    anchors.fill: parent

    horizon: camera.planeHorizon
    camHeight: camera.camHeight
    focal: camera.planeFocal
    aspect: camera.planeAspect
    travel: camera.travel
    curve: camera.curve
    roadHalf: camera.roadHalf
    rumbleHalf: camera.rumbleHalf
    stripe: camera.stripe
    gridScale: camera.gridScale
    drawDistance: camera.drawDistance
    nearDistance: camera.nearDistance

    surfaceFog: camera.surfaceFog
    glowAmount: 1.0
    gridAlpha: camera.gridAlpha
    sunU: camera.planeSunU
    glowRx: 0.24 * camera.planeKx
    glowRy: 0.08 * camera.planeKy
    sectorLength: camera.sectorLength
    clock: camera.worldClock
    heatShimmer: camera.roadShimmer
    texelU: 1 / camera.planeW
    nightfall: camera.nightfall

    roadColor: camera.roadTone
    roadAlt: camera.roadToneAlt
    rumbleColor: Theme.hazard
    rumbleAlt: Theme.cream
    laneColor: camera.laneTone
    groundColor: camera.groundTone
    gridColor: camera.gridTone
    skyColor: camera.fogTone
    fogColor: camera.fogTone
    glowColor: camera.sunTone
    waterColor: camera.waterTone
    waterLit: camera.waterLitTone

    onTravelChanged: requestPaint()
    Component.onCompleted: requestPaint()
  }

  function hex(c) {
    function two(v) {
      var s = Math.round(Math.max(0, Math.min(255, v * 255))).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + two(c.r) + two(c.g) + two(c.b)
  }

  // Every uniform the shader is given, as one JSON line. The reference renderer
  // reads this and nothing else, so a number changed in TrackView reaches the
  // reference without anybody editing the reference.
  //
  // PRINTED ON A TIMER, NOT AT `Component.onCompleted`, and the difference cost
  // an afternoon. The harness assigns `--travel` in its Loader's `onLoaded`,
  // which runs AFTER the loaded item's own `Component.onCompleted`: the first
  // version of this printed the uniforms at travel 120 -- the default -- while
  // the canvas beside it went on to render at whatever travel was asked for.
  // The reference and the fallback were then pictures of two different places
  // on the circuit, and the parity figure they produced was meaningless.
  Timer {
    interval: 300
    running: true
    onTriggered: rig.dumpUniforms()
  }

  function dumpUniforms() {
    console.log("UNIFORMS|" + JSON.stringify({
      "planeW": camera.planeW, "planeH": camera.planeH,
      "horizon": camera.planeHorizon, "camHeight": camera.camHeight,
      "focal": camera.planeFocal, "aspect": camera.planeAspect,
      "travel": camera.travel, "curve": camera.curve,
      "roadHalf": camera.roadHalf, "rumbleHalf": camera.rumbleHalf,
      "stripe": camera.stripe, "gridScale": camera.gridScale,
      "fogDensity": 1.0, "surfaceFog": camera.surfaceFog,
      "glowAmount": 1.0, "gridAlpha": camera.gridAlpha,
      "sunU": camera.planeSunU,
      "glowRx": 0.24 * camera.planeKx, "glowRy": 0.08 * camera.planeKy,
      "sectorLength": camera.sectorLength, "clock": camera.worldClock,
      "heatShimmer": camera.roadShimmer, "texelU": 1 / camera.planeW,
      "nightfall": camera.nightfall,
      "roadColor": hex(camera.roadTone), "roadAlt": hex(camera.roadToneAlt),
      "rumbleColor": hex(camera.rumbleTone), "rumbleAlt": hex(camera.rumbleAltTone),
      "laneColor": hex(camera.laneTone), "groundColor": hex(camera.groundTone),
      "gridColor": hex(camera.gridToneNow), "fogColor": hex(camera.fogTone),
      "glowColor": hex(camera.sunTone), "waterColor": hex(camera.waterTone),
      "waterLit": hex(camera.waterLitTone), "shoreColor": hex(camera.shoreTone)
    }))
  }
}
