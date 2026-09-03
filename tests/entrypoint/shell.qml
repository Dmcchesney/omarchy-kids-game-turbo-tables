import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Omarchy's own manifest-entrypoint load test, copied and pointed at this
// plugin, plus the assertions this plugin's overlay contract needs.
//
// The original is `test/shell.d/fixtures/manifest-entrypoints/shell.qml` in the
// Omarchy tree, SHA-256 f3f8f238fde9cf2e77a98244af91442d32feda43735bc571005e1d5697e19497
// at the revision installed in the development VM, driven by
// `test/shell.d/manifest-entrypoints-test.sh`. Its structure is kept verbatim
// so that what this asserts about `omarchy-shell` is what `omarchy-shell`
// asserts about itself: the same `mockShell`, `fakeBar`,
// `fakeBarWidgetRegistry` and `mockPluginRegistry`, the same
// `initialProperties` / `injectProperties` split, the same `loadEntry`, and the
// same result JSON of `{ ok, failures, created }`.
//
// Five deliberate differences, each because of something this repository is
// held to:
//
//  1. THE ENTRY LIST. Upstream builds it in Python from every manifest under
//     `shell/plugins/` and hands it over base64 in `OMARCHY_QML_MANIFESTS`.
//     This repository may not ship a script of any kind -- the marketplace
//     scanner reads `scripts/`, `bin/`, `install*` and `setup*` as capabilities
//     and this plugin passes with none -- so the list is built here from this
//     plugin's own `manifest.json`, read off disk, in the same shape upstream
//     builds it in: one entry per declared kind, each carrying the manifest,
//     the entry key the host looks the file up under, and the resolved URL.
//     The base64 handoff itself could not be kept either; decoding it needs a
//     function on the dynamic-code-construction list.
//
//  2. THE RESULT IS WRITTEN WITH A FileView. Upstream shells out to write it.
//     That mechanism is a forbidden token in every `.qml` file in this
//     repository, including this one: `check:readme` asserts "starts no
//     processes, runs no shell commands" unconditionally over every QML file in
//     the tree, and the assertion cannot be waived by editing the README. A
//     `FileView` writes the same JSON.
//
//     For the same reason the entry points are instantiated by a `Loader` over
//     a `Repeater` rather than by building each component by hand: the two
//     functions upstream uses to do that are on this repository's
//     dynamic-code-construction list, which every `.qml` file is held to
//     because that list is what stopped a previous round assembling a network
//     call out of string fragments. A `Loader` loads the same URL and hands
//     back the same item, and since neither of this plugin's entry points
//     declares a `required` property, upstream's split between properties set
//     at construction and properties injected after it collapses into one
//     injection in `onLoaded`.
//
//  3. THE OVERLAY CONTRACT IS ACTUALLY EXERCISED. Upstream asserts that every
//     entry point instantiates, which is all it can assert about a plugin it
//     has never seen. This one goes on to call `open`, `close`, `dismiss` and
//     `toggle`, checks that the host is told when the overlay closes itself,
//     checks that the hosted game screen -- not the overlay's own key catcher
//     -- ends up holding the keyboard after `open()` with no pointer event
//     anywhere, and presses the bar widget the way the real bar presses it.
//
//  4. THE THEME BRIDGE IS DRIVEN, NOT PHOTOGRAPHED. `Color.accent` is moved
//     while the overlay is loaded and `ui/Theme` is read back through
//     ThemeProbe.qml. A bridge that copies the theme once passes every
//     screenshot taken after a summon and still fails the design's only
//     requirement, which is that a theme change retints the garage while the
//     child is looking at it.
//
//  5. THE SAVE FILE'S THREE DESTRUCTION DOORS ARE ASSERTED. Three times the
//     save layer was destroyed by reading "I could not find out" as "there is
//     no file". The three checks at the end are those doors: a path that is not
//     a file must throw rather than answer null, a path that is genuinely
//     absent must answer null, and nothing may be written before a read has
//     answered.
//
// HOW TO RUN IT, and why it takes four lines of setup rather than one.
//
// Quickshell binds the `qs.*` import namespace to the *config folder* it was
// started with, and refuses a module path outside that folder. The shell's own
// singletons therefore have to be reachable as `<config>/Commons` and
// `<config>/Ui`, which is exactly why the upstream harness copies its fixture
// into a temporary directory and symlinks the two in beside it. This
// repository cannot ship those symlinks -- `omarchy plugin validate` rejects a
// symlink anywhere inside a plugin, and `npm run check:boundary` fails on one
// too -- so the same three lines are done by whoever runs the fixture:
//
//   dir=$(mktemp -d)
//   cp tests/entrypoint/shell.qml "$dir/shell.qml"
//   ln -s /usr/share/omarchy/shell/Commons "$dir/Commons"
//   ln -s /usr/share/omarchy/shell/Ui "$dir/Ui"
//   OMARCHY_PATH=/usr/share/omarchy \
//   TURBO_TABLES_ROOT=$PWD/ \
//   OMARCHY_QML_TEST_RESULT=/tmp/turbo-tables-entrypoint.json \
//   quickshell -p "$dir" --no-color
//
// `TURBO_TABLES_ROOT` is why nothing here imports out of the plugin by a
// relative path: the fixture runs from a copy, so every file it loads --
// the two entry points and shell/FileStore.qml -- is loaded by URL under that
// root, which is how the real host loads a plugin as well.
//
// It exits 0 when `ok` is true and 1 when it is not, and writes the same
// verdict to `OMARCHY_QML_TEST_RESULT`.
ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")

  // The plugin root: two directories up from this file. Overridable so the
  // fixture can be pointed at an installed copy.
  readonly property string pluginRoot: {
    var given = Quickshell.env("TURBO_TABLES_ROOT")
    if (given && given.length > 0)
      return given
    var here = String(Qt.resolvedUrl("../../"))
    return here.indexOf("file://") === 0 ? here.substring(7) : here
  }

  property var failures: []
  property var createdIds: []
  property var createdObjects: []
  property var panelBarIds: [
    "omarchy.audio",
    "omarchy.bluetooth",
    "omarchy.monitor",
    "omarchy.network",
    "omarchy.power",
    "omarchy.weather"
  ]

  function fail(message) {
    var next = failures.slice()
    next.push(String(message))
    failures = next
    console.warn("not ok - " + message)
  }

  function assertTrue(condition, message) {
    if (!condition)
      fail(message)
    else
      console.log("ok - " + message)
  }

  function assertEqual(actual, expected, message) {
    assertTrue(actual === expected, message + " (got " + JSON.stringify(actual)
               + ", wanted " + JSON.stringify(expected) + ")")
  }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      created: createdIds
    })
    console.log("RESULT " + payload)
    if (resultPath && resultPath.length > 0) {
      resultFile.path = resultPath
      resultFile.setText(payload)
    }
  }

  // ------------------------------------------------------------ the entries
  //
  // Upstream's shape: one entry per declared kind, each carrying the manifest,
  // the entry key the host looks the file up under, and the resolved URL.
  //
  // Upstream's `initialProperties()` is gone with the hand-built component it
  // fed: every property it set for a `bar-widget` -- `bar`, `moduleName`,
  // `settings` -- `injectProperties()` sets again straight after, and neither
  // of this plugin's two entry points declares a `required` property that would
  // have to be there at construction. Keeping an unreachable copy of it would
  // be a fixture that says it tests something it does not.
  readonly property var kindEntryPoints: ({
    "bar": "bar",
    "bar-widget": "barWidget",
    "menu": "menu",
    "overlay": "overlay",
    "panel": "panel",
    "service": "service"
  })

  function manifests() {
    return ownManifestEntries()
  }

  function ownManifestEntries() {
    var text = manifestFile.text()
    if (!text || text.length === 0) {
      fail("manifest.json could not be read at " + manifestFile.path)
      return []
    }
    var manifest = null
    try {
      manifest = JSON.parse(text)
    } catch (error) {
      fail("manifest.json is not JSON: " + error)
      return []
    }
    var kinds = manifest.kinds || []
    var entries = []
    for (var i = 0; i < kinds.length; i++) {
      var kind = kinds[i]
      var key = kindEntryPoints[kind]
      if (!key)
        continue
      var entryPoint = (manifest.entryPoints || {})[key]
      if (!entryPoint)
        continue
      entries.push({
        "id": manifest.id,
        "kind": kind,
        "entryKey": key,
        "entryPoint": entryPoint,
        "url": "file://" + root.pluginRoot + entryPoint,
        "manifest": manifest
      })
    }
    return entries
  }

  function injectProperties(item, entry) {
    if (!item) return
    if ("omarchyPath" in item) item.omarchyPath = rootPath
    if ("shell" in item) item.shell = mockShell
    if ("manifest" in item) item.manifest = entry.manifest
    if ("pluginRegistry" in item) item.pluginRegistry = mockPluginRegistry
    if ("barWidgetRegistry" in item) item.barWidgetRegistry = fakeBarWidgetRegistry
    if ("bar" in item) item.bar = fakeBar
    if ("moduleName" in item) item.moduleName = entry.id
    if ("settings" in item) item.settings = {}
    if ("service" in item) item.service = null
  }

  property var loadedByKind: ({})
  property var entries: []

  function adopt(entry, item) {
    injectProperties(item, entry)
    var objects = createdObjects.slice()
    objects.push(item)
    createdObjects = objects
    var ids = createdIds.slice()
    ids.push(entry.id + ":" + entry.kind)
    createdIds = ids
    var byKind = {}
    for (var key in loadedByKind) byKind[key] = loadedByKind[key]
    byKind[entry.kind] = item
    loadedByKind = byKind
  }

  Item {
    id: host

    Repeater {
      id: entryHost
      model: root.entries

      Loader {
        required property var modelData

        asynchronous: false
        source: modelData.url

        onStatusChanged: {
          if (status === Loader.Error)
            root.fail(modelData.id + " " + modelData.kind + " failed to load: " + source)
        }

        onLoaded: {
          if (!item) {
            root.fail(modelData.id + " " + modelData.kind + " failed to instantiate")
            return
          }
          root.adopt(modelData, item)
        }
      }
    }
  }

  FileView {
    id: manifestFile
    path: root.pluginRoot + "manifest.json"
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: resultFile
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    printErrors: false
  }

  // ------------------------------------------------------------- the mocks
  //
  // Upstream's, with one addition: every call the plugin makes into the shell
  // is recorded, because "the host was told the overlay closed itself" is a
  // thing this fixture has to be able to assert and upstream never needed to.
  QtObject {
    id: fakeBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    signal changed()
    function register(id, component, metadata) {
      var next = {}
      for (var key in widgets) next[key] = widgets[key]
      next[String(id)] = { component: component, metadata: metadata || {} }
      widgets = next
      revision++
      changed()
    }
    function unregister(id) {
      var next = {}
      for (var key in widgets) if (key !== String(id)) next[key] = widgets[key]
      widgets = next
      revision++
      changed()
    }
    function metadataFor(id) { return widgets[String(id)] ? widgets[String(id)].metadata : null }
    function availableIds() { return Object.keys(widgets) }
    function has(id) { return widgets[String(id)] !== undefined }
  }

  QtObject {
    id: mockPluginRegistry
    property var installedPlugins: ({})
    function isEnabled(id) { return true }
    function entryPointUrl(manifest, kind) { return "" }
    function rescan() {}
  }

  QtObject {
    id: mockShell
    property var bar: fakeBar
    property var barConfig: ({ position: "top" })
    property var shellConfig: ({ version: 1, idle: {}, plugins: [], bar: { layout: { left: [], center: [], right: [] } } })

    property var hideCalls: []
    property var toggleCalls: []
    property var summonCalls: []

    function firstPartyServiceFor(id) { return null }
    function serviceFor(id) { return null }
    function summon(id, payloadJson) { summonCalls = summonCalls.concat([String(id)]); return true }
    function hide(id) { hideCalls = hideCalls.concat([String(id)]); return true }
    function toggle(id, payloadJson) { toggleCalls = toggleCalls.concat([String(id)]); return true }
    function callIfLoaded(id, method, arg) { return "ok" }
    function mutateShellConfig(mutator) {}
    function updateEntryInline(moduleName, settings) { return true }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property string omarchyPath: root.rootPath
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color barForeground: "white"
    property color background: "black"
    property color urgent: "red"
    property var shell: mockShell
    function run(command) { root.fail("the plugin asked the bar to run a command: " + command) }
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) {}
    function releasePopout(owner) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
  }

  // ------------------------------------------------ the save file's doors
  //
  // Three FileStores, each pointed at a path that reproduces one of the three
  // ways the save layer has been destroyed. Loaded by URL under the plugin
  // root for the reason in the header: this fixture runs from a copy.
  readonly property var saveStoreUrl: "file://" + root.pluginRoot + "shell/FileStore.qml"

  Loader {
    id: themeProbe
    asynchronous: false
    source: "file://" + root.pluginRoot + "tests/entrypoint/ThemeProbe.qml"
  }

  Item {
    id: storeHost

    Loader {
      id: storeOnADirectory
      asynchronous: false
      source: root.saveStoreUrl
      onLoaded: item.path = root.pluginRoot
    }

    Loader {
      id: storeOnNothing
      asynchronous: false
      source: root.saveStoreUrl
      onLoaded: item.path = root.pluginRoot + "tests/entrypoint/does-not-exist/garage.json"
    }

    Loader {
      id: storeBeforeReading
      asynchronous: false
      source: root.saveStoreUrl
      onLoaded: item.path = root.pluginRoot + "tests/entrypoint/does-not-exist/never.json"
    }
  }

  function checkSaveFileDoors() {
    if (!storeOnADirectory.item || !storeOnNothing.item || !storeBeforeReading.item) {
      fail("shell/FileStore.qml did not load from " + root.saveStoreUrl)
      return
    }
    var onADirectory = storeOnADirectory.item
    var onNothing = storeOnNothing.item
    var beforeReading = storeBeforeReading.item

    // 1. A path that is there and is not a readable file. The only wrong
    //    answer is `null`, because `null` means "fresh install" to every Store
    //    that has ever read one.
    var threw = false
    var answered = undefined
    try {
      answered = onADirectory.load()
    } catch (error) {
      threw = true
    }
    assertTrue(threw, "a save path that cannot be read throws rather than answering")
    assertTrue(answered === undefined,
               "a save path that cannot be read never answers null")
    assertEqual(onADirectory.verdict, "unreadable",
                "a save path that cannot be read is recorded as unreadable")
    assertTrue(!onADirectory.everLoaded,
               "a save path that cannot be read never counts as loaded")

    // 2. The one case that may mean "fresh install", and the operating system
    //    said so in as many words.
    var fresh = "unset"
    try {
      fresh = onNothing.load()
    } catch (error) {
      fail("a genuinely absent save file threw instead of answering null: " + error)
    }
    assertTrue(fresh === null, "a genuinely absent save file answers null")
    assertEqual(onNothing.verdict, "absent",
                "a genuinely absent save file is recorded as absent")

    // 3. Nothing is written before a read has answered. This is the hot-reload
    //    door: a rebuilt object that has not yet found out what is on disk.
    assertTrue(!beforeReading.everLoaded,
               "a save file that has not been read does not count as loaded")
    beforeReading.save("{\"version\": 1}\n")
    beforeReading.flushNow()
    assertTrue(!beforeReading.writable,
               "a write before the first read is refused and stops the writing")
  }

  // -------------------------------------------------------- the theme bridge
  //
  // The overlay instantiates shell/ThemeBridge.qml, so by the time this runs
  // the game's Theme should already be following the shell's. Moving
  // `Color.accent` is the whole test: a copy does not follow it, a binding
  // does, and both directions are checked so that a bridge which happens to
  // fire once is not mistaken for one that keeps up.
  function checkThemeBridge() {
    if (!themeProbe.item) {
      fail("tests/entrypoint/ThemeProbe.qml did not load from " + themeProbe.source)
      return
    }
    var probe = themeProbe.item

    assertTrue(String(probe.accent) === String(Color.accent),
               "the game's accent is the shell's accent to begin with"
               + " (game " + probe.accent + ", shell " + Color.accent + ")")
    assertTrue(String(probe.menuBackground) === String(Color.menu.background),
               "the game's menu surface is the shell's menu surface")
    assertTrue(probe.fontBaseSize === Style.font.baseSize,
               "the game's base font size is the shell's")
    assertTrue(probe.shellCornerRadius === Style.cornerRadius,
               "the game's shell corner radius is the shell's")

    var wasAccent = Color.accent
    var wasBackground = Color.background

    Color.accent = "#ff00ff"
    Color.background = "#204080"
    assertTrue(String(probe.accent) === String(Qt.color("#ff00ff")),
               "moving the shell's accent moves the game's, with no reload and no reopen"
               + " (game reads " + probe.accent + ")")
    assertTrue(String(probe.focusRing) === String(Qt.color("#ff00ff")),
               "and the derived roles the screens actually paint with move too")
    assertTrue(String(probe.background) === String(Qt.color("#204080")),
               "moving the shell's background moves the game's")
    assertTrue(String(probe.ground) !== String(Qt.color("#204080")),
               "the game's ground is its own darkened version of it, not the raw colour"
               + " (game reads " + probe.ground + ")")

    Color.accent = wasAccent
    Color.background = wasBackground
    assertTrue(String(probe.accent) === String(wasAccent),
               "and it follows back when the theme is put back")
    assertTrue(String(probe.background) === String(wasBackground),
               "in both directions, which a one-shot copy cannot do")
  }

  // ------------------------------------------------------ the overlay's API
  function checkOverlay(overlay) {
    if (!overlay) {
      fail("no overlay entry point was loaded")
      return
    }

    assertTrue("opened" in overlay, "the overlay declares opened")
    assertTrue(typeof overlay.open === "function", "the overlay declares open()")
    assertTrue(typeof overlay.close === "function", "the overlay declares close()")
    assertTrue(typeof overlay.dismiss === "function", "the overlay declares dismiss()")
    assertTrue(overlay.opened === false, "the overlay does not summon itself on load")

    overlay.open("{}")
    assertTrue(overlay.opened === true, "open() opens the overlay")

    overlay.close()
    assertTrue(overlay.opened === false, "close() closes the overlay")
    assertEqual(mockShell.hideCalls.length, 0,
                "close() does not tell the host to hide -- the host is the caller")

    overlay.dismiss()
    assertEqual(mockShell.hideCalls.length, 1,
                "dismiss() tells the host the overlay closed itself")
    assertEqual(mockShell.hideCalls[0], "io.github.dmcchesney.turbo-tables-solo",
                "dismiss() names the plugin by its manifest id")

    if (typeof overlay.toggle === "function") {
      overlay.toggle()
      assertTrue(overlay.opened === true, "toggle() opens a closed overlay")
      overlay.toggle()
      assertTrue(overlay.opened === false, "toggle() closes an open overlay")
      assertEqual(mockShell.hideCalls.length, 2,
                  "toggle() closing the overlay tells the host as well")
    }
  }

  // The one thing a child notices on the first frame: whether typing works.
  function checkOverlayFocus(overlay) {
    if (!overlay) return
    assertTrue(overlay.gameHasFocus === true,
               "after open(), and with no pointer event anywhere, the game screen holds"
               + " the keyboard -- not the overlay's own key catcher")
  }

  function checkBarWidget(widget) {
    if (!widget) {
      fail("no bar-widget entry point was loaded")
      return
    }
    assertTrue(typeof widget.triggerPress === "function",
               "the bar widget declares triggerPress(), which is how the bar dispatches a click")
    assertTrue(widget.interactive === true && widget.pressable === true,
               "the bar widget is clickable by the bar's own test")
    assertTrue(widget.implicitWidth > 0 && widget.implicitHeight > 0,
               "the bar widget asks the bar for room")

    var before = mockShell.toggleCalls.length
    widget.triggerPress(Qt.LeftButton)
    assertEqual(mockShell.toggleCalls.length, before + 1,
                "pressing the kart button toggles the overlay through the shell")
    assertEqual(mockShell.toggleCalls[mockShell.toggleCalls.length - 1],
                "io.github.dmcchesney.turbo-tables-solo",
                "the kart button toggles this plugin by its manifest id")
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      root.entries = root.manifests()
      root.assertTrue(root.entries.length > 0, "manifest entry list is not empty")

      Qt.callLater(function () {
        root.assertTrue(root.createdIds.length === root.entries.length,
                        "all manifest entrypoints instantiate")

        root.checkSaveFileDoors()
        root.checkThemeBridge()
        root.checkOverlay(root.loadedByKind["overlay"])
        root.checkBarWidget(root.loadedByKind["bar-widget"])

        // Focus lands one turn of the event loop after open(), by design: the
        // layer surface has to be mapped first. Open it again and look then.
        var overlay = root.loadedByKind["overlay"]
        if (overlay) overlay.open("{}")

        settle.start()
      })
    }
  }

  Timer {
    id: settle
    interval: 400
    running: false
    repeat: false
    onTriggered: {
      var overlay = root.loadedByKind["overlay"]
      root.checkOverlayFocus(overlay)
      if (overlay) overlay.close()

      // Upstream destroys each created object here. These are owned by the
      // `Loader`s that made them, so emptying the model is how they are torn
      // down; calling destroy() on one raises "Invalid attempt to destroy() an
      // indestructible object" and, before this was fixed, that exception
      // escaped before the result file was written and the run reported
      // nothing at all rather than a failure.
      root.entries = []
      root.createdObjects = []

      root.writeResult()
      Qt.exit(root.failures.length === 0 ? 0 : 1)
    }
  }
}
