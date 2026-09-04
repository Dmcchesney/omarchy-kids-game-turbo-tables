import { test } from "node:test";
import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

// ui/parts/CarMeta.js is the bake's meta.json carried into layer 2 as a
// JavaScript literal, because a QML file may not read a file at runtime. It
// is a mirror, and a mirror can go stale: this test holds it to the committed
// meta.json files, so a rebake that moves a number rect fails `npm test`
// until the mirror is regenerated.

const root = resolve(import.meta.dirname, "..");
const bodies = ["coupe", "hatch", "wedge", "saloon", "buggy", "pickup"];

type CarMeta = {
  META: Record<string, unknown>;
  SHEET_W: number;
  SHEET_H: number;
  YAWS: number;
  CELL_W: number[];
  CELL_H: number[];
  ROW_SCALE: number[];
  ROW_Y: number[];
  fit: (px: number) => { sheetScale: number; pixelScale: number; width: number };
  columnForHeading: (deg: number) => number;
  rowOf: (camera: string, scale: number) => number;
};

async function loadCarMeta(): Promise<CarMeta> {
  const text = await readFile(join(root, "ui/parts/CarMeta.js"), "utf8");
  // `.pragma library` is QML's, not JavaScript's; everything else in the
  // file is plain ES5.
  const body = text
    .split(/\r?\n/)
    .filter((line) => !line.startsWith(".pragma"))
    .join("\n");
  const factory = new Function(
    `${body}\nreturn { META, SHEET_W, SHEET_H, YAWS, CELL_W, CELL_H, ROW_SCALE, ROW_Y, fit, columnForHeading, rowOf };`,
  );
  return factory() as CarMeta;
}

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

test("CarMeta.js mirrors every committed meta.json", async (t) => {
  const carMeta = await loadCarMeta();
  assert.deepEqual(Object.keys(carMeta.META).sort(), [...bodies].sort(), "one entry per contract body");
  let compared = 0;
  for (const body of bodies) {
    const path = join(root, "assets/karts", body, "meta.json");
    if (!(await exists(path))) {
      t.diagnostic(`assets/karts/${body}/meta.json is not committed: CarMeta.js "${body}" is unverified against the bake`);
      continue;
    }
    const committed = JSON.parse(await readFile(path, "utf8"));
    assert.deepEqual(
      carMeta.META[body],
      committed,
      `ui/parts/CarMeta.js "${body}" differs from assets/karts/${body}/meta.json: regenerate the mirror`,
    );
    compared += 1;
  }
  t.diagnostic(`${compared} of ${bodies.length} bodies compared against a committed meta.json`);
});

test("every mirrored meta has the contract's shape", async () => {
  const carMeta = await loadCarMeta();
  for (const body of bodies) {
    const meta = carMeta.META[body] as {
      body: string;
      cell: number[][];
      yaws: number;
      anchor: string;
      number: { stall: unknown[]; road: unknown[] };
    };
    assert.equal(meta.body, body);
    assert.deepEqual(meta.cell, [[192, 128], [96, 64], [48, 32]]);
    assert.equal(meta.yaws, 8);
    assert.equal(meta.anchor, "bottom-center");
    for (const camera of ["stall", "road"] as const) {
      assert.equal(meta.number[camera].length, 8, `${body}: eight ${camera} number rects`);
      for (const rect of meta.number[camera] as { x: number; y: number; w: number; h: number }[]) {
        for (const key of ["x", "y", "w", "h"] as const) assert.equal(typeof rect[key], "number");
        assert.ok(rect.x >= 0 && rect.x + rect.w <= 192, `${body} ${camera}: rect inside the 1.0 cell`);
        assert.ok(rect.y >= 0 && rect.y + rect.h <= 128, `${body} ${camera}: rect inside the 1.0 cell`);
      }
    }
  }
});

test("the sheet layout is the contract's", async () => {
  const carMeta = await loadCarMeta();
  assert.equal(carMeta.SHEET_W, 1536);
  assert.equal(carMeta.SHEET_H, 448);
  assert.equal(carMeta.YAWS, 8);
  assert.deepEqual(carMeta.CELL_W, [192, 96, 48]);
  assert.deepEqual(carMeta.CELL_H, [128, 64, 32]);
  assert.deepEqual(carMeta.ROW_SCALE, [1.0, 0.5, 0.25]);
  // Row y is the running sum of the row heights, both camera groups.
  const expected: number[] = [];
  let y = 0;
  for (let group = 0; group < 2; group++)
    for (let step = 0; step < 3; step++) {
      expected.push(y);
      y += carMeta.CELL_H[step];
    }
  assert.deepEqual(carMeta.ROW_Y, expected);
  assert.equal(y, carMeta.SHEET_H);
  assert.equal(carMeta.CELL_W[0] * carMeta.YAWS, carMeta.SHEET_W);
  assert.equal(carMeta.rowOf("stall", 1.0), 0);
  assert.equal(carMeta.rowOf("stall", 0.25), 2);
  assert.equal(carMeta.rowOf("road", 0.5), 4);
});

test("fit never returns a fractional scale", async () => {
  const carMeta = await loadCarMeta();
  const allowed = new Set([48, 96, 144, 192, 288, 384, 576]);
  for (let px = 0; px <= 2000; px += 3) {
    const f = carMeta.fit(px);
    assert.ok(Number.isInteger(f.pixelScale) && f.pixelScale >= 1 && f.pixelScale <= 3, `fit(${px})`);
    assert.ok([1.0, 0.5, 0.25].includes(f.sheetScale), `fit(${px})`);
    assert.ok(allowed.has(f.width), `fit(${px}) gave ${f.width}`);
  }
  assert.deepEqual(carMeta.fit(461), { sheetScale: 1.0, pixelScale: 2, width: 384 });
  // A heading to the viewer's right counts the columns backwards from 8: the
  // bake turned the car counter-clockwise, so column 7 is the nose-right
  // cell. Which way the sheet faces is measured on its pixels in
  // tests/qml/tst_carsprite.qml; this only pins the arithmetic.
  assert.equal(carMeta.columnForHeading(45), 7);
  assert.equal(carMeta.columnForHeading(-45), 1);
  assert.equal(carMeta.columnForHeading(180), 4);
});
