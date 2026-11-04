// Mirrors tests/unit/test_colony_economy.gd so server-side accrual matches the client.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ColonyState } from "../game/colony.ts";

const T0 = 1_800_000_000, H = 3600;
// Mine-only colony (default minus its starter generator) so these tests see mine accrual alone.
const fresh = () => {
  const c = ColonyState.newDefault(T0);
  delete c.cells["0,1"];
  c.energy = 500; c.dots = 0;
  return c;
};

test("one hour mine lvl1", () => {
  const c = fresh();
  assert.deepEqual(c.collect(T0 + H), { energy: 500, dots: 0, secs: H });
  assert.equal(c.energy, 1000);
});

test("remainder carried across 1s collects", () => {
  const c = fresh();
  for (let i = 1; i <= H; i++) c.collect(T0 + i);
  assert.equal(c.energy, 1000);
});

test("offline cap 8h", () => {
  const c = fresh();
  c.cells["0,1"] = { type: "storage", level: 1, build_end: 0, target_level: 1 };
  assert.equal(c.collect(T0 + 24 * H).secs, 8 * H);
  assert.equal(c.energy, 3500); // cap: core 2000 + storage 1500
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
  assert.equal(c.energy, 700 + 250 + 500);
  assert.equal(c.cells["1,0"].level, 2);
});

test("storage cap clamps, stock above cap kept", () => {
  const c = fresh();
  c.collect(T0 + 8 * H);
  assert.equal(c.energy, 2000);
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

test("fromDict hardening mirrors GDScript", () => {
  const base = () => fresh().toDict();
  const d1 = base();
  d1.cells["abc"] = { type: "core", level: 5, build_end: 0, target_level: 5 };
  d1.cells["01,0"] = { type: "wall", level: 1, build_end: 0, target_level: 1 };
  d1.cells["5,0"] = { type: "wall", level: 1, build_end: 0, target_level: 1 };
  const c1 = ColonyState.fromDict(d1)!;
  assert.equal(c1.cells["0,0"].level, 1);
  assert.equal(Object.keys(c1.cells).length, 2);
  const d2 = base();
  d2.cells["0,1"] = { type: "mine", level: [1], build_end: 0, target_level: 1 };
  d2.cells["-1,0"] = { type: 5, level: 1, build_end: 0, target_level: 1 };
  d2.energy = "lots"; d2.energy_rem = -100000; d2.dots_rem = 99999;
  d2.cells["1,0"].target_level = 0;
  const c2 = ColonyState.fromDict(d2)!;
  assert.equal(Object.keys(c2.cells).length, 2);
  assert.equal(c2.energy, 0);
  assert.equal(c2.energyRem, 0);
  assert.equal(c2.dotsRem, 3599);
  assert.equal(c2.cells["1,0"].target_level, 1);
  const d3 = base();
  d3.cells["0,1"] = { type: "core", level: 1, build_end: 0, target_level: 1 };
  assert.equal(ColonyState.fromDict(d3), null, "two cores");
});
