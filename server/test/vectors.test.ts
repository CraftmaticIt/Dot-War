// Determinism contract: every GDScript-generated vector must replay identically in TS.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { SimReplay } from "../sim/replay.ts";

const DIR = new URL("../../tests/vectors/", import.meta.url);
const files = readdirSync(DIR).filter((f) => f.endsWith(".json")).sort();

test("at least six vectors", () => assert.ok(files.length >= 6));

for (const f of files) {
  test(`vector ${f}`, () => {
    const v = JSON.parse(readFileSync(new URL(f, DIR), "utf8"));
    const w = SimReplay.run(v);
    assert.equal(w.canonical(), v.expected_canonical);
    assert.equal(w.stateHash(), v.expected_hash);
  });
}
