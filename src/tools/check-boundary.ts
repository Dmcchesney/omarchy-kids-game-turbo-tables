import { access, lstat, readFile, readdir } from "node:fs/promises";
import { basename, extname, join, relative, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const ignored = new Set([".git", "node_modules", "coverage", "evidence"]);
const forbiddenDirectoryNames = new Set(["bin", "scripts"]);
const forbiddenFileName = /^(?:install|installer|setup|uninstall)(?:\.|$)/i;
const allowedBinaryExtensions = new Set([".png", ".wav", ".qsb"]);
const binaryMagic = [
  Buffer.from([0x7f, 0x45, 0x4c, 0x46]),
  Buffer.from([0x4d, 0x5a]),
  Buffer.from([0xcf, 0xfa, 0xed, 0xfe]),
  Buffer.from([0xfe, 0xed, 0xfa, 0xcf]),
];

const failures: string[] = [];

async function walk(directory: string): Promise<void> {
  for (const name of await readdir(directory)) {
    if (ignored.has(name)) continue;
    const path = join(directory, name);
    const display = relative(root, path);
    const stat = await lstat(path);

    if (stat.isSymbolicLink()) {
      failures.push(`${display}: symlink`);
      continue;
    }

    if (stat.isDirectory()) {
      if (forbiddenDirectoryNames.has(name.toLowerCase()))
        failures.push(`${display}: forbidden directory`);
      await walk(path);
      continue;
    }

    if (forbiddenFileName.test(basename(path)))
      failures.push(`${display}: forbidden installer-like filename`);
    if ((stat.mode & 0o111) !== 0)
      failures.push(`${display}: executable bit set`);

    const extension = extname(name).toLowerCase();
    if (!allowedBinaryExtensions.has(extension)) {
      const prefix = (await readFile(path)).subarray(0, 4);
      if (binaryMagic.some((magic) => prefix.subarray(0, magic.length).equals(magic)))
        failures.push(`${display}: executable binary`);
    }
  }
}

try {
  await access(join(root, "node_modules"));
  failures.push("node_modules: must never exist inside the plugin checkout (its symlinks fail omarchy plugin validate); tools run through npx");
} catch {}

await walk(root);

if (failures.length) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Boundary check passed.");
}
