// Deterministic swarm simulation (port of sim/world.gd).
import * as Fx from "./fx.ts";
import { SimGraph } from "./graph.ts";
import { SimRng } from "./rng.ts";
import { applyTowers } from "./towers.ts";

export const TICK_HZ = 20;
export const GROUP_SPEED = 150;

export type Group = {
  id: number; owner: number; count: number; path: number[]; seg: number; progress: number; dmg_acc: number;
};
export type Cmd = { tick: number; type: "send"; owner: number; from: number; to: number; percent: number };
export type BoostCmd = { tick: number; type: "boost"; owner: number; booster: string; node: number };
export type Effect = { type: string; owner: number; node: number; until: number };
export const BOOST_TICKS: Record<string, number> = { rage: 160, shield: 120, emp: 80, split: 200 };
export const EMP_RANGE = 3000;
export type SimEvent = Record<string, unknown> & { type: string };

const NUM_KEYS = ["tick", "owner", "from", "to", "percent"] as const;

export class SimWorld {
  graph: SimGraph;
  rng: SimRng;
  tick = 0;
  groups: Group[] = [];
  events: SimEvent[] = [];
  effects: Effect[] = [];
  private q: (Cmd | BoostCmd)[] = [];
  private bad: unknown[] = [];
  private nextGroupId = 0;

  constructor(graph: SimGraph, seed: number) {
    this.graph = graph;
    this.rng = new SimRng(seed);
  }

  /** Untrusted input: malformed commands are rejected on the next step, never thrown. */
  queue(cmd: any): void {
    if (cmd !== null && typeof cmd === "object" && cmd.type === "boost") {
      if (typeof cmd.booster !== "string" || !Object.hasOwn(BOOST_TICKS, cmd.booster)) { this.bad.push(cmd); return; }
      const b: any = { type: "boost", booster: cmd.booster };
      for (const k of ["tick", "owner", "node"]) {
        if (typeof cmd[k] !== "number" || !Number.isFinite(cmd[k])) { this.bad.push(cmd); return; }
        b[k] = Math.trunc(cmd[k]);
      }
      this.q.push(b as BoostCmd);
      return;
    }
    if (cmd === null || typeof cmd !== "object" || cmd.type !== "send") { this.bad.push(cmd); return; }
    const clean: any = { type: "send" };
    for (const k of NUM_KEYS) {
      if (typeof cmd[k] !== "number" || !Number.isFinite(cmd[k])) { this.bad.push(cmd); return; }
      clean[k] = Math.trunc(cmd[k]);
    }
    this.q.push(clean as Cmd);
  }

  step(): void {
    this.events = [];
    this.applyCommands();
    this.produce();
    this.move();
    applyTowers(this);
    this.tick += 1;
    this.effects = this.effects.filter((e) => e.until > this.tick);
  }

  private applyCommands(): void {
    for (const c of this.bad) this.reject(c, "bad_cmd");
    this.bad = [];
    const keep: (Cmd | BoostCmd)[] = [];
    for (const c of this.q) {
      if (c.tick === this.tick) {
        if (c.type === "boost") this.applyBoost(c);
        else this.applySend(c);
      }
      else if (c.tick > this.tick) keep.push(c);
      else this.reject(c, "past_tick");
    }
    this.q = keep;
  }

  private applySend(c: Cmd): void {
    if (c.owner <= 0) return this.reject(c, "bad_owner");
    const g = this.graph;
    if (!g.hasNode(c.from) || !g.hasNode(c.to) || c.from === c.to) return this.reject(c, "bad_node");
    const n = g.node(c.from);
    if (n.owner !== c.owner) return this.reject(c, "not_owner");
    if (c.percent < 1 || c.percent > 100) return this.reject(c, "bad_percent");
    const p = g.path(c.from, c.to);
    if (p.length === 0) return this.reject(c, "no_path");
    const count = Fx.idiv(n.garrison * c.percent, 100);
    if (count <= 0) return this.reject(c, "empty");
    n.garrison -= count;
    const grp: Group = { id: this.nextGroupId++, owner: c.owner, count, path: p, seg: 0, progress: 0, dmg_acc: 0 };
    this.groups.push(grp);
    this.events.push({ type: "group_spawned", group: grp.id, owner: c.owner, count });
  }

  private applyBoost(c: BoostCmd): void {
    if (c.owner <= 0) return this.reject(c, "bad_owner");
    if (!this.graph.hasNode(c.node)) return this.reject(c, "bad_node");
    const e = { type: c.booster, owner: c.owner, node: c.node, until: this.tick + BOOST_TICKS[c.booster] };
    this.effects.push(e);
    this.events.push({ type: "boost_applied", booster: e.type, owner: e.owner, node: e.node });
  }

  hasEffect(type: string, owner: number, node: number): boolean {
    return this.effects.some((e) => e.type === type && e.owner === owner && e.node === node && this.tick < e.until);
  }

  towerSilenced(n: { x: number; y: number; owner: number }): boolean {
    for (const e of this.effects) {
      if (e.type === "emp" && e.owner !== n.owner && this.tick < e.until) {
        const t = this.graph.node(e.node);
        if (Fx.dist(n.x, n.y, t.x, t.y) <= EMP_RANGE) return true;
      }
    }
    return false;
  }

  private reject(cmd: unknown, reason: string): void {
    this.events.push({ type: "cmd_rejected", reason, cmd });
  }

  private produce(): void {
    for (const id of this.graph.nodeIds()) {
      const n = this.graph.node(id);
      if (n.owner === 0 || n.prod_per_sec <= 0) continue;
      n.prod_acc += n.prod_per_sec;
      while (n.prod_acc >= TICK_HZ) { n.garrison += 1; n.prod_acc -= TICK_HZ; }
    }
  }

  private move(): void {
    const alive: Group[] = [];
    for (const g of this.groups) if (!this.advance(g)) alive.push(g);
    this.groups = alive;
  }

  private advance(g: Group): boolean {
    const target = g.path[g.path.length - 1];
    g.progress += this.hasEffect("rage", g.owner, target) ? Fx.idiv(GROUP_SPEED * 3, 2) : GROUP_SPEED;
    for (;;) {
      const a = g.path[g.seg], b = g.path[g.seg + 1];
      const len = this.graph.edgeLength(a, b);
      if (g.progress < len) return false;
      g.progress -= len;
      g.seg += 1;
      const last = g.seg === g.path.length - 1;
      if (last || this.graph.node(b).owner !== g.owner) { this.arrive(g, b); return true; }
    }
  }

  private arrive(g: Group, nodeId: number): void {
    const n = this.graph.node(nodeId);
    this.events.push({ type: "group_arrived", group: g.id, node: nodeId });
    const si = this.effects.findIndex((e) => e.type === "split" && e.owner === g.owner && e.node === nodeId && this.tick < e.until);
    if (si >= 0) {
      g.count *= 2;
      this.effects.splice(si, 1);
      this.events.push({ type: "split_applied", group: g.id, node: nodeId });
    }
    if (n.owner === g.owner) { n.garrison += g.count; return; }
    if (n.trap > 0) {
      const kill = Math.min(n.trap, g.count);
      g.count -= kill;
      n.trap = 0;
      this.events.push({ type: "trap_triggered", node: nodeId, group: g.id, killed: kill });
      if (g.count === 0) return;
    }
    n.garrison -= g.count;
    if (n.garrison < 0) {
      n.owner = g.owner;
      n.garrison = -n.garrison;
      n.prod_acc = 0;
      this.events.push({ type: "node_captured", node: nodeId, owner: g.owner });
    }
  }

  groupPos(g: Group): { x: number; y: number } {
    const a = this.graph.node(g.path[g.seg]);
    const b = this.graph.node(g.path[g.seg + 1]);
    const len = this.graph.edgeLength(a.id, b.id);
    if (len === 0) return { x: a.x, y: a.y };
    return { x: a.x + Fx.idiv((b.x - a.x) * g.progress, len), y: a.y + Fx.idiv((b.y - a.y) * g.progress, len) };
  }

  canonical(): string {
    const parts = [`t${this.tick}`];
    for (const id of this.graph.nodeIds()) {
      const n = this.graph.node(id);
      let seg = `n${id},${n.owner},${n.garrison},${n.prod_acc}`;
      if (n.trap > 0) seg += `,t${n.trap}`;
      parts.push(seg);
    }
    for (const g of this.groups) {
      parts.push(`g${g.id},${g.owner},${g.count},${g.seg},${g.progress},${g.dmg_acc},${g.path.join("-")}`);
    }
    for (const e of this.effects) parts.push(`e${e.type},${e.owner},${e.node},${e.until}`);
    return parts.join("|");
  }

  /** FNV-1a 32-bit over UTF-8 bytes of canonical(). */
  stateHash(): number {
    let h = 0x811c9dc5;
    for (const b of new TextEncoder().encode(this.canonical())) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h;
  }
}
