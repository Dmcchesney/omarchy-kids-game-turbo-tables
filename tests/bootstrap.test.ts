import { test } from "node:test";
import assert from "node:assert/strict";
import { repositoryBootstrap } from "../src/engine/index.ts";

test("repository bootstrap owns the settled plugin id", () => {
  assert.deepEqual({ ...repositoryBootstrap }, {
    pluginId: "io.github.dmcchesney.turbo-tables-solo",
    schemaVersion: 1,
  });
});
