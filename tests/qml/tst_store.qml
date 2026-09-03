import QtQuick
import QtTest
import "../../ui"
import "../../engine/engine.mjs" as Engine

// ui/Store.qml -- the only code in layer 2 that decides what reaches a disk.
//
// There was no spec for this file at all until now, which is how four rounds of
// review found the same bug in it four times. Every one of them was one shape:
//
//     **"there is no file" inferred from "I could not find out."**
//
//   round 1  a content heuristic let a stranger's counts overwrite the child's
//   round 2  an unreadable byte fell through to emptySave() and was written
//   round 3  `backend.load()` threw, the throw escaped, the defaults were armed
//   round 4  `load` was missing, was not a function, or answered `undefined`
//   piece 7  layer 3 read a not-found -- which it also gets for a file behind a
//            directory it cannot walk into -- as proof the file was not there
//
// Rounds 3 and 4 were each measured the same way, and it is the shape of every
// case in section 1 below: put a real save on the disk, hand the Store a
// backend that cannot answer, press one garage key, and look at the disk.
//
//     DESTROYED  load() missing entirely   2360 bytes -> 242  quarantined=false
//     DESTROYED  load returns undefined    2360 bytes -> 242  quarantined=false
//     DESTROYED  load is not a function    2360 bytes -> 242  quarantined=false
//     SAFE       load throws               quarantined
//
// So the rule these cases assert is not "handle this error too". It is:
//
//     **Absence must be proved. Two answers may mean "fresh install", and both
//     are positive: there is no backend at all, or a backend that is present,
//     that has a callable `load`, and that answered with an explicit `null`.
//     Everything else is a quarantine.**
//
// That is the same rule `shell/FileStore.qml` keeps one layer down, where an
// `absent` verdict is earned by walking to the first ancestor that exists and
// resolving `<ancestor>/.` to prove this process can enter it -- and is re-earned
// from scratch before the first write. Its `null` is the proof this file trusts.
//
// Run it:
//   qmltestrunner -input tests/qml -import ui -import dev/imports
Item {
  id: root
  width: 400
  height: 300

  // The disk. A plain string, so a test can compare the bytes rather than the
  // Store's own opinion of what it wrote.
  QtObject {
    id: disk
    property string blob: ""
    property int writes: 0
  }

  TestCase {
    id: suite
    name: "Store"
    when: windowShown

    // ------------------------------------------------------------ fixtures
    //
    // A real save file, built by the engine rather than typed out: one record
    // with a ghost timeline, a populated fact history, non-default settings,
    // and `streakThreshold: 15` -- the parity value the design's Decisions row
    // keeps in the vectors, which a valid file may carry and this build does not
    // use. A file the store cannot round-trip byte for byte is a file the
    // design's "an unchanged file writes identical bytes" is false for.
    function victimFile() {
      var file = Engine.emptySave()
      file.settings = {
        "sound": false, "reducedMotion": true, "scanlines": true,
        "kart": 5, "paint": 6, "number": 42, "rivalLevel": "champion",
        "streakThreshold": 15
      }
      var race = suite.playRace(11, "timeTrial", "2-5")
      var record = Engine.recordFromRace(race.state, race.timeline)
      if (record !== null)
        file.records[Engine.recordKeyOf(race.state)] = record
      file.facts = Engine.factHistoryOf(race.state)
      return file
    }

    function victimText() {
      return Engine.serialiseSave(suite.victimFile())
    }

    // A whole race, played out by the engine, so the fact history and the ghost
    // timeline are ones the engine could really have produced. `seedFacts` is
    // the array the race is created with, which is also the baseline a commit
    // has to declare -- the pair `ui/Game.qml` keeps together.
    function playRace(seed, mode, preset, seedFacts) {
      var state = Engine.createRace({
        "seed": seed, "mode": mode, "preset": preset,
        "racers": [{ "id": "you", "kind": "human" }],
        "humanId": "you",
        "factHistory": seedFacts === undefined ? [] : seedFacts
      })
      state = Engine.step(state, { "kind": "start" }, 0).state
      var timeline = Engine.emptyTimeline()
      var at = 0
      for (var n = 0; n < 500 && state.status !== "finished"; n++) {
        at += 2500
        var me = Engine.humanRacer(state)
        if (me === null || me.finished)
          break
        var right = Engine.factAnswer(me.currentFact)
        var out = Engine.step(state, { "kind": "answer",
                                       "value": n === 3 ? right + 1 : right }, at)
        state = out.state
        timeline = Engine.recordStep(timeline, state, out.events, "you")
      }
      return { "state": state, "timeline": timeline }
    }

    // A text-protocol backend over `disk`. `broken` names the way it fails; the
    // default is a backend that works.
    function backendOf(broken) {
      var b = { "format": "text" }
      b.save = function (t) { disk.blob = t; disk.writes += 1 }
      if (broken === "no-load")
        return b
      if (broken === "load-not-a-function") {
        b.load = 42
        return b
      }
      if (broken === "load-undefined") {
        b.load = function () { return undefined }
        return b
      }
      if (broken === "load-throws") {
        b.load = function () { throw new Error("EACCES") }
        return b
      }
      if (broken === "save-throws") {
        b.load = function () { return disk.blob }
        b.save = function (t) { throw new Error("ENOSPC") }
        return b
      }
      if (broken === "load-null") {
        b.load = function () { return null }
        return b
      }
      if (broken === "load-object") {
        b.load = function () { return { "version": 1 } }
        return b
      }
      b.load = function () { return disk.blob }
      return b
    }

    // A Store as a freshly built singleton would be, then handed `backend`.
    //
    // The two flags reset here are the ones a new QML engine would start with.
    // Reaching into them is deliberate and is the only way one process can ask
    // the fresh-install question sixteen times; the alternative -- one process
    // per case -- cannot be a qmltestrunner suite at all, which is the reason
    // this file did not exist for four rounds. A new backend object is built
    // every time, because assigning the same one twice fires no change and
    // would silently skip the load under test.
    function freshStore(broken) {
      Store.loaded = false
      Store.quarantined = false
      Store.quarantineIssues = []
      Store.quarantineReason = ""
      Store._backendHasAnswered = false
      Store.backend = suite.backendOf(broken)
    }

    function init() {
      disk.blob = suite.victimText()
      disk.writes = 0
    }

    function cleanupTestCase() {
      // Leave the singleton with no backend so nothing else in the run can
      // write through it.
      Store.backend = null
    }

    // What is on the disk right now, as the engine reads it.
    function onDisk() {
      var parsed = Engine.parseSave(disk.blob)
      return parsed.ok ? parsed.file : null
    }

    // The child's earned progress, which is the thing every one of the five
    // rounds destroyed.
    function progressOnDisk() {
      var file = suite.onDisk()
      if (file === null)
        return { "records": -1, "facts": -1, "attempts": -1 }
      var attempts = 0
      for (var i = 0; i < file.facts.length; i++)
        attempts += file.facts[i].attempts
      return { "records": Object.keys(file.records).length,
               "facts": file.facts.length, "attempts": attempts }
    }

    // One garage keystroke, which is what armed the destruction every time.
    function oneKeystroke() {
      return Store.setSetting("kartBody", 3)
    }

    // =====================================================================
    // 1. ABSENCE MUST BE PROVED
    //
    // The four rows above, plus the doors of the same shape beside them. Each
    // case is: a real save on disk, a backend that cannot answer, one
    // keystroke, and then the disk.
    // =====================================================================

    function assertTheFileSurvived(what) {
      var before = suite.victimText()
      verify(Store.quarantined, what + ": the store did not quarantine, so it believes the"
             + " defaults in memory are what is on disk")
      compare(suite.oneKeystroke(), false, what + ": setSetting claimed the change was saved")
      Store.setSetting("kartPaint", 4)
      compare(disk.writes, 0, what + ": something was written over the child's file")
      compare(disk.blob, before, what + ": the file on disk is not byte-identical")
      var progress = suite.progressOnDisk()
      compare(progress.records, 1, what + ": the record is gone")
      verify(progress.facts > 0, what + ": the fact history is gone")
    }

    // ROW 1. `load` missing entirely. `reload()` guarded
    // `typeof backend.load === "function"` and, when that was false, fell
    // through to `adopt(null)` -- which reads no payload as "nothing on disk
    // yet". 2,360 bytes became 242.
    function test_01_a_backend_with_no_load_is_a_quarantine_not_a_fresh_install() {
      suite.freshStore("no-load")
      suite.assertTheFileSurvived("a backend with no load()")
      verify(Store.quarantineReason.indexOf("no load()") >= 0,
             "the reason does not say what was wrong: " + Store.quarantineReason)
    }

    // ROW 2. `load` answers `undefined`. A function that fell off its end must
    // never mean what an explicit `null` means.
    function test_02_a_load_that_answers_undefined_is_not_an_absence() {
      suite.freshStore("load-undefined")
      suite.assertTheFileSurvived("load() answering undefined")
    }

    // ROW 3. `load` is present and not callable.
    function test_03_a_load_that_is_not_a_function_is_not_an_absence() {
      suite.freshStore("load-not-a-function")
      suite.assertTheFileSurvived("load being a number")
    }

    // ROW 4. `load` throws -- permissions, an I/O error, or layer 3 refusing to
    // call a not-found file an absence it could not prove. This row was closed
    // in round 4 and is here so it stays closed.
    function test_04_a_load_that_throws_is_quarantined() {
      suite.freshStore("load-throws")
      suite.assertTheFileSurvived("load() throwing")
      verify(Store.quarantineReason.indexOf("EACCES") >= 0,
             "the thrown message is not in the reason: " + Store.quarantineReason)
    }

    // The same door with the failure moved onto the property access itself.
    function test_05_a_backend_whose_load_getter_throws_is_not_an_absence() {
      var evil = { "format": "text" }
      evil.save = function (t) { disk.blob = t; disk.writes += 1 }
      Object.defineProperty(evil, "load", { get: function () { throw new Error("boom") } })
      Store.loaded = false
      Store.quarantined = false
      Store.quarantineReason = ""
      Store._backendHasAnswered = false
      Store.backend = evil
      suite.assertTheFileSurvived("a load getter that throws")
    }

    // A backend that is not an object at all. Nothing can be asked of it, so it
    // says nothing about the disk.
    function test_06_a_backend_that_is_not_an_object_is_not_an_absence() {
      Store.loaded = false
      Store.quarantined = false
      Store.quarantineReason = ""
      Store._backendHasAnswered = false
      Store.backend = "a string where a backend should be"
      verify(Store.quarantined, "a non-object backend was read as a fresh install")
      compare(suite.oneKeystroke(), false)
      compare(disk.writes, 0)
    }

    // The fifth door, and the one no round reached: a backend that answered
    // once and is then taken away -- a hot reload destroying the file object
    // under a live Store. Somebody removing the only thing that knows what is
    // on disk is not a claim that there is nothing on it.
    function test_07_a_backend_taken_away_after_it_answered_is_not_an_absence() {
      suite.freshStore()
      verify(Store.loaded && !Store.quarantined, "the good backend did not load")
      compare(Object.keys(Store.records).length, 1, "the record did not load")
      verify(Store.facts.length > 0, "the fact history did not load")
      Store.backend = null
      suite.assertTheFileSurvived("a backend taken away after it had answered")
    }

    // And the one answer that IS a proof. Layer 3 only returns null once
    // `_absenceIsProven()` has agreed, and re-proves it before the first write.
    function test_08_only_an_explicit_null_is_a_fresh_install() {
      disk.blob = ""
      suite.freshStore("load-null")
      verify(Store.loaded, "a proved absence did not load")
      compare(Store.quarantined, false, "a proved absence was quarantined")
      // The garage's own fresh-install values, which three committed QML tests
      // in tst_garage_keyboard.qml also assert through the garage itself.
      compare(Store.setting("kartNumber"), 7)
      compare(Store.setting("kartBody"), 0)
      compare(suite.oneKeystroke(), true, "a fresh install refused to save")
      compare(disk.writes, 1)
      verify(disk.blob.length > 0, "nothing was written on a fresh install")
    }

    // A payload of the wrong protocol is a bug, not a shape to tolerate.
    function test_09_an_object_under_the_text_protocol_is_quarantined() {
      suite.freshStore("load-object")
      suite.assertTheFileSurvived("an object handed back under the text protocol")
    }

    // =====================================================================
    // 2. A QUARANTINE IS KEPT, RUNS FROM MEMORY, AND IS VISIBLE
    // =====================================================================

    // The design rejects an unknown key rather than dropping it, and `save.ts`
    // enforces that. This is the whole chain: an unknown key reaches the store,
    // the store refuses the file, and the file stays on the disk.
    function test_10_an_unknown_key_quarantines_and_the_file_is_left_alone() {
      var poisoned = JSON.parse(suite.victimText())
      poisoned.settings.theme = 1
      disk.blob = JSON.stringify(poisoned, null, 2) + "\n"
      var before = disk.blob
      suite.freshStore()
      verify(Store.quarantined, "an unknown settings key was accepted")
      compare(suite.oneKeystroke(), false)
      compare(disk.blob, before, "the unreadable file was overwritten")
      compare(disk.writes, 0)
    }

    // The session is still the child's. The garage's controls still work; what
    // they do not do is claim to have been saved.
    function test_11_a_quarantined_session_still_plays_and_says_it_is_not_saved() {
      suite.freshStore("load-throws")
      compare(Store.setSetting("kartBody", 3), false, "setSetting claimed a quarantined save")
      compare(Store.setting("kartBody"), 3, "the change did not apply for the session")
      compare(Store.setSetting("scanlines", true), false)
      compare(Store.setting("scanlines"), true)
      compare(disk.writes, 0)
    }

    // What a screen has to read to be able to say anything at all. ui/Game.qml
    // draws `quarantineReason` for the grown-up; ui/Settings.qml prints it in
    // the RESET panel and offers the one action there is.
    function test_12_a_screen_can_tell_the_child_and_the_parent() {
      suite.freshStore("load-throws")
      compare(Store.quarantined, true)
      verify(Store.quarantineReason.length > 0, "there is nothing for a screen to show")
      verify(Store.quarantineIssues.length > 0, "there is no issue list for a screen to show")
      verify(Store.quarantineIssues[0].problem.length > 0,
             "the issue has no problem to print")
      // The reason is one line, in the schema's own path/problem form, so it
      // fits a strip across a screen rather than needing a scroll.
      compare(Store.quarantineReason.indexOf("\n"), -1, "the reason is not one line")
    }

    // Reading the same file again quarantines it again: the file survives
    // indefinitely rather than being repaired by chance on a later launch.
    function test_13_a_quarantine_survives_a_reload() {
      suite.freshStore("load-throws")
      var before = disk.blob
      Store.reload()
      compare(Store.quarantined, true)
      compare(disk.blob, before)
      compare(disk.writes, 0)
    }

    // The only way out, and only ui/Settings.qml calls it -- behind the same
    // Confirm dialog the three resets use, naming what is lost.
    function test_14_discarding_a_quarantined_file_is_the_one_way_out() {
      suite.freshStore("load-throws")
      compare(Store.discardQuarantinedFile(), true)
      compare(Store.quarantined, false)
      compare(Store.quarantineReason, "")
      compare(disk.writes, 1, "discarding did not start a new file")
      var fresh = suite.onDisk()
      verify(fresh !== null, "the new file does not parse")
      compare(Object.keys(fresh.records).length, 0)
      compare(fresh.facts.length, 0)
      // And it does nothing when there is nothing to discard.
      compare(Store.discardQuarantinedFile(), false)
    }

    // A write that fails stops the writing for the session and does not retry
    // on every keystroke -- and the session keeps playing.
    function test_15_a_write_that_throws_stops_the_writing_and_keeps_the_session() {
      suite.freshStore("save-throws")
      verify(Store.loaded && !Store.quarantined, "the file did not load")
      compare(Store.setSetting("kartBody", 3), true, "the first write is attempted")
      compare(Store.quarantined, true, "a failed write did not stop the writing")
      verify(Store.quarantineReason.indexOf("ENOSPC") >= 0, Store.quarantineReason)
      // The child's records are still in memory: the session is still theirs.
      verify(Object.keys(Store.records).length > 0, "the session lost the records it had read")
      verify(Store.facts.length > 0, "the session lost the fact history it had read")
      compare(Store.setSetting("kartPaint", 4), false)
      compare(Store.setting("kartPaint"), 4, "the session stopped applying changes")
    }

    // The write-side entry point layer 3 uses: the file object reports a failed
    // write by signal, not by exception, so `flush`'s try cannot see it and
    // TurboTables.qml connects `writeFailed` straight to here.
    function test_16_a_write_failure_reported_by_signal_stops_the_writing() {
      suite.freshStore()
      Store.writeFailed("the disk is full")
      compare(Store.quarantined, true)
      verify(Store.quarantineReason.indexOf("disk is full") >= 0, Store.quarantineReason)
      compare(Store.setSetting("kartBody", 3), false)
    }

    // =====================================================================
    // 3. THE DESIGN'S DATA TABLE, AND NOTHING ELSE
    // =====================================================================

    // Design, Data: three keys, and `settings` is "sound, reduced motion,
    // scanlines, kart, paint, number, rival level, streak threshold if
    // exposed". `save.ts` refuses a key it does not know, so this asserts the
    // file the store actually writes rather than what it meant to.
    function test_17_the_file_holds_the_designs_three_keys_and_no_others() {
      disk.blob = ""
      suite.freshStore("load-null")
      suite.oneKeystroke()
      var written = JSON.parse(disk.blob)
      compare(Object.keys(written).sort().join(","), "facts,records,settings,version")
      compare(Object.keys(written.settings).sort().join(","),
              "kart,number,paint,reducedMotion,rivalLevel,scanlines,sound,streakThreshold")
      // And what the engine's own validator says about it, which is the check
      // that cannot drift from the file format.
      var parsed = Engine.parseSave(disk.blob)
      compare(parsed.ok, true, JSON.stringify(parsed.issues))
    }

    // docs/open-questions.md, settled: race mode and math set are this
    // session's choices and are not saved state. They keep working; what they
    // do not do is claim to have been written.
    function test_18_race_mode_and_math_set_apply_and_do_not_persist() {
      disk.blob = ""
      suite.freshStore("load-null")
      compare(Store.setSetting("raceMode", 1), false,
              "setSetting claimed raceMode would survive a reload")
      compare(Store.setting("raceMode"), 1, "raceMode did not apply for the session")
      compare(Store.setSetting("mathSet", 0), false)
      compare(Store.setting("mathSet"), 0)
      compare(disk.writes, 0, "a session-only setting wrote to the file")

      // And they are not in the file even when something else writes it.
      suite.oneKeystroke()
      compare(disk.blob.indexOf("raceMode"), -1, "raceMode reached the save file")
      compare(disk.blob.indexOf("mathSet"), -1, "mathSet reached the save file")
    }

    // Design, Data: "No dates, no session counts, no Grand Prix history, no
    // streak history."
    function test_19_no_date_reaches_the_save_file() {
      suite.freshStore()
      suite.oneKeystroke()
      var text = disk.blob.toLowerCase()
      compare(text.indexOf("date"), -1, "the save file mentions a date")
      compare(text.indexOf("stamp"), -1, "the save file mentions a stamp")
      compare(text.indexOf("session"), -1, "the save file mentions a session")
    }

    // Design, Data: "Human-readable, so a parent can see exactly what is kept."
    // The promise behind it is that an unchanged file writes identical bytes --
    // which is false for any file the store cannot carry, and `streakThreshold`
    // is the one value the garage never shows and a valid file may still hold.
    function test_20_an_unchanged_file_writes_identical_bytes() {
      var before = disk.blob
      suite.freshStore()
      compare(Engine.parseSave(before).file.settings.streakThreshold, 15,
              "the fixture does not carry the parity threshold")
      // A write that changes nothing: setSetting short-circuits an equal value,
      // so flush() is called directly.
      Store.flush()
      compare(disk.writes, 1)
      compare(disk.blob, before, "an unchanged file did not write identical bytes")
    }

    // The round trip the design's Data row rests on: what the store writes,
    // `parseSave` reads back, and the second write is the same bytes again.
    function test_21_what_the_store_writes_is_what_save_ts_reads_back() {
      suite.freshStore()
      Store.setSetting("kartBody", 2)
      var first = disk.blob
      var parsed = Engine.parseSave(first)
      compare(parsed.ok, true, JSON.stringify(parsed.issues))
      compare(Engine.serialiseSave(parsed.file), first, "the file does not round-trip")

      // And back in through the store: the same values come out.
      suite.freshStore()
      compare(Store.setting("kartBody"), 2)
      compare(Store.setting("kartNumber"), 42)
      compare(Store.setting("sound"), false)
      compare(Store.setting("rivalLevel"), 2)
      Store.flush()
      compare(disk.blob, first, "a load-then-save changed the file")
    }

    // The one file shape that is not a version of this schema and still has to
    // be read: what the first ui/Store.qml wrote. It is converted, not
    // quarantined, and the conversion is save.ts's own.
    function test_22_a_legacy_garage_file_is_converted_not_quarantined() {
      disk.blob = JSON.stringify({
        "version": 1,
        "settings": { "kartBody": 2, "kartPaint": 3, "kartNumber": 21,
                      "rivalLevel": 2, "raceMode": 1, "mathSet": 0,
                      "sound": false, "reducedMotion": true, "scanlines": false },
        "records": {}, "facts": {}
      }, null, 2)
      suite.freshStore()
      compare(Store.quarantined, false, "a legacy file was quarantined: " + Store.quarantineReason)
      compare(Store.setting("kartBody"), 2)
      compare(Store.setting("kartNumber"), 21)
      compare(Store.setting("rivalLevel"), 2)
      // And the first write turns it into a file of the current schema.
      suite.oneKeystroke()
      compare(Engine.parseSave(disk.blob).ok, true)
    }

    // =====================================================================
    // 4. THE THREE RESETS, PROVED AT THE PERSISTED PAYLOAD
    //
    // Design, Data, the "Reset by" column: three operations, one per key. The
    // separation is the point -- a child who wants a clean leaderboard must not
    // lose the mastery the fact history holds -- so each case reads the other
    // two keys OFF THE FILE THE RESET WROTE and compares the bytes. Comparing
    // the Store's own properties would only prove the Store agrees with itself.
    // =====================================================================

    function keyBytes(key) {
      var file = suite.onDisk()
      return file === null ? "<unreadable>" : JSON.stringify(file[key])
    }

    function test_23_resetting_settings_leaves_records_and_facts_byte_identical() {
      suite.freshStore()
      Store.flush()
      var records = suite.keyBytes("records")
      var facts = suite.keyBytes("facts")
      verify(records.length > 10 && facts.length > 10, "the fixture has nothing to protect")

      compare(Store.resetSettings(), true)
      compare(suite.keyBytes("records"), records, "resetting settings touched the records")
      compare(suite.keyBytes("facts"), facts, "resetting settings touched the fact history")
      // And the settings are the ones a fresh install shows -- one meaning of
      // "the defaults" for one row of the design's table.
      compare(Store.setting("kartNumber"), 7)
      compare(Store.setting("kartBody"), 0)
      compare(Store.setting("sound"), true)
      compare(suite.onDisk().settings.number, 7)
    }

    function test_24_resetting_records_leaves_settings_and_facts_byte_identical() {
      suite.freshStore()
      Store.flush()
      var settings = suite.keyBytes("settings")
      var facts = suite.keyBytes("facts")

      compare(Store.resetRecords(), true)
      compare(suite.keyBytes("settings"), settings, "resetting records touched the settings")
      compare(suite.keyBytes("facts"), facts, "resetting records touched the fact history")
      compare(suite.keyBytes("records"), "{}", "the records were not cleared")
    }

    function test_25_resetting_facts_leaves_settings_and_records_byte_identical() {
      suite.freshStore()
      Store.flush()
      var settings = suite.keyBytes("settings")
      var records = suite.keyBytes("records")

      compare(Store.resetFacts(), true)
      compare(suite.keyBytes("settings"), settings, "resetting facts touched the settings")
      compare(suite.keyBytes("records"), records, "resetting facts touched the records")
      compare(suite.keyBytes("facts"), "[]", "the fact history was not cleared")
    }

    // Design, Data: three, and no fourth. `ui/Settings.qml` has exactly these
    // three reset buttons plus, only while there is a quarantine to act on, the
    // way out of one.
    function test_26_a_reset_over_a_quarantined_file_writes_nothing_and_says_so() {
      suite.freshStore("load-throws")
      var before = disk.blob
      compare(Store.resetSettings(), false)
      compare(Store.resetRecords(), false)
      compare(Store.resetFacts(), false)
      compare(disk.writes, 0)
      compare(disk.blob, before)
    }

    // =====================================================================
    // 5. THE RACE SEAM
    //
    // The load half is `factHistoryForRace()`, the write half is `commit()`,
    // and the engine refuses any commit whose declared baseline is not the file
    // it is being folded into. The Store is what holds the pair together, so no
    // screen can hand it the wrong one.
    // =====================================================================

    function totalAttempts(facts) {
      var n = 0
      for (var i = 0; i < facts.length; i++)
        n += facts[i].attempts
      return n
    }

    function test_27_a_race_seeded_from_the_file_commits_its_facts_and_its_record() {
      disk.blob = ""
      suite.freshStore("load-null")
      var seeded = Store.factHistoryForRace()
      compare(seeded.length, 0, "a fresh install seeded a race with something")

      var race = suite.playRace(21, "timeTrial", "2-5", seeded)
      var result = Store.commit(race.state, race.timeline)
      compare(result.issues.length, 0, JSON.stringify(result.issues))
      compare(result.factsUpdated, true, "the fact history was refused")
      compare(result.recordUpdated, true, "a clean time trial set no record")

      // On disk, not in memory.
      var file = suite.onDisk()
      verify(file !== null, "the committed file does not parse")
      compare(file.facts.length, Engine.factHistoryOf(race.state).length)
      compare(suite.totalAttempts(file.facts),
              Engine.humanRacer(race.state).attemptCount,
              "the file does not hold the race's own answers")
      compare(Object.keys(file.records).length, 1)
      compare(file.records[Engine.recordKeyOf(race.state)].preset, "2-5")
      verify(file.records[Engine.recordKeyOf(race.state)].timeline.samples.length > 0,
             "the record carries no ghost timeline")
    }

    // The bug the engine spent three rounds on, asserted from the caller's
    // side: one race banked twice must not double a child's counts.
    function test_28_committing_the_same_race_twice_does_not_double_the_counts() {
      disk.blob = ""
      suite.freshStore("load-null")
      var race = suite.playRace(21, "timeTrial", "2-5", Store.factHistoryForRace())
      var first = Store.commit(race.state, race.timeline)
      compare(first.factsUpdated, true)
      var after = suite.keyBytes("facts")
      var attempts = suite.totalAttempts(suite.onDisk().facts)

      var second = Store.commit(race.state, race.timeline)
      compare(second.factsUpdated, false, "the same race was folded in twice")
      verify(second.issues.length > 0, "a repeat commit was silent")
      compare(suite.keyBytes("facts"), after, "the fact history moved on a repeat commit")
      compare(suite.totalAttempts(suite.onDisk().facts), attempts)
    }

    // Two races in a session: the second is seeded from the file as the first
    // left it, and its answers add.
    function test_29_a_second_race_adds_to_the_first() {
      disk.blob = ""
      suite.freshStore("load-null")
      var one = suite.playRace(21, "timeTrial", "2-5", Store.factHistoryForRace())
      Store.commit(one.state, one.timeline)
      var afterOne = suite.totalAttempts(suite.onDisk().facts)

      var two = suite.playRace(77, "timeTrial", "2-5", Store.factHistoryForRace())
      var result = Store.commit(two.state, two.timeline)
      compare(result.issues.length, 0, JSON.stringify(result.issues))
      compare(result.factsUpdated, true, "the second race was refused")
      compare(suite.totalAttempts(suite.onDisk().facts),
              afterOne + Engine.humanRacer(two.state).attemptCount,
              "the second race's answers did not all land")
    }

    // Design, Modes: "Time trial and ghost set records; Grand Prix never does",
    // and its own row: "places and times are shown, never stored as records".
    function test_30_a_grand_prix_banks_facts_and_never_a_record() {
      disk.blob = ""
      suite.freshStore("load-null")
      var race = suite.playRace(31, "grandPrix", "2-5", Store.factHistoryForRace())
      var result = Store.commit(race.state, race.timeline)
      compare(result.factsUpdated, true, "a Grand Prix banked no facts")
      compare(result.recordUpdated, false, "a Grand Prix set a record")
      compare(Object.keys(suite.onDisk().records).length, 0)
      verify(suite.onDisk().facts.length > 0)
    }

    // A commit while quarantined still moves the session's own history -- the
    // mastery lamps are still the child's to watch -- and writes nothing.
    function test_31_a_commit_while_quarantined_keeps_the_session_and_writes_nothing() {
      suite.freshStore("load-throws")
      var before = disk.blob
      var race = suite.playRace(41, "timeTrial", "2-5", Store.factHistoryForRace())
      var result = Store.commit(race.state, race.timeline)
      verify(result !== null, "the race was dropped before it reached memory")
      compare(result.factsUpdated, true, "the session's own history did not move")
      verify(Store.facts.length > 0, "the session lost the race it just ran")
      compare(disk.writes, 0, "a quarantined session wrote to the file")
      compare(disk.blob, before)
    }

    // A fact-history reset under a running race costs that race its answers,
    // and it does so out loud rather than by writing counts it cannot account
    // for. It is a decision, so it has a test that says so.
    function test_32_a_fact_reset_under_a_running_race_costs_that_race_its_answers() {
      suite.freshStore()
      var race = suite.playRace(51, "timeTrial", "2-5", Store.factHistoryForRace())
      compare(Store.resetFacts(), true)
      var result = Store.commit(race.state, race.timeline)
      compare(result.factsUpdated, false, "a race seeded from a history that is gone was banked")
      verify(result.issues.length > 0, "the refusal was silent")
      compare(suite.keyBytes("facts"), "[]", "the reset did not stand")
    }

    // Nothing is written before a load has answered. A screen that writes here
    // would be writing over a save that has not arrived yet.
    function test_33_nothing_is_written_before_a_load_has_answered() {
      var before = disk.blob
      Store.loaded = false
      Store.quarantined = false
      Store._backendHasAnswered = false
      compare(Store.setSetting("kartBody", 3), false)
      compare(Store.resetSettings(), false)
      compare(Store.resetRecords(), false)
      compare(Store.resetFacts(), false)
      compare(Store.commit(null, null), null)
      compare(disk.blob, before)
    }

    // `adopt` is a public function on a singleton, so it keeps the `undefined`
    // guard of its own rather than trusting `reload()` to have made it. It is
    // the second lock on the door four rounds came through, and this is what
    // makes it a lock rather than a comment.
    function test_34_adopt_refuses_undefined_once_a_file_has_been_read() {
      suite.freshStore()
      var before = disk.blob
      verify(Store.loaded && !Store.quarantined)
      Store.adopt(undefined)
      compare(Store.quarantined, true, "adopt(undefined) was read as a fresh install")
      compare(Store.setSetting("kartBody", 3), false)
      compare(disk.writes, 0)
      compare(disk.blob, before)
    }

    // =====================================================================
    // 6. THE SEAM IS ACTUALLY WIRED
    //
    // Four rounds of review ended with the same sentence: `save.ts` is correct
    // and no shipping code has ever called it. Everything above this line is a
    // property of `ui/Store.qml`; these three are about whether anything in the
    // game reaches it.
    // =====================================================================

    // ui/Race.qml hands `factHistory` to `Engine.createRace`, which is the
    // engine's own load-side seam. Without it a race starts from nothing, its
    // history cannot equal the file's plus its own answers, and every commit
    // for the rest of the session is refused.
    function test_35_the_race_screen_seeds_the_engine_from_the_save_file() {
      suite.freshStore()
      var seeded = Store.factHistoryForRace()
      verify(seeded.length > 0, "the fixture has no fact history to seed with")

      raceProbe.factHistory = seeded
      raceProbe.seed = 91
      verify(raceProbe.state !== null, "the race did not build")
      var inRace = Engine.factHistoryOf(raceProbe.state)
      compare(inRace.length, seeded.length,
              "the race was not created with the child's saved fact history")
      compare(JSON.stringify(inRace), JSON.stringify(seeded))
      // And the ghost timeline starts empty for a new race rather than carrying
      // the previous one's samples into this one's record.
      compare(raceProbe.ghostTimeline.samples.length, 0)
    }

    // ui/Game.qml owns a race from start to flag, so it is the only thing that
    // can honestly bank one. This drives its two seam calls directly rather
    // than playing a race through the screen: `startRace()` seeds, and
    // `raceIsOver()` banks, once, before the results screen exists.
    function test_36_the_flow_seeds_a_race_and_banks_it_at_the_flag() {
      disk.blob = ""
      suite.freshStore("load-null")
      compare(disk.writes, 0)

      flowProbe.startRace()
      compare(flowProbe.screen, "garage", "the transition is deferred by a turn of the loop")
      compare(flowProbe.raceFactHistory.length, 0, "a fresh install seeded something")

      var race = suite.playRace(61, "timeTrial", "2-5", flowProbe.raceFactHistory)
      flowProbe.raceIsOver(race.state, race.timeline)

      verify(flowProbe.lastCommit !== null, "the flow banked nothing at the flag")
      compare(flowProbe.lastCommit.factsUpdated, true)
      compare(flowProbe.lastCommit.recordUpdated, true)
      var file = suite.onDisk()
      verify(file !== null, "nothing readable reached the disk")
      compare(suite.totalAttempts(file.facts),
              Engine.humanRacer(race.state).attemptCount)
      compare(Object.keys(file.records).length, 1)
    }

    // A second race in the same session is seeded from the file as the first
    // left it, so its answers add rather than being refused.
    function test_37_the_flow_reseeds_between_races() {
      disk.blob = ""
      suite.freshStore("load-null")
      flowProbe.startRace()
      var one = suite.playRace(61, "timeTrial", "2-5", flowProbe.raceFactHistory)
      flowProbe.raceIsOver(one.state, one.timeline)
      var afterOne = suite.totalAttempts(suite.onDisk().facts)

      flowProbe.startRace()
      verify(flowProbe.raceFactHistory.length > 0, "the second race was seeded with nothing")
      var two = suite.playRace(62, "timeTrial", "2-5", flowProbe.raceFactHistory)
      flowProbe.raceIsOver(two.state, two.timeline)
      compare(flowProbe.lastCommit.issues.length, 0,
              JSON.stringify(flowProbe.lastCommit.issues))
      compare(flowProbe.lastCommit.factsUpdated, true)
      compare(suite.totalAttempts(suite.onDisk().facts),
              afterOne + Engine.humanRacer(two.state).attemptCount)
    }

    // ui/Settings.qml's three resets are the engine's three, not its own. The
    // screen used to assemble a save file by hand and write back the one key it
    // believed had changed, which is a second copy of "a reset touches exactly
    // its own key" -- and that copy drifted twice.
    function test_38_the_settings_screen_resets_through_the_store() {
      suite.freshStore()
      Store.flush()
      var records = suite.keyBytes("records")
      var facts = suite.keyBytes("facts")

      compare(settingsProbe.applyReset("settings"), true)
      compare(suite.keyBytes("records"), records, "the screen's reset touched the records")
      compare(suite.keyBytes("facts"), facts, "the screen's reset touched the fact history")
      compare(suite.onDisk().settings.number, 7, "the screen did not reset to the defaults")

      compare(settingsProbe.applyReset("records"), true)
      compare(suite.keyBytes("facts"), facts, "clearing records touched the fact history")
      compare(suite.keyBytes("records"), "{}")

      compare(settingsProbe.applyReset("facts"), true)
      compare(suite.keyBytes("facts"), "[]")
    }

    // And the screen tells the truth when the file did not change.
    function test_39_the_settings_screen_says_nothing_was_changed_over_a_quarantine() {
      suite.freshStore("load-throws")
      var before = disk.blob
      compare(settingsProbe.applyReset("settings"), false)
      compare(settingsProbe.applyReset("records"), false)
      compare(settingsProbe.applyReset("facts"), false)
      compare(disk.blob, before)
      // The one action a quarantine does offer, and the only caller of it.
      compare(settingsProbe.applyReset("discard"), true)
      compare(Store.quarantined, false)
    }

    // The screen half of requirement 4: a quarantine has to be visible without
    // a keystroke. `ui/Game.qml` draws a notice on every screen a child can
    // stand still on, and `ui/Settings.qml` puts the schema's own sentence
    // where a grown-up will look and adds the one way out to the focus chain.
    function test_40_a_screen_shows_the_quarantine_without_a_keystroke() {
      suite.freshStore()
      compare(flowProbe.noticeVisible, false, "a healthy file draws a warning")
      var healthyStops = settingsProbe.stops.length

      suite.freshStore("load-throws")
      // On every screen a child can stand still on, and not only one of them:
      // the file is unreadable for the whole session, so the notice is up for
      // the whole session.
      var standing = ["garage", "results", "settings"]
      for (var i = 0; i < standing.length; i++) {
        flowProbe.screen = standing[i]
        compare(flowProbe.noticeVisible, true,
                "nothing on the " + standing[i] + " screen says the save file is locked")
      }
      flowProbe.screen = "garage"
      verify(flowProbe.noticeSays.indexOf("ASK A GROWN-UP") >= 0
             || flowProbe.noticeSays.toUpperCase().indexOf("ASK A GROWN-UP") >= 0,
             "the child is not told what to do: " + flowProbe.noticeSays)
      verify(flowProbe.noticeWhy.indexOf(Store.quarantineReason) >= 0,
             "the grown-up is not told why: " + flowProbe.noticeWhy)
      compare(settingsProbe.stops.length, healthyStops + 1,
              "the way out of a quarantine is not reachable by keyboard")
      compare(settingsProbe.focusName(healthyStops - 1), "Start a new save file")
    }
  }

  // ------------------------------------------------------------- the probes
  //
  // The real screens, instantiated once. They are what turns this from a spec
  // for one file into a spec for the seam: `save.ts`'s guarantees have been
  // correct for four rounds and unreachable from the game for all four.
  Race {
    id: raceProbe
    width: 640
    height: 360
    visible: false
    mode: "timeTrial"
    preset: "2-5"
  }

  Settings {
    id: settingsProbe
    width: 640
    height: 360
    visible: false
  }

  // Visible on purpose. Qt Quick's `visible` property reads back the item's
  // *effective* visibility, so every child of an invisible parent answers false
  // -- and a notice test that read `false` from an item it had hidden itself
  // would pass for the wrong reason, or fail for one. The flow is drawn, and
  // the notice is asked whether it is on screen.
  Game {
    id: flowProbe
    anchors.fill: parent
  }
}
