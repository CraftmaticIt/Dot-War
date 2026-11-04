// Match rules (port of battle/match.gd).
import { idiv } from "../sim/fx.ts";
import { SimWorld, TICK_HZ, BOOST_TICKS } from "../sim/world.ts";
import { ATTACKER, DEFENDER } from "./attack_setup.ts";

export const DURATION_TICKS = 180 * TICK_HZ;
export const MAX_BOOSTS = 3;
export type Result = { stars: number; destroyed_pct: number; loot: number; trophies: number };

export class BattleMatch {
  world: SimWorld;
  over = false;
  private defenderIds: number[];
  private core: number;
  private pool: number;
  boostsLeft: string[] = [];

  constructor(world: SimWorld, core: number, pool: number, loadout: unknown = []) {
    this.world = world;
    for (const b of Array.isArray(loadout) ? loadout : []) {
      if (typeof b === "string" && Object.hasOwn(BOOST_TICKS, b) && this.boostsLeft.length < MAX_BOOSTS) this.boostsLeft.push(b);
    }
    this.core = core;
    this.pool = pool;
    this.defenderIds = world.graph.nodeIds().filter((id) => world.graph.node(id).owner === DEFENDER);
  }

  /** Consumed when sent (even if the sim rejects the node): identical to battle/match.gd. */
  boost(booster: unknown, node: unknown): boolean {
    if (this.over || typeof booster !== "string") return false;
    const i = this.boostsLeft.indexOf(booster);
    if (i < 0) return false;
    this.boostsLeft.splice(i, 1);
    this.world.queue({ tick: this.world.tick, type: "boost", owner: ATTACKER, booster, node });
    return true;
  }

  sendRaw(c: any): void {
    if (this.over) return;
    if (c && typeof c === "object" && c.type === "boost") { this.boost(c.booster, c.node); return; }
    this.world.queue({ tick: this.world.tick, type: "send", owner: ATTACKER,
      from: c?.from, to: c?.to, percent: c?.percent });
  }

  step(): void {
    if (this.over) return;
    this.world.step();
    const p = this.progress();
    if (this.world.tick >= DURATION_TICKS || p.destroyed_pct === 100 || this.attackerOut()) this.over = true;
  }

  surrender(): void { this.over = true; }

  private attackerOut(): boolean {
    if (this.world.groups.some((g) => g.owner === ATTACKER && g.count > 0)) return false;
    for (const id of this.world.graph.nodeIds()) {
      const n = this.world.graph.node(id);
      if (n.owner === ATTACKER && (n.garrison > 0 || n.prod_per_sec > 0)) return false;
    }
    return true;
  }

  progress(): { destroyed_pct: number; core: boolean; stars: number; ticks_left: number } {
    const g = this.world.graph;
    const taken = this.defenderIds.filter((id) => g.node(id).owner !== DEFENDER).length;
    const pct = idiv(100 * taken, Math.max(this.defenderIds.length, 1));
    const core = g.hasNode(this.core) && g.node(this.core).owner !== DEFENDER;
    const stars = (pct >= 50 ? 1 : 0) + (core ? 1 : 0) + (pct === 100 ? 1 : 0);
    return { destroyed_pct: pct, core, stars, ticks_left: Math.max(0, DURATION_TICKS - this.world.tick) };
  }

  result(): Result {
    const p = this.progress();
    const won = p.stars >= 1;
    return { stars: p.stars, destroyed_pct: p.destroyed_pct,
      loot: won ? idiv(this.pool * p.destroyed_pct, 100) : 0, trophies: won ? 10 * p.stars : -8 };
  }
}
