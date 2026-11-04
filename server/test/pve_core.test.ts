import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryRepo } from "../core/repo.ts";
import { finishPve, pveRanking, GRACE_SECS } from "../core/pve.ts";
import { profile } from "../core/profile.ts";
import { PVE, weekIndex, WEEK_SECS } from "../game/pve.ts";

const NOW = PVE.weekly.epoch + 3 * WEEK_SECS + 1000;   // week 3
const SOL1 = [{ slot: 2, type: "laser" }];
const crystals = async (r: MemoryRepo, id: string) => (await r.getPlayer(id))!.crystals;

test("level 1 solution: 3 stars, 15 crystals once; worse run keeps stars", async () => {
  const repo = new MemoryRepo();
  await repo.ensurePlayer("u", NOW);
  const r = await finishPve(repo, "u", { level: 1, placement: SOL1 }, NOW);
  assert.equal(r.stars, 3);
  assert.equal(r.gained, 3);
  assert.equal(r.crystals, 15);
  assert.equal(await crystals(repo, "u"), 50 + 15);
  assert.equal((await finishPve(repo, "u", { level: 1, placement: SOL1 }, NOW)).gained, 0);
  assert.equal((await finishPve(repo, "u", { level: 1, placement: [] }, NOW)).stars, 0);
  assert.equal(await crystals(repo, "u"), 65);
  assert.deepEqual((await profile(repo, "u", NOW)).pve, { "1": 3 });
});

test("parallel finishes grant crystals once", async () => {
  const repo = new MemoryRepo();
  await repo.ensurePlayer("u", NOW);
  await Promise.all([1, 2, 3].map(() => finishPve(repo, "u", { level: 1, placement: SOL1 }, NOW)));
  assert.equal(await crystals(repo, "u"), 65);
});

test("bad input: placement, level, locked level, week", async () => {
  const repo = new MemoryRepo();
  await repo.ensurePlayer("u", NOW);
  assert.equal((await finishPve(repo, "u", { level: 1, placement: [{ slot: 2, type: "wall" }] }, NOW)).error, "bad_placement");
  assert.equal((await finishPve(repo, "u", { level: 999, placement: [] }, NOW)).error, "bad_level");
  assert.equal((await finishPve(repo, "u", { level: "1", placement: [] }, NOW)).error, "bad_level");
  assert.equal((await finishPve(repo, "u", { level: 2, placement: [] }, NOW)).error, "locked");
  assert.equal((await finishPve(repo, "u", { week: weekIndex(NOW) - 2, placement: [] }, NOW)).error, "bad_week");
  assert.equal((await finishPve(repo, "u", { week: weekIndex(NOW), placement: "x" }, NOW)).error, "bad_placement");
  assert.equal(await crystals(repo, "u"), 50);
  assert.deepEqual(await repo.pveStars("u"), {});
});

test("arena keeps the best score and ranks players", async () => {
  const repo = new MemoryRepo();
  const wk = weekIndex(NOW);
  const weak = [{ slot: 2, type: "laser" }];
  const strong = [{ slot: 2, type: "laser" }, { slot: 5, type: "laser" }, { slot: 3, type: "pulse" }, { slot: 4, type: "laser" }];
  for (const id of ["a", "b"]) await repo.ensurePlayer(id, NOW);
  const s1 = await finishPve(repo, "a", { week: wk, placement: strong }, NOW);
  const s2 = await finishPve(repo, "a", { week: wk, placement: weak }, NOW);
  assert.ok(s1.score > s2.score);
  assert.equal(s2.best, s1.score);
  await finishPve(repo, "b", { week: wk, placement: weak }, NOW);
  const rk = await pveRanking(repo, "b", NOW);
  assert.equal(rk.week, wk);
  assert.equal(rk.top[0].name, "Gracz #a");
  assert.equal(rk.top[0].score, s1.score);
  assert.deepEqual(rk.me, { score: s2.score, rank: 2 });
  assert.equal((await pveRanking(repo, "zz", NOW)).me, null);
});

test("weekly settlement: top 10% rewarded once; zero scores never", async () => {
  const repo = new MemoryRepo();
  const prev = weekIndex(NOW) - 1;
  for (let i = 0; i < 20; i++) {
    const id = `p${String(i).padStart(2, "0")}`;
    await repo.ensurePlayer(id, NOW);
    await repo.pveWeekRecord(id, prev, i + 1);          // p19 best, p18 second
  }
  await repo.ensurePlayer("z", NOW);
  await repo.pveWeekRecord("z", prev, 0);
  const later = NOW + GRACE_SECS;                     // past the grace period of the previous week
  await pveRanking(repo, "p00", later);
  const rw = PVE.weekly.reward;
  assert.equal(await crystals(repo, "p19"), 50 + rw.crystals);
  assert.equal(await crystals(repo, "p18"), 50 + rw.crystals);
  assert.equal(await crystals(repo, "p17"), 50);
  assert.equal((await repo.getPlayer("p19"))!.boosters.split, 1 + rw.boosters.split);
  await pveRanking(repo, "p00", later);
  assert.equal(await crystals(repo, "p19"), 50 + rw.crystals, "settled once");
  const r2 = new MemoryRepo();
  await r2.ensurePlayer("z", NOW);
  await r2.pveWeekRecord("z", prev, 0);
  await pveRanking(r2, "z", NOW + GRACE_SECS);
  assert.equal(await crystals(r2, "z"), 50);
});

test("arena: last week's run is accepted within the grace period, not after", async () => {
  const repo = new MemoryRepo();
  await repo.ensurePlayer("u", NOW);
  const start = PVE.weekly.epoch + 4 * WEEK_SECS;            // week 4 begins
  const p = [{ slot: 2, type: "laser" }];
  assert.ok(!(await finishPve(repo, "u", { week: 3, placement: p }, start + 600)).error, "10 min after rollover");
  assert.equal((await finishPve(repo, "u", { week: 3, placement: p }, start + GRACE_SECS + 1)).error, "bad_week");
});

test("settlement waits for the grace period and catches up on skipped weeks", async () => {
  const repo = new MemoryRepo();
  for (const id of ["a", "b"]) await repo.ensurePlayer(id, NOW);
  await repo.pveWeekRecord("a", 1, 5);                       // nobody opened the ranking in week 2
  await repo.pveWeekRecord("b", 2, 7);
  const start3 = PVE.weekly.epoch + 3 * WEEK_SECS;
  await pveRanking(repo, "a", start3 + 60);                  // week 2 still in grace
  assert.equal((await repo.getPlayer("a"))!.crystals, 50 + PVE.weekly.reward.crystals, "week 1 settled late");
  assert.equal((await repo.getPlayer("b"))!.crystals, 50, "week 2 not yet");
  await pveRanking(repo, "a", start3 + GRACE_SECS + 1);
  assert.equal((await repo.getPlayer("b"))!.crystals, 50 + PVE.weekly.reward.crystals);
});
