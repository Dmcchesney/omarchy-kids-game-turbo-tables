import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

// ui/parts/PropMeta.js mirrors assets/props/props-meta.json into layer 2 as a
// JavaScript literal, the way CarMeta.js mirrors the car sheets. This test
// holds the mirror to the committed meta, so a rebake that changes a cell
// fails `npm test` until the mirror is regenerated (bake-props.ts does it).

const root = resolve(import.meta.dirname, "..");

type PropMetaModule = {
  META: Record<string, { cell: number[]; views: string[]; rows: number[] }>;
  FINE: number;
  cellRect: (name: string, view: string, step: number) => { x: number; y: number; width: number; height: number } | null;
  stepFor: (name: string, px: number) => number;
};

async function loadMirror(): Promise<PropMetaModule> {
  const text = await readFile(join(root, "ui/parts/PropMeta.js"), "utf8");
  const body = text.split(/\r?\n/).filter((line) => !line.startsWith(".pragma")).join("\n");
  return new Function(`${body}\nreturn { META, FINE, cellRect, stepFor };`)() as PropMetaModule;
}

test("PropMeta.js mirrors assets/props/props-meta.json exactly", async () => {
  const mirror = await loadMirror();
  const meta = JSON.parse(await readFile(join(root, "assets/props/props-meta.json"), "utf8"));
  assert.deepEqual(mirror.META, meta);
  assert.equal(mirror.FINE, 4);
});

test("cellRect addresses each view at each scale inside the sheet", async () => {
  const mirror = await loadMirror();
  for (const [name, m] of Object.entries(mirror.META)) {
    for (const view of m.views) {
      for (let step = 0; step < 3; step++) {
        const r = mirror.cellRect(name, view, step);
        assert.ok(r, `${name}/${view}/${step}`);
        assert.equal(r.y, m.rows[step]);
        assert.ok(r.x + r.width <= m.cell[0] * m.views.length, `${name}/${view}/${step} overruns the sheet`);
      }
    }
    assert.equal(mirror.stepFor(name, m.cell[0]), 0);
    assert.equal(mirror.stepFor(name, m.cell[0] / 4), 2);
  }
});
