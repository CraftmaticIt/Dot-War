// Mirrors tests/unit/test_kinds_spawn.gd (enemy kinds + PvE spawn command).
import { test } from "node:test";
import assert from "node:assert/strict";
import { SimGraph } from "../sim/graph.ts";
import { SimWorld } from "../sim/world.ts";

function line(tower = ""): SimWorld {
  const g = new SimGraph();
  g.addNode(1, 0, 0, 1, 50, 0, tower);
  g.addNode(2, 6000, 0, 0, 0, 0);
  g.addNode(9, 12000, 0, 2, 0, 0);
  g.link(1, 2); g.link(2, 9);
  return new SimWorld(g, 1);
}
const spawn = (w: SimWorld, c: any) => w.queue({ tick: 0, type: "spawn", owner: 2, node: 9, to: 1, count: 5, kind: 0, ...c });
const rejected = (w: SimWorld) => w.events.filter((e) => e.type === "cmd_rejected").map((e) => e.reason);

test("spawn rejections incl. owner 0 and missing keys", () => {
  for (const [c, reason] of [[{ count: 0 }, "empty"], [{ kind: 4 }, "bad_kind"], [{ owner: 1 }, "not_owner"],
    [{ node: 77 }, "bad_node"], [{ owner: 0 }, "bad_owner"], [{ kind: undefined }, "bad_cmd"], [{ count: "5" }, "bad_cmd"]] as const) {
    const w = line();
    spawn(w, c);
    w.step();
    assert.deepEqual(rejected(w), [reason], JSON.stringify(c));
    assert.equal(w.groups.length, 0);
  }
});

test("fast moves 3/2, and 3/2 again under rage", () => {
  const w = line();
  spawn(w, { kind: 1 });
  for (let i = 0; i < 10; i++) w.step();
  assert.equal(w.groups[0].progress, 2250);
  const r = line();
  spawn(r, { kind: 1 });
  r.queue({ tick: 0, type: "boost", owner: 2, booster: "rage", node: 1 });
  for (let i = 0; i < 4; i++) r.step();
  assert.equal(r.groups[0].progress, 4 * 337);
});

test("splash: only on tower death, only nearby non-neutral enemy nodes, never below zero", () => {
  const g = new SimGraph();
  g.addNode(1, 0, 0, 1, 50, 0, "laser");
  g.addNode(2, 2500, 1000, 1, 3, 0);      // in range: 3 -> 0 (not -2)
  g.addNode(3, 2500, -1000, 0, 4, 0);     // neutral: untouched
  g.addNode(9, 6000, 0, 2, 0, 0);
  g.link(1, 9); g.link(1, 2); g.link(1, 3);
  const w = new SimWorld(g, 1);
  w.queue({ tick: 0, type: "spawn", owner: 2, node: 9, to: 1, count: 1, kind: 3 });
  let splash: any = null;
  for (let i = 0; i < 60 && !splash; i++) { w.step(); splash = w.events.find((e) => e.type === "splash"); }
  assert.deepEqual(splash?.nodes, [2]);
  assert.equal(w.graph.node(2).garrison, 0);
  assert.equal(w.graph.node(3).garrison, 4);
});

test("canonical carries ,k only for non-normal kinds", () => {
  const w = line();
  spawn(w, { kind: 0 });
  spawn(w, { kind: 2 });
  w.step();
  const segs = w.canonical().split("|").filter((s) => s.startsWith("g"));
  assert.ok(!segs[0].includes(",k"));
  assert.ok(segs[1].endsWith(",k2"));
});
