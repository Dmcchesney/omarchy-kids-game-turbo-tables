import QtQuick
import QtQuick.Window
import qs.Commons
import "../ui"
import "../ui/parts"

// The layer-2 harness: a window that loads one screen out of ui/ with the
// mock theme and an in-memory save file, on a Mac with no shell anywhere near
// it.
//
// This file is the only thing in the repository that imports the mock shell
// singletons. It reads them once and copies the values into ui/Theme, which is
// exactly what layer 3 will do from the real ones -- so the screens are bound
// against the true shape of a theme without ui/ ever naming the shell.
//
// Run it:
//   qml -I dev/imports dev/Harness.qml -- --screen Garage
//
// Every argument, all optional:
//   --screen <Name>     a file in ui/, without the extension. Default Garage.
//   --seed <n>          the race seed to hand the screen. Default 42.
//   --width <px>        window width.  Default 1920.
//   --height <px>       window height. Default 1080.
//   --size <WxH>        both at once, e.g. --size 1366x768.
//   --focus <n>         press Tab n times, through Qt's own focus chain,
//                       before doing anything else. -1 parks focus off every
//                       control, so no focus ring is drawn: the hero shot.
//   --hud on|off        the frame-rate overlay. Default on; off for shots.
//   --settle <ms>       wait before the screenshot. Default 700.
//   --shot <path>       save a PNG of the window to path.
//   --exit              quit once the screenshot is written.
//   --print-focus       print every focus stop's screen-reader name and quit.
//   --settings k=v,k=v  seed the in-memory save file before the screen loads,
//                       e.g. --settings kartBody=3,kartPaint=5,kartNumber=42
//   --transient k=v,k=v set a value the save file never holds, after the
//                       screen loads: `raceMode` and `mathSet` are
//                       Store.sessionOnlyKeys, so --settings cannot reach
//                       them and the garage could not be shot in Practice.
//                       Named --transient and not --session because Qt's own
//                       `qml` tool eats a `--session` argument before any of
//                       this sees it, silently.
//   --measure <ms>      run the screen for that long and print the frame rate.
//   --sheets <url>      car sheets from another directory (see the rig below).
//   --kart ...          show one car-sheet cell instead of a screen (below).
//   --travel <n>        for a screen with a `travel` property (TrackView on
//                       its own): put the camera there and hold it. 288 is
//                       the apex of sector 8's right-hander, 108 sector 3's
//                       left; nothing advances without Race.qml driving it.
//   --field <d,d,...>   for a screen with setKarts() (TrackView): the child's
//                       car from the seeded settings, plus one rival per
//                       delta, that many questions up the road (up to three).
//   --dump-text         print every visible Text in the loaded screen as one
//                       line -- window rect, declared colour with its alpha,
//                       pixel size, and the string -- then quit. It is what
//                       makes a contrast table cover EVERY text element
//                       rather than the ones a builder remembered.
//   --dump-rects        the same walk, but printing every item that carries
//                       an objectName, so a measurement script can find the
//                       car on the dais without guessing at geometry. Columns:
//                       name, x, y, width, height, effective opacity (0 when
//                       the item is not drawn at all).
//   --warmup <n>        for a screen with buildRace() (Race): advance the race
//                       by n scripted correct answers before showing it, so a
//                       shot has lamps lit, a charge part-full and rivals up
//                       the road. The screen's own `warmup` property; the race
//                       is rebuilt after it is set.
//
// ------------------------------------------------------------------ PIECE F
//
//   --inject <e>[:<a>]  put the loaded screen into the situation a strip is
//                       about and let THE REAL RULES run. The screen's own
//                       `injectEvent(kind, arg)` seeds the hand the strip is
//                       about to spend and then calls `Engine.step` with
//                       `useCard`, exactly as the child's Enter key does, so
//                       every event the strip reacts to is the engine's own.
//                       ROUND 2 CHANGED THIS: it used to synthesise the event
//                       and skip the engine, which made every strip evidence
//                       about the view rather than about the game. Events:
//
//                         --inject cardUsed:wrench    the child plays a card
//                         --inject hit:pothole        a rival plays one at the
//                                                     child (the rival is the
//                                                     actor; the engine writes
//                                                     the stall and the lamps)
//                         --inject blocked:wrench     the target is given a
//                                                     Roll Cage first, so the
//                                                     RULES emit the block
//                         --inject swap               a Tow Hook, played
//                         --inject handDealt          answer the twelfth in a
//                                                     row (needs --warmup 11)
//                         --inject chooseCard:1       press 1 then Enter, which
//                                                     is the hand's slam beat
//                                                     (a key press, not an event)
//
//                       The card names are the engine's own keys: nitro,
//                       oilSlick, wrench, pothole, rollCage, pileUp, turbo,
//                       towHook.
//
//                       A targeted card may name WHO it is aimed at with a
//                       `+` suffix: `+near` (the default) is the nearest rival,
//                       `+leader` is the racer furthest up the road -- which at
//                       a Grand Prix's saturating tail is a kart at the
//                       vanishing point, and is the realistic worst case a
//                       child is handed when the race picks the distance.
//
//                         --inject cardUsed:wrench+leader
//
//   --strip <path>      write a CONTACT SHEET of frames from the injection to
//                       <path>, and the individual frames beside it as
//                       <path minus .png>-<index>.png at the full window size.
//   --strip-step <ms>   milliseconds of the screen's clock between frames.
//                       Default 60, which is the step the piece F gate asks for.
//   --strip-frames <n>  how many frames. Default 10.
//   --strip-preroll <ms> how long the screen runs before the injection, so the
//                       road is moving rather than sitting on its first frame.
//                       Default 320. Stepped in 16 ms slices like the rest.
//   --strip-scale <f>   how much each frame is scaled down in the contact
//                       sheet. Default 0.5; the individual frames are always
//                       full size.
//   --strip-columns <n> columns in the contact sheet. Default 2.
//
//                       `--strip --dump-rects` prints every named item's box
//                       on every frame of the strip, prefixed by a `frame`
//                       line, so the fact's box, the answer field's box and
//                       every effect item's box can be compared frame by frame
//                       on the very frames the contact sheet shows.
//
//                       THE STRIP IS DETERMINISTIC, and that is the whole point
//                       of it. `--strip` sets the screen's `externalClock`,
//                       which stops its FrameAnimation and its 100 ms engine
//                       pulse, stops the caret's blink, and cuts the callouts'
//                       and the minimap's wall-clock fades. Every millisecond
//                       the screen sees is one this file handed it. The same
//                       strip written twice is the same bytes; the piece F
//                       evidence proves that by writing one twice and diffing.
//
//   --hide-text         render with every Text painted transparent (NOT
//                       hidden: hiding one reflows its Row). Paired with
//                       --dump-text it gives the exact background behind each
//                       string: the same frame, same size, same seed, with
//                       the glyphs taken out, so a contrast figure is read
//                       off the shipped picture instead of off an assumption
//                       about which surface a string happens to sit on.
Window {
  id: harness

  // ------------------------------------------------------ argument parsing
  function argument(name, fallback) {
    var argv = Qt.application.arguments
    for (var i = 0; i < argv.length; i++)
      if (argv[i] === "--" + name && i + 1 < argv.length)
        return argv[i + 1]
    return fallback
  }
  function flag(name) {
    return Qt.application.arguments.indexOf("--" + name) >= 0
  }

  readonly property string screenName: argument("screen", "Garage")
  readonly property int seed: parseInt(argument("seed", "42"), 10)
  readonly property string sizeArg: argument("size", "")
  readonly property int wantWidth: sizeArg.length > 0
                                   ? parseInt(sizeArg.split("x")[0], 10)
                                   : parseInt(argument("width", "1920"), 10)
  readonly property int wantHeight: sizeArg.length > 0
                                    ? parseInt(sizeArg.split("x")[1], 10)
                                    : parseInt(argument("height", "1080"), 10)
  readonly property int focusStops: parseInt(argument("focus", "0"), 10)
  readonly property bool hud: argument("hud", "on") !== "off"
  readonly property int settleMs: parseInt(argument("settle", "700"), 10)
  readonly property string shotPath: argument("shot", "")
  readonly property bool quitAfter: flag("exit")
  readonly property bool printFocus: flag("print-focus")
  readonly property string settingsArg: argument("settings", "")
  readonly property string travelArg: argument("travel", "")
  readonly property string fieldArg: argument("field", "")
  // Settings the save file never holds. `raceMode` and `mathSet` are
  // `Store.sessionOnlyKeys` -- the design's Data row does not persist them --
  // so `--settings` cannot reach them and a shot of the garage in Practice
  // was impossible to take. This applies them AFTER the screen has loaded,
  // through Store.setSetting, which is the same call the arrow key makes.
  readonly property string transientArg: argument("transient", "")
  readonly property bool dumpText: flag("dump-text")
  readonly property bool dumpRects: flag("dump-rects")
  readonly property bool hideText: flag("hide-text")
  readonly property int warmup: parseInt(argument("warmup", "0"), 10)

  // ---------------------------------------------------------------- piece F
  readonly property string injectArg: argument("inject", "")
  readonly property string injectKind: injectArg.split(":")[0]
  readonly property string injectValue: injectArg.indexOf(":") >= 0
                                        ? injectArg.slice(injectArg.indexOf(":") + 1) : ""
  readonly property string stripPath: argument("strip", "")
  readonly property bool stripMode: stripPath.length > 0
  readonly property int stripStep: parseInt(argument("strip-step", "60"), 10)
  readonly property int stripFrames: parseInt(argument("strip-frames", "10"), 10)
  readonly property int stripPreroll: parseInt(argument("strip-preroll", "320"), 10)
  readonly property real stripScale: parseFloat(argument("strip-scale", "0.5"))
  readonly property int stripColumns: parseInt(argument("strip-columns", "2"), 10)

  // ------------------------------------------------------ the item walk
  // One depth-first walk of the loaded screen, used by --dump-text,
  // --dump-rects and --hide-text so all three see exactly the same tree in
  // exactly the same order. `visit` is called with every Item under `node`.
  function walk(node, visit) {
    if (!node)
      return
    visit(node)
    var kids = node.children
    if (!kids)
      return
    for (var i = 0; i < kids.length; i++)
      harness.walk(kids[i], visit)
  }

  // Is this a Text? Duck-typed on the three properties only a text item has
  // together, because QML has no instanceof for a built-in type here.
  function isText(item) {
    return item !== null && typeof item.text === "string"
           && item.font !== undefined && item.textFormat !== undefined
           && item.horizontalAlignment !== undefined
  }

  function hex2(n) {
    var s = Math.round(Math.max(0, Math.min(255, n * 255))).toString(16)
    return s.length < 2 ? "0" + s : s
  }

  function colourText(c) {
    return "#" + hex2(c.r) + hex2(c.g) + hex2(c.b) + " a=" + c.a.toFixed(3)
  }

  // Is the item drawn at all? An invisible ancestor hides a visible child, so
  // opacity and visibility are both walked up to the screen root.
  function effectiveOpacity(item) {
    var node = item
    var opacity = 1
    while (node && node !== harness.contentItem) {
      if (!node.visible)
        return 0
      opacity *= node.opacity
      node = node.parent
    }
    return opacity
  }

  function runDump() {
    var screen = screenLoader.item
    var count = 0
    harness.walk(screen, function (item) {
      if (harness.dumpRects && String(item.objectName).length > 0) {
        // PIECE F ROUND 6 -- THE BOX IS THE DRAWN BOX.
        //
        // This used to print `mapToItem(root, 0, 0)` for the origin and
        // `item.width`/`item.height` for the size, and those two do not agree
        // about an item that carries a `scale`: the mapped point IS through the
        // transform and the width is NOT. The `+5` tag pops in with a scale
        // that runs 0.70 to 1.00, so a round-6 measurement read its box as
        // 69x44 standing at the position of a 56x36 one and reported an
        // overlap with a kart that is not on the screen. Mapping all four
        // corners is exact for a scale about any origin.
        var r = item.mapToItem(harness.contentItem, 0, 0, item.width, item.height)
        // The seventh column is the EFFECTIVE OPACITY, added by piece F: the
        // walk prints every named item whether or not it is drawn, and a proof
        // that no effect box crosses the fact is only as good as its knowing
        // which boxes were on the screen. It is the same `effectiveOpacity`
        // --dump-text has always used, so 0 means "not drawn at all".
        console.log("rect\t" + item.objectName + "\t" + Math.round(r.x) + "\t"
                    + Math.round(r.y) + "\t" + Math.round(r.width) + "\t"
                    + Math.round(r.height) + "\t"
                    + harness.effectiveOpacity(item).toFixed(3))
      }
      if (harness.dumpText && harness.isText(item) && item.text.length > 0
          && harness.effectiveOpacity(item) > 0.02) {
        var p = item.mapToItem(harness.contentItem, 0, 0)
        count += 1
        console.log("text\t" + Math.round(p.x) + "\t" + Math.round(p.y) + "\t"
                    + Math.round(item.width) + "\t" + Math.round(item.height)
                    + "\t" + harness.colourText(item.color) + "\to="
                    + harness.effectiveOpacity(item).toFixed(3) + "\t"
                    + item.font.pixelSize + "\t"
                    + item.text.replace(/\n/g, " "))
      }
    })
    if (harness.dumpText)
      console.log("text count: " + count)
  }

  // Hide the glyphs WITHOUT changing the layout. Setting `visible` false on a
  // Text inside a Row or a Column makes the layout reflow and every item after
  // it move, so the background frame no longer matches the real one -- which
  // is exactly how a first pass at this measurement reported a signal tile's
  // caption as 1.00:1 against its own icon. Painting the text transparent
  // leaves every item where it is.
  function applySession() {
    if (harness.transientArg.length === 0)
      return
    var pairs = harness.transientArg.split(",")
    for (var i = 0; i < pairs.length; i++) {
      var parts = pairs[i].split("=")
      if (parts.length !== 2)
        continue
      var raw = parts[1].trim()
      Store.setSetting(parts[0].trim(),
                       isFinite(Number(raw)) ? Number(raw) : raw)
    }
  }

  function applyHideText() {
    harness.walk(screenLoader.item, function (item) {
      if (harness.isText(item))
        item.color = "transparent"
    })
  }

  // A fixed field for a bare TrackView: the child's car from the seeded
  // settings at seat 0, then one rival per delta at seats 1..3, each a
  // different body and paint. Progress is in questions; the view turns a
  // delta into a depth on the road, so `--field 2,4,8` is three cars at
  // increasing distance and `--travel` decides what corner they are in.
  function seedField(view) {
    var deltas = harness.fieldArg.split(",")
    var list = [{
      "id": "you", "name": "YOU", "number": Store.setting("kartNumber"),
      "body": Store.setting("kartBody"), "seat": 0,
      "paint": Theme.paints[Store.setting("kartPaint")],
      "progress": 0, "isHuman": true, "ghost": false
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

  width: wantWidth
  height: wantHeight
  visible: true
  title: "Turbo Tables harness -- " + screenName
  // Transparent in sprite mode, so grabToImage returns the kart's own alpha.
  color: kartMode ? "transparent" : Theme.ground

  // ---------------------------------------------------------------- store
  MemoryStore { id: memory }

  // ---------------------------------------------------------------- theme
  // The one place the mock shell singletons are read. Copy, do not bind: this
  // is the same handoff layer 3 makes, and doing it as an explicit copy is
  // what proves ui/Theme works as a plain adapter with no shell behind it.
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

  // A seeded save file, so a screen can be opened in a chosen state without
  // anyone having to drive it there first. Values parse as numbers when they
  // look like numbers and as booleans for true/false; anything else stays a
  // string, which is what the save file would hold anyway.
  function seedSettings(spec) {
    if (spec.length === 0)
      return
    var settings = {}
    var pairs = spec.split(",")
    for (var i = 0; i < pairs.length; i++) {
      var parts = pairs[i].split("=")
      if (parts.length !== 2)
        continue
      var key = parts[0].trim()
      var raw = parts[1].trim()
      var value = raw
      if (raw === "true")
        value = true
      else if (raw === "false")
        value = false
      else if (raw.length > 0 && isFinite(Number(raw)))
        value = Number(raw)
      settings[key] = value
    }
    memory.data = { "version": 1, "settings": settings, "records": {}, "facts": {} }
  }

  Component.onCompleted: {
    applyTheme()
    if (harness.sheetsArg.length > 0)
      Theme.carSheetRoot = harness.sheetsArg
    seedSettings(harness.settingsArg)
    Store.backend = memory
    // Only now may the screen load: the theme, the sheets and the seeded
    // save file are all in place, so nothing binds to a default and then
    // rebinds a frame later.
    harness.ready = true
    console.log("harness: screen=" + screenName + " seed=" + seed
                + " size=" + wantWidth + "x" + wantHeight
                + " font=" + Theme.mono
                + " accent=" + Theme.accent
                + " shellCornerRadius=" + Theme.shellCornerRadius)
    if (kartMode)
      startup.start()
  }

  // ------------------------------------------------------- the sprite rig
  //
  // PIECE C. `--kart` shows ONE CELL of a baked car sheet on a TRANSPARENT
  // background instead of loading a screen, so a critic can shoot any cell
  // headless and read its alpha. There is no live renderer left to rig: the
  // cell is the art, and this is a viewer for it.
  //
  //   --kart <n>                body 0..5
  //   --kart-paint <n>          paint index, default 0
  //   --kart-yaw <n>            column 0..7, default 0
  //   --kart-camera stall|road  row group, default stall
  //   --kart-scale 1|0.5|0.25   row within the group, default 1
  //   --kart-pixels <n>         whole-number upscale 1..3, default 3
  //   --kart-number <n>         the number to overlay, default 7
  //   --kart-glow <0..1>        tail-lamp glow (road camera), default 0
  //   --sheets <dir-url>        read sheets from here instead of assets/karts/
  //                             (a file: URL ending in a slash). Applies to
  //                             every car on every screen, not only the rig.
  readonly property string kartArg: argument("kart", "")
  readonly property bool kartMode: kartArg.length > 0
  readonly property int kartIndex: parseInt(kartArg.length > 0 ? kartArg : "0", 10)
  readonly property int kartPaint: parseInt(argument("kart-paint", "0"), 10)
  readonly property int kartYaw: parseInt(argument("kart-yaw", "0"), 10)
  readonly property string kartCamera: argument("kart-camera", "stall")
  readonly property real kartScale: parseFloat(argument("kart-scale", "1"))
  readonly property int kartPixels: parseInt(argument("kart-pixels", "3"), 10)
  readonly property int kartNumber: parseInt(argument("kart-number", "7"), 10)
  readonly property real kartGlow: parseFloat(argument("kart-glow", "0"))
  readonly property string sheetsArg: argument("sheets", "")

  // A Loader, and one that waits for `ready`, so the cell is only ever asked
  // for after `--sheets` has been applied and never from a screen run.
  Loader {
    id: kartRig
    active: harness.kartMode && harness.ready
    anchors.fill: parent

    sourceComponent: CarSprite {
      x: Math.round(kartRig.width / 2 - drawnWidth / 2 + anchorDx)
      y: Math.round(kartRig.height / 2 - drawnHeight / 2 + anchorDy)
      body: harness.kartIndex
      paint: harness.kartPaint
      number: harness.kartNumber
      camera: harness.kartCamera
      yaw: harness.kartYaw
      sheetScale: harness.kartScale
      pixelScale: harness.kartPixels
      lampGlow: harness.kartGlow
    }
  }

  // --------------------------------------------------------------- screen
  property bool ready: false

  Loader {
    id: screenLoader
    active: !harness.kartMode && harness.ready
    anchors.fill: parent
    focus: true
    source: Qt.resolvedUrl("../ui/" + harness.screenName + ".qml")

    onLoaded: {
      if (item.hasOwnProperty("seed"))
        item.seed = harness.seed
      // PIECE F. The warm-up and the external clock both have to be in place
      // BEFORE the race is rebuilt, or the strip's first frame is a race that
      // was built under a different clock.
      if (harness.warmup > 0 && item.hasOwnProperty("warmup"))
        item.warmup = harness.warmup
      if (harness.stripMode && item.hasOwnProperty("externalClock"))
        item.externalClock = true
      if ((harness.warmup > 0 || harness.stripMode) && typeof item.buildRace === "function")
        item.buildRace()
      if (harness.travelArg.length > 0 && item.hasOwnProperty("travel"))
        item.travel = parseFloat(harness.travelArg)
      if (harness.fieldArg.length > 0 && typeof item.setKarts === "function")
        harness.seedField(item)
      item.forceActiveFocus()
      if (item.focusTarget)
        item.focusTarget.forceActiveFocus(Qt.TabFocusReason)
      startup.start()
    }

    onStatusChanged: {
      if (status === Loader.Error) {
        console.log("harness: could not load " + source)
        // A shot or a measurement that was asked to exit must not hang on a
        // screen that failed to load: exit with a code a script can read.
        if (harness.quitAfter || harness.measureMs > 0)
          Qt.exit(3)
      }
    }
  }

  // Somewhere for focus to go that is not a control. `--focus -1` parks the
  // active focus here, so no ring is drawn anywhere on the screen.
  //
  // ROUND-6, and it exists because of a fair criticism of the EVIDENCE rather
  // than of the screen: the frame the last round presented as "the design"
  // was byte-identical to its own focus-00 frame, so the picture a critic was
  // asked to judge carried a focus ring on the KART BODY selector. The ring
  // is correct -- the screen is keyboard-first and something always has
  // focus when it is opened with the keyboard -- but it is not the shot to
  // lead with, and the fix belongs in the harness, not in the screen.
  Item {
    id: focusPark
    width: 0
    height: 0
    activeFocusOnTab: false
  }

  Connections {
    target: screenLoader.item
    ignoreUnknownSignals: true
    function onRaceRequested() { console.log("harness: raceRequested") }
    function onLeaveRequested() { console.log("harness: leaveRequested") }
  }

  // ----------------------------------------------------- frame-rate meter
  // smoothFrameTime is the running average frame duration in seconds, which
  // is the number the plan asks the harness to show before any art is
  // finished.
  FrameAnimation {
    id: ticker
    running: harness.hud
  }

  Rectangle {
    id: meter
    visible: harness.hud
    z: 100
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 8
    width: meterText.implicitWidth + 20
    height: meterText.implicitHeight + 12
    radius: 4
    color: Qt.rgba(0, 0, 0, 0.72)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.2)

    Text {
      id: meterText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      color: "#9ece6a"
      font.family: Theme.mono
      font.pixelSize: 13
      text: {
        var seconds = ticker.smoothFrameTime
        var fps = seconds > 0 ? (1 / seconds) : 0
        return fps.toFixed(1) + " fps   " + (seconds * 1000).toFixed(2) + " ms   "
               + harness.width + "x" + harness.height
      }
    }
  }

  // ------------------------------------------------- non-interactive shots
  //
  // ROUND-8. This used to advance focus with nextItemInFocusChain() and claim
  // that was "the function Qt's own Tab handler calls", so --focus 5 landed
  // where five Tab presses land. A critic's note against that was fair even
  // then -- it measured the mechanism rather than the affordance -- and it is
  // now simply wrong for the garage: the stops are deliberately OUT of Qt's
  // implicit chain (see the note in ui/Garage.qml), so nextItemInFocusChain()
  // finds nothing there at all.
  //
  // A screen that publishes moveFocus() is now advanced through it, which is
  // the exact function its Tab handler calls: one call short of the key
  // itself. That is as close as a QML process can get without QtTest, and it
  // is stated here rather than implied, because ONLY
  // tests/qml/tst_garage_keyboard.qml presses a real key. No screenshot in any
  // evidence pack proves a key was pressed; the test file does.
  function tabForward(times) {
    var screen = screenLoader.item
    var owned = screen && typeof screen.moveFocus === "function"
                && typeof screen.stopIndex === "function"
    for (var i = 0; i < times; i++) {
      if (owned) {
        screen.moveFocus(1)
        continue
      }
      var current = harness.activeFocusItem
      if (!current)
        return
      var next = current.nextItemInFocusChain(true)
      if (!next)
        return
      next.forceActiveFocus(Qt.TabFocusReason)
    }
  }

  Timer {
    id: startup
    interval: 60
    onTriggered: {
      var screen = screenLoader.item
      if (harness.kartMode) {
        if (harness.shotPath.length > 0)
          settle.start()
        return
      }
      if (harness.focusStops < 0)
        focusPark.forceActiveFocus(Qt.OtherFocusReason)
      else if (harness.focusStops > 0)
        harness.tabForward(harness.focusStops)

      harness.applySession()
      if (harness.hideText)
        harness.applyHideText()
      if (harness.dumpText || harness.dumpRects) {
        harness.runDump()
        // In strip mode the dump is per FRAME, below, so the run carries on.
        if (harness.shotPath.length === 0 && !harness.stripMode) {
          Qt.exit(0)
          return
        }
      }

      if (harness.printFocus && screen && screen.stops !== undefined) {
        for (var j = 0; j < screen.stops.length; j++)
          console.log("focus " + j + ": " + screen.focusName(j))
        Qt.exit(0)
        return
      }
      if (harness.stripMode)
        stripStart.start()
      else if (harness.shotPath.length > 0) {
        // A plain shot may still carry an injection, so a single frame of an
        // effect can be taken without a whole strip.
        if (harness.injectArg.length > 0 && screen
            && typeof screen.injectEvent === "function")
          console.log("harness: inject " + harness.injectArg + " -> "
                      + screen.injectEvent(harness.injectKind, harness.injectValue))
        settle.start()
      } else if (harness.measureMs > 0) {
        if (harness.injectArg.length > 0 && screen
            && typeof screen.injectEvent === "function")
          console.log("harness: inject " + harness.injectArg + " -> "
                      + screen.injectEvent(harness.injectKind, harness.injectValue))
        measure.start()
      }
    }
  }

  // ------------------------------------------------------ frame-rate run
  // `--measure <ms>` runs the loaded screen for that long after the settle
  // delay, counting rendered frames with a FrameAnimation of its own, then
  // prints the mean frame rate and quits. It is the number the plan asks for
  // -- "frame rate on the track unchanged or better" -- taken the same way
  // before and after a change, on the same renderer, so it is comparable.
  readonly property int measureMs: parseInt(argument("measure", "0"), 10)
  property int measuredFrames: 0

  FrameAnimation {
    id: counter
    running: false
    onTriggered: harness.measuredFrames += 1
  }

  Timer {
    id: measure
    interval: harness.settleMs
    onTriggered: {
      harness.measuredFrames = 0
      counter.start()
      measureEnd.start()
    }
  }

  Timer {
    id: measureEnd
    interval: harness.measureMs
    onTriggered: {
      counter.stop()
      var seconds = harness.measureMs / 1000
      console.log("harness: measured " + harness.measuredFrames + " frames in "
                  + harness.measureMs + " ms = "
                  + (harness.measuredFrames / seconds).toFixed(1) + " fps ("
                  + (1000 * seconds / Math.max(1, harness.measuredFrames)).toFixed(2)
                  + " ms/frame) at " + harness.width + "x" + harness.height
                  + " screen=" + harness.screenName)
      Qt.exit(0)
    }
  }

  // ========================================================================
  // PIECE F -- the frame strip.
  // ========================================================================
  //
  // A strip is: run the screen forward on a clock this file owns, deliver one
  // engine-shaped event, then grab a frame every `--strip-step` milliseconds of
  // that clock. The frames go out at the full window size and a contact sheet
  // of them, labelled with the millisecond offset of each, goes to `--strip`.
  //
  // WHY THE CLOCK IS OURS. Everything the effect layer draws is a pure function
  // of `TrackView.fxClock`, which is stepped by `advance(dt)` -- so if the dt
  // comes from a FrameAnimation sampling the wall clock, two runs land between
  // different beats and the strip is different bytes each time. A strip that
  // differs run to run cannot be evidence, so `--strip` sets the screen's
  // `externalClock` and hands it exactly the milliseconds below.
  //
  // The contact sheet is composed in QML rather than by a second tool: the
  // frames are loaded back as Images into a Grid and the Grid is grabbed. That
  // keeps the whole strip one command, which is what the piece F gate asks for
  // ("anyone can reproduce a strip in one command").
  property int stripIndex: 0
  property var stripFiles: []
  readonly property string stripStem: harness.stripPath.replace(/\.png$/i, "")

  function stripFileFor(i) {
    return harness.stripStem + "-" + (i < 10 ? "0" : "") + i + ".png"
  }

  function stripBegin() {
    var screen = screenLoader.item
    if (!screen) {
      Qt.exit(3)
      return
    }
    // The pre-roll, in 16 ms slices: the road has to be moving before the card
    // is played, or the first frame of every strip is a stationary world.
    var slices = Math.max(0, Math.round(harness.stripPreroll / 16))
    for (var i = 0; i < slices; i++)
      if (typeof screen.stepClock === "function")
        screen.stepClock(16)
    if (harness.injectArg.length > 0 && typeof screen.injectEvent === "function") {
      var ok = screen.injectEvent(harness.injectKind, harness.injectValue)
      console.log("harness: inject " + harness.injectArg + " -> " + ok)
    }
    harness.stripIndex = 0
    harness.stripFiles = []
    stripGrab()
  }

  function stripGrab() {
    if (harness.stripIndex >= harness.stripFrames) {
      stripCompose()
      return
    }
    // `--strip --dump-rects` prints every named item's box on every frame of
    // the strip, so "no effect item ever crosses the fact" is a measurement of
    // the same frames the contact sheet shows rather than a separate claim.
    if (harness.dumpRects || harness.dumpText) {
      console.log("frame\t" + harness.stripIndex + "\t"
                  + (harness.stripIndex * harness.stripStep))
      harness.runDump()
    }
    var path = harness.stripFileFor(harness.stripIndex)
    var started = harness.contentItem.grabToImage(function (result) {
      result.saveToFile(path)
      var files = harness.stripFiles.slice()
      files.push({ "path": path, "at": harness.stripIndex * harness.stripStep })
      harness.stripFiles = files
      harness.stripIndex += 1
      var screen = screenLoader.item
      if (screen && typeof screen.stepClock === "function")
        screen.stepClock(harness.stripStep)
      // Next grab on the following event-loop turn, so the step above has been
      // applied to every binding before the frame is rendered.
      stripNext.restart()
    }, Qt.size(harness.width, harness.height))
    if (!started) {
      console.log("harness: grabToImage refused on strip frame " + harness.stripIndex)
      Qt.exit(2)
    }
  }

  Timer {
    id: stripNext
    interval: 1
    onTriggered: harness.stripGrab()
  }

  function stripCompose() {
    sheetLoader.active = true
    sheetSettle.restart()
  }

  Loader {
    id: sheetLoader
    active: false
    // Off the visible area: the sheet is grabbed, never looked at in the
    // window, and it is taller than the window by design.
    x: 0
    y: harness.height + 40

    sourceComponent: Column {
      spacing: 0

      Rectangle {
        width: harness.stripColumns * Math.round(harness.width * harness.stripScale)
        height: 44
        color: "#101018"

        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: 14
          textFormat: Text.PlainText
          color: "#f2e6c4"
          font.family: Theme.mono
          font.bold: true
          font.pixelSize: 20
          text: "TURBO TABLES  ·  " + harness.screenName + "  ·  inject "
                + (harness.injectArg.length > 0 ? harness.injectArg : "(none)")
                + "  ·  seed " + harness.seed + "  ·  warmup " + harness.warmup
                + "  ·  " + harness.stripStep + " ms steps  ·  "
                + harness.width + "x" + harness.height
                + (Store.setting("reducedMotion") === true ? "  ·  REDUCED MOTION" : "")
        }
      }

      Grid {
        columns: harness.stripColumns
        spacing: 0

        Repeater {
          model: harness.stripFiles

          Column {
            spacing: 0

            Rectangle {
              width: Math.round(harness.width * harness.stripScale)
              height: 26
              color: "#1a1b26"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                textFormat: Text.PlainText
                color: "#9ece6a"
                font.family: Theme.mono
                font.bold: true
                font.pixelSize: 16
                text: "t = +" + modelData.at + " ms"
              }
            }

            Image {
              width: Math.round(harness.width * harness.stripScale)
              height: Math.round(harness.height * harness.stripScale)
              source: "file://" + modelData.path
              smooth: true
              cache: false
              asynchronous: false
            }
          }
        }
      }
    }
  }

  Timer {
    id: sheetSettle
    // The frames are read back off disk; one turn of the loop is enough with
    // `asynchronous: false`, and this is a little more than that.
    interval: 200
    onTriggered: {
      var item = sheetLoader.item
      if (!item) {
        console.log("harness: contact sheet did not build")
        Qt.exit(2)
        return
      }
      var started = item.grabToImage(function (result) {
        result.saveToFile(harness.stripPath)
        console.log("harness: wrote " + harness.stripPath + " at "
                    + Math.round(item.width) + "x" + Math.round(item.height)
                    + " from " + harness.stripFiles.length + " frames of "
                    + harness.width + "x" + harness.height)
        Qt.exit(0)
      }, Qt.size(Math.round(item.width), Math.round(item.height)))
      if (!started) {
        console.log("harness: grabToImage refused on the contact sheet")
        Qt.exit(2)
      }
    }
  }

  Timer {
    id: stripStart
    interval: harness.settleMs
    onTriggered: harness.stripBegin()
  }

  Timer {
    id: settle
    interval: harness.settleMs
    onTriggered: {
      var screen = screenLoader.item
      if (screen && typeof screen.focusedName === "function")
        console.log("harness: focus is on " + JSON.stringify(screen.focusedName()))
      var started = harness.contentItem.grabToImage(function (result) {
        result.saveToFile(harness.shotPath)
        console.log("harness: wrote " + harness.shotPath
                    + " at " + harness.width + "x" + harness.height)
        if (harness.quitAfter)
          Qt.exit(0)
      }, Qt.size(harness.width, harness.height))
      if (!started) {
        console.log("harness: grabToImage refused")
        if (harness.quitAfter)
          Qt.exit(2)
      }
    }
  }
}
