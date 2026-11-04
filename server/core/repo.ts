// Storage interface for server core logic. Times are unix seconds.
// Every method is ONE atomic operation (one SQL statement / function in SupaRepo), so
// concurrent requests cannot double-settle or overwrite each other's changes.
// MemoryRepo mirrors that: no await inside a method body.

export type Player = { id: string; trophies: number; attacks: number; crystals: number; shield_until: number | null };
export type ColonyRow = { data: any; synced_at: number; rev: number };
export type AttackStatus = "open" | "settling" | "done" | "abandoned";
export type AttackRow = {
  id: string; attacker: string; defender: string | null; bot: { trophies: number; seed: number } | null;
  snapshot: any; dots: number; seed: number; loot_pool: number; status: AttackStatus;
  commands: any; result: any; created_at: number; finished_at: number | null;
};

export interface Repo {
  getPlayer(id: string): Promise<Player | null>;
  /** Creates the default player row if missing; returns the current row. */
  ensurePlayer(id: string): Promise<Player>;
  /** trophies = max(0, trophies + dTrophies); attacks += dAttacks; shield set when given;
   *  crystals = min(crystals, crystalsMax) when given. */
  adjustPlayer(id: string, dTrophies: number, dAttacks: number, shieldUntil: number | null, crystalsMax?: number): Promise<void>;
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
}

const clone = <T>(x: T): T => structuredClone(x);
const LIVE: AttackStatus[] = ["open", "settling"];

export class MemoryRepo implements Repo {
  players = new Map<string, Player>();
  colonies = new Map<string, ColonyRow>();
  attacks = new Map<string, AttackRow>();
  private nextId = 1;

  newId(): string { return `a${this.nextId++}`; }

  /** Test helper: player + colony rows in one go. */
  seed(id: string, p: Omit<Player, "id">, data: any, syncedAt: number): void {
    this.players.set(id, { id, ...p });
    this.colonies.set(id, { data: clone(data), synced_at: syncedAt, rev: 0 });
  }

  async getPlayer(id: string) { const p = this.players.get(id); return p ? { ...p } : null; }
  async ensurePlayer(id: string) {
    if (!this.players.has(id)) this.players.set(id, { id, trophies: 0, attacks: 0, crystals: 50, shield_until: null });
    return { ...this.players.get(id)! };
  }
  async adjustPlayer(id: string, dT: number, dA: number, shield: number | null, crystalsMax?: number) {
    const p = this.players.get(id);
    if (!p) return;
    p.trophies = Math.max(0, p.trophies + dT);
    p.attacks += dA;
    if (shield !== null) p.shield_until = shield;
    if (crystalsMax !== undefined) p.crystals = Math.min(p.crystals, crystalsMax);
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
  async defensesSince(defender: string, since: number) {
    let count = 0, loot = 0;
    for (const a of this.attacks.values()) {
      if (a.defender === defender && a.status === "done" && (a.finished_at ?? 0) > since) { count++; loot += a.result?.loot ?? 0; }
    }
    return { count, loot };
  }
}
