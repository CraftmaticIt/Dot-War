// Mirrors tests/unit/test_colony_economy.gd so server-side accrual matches the client.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ColonyState } from "../game/colony.ts";

const T0 = 1_800_000_000, H = 3600;
const fresh = () => ColonyState.newDefault(T0);

test("one hour mine lvl1", () => {
  const c = fresh();
  assert.deepEqual(c.collect(T0 + H), { energy: 100, dots: 0, secs: H });
  assert.equal(c.energy, 600);
});

test("remainder carried across 1s collects", () => {
  const c = fresh();
  for (let i = 1; i <= H; i++) c.collect(T0 + i);
  assert.equal(c.energy, 600);
});

test("offline cap 8h", () => {
  const c = fresh();
  c.cells["0,1"] = { type: "storage", level: 1, build_end: 0, target_level: 1 };
  assert.equal(c.collect(T0 + 24 * H).secs, 8 * H);
  assert.equal(c.energy, 1300);
});

test("clock backwards", () => {
  const c = fresh();
  assert.deepEqual(c.collect(T0 - 100), { energy: 0, dots: 0, secs: 0 });
  assert.equal(c.lastCollect, T0);
});

test("build finishing mid window", () => {
  const c = fresh();
  c.cells["0,0"].level = 2;
  c.energy = 700;
  c.cells["1,0"] = { type: "mine", level: 1, build_end: T0 + 1800, target_level: 2 };
  c.collect(T0 + H);
  assert.equal(c.energy, 850);
  assert.equal(c.cells["1,0"].level, 2);
});

test("storage cap clamps, stock above cap kept", () => {
  const c = fresh();
  c.collect(T0 + 8 * H);
  assert.equal(c.energy, 1000);
  const d = fresh();
  d.energy = 5000;
  d.collect(T0 + H);
  assert.equal(d.energy, 5000);
});

test("fromDict rejects colony without core and future versions", () => {
  assert.equal(ColonyState.fromDict({ cells: {} }), null);
  const d = fresh().toDict();
  d.version = 99;
  assert.equal(ColonyState.fromDict(d), null);
  assert.equal(ColonyState.fromDict("x"), null);
});
