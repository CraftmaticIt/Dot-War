// Battle world = defender snapshot + 3 attacker entries (port of battle/attack_setup.gd).
import * as Fx from "../sim/fx.ts";
import { SimGraph } from "../sim/graph.ts";
import { SimWorld } from "../sim/world.ts";

export const ATTACKER = 1, DEFENDER = 2;
export const ENTRY_IDS = [1001, 1002, 1003];
/** Each attacker entry base produces this many dots per second during the battle. */
export const ENTRY_PROD = 1;
export const ENTRY_GAP = 6000, MIN_SPREAD = 8000;

export function buildAttack(defender: SimGraph, attackerDots: number, seed: number): SimWorld {
  const g = SimGraph.fromDict(defender.toDict());
  const ids = g.nodeIds();
  let minX = 0, minY = 0, maxY = 0;
  ids.forEach((id, i) => {
    const n = g.node(id);
    if (i === 0 || n.x < minX) minX = n.x;
    if (i === 0 || n.y < minY) minY = n.y;
    if (i === 0 || n.y > maxY) maxY = n.y;
  });
  let ys: number[];
  if (maxY - minY < MIN_SPREAD) {
    const c = Fx.idiv(minY + maxY, 2);
    ys = [c - MIN_SPREAD / 2, c, c + MIN_SPREAD / 2];
  } else {
    ys = [minY, minY + Fx.idiv(maxY - minY, 2), maxY];
  }
  const share = Fx.idiv(attackerDots, 3), rest = attackerDots % 3;
  ENTRY_IDS.forEach((eid, i) => {
    const x = minX - ENTRY_GAP;
    g.addNode(eid, x, ys[i], ATTACKER, share + (i < rest ? 1 : 0), ENTRY_PROD);
    const scored = ids.map((id) => [Fx.dist(x, ys[i], g.node(id).x, g.node(id).y), id]);
    scored.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    for (const [, id] of scored.slice(0, 2)) g.link(eid, id);
  });
  return new SimWorld(g, seed);
}
