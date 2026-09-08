// Cross-runtime determinism gate: replay every committed race vector through
// engine/engine.mjs under the QML JavaScript engine and diff the result, byte
// for byte, against the same bundle replayed under Node.
//
//   node tests/bundle-qml/run.mjs
//
// Exits 0 when every vector matches, 1 on any mismatch, and 2 when the QML
// runtime is not available (which is an environment failure, not a mismatch;
// pass --skip-if-unavailable to turn that into a 0 for a machine without Qt).
//
// It always exits. An exception inside the replay is caught by replay.qml and
// becomes an exit(1); a child that hangs anyway is killed after QML_TIMEOUT_MS
// and reported as a failure. Round 2's critic injected a construct the QML V4
// engine rejects -- the exact failure this gate exists to catch -- and the
// runner hung for 45 seconds instead of going red.
//
// Design, Laps decks presets: "Seeds and resulting question sequences are
// committed as test vectors, and the multiplayer engine must reproduce them
// byte for byte." Everything else in the suite proves that under Node, which is
// not the runtime the plugin ships into.

import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(import.meta.dirname, "../..");
const skipIfUnavailable = process.argv.includes("--skip-if-unavailable");

function findQml() {
  const found = spawnSync("sh", ["-c", "command -v qml"], { encoding: "utf8" });
  const path = (found.stdout ?? "").trim();
  return path === "" ? null : path;
}

/**
 * How long the `qml` child is allowed to take. The whole replay is around half
 * a second on a warm machine, so this is a hundredfold margin; it exists only so
 * that a child which never exits -- an infinite loop inside the bundle, or an
 * exception that escapes `Component.onCompleted` -- turns this gate red instead
 * of hanging `npm test` forever. Round 2's critic injected exactly that and
 * watched the runner spin for 45 seconds.
 */
const QML_TIMEOUT_MS = 60000;

/** The QML side of the run: returns { name -> json } plus the repeat flags. */
function runUnderQml(qmlBinary, vectors) {
  const workspace = mkdtempSync(join(tmpdir(), "turbo-tables-qml-"));
  try {
    copyFileSync(resolve(root, "engine/engine.mjs"), join(workspace, "engine.mjs"));
    copyFileSync(resolve(import.meta.dirname, "replay.qml"), join(workspace, "replay.qml"));
    writeFileSync(
      join(workspace, "vector.mjs"),
      "export const VECTORS = " + JSON.stringify(vectors) + ";\n",
    );
    const run = spawnSync(qmlBinary, ["replay.qml"], {
      cwd: workspace,
      encoding: "utf8",
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen" },
      maxBuffer: 64 * 1024 * 1024,
      timeout: QML_TIMEOUT_MS,
      killSignal: "SIGKILL",
    });
    const output = (run.stdout ?? "") + (run.stderr ?? "");
    // A timeout is reported as run.error with code ETIMEDOUT, and the child has
    // already been killed. Report it as a failure of this gate rather than
    // letting it escape as an uncaught exception, so the message says what
    // happened and the exit code is still 1.
    const timedOut = run.error !== undefined && run.error.code === "ETIMEDOUT";
    if (run.error !== undefined && !timedOut) throw run.error;
    const replayed = new Map();
    const repeatable = new Map();
    let current = null;
    let buffer = [];
    let done = -1;
    for (const raw of output.split("\n")) {
      const line = raw.startsWith("qml: ") ? raw.slice(5) : raw;
      if (!line.startsWith("TTQ ")) continue;
      const body = line.slice(4);
      if (body.startsWith("VEC ")) {
        const parts = body.slice(4).split(" ");
        current = parts[0];
        repeatable.set(current, parts[2] === "repeatable");
        buffer = [];
      } else if (body.startsWith("D ")) {
        buffer.push(body.slice(2));
      } else if (body.startsWith("END ")) {
        replayed.set(body.slice(4), buffer.join(""));
        current = null;
      } else if (body.startsWith("DONE ")) {
        done = Number(body.slice(5));
      }
    }
    return { replayed, repeatable, done, status: run.status, output, timedOut };
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
}

const qmlBinary = findQml();
if (qmlBinary === null) {
  const message = "qml is not on PATH: cross-runtime determinism was NOT measured";
  if (skipIfUnavailable) {
    console.log("skipped: " + message);
    process.exit(0);
  }
  console.error("failed: " + message);
  process.exit(2);
}

const races = JSON.parse(readFileSync(resolve(root, "vectors/races.json"), "utf8"));
const vectors = races.vectors.map((vector) => ({
  name: vector.name,
  seed: vector.seed,
  preset: vector.preset,
  chosenTables: vector.chosenTables,
  mode: vector.mode,
  streakThreshold: vector.streakThreshold,
  schedule: vector.schedule,
  racers: vector.racers,
  inputs: vector.inputs,
}));

const engine = await import(pathToFileURL(resolve(root, "engine/engine.mjs")).href);

function replayUnderNode(vector) {
  let state = engine.createRace({
    seed: vector.seed,
    preset: vector.preset,
    chosenTables: vector.chosenTables,
    mode: vector.mode,
    streakThreshold: vector.streakThreshold,
    schedule: vector.schedule,
    racers: vector.racers,
  });
  const events = [];
  for (const entry of vector.inputs) {
    const result = engine.step(state, entry.input, entry.at);
    state = result.state;
    for (const event of result.events) events.push(event);
  }
  return JSON.stringify({ events, finalState: state });
}

const { replayed, repeatable, done, status, output, timedOut } = runUnderQml(qmlBinary, vectors);
const version = (spawnSync(qmlBinary, ["--version"], { encoding: "utf8" }).stdout ?? "").trim();

const failures = [];
if (timedOut) {
  failures.push(
    "qml did not exit within " +
      QML_TIMEOUT_MS +
      "ms and was killed: the bundle hangs or throws inside the QML engine",
  );
} else if (status !== 0) {
  failures.push("qml exited " + status);
}
if (done !== vectors.length) {
  failures.push("qml replayed " + done + " vectors, expected " + vectors.length);
}
for (const vector of vectors) {
  const underQml = replayed.get(vector.name);
  const underNode = replayUnderNode(vector);
  if (underQml === undefined) {
    failures.push(vector.name + ": no output from the QML engine");
    continue;
  }
  if (repeatable.get(vector.name) !== true) {
    failures.push(vector.name + ": two replays inside the QML engine disagreed");
  }
  if (underQml !== underNode) {
    let at = 0;
    while (at < underQml.length && at < underNode.length && underQml[at] === underNode[at]) at += 1;
    failures.push(
      vector.name +
        ": diverged at character " +
        at +
        "\n    node: " +
        JSON.stringify(underNode.slice(Math.max(0, at - 60), at + 60)) +
        "\n    qml:  " +
        JSON.stringify(underQml.slice(Math.max(0, at - 60), at + 60)),
    );
    continue;
  }
  console.log(
    "  " +
      vector.name.padEnd(28) +
      " " +
      String(vector.inputs.length).padStart(4) +
      " inputs  " +
      String(underNode.length).padStart(7) +
      " bytes  byte-identical",
  );
}

if (failures.length > 0) {
  console.error("\nCross-runtime replay FAILED (" + version + "):");
  for (const failure of failures) console.error("  " + failure);
  if (status !== 0 || timedOut) console.error(output.slice(0, 4000));
  process.exit(1);
}

console.log(
  "\nengine/engine.mjs replayed " +
    vectors.length +
    " race vectors under " +
    version +
    " and under Node " +
    process.version +
    ": byte-identical, and repeatable inside the QML engine.",
);
