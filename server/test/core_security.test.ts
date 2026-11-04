// Regression tests for the stage-4 review findings (exploits and races).
import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryRepo } from "../core/repo.ts";
import { syncColony } from "../core/sync.ts";
import { findOpponent, ABANDON_SECS } from "../core/matchmaking.ts";
import { finishAttack } from "../core/finish.ts";
import { ColonyState } from "../game/colony.ts";

const T0 = 1_800_000_000, H = 3600;
const rand = () => 0.42;

async function seeded(repo: MemoryRepo, id: string, trophies = 0, dots = 0, energy = 500) {
  const c = ColonyState.newDefault(T0);
  c.cells["0,1"] = { type: "generator", level: 1, build_end: 0, target_level: 1 };
  c.dots = dots;
  c.energy = energy;
  repo.seed(id, { trophies, attacks: 0, crystals: 50, shield_until: null }, c.toDict(), T0);
  return c;
}
const stored = async (repo: MemoryRepo, id: string) => ColonyState.fromDict((await repo.getColony(id))!.data)!;
const allCmds = [1001, 1002, 1003].flatMap((e) => [0, 100, 200].map((t) => ({ tick: t, from: e, to: 1, percent: 100 })));

test("C1: parallel finish settles once", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 0, 300);
  const f = await findOpponent(repo, "a", T0, rand, () => repo.newId());
  const rs = await Promise.all([1, 2, 3].map(() => finishAttack(repo, "a", f.attack_id!, allCmds, -1, T0 + 10)));
  const settled = rs.filter((r) => r.result && !r.error);
  assert.ok(settled.length >= 1);
  const loot = settled[0].result!.loot;
  assert.equal((await stored(repo, "a")).energy, 500 + loot, "loot credited exactly once");
  assert.equal((await repo.getPlayer("a"))!.trophies, Math.max(0, settled[0].result!.trophies));
});

test("C1: parallel resolveStale penalises once", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 50, 40);
  await seeded(repo, "x", 0, 0);
  await seeded(repo, "y", 0, 0);
  await findOpponent(repo, "a", T0, rand, () => repo.newId());
  await Promise.all([findOpponent(repo, "x", T0 + ABANDON_SECS + 1, rand), findOpponent(repo, "y", T0 + ABANDON_SECS + 1, rand)]);
  assert.equal((await repo.getPlayer("a"))!.trophies, 42);
});

test("C2: defender cannot re-upload pre-attack energy right after losing loot", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 100, 400);
  const d = await seeded(repo, "d", 100, 0, 1000);
  const f = await findOpponent(repo, "a", T0, rand, () => repo.newId());
  const r = await finishAttack(repo, "a", f.attack_id!, allCmds, -1, T0 + 10);
  if (r.result!.loot > 0) {
    const s = await syncColony(repo, "d", d.toDict(), T0 + 20);
    assert.equal(s.accepted, false);
    assert.equal(s.colony.energy, 1000 - r.result!.loot);
    assert.equal(s.defenses?.count, 1);
    assert.equal(s.defenses?.loot, r.result!.loot);
  }
});

test("C3: forged build_end does not give instant builds", async () => {
  const repo = new MemoryRepo();
  const c = await seeded(repo, "u", 0, 0, 5000);
  c.cells["0,0"] = { type: "core", level: 1, build_end: T0 + 1, target_level: 2 };
  c.energy -= 1000;
  const r1 = await syncColony(repo, "u", c.toDict(), T0 + 1);
  assert.equal(r1.accepted, false, "build_end shorter than the build time is rejected");
});

test("C3: shortening a running build is rejected", async () => {
  const repo = new MemoryRepo();
  const c = await seeded(repo, "u", 0, 0, 5000);
  c.cells["0,0"] = { type: "core", level: 1, build_end: T0 + 300, target_level: 2 };
  c.energy -= 1000;
  assert.equal((await syncColony(repo, "u", c.toDict(), T0)).accepted, true);
  c.cells["0,0"].build_end = T0 + 2;
  assert.equal((await syncColony(repo, "u", c.toDict(), T0 + 1)).accepted, false);
  c.cells["0,0"] = { type: "core", level: 2, build_end: 0, target_level: 2 };
  assert.equal((await syncColony(repo, "u", c.toDict(), T0 + 3)).accepted, false, "finished early without crystals");
});

test("C4: dots and energy capped by storage", async () => {
  const repo = new MemoryRepo();
  const c = await seeded(repo, "u");
  c.dots = 480;  // 8 h of a lvl1 generator, cap 50
  assert.equal((await syncColony(repo, "u", c.toDict(), T0 + 8 * H)).accepted, false);
  c.dots = 50;
  c.energy = 2300; // cap 2000
  assert.equal((await syncColony(repo, "u", c.toDict(), T0 + 8 * H)).accepted, false);
  c.energy = 2000;
  assert.equal((await syncColony(repo, "u", c.toDict(), T0 + 8 * H)).accepted, true);
});

test("C5: first upload must be plausible from a fresh colony", async () => {
  const repo = new MemoryRepo();
  const c = ColonyState.newDefault(T0);
  c.cells["0,0"].level = 5;
  c.dots = 1e9;
  c.energy = 1e9;
  const r = await syncColony(repo, "new", c.toDict(), T0);
  assert.equal(r.accepted, false);
  assert.equal(r.colony.cells["0,0"].level, 1, "server starts the account from the default colony");
  const ok = ColonyState.newDefault(T0);
  ok.cells["-1,0"] = { type: "generator", level: 0, build_end: T0 + 20, target_level: 1 };
  ok.energy -= 200;
  assert.equal((await syncColony(repo, "new2", ok.toDict(), T0)).accepted, true);
});

test("I1: parallel finds spend dots once", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 0, 200);
  const rs = await Promise.all([1, 2].map(() => findOpponent(repo, "a", T0, rand, () => repo.newId())));
  assert.equal(rs.filter((r) => r.attack_id).length, 1);
  assert.equal(rs.filter((r) => r.error === "few_dots").length, 1);
});

test("I2: sync racing a find does not restore spent dots", async () => {
  const repo = new MemoryRepo();
  const c = await seeded(repo, "a", 0, 40);
  const [s] = await Promise.all([syncColony(repo, "a", c.toDict(), T0 + 5), findOpponent(repo, "a", T0 + 5, rand, () => repo.newId())]);
  assert.ok(s);
  assert.equal((await stored(repo, "a")).dots, 0);
});

test("I2: defender sync does not clear shield or restore trophies", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 100, 400);
  const d = await seeded(repo, "d", 100, 0, 1000);
  const f = await findOpponent(repo, "a", T0, rand, () => repo.newId());
  const [, r] = await Promise.all([syncColony(repo, "d", d.toDict(), T0 + 10), finishAttack(repo, "a", f.attack_id!, allCmds, -1, T0 + 10)]);
  if (r.result!.stars >= 1) {
    const p = (await repo.getPlayer("d"))!;
    assert.equal(p.shield_until, T0 + 10 + 8 * H);
    assert.ok(p.trophies < 100);
  }
});

test("I3: downgrade, core limit, isolated cells, builders rejected", async () => {
  const repo = new MemoryRepo();
  const base = await seeded(repo, "u", 0, 0, 900);
  const down = ColonyState.fromDict(base.toDict())!;
  down.cells["0,1"] = { type: "generator", level: 0, build_end: 0, target_level: 0 };
  assert.equal((await syncColony(repo, "u", down.toDict(), T0 + 10)).reason, "downgrade");
  const lim = ColonyState.fromDict(base.toDict())!;
  lim.cells["1,0"] = { type: "mine", level: 1, build_end: T0 + 70, target_level: 2 };
  lim.energy -= 300;
  assert.equal((await syncColony(repo, "u", lim.toDict(), T0 + 10)).reason, "core_limit");
  const iso = ColonyState.fromDict(base.toDict())!;
  iso.cells["3,0"] = { type: "wall", level: 0, build_end: T0 + 20, target_level: 1 };
  iso.energy -= 50;
  assert.equal((await syncColony(repo, "u", iso.toDict(), T0 + 10)).reason, "not_connected");
  const busy = ColonyState.fromDict(base.toDict())!;
  for (const k of ["-1,0", "0,-1", "-1,1"]) busy.cells[k] = { type: "wall", level: 0, build_end: T0 + 30, target_level: 1 };
  busy.energy -= 150;
  assert.equal((await syncColony(repo, "u", busy.toDict(), T0 + 10)).reason, "builders");
});

test("I4: two upgrades offline accepted when timers justify them", async () => {
  const repo = new MemoryRepo();
  const c = await seeded(repo, "u", 0, 0, 10000);
  c.cells["0,0"] = { type: "core", level: 3, build_end: 0, target_level: 3 };  // 300 s + 3600 s
  c.energy -= 5000;
  const r = await syncColony(repo, "u", c.toDict(), T0 + 4000);
  assert.equal(r.accepted, true, r.reason);
});

test("I6: traps are disguised in the snapshot sent to the attacker", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 100, 40);
  const d = ColonyState.newDefault(T0);
  d.cells["0,1"] = { type: "trap", level: 1, build_end: 0, target_level: 1 };
  repo.seed("d", { trophies: 100, attacks: 0, crystals: 50, shield_until: null }, d.toDict(), T0);
  const f = await findOpponent(repo, "a", T0, rand, () => repo.newId());
  assert.ok(!Object.values(f.snapshot.cells).some((c: any) => c.type === "trap"));
  const row = await repo.getAttack(f.attack_id!);
  assert.equal(row!.snapshot.cells["0,1"].type, "trap", "server keeps the real snapshot");
});

test("practice attack: always a bot, no loot or trophies", async () => {
  const repo = new MemoryRepo();
  await seeded(repo, "a", 100, 300);
  await seeded(repo, "real", 100, 0, 2000);
  const f = await findOpponent(repo, "a", T0, rand, () => repo.newId(), true);
  assert.equal((await repo.getAttack(f.attack_id!))!.defender, null);
  assert.equal(f.bot?.practice, true);
  const r = await finishAttack(repo, "a", f.attack_id!, allCmds, -1, T0 + 10);
  assert.equal(r.result!.loot, 0);
  assert.equal(r.result!.trophies, 0);
  assert.equal((await repo.getPlayer("a"))!.trophies, 100);
  assert.equal((await stored(repo, "real")).energy, 2000);
});
