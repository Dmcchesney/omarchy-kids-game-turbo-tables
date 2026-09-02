import { describe, expect, it } from "vitest";
import { repositoryBootstrap } from "../src/engine/index.ts";

describe("repository bootstrap", () => {
  it("owns the settled plugin id", () => {
    expect(repositoryBootstrap).toEqual({
      pluginId: "io.github.dmcchesney.turbo-tables-solo",
      schemaVersion: 1,
    });
  });
});
