// Mirrors tests/unit/test_pve_match.gd.
import { test } from "node:test";
import assert from "node:assert/strict";
import { PVE, level, PveMatch, starsFor, arenaLevel, weekIndex, runPve, type PveLevelDef, type Placement } from "../game/pve.ts";

function run(lvl: PveLevelDef, p: Placement) {
  const m = new PveMatch(lvl, p, 1);
  for (let i = 0; !m.over && i < 30000; i++) m.step();
  assert.ok(m.over);
  return m.result();
}
const arenaLike = (counts: number[]): PveLevelDef => ({ ...structuredClone(level(1)!), arena: true,
  waves: counts.map((c, i) => ({ tick: 40 + i * 300, node: 9, count: c, kind: 0 })) });

test("level 1: laser 3 stars, empty 0", () => {
  assert.equal(run(level(1)!, [{ slot: 2, type: "laser" }]).stars, 3);
  assert.equal(run(level(1)!, []).stars, 0);
});
test("stars formula", () => {
  assert.deepEqual([starsFor(false, 0), starsFor(false, 1), starsFor(false, 2), starsFor(true, 0)], [3, 2, 1, 0]);
});
test("arena scoring", () => {
  assert.equal(run(arenaLike([1, 1, 1, 1]), [{ slot: 2, type: "laser" }]).score, 4);
  const r = run(arenaLike([5, 5, 200, 5]), [{ slot: 2, type: "laser" }]);
  assert.equal(r.waves_started, 3);
  assert.equal(r.score, 2);
});
test("arena level per week", () => {
  const a = arenaLevel(5);
  assert.deepEqual(a, arenaLevel(5));
  assert.notDeepEqual(a.waves, arenaLevel(6).waves);
  assert.equal(a.waves.length, PVE.arena.max_waves);
  assert.deepEqual([a.waves[0].tick, a.waves[1].tick, a.waves[2].count], [40, 340, 14]);
});
test("week index", () => {
  const e = PVE.weekly.epoch;
  assert.deepEqual([weekIndex(e), weekIndex(e + 604799), weekIndex(e + 604800)], [0, 0, 1]);
});

test("player sends: replayable, spawns off-limits, junk ignored", () => {
  const l = level(1)!;
  const m = new PveMatch(l, [], 1);
  m.step();
  m.send(1, 2, 50);
  m.step();
  assert.deepEqual(m.commands, [{ tick: 1, from: 1, to: 2, percent: 50 }]);
  const a = runPve(l, [], 1, m.commands);
  assert.equal(a.hash, runPve(l, [], 1, m.commands).hash);
  assert.notEqual(a.hash, runPve(l, [], 1).hash);
  const s = new PveMatch(l, [], 1);
  s.send(1, 9, 100);
  s.step();
  assert.equal(s.world.groups.length, 0);
  const junk: any[] = [{ tick: "x", from: 1, to: 2, percent: 50 }, "bad", { tick: 3 }, null,
    { tick: 2, from: 1, to: 2, percent: 50, type: "spawn", owner: 2 }];
  assert.equal(runPve(l, [{ slot: 2, type: "laser" }], 1, junk).result.stars, 3);
});
