// Repo backed by Supabase (service role: bypasses RLS; every write is validated in server/core).
// Each method is one atomic statement or SQL function (see migrations/*_atomic_ops.sql).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import type { AttackRow, ColonyRow, Player, Repo } from "./server/core/repo.ts";
import type { Deps } from "./server/http/handlers.ts";

const sec = (iso: string | null): number | null => (iso ? Math.floor(Date.parse(iso) / 1000) : null);
const iso = (s: number | null): string | null => (s === null ? null : new Date(s * 1000).toISOString());
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LIVE = "(open,settling)";

const toAttack = (r: any): AttackRow => ({ ...r, created_at: sec(r.created_at)!, finished_at: sec(r.finished_at) });
const toPlayer = (d: any): Player => ({ id: d.id, trophies: d.trophies, attacks: d.attacks, crystals: d.crystals,
  shield_until: sec(d.shield_until) });
function check(error: any): void { if (error) throw error; }

export class SupaRepo implements Repo {
  db: SupabaseClient;
  constructor(db: SupabaseClient) { this.db = db; }

  async getPlayer(id: string) {
    const { data, error } = await this.db.from("players").select("*").eq("id", id).maybeSingle();
    check(error);
    return data ? toPlayer(data) : null;
  }
  async ensurePlayer(id: string) {
    const { error } = await this.db.from("players").upsert({ id }, { onConflict: "id", ignoreDuplicates: true });
    check(error);
    return (await this.getPlayer(id))!;
  }
  async adjustPlayer(id: string, dT: number, dA: number, shield: number | null, crystalsMax?: number) {
    const { error } = await this.db.rpc("adjust_player", { p_id: id, p_dtrophies: dT, p_dattacks: dA,
      p_shield: iso(shield), p_crystals_max: crystalsMax ?? null });
    check(error);
  }
  async getColony(id: string): Promise<ColonyRow | null> {
    const { data, error } = await this.db.from("colonies").select("data, synced_at, rev").eq("player_id", id).maybeSingle();
    check(error);
    return data ? { data: data.data, synced_at: sec(data.synced_at)!, rev: data.rev } : null;
  }
  async createColony(id: string, data: any, syncedAt: number) {
    const { error } = await this.db.from("colonies").insert({ player_id: id, data, synced_at: iso(syncedAt), rev: 0 });
    if (error?.code === "23505") return false;
    check(error);
    return true;
  }
  async casColony(id: string, data: any, syncedAt: number, rev: number) {
    const { data: rows, error } = await this.db.from("colonies")
      .update({ data, synced_at: iso(syncedAt), rev: rev + 1 }).eq("player_id", id).eq("rev", rev).select("player_id");
    check(error);
    return (rows ?? []).length === 1;
  }
  async consumeDots(id: string, min: number) {
    const { data, error } = await this.db.rpc("consume_dots", { p_id: id, p_min: min });
    check(error);
    return typeof data === "number" ? data : -1;
  }
  async creditEnergy(id: string, delta: number, clearOpen: boolean) {
    const { error } = await this.db.rpc("credit_energy", { p_id: id, p_delta: delta, p_clear_open: clearOpen });
    check(error);
  }
  async candidates(min: number, max: number, exclude: string, now: number, limit: number) {
    // Random window over the trophy range so the same rows are not always picked first.
    const pivot = min + Math.floor(Math.random() * Math.max(1, max - min + 1));
    const pick = async (gte: boolean) => {
      let q = this.db.from("players").select("id").neq("id", exclude)
        .or(`shield_until.is.null,shield_until.lte.${iso(now)}`).gte("trophies", gte ? pivot : min).lte("trophies", gte ? max : pivot - 1)
        .order("trophies", { ascending: gte }).limit(limit * 2);
      const { data, error } = await q;
      check(error);
      return (data ?? []).map((r: any) => r.id as string);
    };
    const ids = [...new Set([...(await pick(true)), ...(await pick(false))])];
    if (ids.length === 0) return [];
    const { data: cols, error } = await this.db.from("colonies").select("player_id").in("player_id", ids);
    check(error);
    const have = new Set((cols ?? []).map((r: any) => r.player_id));
    return ids.filter((id) => have.has(id)).slice(0, limit);
  }
  async insertAttack(a: AttackRow) {
    const { error } = await this.db.from("attacks").insert({ ...a, created_at: iso(a.created_at), finished_at: iso(a.finished_at) });
    if (error?.code === "23505") return false;
    check(error);
    return true;
  }
  async getAttack(id: string) {
    if (!UUID.test(id)) return null;
    const { data, error } = await this.db.from("attacks").select("*").eq("id", id).maybeSingle();
    check(error);
    return data ? toAttack(data) : null;
  }
  async claimAttack(id: string, attacker: string) {
    if (!UUID.test(id)) return null;
    const { data, error } = await this.db.from("attacks").update({ status: "settling" })
      .eq("id", id).eq("attacker", attacker).eq("status", "open").select("*");
    check(error);
    return data && data.length === 1 ? toAttack(data[0]) : null;
  }
  async completeAttack(id: string, result: any, commands: any, finishedAt: number) {
    const { error } = await this.db.from("attacks").update({ status: "done", result, commands, finished_at: iso(finishedAt) })
      .eq("id", id).eq("status", "settling");
    check(error);
  }
  async abandonAttack(id: string, now: number, result: any) {
    const { data, error } = await this.db.from("attacks").update({ status: "abandoned", result, finished_at: iso(now) })
      .eq("id", id).eq("status", "open").select("*");
    check(error);
    return data && data.length === 1 ? toAttack(data[0]) : null;
  }
  async openAttacks(olderThan: number) {
    const { data, error } = await this.db.from("attacks").select("*").eq("status", "open").lt("created_at", iso(olderThan)).limit(50);
    check(error);
    return (data ?? []).map(toAttack);
  }
  async openAttacksBy(attacker: string) {
    const { data, error } = await this.db.from("attacks").select("*").eq("status", "open").eq("attacker", attacker);
    check(error);
    return (data ?? []).map(toAttack);
  }
  async defensesSince(defender: string, since: number) {
    const { data, error } = await this.db.from("attacks").select("result").eq("defender", defender).eq("status", "done")
      .gt("finished_at", iso(since)).limit(100);
    check(error);
    const rows = data ?? [];
    return { count: rows.length, loot: rows.reduce((s: number, r: any) => s + (r.result?.loot ?? 0), 0) };
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
