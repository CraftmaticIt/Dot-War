// Storage interface for server core logic. Times are unix seconds.
// Every method is ONE atomic operation (one SQL statement / function in SupaRepo), so
// concurrent requests cannot double-settle or overwrite each other's changes.
// MemoryRepo mirrors that: no await inside a method body.

import { DEFS, seasonIndex, type QuestState } from "../game/meta.ts";

export type Player = {
  id: string; trophies: number; attacks: number; crystals: number; shield_until: number | null;
  boosters: Record<string, number>; season: number; quests: QuestState | null; quests_rev: number; last_reward: any;
};
export type ColonyRow = { data: any; synced_at: number; rev: number };
export type AttackStatus = "open" | "settling" | "done" | "abandoned";
export type AttackRow = {
  id: string; attacker: string; defender: string | null; bot: { trophies: number; seed: number; practice?: boolean } | null;
  snapshot: any; dots: number; seed: number; loot_pool: number; status: AttackStatus;
  commands: any; result: any; created_at: number; finished_at: number | null; loadout?: string[];
};

export interface Repo {
  getPlayer(id: string): Promise<Player | null>;
  /** Creates the default player row if missing (season = current); returns the row. */
  ensurePlayer(id: string, now: number): Promise<Player>;
  /** trophies = max(0, trophies + dTrophies); attacks += dAttacks; shield set when given;
   *  crystals = max(0, crystals + dCrystals). Every crystals change is mirrored into
   *  colonies.data.crystals (rev bumped) so the colony copy never disagrees. */
  adjustPlayer(id: string, dTrophies: number, dAttacks: number, shieldUntil: number | null, dCrystals?: number): Promise<void>;
  /** All-or-nothing: subtract `need` from boosters if every count suffices. */
  takeBoosters(id: string, need: Record<string, number>): Promise<boolean>;
  grant(id: string, crystals: number, boosters: Record<string, number>): Promise<void>;
  /** crystals -= price and boosters[item] += 1 only if crystals >= price. */
  buy(id: string, item: string, price: number): Promise<boolean>;
  /** Only when player.season < season: + reward crystals, soft trophy reset, season = season. */
  settleSeason(id: string, season: number, reward: number, info: any): Promise<boolean>;
  /** Replace quests if quests_rev is unchanged (bumps it). */
  setQuests(id: string, quests: QuestState, rev: number): Promise<boolean>;
  getColony(id: string): Promise<ColonyRow | null>;
  /** Insert only if absent. */
  createColony(id: string, data: any, syncedAt: number): Promise<boolean>;
  /** Replace only if rev is unchanged (compare-and-swap); bumps rev. */
  casColony(id: string, data: any, syncedAt: number, rev: number): Promise<boolean>;
  /** If dots >= min: returns them and sets dots/dots_rem 0, attack_open 1; else -1. Bumps rev. */
  consumeDots(id: string, min: number): Promise<number>;
  /** energy = max(0, energy + delta); attack_open 0 when clearOpen. Bumps rev. */
  creditEnergy(id: string, delta: number, clearOpen: boolean): Promise<void>;
  /** Players with trophies in [min, max], not `exclude`, without an active shield, having a colony. */
  candidates(min: number, max: number, exclude: string, now: number, limit: number): Promise<string[]>;
  /** false when the defender (or attacker) already has an open/settling attack. */
  insertAttack(a: AttackRow): Promise<boolean>;
  getAttack(id: string): Promise<AttackRow | null>;
  /** open -> settling for the given attacker; null if not claimable. */
  claimAttack(id: string, attacker: string): Promise<AttackRow | null>;
  completeAttack(id: string, result: any, commands: any, finishedAt: number): Promise<void>;
  /** open -> abandoned; null if it was not open any more. */
  abandonAttack(id: string, now: number, result: any): Promise<AttackRow | null>;
  openAttacks(olderThan: number): Promise<AttackRow[]>;
  openAttacksBy(attacker: string): Promise<AttackRow[]>;
  defensesSince(defender: string, since: number): Promise<{ count: number; loot: number }>;
  /** stars = max(old, new); crystals += (new - old)+ * perStar (mirrored). Returns gained stars. */
  pveRecord(id: string, level: number, stars: number, perStar: number): Promise<number>;
  /** score = max(old, new) for (player, week). */
  pveWeekRecord(id: string, week: number, score: number): Promise<void>;
  pveStars(id: string): Promise<Record<string, number>>;
  /** Ordered by score desc, then player asc. */
  pveTop(week: number, limit: number): Promise<{ player: string; score: number }[]>;
  /** rank = 1 + players with a higher score; null when the player has no score this week. */
  pveRank(id: string, week: number): Promise<{ score: number; rank: number } | null>;
  /** Once per week: players with score > 0 within the top `topPct`% (at least 1; ties at the
   *  threshold included) get crystals + boosters. false when the week was already settled. */
  settlePveWeek(week: number, topPct: number, crystals: number, boosters: Record<string, number>): Promise<boolean>;
}

const clone = <T>(x: T): T => structuredClone(x);
const LIVE: AttackStatus[] = ["open", "settling"];

export class MemoryRepo implements Repo {
  players = new Map<string, Player>();
  colonies = new Map<string, ColonyRow>();
  attacks = new Map<string, AttackRow>();
  pve = new Map<string, Map<number, number>>();       // player -> level -> stars
  weekly = new Map<number, Map<string, number>>();    // week -> player -> score
  settledWeeks = new Set<number>();
  private nextId = 1;

  newId(): string { return `a${this.nextId++}`; }

  /** Test helper: player + colony rows in one go. */
  seed(id: string, p: Partial<Omit<Player, "id">>, data: any, syncedAt: number): void {
    const full: Player = { id, trophies: 0, attacks: 0, crystals: 50, shield_until: null, boosters: { ...DEFS.start_boosters },
      season: seasonIndex(syncedAt), quests: null, quests_rev: 0, last_reward: null, ...p };
    this.players.set(id, full);
    this.colonies.set(id, { data: clone(data), synced_at: syncedAt, rev: 0 });
  }
  private mirror(id: string): void {
    const c = this.colonies.get(id), p = this.players.get(id);
    if (c && p) { c.data.crystals = p.crystals; c.rev += 1; }
  }


  async getPlayer(id: string) { const p = this.players.get(id); return p ? clone(p) : null; }
  async ensurePlayer(id: string, now: number) {
    if (!this.players.has(id)) {
      this.players.set(id, { id, trophies: 0, attacks: 0, crystals: 50, shield_until: null, boosters: { ...DEFS.start_boosters },
        season: seasonIndex(now), quests: null, quests_rev: 0, last_reward: null });
    }
    return clone(this.players.get(id)!);
  }
  async adjustPlayer(id: string, dT: number, dA: number, shield: number | null, dCrystals = 0) {
    const p = this.players.get(id);
    if (!p) return;
    p.trophies = Math.max(0, p.trophies + dT);
    p.attacks += dA;
    if (shield !== null) p.shield_until = shield;
    if (dCrystals !== 0) { p.crystals = Math.max(0, p.crystals + dCrystals); this.mirror(id); }
  }
  async takeBoosters(id: string, need: Record<string, number>) {
    const p = this.players.get(id);
    if (!p || Object.entries(need).some(([k, n]) => (p.boosters[k] ?? 0) < n)) return false;
    for (const [k, n] of Object.entries(need)) p.boosters[k] -= n;
    return true;
  }
  async grant(id: string, crystals: number, boosters: Record<string, number>) {
    const p = this.players.get(id);
    if (!p) return;
    for (const [k, n] of Object.entries(boosters)) p.boosters[k] = (p.boosters[k] ?? 0) + n;
    if (crystals !== 0) { p.crystals = Math.max(0, p.crystals + crystals); this.mirror(id); }
  }
  async buy(id: string, item: string, price: number) {
    const p = this.players.get(id);
    if (!p || p.crystals < price) return false;
    p.crystals -= price;
    p.boosters[item] = (p.boosters[item] ?? 0) + 1;
    this.mirror(id);
    return true;
  }
  async settleSeason(id: string, season: number, reward: number, info: any) {
    const p = this.players.get(id);
    if (!p || p.season >= season) return false;
    p.season = season;
    p.crystals += reward;
    const a = DEFS.season.reset_above;
    if (p.trophies > a) p.trophies = a + Math.trunc((p.trophies - a) / 2);
    p.last_reward = clone(info);
    this.mirror(id);
    return true;
  }
  async setQuests(id: string, quests: QuestState, rev: number) {
    const p = this.players.get(id);
    if (!p || p.quests_rev !== rev) return false;
    p.quests = clone(quests);
    p.quests_rev = rev + 1;
    return true;
  }
  async getColony(id: string) { const c = this.colonies.get(id); return c ? clone(c) : null; }
  async createColony(id: string, data: any, syncedAt: number) {
    if (this.colonies.has(id)) return false;
    this.colonies.set(id, { data: clone(data), synced_at: syncedAt, rev: 0 });
    return true;
  }
  async casColony(id: string, data: any, syncedAt: number, rev: number) {
    const c = this.colonies.get(id);
    if (!c || c.rev !== rev) return false;
    this.colonies.set(id, { data: clone(data), synced_at: syncedAt, rev: rev + 1 });
    return true;
  }
  async consumeDots(id: string, min: number) {
    const c = this.colonies.get(id);
    const dots = c?.data?.dots ?? -1;
    if (!c || dots < min) return -1;
    c.data.dots = 0; c.data.dots_rem = 0; c.data.attack_open = 1; c.rev += 1;
    return dots;
  }
  async creditEnergy(id: string, delta: number, clearOpen: boolean) {
    const c = this.colonies.get(id);
    if (!c) return;
    c.data.energy = Math.max(0, (c.data.energy ?? 0) + delta);
    if (clearOpen) c.data.attack_open = 0;
    c.rev += 1;
  }
  async candidates(min: number, max: number, exclude: string, now: number, limit: number) {
    return [...this.players.values()]
      .filter((p) => p.id !== exclude && p.trophies >= min && p.trophies <= max &&
        (p.shield_until === null || p.shield_until <= now) && this.colonies.has(p.id))
      .map((p) => p.id).sort().slice(0, limit);
  }
  async insertAttack(a: AttackRow) {
    for (const x of this.attacks.values()) {
      if (!LIVE.includes(x.status)) continue;
      if (a.defender !== null && x.defender === a.defender) return false;
      if (x.attacker === a.attacker) return false;
    }
    this.attacks.set(a.id, clone(a));
    return true;
  }
  async getAttack(id: string) { const a = this.attacks.get(id); return a ? clone(a) : null; }
  async claimAttack(id: string, attacker: string) {
    const a = this.attacks.get(id);
    if (!a || a.attacker !== attacker || a.status !== "open") return null;
    a.status = "settling";
    return clone(a);
  }
  async completeAttack(id: string, result: any, commands: any, finishedAt: number) {
    const a = this.attacks.get(id);
    if (a && a.status === "settling") Object.assign(a, { status: "done", result: clone(result), commands: clone(commands), finished_at: finishedAt });
  }
  async abandonAttack(id: string, now: number, result: any) {
    const a = this.attacks.get(id);
    if (!a || a.status !== "open") return null;
    Object.assign(a, { status: "abandoned", finished_at: now, result: clone(result) });
    return clone(a);
  }
  async openAttacks(olderThan: number) {
    return [...this.attacks.values()].filter((a) => a.status === "open" && a.created_at < olderThan).map(clone);
  }
  async openAttacksBy(attacker: string) {
    return [...this.attacks.values()].filter((a) => a.status === "open" && a.attacker === attacker).map(clone);
  }
  async pveRecord(id: string, level: number, stars: number, perStar: number) {
    if (!this.players.has(id)) return 0;
    const m = this.pve.get(id) ?? new Map<number, number>();
    this.pve.set(id, m);
    const old = m.get(level) ?? 0;
    if (stars <= old) return 0;
    m.set(level, stars);
    const p = this.players.get(id)!;
    p.crystals += (stars - old) * perStar;
    this.mirror(id);
    return stars - old;
  }
  async pveWeekRecord(id: string, week: number, score: number) {
    const m = this.weekly.get(week) ?? new Map<string, number>();
    this.weekly.set(week, m);
    m.set(id, Math.max(m.get(id) ?? 0, score));
  }
  async pveStars(id: string) {
    const out: Record<string, number> = {};
    for (const [l, s] of this.pve.get(id) ?? []) out[String(l)] = s;
    return out;
  }
  private ranked(week: number) {
    return [...(this.weekly.get(week) ?? [])].map(([player, score]) => ({ player, score }))
      .sort((a, b) => b.score - a.score || (a.player < b.player ? -1 : a.player > b.player ? 1 : 0));
  }
  async pveTop(week: number, limit: number) { return this.ranked(week).slice(0, limit); }
  async pveRank(id: string, week: number) {
    const m = this.weekly.get(week);
    if (!m || !m.has(id)) return null;
    const score = m.get(id)!;
    return { score, rank: 1 + [...m.values()].filter((s) => s > score).length };
  }
  async settlePveWeek(week: number, topPct: number, crystals: number, boosters: Record<string, number>) {
    if (this.settledWeeks.has(week)) return false;
    this.settledWeeks.add(week);
    const scored = this.ranked(week).filter((r) => r.score > 0);
    if (!scored.length) return true;
    const k = Math.max(1, Math.trunc((scored.length * topPct) / 100));
    const threshold = scored[k - 1].score;
    for (const r of scored) {
      if (r.score < threshold) break;
      const p = this.players.get(r.player);
      if (!p) continue;
      for (const [b, n] of Object.entries(boosters)) p.boosters[b] = (p.boosters[b] ?? 0) + n;
      p.crystals += crystals;
      this.mirror(r.player);
    }
    return true;
  }
  async defensesSince(defender: string, since: number) {
    let count = 0, loot = 0;
    for (const a of this.attacks.values()) {
      if (a.defender === defender && a.status === "done" && (a.finished_at ?? 0) > since) { count++; loot += a.result?.loot ?? 0; }
    }
    return { count, loot };
  }
}
