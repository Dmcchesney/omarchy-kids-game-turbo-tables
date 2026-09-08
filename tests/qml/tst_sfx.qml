import QtQuick
import QtTest
import "../../ui"
import "../../ui/parts"

// PIECE 6, M6'. Sound, end to end, in the only terms a machine can check.
//
// ---------------------------------------------------------------------------
// WHAT THIS FILE IS NOT
// ---------------------------------------------------------------------------
//
// It is not evidence that the game sounds right. NOBODY IN THE BUILD LOOP HAS
// HEARD ANY OF THESE FIFTEEN FILES, this test cannot hear one, and no test in
// this repository can. `npm run check:sfx` proves each WAV is PCM of the
// declared format, length and hash; `tests/qml/tst_trackview_fx.qml` proves the
// right cue fires on the right beat of each card; this file proves the four
// things left between those two and a speaker:
//
//   1. every cue in the table resolves to a URL that names its own file;
//   2. the cue's URL -- not its name -- is what crosses the seam;
//   3. the real `shell/AudioLoader.qml`, with the real `shell/SoundBank.qml`
//      behind it, loads every one of those URLs, reports them Ready, and
//      reports a sound PLAYING when a cue is played;
//   4. the three ways it can go quiet all work: the child's `sound` setting,
//      the loader's own `enabled`, and having no bank at all -- the last being
//      the branch a machine without Qt Multimedia takes, with the one caveat
//      written out at that case.
//
// EVERY EFFECT IN THIS FILE IS PLAYED AT VOLUME ZERO. The build machine is the
// maintainer's own, he works at it while the loop runs, and a test suite is not
// entitled to make a noise on it. Volume zero still opens the device, still
// loads the sample and still reports `playing`, so nothing checked here is
// weakened by it -- and nothing here would have told us how it sounds anyway.
Item {
  id: root
  width: 320
  height: 240

  // The seam's other side, for the cases that do not want a real device: it
  // records the URL it was handed and nothing else.
  QtObject {
    id: recorder
    property var urls: []
    function play(url) {
      var next = recorder.urls.slice()
      next.push(String(url))
      recorder.urls = next
      return true
    }
    function clear() { recorder.urls = [] }
  }

  // The real loader, with its real default bank. `asynchronous: false` so the
  // component is there the moment the test looks; the bank's own `Loader` is
  // asynchronous inside it, which is why `readyLoader()` waits below.
  Loader {
    id: audioHost
    asynchronous: false
    source: "../../shell/AudioLoader.qml"
    onLoaded: {
      item.volume = 0
      item.sources = Sfx.sources
    }
  }

  // A loader told not to build a bank at all. Every function takes the same
  // branch here that it takes on a machine with no Qt Multimedia; what differs
  // is only the line `unavailableReason` prints. See the note on that case.
  Loader {
    id: banklessHost
    asynchronous: false
    source: "../../shell/AudioLoader.qml"
    onLoaded: {
      item.volume = 0
      item.bankWanted = false
    }
  }

  TestCase {
    id: testCase
    name: "Sfx"
    when: windowShown

    property var wasVoice: null
    property bool wasSound: true

    function initTestCase() {
      testCase.wasVoice = Sfx.voice
      testCase.wasSound = Store.setting("sound") !== false
    }

    // The singleton outlives this file: every later test in the run reads the
    // same `Sfx` and the same `Store`, so both go back exactly as they were.
    function cleanupTestCase() {
      Sfx.voice = testCase.wasVoice
      Store.setSetting("sound", testCase.wasSound)
      if (audioHost.item)
        audioHost.item.stopAll()
    }

    function init() {
      recorder.clear()
      Store.setSetting("sound", true)
      Sfx.voice = null
      // `lastCue` is a singleton's, so it carries between cases in whatever
      // order the runner picks. Clearing it here is what makes "the cue did not
      // move" mean anything below.
      Sfx.clearLog()
    }

    function cleanup() {
      Sfx.voice = null
      Store.setSetting("sound", true)
    }

    /** The bank loads its WAVs asynchronously. Wait for the loader to say it is
        available and for every voice to be Ready, rather than for a time. */
    function readyLoader() {
      verify(audioHost.item !== null, "shell/AudioLoader.qml loaded")
      tryVerify(function () { return audioHost.item.available }, 5000,
                "the default bank loads: " + (audioHost.item ? audioHost.item.unavailableReason : ""))
      var bank = audioHost.item.bankItem
      tryVerify(function () { return bank.readyVoices() === bank.pool.count }, 5000,
                "every voice loads its WAV")
      return audioHost.item
    }

    // ---------------------------------------------------------------- 1
    function test_every_cue_resolves_to_its_own_file() {
      var cues = Object.keys(Sfx.cues)
      verify(cues.length > 0, "the cue table is not empty")
      compare(Sfx.sources.length, cues.length,
              "one source URL per cue, derived from the table and not listed twice")
      for (var i = 0; i < cues.length; i++) {
        var url = Sfx.url(cues[i])
        verify(String(url).indexOf("/" + Sfx.cues[cues[i]] + ".wav") > 0,
               "the cue " + cues[i] + " resolves to " + Sfx.cues[cues[i]] + ".wav, not " + url)
        verify(Sfx.sources.indexOf(url) >= 0, "and that URL is in Sfx.sources")
      }
    }

    // ---------------------------------------------------------------- 2
    function test_the_seam_is_handed_the_url_and_not_the_cue_name() {
      Sfx.voice = recorder
      var cues = Object.keys(Sfx.cues)
      for (var i = 0; i < cues.length; i++)
        verify(Sfx.play(cues[i]), "play(" + cues[i] + ") reached the seam")
      compare(recorder.urls.length, cues.length, "one call per cue")
      for (var j = 0; j < cues.length; j++)
        compare(recorder.urls[j], String(Sfx.url(cues[j])),
                "the seam was handed " + cues[j] + "'s URL")
    }

    function test_an_unknown_cue_never_reaches_the_seam() {
      Sfx.voice = recorder
      verify(!Sfx.play("no-such-cue"), "an unknown cue answers false")
      compare(recorder.urls.length, 0, "and nothing was played")
      compare(Sfx.lastCue, "", "and lastCue did not move, so a typo is findable")
    }

    // ---------------------------------------------------------------- 4a
    function test_the_sound_setting_silences_the_seam() {
      Sfx.voice = recorder
      Store.setSetting("sound", false)
      verify(!Sfx.play("nitro"), "with sound off, play() answers false")
      compare(recorder.urls.length, 0, "and nothing crossed the seam")
      compare(Sfx.lastCue, "nitro",
              "while the routing is still recorded, so the wiring stays checkable either way")

      Store.setSetting("sound", true)
      verify(Sfx.play("nitro"), "and switching it back on lets the same cue through")
      compare(recorder.urls.length, 1, "exactly once")
    }

    // ---------------------------------------------------------------- 3
    function test_the_real_bank_holds_every_cue_ready() {
      var audio = readyLoader()
      var bank = audio.bankItem
      compare(bank.pool.count, Sfx.sources.length * bank.voices,
              "one pool slot per cue per voice")
      compare(bank.readyVoices(), bank.pool.count,
              "Qt loaded every WAV in the bank and reports it Ready")
      compare(audio.unavailableReason, "", "and the loader has nothing to complain about")
    }

    function test_playing_a_cue_through_the_real_bank_starts_a_sound() {
      var audio = readyLoader()
      var bank = audio.bankItem
      bank.stopAll()
      compare(bank.playingVoices(), 0, "nothing is sounding to begin with")

      Sfx.voice = audio
      var cues = Object.keys(Sfx.cues)
      for (var i = 0; i < cues.length; i++)
        verify(audio.play(Sfx.url(cues[i])),
               "the bank accepted " + cues[i] + " (" + Sfx.url(cues[i]) + ")")
      verify(bank.playingVoices() > 0,
             "and Qt reports a sound playing -- which is as close to hearing as this"
             + " repository gets; nobody has listened to one of them")
      bank.stopAll()
      compare(bank.playingVoices(), 0, "stopAll() silences every voice")
    }

    function test_a_cue_can_overlap_itself_three_times() {
      // Design v4, Oil Slick: "splat, then three squeals staggered by 120", and
      // `ui/TrackView.qml` asks for `squeal` three times. One SoundEffect would
      // restart rather than layer, so three would be one.
      var audio = readyLoader()
      var bank = audio.bankItem
      bank.stopAll()
      for (var i = 0; i < 3; i++)
        verify(audio.play(Sfx.url("squeal")), "squeal " + (i + 1) + " was accepted")
      compare(bank.playingVoices(), 3, "three voices of the same cue sound at once")
      bank.stopAll()
    }

    function test_a_url_the_bank_does_not_hold_is_refused() {
      var audio = readyLoader()
      verify(!audio.play(Theme.sfxRoot + "not-a-cue.wav"),
             "a URL that is not in the bank answers false rather than playing silence")
    }

    // ---------------------------------------------------------------- 4b
    function test_switching_sound_off_stops_the_real_loader() {
      var audio = readyLoader()
      var bank = audio.bankItem
      bank.stopAll()
      verify(audio.play(Sfx.url("turbo")), "sound is on, so the cue plays")
      audio.enabled = false
      compare(bank.playingVoices(), 0, "switching sound off stops what was sounding")
      verify(!audio.play(Sfx.url("turbo")), "and refuses the next cue")
      audio.enabled = true
      verify(audio.play(Sfx.url("turbo")), "and switching it back on plays again")
      bank.stopAll()
    }

    // ---------------------------------------------------------------- 4c
    //
    // NO BANK, which is the branch a machine without Qt Multimedia takes.
    //
    // What this case can and cannot be. A machine without Qt Multimedia cannot
    // compile `shell/SoundBank.qml` at all, and a component that will not
    // compile reaches the loader as `Loader.Error`. That cannot be induced from
    // inside this process: Qt Multimedia is installed on every machine this
    // suite runs on, and Qt 6 resolves an installed library import ahead of
    // every import path, so the import cannot be made to fail. The bank is also
    // named literally in the loader now -- `check:readme` requires it -- so it
    // cannot be pointed at a broken component either.
    //
    // So this case walks the OTHER way to have no bank, which is the same
    // branch of `available`, `play`, `stop` and `stopAll` and differs only in
    // the line `unavailableReason` prints. The real `Loader.Error` path is run
    // in piece 6's evidence, by a byte-identical copy of `shell/AudioLoader.qml`
    // placed beside a copy of `shell/SoundBank.qml` whose one difference is an
    // import that names a module that is not installed.
    function test_no_bank_leaves_the_game_silent() {
      verify(banklessHost.item !== null, "the loader itself still loads")
      var audio = banklessHost.item
      verify(!audio.available, "with no bank, the loader is not available")
      compare(audio.unavailableReason, "no sound bank is installed",
              "and says so in one line a parent could read")
      compare(audio.bankItem, null, "no bank object exists at all")
      verify(!audio.play(Sfx.url("nitro")), "play() answers false")
      verify(!audio.stop(Sfx.url("nitro")), "stop() answers false")
      verify(!audio.stopAll(), "stopAll() answers false")

      // And the game on the other side of the seam does not notice. `Sfx.play`
      // reports that the cue was ROUTED, which it was; what the seam did with
      // it is the seam's business, and a screen calling this gets no error and
      // no exception whichever way it went.
      Sfx.voice = audio
      verify(Sfx.play("nitro"), "Sfx.play() routes the cue and throws nothing")
      compare(Sfx.lastCue, "nitro", "and the routing is recorded exactly as when sound works")
    }
  }
}
