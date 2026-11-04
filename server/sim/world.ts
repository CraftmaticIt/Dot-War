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
export type SimEvent = Record<string, unknown> & { type: string };

const NUM_KEYS = ["tick", "owner", "from", "to", "percent"] as const;

export class SimWorld {
  graph: SimGraph;
  rng: SimRng;
  tick = 0;
  groups: Group[] = [];
  events: SimEvent[] = [];
  private q: Cmd[] = [];
  private bad: unknown[] = [];
  private nextGroupId = 0;

  constructor(graph: SimGraph, seed: number) {
    this.graph = graph;
    this.rng = new SimRng(seed);
  }

  /** Untrusted input: malformed commands are rejected on the next step, never thrown. */
  queue(cmd: any): void {
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
  }

  private applyCommands(): void {
    for (const c of this.bad) this.reject(c, "bad_cmd");
    this.bad = [];
    const keep: Cmd[] = [];
    for (const c of this.q) {
      if (c.tick === this.tick) this.applySend(c);
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
    g.progress += GROUP_SPEED;
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
    return parts.join("|");
  }

  /** FNV-1a 32-bit over UTF-8 bytes of canonical(). */
  stateHash(): number {
    let h = 0x811c9dc5;
    for (const b of new TextEncoder().encode(this.canonical())) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h;
  }
}
