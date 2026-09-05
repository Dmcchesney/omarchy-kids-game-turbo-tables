// npm run check:terrain -- the two copies of the circuit's ground, compared.
//
// `ui/parts/Terrain.js` is the source of the sector palettes, the sector curve
// table, the lattice sizes, the crossfade and the integer hash. `shaders/
// road.frag` holds a mirror of all of it, because GLSL cannot read a `.js` and
// a fragment shader is where the ground is actually painted on every machine
// that has a shader pipeline. Two copies of a picture is two pictures unless
// something compares them, and this project has learned that the expensive way:
// three rounds asserted "the fallback draws the same picture" and two of those
// were measured false -- the zebra pitch was twice the shader's, and the
// transverse grid lines were never drawn at all.
//
// So this is a gate rather than a convention. Every number below is parsed out
// of both files and compared; a palette changed in one and not the other fails
// the build in the same commit that made the change, which is the only moment
// at which it is cheap to fix.
//
// WHAT IT DOES NOT CHECK, stated here rather than left to be discovered: this
// compares TABLES, not code. The two `groundAt` implementations -- one in GLSL,
// one in JavaScript -- are still written twice and could still diverge in their
// arithmetic while every constant matches. What holds those together is the
// rendered difference in the piece T evidence, measured between a CPU reference
// of road.frag and a real CanvasRoad frame at the same camera. A reader who
// changes the shape of `groundAt` must re-run that; changing a NUMBER in it is
// what this catches.

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const failures: string[] = [];
const fail = (message: string): void => {
  failures.push(message);
};

const frag = await readFile(resolve(root, "shaders/road.frag"), "utf8");
const terrain = await readFile(resolve(root, "ui/parts/Terrain.js"), "utf8");

/** Every number in a chunk of source, in order. */
function numbers(text: string): number[] {
  return (text.match(/-?\d+(?:\.\d+)?/g) ?? []).map(Number);
}

/**
 * The text between a bracket and its match, starting at the first `open` at or
 * after `from`. Bracket-matched rather than terminated by a token, because both
 * files write these tables across several lines with brackets inside them, and a
 * "stop at the next `]`" rule silently ran one table into the next -- which this
 * check's own first run did, reporting SECTOR_CURVE as sixty numbers long.
 */
function balanced(text: string, from: number, open: string, close: string, what: string): string | null {
  const start = text.indexOf(open, from);
  if (start < 0) {
    fail(`${what}: no ${open} after the declaration`);
    return null;
  }
  let depth = 0;
  for (let i = start; i < text.length; i++) {
    if (text[i] === open) depth += 1;
    else if (text[i] === close) {
      depth -= 1;
      if (depth === 0) return text.slice(start + 1, i);
    }
  }
  fail(`${what}: unterminated ${open}`);
  return null;
}

function findOrFail(text: string, pattern: RegExp, what: string): number {
  const at = text.search(pattern);
  if (at < 0) fail(`${what}: not found`);
  return at;
}

/** A table in road.frag: `const <type> NAME[12] = <type>[12]( ... );` */
function fragTable(name: string): number[] | null {
  const at = findOrFail(frag, new RegExp(`const\\s+\\w+\\s+${name}\\s*\\[12\\]\\s*=`), `road.frag ${name}`);
  if (at < 0) return null;
  const body = balanced(frag, frag.indexOf("=", at), "(", ")", `road.frag ${name}`);
  if (body === null) return null;
  // `vec3(` and `vec4(` carry a digit that is a TYPE, not a value.
  return numbers(body.replace(/vec[234]\s*\(/g, "("));
}

/** A table in Terrain.js: `var NAME = [ ... ]` */
function jsTable(name: string): number[] | null {
  const at = findOrFail(terrain, new RegExp(`\\bvar\\s+${name}\\s*=`), `Terrain.js ${name}`);
  if (at < 0) return null;
  const body = balanced(terrain, terrain.indexOf("=", at), "[", "]", `Terrain.js ${name}`);
  if (body === null) return null;
  return numbers(body);
}

function compareTable(name: string, expect: number): void {
  const a = fragTable(name);
  const b = jsTable(name);
  if (a === null || b === null) return;
  if (a.length !== expect) fail(`road.frag ${name} has ${a.length} numbers, expected ${expect}`);
  if (b.length !== expect) fail(`Terrain.js ${name} has ${b.length} numbers, expected ${expect}`);
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    if (Math.abs(a[i] - b[i]) > 5e-5) {
      fail(`${name}[${i}]: road.frag has ${a[i]}, Terrain.js has ${b[i]}`);
    }
  }
}

// The three sector tables and the curve. 12 sectors; SOIL and SCRUB are
// triples, FLAGS is a quad.
compareTable("SECTOR_CURVE", 12);
compareTable("SOIL", 36);
compareTable("SCRUB", 36);
compareTable("FLAGS", 48);

// The lattice. `const float COARSE = 2.0;` against `var COARSE = 2.0`.
for (const name of ["COARSE", "FINE", "RUT"]) {
  const inFrag = frag.match(new RegExp(`const\\s+float\\s+${name}\\s*=\\s*(-?\\d+(?:\\.\\d+)?)`));
  const inJs = terrain.match(new RegExp(`\\bvar\\s+${name}\\s*=\\s*(-?\\d+(?:\\.\\d+)?)`));
  if (!inFrag) fail(`road.frag ${name}: not found`);
  else if (!inJs) fail(`Terrain.js ${name}: not found`);
  else if (Math.abs(Number(inFrag[1]) - Number(inJs[1])) > 1e-9) {
    fail(`${name}: road.frag has ${inFrag[1]}, Terrain.js has ${inJs[1]}`);
  }
}

// The integer hash: the three wrapping multipliers and the two shifts have to
// be the same in both, or the two renderers paint different noise fields with
// no other symptom than a picture that does not match.
function body(text: string, pattern: RegExp, what: string): string {
  const at = findOrFail(text, pattern, what);
  if (at < 0) return "";
  return balanced(text, text.indexOf("{", at), "{", "}", what) ?? "";
}
const fragHash = numbers(body(frag, /float hashCell\(/, "road.frag hashCell"));
const jsHash = numbers(body(terrain, /function hashCell\(/, "Terrain.js hashCell"));
const wanted = [374761393, 668265263, 13, 1274126177, 16, 16, 65536];
for (const constant of wanted) {
  if (!fragHash.includes(constant)) fail(`road.frag hashCell is missing the constant ${constant}`);
  if (!jsHash.includes(constant)) fail(`Terrain.js hashCell is missing the constant ${constant}`);
}

// The sector crossfade: `smoothstep(0.62, 1.0, f)` against `(f - 0.62) / 0.38`.
const fragFade = frag.match(/t = smoothstep\((\d+(?:\.\d+)?),\s*1\.0,\s*f\);/);
const jsFade = terrain.match(/var t = \(f - (\d+(?:\.\d+)?)\) \/ (\d+(?:\.\d+)?)/);
if (!fragFade) fail("road.frag: the sector crossfade smoothstep was not found");
else if (!jsFade) fail("Terrain.js: the sector crossfade was not found");
else {
  const edge = Number(fragFade[1]);
  if (Math.abs(edge - Number(jsFade[1])) > 1e-9) {
    fail(`the sector crossfade starts at ${edge} in road.frag and ${jsFade[1]} in Terrain.js`);
  }
  if (Math.abs(1 - edge - Number(jsFade[2])) > 1e-9) {
    fail(`the sector crossfade spans ${(1 - edge).toFixed(4)} in road.frag and ${jsFade[2]} in Terrain.js`);
  }
}

// The fine octave's distance fade, which decides where the half-unit lattice
// stops contributing: `smoothstep(22.0, 6.0, z)` in both.
if (!/smoothstep\(22\.0,\s*6\.0,\s*z\)/.test(frag)) {
  fail("road.frag: the fine octave's fade is not smoothstep(22.0, 6.0, z)");
}
if (!/\(z - 22\.0\) \/ \(6\.0 - 22\.0\)/.test(terrain)) {
  fail("Terrain.js: fineFade is not the inverse of smoothstep(22.0, 6.0, z)");
}

if (failures.length > 0) {
  console.error("check:terrain FAILED");
  for (const line of failures) console.error(`  ${line}`);
  process.exit(1);
}

console.log(
  "check:terrain ok -- shaders/road.frag and ui/parts/Terrain.js agree on the sector curve, "
    + "the twelve soil and scrub palettes, the twelve flag quads, the three lattice sizes, "
    + "the integer hash's constants, the sector crossfade and the fine octave's fade.",
);
