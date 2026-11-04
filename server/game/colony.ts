// Colony state subset needed by the server (port of meta/colony.gd):
// (de)serialisation, economy accrual, battle snapshot.
import * as B from "./buildings.ts";
import * as Hex from "./hex.ts";
import { idiv } from "../sim/fx.ts";
import { SimGraph } from "../sim/graph.ts";

export type Cell = { type: string; level: number; build_end: number; target_level: number };
export const SAVE_VERSION = 1;
export const OFFLINE_CAP_SECS = 8 * 3600;

const INT_FIELDS: [string, keyof ColonyState][] = [
  ["energy", "energy"], ["crystals", "crystals"], ["dots", "dots"], ["last_collect", "lastCollect"],
  ["energy_rem", "energyRem"], ["dots_rem", "dotsRem"], ["trophies", "trophies"], ["attacks", "attacks"],
  ["attack_open", "attackOpen"],
];
const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

export class ColonyState {
  cells: Record<string, Cell> = {};
  energy = 0; crystals = 0; dots = 0; lastCollect = 0; energyRem = 0; dotsRem = 0;
  trophies = 0; attacks = 0; attackOpen = 0;

  static newDefault(now: number): ColonyState {
    const c = new ColonyState();
    c.cells[Hex.key(0, 0)] = { type: "core", level: 1, build_end: 0, target_level: 1 };
    c.cells[Hex.key(1, 0)] = { type: "mine", level: 1, build_end: 0, target_level: 1 };
    c.energy = 500;
    c.crystals = 50;
    c.lastCollect = now;
    return c;
  }

  coreLevel(): number {
    for (const k in this.cells) if (this.cells[k].type === "core") return Math.max(this.cells[k].level, 1);
    return 1;
  }

  finishBuilds(now: number): void {
    for (const k in this.cells) {
      const c = this.cells[k];
      if (c.build_end !== 0 && c.build_end <= now) { c.level = c.target_level; c.build_end = 0; }
    }
  }

  energyCap(): number { let s = 0; for (const k in this.cells) s += B.energyCap(this.cells[k].type, this.cells[k].level); return s; }
  dotsCap(): number { let s = 0; for (const k in this.cells) s += B.dotsCap(this.cells[k].type, this.cells[k].level); return s; }
  rates(): { e: number; d: number } {
    let e = 0, d = 0;
    for (const k in this.cells) {
      e += B.energyPerHour(this.cells[k].type, this.cells[k].level);
      d += B.dotsPerHour(this.cells[k].type, this.cells[k].level);
    }
    return { e, d };
  }

  collect(now: number): { energy: number; dots: number; secs: number } {
    if (now <= this.lastCollect) { this.finishBuilds(now); return { energy: 0, dots: 0, secs: 0 }; }
    const start = Math.max(this.lastCollect, now - OFFLINE_CAP_SECS);
    this.finishBuilds(start);
    const points: number[] = [];
    for (const k in this.cells) {
      const be = this.cells[k].build_end;
      if (be > start && be < now && !points.includes(be)) points.push(be);
    }
    points.sort((a, b) => a - b);
    points.push(now);
    const e0 = this.energy, d0 = this.dots;
    let t0 = start;
    for (const t1 of points) {
      const r = this.rates();
      this.energyRem += r.e * (t1 - t0);
      this.energy += idiv(this.energyRem, 3600);
      this.energyRem %= 3600;
      this.dotsRem += r.d * (t1 - t0);
      this.dots += idiv(this.dotsRem, 3600);
      this.dotsRem %= 3600;
      const ecap = this.energyCap();
      if (this.energy >= ecap) { this.energy = Math.max(ecap, e0); this.energyRem = 0; }
      const dcap = this.dotsCap();
      if (this.dots >= dcap) { this.dots = Math.max(dcap, d0); this.dotsRem = 0; }
      this.finishBuilds(t1);
      t0 = t1;
    }
    this.lastCollect = now;
    return { energy: this.energy - e0, dots: this.dots - d0, secs: now - start };
  }

  toDict(): Record<string, any> {
    const out: Record<string, any> = { version: SAVE_VERSION, cells: {} };
    for (const k of Object.keys(this.cells).sort()) out.cells[k] = { ...this.cells[k] };
    for (const [j, f] of INT_FIELDS) out[j] = this[f];
    return out;
  }

  /** null for unusable data (wrong shape, unknown/future version, no core). */
  static fromDict(d: any): ColonyState | null {
    if (d === null || typeof d !== "object" || Array.isArray(d)) return null;
    if (d.cells === null || typeof d.cells !== "object" || Array.isArray(d.cells)) return null;
    const ver = d.version ?? 1;
    if (!isNum(ver) || Math.trunc(ver) > SAVE_VERSION) return null;
    const c = new ColonyState();
    for (const k of Object.keys(d.cells)) {
      const cell = d.cells[k];
      if (cell === null || typeof cell !== "object" || typeof cell.type !== "string" || !B.isType(cell.type)) continue;
      const [q, r] = Hex.parse(k);
      const n = (v: unknown) => (isNum(v) ? Math.trunc(v) : 0);
      c.cells[Hex.key(q, r)] = {
        type: cell.type,
        level: clamp(n(cell.level), 0, B.MAX_LEVEL),
        build_end: n(cell.build_end),
        target_level: clamp(n(cell.target_level), 0, B.MAX_LEVEL),
      };
    }
    if (!Object.values(c.cells).some((x) => x.type === "core")) return null;
    for (const [j, f] of INT_FIELDS) (c as any)[f] = isNum(d[j]) ? Math.trunc(d[j]) : 0;
    return c;
  }

  /** node id -> [q, r], ids 1..n over built cells in sorted (q, r) order. */
  snapshotIds(): Map<number, [number, number]> {
    const built = Object.keys(this.cells).filter((k) => this.cells[k].level >= 1).map(Hex.parse);
    built.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    return new Map(built.map((h, i) => [i + 1, h]));
  }

  toSimGraph(owner: number): SimGraph {
    const ids = this.snapshotIds();
    const byHex = new Map<string, number>();
    const g = new SimGraph();
    for (const [id, [q, r]] of ids) {
      const cell = this.cells[Hex.key(q, r)];
      const pos = Hex.toFx(q, r);
      const t = cell.type, l = cell.level;
      g.addNode(id, pos.x, pos.y, owner, B.garrison(t, l), B.battleProd(t, l), B.tower(t), B.trapDmg(t, l),
        B.tower(t) !== "" ? l : 1);
      byHex.set(Hex.key(q, r), id);
    }
    for (const [id, [q, r]] of ids) {
      for (const [nq, nr] of Hex.neighbors(q, r)) {
        const nb = byHex.get(Hex.key(nq, nr));
        if (nb !== undefined && id < nb) g.link(id, nb);
      }
    }
    return g;
  }

  coreNodeId(): number {
    for (const [id, [q, r]] of this.snapshotIds()) if (q === 0 && r === 0) return id;
    return 1;
  }
}
