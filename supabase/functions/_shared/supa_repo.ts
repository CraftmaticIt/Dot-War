// Repo backed by Supabase (service role: bypasses RLS; every write is validated in server/core).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import type { AttackRow, ColonyRow, Player, Repo } from "./server/core/repo.ts";
import type { Deps } from "./server/http/handlers.ts";

const sec = (iso: string | null): number | null => (iso ? Math.floor(Date.parse(iso) / 1000) : null);
const iso = (s: number | null): string | null => (s === null ? null : new Date(s * 1000).toISOString());

function rowToAttack(r: any): AttackRow {
  return { ...r, created_at: sec(r.created_at)!, finished_at: sec(r.finished_at) };
}

export class SupaRepo implements Repo {
  constructor(private db: SupabaseClient) {}

  async getPlayer(id: string): Promise<Player | null> {
    const { data, error } = await this.db.from("players").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data ? { id: data.id, trophies: data.trophies, attacks: data.attacks, crystals: data.crystals,
      shield_until: sec(data.shield_until) } : null;
  }
  async putPlayer(p: Player): Promise<void> {
    const { error } = await this.db.from("players").upsert({ id: p.id, trophies: p.trophies, attacks: p.attacks,
      crystals: p.crystals, shield_until: iso(p.shield_until) });
    if (error) throw error;
  }
  async getColony(id: string): Promise<ColonyRow | null> {
    const { data, error } = await this.db.from("colonies").select("data, synced_at").eq("player_id", id).maybeSingle();
    if (error) throw error;
    return data ? { data: data.data, synced_at: sec(data.synced_at)! } : null;
  }
  async putColony(id: string, row: ColonyRow): Promise<void> {
    const { error } = await this.db.from("colonies").upsert({ player_id: id, data: row.data, synced_at: iso(row.synced_at) });
    if (error) throw error;
  }
  async candidates(min: number, max: number, exclude: string, now: number, limit: number): Promise<string[]> {
    const { data, error } = await this.db.from("players").select("id")
      .gte("trophies", min).lte("trophies", max).neq("id", exclude)
      .or(`shield_until.is.null,shield_until.lte.${iso(now)}`).limit(limit * 3);
    if (error) throw error;
    const ids = (data ?? []).map((r: any) => r.id);
    if (ids.length === 0) return [];
    const { data: cols, error: e2 } = await this.db.from("colonies").select("player_id").in("player_id", ids);
    if (e2) throw e2;
    const have = new Set((cols ?? []).map((r: any) => r.player_id));
    return ids.filter((id: string) => have.has(id)).sort().slice(0, limit);
  }
  async insertAttack(a: AttackRow): Promise<boolean> {
    const { error } = await this.db.from("attacks").insert({ ...a, created_at: iso(a.created_at), finished_at: iso(a.finished_at) });
    if (error?.code === "23505") return false;  // unique: defender already has an open attack
    if (error) throw error;
    return true;
  }
  async getAttack(id: string): Promise<AttackRow | null> {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
    const { data, error } = await this.db.from("attacks").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data ? rowToAttack(data) : null;
  }
  async updateAttack(id: string, patch: Partial<AttackRow>): Promise<void> {
    const p: any = { ...patch };
    if ("created_at" in p) p.created_at = iso(p.created_at);
    if ("finished_at" in p) p.finished_at = iso(p.finished_at);
    const { error } = await this.db.from("attacks").update(p).eq("id", id);
    if (error) throw error;
  }
  async openAttacks(olderThan: number): Promise<AttackRow[]> {
    const { data, error } = await this.db.from("attacks").select("*").eq("status", "open").lt("created_at", iso(olderThan)).limit(200);
    if (error) throw error;
    return (data ?? []).map(rowToAttack);
  }
  async openAttacksBy(attacker: string): Promise<AttackRow[]> {
    const { data, error } = await this.db.from("attacks").select("*").eq("status", "open").eq("attacker", attacker);
    if (error) throw error;
    return (data ?? []).map(rowToAttack);
  }
}

export function makeDeps(): Deps {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });
  return {
    repo: new SupaRepo(db),
    getUser: async (jwt: string) => {
      const { data, error } = await db.auth.getUser(jwt);
      return error || !data.user ? null : data.user.id;
    },
    now: () => Math.floor(Date.now() / 1000),
    rand: () => crypto.getRandomValues(new Uint32Array(1))[0] / 2 ** 32,
  };
}
