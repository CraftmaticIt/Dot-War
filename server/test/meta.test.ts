import { test } from "node:test";
import assert from "node:assert/strict";
import * as M from "../game/meta.ts";

const EPOCH = M.DEFS.season.epoch, DAY = 86400;

test("league thresholds and names", () => {
  assert.deepEqual([0, 399, 400, 799, 800, 1200, 1599, 1600, 9999].map(M.leagueOf), [0, 0, 1, 1, 2, 3, 3, 4, 4]);
  assert.equal(M.DEFS.leagues[2].name, "Złoto");
});

test("season index, end and soft reset", () => {
  assert.equal(M.seasonIndex(EPOCH), 0);
  assert.equal(M.seasonIndex(EPOCH + 14 * DAY - 1), 0);
  assert.equal(M.seasonIndex(EPOCH + 14 * DAY), 1);
  assert.equal(M.seasonEnds(EPOCH + 5), EPOCH + 14 * DAY);
  assert.equal(M.seasonReset(900), 900);
  assert.equal(M.seasonReset(1600), 1300);
  assert.equal(M.seasonReset(1001), 1000);
});

test("daily quests: 3 distinct, deterministic per uid and day", () => {
  const a = M.dailyQuests("u1", 100), b = M.dailyQuests("u1", 100), c = M.dailyQuests("u1", 101);
  assert.deepEqual(a, b);
  assert.equal(a.list.length, 3);
  assert.equal(new Set(a.list.map((q) => q.id)).size, 3);
  assert.ok(a.list.every((q) => q.progress === 0 && !q.done));
});

test("events advance quests, complete once, all-done flag once", () => {
  let s = { day: 1, list: [{ id: "win1", progress: 0, done: false }, { id: "stars5", progress: 0, done: false }, { id: "boost2", progress: 0, done: false }] };
  let r = M.applyEvent(s, "stars", 3);
  assert.equal(r.state.list[1].progress, 3);
  assert.equal(r.completed.length, 0);
  r = M.applyEvent(r.state, "stars", 4);
  assert.equal(r.state.list[1].progress, 5, "capped at target");
  assert.deepEqual(r.completed.map((q) => q.id), ["stars5"]);
  r = M.applyEvent(r.state, "stars", 4);
  assert.equal(r.completed.length, 0, "no second reward");
  r = M.applyEvent(r.state, "attack_win", 1);
  assert.equal(r.allDone, false);
  r = M.applyEvent(r.state, "boost_used", 2);
  assert.equal(r.allDone, true);
  r = M.applyEvent(r.state, "boost_used", 2);
  assert.equal(r.allDone, false, "all-done reported only when it happens");
});

test("chest contents within ranges", () => {
  for (const x of [0, 0.3, 0.999]) {
    const c = M.rollChest(() => x);
    const n = Object.values(c.boosters).reduce((a, b) => a + b, 0);
    assert.ok(n >= 1 && n <= 2);
    assert.ok(c.crystals >= 5 && c.crystals <= 20);
    assert.ok(Object.keys(c.boosters).every((k) => k in M.DEFS.boosters));
  }
});

test("loadout validation", () => {
  assert.deepEqual(M.cleanLoadout(["rage", "emp", "nuke", 5, "rage", "split"]), ["rage", "emp", "rage"]);
  assert.deepEqual(M.cleanLoadout("x"), []);
  assert.deepEqual(M.loadoutNeeds(["rage", "rage", "emp"]), { rage: 2, emp: 1 });
});
