// Tower damage pass (port of sim/towers.gd). dmg = Fx dots per tick.
import * as Fx from "./fx.ts";
import type { SimWorld, Group } from "./world.ts";

export const SPECS: Record<string, { range: number; dmg: number }> = {
  laser: { range: 4000, dmg: 200 },
  pulse: { range: 2000, dmg: 60 },
};

export function applyTowers(world: SimWorld): void {
  if (world.groups.length === 0) return;
  const pos = new Map<number, { x: number; y: number }>();
  for (const g of world.groups) pos.set(g.id, world.groupPos(g));
  for (const id of world.graph.nodeIds()) {
    const n = world.graph.node(id);
    if (n.tower === "" || n.owner === 0 || world.towerSilenced(n)) continue;
    const spec = SPECS[n.tower];
    const dmg = Fx.idiv(spec.dmg * (2 + n.tower_lvl), 3);
    if (n.tower === "laser") {
      let target: Group | null = null;
      let best = 0;
      for (const g of world.groups) {
        if (g.owner === n.owner || g.count <= 0) continue;
        const p = pos.get(g.id)!;
        const d = Fx.dist(n.x, n.y, p.x, p.y);
        if (d <= spec.range && (target === null || d < best)) { target = g; best = d; }
      }
      if (target) hit(target, shielded(world, target, dmg));
    } else {
      for (const g of world.groups) {
        if (g.owner === n.owner || g.count <= 0) continue;
        const p = pos.get(g.id)!;
        if (Fx.dist(n.x, n.y, p.x, p.y) <= spec.range) hit(g, shielded(world, g, dmg));
      }
    }
  }
  const alive: Group[] = [];
  for (const g of world.groups) {
    if (g.count > 0) alive.push(g);
    else world.events.push({ type: "group_destroyed", group: g.id });
  }
  world.groups = alive;
}

function shielded(world: SimWorld, g: Group, dmg: number): number {
  return world.hasEffect("shield", g.owner, g.path[g.path.length - 1]) ? Fx.idiv(dmg * 2, 5) : dmg;
}

function hit(g: Group, dmg: number): void {
  g.dmg_acc += dmg;
  if (g.dmg_acc >= Fx.ONE) {
    g.count -= Fx.idiv(g.dmg_acc, Fx.ONE);
    g.dmg_acc = g.dmg_acc % Fx.ONE;
  }
}
