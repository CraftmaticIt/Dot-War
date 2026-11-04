// PvE contract: every GDScript-generated PvE vector must replay identically in TS.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { level, arenaLevel, runPve } from "../game/pve.ts";

const DIR = new URL("../../tests/pve_vectors/", import.meta.url);
const files = readdirSync(DIR).filter((f) => f.endsWith(".json")).sort();

test("at least three PvE vectors", () => assert.ok(files.length >= 3));

for (const f of files) {
  test(`pve vector ${f}`, () => {
    const v = JSON.parse(readFileSync(new URL(f, DIR), "utf8"));
    const lvl = v.week !== undefined ? arenaLevel(v.week) : level(v.level)!;
    const r = runPve(lvl, v.placement, v.seed, v.commands ?? []);
    assert.deepEqual(r.result, v.expected.result);
    assert.equal(r.hash, v.expected.hash);
  });
}
