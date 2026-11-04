// PvE (port of pve/pve_level.gd and pve/pve_match.gd). Definitions in pve_levels.json, also read by Godot.
import PVE_JSON from "./pve_levels.json" with { type: "json" };
import * as B from "./buildings.ts";
import { SimGraph } from "../sim/graph.ts";
import { SimWorld } from "../sim/world.ts";

export type PveNode = { id: number; x: number; y: number; role: string };
export type Wave = { tick: number; node: number; count: number; kind: number };
export type PveLevelDef = {
  id?: number; chapter?: number; name?: string; nodes: PveNode[]; links: number[][];
  allowed: Record<string, number>; level: number; waves: Wave[];
};
export type Placement = { slot: number; type: string }[];
export const PVE = PVE_JSON as unknown as {
  star_crystals: number;
  weekly: { epoch: number; top_pct: number; reward: { crystals: number; boosters: Record<string, number> } };
  arena: { budget: number; costs: Record<string, number>; wave_gap: number; max_waves: number;
    map: { nodes: PveNode[]; links: number[][] } };
  levels: PveLevelDef[];
};
export const PLAYER = 1, ENEMY = 2;
const TYPES = ["laser", "pulse", "wall", "trap"];

export const level = (id: number): PveLevelDef | null => PVE.levels.find((l) => l.id === id) ?? null;

/** "" or "bad_placement". Campaign: counts within `allowed`; arena: total cost within the budget. */
export function validate(lvl: PveLevelDef, placement: unknown, arena: boolean): string {
  if (!Array.isArray(placement)) return "bad_placement";
  const roles = new Map(lvl.nodes.map((n) => [n.id, n.role]));
  const used = new Set<number>();
  const counts: Record<string, number> = {};
  let cost = 0;
  for (const e of placement) {
    if (e === null || typeof e !== "object" || typeof e.type !== "string" || !Number.isInteger(e.slot)) return "bad_placement";
    const t: string = e.type;
    if (roles.get(e.slot) !== "slot" || used.has(e.slot) || !TYPES.includes(t)) return "bad_placement";
    used.add(e.slot);
    counts[t] = (counts[t] ?? 0) + 1;
    if (arena) {
      if (!Object.hasOwn(PVE.arena.costs, t)) return "bad_placement";
      cost += PVE.arena.costs[t];
    } else if (counts[t] > (Object.hasOwn(lvl.allowed, t) ? lvl.allowed[t] : 0)) return "bad_placement";
  }
  return arena && cost > PVE.arena.budget ? "bad_placement" : "";
}

/** Assumes a validated placement. */
export function buildWorld(lvl: PveLevelDef, placement: Placement, seed: number): SimWorld {
  const L = lvl.level ?? 1;
  const types = new Map(placement.map((e) => [e.slot, e.type]));
  const g = new SimGraph();
  for (const n of lvl.nodes) {
    if (n.role === "core") g.addNode(n.id, n.x, n.y, PLAYER, B.garrison("core", L), B.battleProd("core", L));
    else if (n.role === "spawn") g.addNode(n.id, n.x, n.y, ENEMY, 0, 0);
    else if (types.has(n.id)) {
      const t = types.get(n.id)!;
      g.addNode(n.id, n.x, n.y, PLAYER, B.garrison(t, L), B.battleProd(t, L), B.tower(t), B.trapDmg(t, L), L);
    } else g.addNode(n.id, n.x, n.y, 0, 0, 0);
  }
  for (const [a, b] of lvl.links) g.link(a, b);
  return new SimWorld(g, seed);
}

export const coreId = (lvl: PveLevelDef): number => lvl.nodes.find((n) => n.role === "core")?.id ?? -1;

export const playerNodes = (lvl: PveLevelDef, placement: Placement): number[] =>
  [coreId(lvl), ...placement.map((e) => e.slot)].sort((a, b) => a - b);
