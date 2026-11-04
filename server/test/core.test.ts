import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryRepo, type Player } from "../core/repo.ts";
import { syncColony } from "../core/sync.ts";
import { findOpponent, ABANDON_SECS } from "../core/matchmaking.ts";
import { finishAttack } from "../core/finish.ts";
import { ColonyState } from "../game/colony.ts";

const T0 = 1_800_000_000, H = 3600;
const rand = () => 0.42;

function player(id: string, trophies = 0, crystals = 50): Player {
  return { id, trophies, attacks: 0, crystals, shield_until: null };
}
async function setup(repo: MemoryRepo, id: string, trophies = 0, dots = 0, energy = 500) {
  const c = ColonyState.newDefault(T0);
  c.dots = dots;
  c.energy = energy;
  c.cells["0,1"] = { type: "generator", level: 1, build_end: 0, target_level: 1 };
  const { id: _, ...rest } = player(id, trophies);
  repo.seed(id, rest, c.toDict(), T0);
  return c;
}

test("first sync accepted, server fields from players", async () => {
  const repo = new MemoryRepo();
  const c = ColonyState.newDefault(T0);
  c.trophies = 999; c.crystals = 9999;
  const r = await syncColony(repo, "u1", c.toDict(), T0);
  assert.equal(r.accepted, true);
  assert.equal(r.colony.trophies, 0);
  assert.equal(r.colony.crystals, 50);
  assert.ok(await repo.getColony("u1"));
});

test("inflated energy rejected", async () => {
  const repo = new MemoryRepo();
  const c = await setup(repo, "u1");
  c.energy = 100000;
  const r = await syncColony(repo, "u1", c.toDict(), T0 + 60);
  assert.equal(r.accepted, false);
  assert.equal(r.colony.energy, 500);
});

test("inflated dots and crystals rejected", async () => {
  const repo = new MemoryRepo();
  const c = await setup(repo, "u1");
  c.dots = 40;
  assert.equal((await syncColony(repo, "u1", c.toDict(), T0 + 60)).accepted, false);
  const d = ColonyState.fromDict((await repo.getColony("u1"))!.data)!;
  d.crystals = 51;
  const r = await syncColony(repo, "u1", d.toDict(), T0 + 60);
  assert.equal(r.colony.crystals, 50, "crystals are server-owned: clamped, never raised");
  assert.equal((await repo.getPlayer("u1"))!.crystals, 50);
});

test("server fields overwritten on accept", async () => {
  const repo = new MemoryRepo();
  const c = await setup(repo, "u1", 120);
  c.trophies = 5000; c.attacks = 77;
  const r = await syncColony(repo, "u1", c.toDict(), T0 + 10);
  assert.equal(r.accepted, true);
  assert.equal(r.colony.trophies, 120);
  assert.equal(r.colony.attacks, 0);
});

test("level jump and finished build without time rejected", async () => {
  const repo = new MemoryRepo();
  const c = await setup(repo, "u1", 0, 0, 5000);
  const jump = ColonyState.fromDict(c.toDict())!;
  jump.cells["1,0"] = { type: "mine", level: 3, build_end: 0, target_level: 3 };
  assert.equal((await syncColony(repo, "u1", jump.toDict(), T0 + 8 * H)).reason, "core_limit", "mine above core level");
  const instant = ColonyState.fromDict(c.toDict())!;
  instant.cells["0,0"] = { type: "core", level: 2, build_end: 0, target_level: 2 };  // 300 s build, 10 s later, no crystals
  instant.energy -= 1000;
  assert.equal((await syncColony(repo, "u1", instant.toDict(), T0 + 10)).accepted, false);
});

test("legit progress accepted (8h of mine + generator, one build)", async () => {
  const repo = new MemoryRepo();
  const c = await setup(repo, "u1", 0, 0, 500);
  c.collect(T0 + 8 * H);
  c.cells["-1,0"] = { type: "wall", level: 0, build_end: T0 + 8 * H + 5, target_level: 1 };
  c.energy -= 50;
  const r = await syncColony(repo, "u1", c.toDict(), T0 + 8 * H);
  assert.equal(r.accepted, true, r.reason);
  assert.equal(r.colony.cells["-1,0"].target_level, 1);
});

test("speedup with crystals accepted and crystals persisted", async () => {
  const repo = new MemoryRepo();
  const c = await setup(repo, "u1", 0, 0, 5000);
  c.cells["0,0"] = { type: "core", level: 2, build_end: 0, target_level: 2 };
  c.energy -= 1000;
  c.crystalsSpent = 5;
  const r = await syncColony(repo, "u1", c.toDict(), T0 + 10);
  assert.equal(r.accepted, true, r.reason);
  assert.equal((await repo.getPlayer("u1"))!.crystals, 45);
});

test("match within 200 trophies", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "att", 300, 40);
  await setup(repo, "far", 800);
  await setup(repo, "near", 450);
  const r = await findOpponent(repo, "att", T0 + 10, rand, () => repo.newId());
  assert.equal(r.error, undefined);
  assert.equal((await repo.getAttack(r.attack_id!))!.defender, "near");
  assert.equal(r.dots, 40);
  assert.equal(ColonyState.fromDict((await repo.getColony("att"))!.data)!.dots, 0, "dots spent");
});

test("skips shielded and already attacked; two attackers get different defenders", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "a1", 100, 40);
  await setup(repo, "a2", 100, 40);
  await setup(repo, "d1", 100);
  await setup(repo, "d2", 100);
  await setup(repo, "sh", 100);
  repo.players.get("sh")!.shield_until = T0 + H;
  const r1 = await findOpponent(repo, "a1", T0 + 10, rand, () => repo.newId());
  const r2 = await findOpponent(repo, "a2", T0 + 10, rand, () => repo.newId());
  const d1 = (await repo.getAttack(r1.attack_id!))!.defender;
  const d2 = (await repo.getAttack(r2.attack_id!))!.defender;
  assert.notEqual(d1, null);
  assert.notEqual(d2, null);
  assert.notEqual(d1, d2);
  assert.ok(d1 !== "sh" && d2 !== "sh");
});

test("fallback bot and few dots", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "solo", 0, 25);
  const r = await findOpponent(repo, "solo", T0 + 10, rand);
  assert.ok(r.bot);
  assert.equal((await repo.getAttack(r.attack_id!))!.defender, null);
  await setup(repo, "poor", 0, 5);
  assert.equal((await findOpponent(repo, "poor", T0 + 10, rand)).error, "few_dots");
});

test("abandoned attack resolved as loss", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "a", 50, 40);
  const r = await findOpponent(repo, "a", T0, rand);
  await setup(repo, "x", 50);  // unrelated sync later
  await findOpponent(repo, "x", T0 + ABANDON_SECS + 1, rand);
  assert.equal((await repo.getAttack(r.attack_id!))!.status, "abandoned");
  assert.equal((await repo.getPlayer("a"))!.trophies, 42);
});

test("finish replays, scores and is idempotent; foreign attack forbidden", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "a", 0, 300);
  const f = await findOpponent(repo, "a", T0, rand);
  const cmds = [1001, 1002, 1003].map((e) => ({ tick: 0, from: e, to: 1, percent: 100 }));
  const r1 = await finishAttack(repo, "a", f.attack_id!, cmds, -1, T0 + 100);
  assert.equal(r1.error, undefined);
  const again = await finishAttack(repo, "a", f.attack_id!, [], -1, T0 + 200);
  assert.deepEqual(again.result, r1.result, "idempotent");
  const p = (await repo.getPlayer("a"))!;
  assert.equal(p.trophies, Math.max(0, r1.result!.trophies));
  assert.equal((await finishAttack(repo, "intruder", f.attack_id!, [], -1, T0)).error, "forbidden");
});

test("defender loses loot, trophies, gets shield", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "a", 100, 400);
  await setup(repo, "d", 100, 0, 1000);
  const f = await findOpponent(repo, "a", T0, rand);
  assert.equal(f.loot_pool, 800, "80% of defender energy");
  const all = [1001, 1002, 1003].flatMap((e) => [0, 200, 400, 600].map((t) => ({ tick: t, from: e, to: 1, percent: 100 })));
  const r = await finishAttack(repo, "a", f.attack_id!, all, -1, T0 + 100);
  if (r.result!.stars >= 1) {
    const d = (await repo.getPlayer("d"))!;
    assert.equal(d.shield_until, T0 + 100 + 8 * H);
    const dc = ColonyState.fromDict((await repo.getColony("d"))!.data)!;
    assert.equal(dc.energy, 1000 - r.result!.loot);
    assert.ok(d.trophies <= 100);
  } else {
    assert.equal((await repo.getPlayer("d"))!.shield_until, null);
  }
});

test("malformed commands ignored, no crash", async () => {
  const repo = new MemoryRepo();
  await setup(repo, "a", 0, 50);
  const f = await findOpponent(repo, "a", T0, rand);
  const r = await finishAttack(repo, "a", f.attack_id!, [null, 5, { tick: "x" }, { tick: 0, from: "1001" }] as any, -1, T0 + 10);
  assert.equal(r.error, undefined);
  assert.equal(r.result!.stars, 0);
  const r2 = await finishAttack(repo, "a", "nope", "garbage" as any, -1, T0);
  assert.equal(r2.error, "not_found");
});
