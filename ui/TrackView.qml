import QtQuick
import "parts"

// Looking down the track.
//
// THE ONE PROJECTION, WRITTEN THREE TIMES
//
// The road is drawn by a fragment shader that inverts the camera projection
// per pixel; the karts and the roadside props are ordinary items positioned by
// the same projection in QML; and CanvasRoad.qml draws the same road again for
// machines where the shader will not run. Those three have to agree exactly,
// or a kart floats above the tarmac. The four lines that must match are:
//
//     v(z)      = horizon + focal * camHeight / (2 z)          <- vAt
//     z(v)      = focal * camHeight / (2 (v - horizon))        <- road.frag
//     u(x, z)   = 0.5 + (x + curve z^2) focal / (2 z aspect)   <- uAt
//     pixels(W) = W focal height / (2 z)                       <- sizeAt
//
// The last one is why horizontal and vertical sprite scale are the same
// number: `aspect` cancels against width/height, so a kart is never stretched.
//
// WHAT MOVES. Speed is effective-progress rate, not a throttle: the child does
// not steer and cannot brake, so `speed` is set by Race.qml from how fast the
// engine's effective progress is climbing, a Turbo throws `travel` forward and
// a landed attack pulls the horizon back and stalls the road. The kart itself
// never reverses -- the design is explicit that the road does the telling --
// so `travel` is monotonic and only its rate ever changes.
//
// WHAT IT COSTS. The road renders into a layer at 480 x 270 and is scaled up
// with nearest-neighbour filtering, so the fragment work is an eighth of
// 1080p. The sprites are drawn once each into fixed-size canvases and are
// moved and scaled by the scene graph after that, so a frame is one shader
// pass and sixteen textured quads and no drawing at all. The kart list is a
// ListModel rather than a JavaScript array on purpose: assigning a new array
// to a Repeater destroys and rebuilds every delegate, and at sixty frames a
// second that would rebuild four canvases sixty times a second.
Item {
  id: view

  property bool reducedMotion: false
  property bool paused: false

  // 0 = stopped, 1 = a good pace. Race.qml drives it from progress rate.
  property real speed: 0.55
  // The child's smoothed effective progress, in questions. Every other kart
  // is placed relative to it.
  property real humanProgress: 0

  // ------------------------------------------------------- camera constants
  readonly property real baseHorizon: 0.400
  readonly property real camHeight: 2.20
  readonly property real baseFocal: 1.20
  readonly property real roadHalf: 1.90
  readonly property real rumbleHalf: 0.30
  readonly property real stripe: 1.4
  readonly property real gridScale: 4.5
  readonly property real drawDistance: 190
  readonly property real nearDistance: 1.25
  // Where the child's kart sits. The two numbers are locked together: a kart's
  // size and its height up the screen are both 1/z, so "low on the screen" and
  // "not enormous" are the same choice. At z = 2.6 with a kart 1.55 world
  // units wide the sprite is about a fifth of the screen width and its roof
  // sits just below the horizon, which leaves the whole upper third free for
  // the fact -- which the design requires, because the fact may never be over
  // the karts.
  readonly property real playerZ: 3.20
  readonly property real kartWorldWidth: 1.36
  // World units per question of effective progress, near the child. Beyond
  // four questions the gap is compressed, so a rival a whole lap ahead is a
  // speck on the horizon rather than a kart that is not on the screen at all.
  readonly property real unitsPerQuestion: 4.0

  // ----------------------------------------------------------- live camera
  property real travel: 0
  property real curve: 0
  // Impulses, each 0..1 and each decaying. Reduced motion never raises them.
  property real lurch: 0
  property real pullback: 0
  property real shake: 0
  property real shakeX: 0
  property real shakeY: 0

  readonly property real horizon: baseHorizon + pullback * 0.055
  readonly property real focal: baseFocal + lurch * 0.16 - pullback * 0.13
  readonly property real aspect: height > 0 ? width / height : 16 / 9

  // ------------------------------------------------------- the projection
  function vAt(z) { return horizon + (focal * camHeight) / (2 * Math.max(0.05, z)) }
  function uAt(x, z) {
    return 0.5 + ((x + curve * z * z) * focal) / (Math.max(0.05, z) * 2 * aspect)
  }
  function sizeAt(worldWidth, z) {
    return worldWidth * focal * height / (2 * Math.max(0.05, z))
  }

  // Compressed distance for a kart `delta` questions ahead of the child.
  function zForDelta(delta) {
    var a = Math.abs(delta)
    var near = Math.min(a, 4) * unitsPerQuestion
    var far = a > 4 ? (a - 4) * unitsPerQuestion * 0.30 : 0
    return playerZ + (delta < 0 ? -1 : 1) * (near + far)
  }

  // Lane offsets by seat, so four karts do not stack on the centre line.
  readonly property var lanes: [0.0, -0.98, 0.98, -0.42]
  function laneOf(seat) { return lanes[((seat % 4) + 4) % 4] }

  // ---------------------------------------------------------- the kart list
  ListModel { id: kartModel }

  // Called once, when the race is built.
  function setKarts(list) {
    kartModel.clear()
    for (var i = 0; i < list.length; i++) {
      var k = list[i]
      kartModel.append({
        "kartId": k.id,
        "kartName": k.name,
        "kartNumber": k.number,
        "kartBody": k.body,
        "kartSeat": k.seat,
        "kartPaint": String(k.paint),
        "kartProgress": k.progress,
        "isHuman": k.isHuman === true,
        "isGhost": k.ghost === true
      })
    }
  }

  // Called every frame with one number per kart, in the same order. Setting a
  // role leaves the delegate alone and only re-evaluates the bindings that
  // read it, which is the whole reason this is a ListModel.
  function setProgress(values) {
    var n = Math.min(values.length, kartModel.count)
    for (var i = 0; i < n; i++)
      kartModel.setProperty(i, "kartProgress", values[i])
  }

  // ------------------------------------------------------------ the clock
  // Called by Race.qml's FrameAnimation. Nothing in this file starts a timer
  // of its own, so a closed overlay costs the shell nothing.
  function advance(dtMs) {
    if (paused)
      return
    var dt = Math.max(0, Math.min(80, dtMs)) / 1000

    if (reducedMotion) {
      // The design's reduced-motion floor: a static perspective plane with
      // sprites. No scroll, no shake, no lurch, no streaks.
      lurch = 0
      pullback = 0
      shake = 0
      shakeX = 0
      shakeY = 0
      return
    }

    var rate = speed * 26 + lurch * 90
    rate *= (1 - Math.min(0.95, pullback * 1.05))
    travel += rate * dt

    // A slow wander in the curve, so the road bends the way a circuit does
    // rather than running dead straight for twelve laps. Derived from
    // `travel`, so it is the same bend at the same point of the track every
    // lap and not a random number per frame.
    curve = 0.00075 * Math.sin(travel * 0.010) + 0.00042 * Math.sin(travel * 0.0031 + 1.7)

    lurch = Math.max(0, lurch - dt * 1.5)
    pullback = Math.max(0, pullback - dt * 1.35)
    shake = Math.max(0, shake - dt * 2.6)
    if (shake > 0) {
      var phase = travel * 3.1
      shakeX = Math.sin(phase * 6.3) * shake * 9
      shakeY = Math.cos(phase * 8.1) * shake * 6
    } else {
      shakeX = 0
      shakeY = 0
    }

    if (!shaderMode)
      roadCanvas.requestPaint()
  }

  // Design, Motion: "a road lurch on Turbo, a horizon pull-back on being hit".
  function throwForward(strength) {
    if (reducedMotion)
      return
    lurch = Math.min(1, lurch + strength)
    shake = Math.min(1, shake + strength * 0.45)
  }
  function pullBack(strength) {
    if (reducedMotion)
      return
    pullback = Math.min(1, pullback + strength)
    shake = Math.min(1, shake + strength * 0.80)
  }

  // Ground, light and shadow, from the design's Visual style section. Held
  // here rather than in the shader so a themed desktop retints the track.
  readonly property color groundTone: Theme.ground
  readonly property color skyTone: Qt.rgba(Theme.ground.r * 0.62, Theme.ground.g * 0.62,
                                           Theme.ground.b * 0.80, 1)
  readonly property color fogTone: Qt.rgba(Theme.ground.r * 0.80 + Theme.tealDeep.r * 0.24,
                                           Theme.ground.g * 0.80 + Theme.tealDeep.g * 0.24,
                                           Theme.ground.b * 0.80 + Theme.tealDeep.b * 0.24, 1)
  // The diagnostic grid is a hairline on a near-black floor, not a lit lattice:
  // the design's ground is "near-black from the theme's darkest background" and
  // the grid is a motif on it. Round one drew it at the full teal and the floor
  // read as water.
  readonly property color gridTone: Qt.rgba(Theme.ground.r * 0.5 + Theme.tealDeep.r * 0.42,
                                            Theme.ground.g * 0.5 + Theme.tealDeep.g * 0.42,
                                            Theme.ground.b * 0.5 + Theme.tealDeep.b * 0.42, 1)
  readonly property color roadTone: Qt.rgba(0.113, 0.123, 0.142, 1)
  readonly property color roadToneAlt: Qt.rgba(0.152, 0.165, 0.190, 1)
  readonly property color laneTone: Theme.cream

  // --------------------------------------------------------- shader or not
  // Two ways the shader path is refused, and both have to be handled or the
  // screen is simply black on the machines that hit them:
  //
  //   * the shader fails to compile -- `status` goes to Error, which is the
  //     case the design's fallback exists for;
  //   * there is no shader pipeline at all, which is what a software-rendered
  //     Qt Quick scene graph is. A ShaderEffect there never compiles anything
  //     and never reports an error; it just draws nothing. `GraphicsInfo.api`
  //     is the only thing that says so, and it says so before the first frame.
  property bool shaderFailed: false
  readonly property bool softwareScene: GraphicsInfo.api === GraphicsInfo.Software
                                        || GraphicsInfo.api === GraphicsInfo.Unknown
  // Forces the fallback for a side-by-side comparison. Never set in play.
  property bool forceCanvas: false
  readonly property bool shaderMode: !softwareScene && !shaderFailed && !forceCanvas
  readonly property string roadPath: shaderMode
                                     ? "shader"
                                     : (softwareScene ? "canvas (software scene graph)"
                                        : (shaderFailed ? "canvas (shader refused)" : "canvas (forced)"))

  function noteShaderStatus(status) {
    if (status === ShaderEffect.Error) {
      console.log("TrackView: road shader did not compile, falling back to CanvasRoad\n"
                  + roadShader.log)
      view.shaderFailed = true
    }
  }

  Component.onCompleted: console.log("TrackView: road path = " + roadPath)

  // ------------------------------------------------------------- the road
  clip: true

  Item {
    id: plane
    width: 480
    height: 270
    x: view.shakeX
    y: view.shakeY
    transform: Scale {
      xScale: view.width / 480
      yScale: view.height / 270
    }

    // The layer is what makes the shader's fragment work an eighth of 1080p.
    // With the canvas fallback the picture is already 480 x 270 and a layer
    // would only add a copy, so it is switched off with the shader.
    layer.enabled: view.shaderMode
    layer.smooth: false
    layer.textureSize: Qt.size(480, 270)

    ShaderEffect {
      id: roadShader
      anchors.fill: parent
      visible: view.shaderMode
      blending: false
      fragmentShader: Qt.resolvedUrl("../shaders/road.frag.qsb")

      property real horizon: view.horizon
      property real camHeight: view.camHeight
      property real focal: view.focal
      property real aspect: view.aspect
      property real travel: view.travel
      property real curve: view.curve
      property real roadHalf: view.roadHalf
      property real rumbleHalf: view.rumbleHalf
      property real stripe: view.stripe
      property real gridScale: view.gridScale
      property real fogDensity: 1.0
      property real glowAmount: 0.09

      property color roadColor: view.roadTone
      property color roadAlt: view.roadToneAlt
      property color rumbleColor: Theme.hazard
      property color rumbleAlt: Theme.cream
      property color laneColor: view.laneTone
      property color groundColor: view.groundTone
      property color gridColor: view.gridTone
      property color skyColor: view.skyTone
      property color fogColor: view.fogTone
      property color glowColor: Theme.amber

      onStatusChanged: view.noteShaderStatus(status)
    }

    CanvasRoad {
      id: roadCanvas
      anchors.fill: parent
      visible: !view.shaderMode

      horizon: view.horizon
      camHeight: view.camHeight
      focal: view.focal
      aspect: view.aspect
      travel: view.travel
      curve: view.curve
      roadHalf: view.roadHalf
      rumbleHalf: view.rumbleHalf
      stripe: view.stripe
      gridScale: view.gridScale
      drawDistance: view.drawDistance
      nearDistance: view.nearDistance

      roadColor: view.roadTone
      roadAlt: view.roadToneAlt
      rumbleColor: Theme.hazard
      rumbleAlt: Theme.cream
      laneColor: view.laneTone
      groundColor: view.groundTone
      gridColor: view.gridTone
      skyColor: view.skyTone
      fogColor: view.fogTone
      glowColor: Theme.amber

      // Under reduced motion nothing calls advance(), so the plane repaints
      // only when the camera itself changes -- which is the static plane the
      // design's floor asks for.
      onHorizonChanged: requestPaint()
      onFocalChanged: requestPaint()
      onWidthChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }
  }

  // ------------------------------------------------------------ the backdrop
  // The far wall of the garage, standing on the horizon: bays of dark steel
  // with lit windows and a hazard rail along the top.
  //
  // Without it the road ran into an empty void, which is what a road renderer
  // looks like when nobody has decided what is behind it. The design's circuit
  // is indoors -- "a garage at night, seen from the driver's seat" -- so what
  // is behind the vanishing point is a wall, and putting one there is the
  // difference between a plane with a stripe on it and a place.
  //
  // It parallaxes with the curve, which is what makes a bend read as a bend
  // before the road's own edges have moved far enough to say so, and it is
  // drawn as items rather than in the shader so the fallback gets it too.
  Item {
    id: backdrop
    width: parent.width
    height: Math.round(view.height * 0.062)
    y: Math.round(view.horizon * view.height) - height + view.shakeY
    clip: true
    z: 1

    readonly property real bayWidth: Math.max(28, view.width / 16)
    readonly property int bays: Math.ceil(view.width / bayWidth) + 2
    // A far wall moves a fraction of what the road does. The curve term is the
    // parallax; the travel term is the slow drift of a wall that is a long way
    // off but not infinitely far.
    // Modulo one bay, not the whole row: the row is one bay wider than the
    // screen and slides within that, so it covers the width at every offset.
    // Taking the modulo over the whole row was the round-two bug that left the
    // wall standing off the side of the screen.
    readonly property real shift: {
      var s = -view.curve * 62000 - view.travel * 0.55
      var m = s % bayWidth
      return m < 0 ? m + bayWidth : m
    }

    Repeater {
      model: backdrop.bays

      Item {
        width: backdrop.bayWidth
        height: backdrop.height
        x: (index - 1) * backdrop.bayWidth + backdrop.shift

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(view.groundTone.r * 1.10 + 0.010,
                         view.groundTone.g * 1.10 + 0.011,
                         view.groundTone.b * 1.25 + 0.014, 1)
        }
        // the pillar between two bays
        Rectangle {
          width: Math.max(1, backdrop.bayWidth * 0.10)
          height: parent.height
          color: Qt.rgba(0, 0, 0, 0.62)
        }
        // A lit window. Two bays in five are dark and one in five is a cold
        // teal, so the wall is a building with people in some of it rather
        // than a repeating pattern.
        Rectangle {
          visible: (index % 5) !== 1 && (index % 7) !== 3
          x: backdrop.bayWidth * 0.34
          y: backdrop.height * 0.34
          width: backdrop.bayWidth * 0.30
          height: Math.max(2, backdrop.height * 0.22)
          color: (index % 5) === 2 ? Qt.rgba(Theme.teal.r, Theme.teal.g, Theme.teal.b, 0.28)
                                   : Qt.rgba(Theme.amber.r, Theme.amber.g, Theme.amber.b, 0.34)
        }
      }
    }

    // the hazard rail along the top of the wall, and the shadow it casts down
    Rectangle {
      width: parent.width
      height: Math.max(1, backdrop.height * 0.055)
      color: Qt.rgba(Theme.hazard.r, Theme.hazard.g, Theme.hazard.b, 0.26)
    }
    Rectangle {
      width: parent.width
      height: backdrop.height * 0.34
      anchors.bottom: parent.bottom
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
      }
    }
  }

  // ------------------------------------------------------------- streaks
  // Design, Accessibility: "Reduced motion removes all shake, lurch, and
  // streak lines." These are the streak lines: short light trails running out
  // from the vanishing point, fading in with speed and gone entirely when the
  // setting is on.
  Item {
    id: streaks
    anchors.fill: parent
    visible: !view.reducedMotion && view.speed > 0.12
    opacity: Math.max(0, Math.min(0.42, (view.speed - 0.12) * 0.45 + view.lurch * 0.55))
    z: 5

    readonly property real vx: view.uAt(0, 6000) * view.width + view.shakeX
    readonly property real vy: view.horizon * view.height + view.shakeY

    Repeater {
      model: 14

      Rectangle {
        readonly property real ang: (index / 14) * Math.PI * 2 + 0.21
        readonly property real phase: {
          var p = (view.travel * 0.055 + index * 0.137) % 1
          return p < 0 ? p + 1 : p
        }
        readonly property real reach: phase * phase * Math.max(view.width, view.height) * 1.05

        width: Math.max(6, 26 + phase * 96)
        height: Math.max(1, Math.round(1 + phase * 2))
        color: Theme.cream
        opacity: (1 - phase) * 0.85
        antialiasing: false
        transformOrigin: Item.Center
        x: streaks.vx + Math.cos(ang) * reach - width / 2
        y: streaks.vy + Math.sin(ang) * reach * 0.62 - height / 2
        rotation: Math.atan2(Math.sin(ang) * 0.62, Math.cos(ang)) * 180 / Math.PI
      }
    }
  }

  // ---------------------------------------------------------- the props
  // Twelve pieces of the garage, spaced down the track and recycled by a
  // modulo, so there are always twelve on screen and never a thirteenth to
  // pay for. The kinds repeat on a fixed cycle, so the same landmark comes
  // round at the same place every lap, which is what makes it a circuit.
  readonly property var propCycle: ["tireWall", "workLight", "cone", "drum",
                                    "sign", "workLight", "rollerDoor", "cone",
                                    "tireWall", "drum", "workLight", "sign"]
  readonly property real propSpacing: 12.0
  readonly property real propLoop: propCycle.length * propSpacing

  Repeater {
    model: view.propCycle.length

    Item {
      readonly property string myKind: view.propCycle[index]
      readonly property bool arch: myKind === "rollerDoor"
      readonly property real worldWidth: arch ? 9.4 : (myKind === "tireWall" ? 2.6 : 1.35)
      readonly property real zed: {
        var raw = (index * view.propSpacing - view.travel) % view.propLoop
        return (raw < 0 ? raw + view.propLoop : raw) + view.nearDistance
      }
      // Alternating sides, at three different distances off the kerb, so the
      // roadside is a place rather than two parallel rows.
      readonly property real lateral: arch
                                      ? 0
                                      : (index % 2 === 0 ? -1 : 1)
                                        * (view.roadHalf + view.rumbleHalf
                                           + [0.75, 1.55, 2.60][index % 3])
      readonly property real sc: view.sizeAt(worldWidth, zed) / furniture.sheetW

      x: view.uAt(lateral, zed) * view.width + view.shakeX
      y: view.vAt(zed) * view.height + view.shakeY
      width: 0
      height: 0
      z: 1000 - zed
      visible: zed > view.nearDistance + 0.2 && zed < view.drawDistance
               && sc > 0.010 && x > -view.width * 0.7 && x < view.width * 1.7

      TrackSprite {
        id: furniture
        kind: parent.myKind
        // Three steps of distance dimming, quantised on purpose: `dim` is the
        // one sprite property that repaints the canvas, so it must not be a
        // continuous function of a position that changes every frame.
        dim: Math.max(0.34, Math.round(Math.max(0.34, 1.08 - parent.zed / 120) * 3) / 3)
        x: -sheetW / 2
        y: -sheetH
        scale: parent.sc
      }
    }
  }

  // ---------------------------------------------------------- the karts
  // Back to front by depth, which the scene graph does from `z`, so the
  // drawing order is a property of where the karts are and cannot fall out of
  // step with them.
  Repeater {
    model: kartModel

    Item {
      id: slot
      // The model carries the paint as a string, because a ListModel role is
      // typed by the first value put in it and a colour round-trips through a
      // string safely. This is where it becomes a colour again.
      readonly property color paintCol: kartPaint
      readonly property real delta: isHuman ? 0 : (kartProgress - view.humanProgress)
      readonly property real zed: isHuman ? view.playerZ : view.zForDelta(delta)
      readonly property real sc: view.sizeAt(view.kartWorldWidth, zed) / kartArt.sheetW
      readonly property real spriteH: kartArt.sheetH * sc
      // The child's kart bobs a little with speed: the one thing on screen
      // that says the engine is running while the child is thinking.
      readonly property real bob: (isHuman && !view.reducedMotion)
                                  ? Math.sin(view.travel * 0.62) * (1.2 + view.speed * 2.6)
                                  : 0

      x: view.uAt(view.laneOf(kartSeat), zed) * view.width + view.shakeX
      y: view.vAt(zed) * view.height + view.shakeY + bob
      width: 0
      height: 0
      z: 1000 - zed
      visible: zed > view.nearDistance && zed < view.drawDistance
               && x > -view.width * 0.6 && x < view.width * 1.6

      TrackSprite {
        id: kartArt
        kind: "kart"
        paintColor: slot.paintCol
        number: kartNumber
        body: kartBody
        ghost: isGhost
        dim: Math.max(0.40, Math.round(Math.max(0.40, 1.06 - slot.zed / 105) * 3) / 3)
        opacity: isGhost ? 0.55 : 1.0
        x: -sheetW / 2
        y: -sheetH
        scale: slot.sc
      }

      // A rival carries a small name plate so a callout that says PASSED BOLT
      // can be matched to a kart on the road. The child's own kart does not:
      // it is the one in the middle at the bottom.
      Item {
        visible: !isHuman && !isGhost && slot.zed > view.playerZ + 1.5
                 && slot.spriteH > 28
        width: tag.implicitWidth + 10
        height: tag.implicitHeight + 5
        x: -width / 2
        y: -slot.spriteH - height - 4

        Rectangle {
          anchors.fill: parent
          radius: 3
          color: Qt.rgba(0, 0, 0, 0.62)
          border.width: 1
          border.color: Qt.rgba(slot.paintCol.r, slot.paintCol.g, slot.paintCol.b, 0.8)
        }

        Text {
          id: tag
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: kartName
          color: Theme.textBright
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: Math.max(9, Math.min(15, Math.round(slot.spriteH * 0.16)))
          font.letterSpacing: 1
        }
      }
    }
  }
}
