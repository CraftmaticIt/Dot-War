// Mirrors tests/unit/test_pve_level.gd.
import { test } from "node:test";
import assert from "node:assert/strict";
import * as B from "../game/buildings.ts";
import { PVE, level, validate, buildWorld, playerNodes } from "../game/pve.ts";

const l1 = () => level(1)!;

test("level lookup", () => {
  assert.equal(l1().id, 1);
  assert.equal(level(999), null);
});

test("validate accepts allowed placement", () => {
  assert.equal(validate(l1(), [{ slot: 2, type: "laser" }], false), "");
  assert.equal(validate(l1(), [], false), "");
});

test("validate rejects bad placements", () => {
  const bad: unknown[] = [
    [{ slot: 2, type: "laser" }, { slot: 2, type: "laser" }], [{ slot: 1, type: "laser" }], [{ slot: 9, type: "laser" }],
    [{ slot: 55, type: "laser" }], [{ slot: 2, type: "wall" }], [{ slot: 2, type: "core" }],
    [{ slot: "2", type: "laser" }], [{ slot: 2 }], ["x"], [{ slot: 2.5, type: "laser" }], "nope", null,
    [{ slot: 2, type: "__proto__" }], [{ slot: 2, type: "constructor" }],
  ];
  for (const p of bad) assert.equal(validate(l1(), p, false), "bad_placement", JSON.stringify(p));
});

test("validate counts limit", () => {
  const l = structuredClone(l1());
  l.nodes.push({ id: 3, x: 3000, y: 0, role: "slot" });
  assert.equal(validate(l, [{ slot: 2, type: "laser" }, { slot: 3, type: "laser" }], false), "bad_placement");
});

test("validate arena budget", () => {
  const a = PVE.arena;
  const lvl = { nodes: a.map.nodes, links: a.map.links, allowed: {}, level: 1, waves: [] } as any;
  const ok: any[] = [{ slot: 2, type: "laser" }, { slot: 3, type: "laser" }, { slot: 4, type: "pulse" }, { slot: 5, type: "laser" }];
  assert.equal(validate(lvl, ok, true), "");
  ok.push({ slot: 6, type: "trap" });
  assert.equal(validate(lvl, ok, true), "bad_placement");
});

test("build world and player nodes", () => {
  const p = [{ slot: 2, type: "laser" }];
  const g = buildWorld(l1(), p, 1).graph;
  assert.equal(g.node(1).owner, 1);
  assert.equal(g.node(1).garrison, B.garrison("core", 1));
  assert.equal(g.node(2).owner, 1);
  assert.equal(g.node(2).tower, "laser");
  assert.equal(g.node(9).owner, 2);
  assert.deepEqual(playerNodes(l1(), p), [1, 2]);
  assert.equal(buildWorld(l1(), [], 1).graph.node(2).owner, 0);
  assert.deepEqual(playerNodes(l1(), []), [1]);
});
