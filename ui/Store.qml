pragma Singleton
import QtQuick
import "../engine/engine.mjs" as Engine

// The save adapter. Layer 2 reads and writes settings, records and fact
// history through this singleton and never touches a file: `backend` is
// assigned a persistence object by whoever is hosting the screens -- the real
// one in layer 3, the in-memory one in dev/MemoryStore.qml.
//
// Three keys, exactly the design's Data table. No dates anywhere: not a
// timestamp, not a day count, not a "last played". A parent who opens the file
// sees settings, records and per-fact outcomes and nothing else.
//
// The schema, the validation, the merge, the legacy conversion and the three
// resets all live in src/engine/save.ts and reach here through the committed
// bundle at engine/engine.mjs. Nothing in this file decides what a save file
// may contain, and nothing in this file knows a file format that `npm test`
// cannot reach.
//
// ---------------------------------------------------------------------------
// THE RULE THIS FILE EXISTS FOR
// ---------------------------------------------------------------------------
//
// **Absence must be proved. It is never inferred from "I could not find out."**
//
// The save layer has now been destroyed five times by the same mistake, each
// time through a different door, and every one of them ended the same way: 242
// bytes of defaults over a 2,360-byte file holding a record and twelve facts,
// on the child's next keystroke, in silence.
//
//   round 1  a content heuristic let a stranger's counts overwrite the child's
//   round 2  an unreadable byte fell through to emptySave() and was written
//   round 3  `backend.load()` threw, the throw escaped, the defaults were armed
//   round 4  `load` was missing, was not a function, or answered `undefined`
//            -- `reload()` guarded `typeof backend.load === "function"` and,
//            when that was false, fell through to `adopt(null)`, which reads
//            absent/undefined as "fresh install"
//   piece 7  `shell/FileStore.qml` read the shell's `FileNotFound` -- which it
//            also returns for a file behind a directory it cannot walk into --
//            as proof the file was not there
//
// `shell/FileStore.qml` closed its own door by *earning* absence: it walks up
// to the first ancestor that exists, proves that ancestor is traversable by
// resolving `<ancestor>/.`, and only then is a not-found below it genuine
// absence. Anything else it throws. This file is the same rule one layer up:
//
//   **Only two answers may mean "fresh install", and both are positive:**
//
//     1. There is no backend at all. Nothing has been asked because there is
//        nobody to ask and nothing that could be written -- `flush()` cannot
//        reach a disk from here, so there is nothing to destroy.
//     2. A backend that is present, that has a callable `load`, and that
//        answered with an explicit `null`. Layer 3's `null` is itself a proof:
//        `FileStore.load()` returns it only after `_absenceIsProven()` agrees,
//        and re-proves it once more before the first byte is written.
//
//   Everything else is a quarantine. A backend with no `load`. A `load` that is
//   not a function. A `load` that throws. A `load` that answers `undefined`, or
//   a number, or a payload of the other protocol. A backend that is taken away
//   after it had already answered. None of those is a statement about what is
//   on disk, and none of them may arm a write.
//
// Quarantine means: the file is kept exactly as it is on disk, this session
// runs from the defaults in memory, and every write is refused until somebody
// decides what to do about it. `quarantineIssues` says why, in the schema's own
// path/problem form; `quarantineReason` is one line of it.
//
// ---------------------------------------------------------------------------
// WHAT A SCREEN DOES WITH A QUARANTINE
// ---------------------------------------------------------------------------
//
// Nothing used to read `quarantined`, so a quarantine was invisible: the child
// saw a garage that looked factory-reset and whose every change silently failed
// to stick, forever, with the explanation on stderr. Now:
//
//   ui/Game.qml     draws a notice strip across every screen of the flow, with
//                   no keystroke needed: a line the child can read, and
//                   `quarantineReason` underneath for the parent they fetch.
//   ui/Settings.qml shows the same reason in the RESET panel, and offers the
//                   one action there is -- `discardQuarantinedFile()` -- behind
//                   the same Confirm dialog the three resets use, naming what
//                   is lost. Nothing else may call it.
//
// The garage's controls are never disabled: they still apply for the session,
// and `setSetting` answers false so a screen can say "not saved".
QtObject {
  id: store

  // ------------------------------------------------------------- the backend
  //
  // Two protocols, declared rather than guessed at, because guessing is how an
  // earlier draft silently degraded the harness to an empty save.
  //
  //   format === "text"   load() -> the file's TEXT, or null when the file is
  //                       *proved* not to be there;  save(text) persists it.
  //                       This is the real protocol: `Engine.serialiseSave` is
  //                       what fixes the key order and the two-space indent
  //                       that the design's "Human-readable, so a parent can
  //                       see exactly what is kept" is a promise about, and an
  //                       unchanged file has to write identical bytes. Layer 3
  //                       declares `format: "text"`.
  //
  //   anything else       load() -> a plain object, or null;  save(object).
  //                       The in-memory protocol dev/MemoryStore.qml and
  //                       tests/qml use. The object is the shape the first
  //                       version of this file wrote -- `settings` in the
  //                       garage's own 0-based vocabulary, `records` and
  //                       `facts` in the schema's -- so a harness can seed a
  //                       screen with `--settings kartBody=3` and a test can
  //                       read `lastWritten.settings.kartBody` back. It still
  //                       goes through `Engine.validateSave` in both
  //                       directions; only the wire format differs.
  //
  // A backend that returns the payload of the other protocol is a bug, not a
  // shape to be tolerated: it is refused out loud and quarantined.
  property var backend: null

  // False until a load has been attempted. Every mutator refuses while it is
  // false, so a screen cannot write over a save that has not arrived yet.
  property bool loaded: false

  // True when the backend handed back something this build will not touch, or
  // could not be asked at all. The file is still on disk, untouched; this
  // session runs from defaults in memory and every write is refused.
  property bool quarantined: false
  property var quarantineIssues: []
  property string quarantineReason: ""

  // True once a backend has answered a load with something this file accepted
  // -- a file, or a proved absence. After that, a backend that goes away is a
  // backend that was taken away, which is not a statement that the file is
  // gone. It is the last of the five doors: without it, `Store.backend = null`
  // after a real load would silently re-arm the defaults.
  property bool _backendHasAnswered: false

  signal changed()

  // ------------------------------------------------------------- defaults
  //
  // The garage's own vocabulary, which is 0-based and numeric because the
  // steppers are. It is NOT the file's vocabulary; `toSchema` and `fromSchema`
  // are the only two places the two meet, so no screen has to know the file
  // exists.
  //
  // `kartNumber: 7` is deliberately not `Engine.defaultSettings().number`,
  // which is 1: the garage's fresh-install kart number is 7 and three
  // committed QML tests say so. The two only differ on an install that has
  // never written anything; from the first write on, the file is the authority.
  // "The defaults" means this object, everywhere -- on a fresh install and on a
  // RESET SETTINGS alike, so the same design row cannot start at one value and
  // reset to another.
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

  // Design, Data, `settings`: "sound, reduced motion, scanlines, kart, paint,
  // number, rival level, streak threshold if exposed." Race mode and math set
  // are not on that list and `save.ts` rejects a key it does not know, so they
  // are this session's choices and not saved state. docs/open-questions.md
  // records that as the maintainer's decision. They keep working in the garage;
  // what they do not do is claim to have been written.
  readonly property var sessionOnlyKeys: ["raceMode", "mathSet"]

  readonly property var rivalLevels: ["rookie", "pro", "champion"]

  property var settings: ({})
  property var records: ({})
  property var facts: []

  // The file's streak threshold, carried rather than assumed.
  //
  // Design, Data: "streak threshold if exposed" is a persisted setting, and
  // Decisions: the threshold is 12 while "the bellringer's 15 stays in the test
  // vectors as a parity case" -- so a valid file may carry a value this build
  // does not use, and it is still the child's file. An earlier draft wrote
  // `Engine.STREAK_THRESHOLD` unconditionally, so a file saying 15 became 12 on
  // the first garage keystroke and "an unchanged file writes identical bytes"
  // was false for it. It round-trips on both protocols.
  //
  // It is not in `defaultSettings` because the garage does not expose it: no
  // stepper reads it and no screen shows it. It is loaded, kept and written
  // back, and that is all.
  property int _streakThreshold: Engine.STREAK_THRESHOLD

  // The exact array handed to the race that is running. Never nulled on the way
  // out of `commit`: after a commit it becomes the file as it now stands, so a
  // second commit of the same race is a baseline that does not account for it
  // and `Engine.commitRace` refuses it instead of doubling the child's counts.
  // Never exposed to a screen.
  property var _seededWith: null

  // ------------------------------------------------------------- reading
  function setting(key) {
    var value = settings[key]
    return value === undefined ? defaultSettings[key] : value
  }

  function isSessionOnly(key) {
    return sessionOnlyKeys.indexOf(key) >= 0
  }

  function clamp(value, low, high, fallback) {
    var n = Math.round(Number(value))
    if (!isFinite(n)) return fallback
    return n < low ? low : (n > high ? high : n)
  }

  function copyOf(source) {
    var out = {}
    for (var k in source) out[k] = source[k]
    return out
  }

  // The garage's settings as the design's Data row spells them.
  function toSchema() {
    var level = rivalLevels[setting("rivalLevel")]
    return {
      "sound": setting("sound") === true,
      "reducedMotion": setting("reducedMotion") === true,
      "scanlines": setting("scanlines") === true,
      "kart": clamp(setting("kartBody") + 1, 1, Engine.KART_BODIES, 1),
      "paint": clamp(setting("kartPaint") + 1, 1, Engine.PAINT_SWATCHES, 1),
      "number": clamp(setting("kartNumber"), Engine.KART_NUMBER_MIN, Engine.KART_NUMBER_MAX, 1),
      "rivalLevel": level === undefined ? "pro" : level,
      "streakThreshold": clamp(_streakThreshold, Engine.STREAK_THRESHOLD_MIN,
                               Engine.STREAK_THRESHOLD_MAX, Engine.STREAK_THRESHOLD)
    }
  }

  // The other direction: start from the garage's defaults and overwrite only
  // the keys the file actually carries, so the session-only ones keep their
  // defaults rather than becoming undefined.
  function fromSchema(s) {
    var merged = copyOf(defaultSettings)
    merged["sound"] = s.sound
    merged["reducedMotion"] = s.reducedMotion
    merged["scanlines"] = s.scanlines
    merged["kartBody"] = s.kart - 1
    merged["kartPaint"] = s.paint - 1
    merged["kartNumber"] = s.number
    var at = rivalLevels.indexOf(s.rivalLevel)
    merged["rivalLevel"] = at < 0 ? 1 : at
    return merged
  }

  // The save file, in the schema's own shape. This is the object every engine
  // call in this file is handed, so nothing here ever assembles a file by hand.
  function file() {
    var f = Engine.emptySave()
    f.settings = toSchema()
    f.records = records
    f.facts = facts
    return f
  }

  // The object-protocol payload: the same file with the garage's vocabulary for
  // settings, plus the streak threshold so this protocol round-trips it too.
  function snapshot() {
    var out = { "version": Engine.SAVE_VERSION, "settings": {}, "records": records, "facts": facts }
    for (var k in defaultSettings) out.settings[k] = setting(k)
    out.settings["streakThreshold"] = _streakThreshold
    return out
  }

  // ------------------------------------------------------------- writing
  //
  // Returns true when the value was applied AND will survive a reload. A
  // session-only key applies and returns false: a setting that cannot come back
  // must not share an answer with one that can. A quarantined session is the
  // same shape of answer -- applied, not saved.
  function setSetting(key, value) {
    if (!loaded) return false
    if (isSessionOnly(key)) return sessionSetting(key, value)
    if (quarantined) {
      applyLocally(key, value)
      return false
    }
    if (settings[key] === value) return true
    applyLocally(key, value)
    flush()
    return true
  }

  // A choice that lives for this session only, applied and never written.
  // Always returns false, because the honest answer to "did that persist" is
  // no. `raceMode` and `mathSet` come through here.
  function sessionSetting(key, value) {
    if (!loaded) return false
    if (settings[key] !== value) applyLocally(key, value)
    return false
  }

  function applyLocally(key, value) {
    var next = copyOf(settings)
    next[key] = value
    settings = next
    changed()
  }

  // Every write goes through here, and every write is inside a `try`. A backend
  // that throws on `save` -- a full disk, a read-only directory, a file the
  // process no longer owns -- must not take the session down and must not be
  // retried on every keystroke afterwards. It stops the writing and says so.
  function flush() {
    if (!loaded || quarantined) return
    if (!backend || typeof backend.save !== "function") return
    try {
      if (backendFormat() === "text") backend.save(Engine.serialiseSave(file()))
      else backend.save(snapshot())
    } catch (e) {
      stopWriting([{ "path": "", "problem": "the save file could not be written: " + e }])
    }
  }

  // ---------------------------------------------------- the design's resets
  //
  // Design, Data, the "Reset by" column: settings by Settings, records by
  // "Reset garage records", facts by "Reset fact history". Each moves exactly
  // its own key.
  //
  // All three go through the engine, and all three take *every* key back off
  // the file the engine returned -- not just the one they meant to change. That
  // is what makes "the other two are untouched" a property of `save.ts`'s own
  // tested arithmetic rather than of this file remembering not to assign them:
  // if `Engine.resetRecords` ever touched `facts`, this would carry the damage
  // out where a test can see it instead of hiding it behind a local assignment.
  //
  // `resetSettings` is the one place the garage's vocabulary wins over the
  // engine's. `Engine.resetSettings` gives the *schema's* defaults, whose kart
  // number is 1, while a fresh install of the garage shows 7 -- the same design
  // row starting at one value and resetting to another. The engine's file is
  // still what records and facts come from; the settings the garage adopts are
  // the same `defaultSettings` a fresh install adopts, so there is exactly one
  // meaning of "the defaults" on this screen.
  function resetSettings() {
    if (!loaded || quarantined) return false
    var next = Engine.resetSettings(file())
    records = next.records
    facts = next.facts
    _streakThreshold = next.settings.streakThreshold
    settings = copyOf(defaultSettings)
    changed()
    flush()
    return true
  }

  function resetRecords() {
    if (!loaded || quarantined) return false
    var next = Engine.resetRecords(file())
    records = next.records
    facts = next.facts
    settings = fromSchema(next.settings)
    _streakThreshold = next.settings.streakThreshold
    changed()
    flush()
    return true
  }

  function resetFacts() {
    if (!loaded || quarantined) return false
    var next = Engine.resetFacts(file())
    records = next.records
    facts = next.facts
    settings = fromSchema(next.settings)
    _streakThreshold = next.settings.streakThreshold
    // `_seededWith` is deliberately left alone. A race that is running was
    // seeded from a history that no longer exists, so its baseline is no longer
    // this file's and `commitRace` refuses it -- and it refuses it whether the
    // stale array is kept or nulled, because a stale array is the wrong length
    // for the emptied file and a null one does not add up to the race's
    // `attemptCount`. Nulling it would be a line no test can kill, and a line
    // no test can kill is a claim nobody is checking. The cost is real and is
    // named in tst_store.qml: a fact-history reset under a running race costs
    // that race its answers.
    changed()
    flush()
    return true
  }

  // ------------------------------------------------------- the race seam
  //
  // Hand this straight to the race. The baseline is remembered here, so no
  // screen can hand `commit` the wrong one.
  function factHistoryForRace() {
    if (!loaded) return []
    _seededWith = Engine.factHistoryForRace(file())
    return _seededWith
  }

  // Fold a finished race in: the fact history always, the record only when the
  // design allows one. `timeline` is the ghost recorded during the race.
  //
  // Calling this twice for one race is safe and loud rather than safe and
  // silent: the second call's baseline is the file as the first call left it,
  // which does not account for the race's answers, so `commitRace` refuses the
  // merge and says so. `result.factsUpdated` is false and the counts do not
  // move.
  //
  // A quarantined session still folds the race into memory -- the session is
  // still the child's and the mastery lamps are still theirs to watch move --
  // and only the write is refused. An earlier draft returned null on the first
  // line, so after one failed write every later race in the session was
  // discarded before it reached even the in-memory history, with nothing on
  // screen saying why.
  function commit(state, timeline) {
    if (!loaded) return null
    var result = Engine.commitRace(
      file(),
      state,
      Engine.factHistoryOf(state),
      Engine.recordFromRace(state, timeline === undefined || timeline === null
                                   ? Engine.emptyTimeline() : timeline),
      _seededWith)
    if (result.issues.length > 0)
      console.warn("Store: the race did not commit cleanly: " + JSON.stringify(result.issues))
    records = result.file.records
    facts = result.file.facts
    // The baseline for anything that follows is the file as it now stands.
    _seededWith = Engine.factHistoryForRace(result.file)
    changed()
    flush()
    return result
  }

  // ------------------------------------------------------------- loading
  function backendFormat() {
    if (!backend) return "object"
    var declared = undefined
    try { declared = backend.format } catch (e) { declared = undefined }
    return declared === "text" ? "text" : "object"
  }

  // Ask the backend what is on disk, and treat every answer that is not a proof
  // as a quarantine. See the header: this function is the whole rule.
  function reload() {
    // 1. There is no backend. Nothing has been asked because there is nobody to
    //    ask -- and nothing that could be written either, since `flush()` needs
    //    a `save` to call. A backend that is taken away *after* it answered is
    //    a different thing: somebody removed the only thing that knows what is
    //    on disk, which is not a claim that there is nothing on it.
    if (backend === null || backend === undefined) {
      if (_backendHasAnswered) {
        quarantine(null, [{
          "path": "",
          "problem": "the backend that had answered was taken away, so nothing here knows what is"
                     + " on disk any more"
        }])
        return
      }
      adopt(null)
      return
    }

    // 2. A backend that is present and cannot be asked. `load` missing, `load`
    //    not callable, or a property access that throws. Each of these was a
    //    door a child's file was destroyed through, because `reload()` guarded
    //    the same condition and then fell through to `adopt(null)` -- which
    //    reads "no payload" as "fresh install". "I cannot ask" is not "there is
    //    nothing there".
    var loader = undefined
    try {
      loader = backend.load
    } catch (e) {
      quarantine(null, [{
        "path": "",
        "problem": "the backend could not be asked for the save file: " + e
      }])
      return
    }
    if (typeof loader !== "function") {
      quarantine(null, [{
        "path": "",
        "problem": "the backend has no load() to ask -- it is "
                   + (loader === undefined ? "missing" : "a " + typeof loader)
                   + " -- so nothing here knows what is on disk"
      }])
      return
    }

    // 3. A read that throws. Permissions, an I/O error, a decode failure, or
    //    layer 3 refusing to call a not-found file an absence it could not
    //    prove. A throw is a quarantine, with what was thrown as the reason.
    var payload = undefined
    try {
      payload = backend.load()
    } catch (e) {
      quarantine(null, [{
        "path": "",
        "problem": "the save file could not be read: " + e
      }])
      return
    }

    // 4. `undefined` is not an answer. `null` is: it is the one positive claim
    //    a backend may make about an empty slot, and layer 3 only makes it
    //    after `_absenceIsProven()` has agreed and re-agrees before the first
    //    write. A function that fell off its end, or a backend that forgot to
    //    return, must never mean the same thing.
    if (payload === undefined) {
      quarantine(null, [{
        "path": "",
        "problem": "the backend answered with undefined, which says nothing about what is on"
                   + " disk -- only an explicit null is a claim that there is no save file"
      }])
      return
    }

    adopt(payload)
  }

  // Take what the backend handed over, or quarantine it. Four outcomes and no
  // fifth: nothing on disk yet, a file this build understands, a legacy file it
  // can convert, or a quarantine.
  //
  // `adopt` is reachable from `Component.onCompleted` as well as from
  // `reload()`, so it keeps the `undefined` guard of its own rather than
  // trusting its caller to have made it. Two guards for the door five bugs came
  // through is not ceremony.
  function adopt(payload) {
    if (payload === undefined && _backendHasAnswered) {
      quarantine(null, [{
        "path": "",
        "problem": "nothing was handed over, and this session has already read a save file"
      }])
      return
    }

    quarantined = false
    quarantineIssues = []
    quarantineReason = ""
    _seededWith = null

    // 1. Nothing on disk -- proved, not assumed. The garage's own defaults, not
    //    the schema's.
    if (payload === null || payload === undefined) {
      settings = copyOf(defaultSettings)
      _streakThreshold = Engine.STREAK_THRESHOLD
      records = {}
      facts = []
      loaded = true
      if (backend) _backendHasAnswered = true
      changed()
      return
    }

    var text = backendFormat() === "text"
    if (text !== (typeof payload === "string")) {
      quarantine(payload, [{
        "path": "",
        "problem": "the backend declared " + (text ? "text" : "an object")
                   + " and handed back " + typeof payload
      }])
      return
    }

    // 2. A file this build reads, or 3. one it converts.
    var read = text ? fileFromText(payload) : fileFromObject(payload)
    if (!read.ok) {
      quarantine(payload, read.issues)
      return
    }

    settings = fromSchema(read.file.settings)
    _streakThreshold = read.file.settings.streakThreshold
    records = read.file.records
    facts = read.file.facts
    loaded = true
    _backendHasAnswered = true
    changed()
  }

  function fileFromText(t) {
    var parsed = Engine.parseSave(t)
    if (parsed.ok) return { "ok": true, "file": parsed.file, "issues": [] }
    var raw = null
    try { raw = JSON.parse(t) } catch (e) { return { "ok": false, "file": null, "issues": parsed.issues } }
    return fromLegacy(raw, parsed.issues)
  }

  function fileFromObject(o) {
    // The object protocol's settings are the garage's vocabulary; its records
    // and facts are the schema's. Convert the first, then validate the whole
    // thing the same way a text file is validated.
    //
    // A partial settings object is filled in from the defaults rather than
    // refused, because that is what this protocol is for: `dev/Harness.qml`
    // seeds a screen with `--settings kartBody=3,kartPaint=5` and expects the
    // rest of the garage to look like a fresh install. A *text* file with a key
    // missing is a different thing and `parseSave` refuses it.
    if (o === null || typeof o !== "object" || (o.length !== undefined && o.constructor === Array))
      return { "ok": false, "file": null,
               "issues": [{ "path": "", "problem": "the payload is not a save object" }] }
    var given = (o.settings && typeof o.settings === "object") ? o.settings : {}
    var filled = copyOf(defaultSettings)
    var threshold = _streakThreshold
    for (var g in given) {
      // The threshold is a schema key, not one of the legacy garage's, so it
      // travels beside them rather than through the legacy converter -- which
      // refuses a key it does not know, and is right to.
      if (g === "streakThreshold") threshold = given[g]
      else filled[g] = given[g]
    }
    var legacy = Engine.migrateLegacyGarageSettings({
      "version": Engine.SAVE_VERSION,
      "settings": filled,
      "records": {},
      "facts": []
    })
    if (legacy.settings === null)
      return { "ok": false, "file": null, "issues": [{ "path": "settings", "problem": legacy.problem }] }
    legacy.settings.streakThreshold = clamp(threshold, Engine.STREAK_THRESHOLD_MIN,
                                            Engine.STREAK_THRESHOLD_MAX, Engine.STREAK_THRESHOLD)
    var candidate = {
      "version": Engine.SAVE_VERSION,
      "settings": legacy.settings,
      "records": (o.records && typeof o.records === "object") ? o.records : {},
      "facts": (o.facts && o.facts.length !== undefined) ? o.facts : []
    }
    var checked = Engine.validateSave(candidate)
    return { "ok": checked.ok, "file": checked.file, "issues": checked.issues }
  }

  // The one file shape that is not a version of this schema and still has to be
  // read: what the first version of this file wrote. The conversion is
  // `save.ts`'s, exported and tested by `npm test`; the decision to call it is
  // this file's.
  function fromLegacy(raw, fallbackIssues) {
    var legacy = Engine.migrateLegacyGarageSettings(raw)
    if (legacy.settings === null) return { "ok": false, "file": null, "issues": fallbackIssues }
    var f = Engine.emptySave()
    f.settings = legacy.settings
    return { "ok": true, "file": f, "issues": [] }
  }

  // Keep the file, run the session in memory, refuse every write, and say so.
  // A backend may offer `quarantine(payload)` -- layer 3's may, to copy the
  // file aside -- but nothing here depends on it: not writing is already enough
  // to keep the child's progress on disk.
  function quarantine(payload, issues) {
    quarantined = true
    quarantineIssues = issues
    quarantineReason = reasonOf(issues)
    settings = copyOf(defaultSettings)
    _streakThreshold = Engine.STREAK_THRESHOLD
    records = {}
    facts = []
    _seededWith = null
    // `loaded` is true so that `Component.onCompleted`'s `adopt(null)` cannot
    // arrive afterwards and clobber the quarantine with a fresh install.
    loaded = true
    console.warn("Store: the save file was not readable and has been left alone: "
                 + quarantineReason + " (" + issues.length + " issue(s))")
    if (backend && typeof backend.quarantine === "function") {
      try { backend.quarantine(payload) } catch (e) { /* advisory only */ }
    }
    changed()
  }

  // The write-side half of the same rule. A file that loaded fine and cannot be
  // *written* leaves the session holding state that is still the child's, so
  // this keeps it -- the race that just finished is still on screen and its
  // numbers are still right -- and only stops writing. The same `quarantined`
  // flag, because it means the same thing to every caller: this session will
  // not touch the file, and `setSetting` will keep answering false.
  //
  // Layer 3 reports a failed write by signal rather than by exception, so the
  // `try` in `flush()` never sees it: `TurboTables.qml` connects the file
  // object's `writeFailed` straight to here instead.
  function stopWriting(issues) {
    if (quarantined) return
    quarantined = true
    quarantineIssues = issues
    quarantineReason = reasonOf(issues)
    console.warn("Store: the save file could not be written and will not be written again this"
                 + " session: " + quarantineReason)
    changed()
  }

  // The shape `shell/FileStore.qml`'s `writeFailed(string)` arrives in.
  function writeFailed(reason) {
    stopWriting([{ "path": "", "problem": String(reason) }])
  }

  function reasonOf(issues) {
    return issues.length > 0
        ? ((issues[0].path.length > 0 ? issues[0].path + ": " : "") + issues[0].problem)
        : "the save file could not be read"
  }

  // The explicit way out: somebody has decided the unreadable file is not worth
  // keeping. Only ui/Settings.qml calls this, behind the same Confirm dialog
  // the three resets use, and it names what is lost before it asks.
  function discardQuarantinedFile() {
    if (!quarantined) return false
    quarantined = false
    quarantineIssues = []
    quarantineReason = ""
    flush()
    changed()
    return true
  }

  onBackendChanged: reload()

  Component.onCompleted: if (!loaded) adopt(null)
}
