// Mirrors tests/unit/test_pve_campaign.gd: the server agrees every level is solvable and a puzzle.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PVE, validate, runPve } from "../game/pve.ts";

const SOL = JSON.parse(readFileSync(new URL("../../tests/pve_solutions.json", import.meta.url), "utf8"));

test("15 levels, 3 chapters", () => {
  assert.deepEqual(PVE.levels.map((l) => l.id), Array.from({ length: 15 }, (_, i) => i + 1));
  assert.deepEqual(PVE.levels.map((l) => l.chapter), PVE.levels.map((_, i) => Math.trunc(i / 5) + 1));
});

for (const l of PVE.levels) {
  test(`level ${l.id} ${l.name}: solution 3 stars, empty fails`, () => {
    const p = SOL[String(l.id)];
    assert.equal(validate(l, p, false), "");
    assert.equal(runPve(l, p, 1).result.stars, 3);
    assert.ok(runPve(l, [], 1).result.stars < 3);
  });
}
