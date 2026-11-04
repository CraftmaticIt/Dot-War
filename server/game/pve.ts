// PvE (port of pve/pve_level.gd and pve/pve_match.gd). Definitions in pve_levels.json, also read by Godot.
import PVE_JSON from "./pve_levels.json" with { type: "json" };
import * as B from "./buildings.ts";
import { SimGraph } from "../sim/graph.ts";
import { SimWorld } from "../sim/world.ts";
import { SimRng } from "../sim/rng.ts";
import { idiv } from "../sim/fx.ts";

export type PveNode = { id: number; x: number; y: number; role: string };
export type Wave = { tick: number; node: number; count: number; kind: number };
export type PveLevelDef = {
  id?: number; chapter?: number; name?: string; nodes: PveNode[]; links: number[][];
  allowed: Record<string, number>; level: number; waves: Wave[]; arena?: boolean; week?: number;
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

export const CAMPAIGN_TICKS = 12000;
export const ARENA_TAIL_TICKS = 2400;
export const WEEK_SECS = 604800;
export const MAX_COMMANDS = 2000;
export type PveCmd = { tick: number; from: number; to: number; percent: number };
export type PveResult = { stars: number; lost: number; score: number; waves_started: number; ticks: number };

export const starsFor = (coreLost: boolean, lost: number): number =>
  coreLost ? 0 : 1 + (lost <= 1 ? 1 : 0) + (lost === 0 ? 1 : 0);

/** PvE defense (port of pve/pve_match.gd): waves march on the core; the player may send dots
 *  from own nodes (never into or through a spawn); enemy-held nodes forward their garrison to the
 *  core every tick. Placement + player commands are the whole replay. */
export class PveMatch {
  world: SimWorld;
  over = false;
  commands: PveCmd[] = [];
  private cmds: PveCmd[] = [];
  private core: number;
  private start: number[];
  private spawns: Set<number>;
  private waves: Wave[];
  private limit: number;
  private wavesStarted = 0;
  private startedAtFall = -1;

  constructor(lvl: PveLevelDef, placement: Placement, seed: number) {
    this.world = buildWorld(lvl, placement, seed);
    this.core = coreId(lvl);
    this.start = playerNodes(lvl, placement);
    this.spawns = new Set(lvl.nodes.filter((n) => n.role === "spawn").map((n) => n.id));
    this.waves = lvl.waves ?? [];
    const last = this.waves.reduce((m, w) => Math.max(m, w.tick), 0);
    this.limit = lvl.arena ? last + ARENA_TAIL_TICKS : CAMPAIGN_TICKS;
  }

  send(from: number, to: number, percent: number): void {
    if (this.over) return;
    const c = { tick: this.world.tick, from, to, percent };
    this.commands.push(c);
    this.cmds.push(c);
  }

  /** Untrusted replay input: only well-formed {tick, from, to, percent} entries are kept. */
  loadCommands(cmds: unknown): void {
    if (!Array.isArray(cmds)) return;
    for (const c of cmds.slice(0, MAX_COMMANDS)) {
      if (c === null || typeof c !== "object") continue;
      const ks = ["tick", "from", "to", "percent"] as const;
      if (ks.some((k) => typeof (c as any)[k] !== "number" || !Number.isFinite((c as any)[k]))) continue;
      this.cmds.push({ tick: Math.trunc(c.tick), from: Math.trunc(c.from), to: Math.trunc(c.to), percent: Math.trunc(c.percent) });
    }
  }

  private touchesSpawn(from: number, to: number): boolean {
    if (this.spawns.has(from) || this.spawns.has(to)) return true;
    const g = this.world.graph;
    if (!g.hasNode(from) || !g.hasNode(to)) return false;
    return g.path(from, to).some((id) => this.spawns.has(id));
  }

  step(): void {
    if (this.over) return;
    const w = this.world, t = w.tick;
    const later: PveCmd[] = [];
    for (const c of this.cmds) {
      if (c.tick === t) {
        if (!this.touchesSpawn(c.from, c.to)) w.queue({ tick: t, type: "send", owner: PLAYER, from: c.from, to: c.to, percent: c.percent });
      } else if (c.tick > t) later.push(c);
    }
    this.cmds = later;
    for (const wv of this.waves) {
      if (wv.tick === t) {
        w.queue({ tick: t, type: "spawn", owner: ENEMY, node: wv.node, to: this.core, count: wv.count, kind: wv.kind });
        this.wavesStarted += 1;
      }
    }
    for (const id of w.graph.nodeIds()) {
      const n = w.graph.node(id);
      if (n.owner === ENEMY && !this.spawns.has(id) && n.garrison > 0 && id !== this.core) {
        w.queue({ tick: t, type: "send", owner: ENEMY, from: id, to: this.core, percent: 100 });
      }
    }
    w.step();
    if (w.graph.node(this.core).owner !== PLAYER) { this.startedAtFall = this.wavesStarted; this.over = true; }
    else if (this.wavesStarted === this.waves.length && !this.enemyAlive()) this.over = true;
    else if (w.tick >= this.limit) this.over = true;
  }

  private enemyAlive(): boolean {
    if (this.world.groups.some((g) => g.owner === ENEMY)) return true;
    for (const id of this.world.graph.nodeIds()) {
      const n = this.world.graph.node(id);
      if (n.owner === ENEMY && !this.spawns.has(id) && n.garrison > 0) return true;
    }
    return false;
  }

  result(): PveResult {
    const lost = this.start.filter((id) => this.world.graph.node(id).owner !== PLAYER).length;
    const coreLost = this.startedAtFall >= 0;
    return { stars: starsFor(coreLost, lost), lost, score: coreLost ? Math.max(0, this.startedAtFall - 1) : this.waves.length,
      waves_started: this.wavesStarted, ticks: this.world.tick };
  }
}

/** Runs to the end: {result, hash} (PvE vectors, server replay). */
export function runPve(lvl: PveLevelDef, placement: Placement, seed: number, cmds: unknown = []): { result: PveResult; hash: number } {
  const m = new PveMatch(lvl, placement, seed);
  m.loadCommands(cmds);
  while (!m.over) m.step();
  return { result: m.result(), hash: m.world.stateHash() };
}

export const weekIndex = (now: number): number => idiv(now - PVE.weekly.epoch, WEEK_SECS);

/** Weekly arena: wave i at tick 40 + i*wave_gap, count 8 + 3i, rng picks spawn then (i >= 3) kind. */
export function arenaLevel(week: number): PveLevelDef {
  const a = PVE.arena;
  const spawns = a.map.nodes.filter((n) => n.role === "spawn").map((n) => n.id).sort((x, y) => x - y);
  const rng = new SimRng(week + 1);
  const waves: Wave[] = [];
  for (let i = 0; i < a.max_waves; i++) {
    const node = spawns[rng.rangeI(spawns.length)];
    const kind = i < 3 ? 0 : rng.rangeI(4);
    waves.push({ tick: 40 + i * a.wave_gap, node, count: 8 + 3 * i, kind });
  }
  return { nodes: a.map.nodes, links: a.map.links, allowed: {}, level: 1, waves, arena: true, week };
}
