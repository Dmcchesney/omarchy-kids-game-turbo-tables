pragma Singleton
import QtQuick

// The save adapter. Layer 2 reads and writes settings, records and fact
// history through this singleton and never touches a file: `backend` is
// assigned an object with load() and save() by whoever is hosting the
// screens -- the real one in layer 3, the in-memory one in the harness.
//
// Three keys, exactly the design's Data table. No dates anywhere: not a
// timestamp, not a day count, not a "last played". A parent who opens the
// file sees settings, records and per-fact outcomes and nothing else.
QtObject {
  id: store

  // The host's persistence object. Duck-typed on purpose so neither
  // implementation has to be visible from here:
  //   load()        -> a plain object shaped like snapshot(), or null
  //   save(object)  -> persists it, however it likes
  property var backend: null

  // False until a load has been attempted. A screen that writes before this
  // is true would be writing over a save that has not arrived yet, so every
  // mutator refuses while it is false.
  property bool loaded: false

  signal changed()

  // ------------------------------------------------------------- defaults
  readonly property var defaultSettings: ({
    "kartBody": 0,
    "kartPaint": 0,
    "kartNumber": 7,
    "rivalLevel": 1,
    "raceMode": 3,
    "mathSet": 2,
    "sound": true,
    "reducedMotion": false,
    "scanlines": false
  })

  property var settings: ({})
  property var records: ({})
  property var facts: ({})

  // ------------------------------------------------------------- reading
  function setting(key) {
    var value = settings[key]
    return value === undefined ? defaultSettings[key] : value
  }

  function snapshot() {
    return {
      "version": 1,
      "settings": settings,
      "records": records,
      "facts": facts
    }
  }

  // ------------------------------------------------------------- writing
  function setSetting(key, value) {
    if (!loaded)
      return false
    if (settings[key] === value)
      return true
    var next = {}
    for (var k in settings)
      next[k] = settings[k]
    next[key] = value
    settings = next
    flush()
    changed()
    return true
  }

  function flush() {
    if (!loaded || !backend || typeof backend.save !== "function")
      return
    backend.save(snapshot())
  }

  // ------------------------------------------------------------- loading
  function adopt(data) {
    var incoming = (data && typeof data === "object") ? data : {}
    var merged = {}
    for (var d in defaultSettings)
      merged[d] = defaultSettings[d]
    var given = (incoming.settings && typeof incoming.settings === "object") ? incoming.settings : {}
    for (var g in given)
      if (Object.prototype.hasOwnProperty.call(merged, g))
        merged[g] = given[g]
    settings = merged
    records = (incoming.records && typeof incoming.records === "object") ? incoming.records : {}
    facts = (incoming.facts && typeof incoming.facts === "object") ? incoming.facts : {}
    loaded = true
    changed()
  }

  function reload() {
    var data = null
    if (backend && typeof backend.load === "function")
      data = backend.load()
    adopt(data)
  }

  onBackendChanged: reload()

  Component.onCompleted: if (!loaded) adopt(null)
}
