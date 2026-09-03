import QtQuick
import QtTest
import Quickshell.Io
import "../../shell" as Shell

// shell/FileStore.qml -- the only code in the repository that touches a disk,
// and until this file the only code in the repository with no automated test at
// all.
//
// It could not have one: it imports Quickshell, which is not on the machine the
// suite runs on, so every claim about it was a run in the Omarchy VM or a
// reading of the source. That is not a small gap. It is where the class of
// defect this file now guards lived undetected for four rounds -- not the load
// side, which five rounds of VM attacks could not break, but what happens
// *after* the file layer correctly refuses to write:
//
//   the way out of a read-side quarantine was inert. `_everLoaded` is false
//   when the file could not be read, nothing in the session ever set it, so
//   `save()` refused with "before the file had been read" for the rest of the
//   session and every session after it -- while ui/Settings.qml said
//   "A NEW SAVE FILE HAS BEEN STARTED". A corrupt garage.json on a Kids-Mode
//   machine was permanent, and the screen said it was fixed.
//
//   a concurrent writer's save was discarded. The re-proof before a write was
//   worn only over an "absent" verdict; a "present" one was trusted with no
//   second look. A parent hand-restoring garage.json while the shell runs --
//   the only remedy the first defect leaves them -- lost it on the child's next
//   keystroke, which is what made the first defect unrecoverable.
//
// `tests/qml-shell/` answers this file's questions the way its own header
// records Quickshell 0.3.1 answering them in the VM. It models the shell, never
// the plugin: no rule `shell/FileStore.qml` keeps is restated there, and where
// the model is wrong about Quickshell these tests are wrong with it. It is not
// a replacement for a VM run and does not claim to be one; it is the difference
// between this file being checked on every run and being checked when a VM
// happens to boot.
//
// WHY THIS SPEC IS NOT IN `tests/qml/`. It imports `Quickshell.Io`, and the
// suite in `tests/qml/` is run on a Mac where Quickshell does not exist -- a
// spec importing a shell module there fails to compile and takes the whole run
// red. It lives beside the model it needs instead, and is run separately:
//
//   qmltestrunner -input tests/qml       -import ui -import dev/imports
//   qmltestrunner -input tests/qml-shell -import ui -import tests/qml-shell
//
// The second line scans this directory for `tst_*.qml` and finds only this
// file; `Quickshell/` beside it holds the model and is a QML module, not a
// spec. Nothing under `tests/qml/` imports a shell module, and that is the
// property that keeps the first line green on a machine with no Quickshell.
Item {
  id: root
  width: 200
  height: 200

  readonly property string dataDir: "/home/kid/.local/share/turbo-tables-solo"
  readonly property string savePath: dataDir + "/garage.json"

  TestCase {
    id: suite
    name: "FileStore"
    when: windowShown

    property var store: null
    property var refusals: []
    property int wroteCount: 0

    // A real save file's worth of bytes. The engine is not imported here on
    // purpose: this file is about whether a byte may be replaced, and nothing
    // in it may depend on what the byte means.
    readonly property string aSave:
        "{\n  \"version\": 1,\n  \"settings\": {},\n  \"records\": {\"a\": 1},\n"
        + "  \"facts\": [1, 2, 3]\n}\n"
    readonly property string anotherSave:
        "{\n  \"version\": 1,\n  \"settings\": {},\n  \"records\": {\"b\": 2},\n"
        + "  \"facts\": [4, 5, 6, 7]\n}\n"

    function init() {
      FakeFs.clear()
      suite.refusals = []
      suite.wroteCount = 0
    }

    function cleanup() {
      if (suite.store !== null) {
        suite.store.destroy()
        suite.store = null
      }
    }

    // A store over the modelled disk, with its two signals collected the way
    // TurboTables.qml collects them. `debounceMs: 0` is not a shortcut around
    // the debounce: every test below calls `flushNow()` explicitly, so what is
    // asserted is a write that has actually happened rather than one a timer
    // might get to.
    function aStore() {
      var made = storeComponent.createObject(root, { "path": root.savePath })
      verify(made !== null, "the file store did not instantiate")
      made.writeFailed.connect(function (reason) { suite.refusals.push(reason) })
      made.wrote.connect(function () { suite.wroteCount += 1 })
      suite.store = made
      return made
    }

    function withASaveOnDisk() {
      FakeFs.dirs(root.dataDir)
      FakeFs.file(root.savePath, suite.aSave)
    }

    // ===================================================================
    // 1. THE THREE OUTCOMES OF A READ, AND NO FOURTH
    // ===================================================================

    function test_01_a_readable_save_is_read() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      compare(store.load(), suite.aSave)
      compare(store.verdict, "present")
      compare(store.everLoaded, true)
      compare(store.absenceProven, false)
    }

    function test_02_a_proved_absence_is_null_and_only_then() {
      FakeFs.dirs(root.dataDir)
      var store = suite.aStore()
      compare(store.load(), null)
      compare(store.verdict, "absent")
      compare(store.absenceProven, true)
    }

    // The measurement the whole file is built against: a file behind a
    // directory this process cannot walk into arrives as FileNotFound, exactly
    // like a file that is not there. It may never be read as an absence.
    function test_03_a_shut_directory_is_not_an_absence() {
      suite.withASaveOnDisk()
      FakeFs.chmod(root.dataDir, { "traversable": false, "readable": false })
      var store = suite.aStore()
      var threw = false
      try { store.load() } catch (error) { threw = true }
      verify(threw, "a file behind a shut directory was answered for")
      compare(store.absenceProven, false)
      compare(FakeFs.textAt(root.savePath), suite.aSave, "the file did not survive the read")
    }

    // chmod 666: readable, not traversable. The awkward mode that tells a real
    // traversability proof from a plausible one.
    function test_04_a_readable_untraversable_directory_does_not_prove_absence() {
      FakeFs.dirs(root.dataDir)
      FakeFs.chmod(root.dataDir, { "traversable": false, "readable": true })
      var store = suite.aStore()
      var threw = false
      try { store.load() } catch (error) { threw = true }
      verify(threw, "an untraversable directory was read as an empty one")
      compare(store.absenceProven, false)
    }

    // chmod 111: traversable, unreadable. Absence through it is real.
    function test_05_a_traversable_unreadable_directory_can_prove_absence() {
      FakeFs.dirs(root.dataDir)
      FakeFs.chmod(root.dataDir, { "traversable": true, "readable": false })
      var store = suite.aStore()
      compare(store.load(), null)
      compare(store.absenceProven, true)
    }

    function test_06_a_file_that_cannot_be_read_is_a_throw_not_an_absence() {
      suite.withASaveOnDisk()
      FakeFs.chmod(root.savePath, { "readable": false })
      var store = suite.aStore()
      var threw = false
      try { store.load() } catch (error) { threw = true }
      verify(threw, "an unreadable file was answered for")
      compare(store.verdict, "unreadable")
      compare(store.everLoaded, false)
    }

    // ===================================================================
    // 2. THE WRITE SIDE'S REFUSALS
    // ===================================================================

    // Refusal 1, which is also the state a read-side quarantine leaves this
    // object in for the whole session.
    function test_07_nothing_is_written_before_a_read_has_answered() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.save(suite.anotherSave)
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), suite.aSave, "the child's file was overwritten")
      compare(suite.refusals.length, 1)
      verify(suite.refusals[0].indexOf("before the file had been read") >= 0, suite.refusals[0])
    }

    // Refusal 2.
    function test_08_nothing_is_written_over_an_unreadable_file() {
      suite.withASaveOnDisk()
      FakeFs.chmod(root.savePath, { "readable": false })
      var store = suite.aStore()
      try { store.load() } catch (error) { /* expected */ }
      store.save(suite.anotherSave)
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), suite.aSave)
      compare(store.writable, false)
    }

    // Refusal 3.
    function test_09_nothing_blank_is_ever_written() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()
      store.save("   \n  ")
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), suite.aSave)
      verify(suite.refusals[0].indexOf("empty") >= 0, suite.refusals[0])
    }

    // The absence re-proof: proved absent at start, a real save appears, then a
    // write. The save that appeared is a save, not an empty slot.
    function test_10_a_save_that_appears_after_a_proved_absence_is_not_written_over() {
      FakeFs.dirs(root.dataDir)
      var store = suite.aStore()
      compare(store.load(), null)

      FakeFs.file(root.savePath, suite.aSave)      // somebody restores a save
      store.save(suite.anotherSave)
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.aSave, "the restored save was overwritten")
      compare(store.writable, false)
      verify(suite.refusals[0].indexOf("readable now") >= 0, suite.refusals[0])
    }

    // ===================================================================
    // 3. REFUSAL 4 -- SOMEBODY ELSE'S BYTES
    //
    // The defect a seam critic reproduced in the VM: the re-proof was worn only
    // over an "absent" verdict, so a file read at shell start and replaced by
    // another writer an hour later was overwritten on the child's next
    // keystroke with no probe, no refusal and no message.
    // ===================================================================

    function test_11_a_file_that_changed_on_disk_is_never_overwritten() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      compare(store.load(), suite.aSave)

      // A parent puts a different save file back while the shell is running.
      FakeFs.file(root.savePath, suite.anotherSave)

      store.save("{\"this\": \"session\"}\n")
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.anotherSave,
              "the other writer's save was silently discarded")
      compare(store.writable, false, "the session went on believing it can write")
      compare(suite.refusals.length, 1, "the refusal was silent")
      verify(suite.refusals[0].indexOf("changed on disk") >= 0, suite.refusals[0])
    }

    // The same rule after this object has written the file itself, which is the
    // path the absence re-proof retires and nothing else covered.
    function test_12_a_fresh_install_that_wrote_once_still_looks_before_writing_again() {
      FakeFs.dirs(root.dataDir)
      var store = suite.aStore()
      compare(store.load(), null)

      store.save(suite.aSave)
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), suite.aSave, "the fresh install wrote nothing")

      FakeFs.file(root.savePath, suite.anotherSave)   // somebody else writes
      store.save("{\"this\": \"session\"}\n")
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.anotherSave,
              "the second writer's save was overwritten")
      compare(store.writable, false)
    }

    // Its own writes are not somebody else's. A session that writes twice must
    // not refuse itself, or the guard costs the child every save after the
    // first.
    function test_13_this_sessions_own_writes_are_not_a_stranger() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()
      for (var n = 0; n < 4; n++) {
        store.save("{\"n\": " + n + "}\n")
        store.flushNow()
      }
      compare(FakeFs.textAt(root.savePath), "{\"n\": 3}\n", "the session refused its own writes")
      compare(store.writable, true)
      compare(suite.refusals.length, 0, JSON.stringify(suite.refusals))
    }

    // A file that goes away is not a file that changed: there is nothing on
    // that path to destroy, so the write may land -- but only once its absence
    // proves out, which is the same standard everything else in this file is
    // held to.
    function test_14_a_save_deleted_underneath_the_session_may_be_written_again() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()

      FakeFs.remove(root.savePath)                 // a parent deletes it
      store.save(suite.anotherSave)
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.anotherSave, "the session stopped saving")
      compare(store.writable, true)
    }

    function test_15_a_save_that_became_unreadable_is_not_written_over() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()

      FakeFs.chmod(root.savePath, { "readable": false })
      store.save(suite.anotherSave)
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.aSave)
      compare(store.writable, false)
      verify(suite.refusals[0].indexOf("could not be re-read") >= 0, suite.refusals[0])
    }

    // ===================================================================
    // 4. THE WAY OUT
    //
    // The worst defect of the round: refusals 1 and 2 have no expiry, so the
    // one action the product offers a family whose save file cannot be read
    // cleared a flag one layer up and was refused down here -- silently, while
    // the screen said a new save file had been started.
    // ===================================================================

    function test_16_a_read_side_refusal_has_no_way_out_without_an_explicit_one() {
      suite.withASaveOnDisk()
      FakeFs.chmod(root.savePath, { "readable": false })
      var store = suite.aStore()
      try { store.load() } catch (error) { /* expected */ }

      // What the wiring used to do on its own, and all it could do: lift the
      // latch a failed write sets. It is not the latch that is holding.
      store.allowWritingAgain()
      store.save(suite.anotherSave)
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.aSave,
              "allowWritingAgain was enough, so this test is asserting the wrong thing")
      compare(store.writable, false)
    }

    function test_17_replacing_an_unreadable_file_writes_and_hands_the_session_back() {
      suite.withASaveOnDisk()
      FakeFs.chmod(root.savePath, { "readable": false })
      var store = suite.aStore()
      try { store.load() } catch (error) { /* expected */ }
      compare(store.everLoaded, false)
      compare(store.verdict, "unreadable")

      // The decision a person made in the Confirm dialog, and nothing else.
      store.replaceUnreadableFile()
      store.save(suite.anotherSave)
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.anotherSave, "the way out wrote nothing")
      compare(store.writable, true)
      compare(suite.refusals.length, 0, JSON.stringify(suite.refusals))
      compare(suite.wroteCount, 1)

      // And it is one overwrite, not a licence: the session goes back to the
      // ordinary rules over the bytes it now owns.
      compare(store.replaceAuthorised, false, "the authorisation outlived the write")
      store.save("{\"later\": true}\n")
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), "{\"later\": true}\n",
              "the session did not keep saving after the replacement")

      FakeFs.file(root.savePath, suite.aSave)      // and refusal 4 is back on
      store.save("{\"later\": 2}\n")
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), suite.aSave,
              "the replacement left the session able to overwrite a stranger's file")
      compare(store.writable, false)
    }

    // The way out over a file that could not be read AND cannot be written.
    // Nothing lands, and it says so rather than latching quietly.
    function test_18_a_replacement_that_cannot_be_written_is_reported() {
      suite.withASaveOnDisk()
      FakeFs.chmod(root.savePath, { "readable": false, "writable": false })
      var store = suite.aStore()
      try { store.load() } catch (error) { /* expected */ }

      store.replaceUnreadableFile()
      store.save(suite.anotherSave)
      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.aSave)
      compare(store.writable, false)
      compare(suite.refusals.length, 1, "a failed replacement said nothing")
      compare(suite.wroteCount, 0)
    }

    // An authorisation that was never spent does not outlive the question it
    // answered. The person was asked about a file nothing could see; a read
    // that comes back is a different file to be asked about, and an
    // authorisation left standing would let one write past refusal 4 with
    // nobody having decided that.
    // An authorisation that was never spent does not outlive the question it
    // answered.
    //
    // The reachable shape of that: the quarantine was `ui/Store.qml`'s, over a
    // file this layer read perfectly well but whose *payload* it would not
    // touch. The child confirms, this object is authorised, the write fails on
    // a full disk -- and the authorisation is still standing. If a later read
    // then answers and clears the quarantine, `allowWritingAgain()` lifts the
    // write latch and the next write would go past refusal 4 with nobody having
    // decided that. A read that came back is a new question, so it ends the old
    // answer.
    function test_19_a_read_that_comes_back_supersedes_an_unspent_authorisation() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      compare(store.load(), suite.aSave)

      store.replaceUnreadableFile()
      compare(store.replaceAuthorised, true, "the authorisation was not recorded")

      compare(store.load(), suite.aSave)                  // the read is asked again
      compare(store.replaceAuthorised, false,
              "an authorisation to overwrite outlived the read that answered")

      FakeFs.file(root.savePath, suite.anotherSave)       // and refusal 4 stands
      store.save("{\"this\": \"session\"}\n")
      store.flushNow()
      compare(FakeFs.textAt(root.savePath), suite.anotherSave)
      compare(store.writable, false)
    }

    // The read-side refusals stand for everything that did not go through the
    // dialog. An authorisation is one write's worth of exception, not a mode.
    function test_20_nothing_else_stands_the_read_side_refusals_down() {
      FakeFs.dirs(root.dataDir)
      FakeFs.file(root.savePath, suite.aSave)
      FakeFs.chmod(root.savePath, { "readable": false })
      var store = suite.aStore()
      try { store.load() } catch (error) { /* expected */ }
      compare(store.replaceAuthorised, false)
      for (var n = 0; n < 3; n++) {
        store.save(suite.anotherSave)
        store.flushNow()
      }
      compare(FakeFs.textAt(root.savePath), suite.aSave)
    }

    // ===================================================================
    // 5. THE PATH, AND TEARDOWN
    // ===================================================================

    // A new path is a new file and nothing is known about it. Without this the
    // verdict is sticky across the move and one file's contents are written to
    // another's name.
    function test_21_moving_the_path_forgets_everything_about_the_old_one() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()
      store.replaceUnreadableFile()

      store.path = root.dataDir + "/somewhere-else.json"
      compare(store.verdict, "unknown")
      compare(store.everLoaded, false)
      compare(store.replaceAuthorised, false,
              "an authorisation to replace one file travelled to another")

      store.save(suite.anotherSave)
      store.flushNow()
      compare(FakeFs.textAt(root.dataDir + "/somewhere-else.json"), null,
              "a file was written at a path that had never been read")
      compare(FakeFs.textAt(root.savePath), suite.aSave)
    }

    // `Component.onDestruction` -> `flushNow()` -> `writeNow()` -> `stopWriting()`
    // reaches a `debounce.stop()` on a child that may already be gone. The guard
    // `flushNow` was given in an earlier round was not given to the other caller
    // in the same file, and a critic could only find that by reading: the
    // teardown ordering it needs could not be forced in the VM.
    //
    // It does not have to be forced. The state is "this object's `debounce` is
    // gone while a write is still being decided", and `debounce` is an ordinary
    // property, so a test can put the object in that state directly and take
    // the same path through it. Reproducing the state beats reproducing the
    // race, and a defect nobody can reproduce is a defect nobody can guard.
    function test_22_stop_writing_survives_a_debounce_that_is_already_gone() {
        suite.withASaveOnDisk()
        var store = suite.aStore()
        store.load()
        store.save(suite.anotherSave)              // something is pending
        store.debounce = null                      // the teardown, held still
        FakeFs.chmod(root.dataDir, { "writable": false })
        FakeFs.chmod(root.savePath, { "writable": false })

        // flushNow -> writeNow -> the write fails -> stopWriting -> debounce.stop()
        store.flushNow()

        compare(store.writable, false, "the failed write did not stop the writing")
        compare(FakeFs.textAt(root.savePath), suite.aSave)
        compare(suite.refusals.length, 1, "the failure was not reported")
    }

    // Refusal 4 takes a probe before every write, and the probe is built from
    // this object's own child component -- which, on the teardown path, may be
    // gone before the write is decided. The same shape as the `debounce` guard
    // above, introduced by the same fix, and the same cost if it is missed. It
    // is put in the state directly for the same reason.
    //
    // The answer has to be a refusal: "I could not build a probe" is silence,
    // and silence is not a verdict this file may write over.
    function test_23_a_write_that_cannot_be_probed_is_refused_not_thrown() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()
      store.save(suite.anotherSave)
      store._probeComponent = null

      store.flushNow()

      compare(FakeFs.textAt(root.savePath), suite.aSave,
              "a write nothing could check landed anyway")
      compare(store.writable, false)
      compare(suite.refusals.length, 1, "the refusal was silent")
    }

    // And the same path through a real teardown, which is the one that happens.
    function test_24_a_teardown_with_a_failing_write_pending_does_not_throw() {
      suite.withASaveOnDisk()
      var store = suite.aStore()
      store.load()
      FakeFs.chmod(root.dataDir, { "writable": false })
      FakeFs.chmod(root.savePath, { "writable": false })
      store.save(suite.anotherSave)

      store.destroy()
      suite.store = null
      wait(50)
      compare(FakeFs.textAt(root.savePath), suite.aSave)
    }

    // The design's Data row, built from the environment rather than hard-coded.
    function test_25_the_path_is_the_designs_data_row() {
      var store = storeComponent.createObject(root)
      suite.store = store
      compare(store.path, "/home/kid/.local/share/turbo-tables-solo/garage.json")
    }
  }

  Component {
    id: storeComponent
    Shell.FileStore {
      debounceMs: 0
    }
  }
}
