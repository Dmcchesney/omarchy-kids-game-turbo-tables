// The cross-runtime determinism gate, wired into `npm test`.
//
// The work is in run.mjs, which is also runnable on its own and exits non-zero
// on a mismatch. Here it is wrapped so a machine with no Qt on PATH SKIPS the
// gate loudly rather than failing the suite -- and so the skip is visible in the
// test output, because "unverified" and "verified" must never look the same.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const runner = resolve(import.meta.dirname, "run.mjs");
const qmlOnPath = (spawnSync("sh", ["-c", "command -v qml"], { encoding: "utf8" }).stdout ?? "")
  .trim();

test(
  "bundle-qml: every race vector replays byte-identically through engine/engine.mjs under the QML JavaScript engine",
  { skip: qmlOnPath === "" ? "qml is not on PATH: cross-runtime determinism NOT measured" : false },
  () => {
    // The runner already bounds its own `qml` child; this second bound is for
    // the runner itself, so that no defect anywhere under this test can turn
    // `npm test` into an indefinite hang. "Unverified" must look different from
    // "verified", and a suite that never returns looks like neither.
    const run = spawnSync(process.execPath, [runner], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      timeout: 120000,
      killSignal: "SIGKILL",
    });
    if (run.error !== undefined) {
      assert.fail(
        "the cross-runtime runner did not finish: " +
          run.error.message +
          "\n" +
          (run.stdout ?? "") +
          (run.stderr ?? ""),
      );
    }
    if (run.status !== 0) assert.fail((run.stdout ?? "") + (run.stderr ?? ""));
    assert.match(run.stdout, /byte-identical, and repeatable inside the QML engine\./);
  },
);
