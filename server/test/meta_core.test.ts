import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryRepo } from "../core/repo.ts";
import { syncColony } from "../core/sync.ts";
import { findOpponent } from "../core/matchmaking.ts";
import { finishAttack } from "../core/finish.ts";
import { profile } from "../core/profile.ts";
import { shopBuy } from "../core/shop.ts";
import { ColonyState } from "../game/colony.ts";
import { DEFS, dayIndex } from "../game/meta.ts";

const T0 = DEFS.season.epoch + 3 * 86400, H = 3600;
const rand = () => 0.42;
const cmds = [1001, 1002, 1003].flatMap((e) => [0, 100, 200].map((t) => ({ tick: t, from: e, to: 1, percent: 100 })));

function seeded(repo: MemoryRepo, id: string, o: { trophies?: number; dots?: number; crystals?: number; season?: number } = {}) {
  const c = ColonyState.newDefault(T0);
  c.cells["0,1"] = { type: "generator", level: 1, build_end: 0, target_level: 1 };
  c.dots = o.dots ?? 0;
  c.crystals = o.crystals ?? 50;
  repo.seed(id, { trophies: o.trophies ?? 0, attacks: 0, crystals: o.crystals ?? 50, shield_until: null,
    boosters: { ...DEFS.start_boosters }, season: o.season ?? 0, quests: null, quests_rev: 0, last_reward: null }, c.toDict(), T0);
  return c;
}

test("new player profile: start boosters, league, 3 quests", async () => {
  const repo = new MemoryRepo();
  const pr = await profile(repo, "u", T0);
  assert.deepEqual(pr.boosters, DEFS.start_boosters);
  assert.equal(pr.league, 0);
  assert.equal(pr.quests.length, 3);
  assert.ok(pr.quests.every((q: any) => typeof q.text === "string" && q.target > 0));
});

test("season settles once, even in parallel", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { trophies: 1600, season: 0, crystals: 50 });
  const later = DEFS.season.epoch + 15 * 86400;
  const prs = await Promise.all([1, 2, 3].map(() => profile(repo, "u", later)));
  const p = (await repo.getPlayer("u"))!;
  assert.equal(p.crystals, 50 + 200, "Diament reward once");
  assert.equal(p.trophies, 1300, "soft reset");
  assert.equal(p.season, 1);
  assert.equal(prs[0].last_reward?.reward, 200);
  assert.equal(ColonyState.fromDict((await repo.getColony("u"))!.data)!.crystals, 250, "colony mirror updated");
});

test("parallel buys: only affordable ones succeed", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { crystals: 30 });
  const rs = await Promise.all([1, 2, 3].map(() => shopBuy(repo, "u", "rage", T0)));
  assert.equal(rs.filter((r) => !r.error).length, 2);
  assert.equal(rs.filter((r) => r.error === "no_crystals").length, 1);
  const p = (await repo.getPlayer("u"))!;
  assert.equal(p.crystals, 0);
  assert.equal(p.boosters.rage, 3);
  assert.equal((await shopBuy(repo, "u", "nuke", T0)).error, "bad_item");
});

test("bought crystals spend is not charged again on the next sync", async () => {
  const repo = new MemoryRepo();
  const c = seeded(repo, "u", { crystals: 50 });
  await shopBuy(repo, "u", "rage", T0);
  c.crystals = 35;  // client adopted the profile after buying
  const s = await syncColony(repo, "u", c.toDict(), T0 + 10);
  assert.equal(s.colony.crystals, 35);
  assert.equal((await repo.getPlayer("u"))!.crystals, 35);
});

test("find without the boosters is rejected and spends nothing", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { dots: 40 });
  const r = await findOpponent(repo, "u", T0, rand, () => repo.newId(), false, ["split", "split"]);
  assert.equal(r.error, "no_boosters");
  const p = (await repo.getPlayer("u"))!;
  assert.equal(p.boosters.split, 1);
  assert.equal(ColonyState.fromDict((await repo.getColony("u"))!.data)!.dots, 40);
});

test("few dots refunds the loadout", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { dots: 3 });
  assert.equal((await findOpponent(repo, "u", T0, rand, () => repo.newId(), false, ["rage"])).error, "few_dots");
  assert.equal((await repo.getPlayer("u"))!.boosters.rage, 1);
});

test("loadout spent, replayed and counted for quests; rewards once", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { dots: 300 });
  const f = await findOpponent(repo, "u", T0, rand, () => repo.newId(), false, ["rage", "emp"]);
  assert.deepEqual(f.loadout, ["rage", "emp"]);
  assert.equal((await repo.getPlayer("u"))!.boosters.rage, 0);
  const boosts = [{ tick: 5, type: "boost", booster: "rage", node: 1 }, { tick: 6, type: "boost", booster: "emp", node: 1 }];
  const r1 = await finishAttack(repo, "u", f.attack_id!, [...cmds, ...boosts], -1, T0 + 60);
  const crystalsAfter = (await repo.getPlayer("u"))!.crystals;
  const r2 = await finishAttack(repo, "u", f.attack_id!, [...cmds, ...boosts], -1, T0 + 70);
  assert.deepEqual(r2.result, r1.result);
  assert.equal((await repo.getPlayer("u"))!.crystals, crystalsAfter, "repeated finish grants nothing");
  const q = (await repo.getPlayer("u"))!.quests!;
  const boostQuest = q.list.find((x) => x.id === "boost2");
  if (boostQuest) assert.equal(boostQuest.progress, 2);
});

test("three-star attack gives a chest", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { dots: 900 });
  const f = await findOpponent(repo, "u", T0, rand, () => repo.newId());
  const all = [1001, 1002, 1003].flatMap((e) => Array.from({ length: 30 }, (_, i) => ({ tick: i * 100, from: e, to: 1, percent: 100 })));
  const before = (await repo.getPlayer("u"))!;
  const r = await finishAttack(repo, "u", f.attack_id!, all, -1, T0 + 60);
  if (r.result!.stars === 3) {
    assert.ok(r.rewards?.chest, "chest granted");
    const after = (await repo.getPlayer("u"))!;
    const sum = (b: Record<string, number>) => Object.values(b).reduce((a, x) => a + x, 0);
    assert.ok(sum(after.boosters) > sum(before.boosters));
  }
});

test("upgrade event from an accepted sync advances the quest", async () => {
  const repo = new MemoryRepo();
  const c = seeded(repo, "u");
  await profile(repo, "u", T0);
  const p0 = (await repo.getPlayer("u"))!;
  p0.quests = { day: dayIndex(T0), list: [{ id: "upgrade3", progress: 0, done: false }, { id: "win1", progress: 0, done: false }, { id: "stars5", progress: 0, done: false }] };
  repo.players.set("u", p0);
  c.energy = 5000;
  repo.colonies.get("u")!.data.energy = 5000;
  c.cells["0,0"] = { type: "core", level: 2, build_end: 0, target_level: 2 };
  c.energy -= 1000;
  const s = await syncColony(repo, "u", c.toDict(), T0 + 400);
  assert.equal(s.accepted, true, s.reason);
  assert.equal((await repo.getPlayer("u"))!.quests!.list[0].progress, 1);
});

test("practice attacks give no quest progress or chest", async () => {
  const repo = new MemoryRepo();
  seeded(repo, "u", { dots: 900 });
  await profile(repo, "u", T0);
  const before = JSON.stringify((await repo.getPlayer("u"))!.quests);
  const f = await findOpponent(repo, "u", T0, rand, () => repo.newId(), true, ["rage"]);
  assert.deepEqual(f.loadout, [], "practice ignores loadout");
  const r = await finishAttack(repo, "u", f.attack_id!, cmds, -1, T0 + 60);
  assert.equal(r.rewards?.chest ?? null, null);
  assert.equal(JSON.stringify((await repo.getPlayer("u"))!.quests), before);
});
