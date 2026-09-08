// Runs the marketplace's own security-baseline rules against this repository.
//
// What it scans, and why that matters
// -----------------------------------
// The marketplace scanner reads a repository through the GitHub API: it asks
// for a commit, walks that commit's tree, and pulls each blob from
// raw.githubusercontent.com. Pointed at GitHub it therefore reports on the
// last commit that was *pushed*, which says nothing about the work sitting in
// the working tree. A rule of "the scanner reports passed on every commit"
// cannot be enforced by a check that never sees the commit being prepared.
//
// So by default this tool hands the scanner the actual working tree. The
// analysis is the marketplace's, unmodified and imported from a pinned
// checkout; only the transport is replaced. A small fetch implementation
// answers the three API endpoints and the raw-blob URLs from files on disk,
// enumerated exactly the way git sees them:
//
//     git ls-files --cached --others --exclude-standard
//
// which is tracked files plus new files that are not ignored, each read from
// disk, so uncommitted edits, additions and mode changes are all in scope.
// The commit identity handed to the scanner is a content digest of that file
// set, not a git commit; it is labelled as such in the output.
//
// `npm run scan -- --remote` runs the unmodified remote path instead, against
// HEAD as GitHub has it, which is what the marketplace itself will do at
// submission time. That is the check to run once the submission commit is
// pushed; the default is the check to run before every commit.

import { createHash } from "node:crypto";
import { access, lstat, readFile, readlink } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const root = resolve(import.meta.dirname, "../..");
const marketplace = resolve(
  process.env.TURBO_TABLES_MARKETPLACE ?? resolve(root, "../omarchy-plugin-marketplace"),
);
const remote = process.argv.includes("--remote");

const scannerModule = resolve(marketplace, "scripts/security-baseline-scanner.mjs");
const reportModule = resolve(marketplace, "scripts/security-baseline-report.mjs");
const policyModule = resolve(marketplace, "scripts/security-baseline-policy.mjs");

type Blob = { path: string; mode: string; size: number; sha: string; bytes: Buffer };

function git(...args: string[]): string {
  const result = spawnSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(result.stderr.trim() || `git ${args[0]} failed`);
  return result.stdout;
}

function repositoryUrl(): string {
  return git("remote", "get-url", "origin")
    .trim()
    .replace(/^git@github\.com:/, "https://github.com/")
    .replace(/\.git$/, "");
}

/**
 * Files the index still carries that are gone from the working tree. The
 * working-tree scan cannot see them -- `lstat` throws and the loop below moves
 * on -- but a commit cut from this checkout would still ship them, which is
 * exactly how round 3 found `preview.png` (byte-identical to the multiplayer
 * lobby mock, under the filename the marketplace uses for previews) alive at
 * HEAD while every gate ran green against a tree that no longer had it. An
 * unstaged deletion is therefore a scan failure, not a silent skip.
 */
function unstagedDeletions(): string[] {
  return git("ls-files", "-z", "--deleted").split("\0").filter(Boolean).sort();
}

async function workingTreeBlobs(): Promise<Blob[]> {
  const listed = [...new Set(
    git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
      .split("\0")
      .filter(Boolean),
  )].sort();
  const blobs: Blob[] = [];
  for (const path of listed) {
    const absolute = resolve(root, path);
    let stat;
    try {
      stat = await lstat(absolute);
    } catch {
      continue; // tracked but deleted from the working tree
    }
    if (stat.isSymbolicLink()) {
      const target = Buffer.from(await readlink(absolute), "utf8");
      blobs.push({
        path,
        mode: "120000",
        size: target.length,
        sha: createHash("sha1").update(target).digest("hex"),
        bytes: target,
      });
      continue;
    }
    if (!stat.isFile()) continue;
    const bytes = await readFile(absolute);
    blobs.push({
      path,
      mode: (stat.mode & 0o111) !== 0 ? "100755" : "100644",
      size: bytes.length,
      sha: createHash("sha1").update(bytes).digest("hex"),
      bytes,
    });
  }
  return blobs;
}

function digest(label: string, blobs: Blob[]): string {
  const hash = createHash("sha1").update(`${label}\n`);
  for (const blob of blobs) hash.update(`${blob.mode} ${blob.path} ${blob.sha}\n`);
  return hash.digest("hex");
}

function jsonResponse(body: unknown): Response {
  const text = JSON.stringify(body);
  return new Response(text, {
    status: 200,
    headers: {
      "content-type": "application/json",
      "content-length": String(Buffer.byteLength(text)),
    },
  });
}

function bytesResponse(bytes: Buffer, range: string | undefined, total: number): Response {
  const match = range ? /^bytes=0-(\d+)$/.exec(range) : null;
  if (!match) {
    return new Response(new Uint8Array(bytes), {
      status: 200,
      headers: { "content-length": String(bytes.length) },
    });
  }
  const slice = bytes.subarray(0, Math.min(bytes.length, Number(match[1]) + 1));
  return new Response(new Uint8Array(slice), {
    status: 206,
    headers: {
      "content-length": String(slice.length),
      "content-range": `bytes 0-${slice.length - 1}/${total}`,
    },
  });
}

/**
 * Serves the working tree over the three GitHub endpoints the marketplace
 * snapshot reader uses, so the scanner's own code path runs unchanged.
 */
function workingTreeFetch(owner: string, repository: string, commitSha: string, blobs: Blob[]) {
  const byPath = new Map(blobs.map((blob) => [blob.path, blob]));
  const treeSha = digest("tree", blobs);
  const slug = `/repos/${owner}/${repository}`;
  return async (input: string | URL, init: RequestInit = {}): Promise<Response> => {
    const url = new URL(String(input));
    if (url.host === "api.github.com") {
      if (url.pathname === slug) {
        return jsonResponse({
          full_name: `${owner}/${repository}`,
          private: false,
          disabled: false,
          archived: false,
          default_branch: "main",
        });
      }
      if (url.pathname === `${slug}/commits/${commitSha}`) {
        return jsonResponse({ sha: commitSha, commit: { tree: { sha: treeSha } } });
      }
      if (url.pathname === `${slug}/git/trees/${treeSha}`) {
        return jsonResponse({
          sha: treeSha,
          truncated: false,
          tree: blobs.map((blob) => ({
            path: blob.path,
            type: "blob",
            mode: blob.mode,
            size: blob.size,
            sha: blob.sha,
          })),
        });
      }
      return new Response("Not Found", { status: 404 });
    }
    if (url.host === "raw.githubusercontent.com") {
      const segments = url.pathname.split("/").filter(Boolean);
      if (segments[0] !== owner || segments[1] !== repository || segments[2] !== commitSha) {
        return new Response("Not Found", { status: 404 });
      }
      const path = segments.slice(3).map(decodeURIComponent).join("/");
      const blob = byPath.get(path);
      if (!blob) return new Response("Not Found", { status: 404 });
      const headers = new Headers((init.headers ?? {}) as HeadersInit);
      return bytesResponse(blob.bytes, headers.get("range") ?? undefined, blob.size);
    }
    return new Response("Not Found", { status: 404 });
  };
}

function decodeMarker(report: string): unknown {
  const encoded = /marketplace-security-baseline:v\d+ ([A-Za-z0-9_-]+) -->/.exec(report)?.[1];
  if (!encoded) return null;
  return JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
}

try {
  await access(scannerModule);
} catch {
  console.error(`The marketplace security baseline was not found at ${marketplace}.`);
  console.error("The analysis is the marketplace's own code and is never vendored into this repository.");
  console.error("Clone it beside this checkout, or point TURBO_TABLES_MARKETPLACE at it:");
  console.error("  git clone https://github.com/omacom/omarchy-plugin-marketplace.git ../omarchy-plugin-marketplace");
  console.error("CI pins it to a commit; see .github/workflows/ci.yml.");
  process.exit(2);
}

const [{ resolveSubmissionSnapshot, runSecurityBaseline, SecurityBaselineError },
  { buildSecurityBaselineFailureReport, buildSecurityBaselineReport },
  { securityBaselineVersion, securityBaselineEnforcementMode, verifiedPublicationDisposition }] =
  await Promise.all([
    import(pathToFileURL(scannerModule).href),
    import(pathToFileURL(reportModule).href),
    import(pathToFileURL(policyModule).href),
  ]);

const manifest = JSON.parse(await readFile(resolve(root, "manifest.json"), "utf8"));
const repoUrl = repositoryUrl();
const [owner, repository] = new URL(repoUrl).pathname.split("/").filter(Boolean);
const entryPoints: string[] = Object.values(manifest.entryPoints);
const options: Record<string, unknown> = {
  requiredPaths: entryPoints,
  listedPlugins: [{ pluginId: manifest.id, manifestPathHint: "manifest.json" }],
};

let subject: string;
let commitSha: string;
let blobs: Blob[] = [];

if (remote) {
  commitSha = git("rev-parse", "HEAD").trim();
  subject = `remote snapshot of ${repoUrl} at pushed commit ${commitSha}`;
} else {
  blobs = await workingTreeBlobs();
  commitSha = digest("commit", blobs);
  options.fetchImpl = workingTreeFetch(owner, repository, commitSha, blobs);
  subject = `working tree at ${relative(process.cwd(), root) || "."} (${blobs.length} files, content id ${commitSha})`;
}

try {
  const result = await runSecurityBaseline(repoUrl, commitSha, options);
  process.stdout.write(buildSecurityBaselineReport(result, { context: "submission" }));

  const marker = decodeMarker(buildSecurityBaselineReport(result, { context: "submission" }));
  const findings: { ruleId: string; title: string }[] = result.findings;
  const capabilities: { id: string; title: string }[] = result.capabilities;

  console.log("");
  console.log("### Decoded result");
  console.log("");
  console.log(`Scanned:            ${subject}`);
  console.log(`Scan mode:          ${remote ? "--remote (GitHub snapshot; uncommitted work is NOT scanned)" : "working tree (default)"}`);
  console.log(`Baseline source:    ${marketplace}`);
  console.log(`Baseline version:   ${result.baselineVersion} (policy module reports ${securityBaselineVersion})`);
  console.log(`Enforcement mode:   ${result.enforcementMode} (policy module reports ${securityBaselineEnforcementMode})`);
  console.log(`Outcome:            ${result.outcome}`);
  console.log(`Disposition:        ${result.disposition}`);
  console.log(`Blocks approval:    ${result.blocksApproval}`);
  console.log(`Verified publication disposition: ${verifiedPublicationDisposition(result)}`);
  console.log(`Findings (${findings.length}):       ${findings.length ? findings.map((f) => `${f.ruleId}`).join(", ") : "none"}`);
  console.log(`Capabilities (${capabilities.length}):   ${capabilities.length ? capabilities.map((c) => `${c.id}`).join(", ") : "none"}`);
  console.log(`Marker payload:     ${JSON.stringify(marker)}`);

  if (!remote) {
    const snapshot = await resolveSubmissionSnapshot(repoUrl, commitSha, options);
    console.log("");
    console.log(`### Files the scanner read (${snapshot.files.length} of ${blobs.length} in the working tree)`);
    console.log("");
    for (const file of snapshot.files) {
      console.log(`  ${file.path}${file.binary ? ` [binary ${file.format}]` : ""}`);
    }
    console.log("");
    console.log(`### Files in the working tree the scanner's scope excluded (${blobs.length - snapshot.files.length})`);
    console.log("");
    const read = new Set(snapshot.files.map((file: { path: string }) => file.path));
    for (const blob of blobs) if (!read.has(blob.path)) console.log(`  ${blob.path}`);
  }

  if (!remote) {
    const deleted = unstagedDeletions();
    if (deleted.length) {
      console.error("");
      console.error(
        `The index still carries ${deleted.length} file(s) that are gone from the working tree, so this scan did not read them\n`
        + "and a commit cut from this checkout would still ship them:",
      );
      for (const path of deleted) console.error(`  ${path}`);
      console.error("Stage the deletion (git add -A <path>) so the index and the working tree agree.");
      process.exitCode = 1;
    } else {
      console.log("Unstaged deletions:  none -- the index and the working tree hold the same files, so this scan saw everything a commit would ship");
    }
  }

  if (result.outcome !== "passed") {
    console.error(`\nScanner outcome is ${result.outcome}; the rule is passed on every commit.`);
    process.exitCode = 1;
  }
} catch (error) {
  const code = (error as { code?: string })?.code ?? "security-baseline-unavailable";
  process.stdout.write(buildSecurityBaselineFailureReport(error, { context: "submission" }));
  console.error(`Automated security baseline failed [${code}]: ${(error as Error)?.message}`);
  if (!(error instanceof SecurityBaselineError)) console.error(error);
  process.exitCode = 2;
}
