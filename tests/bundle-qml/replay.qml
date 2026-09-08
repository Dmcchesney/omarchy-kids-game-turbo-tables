// Replays every committed race vector through the shipped bundle, inside the
// QML JavaScript engine, and prints the result for the Node runner to diff.
//
// Design, Laps decks presets: "the multiplayer engine must reproduce them byte
// for byte". That claim is about a runtime that is not Node, and this is the
// only place in the repository where the engine leaves V8. It also retires the
// plan's M0 spike, "confirm the esbuild output loads as an ES module in Qt's
// QML engine": it does, as `import "engine.mjs" as Engine`, with no shim and no
// .pragma library fallback.
//
// The runner copies engine.mjs, this file and a generated vector.mjs into a
// temporary directory and runs `qml replay.qml` there, so nothing is written
// into the checkout.
//
//   QT_QPA_PLATFORM=offscreen qml replay.qml
//
// Output, one item per line, each optionally prefixed by Qt's own "qml: ":
//   TTQ VEC <name> <length> <repeatable|REPEAT-DIVERGED>
//   TTQ D <up to 3000 characters of the JSON>
//   TTQ END <name>
//   TTQ DONE <count>

import QtQml
import "engine.mjs" as Engine
import "vector.mjs" as Data

QtObject {
  function replay(vector) {
    var state = Engine.createRace({
      seed: vector.seed,
      preset: vector.preset,
      chosenTables: vector.chosenTables,
      mode: vector.mode,
      streakThreshold: vector.streakThreshold,
      schedule: vector.schedule,
      racers: vector.racers
    });
    var events = [];
    for (var i = 0; i < vector.inputs.length; i++) {
      var result = Engine.step(state, vector.inputs[i].input, vector.inputs[i].at);
      state = result.state;
      for (var e = 0; e < result.events.length; e++) events.push(result.events[e]);
    }
    return JSON.stringify({ events: events, finalState: state });
  }

  // A construct the QML V4 engine rejects is exactly the failure this gate
  // exists to catch, and it arrives as an exception out of `replay()`. Without
  // the try/catch below, that exception escapes `Component.onCompleted`,
  // `Qt.exit(0)` is never reached, the process never exits, and the Node runner
  // waits for a child that will never die. So: catch it, say which vector threw,
  // and exit non-zero. The runner's own `timeout` is the backstop for the case
  // this cannot reach -- a bare infinite loop inside the engine.
  Component.onCompleted: {
    var lines = [];
    var failure = "";
    try {
      for (var v = 0; v < Data.VECTORS.length; v++) {
        var vector = Data.VECTORS[v];
        var json = replay(vector);
        // Determinism inside this runtime too: the same script from a fresh race
        // is the same race here as it is under Node.
        var again = replay(vector);
        lines.push("TTQ VEC " + vector.name + " " + json.length +
                   (json === again ? " repeatable" : " REPEAT-DIVERGED"));
        for (var p = 0; p < json.length; p += 3000) lines.push("TTQ D " + json.substr(p, 3000));
        lines.push("TTQ END " + vector.name);
      }
      lines.push("TTQ DONE " + Data.VECTORS.length);
    } catch (error) {
      var where = typeof vector === "undefined" || vector === null ? "(before the first vector)"
                                                                   : vector.name;
      failure = "TTQ THREW " + where + ": " + error;
      if (error && error.stack) failure += "\n" + error.stack;
    }
    for (var k = 0; k < lines.length; k++) console.log(lines[k]);
    if (failure !== "") {
      console.log(failure);
      Qt.exit(1);
      return;
    }
    Qt.exit(0);
  }
}
