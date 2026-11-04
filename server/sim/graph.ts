// Node graph (port of sim/graph.gd). Deterministic ordering everywhere.
import * as Fx from "./fx.ts";

export type SimNode = {
  id: number; x: number; y: number; owner: number; garrison: number;
  prod_per_sec: number; tower: string; prod_acc: number; trap: number; tower_lvl: number;
};

const TOWERS = ["", "laser", "pulse"];
const num = (v: unknown, d = 0): number => (typeof v === "number" ? Math.trunc(v) : d);

export class SimGraph {
  private nodes = new Map<number, SimNode>();
  private adj = new Map<number, number[]>();

  addNode(id: number, x: number, y: number, owner: number, garrison: number, prodPerSec: number,
    tower = "", trap = 0, towerLvl = 1): void {
    if (!TOWERS.includes(tower)) throw new Error(`unknown tower: ${tower}`);
    this.nodes.set(id, {
      id, x, y, owner, garrison, prod_per_sec: prodPerSec, tower, prod_acc: 0,
      trap: Math.max(trap, 0), tower_lvl: Math.max(towerLvl, 1),
    });
    if (!this.adj.has(id)) this.adj.set(id, []);
  }

  link(a: number, b: number): void {
    if (!this.nodes.has(a) || !this.nodes.has(b) || a === b) throw new Error("bad link");
    const la = this.adj.get(a)!;
    if (!la.includes(b)) {
      la.push(b); la.sort((p, q) => p - q);
      const lb = this.adj.get(b)!;
      lb.push(a); lb.sort((p, q) => p - q);
    }
  }

  hasNode(id: number): boolean { return this.nodes.has(id); }
  node(id: number): SimNode { return this.nodes.get(id)!; }
  nodeIds(): number[] { return [...this.nodes.keys()].sort((a, b) => a - b); }
  neighbors(id: number): number[] { return [...this.adj.get(id)!]; }

  edgeLength(a: number, b: number): number {
    const na = this.node(a), nb = this.node(b);
    return Fx.dist(na.x, na.y, nb.x, nb.y);
  }

  /** Dijkstra; ties -> lower node id, lower predecessor id. [] when unreachable. */
  path(from: number, to: number): number[] {
    if (!this.nodes.has(from) || !this.nodes.has(to)) return [];
    const dist = new Map<number, number>([[from, 0]]);
    const prev = new Map<number, number>();
    const done = new Set<number>();
    for (;;) {
      let u = -1, best = 0;
      for (const id of this.nodeIds()) {
        if (done.has(id) || !dist.has(id)) continue;
        if (u === -1 || dist.get(id)! < best) { u = id; best = dist.get(id)!; }
      }
      if (u === -1 || u === to) break;
      done.add(u);
      for (const v of this.adj.get(u)!) {
        if (done.has(v)) continue;
        const nd = best + this.edgeLength(u, v);
        if (!dist.has(v) || nd < dist.get(v)! || (nd === dist.get(v)! && u < prev.get(v)!)) {
          dist.set(v, nd);
          prev.set(v, u);
        }
      }
    }
    if (!dist.has(to)) return [];
    const out = [to];
    let cur = to;
    while (cur !== from) { cur = prev.get(cur)!; out.push(cur); }
    return out.reverse();
  }

  toDict(): { nodes: SimNode[]; links: number[][] } {
    const nodes = this.nodeIds().map((id) => ({ ...this.node(id) }));
    const links: number[][] = [];
    for (const a of this.nodeIds()) for (const b of this.adj.get(a)!) if (a < b) links.push([a, b]);
    return { nodes, links };
  }

  static fromDict(d: any): SimGraph {
    const g = new SimGraph();
    for (const n of d.nodes) {
      g.addNode(num(n.id), num(n.x), num(n.y), num(n.owner), num(n.garrison), num(n.prod_per_sec),
        typeof n.tower === "string" ? n.tower : "", num(n.trap, 0), num(n.tower_lvl, 1));
      g.node(num(n.id)).prod_acc = num(n.prod_acc, 0);
    }
    for (const l of d.links) g.link(num(l[0]), num(l[1]));
    return g;
  }
}
