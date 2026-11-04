// Storage interface for server core logic. Times are unix seconds.
// MemoryRepo is the test double; supabase/functions/_shared/supa_repo.ts is the real one.

export type Player = { id: string; trophies: number; attacks: number; crystals: number; shield_until: number | null };
export type ColonyRow = { data: any; synced_at: number };
export type AttackStatus = "open" | "done" | "abandoned";
export type AttackRow = {
  id: string; attacker: string; defender: string | null; bot: { trophies: number; seed: number } | null;
  snapshot: any; dots: number; seed: number; loot_pool: number; status: AttackStatus;
  commands: any; result: any; created_at: number; finished_at: number | null;
};

export interface Repo {
  getPlayer(id: string): Promise<Player | null>;
  putPlayer(p: Player): Promise<void>;
  getColony(id: string): Promise<ColonyRow | null>;
  putColony(id: string, row: ColonyRow): Promise<void>;
  /** Players with trophies in [min, max], not `exclude`, without an active shield, having a colony. */
  candidates(min: number, max: number, exclude: string, now: number, limit: number): Promise<string[]>;
  /** false when the defender already has an open attack (unique index). */
  insertAttack(a: AttackRow): Promise<boolean>;
  getAttack(id: string): Promise<AttackRow | null>;
  updateAttack(id: string, patch: Partial<AttackRow>): Promise<void>;
  openAttacks(olderThan: number): Promise<AttackRow[]>;
  openAttacksBy(attacker: string): Promise<AttackRow[]>;
}

export class MemoryRepo implements Repo {
  players = new Map<string, Player>();
  colonies = new Map<string, ColonyRow>();
  attacks = new Map<string, AttackRow>();
  private nextId = 1;

  newId(): string { return `a${this.nextId++}`; }
  async getPlayer(id: string) { const p = this.players.get(id); return p ? { ...p } : null; }
  async putPlayer(p: Player) { this.players.set(p.id, { ...p }); }
  async getColony(id: string) { const c = this.colonies.get(id); return c ? structuredClone(c) : null; }
  async putColony(id: string, row: ColonyRow) { this.colonies.set(id, structuredClone(row)); }
  async candidates(min: number, max: number, exclude: string, now: number, limit: number) {
    return [...this.players.values()]
      .filter((p) => p.id !== exclude && p.trophies >= min && p.trophies <= max &&
        (p.shield_until === null || p.shield_until <= now) && this.colonies.has(p.id))
      .map((p) => p.id).sort().slice(0, limit);
  }
  async insertAttack(a: AttackRow) {
    if (a.defender !== null) {
      for (const x of this.attacks.values()) if (x.defender === a.defender && x.status === "open") return false;
    }
    this.attacks.set(a.id, structuredClone(a));
    return true;
  }
  async getAttack(id: string) { const a = this.attacks.get(id); return a ? structuredClone(a) : null; }
  async updateAttack(id: string, patch: Partial<AttackRow>) {
    const a = this.attacks.get(id);
    if (a) this.attacks.set(id, { ...a, ...structuredClone(patch) });
  }
  async openAttacks(olderThan: number) {
    return [...this.attacks.values()].filter((a) => a.status === "open" && a.created_at < olderThan).map((a) => structuredClone(a));
  }
  async openAttacksBy(attacker: string) {
    return [...this.attacks.values()].filter((a) => a.status === "open" && a.attacker === attacker).map((a) => structuredClone(a));
  }

}
