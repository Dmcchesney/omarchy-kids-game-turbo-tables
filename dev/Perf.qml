import QtQuick
import QtQuick.Window
import qs.Commons
import "../ui"
import "../ui/parts"

// THE INSTRUMENT.
//
// `dev/Harness.qml --measure` counts FrameAnimation ticks and reports 62.5-62.8
// fps at 480x270, at 1366x768, at 1920x1080 and at 3840x2160, with and without a
// screenful of effects. A number that does not move when the work changes by 64x
// is measuring the animation driver's cadence, not the cost of a frame. This file
// exists because that number cannot be used, and every claim made from it is void.
//
// WHAT THIS FILE DOES, AND WHAT IT DELIBERATELY DOES NOT DO.
//
// It loads one screen out of `ui/` exactly as the harness does -- same theme
// copy, same in-memory save file, same seeded settings -- then renders a FIXED
// NUMBER OF REAL SCENE-GRAPH FRAMES and quits. A fixed frame count, not a fixed
// duration: two runs of 600 frames did the same amount of the game's work, so
// their costs are comparable, whereas two runs of 2000 ms did not.
//
// It measures NO TIME ITSELF. There is no clock in this file, because
// `src/tools/check-readme.ts` forbids one in any .qml file in this repository
// and is right to -- and because a millisecond-resolution clock could not have
// timed a frame that costs a fifth of a millisecond anyway. Time is measured
// from OUTSIDE the running application, by `src/tools/perf.ts`, as the process's
// own user+system CPU time over a known frame count. That is the honest place
// for it: the number cannot be faked by the animation driver, it has microsecond
// resolution, and it counts work this application actually did.
//
// What this file publishes is everything that is only visible from inside:
//
//   * how many real frames were rendered (`afterRendering`), against how many
//     animation ticks were delivered (`FrameAnimation`). Those two are not the
//     same number, and the difference is itself a finding;
//   * the frame CADENCE, from FrameAnimation.frameTime, which has sub-millisecond
//     resolution. It is the old signal, reported here on purpose so that a reader
//     can watch it sit at 16 ms while the cost triples. It becomes meaningful only
//     when a frame costs more than the driver's interval -- that is saturation,
//     and it is the one thing the cadence genuinely tells you;
//   * a census of the scene: item counts, Canvas / ShaderEffect / layer counts,
//     and RESIDENT DECODED TEXTURE BYTES, deduplicated the way Qt's pixmap cache
//     deduplicates. The prop kit is 1.9 MB on disk and 264 MB decoded as RGBA;
//     a directory listing cannot see that and this can;
//   * two deliberate load levers, `--spin` and `--alloc`, whose only purpose is
//     to prove the instrument responds in proportion to work that is known
//     exactly. An instrument nobody has falsified is not an instrument.
//
// USAGE (always headless; never open a window on this machine):
//
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
//     qml -platform offscreen -I dev/imports dev/Perf.qml -- \
//     --screen TrackView --size 1920x1080 --frames 600
//
// but prefer `npm run perf -- ...`, which runs this twice and does the CPU
// arithmetic that turns the frame count into a cost.
//
// ARGUMENTS
//   --screen <Name>    a file in ui/, without the extension; `dev/Name` loads
//                      from this directory instead. Default Garage.
//   --size WxH         window size. Default 480x270, the internal resolution.
//   --frames <n>       how many rendered frames to measure. Default 600. When
//                      --window-ms is given this is only an upper bound.
//   --window-ms <n>    stop the count after n milliseconds of the counting phase
//                      rather than after a fixed number of frames. This is what
//                      `npm run perf` uses: every run is then the same length,
//                      and the FRAME COUNT is the measurement.
//   --warm <n>         rendered frames to discard after the settle, before the
//                      count starts. Default 30.
//   --settle <ms>      quiet time after the screen loads. Default 700.
//   --max-ms <ms>      give up if the frame count is not reached in this long,
//                      and say so. A screen that stops rendering entirely is a
//                      RESULT, not a hang. Default 40000.
//   --spin <n>         burn n iterations of arithmetic every frame, inside the
//                      synchronise phase. The falsification lever for CPU cost.
//   --alloc <n>        allocate n short-lived objects every frame. The
//                      falsification lever for garbage-collection pressure.
//   --census on|off    walk the tree and publish the scene census. Default on.
//
// It also accepts the harness's scene-setup arguments so that the thing measured
// is the thing shipped: --seed --settings --transient --warmup --travel --clock
// --lap --boards --field --inject.
//
// OUTPUT: one line, `perf-json: {...}`, and nothing else that a tool has to
// parse. Everything a screen logs on its own is left alone on the same stream.
Window {
  id: perf

  // ------------------------------------------------------ argument parsing
  function argument(name, fallback) {
    var argv = Qt.application.arguments
    for (var i = 0; i < argv.length; i++)
      if (argv[i] === "--" + name && i + 1 < argv.length)
        return argv[i + 1]
    return fallback
  }

  readonly property string screenName: argument("screen", "Garage")
  readonly property string sizeArg: argument("size", "480x270")
  readonly property int wantWidth: parseInt(sizeArg.split("x")[0], 10)
  readonly property int wantHeight: parseInt(sizeArg.split("x")[1], 10)
  readonly property int seed: parseInt(argument("seed", "42"), 10)
  readonly property int frameTarget: parseInt(argument("frames", "600"), 10)
  readonly property int warmFrames: parseInt(argument("warm", "30"), 10)
  readonly property int settleMs: parseInt(argument("settle", "700"), 10)
  readonly property int maxMs: parseInt(argument("max-ms", "40000"), 10)
  readonly property int spinIterations: parseInt(argument("spin", "0"), 10)
  readonly property int allocCount: parseInt(argument("alloc", "0"), 10)
  readonly property bool wantCensus: argument("census", "on") !== "off"

  readonly property string settingsArg: argument("settings", "")
  readonly property string transientArg: argument("transient", "")
  readonly property string travelArg: argument("travel", "")
  readonly property string clockArg: argument("clock", "")
  readonly property string lapArg: argument("lap", "")
  readonly property string boardsArg: argument("boards", "")
  readonly property string fieldArg: argument("field", "")
  readonly property int warmupArg: parseInt(argument("warmup", "0"), 10)
  readonly property string injectArg: argument("inject", "")

  width: wantWidth
  height: wantHeight
  visible: true
  color: Theme.ground
  title: "Turbo Tables perf -- " + screenName

  MemoryStore { id: saveFile }

  // ------------------------------------------------------------ the pacemaker
  //
  // THE FIRST TWO THINGS THIS INSTRUMENT FOUND, and both had to be answered
  // before any number could be taken at all.
  //
  // ONE: a Qt Quick scene that changes nothing renders nothing. The garage
  // settles into a still picture and then produces THREE frames in six seconds.
  // "600 frames of the garage" is not something the machine will give you unless
  // something asks for them, and a frame count gathered only from the screens
  // that happen to animate is not comparable between screens. Worse, the
  // software scene graph repaints only the DIRTY REGION, so a screen with one
  // blinking lamp costs one lamp whatever else is on it -- true about this
  // renderer, useless as "what does this screen cost", and wrong about the
  // machines we aim at: llvmpipe in the VM and any GPU redraw the whole surface.
  //
  // TWO, and this is the one that makes the instrument possible: the frame rate
  // is capped by the ANIMATION DRIVER, not by the cost of a frame. That is
  // precisely the defect in `--measure`. Drive the invalidation from a
  // FrameAnimation and an empty 480x270 window renders 126 frames in two
  // seconds -- 63 fps, the famous number, on a window with NOTHING IN IT. Drive
  // it from `afterRendering` instead, with QT_QPA_UPDATE_IDLE_TIME=0 so the
  // platform stops rate-limiting its update requests, and the same empty window
  // renders 139,522 frames in two seconds: 14 microseconds each. The loop is
  // then limited by the cost of the frame and by nothing else, and WALL TIME PER
  // FRAME BECOMES A COST.
  //
  // So the pacemaker is: a window-sized rectangle behind the screen whose colour
  // is flipped from inside `afterRendering`. Flipping it marks the whole window
  // dirty, which forces the whole scene to be re-rasterised, and marking it dirty
  // from inside the render cycle schedules the next frame immediately instead of
  // waiting for a tick. The two colours are both opaque and both completely
  // covered by the screen in front of them, so the picture is unchanged; only the
  // bookkeeping is.
  //
  // WHAT UNCAPPING COSTS IN HONESTY, stated here because it is the kind of thing
  // that gets left out. The animation clock still advances in real time, so a
  // screen's per-frame JavaScript still runs on every frame; but the scene moves
  // ~2000x less far between two frames than it does in play, so anything that is
  // throttled to the wall clock rather than to the frame -- a Timer-driven
  // effect, a sprite advancing at a fixed frames-per-second -- runs relatively
  // less often here and is UNDER-counted. `--pace vsync` measures at the game's
  // own cadence for exactly that reason; there, wall time is meaningless and the
  // cost has to be read from the process's CPU time instead.
  //
  // The pacemaker is not free, and pretending it were would be the same sin as
  // the old number. `--screen none` measures it alone -- an empty window, the
  // pacemaker, nothing else -- and that reading is the floor to subtract.
  //
  //   --redraw full    invalidate the whole window every frame (default)
  //   --redraw dirty   leave Qt's own dirty tracking alone and measure whatever
  //                    the screen chooses to change. Honest about THIS renderer;
  //                    not comparable between screens, and a static screen will
  //                    not reach the frame target at all -- which is a reading.
  //   --pace uncapped  drive frames from afterRendering (default). Needs
  //                    QT_QPA_UPDATE_IDLE_TIME=0 in the environment to go past
  //                    ~740 fps; `npm run perf` sets it.
  //   --pace vsync     drive frames from the animation driver, at the cadence the
  //                    game actually runs at.
  readonly property bool forceRedraw: argument("redraw", "full") !== "dirty"
  readonly property bool uncapped: argument("pace", "uncapped") !== "vsync"
  property bool invalidatorFlip: false

  function invalidate() {
    if (perf.forceRedraw)
      perf.invalidatorFlip = !perf.invalidatorFlip
  }

  // IT HAS TO BE ON TOP, AND IT HAS TO BE TRANSLUCENT, and both of those were
  // learned by getting a wrong answer first. The first version of this was an
  // opaque rectangle BEHIND the screen. It worked on the garage and on an empty
  // window, and on `Settings` and `Results` it reported 0.0078 ms per frame at
  // 480x270 and 0.0078 ms per frame at 1920x1080 -- identical across sixteen
  // times the pixels, and BELOW the cost of an empty window. That is the same
  // shape of wrongness as the 62.5 fps this instrument exists to replace, and it
  // had exactly one cause: the software renderer culls an item that opaque items
  // completely cover, so an invalidator hidden behind a screen with a solid
  // background dirtied nothing and the loop spun producing empty frames.
  //
  // On top, with an alpha of one part in 255, it cannot be culled and everything
  // underneath it has to be composited again to produce it. Its own cost is one
  // full-window blend per frame, which is real, and which `--screen none`
  // measures so it can be subtracted rather than assumed away.
  Rectangle {
    id: invalidator
    anchors.fill: parent
    z: 99999
    visible: perf.forceRedraw
    color: perf.invalidatorFlip ? Qt.rgba(0, 0, 0, 1 / 255) : Qt.rgba(0, 0, 0, 2 / 255)
  }

  // ---------------------------------------------------------------- phases
  // idle -> settling -> warming -> counting -> done. Nothing is measured until
  // `counting`, and the phases before it are identical between two runs that
  // differ only in --frames, which is what lets the outer tool subtract one
  // run's CPU from the other's and be left with nothing but rendered frames.
  property string phase: "idle"
  property bool ready: false

  property int rawRenders: 0         // afterRendering, in every phase
  property int renderedFrames: 0     // afterRendering, since `counting` began
  property int warmedFrames: 0       // afterRendering, during `warming`
  property int animationTicks: 0     // FrameAnimation, since `counting` began
  property real windowStart: 0       // FrameAnimation.elapsedTime at the start
  property real windowEnd: 0
  property real cadenceSum: 0        // sum of FrameAnimation.frameTime, seconds
  property real cadenceMax: 0
  property real cadenceMin: 9999
  property real burnSink: 0          // written by --spin so it is not dead code
  property var allocSink: null       // written by --alloc for the same reason

  // ----------------------------------------------------------------- theme
  // The same explicit copy the harness makes. Copy, do not bind: it is the
  // handoff layer 3 performs, and doing it here keeps the measured screen
  // byte-identical to the shipped one.
  function applyTheme() {
    Theme.background = Color.background
    Theme.foreground = Color.foreground
    Theme.accent = Color.accent
    Theme.urgent = Color.urgent
    Theme.muted = Color.muted
    Theme.menuBackground = Color.menu.background
    Theme.menuText = Color.menu.text
    Theme.menuBorder = Color.menu.border
    Theme.fontFamily = Style.font.family
    Theme.resolvedFontFamily = Style.font.resolvedFamily
    Theme.fontBaseSize = Style.font.baseSize
    Theme.shellCornerRadius = Style.cornerRadius
    Theme.spacingScale = Style.spacing.scale
  }

  function seedSettings(spec) {
    if (spec.length === 0)
      return
    var settings = {}
    var pairs = spec.split(",")
    for (var i = 0; i < pairs.length; i++) {
      var parts = pairs[i].split("=")
      if (parts.length !== 2)
        continue
      var raw = parts[1].trim()
      var value = raw
      if (raw === "true")
        value = true
      else if (raw === "false")
        value = false
      else if (raw.length > 0 && isFinite(Number(raw)))
        value = Number(raw)
      settings[parts[0].trim()] = value
    }
    saveFile.data = { "version": 1, "settings": settings, "records": {}, "facts": {} }
  }

  function applySession() {
    if (perf.transientArg.length === 0)
      return
    var pairs = perf.transientArg.split(",")
    for (var i = 0; i < pairs.length; i++) {
      var parts = pairs[i].split("=")
      if (parts.length !== 2)
        continue
      var raw = parts[1].trim()
      var value = raw
      if (raw === "true")
        value = true
      else if (raw === "false")
        value = false
      else if (raw.length > 0 && isFinite(Number(raw)))
        value = Number(raw)
      Store.setSetting(parts[0].trim(), value)
    }
  }

  // A field of rivals, shaped the way TrackView's own setKarts() expects, so a
  // track measurement is taken with cars on it rather than with an empty road.
  function seedField(view) {
    var deltas = perf.fieldArg.split(",")
    var list = [{
      "id": "human", "name": "YOU", "number": 7, "body": 0, "seat": 0,
      "paint": Theme.paints[0], "progress": 0, "isHuman": true, "ghost": false
    }]
    for (var i = 0; i < deltas.length && i < 3; i++) {
      list.push({
        "id": "rival" + i, "name": "RIVAL " + (i + 1), "number": 10 + i * 11,
        "body": (2 + i * 2) % 6, "seat": i + 1,
        "paint": Theme.paints[(4 + i * 3) % 8],
        "progress": parseFloat(deltas[i]), "isHuman": false, "ghost": false
      })
    }
    view.setKarts(list)
    view.humanProgress = 0
  }

  Component.onCompleted: {
    applyTheme()
    seedSettings(perf.settingsArg)
    Store.backend = saveFile
    perf.ready = true
    // `--screen none` is the floor: an empty window with the pacemaker in it and
    // nothing else. Subtract it from any other reading to get the screen's own
    // cost rather than the cost of measuring.
    if (perf.screenName === "none") {
      perf.phase = "settling"
      settle.start()
      guard.start()
    }
  }

  // ---------------------------------------------------------------- screen
  Loader {
    id: screenLoader
    active: perf.ready && perf.screenName !== "none"
    anchors.fill: parent
    focus: true
    source: perf.screenName.indexOf("dev/") === 0
            ? Qt.resolvedUrl("../dev/" + perf.screenName.substring(4) + ".qml")
            : Qt.resolvedUrl("../ui/" + perf.screenName + ".qml")

    onLoaded: {
      if (item.hasOwnProperty("seed"))
        item.seed = perf.seed
      if (perf.warmupArg > 0 && item.hasOwnProperty("warmup"))
        item.warmup = perf.warmupArg
      if (perf.warmupArg > 0 && typeof item.buildRace === "function")
        item.buildRace()
      if (perf.travelArg.length > 0 && item.hasOwnProperty("travel"))
        item.travel = parseFloat(perf.travelArg)
      if (perf.clockArg.length > 0 && item.hasOwnProperty("fxClock"))
        item.fxClock = parseFloat(perf.clockArg)
      if (perf.lapArg.length > 0 && item.hasOwnProperty("lap"))
        item.lap = parseInt(perf.lapArg, 10)
      if (perf.boardsArg.length > 0 && item.hasOwnProperty("factBoards"))
        item.factBoards = perf.boardsArg.split("|")
      if (perf.fieldArg.length > 0 && typeof item.setKarts === "function")
        perf.seedField(item)
      item.forceActiveFocus()
      if (item.focusTarget)
        item.focusTarget.forceActiveFocus(Qt.TabFocusReason)
      perf.phase = "settling"
      settle.start()
      guard.start()
    }

    onStatusChanged: {
      if (status === Loader.Error) {
        console.log("perf-json: " + JSON.stringify({ "error": "load failed: " + source }))
        Qt.exit(3)
      }
    }
  }

  Timer {
    id: settle
    interval: perf.settleMs
    onTriggered: {
      perf.applySession()
      var screen = screenLoader.item
      if (perf.injectArg.length > 0 && screen && typeof screen.injectEvent === "function") {
        var kind = perf.injectArg.split(":")[0]
        var value = perf.injectArg.indexOf(":") >= 0
                    ? perf.injectArg.slice(perf.injectArg.indexOf(":") + 1) : ""
        screen.injectEvent(kind, value)
      }
      perf.phase = "warming"
      ticker.start()
      perf.invalidate()
    }
  }

  // The wall-clock stop. A screen whose scene never goes dirty again renders no
  // more frames, so the frame target is never reached -- and that is a genuine
  // reading about that screen, not a failure of the measurement. It is reported
  // with `reachedTarget: false` and the frames it did manage.
  Timer {
    id: guard
    interval: perf.maxMs
    onTriggered: {
      if (perf.phase !== "done")
        perf.finish(false)
    }
  }

  // --------------------------------------------------------- the fixed window
  //
  // `--window-ms n` stops the count after n milliseconds of the counting phase
  // instead of after a fixed number of frames, and it exists because the frame
  // count turned out to be the wrong thing to hold fixed.
  //
  // Holding the FRAMES fixed makes two runs comparable in work but not in
  // length: 600 frames of the track is 2.4 seconds and 600 frames of an empty
  // window is 5 milliseconds, so the cheap measurements were over before the
  // machine had settled and their spread was 25 per cent. Holding the TIME fixed
  // makes every run the same length whatever it is measuring, which is what the
  // arithmetic below actually needs -- the frame count becomes the OUTPUT, and
  // the output of a two-and-a-half second window is a number with four figures
  // in it whether the screen costs four milliseconds a frame or eight
  // microseconds.
  //
  // The window is closed by a Timer, but the DURATION reported is not the
  // Timer's nominal interval: it is the animation driver's own elapsed counter
  // read at both ends. A Timer competing with a saturated render loop fires
  // late, and taking its interval on trust would have quietly inflated every
  // reading -- which is precisely the class of mistake this file exists to stop
  // making.
  readonly property int windowMs: parseInt(argument("window-ms", "0"), 10)

  Timer {
    id: measureWindow
    interval: Math.max(1, perf.windowMs)
    onTriggered: {
      if (perf.phase !== "counting")
        return
      perf.windowEnd = ticker.elapsedTime
      perf.phase = "done"
      perf.finish(true)
    }
  }

  // -------------------------------------------------------------- the levers
  //
  // `--spin` and `--alloc` exist to be believed. They are the only work in this
  // process whose size is known exactly, so they are the only work that can show
  // whether a signal is proportional to load or merely correlated with it.
  //
  // The accumulators are written to properties so that neither loop can be
  // eliminated: a JIT is free to delete arithmetic nobody reads.
  function burn(iterations) {
    var accumulator = perf.burnSink
    for (var i = 0; i < iterations; i++)
      accumulator += Math.sqrt(i + 1) * 1e-9
    perf.burnSink = accumulator
  }

  function churn(count) {
    var last = null
    for (var i = 0; i < count; i++)
      last = { "a": i, "b": [i, i + 1], "c": "n" + i }
    perf.allocSink = last
  }

  // ------------------------------------------------------------ frame counting
  //
  // `afterRendering` fires once per real scene-graph frame. It is not the same
  // as an animation tick: a tick that dirties nothing renders nothing, and a
  // frame can be produced without a tick. Both are counted, and both are
  // reported, because the gap between them is the first thing that told us the
  // old number was not measuring frames.
  Connections {
    target: perf

    function onBeforeSynchronizing() {
      if (perf.phase === "idle" || perf.phase === "done")
        return
      if (perf.spinIterations > 0)
        perf.burn(perf.spinIterations)
      if (perf.allocCount > 0)
        perf.churn(perf.allocCount)
    }

    function onAfterRendering() {
      perf.rawRenders += 1
      if (perf.phase === "warming") {
        perf.warmedFrames += 1
        if (perf.warmedFrames >= perf.warmFrames) {
          perf.phase = "counting"
          perf.windowStart = ticker.elapsedTime
          if (perf.windowMs > 0)
            measureWindow.start()
        }
        if (perf.uncapped)
          perf.invalidate()
        return
      }
      if (perf.phase !== "counting")
        return
      perf.renderedFrames += 1
      if (perf.renderedFrames >= perf.frameTarget) {
        perf.windowEnd = ticker.elapsedTime
        perf.phase = "done"
        Qt.callLater(function () { perf.finish(true) })
        return
      }
      // Dirtying the window from inside the render cycle is what schedules the
      // next frame at once instead of at the driver's next beat. It is the whole
      // trick, and it is one line.
      if (perf.uncapped)
        perf.invalidate()
    }
  }

  // The animation driver, sampled for cadence only. `frameTime` is a real in
  // seconds with sub-millisecond resolution, which is more than the driver's
  // own regularity deserves -- but it is exactly what shows the cadence pinned
  // at 16 ms while the cost of the frame triples underneath it, and it is what
  // detects the one case where the cadence does mean something: saturation,
  // when a frame costs more than the driver's interval and the cadence has to
  // give way.
  FrameAnimation {
    id: ticker
    running: false
    onTriggered: {
      if (!perf.uncapped)
        perf.invalidate()
      if (perf.phase !== "counting")
        return
      perf.animationTicks += 1
      var dt = ticker.frameTime
      perf.cadenceSum += dt
      if (dt > perf.cadenceMax)
        perf.cadenceMax = dt
      if (dt < perf.cadenceMin)
        perf.cadenceMin = dt
    }
  }

  // ------------------------------------------------------------- the census
  //
  // Everything below is a property of the scene rather than of a frame, and
  // none of it needs a clock. It is here because it is the only place it can be
  // taken: nothing outside the application can see how many Canvas items a
  // screen instantiated or how many bytes its images occupy once decoded.
  function walk(node, visit) {
    if (!node)
      return
    visit(node)
    var kids = node.children
    if (!kids)
      return
    for (var i = 0; i < kids.length; i++)
      perf.walk(kids[i], visit)
  }

  // The type name Qt prints for an object, tidied: `QQuickRectangle(0x…)` and
  // `Rectangle_QMLTYPE_7(0x…)` both become `Rectangle`, `KitProp_QMLTYPE_23`
  // becomes `KitProp`. Duck-typing answers what a thing costs; this answers
  // what it is called, which is what a reader needs to go and look at it.
  function typeName(item) {
    var text = String(item)
    var cut = text.indexOf("(")
    if (cut > 0)
      text = text.substring(0, cut)
    text = text.replace(/_QMLTYPE_\d+$/, "").replace(/_QML_\d+$/, "")
    if (text.indexOf("QQuick") === 0)
      text = text.substring(6)
    return text
  }

  function isDrawn(item) {
    var node = item
    while (node && node !== perf.contentItem) {
      if (!node.visible || node.opacity <= 0)
        return false
      node = node.parent
    }
    return true
  }

  // Is this an Image, a BorderImage or an AnimatedImage? Duck-typed on the
  // three properties only an image-backed item carries together.
  function isImage(item) {
    return item !== null && item.source !== undefined
           && item.sourceSize !== undefined && item.fillMode !== undefined
  }

  // The size Qt actually decoded the file to. When `sourceSize` is set, Qt
  // decodes to it and the item's implicit size follows; when it is not, the
  // implicit size is the file's own pixel size. Either way the implicit size is
  // the decoded size, which is the number that costs memory -- and it is the
  // number a directory listing cannot show you. `waterTower.png` is 54 KB on
  // disk and 2592x2870 decoded: 28 MB of RGBA for a prop that draws sixty
  // pixels tall.
  function decodedBytes(item) {
    var w = item.sourceSize && item.sourceSize.width > 0
            ? item.sourceSize.width : Math.round(item.implicitWidth)
    var h = item.sourceSize && item.sourceSize.height > 0
            ? item.sourceSize.height : Math.round(item.implicitHeight)
    if (!(w > 0) || !(h > 0))
      return { "w": 0, "h": 0, "bytes": 0 }
    return { "w": w, "h": h, "bytes": w * h * 4 }
  }

  function census() {
    var screen = screenLoader.item
    var counts = {}
    var totals = {
      "items": 0, "drawn": 0, "hidden": 0,
      "images": 0, "canvases": 0, "shaderEffects": 0, "shaderEffectSources": 0,
      "texts": 0, "layers": 0, "layerPixels": 0,
      "textureBytes": 0, "hiddenTextureBytes": 0, "distinctTextures": 0
    }
    var seen = {}
    var biggest = []

    perf.walk(screen, function (item) {
      totals.items += 1
      var drawn = perf.isDrawn(item)
      if (drawn)
        totals.drawn += 1
      else
        totals.hidden += 1

      var name = perf.typeName(item)
      counts[name] = (counts[name] || 0) + 1

      if (item.canvasSize !== undefined && typeof item.requestPaint === "function")
        totals.canvases += 1
      if (item.fragmentShader !== undefined && item.vertexShader !== undefined)
        totals.shaderEffects += 1
      if (item.sourceItem !== undefined && item.recursive !== undefined)
        totals.shaderEffectSources += 1
      if (typeof item.text === "string" && item.font !== undefined
          && item.textFormat !== undefined)
        totals.texts += 1
      // A layer is an offscreen surface the size of the item, redrawn whenever
      // the item changes and composited every frame. It is the most expensive
      // thing in QML that looks like a one-line property.
      if (item.layer && item.layer.enabled) {
        totals.layers += 1
        totals.layerPixels += Math.round(item.width) * Math.round(item.height)
      }

      if (!perf.isImage(item))
        return
      totals.images += 1
      var size = perf.decodedBytes(item)
      if (size.bytes <= 0)
        return
      // Qt's pixmap cache keys on the URL and the requested size, so two items
      // showing one file at one size cost one decode between them. Counting
      // per item would have reported the prop kit several times over.
      var key = String(item.source) + "@" + size.w + "x" + size.h
      if (seen[key])
        return
      seen[key] = true
      totals.distinctTextures += 1
      totals.textureBytes += size.bytes
      if (!drawn)
        totals.hiddenTextureBytes += size.bytes
      biggest.push({ "source": String(item.source).split("/").pop(),
                     "px": size.w + "x" + size.h,
                     "bytes": size.bytes, "drawn": drawn })
    })

    biggest.sort(function (a, b) { return b.bytes - a.bytes })
    var top = []
    for (var i = 0; i < biggest.length && i < 8; i++)
      top.push(biggest[i])

    var byType = []
    for (var key in counts)
      byType.push({ "type": key, "n": counts[key] })
    byType.sort(function (a, b) { return b.n - a.n })
    var topTypes = []
    for (var j = 0; j < byType.length && j < 12; j++)
      topTypes.push(byType[j])

    totals.topTextures = top
    totals.topTypes = topTypes
    return totals
  }

  // ---------------------------------------------------------------- the report
  function finish(reached) {
    perf.phase = "done"
    ticker.stop()
    guard.stop()
    measureWindow.stop()
    if (perf.windowEnd <= perf.windowStart)
      perf.windowEnd = ticker.elapsedTime
    var windowSeconds = Math.max(0, perf.windowEnd - perf.windowStart)
    var report = {
      "screen": perf.screenName,
      "width": perf.wantWidth,
      "height": perf.wantHeight,
      "pixels": perf.wantWidth * perf.wantHeight,
      "framesTarget": perf.frameTarget,
      "windowMs": perf.windowMs,
      "framesRendered": perf.renderedFrames,
      "rawRenders": perf.rawRenders,
      "warmFrames": perf.warmFrames,
      "reachedTarget": reached,
      "animationTicks": perf.animationTicks,
      "spin": perf.spinIterations,
      "alloc": perf.allocCount,
      "pace": perf.uncapped ? "uncapped" : "vsync",
      "redraw": perf.forceRedraw ? "full" : "dirty",
      // The measured window in seconds of wall time, taken from the animation
      // driver's own elapsed counter. It is here to compute the achieved frame
      // rate and NOT to compute a cost: the driver paces the loop, so this
      // number is pinned near frames/60 whatever the frame costs, right up
      // until the frame costs more than the driver's interval.
      "windowSeconds": Number(windowSeconds.toFixed(4)),
      "achievedFps": windowSeconds > 0
                     ? Number((perf.renderedFrames / windowSeconds).toFixed(2)) : 0,
      // THE HEADLINE, in `--pace uncapped`: wall milliseconds per rendered
      // frame, with nothing pacing the loop but the frame itself. In
      // `--pace vsync` it is pinned near 16 and means nothing; read the CPU
      // figure from `npm run perf` there instead.
      "wallMsPerFrame": perf.renderedFrames > 0
                        ? Number((1000 * windowSeconds / perf.renderedFrames).toFixed(4)) : 0,
      "cadenceMeanMs": perf.animationTicks > 0
                       ? Number((1000 * perf.cadenceSum / perf.animationTicks).toFixed(3)) : 0,
      "cadenceMinMs": perf.cadenceMin < 9999 ? Number((1000 * perf.cadenceMin).toFixed(3)) : 0,
      "cadenceMaxMs": Number((1000 * perf.cadenceMax).toFixed(3))
    }
    if (perf.wantCensus)
      report.census = perf.census()
    console.log("perf-json: " + JSON.stringify(report))
    Qt.exit(reached ? 0 : 4)
  }
}
