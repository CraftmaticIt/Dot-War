// Tower damage pass (port of sim/towers.gd). dmg = Fx dots per tick.
import * as Fx from "./fx.ts";
import { SPLASH_DMG, SPLASH_RANGE, type SimWorld, type Group } from "./world.ts";

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
      if (target) hit(target, dmgFor(world, target, dmg));
    } else {
      for (const g of world.groups) {
        if (g.owner === n.owner || g.count <= 0) continue;
        const p = pos.get(g.id)!;
        if (Fx.dist(n.x, n.y, p.x, p.y) <= spec.range) hit(g, dmgFor(world, g, dmg));
      }
    }
  }
  const alive: Group[] = [];
  for (const g of world.groups) {
    if (g.count > 0) alive.push(g);
    else {
      world.events.push({ type: "group_destroyed", group: g.id });
      if (g.kind === 3) splash(world, g, pos.get(g.id)!);
    }
  }
  world.groups = alive;
}

/** Splash group killed by towers: nodes of another non-neutral owner in range lose SPLASH_DMG. */
function splash(world: SimWorld, g: Group, p: { x: number; y: number }): void {
  const hitIds: number[] = [];
  for (const id of world.graph.nodeIds()) {
    const n = world.graph.node(id);
    if (n.owner > 0 && n.owner !== g.owner && Fx.dist(n.x, n.y, p.x, p.y) <= SPLASH_RANGE) {
      n.garrison = Math.max(0, n.garrison - SPLASH_DMG);
      hitIds.push(id);
    }
  }
  if (hitIds.length) world.events.push({ type: "splash", group: g.id, nodes: hitIds });
}

function dmgFor(world: SimWorld, g: Group, dmg: number): number {
  const d = shielded(world, g, dmg);
  return g.kind === 2 ? Fx.idiv(d, 2) : d;
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
