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
//
// `shell/FileStore.qml` -- the layer below this one -- now has a spec of its
// own, and it is deliberately NOT in this directory: it needs a model of
// Quickshell to run at all, and a spec importing a shell module cannot compile
// on a machine with no Quickshell. It lives in `tests/qml-shell/` with the
// model, and is run by:
//
//   qmltestrunner -input tests/qml-shell -import ui -import tests/qml-shell
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

  // The other disk: the one section 7 uses, which can also be unreadable,
  // unwritable, absent, or quietly replaced by somebody else while the session
  // is running. `disk` above cannot be any of those, which is most of the
  // reason section 7 did not exist.
  QtObject {
    id: realDisk
    property string blob: ""
    property bool exists: true
    property bool readable: true
    property bool writable: true
    property int writes: 0

    function reset(text) {
      realDisk.blob = text === undefined ? "" : text
      realDisk.exists = text !== undefined && text.length > 0
      realDisk.readable = true
      realDisk.writable = true
      realDisk.writes = 0
    }
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

    // ---------------------------------------------------------------------
    // A BACKEND THAT CAN SAY NO
    //
    // THE FIXTURE CHOICE THAT COST FOUR ROUNDS. Every backend above accepts
    // every write it is handed. `shell/FileStore.qml` does not: it has four
    // refusals of its own, and three of them are exactly the state a save file
    // that could not be *read* leaves it in. So `test_14`, which asserts the
    // one way out of a quarantine, asserted it against a stub for which there
    // was nothing to get out of -- and the way out was inert in the product for
    // four rounds while a green test said it worked.
    //
    // This models the file layer's decisions, and only those. It is a second
    // copy of a rule and can therefore drift from the original, which is a real
    // cost and is why each branch names the refusal in `shell/FileStore.qml` it
    // stands for:
    //
    //   1. `!_everLoaded`               nothing before a read has answered
    //   2. `_verdict === "unreadable"`  nothing over a file that would not read
    //   3. blank payload                nothing empty, ever
    //   4. `_checkedTheBytesStillMatch` nothing over bytes it does not know
    //
    //   `replaceUnreadableFile()`  stands 1, 2 and 4 down for exactly one write
    //   `allowWritingAgain()`      lifts only the latch a failed write set
    //   `flushNow()`               writes what the debounce is holding, now
    //
    // A failed write is reported the way the real one is -- by telling the
    // Store, which is what `TurboTables.qml` wires `writeFailed` to -- rather
    // than by throwing, because the Store's `try` around `save()` cannot see a
    // signal and that difference is itself a door.
    //
    // `debounced` is true by default because the real one always is: a write
    // that only lands because the child happened to press another key
    // afterwards has not landed.
    function fileBackendOf(options) {
      var opt = options === undefined ? {} : options
      var b = {
        "format": opt.format === undefined ? "text" : opt.format,
        "debounced": opt.debounced !== false,
        // The file layer's own state, spelled as it is spelled there.
        "everLoaded": false,
        "verdict": "unknown",
        "writable": true,
        "lastKnownText": "",
        "lastKnownTextIsKnown": false,
        "replaceAuthorised": false,
        "replacedTheFile": false,
        "pending": "",
        "hasPending": false,
        "refusals": []
      }

      b.stopWriting = function (reason) {
        if (!b.writable)
          return
        b.writable = false
        b.hasPending = false
        b.pending = ""
        b.refusals.push(reason)
        // How TurboTables.qml connects `writeFailed`. Not a throw: the Store's
        // `try` around `save()` never sees a signal.
        Store.writeFailed(reason)
      }

      b.load = function () {
        if (!realDisk.exists) {
          b.verdict = "absent"
          b.everLoaded = true
          return null                    // absence, modelled as proved
        }
        if (!realDisk.readable) {
          b.verdict = "unreadable"
          throw new Error("the save file could not be read: PermissionDenied")
        }
        b.verdict = "present"
        b.everLoaded = true
        b.lastKnownText = realDisk.blob
        b.lastKnownTextIsKnown = true
        return b.format === "text" ? realDisk.blob : JSON.parse(realDisk.blob)
      }

      b.save = function (payload) {
        var text = typeof payload === "string"
                 ? payload
                 : JSON.stringify(payload, null, 2) + "\n"

        // 3.
        if (text.replace(/\s+/g, "").length === 0) {
          b.stopWriting("refused to write an empty save file")
          return
        }
        // 1 and 2, and the exception a person's decision buys.
        if (!(b.replaceAuthorised || b.replacedTheFile)) {
          if (!b.everLoaded) {
            b.stopWriting("refused to write to the save file before the file had been read")
            return
          }
          if (b.verdict === "unreadable") {
            b.stopWriting("refused to write over an unreadable save file")
            return
          }
        }
        if (!b.writable)
          return

        b.pending = text
        b.hasPending = true
        if (!b.debounced)
          b.writeNow()
      }

      b.flushNow = function () { b.writeNow() }

      b.writeNow = function () {
        if (!b.hasPending || !b.writable)
          return
        var text = b.pending
        b.hasPending = false
        b.pending = ""

        // 4. The bytes about to be replaced have to be the bytes this session
        //    is holding a newer version of.
        if (!b.replaceAuthorised && b.lastKnownTextIsKnown) {
          if (realDisk.exists && realDisk.readable) {
            if (realDisk.blob !== b.lastKnownText) {
              b.stopWriting("the save file changed on disk after this session read it")
              return
            }
          } else if (realDisk.exists) {
            b.stopWriting("the save file could not be re-read before writing over it")
            return
          }
          // Not there at all: proved absent, so there is nothing to destroy.
        }

        if (!realDisk.writable) {
          b.stopWriting("the save file could not be written: ENOSPC")
          return
        }

        realDisk.blob = text
        realDisk.exists = true
        realDisk.writes += 1
        b.lastKnownText = text
        b.lastKnownTextIsKnown = true
        if (b.replaceAuthorised) {
          b.replaceAuthorised = false
          b.replacedTheFile = true
        }
      }

      b.allowWritingAgain = function () { b.writable = true }

      b.replaceUnreadableFile = function () {
        b.replaceAuthorised = true
        b.writable = true
      }

      return b
    }

    // The same wiring `TurboTables.qml` does at startup, so section 7 exercises
    // the pair rather than either half. A brand-new backend object every time:
    // assigning the same one twice fires no change and would skip the load.
    property var fileBack: null
    function freshFileStore(options) {
      Store.loaded = false
      Store.quarantined = false
      Store.quarantineIssues = []
      Store.quarantineReason = ""
      Store.quarantineKind = ""
      Store._backendHasAnswered = false
      Store._adoptedFormat = ""
      suite.fileBack = suite.fileBackendOf(options)
      Store.backend = suite.fileBack
      return suite.fileBack
    }

    // What is on the modelled disk, as the engine reads it.
    function realDiskFile() {
      var parsed = Engine.parseSave(realDisk.blob)
      return parsed.ok ? parsed.file : null
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
      Store.quarantineKind = ""
      Store._backendHasAnswered = false
      Store._adoptedFormat = ""
      Store.backend = suite.backendOf(broken)
    }

    function init() {
      disk.blob = suite.victimText()
      disk.writes = 0
      realDisk.reset(suite.victimText())
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
      // And it is quarantined for the RIGHT reason. Without this line the test
      // passes with `adopt`'s protocol check deleted -- the object falls
      // through to `parseSave`, which refuses it as text and quarantines with a
      // parse error. A mutation run found exactly that: the check the file
      // documents was guarded by nothing, and the test named after it was
      // passing for a different reason than its name claims. The reason is not
      // decoration; it is the sentence ui/Settings.qml puts in front of a
      // parent, and "not JSON" would send them to look at a file that is fine.
      verify(Store.quarantineReason.indexOf("declared text") >= 0
             && Store.quarantineReason.indexOf("handed back object") >= 0,
             "the reason does not name the protocol mismatch: " + Store.quarantineReason)
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
      // Including a change that changes nothing. `setSetting` answers "this
      // will survive a reload", and under a quarantine nothing will -- the
      // values in memory are the defaults, not the file's, so even setting a
      // key to what it already holds is not a claim this session can make. The
      // early-out for an unchanged value sits above the quarantine branch and
      // would answer true without this line.
      compare(Store.setSetting("kartBody", 3), false,
              "setting a key to what it already held claimed a save")
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
    //
    // THIS TEST'S BACKEND CAN REFUSE. It used to be `backendOf("load-throws")`,
    // whose `save` accepts everything it is handed, so the case the way out
    // exists for -- a file layer that is refusing to write because the read
    // never came back -- was not in the fixture at all. The way out was inert
    // in the product for four rounds underneath this green test. It is now the
    // faithful model above, over a disk that genuinely cannot be read.
    function test_14_discarding_a_quarantined_file_is_the_one_way_out() {
      realDisk.reset(suite.victimText())
      realDisk.readable = false
      var back = suite.freshFileStore()

      verify(Store.quarantined, "an unreadable file did not quarantine")
      compare(Store.quarantineKind, "read")
      compare(realDisk.writes, 0, "something was written over the unreadable file")
      // The file layer really is refusing: this is the state that made the way
      // out inert, asserted rather than assumed.
      compare(back.everLoaded, false, "the fixture's file layer thinks it has read the file")
      compare(back.verdict, "unreadable")

      compare(Store.discardQuarantinedFile(), true, "the way out reported what it did not do")
      compare(Store.quarantined, false, "the way out re-quarantined the session")
      compare(Store.quarantineReason, "")
      compare(back.refusals.length, 0,
              "the file layer refused the discard: " + JSON.stringify(back.refusals))
      compare(realDisk.writes, 1, "discarding did not start a new file")

      realDisk.readable = true
      var fresh = suite.realDiskFile()
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
      // The first write IS attempted -- `save` throwing is the proof of that --
      // and the answer is still false, because the change it carried did not
      // reach the file. `setSetting` used to answer true here on the reasoning
      // that the write had been tried; a screen cannot act on "tried".
      compare(Store.setSetting("kartBody", 3), false,
              "a change whose write was refused was reported as saved")
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
      suite.freshStore()
      // Start from a session that has the child's work in memory, so "nothing
      // was changed" can be checked against something.
      var records = Object.keys(Store.records).length
      var facts = Store.facts.length
      var number = Store.setting("kartNumber")
      verify(records > 0 && facts > 0, "the fixture did not load a real save")
      verify(number !== Store.defaultSettings.kartNumber,
             "the fixture's kart number is the default, so a reset would be invisible")
      Store.writeFailed("the disk is full")

      var before = disk.blob
      compare(Store.resetSettings(), false)
      compare(Store.resetRecords(), false)
      compare(Store.resetFacts(), false)
      compare(disk.writes, 0)
      compare(disk.blob, before)
      // A reset that answered "nothing was changed" must not have changed
      // anything -- including in memory. The three of them each go through the
      // engine and take every key back off the file that comes out, so a reset
      // that ran and only failed to WRITE would have emptied the session's
      // records and fact history behind a banner saying it had not. The return
      // value alone does not catch that: a mutation removing the quarantine
      // guard from `resetSettings` still answers false, because the flush it
      // reaches is refused for its own reasons.
      compare(Object.keys(Store.records).length, records,
              "a refused reset emptied the session's records anyway")
      compare(Store.facts.length, facts,
              "a refused reset emptied the session's fact history anyway")
      compare(Store.setting("kartNumber"), number,
              "a refused reset put the settings back to the defaults anyway")

      // And the same over a read-side quarantine, where the session is empty by
      // design and the file is the thing being protected.
      suite.freshStore("load-throws")
      var untouched = disk.blob
      compare(Store.resetSettings(), false)
      compare(Store.resetRecords(), false)
      compare(Store.resetFacts(), false)
      compare(disk.writes, 0)
      compare(disk.blob, untouched)
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

      // `flush()` keeps the guard of its own, rather than trusting the five
      // callers above to have made it. It is a public function on a singleton,
      // the same argument `adopt` keeps its own `undefined` guard for -- and
      // without this line the guard is unreachable from any test, because every
      // caller refuses first. A lock nothing can reach is a lock nobody is
      // checking.
      Store.flush()
      compare(disk.writes, 0, "flush wrote before a load had answered")
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

    // The other half of the same door, and the one that could not be reached
    // until `Component.onCompleted`'s guard was given a name.
    //
    // `adopt(null)` is the *legitimate* proved-absence path, so it cannot be
    // refused -- and run over a store that has already read a file it replaces
    // the child's records and fact history with the defaults, which the next
    // keystroke flushes over the file. What stops that is one condition on the
    // singleton's own completion, and because completion fires once before any
    // backend exists, the ordering that makes it matter cannot be produced in a
    // running process: a mutation deleting the guard survived the whole suite
    // four times. The state can be produced even when the ordering cannot.
    function test_34b_completion_does_not_re_adopt_over_a_file_that_has_been_read() {
      suite.freshStore()
      var records = Object.keys(Store.records).length
      var facts = Store.facts.length
      verify(records > 0 && facts > 0, "the fixture did not load a real save")

      Store.completeIfNothingHasAnswered()

      compare(Object.keys(Store.records).length, records,
              "completing the singleton emptied the records it had already read")
      compare(Store.facts.length, facts,
              "completing the singleton emptied the fact history it had already read")
      compare(Store.quarantined, false)
      // And the file behind it is still the child's.
      Store.setSetting("kartBody", 3)
      var after = suite.progressOnDisk()
      compare(after.records, 1, "the record was written away")
      verify(after.facts > 0, "the fact history was written away")
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

    // =====================================================================
    // 7. THE RECOVERY PATH, AND THE TWO RULES NOTHING GUARDED
    //
    // Everything above this line is about not touching the file. This section
    // is about what happens *after* the plugin has correctly decided not to,
    // which nobody had audited: a seam critic found the one action the product
    // offers a family in that state did nothing, said it had worked, and that
    // the only remedy outside the game -- a parent putting a good file back by
    // hand -- was destroyed by the plugin on the child's next keystroke. The
    // two composed into permanent, unrecoverable loss with a screen saying it
    // was fine.
    //
    // It also banks the two rules an independent mutation run found guarded by
    // nothing: the JSON-array check in `fileFromObject`, and a race committed
    // over a fact history that is not empty -- which is to say, the normal case.
    // =====================================================================

    // --------------------------------------------------------------- D-1
    //
    // The way out has to move bytes, and what it reports has to be what it did.
    // Measured before the fix: `discard returned true, writes=0,
    // bytesMoved=false, quarantinedAfter=true` -- so ui/Settings.qml showed
    // "A NEW SAVE FILE HAS BEEN STARTED" on the same screen as the red strip.
    function test_41_the_way_out_of_a_read_side_quarantine_writes_and_says_so() {
      realDisk.reset(suite.victimText())
      realDisk.readable = false
      var back = suite.freshFileStore()
      verify(Store.quarantined)

      // The screen's own path, question and answer, because the sentence a
      // family reads is the observable this defect was invisible in.
      settingsProbe.pending = "discard"
      settingsProbe.answer(true)

      compare(Store.quarantined, false, "the session is still locked after the way out")
      compare(realDisk.writes, 1, "the way out wrote nothing")
      compare(settingsProbe.bannerText, "A NEW SAVE FILE HAS BEEN STARTED")
      realDisk.readable = true
      verify(suite.realDiskFile() !== null, "what was written is not a save file")

      // And the session saves from here on without needing to be authorised
      // again: the file layer owns the file it just wrote.
      compare(Store.setSetting("kartBody", 3), true, "the session did not start saving again")
      back.flushNow()
      compare(realDisk.writes, 2, "the next change did not reach the file")
      compare(suite.realDiskFile().settings.kart, 4)
    }

    // The other half of the same requirement: when the mechanism cannot work,
    // the report says so. A disk that cannot be read AND cannot be written is
    // the case a banner claiming success would be a lie about.
    function test_42_a_way_out_that_could_not_write_reports_that_it_did_not() {
      realDisk.reset(suite.victimText())
      realDisk.readable = false
      realDisk.writable = false
      suite.freshFileStore()
      verify(Store.quarantined)
      var before = realDisk.blob

      settingsProbe.pending = "discard"
      settingsProbe.answer(true)

      compare(settingsProbe.bannerText, "NOTHING WAS CHANGED",
              "the screen claimed a new save file that was never written")
      compare(Store.quarantined, true, "the session was left believing it can write")
      compare(realDisk.writes, 0)
      compare(realDisk.blob, before, "the unwritable file moved")
      // Still offered, because there is still a quarantine to act on.
      verify(settingsProbe.quarantined)
    }

    // And with nothing on the other end at all, which is the shape D-4 has on
    // the recovery path: a discard cannot claim a file it has no way to reach.
    function test_43_a_way_out_with_no_backend_to_write_through_reports_false() {
      suite.freshStore()
      Store.backend = null                       // taken away after answering
      verify(Store.quarantined)
      compare(Store.discardQuarantinedFile(), false,
              "a discard with nothing to write through said a new file was started")
      compare(Store.quarantined, true)
      compare(disk.writes, 0)
    }

    // --------------------------------------------------------------- D-2
    //
    // A file that changes on disk under a running shell is never silently
    // overwritten. VM-reproduced before the fix: a second writer's save,
    // holding a record this session had never seen, was gone after one
    // keystroke -- no probe, no refusal, no message. This is what made a
    // corrupt save file unrecoverable, because hand-restoring it is the
    // obvious human remedy.
    function test_44_a_save_that_changed_on_disk_is_not_overwritten() {
      realDisk.reset(suite.victimText())
      var back = suite.freshFileStore()
      verify(Store.loaded && !Store.quarantined, "the file did not load")

      // A parent puts a different, good save file back while the child is
      // logged in. It holds a race this session has never seen.
      var restored = suite.victimFile()
      var keys = Object.keys(restored.records)
      verify(keys.length > 0 && restored.facts.length > 0, "the fixture is not a real save")
      restored.records[keys[0]].timeMs -= 1200      // a better time, from another day
      restored.facts[0].attempts += 7               // and seven answers this session never saw
      restored.facts[0].correct += 7
      var restoredText = Engine.serialiseSave(restored)
      verify(restoredText !== realDisk.blob, "the fixture did not actually change the file")
      realDisk.blob = restoredText

      Store.setSetting("kartBody", 3)
      back.flushNow()

      compare(realDisk.blob, restoredText, "the other writer's save was overwritten")
      compare(realDisk.writes, 0)
      verify(Store.quarantined, "the refusal was silent")
      verify(Store.quarantineReason.indexOf("changed on disk") >= 0, Store.quarantineReason)
      compare(Store.setSetting("kartPaint", 4), false)
    }

    // The same rule over the path the absence re-proof does not cover: once
    // this session has written the file itself, the "absent" re-proof retires
    // and every write after that used to be taken on trust.
    function test_45_a_fresh_install_that_wrote_once_still_checks_before_writing_again() {
      realDisk.reset()                            // nothing on disk at all
      var back = suite.freshFileStore()
      verify(Store.loaded && !Store.quarantined, "a proved absence did not load")

      Store.setSetting("kartBody", 3)
      back.flushNow()
      compare(realDisk.writes, 1, "the fresh install wrote nothing")

      // Somebody else writes over it between one keystroke and the next.
      var theirs = Engine.serialiseSave(suite.victimFile())
      realDisk.blob = theirs

      Store.setSetting("kartPaint", 5)
      back.flushNow()
      compare(realDisk.blob, theirs, "the second writer's save was overwritten")
      compare(realDisk.writes, 1)
      verify(Store.quarantined, "the refusal was silent")
    }

    // The write-side quarantine's way out, which must not cost the child the
    // records the session read before the disk filled up.
    function test_46_recovering_from_a_write_side_quarantine_keeps_the_session() {
      realDisk.reset(suite.victimText())
      var back = suite.freshFileStore()
      var records = Object.keys(Store.records).length
      verify(records > 0 && Store.facts.length > 0, "the file did not load")

      realDisk.writable = false
      Store.setSetting("kartBody", 3)
      back.flushNow()
      verify(Store.quarantined, "a failed write did not stop the writing")
      compare(Store.quarantineKind, "write")
      // And the screen says which half it was. A parent told the file could not
      // be READ goes and looks at a file that is perfectly fine.
      verify(settingsProbe.quarantineHeadline.indexOf("WRITTEN") >= 0,
             settingsProbe.quarantineHeadline)

      realDisk.writable = true
      compare(Store.discardQuarantinedFile(), true)
      compare(realDisk.writes, 1)
      var after = suite.realDiskFile()
      verify(after !== null, "the recovered file does not parse")
      compare(Object.keys(after.records).length, records,
              "recovering from a full disk cost the child their records")
      verify(after.facts.length > 0, "recovering from a full disk cost the fact history")
    }

    // --------------------------------------------------------------- D-4
    //
    // A store that cannot write anything used to say every change was saved:
    // `setSetting` true, `quarantined` false, writes 0, no NOT SAVED anywhere,
    // for the whole session. The file survived only because there was no `save`
    // to call, which is luck, not a rule -- and luck that says "saved".
    function test_47_a_backend_with_no_save_to_call_is_a_quarantine() {
      var b = { "format": "text" }
      b.load = function () { return disk.blob }      // no save at all
      var before = disk.blob
      Store.loaded = false
      Store.quarantined = false
      Store.quarantineReason = ""
      Store.quarantineKind = ""
      Store._backendHasAnswered = false
      Store._adoptedFormat = ""
      Store.backend = b

      verify(Store.loaded && !Store.quarantined, "a readable file did not load")
      compare(Store.setSetting("kartBody", 3), false,
              "a store with no way to write said the change was saved")
      verify(Store.quarantined, "a backend that cannot write anything did not say so")
      verify(Store.quarantineReason.indexOf("no save()") >= 0, Store.quarantineReason)
      compare(disk.blob, before)
      compare(disk.writes, 0)
    }

    // --------------------------------------------------------------- D-5
    //
    // `backendFormat()` is read on every flush, so a backend whose protocol
    // moves after the load hands the file layer the other protocol's payload.
    // Measured: a text load, `format` flipped to "object", and the next
    // keystroke wrote a JSON snapshot over the file, which then did not parse
    // as a save, with nothing quarantined.
    function test_48_a_protocol_that_moves_after_the_load_is_refused() {
      var b = { "format": "text" }
      b.load = function () { return disk.blob }
      b.save = function (p) {
        disk.blob = typeof p === "string" ? p : JSON.stringify(p)
        disk.writes += 1
      }
      Store.loaded = false
      Store.quarantined = false
      Store.quarantineReason = ""
      Store.quarantineKind = ""
      Store._backendHasAnswered = false
      Store._adoptedFormat = ""
      Store.backend = b
      verify(Store.loaded && !Store.quarantined, "the text file did not load")
      var before = disk.blob

      b.format = "object"
      compare(Store.setSetting("kartBody", 3), false,
              "a write in a protocol the load did not answer in was reported as saved")
      compare(disk.writes, 0, "a snapshot was written over the child's text file")
      compare(disk.blob, before)
      verify(Store.quarantined)
      verify(suite.onDisk() !== null, "the file no longer parses as a save")
    }

    // --------------------------------------------------- the array door
    //
    // `fileFromObject`'s array check. `typeof [] === "object"`, so without the
    // explicit test a JSON array walks through a guard whose message says it
    // did not: every key reads as undefined, the defaults are adopted, and the
    // next keystroke writes them over the child's file. The check has been in
    // the code, and named in a builder's report as a door it closed, since
    // round 4 -- and an independent mutation run deleted it and the whole suite
    // still passed 42/42 while the file was destroyed.
    function test_49_a_json_array_under_the_object_protocol_is_not_a_save() {
      var arrays = ["[1,2,3]", "[]", "[{\"settings\":{}}]"]
      for (var i = 0; i < arrays.length; i++) {
        var payload = JSON.parse(arrays[i])
        var b = { "format": "object" }
        b.load = function () { return payload }
        b.save = function (o) { disk.blob = JSON.stringify(o); disk.writes += 1 }
        disk.blob = suite.victimText()
        disk.writes = 0
        Store.loaded = false
        Store.quarantined = false
        Store.quarantineReason = ""
        Store.quarantineKind = ""
        Store._backendHasAnswered = false
        Store._adoptedFormat = ""
        Store.backend = b
        suite.assertTheFileSurvived("a JSON array " + arrays[i]
                                    + " under the object protocol")
        verify(Store.quarantineReason.indexOf("not a save object") >= 0,
               Store.quarantineReason)
      }
    }

    // ------------------------------------------- the returning child
    //
    // Every committed commit test starts from `disk.blob = ""`. The single most
    // common real-world path -- a child who has played before, whose file holds
    // a record and forty-eight attempts, running one more race -- was untested,
    // and a mutation that stopped `factHistoryForRace` remembering what it
    // handed out survived the whole suite while silently refusing every race a
    // returning child ran.
    function test_50_a_race_over_a_non_empty_fact_history_banks_and_adds() {
      suite.freshStore()
      var before = suite.progressOnDisk()
      verify(before.records === 1, "the fixture is not a returning child's file")
      verify(before.facts > 0 && before.attempts > 0,
             "the fixture has no fact history to return to")

      var seeded = Store.factHistoryForRace()
      compare(seeded.length, before.facts,
              "the returning child's history did not reach the race")

      var race = suite.playRace(63, "timeTrial", "2-5", seeded)
      var result = Store.commit(race.state, race.timeline)
      compare(result.issues.length, 0, JSON.stringify(result.issues))
      compare(result.factsUpdated, true, "a returning child's race was refused")

      var after = suite.progressOnDisk()
      compare(after.attempts,
              before.attempts + Engine.humanRacer(race.state).attemptCount,
              "the race's answers did not add to the history that was already there")
      verify(after.facts >= before.facts, "the fact history shrank")
      compare(after.records, 1, "the record that was already there is gone")
    }

    // ------------------------------------------- a reset that did not happen
    //
    // The three resets are the one place on this screen where a banner claiming
    // something the file did not do is unrecoverable: the child is told the
    // records are cleared and there is no undo to check it against. `answer()`
    // in ui/Settings.qml promises the banner "reports what happened to the
    // file, not what was asked for", and until this round the resets answered
    // `true` for a write the file layer refused.
    function test_51_a_reset_whose_write_was_refused_says_nothing_was_changed() {
      realDisk.reset(suite.victimText())
      suite.freshFileStore({ "debounced": false })
      var before = realDisk.blob
      verify(Store.loaded && !Store.quarantined, "the file did not load")

      realDisk.writable = false                  // the disk fills up

      settingsProbe.pending = "records"
      settingsProbe.answer(true)

      compare(settingsProbe.bannerText, "NOTHING WAS CHANGED",
              "the screen said the records were cleared over a file that never changed")
      compare(realDisk.blob, before, "the file moved")
      compare(realDisk.writes, 0)
      verify(Store.quarantined)
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
