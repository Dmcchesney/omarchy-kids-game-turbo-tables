import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "../..");
const marketplace = resolve(root, "../omarchy-plugin-marketplace");
const scanner = resolve(marketplace, "scripts/security-baseline.mjs");
const manifest = JSON.parse(await readFile(resolve(root, "manifest.json"), "utf8"));
const git = (...args: string[]) => {
  const result = spawnSync("git", args, { cwd: root, encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr.trim() || "git failed");
  return result.stdout.trim();
};

let repoUrl = git("remote", "get-url", "origin");
repoUrl = repoUrl
  .replace(/^git@github\.com:/, "https://github.com/")
  .replace(/\.git$/, "");
const commitSha = git("rev-parse", "HEAD");
const entryPoints = Object.values(manifest.entryPoints);
const workspace = await mkdtemp(resolve(tmpdir(), "turbo-tables-scan-"));
const metadataPath = resolve(workspace, "metadata.json");
const jsonPath = resolve(workspace, "result.json");

await writeFile(metadataPath, JSON.stringify({
  schemaVersion: 1,
  context: "submission",
  repoUrl,
  commitSha,
  pluginIds: [manifest.id],
  listedPlugins: [{ pluginId: manifest.id }],
  entryPoints,
}, null, 2));

try {
  const result = spawnSync(process.execPath, [
    scanner,
    `--metadata=${metadataPath}`,
    `--json=${jsonPath}`,
  ], {
    cwd: marketplace,
    encoding: "utf8",
    stdio: ["ignore", "inherit", "inherit"],
  });
  process.exitCode = result.status ?? 2;
} finally {
  await rm(workspace, { recursive: true, force: true });
}
