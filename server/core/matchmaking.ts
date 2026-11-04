// Opponent selection: players within ±200 trophies without shield/live attack, else a bot.
import { idiv } from "../sim/fx.ts";
import { ColonyState } from "../game/colony.ts";
import { BotColony } from "../game/bot_colony.ts";
import type { AttackRow, Repo } from "./repo.ts";
import { cleanLoadout, loadoutNeeds } from "../game/meta.ts";

export const RANGE = 200;
export const MAX_CANDIDATES = 20;
export const ABANDON_SECS = 600;
export const ABANDON_TROPHIES = -8;
export const MIN_ATTACK_DOTS = 10;
export const UNPROTECTED_PCT = 80;
const ABANDON_RESULT = { stars: 0, destroyed_pct: 0, loot: 0, trophies: ABANDON_TROPHIES };

export type FindResult = {
  error?: string; attack_id?: string; snapshot?: any; loot_pool?: number; seed?: number; dots?: number;
  bot?: { trophies: number; seed: number; practice?: boolean } | null; loadout?: string[];
};

/** Atomic: only the request that flips open -> abandoned applies the penalty. */
async function abandon(repo: Repo, id: string, now: number): Promise<void> {
  const a = await repo.abandonAttack(id, now, ABANDON_RESULT);
  if (!a) return;
  await repo.adjustPlayer(a.attacker, ABANDON_TROPHIES, 0, null);
  await repo.creditEnergy(a.attacker, 0, true);
}

export async function resolveStale(repo: Repo, now: number): Promise<void> {
  for (const a of await repo.openAttacks(now - ABANDON_SECS)) await abandon(repo, a.id, now);
}

/** What the attacker's client receives: traps look like ordinary buildings (same garrison). */
export function disguise(snapshot: any): any {
  const s = structuredClone(snapshot);
  for (const k in s.cells ?? {}) if (s.cells[k].type === "trap") s.cells[k].type = "mine";
  return s;
}

/** practice = bot only, no loot/trophies (used by the live smoke test; never touches players). */
export async function findOpponent(repo: Repo, uid: string, now: number, rand: () => number,
  newId: () => string = () => crypto.randomUUID(), practice = false, rawLoadout: unknown = []): Promise<FindResult> {
  await resolveStale(repo, now);
  for (const a of await repo.openAttacksBy(uid)) await abandon(repo, a.id, now);  // a new attack forfeits the old one
  const p = await repo.getPlayer(uid);
  if (!p || !(await repo.getColony(uid))) return { error: "no_colony" };
  const loadout = practice ? [] : cleanLoadout(rawLoadout);
  const need = loadoutNeeds(loadout);
  if (loadout.length && !(await repo.takeBoosters(uid, need))) return { error: "no_boosters" };  // atomic, all or nothing
  const dots = await repo.consumeDots(uid, MIN_ATTACK_DOTS);  // atomic: parallel finds cannot reuse dots
  if (dots < 0) {
    if (loadout.length) await repo.grant(uid, 0, need);  // refund the boosters
    return { error: "few_dots" };
  }

  const cands = practice ? [] : await repo.candidates(p.trophies - RANGE, p.trophies + RANGE, uid, now, MAX_CANDIDATES);
  for (let i = cands.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [cands[i], cands[j]] = [cands[j], cands[i]];
  }
  const base = { attacker: uid, dots, status: "open" as const, commands: null, result: null, created_at: now, finished_at: null, loadout };
  let row: AttackRow | null = null;
  for (const d of cands) {
    const col = await repo.getColony(d);
    const dc = col && ColonyState.fromDict(col.data);
    if (!dc) continue;
    const r: AttackRow = { ...base, id: newId(), defender: d, bot: null, snapshot: dc.toDict(),
      seed: Math.floor(rand() * 2 ** 31), loot_pool: idiv(UNPROTECTED_PCT * Math.max(0, dc.energy), 100) };
    if (await repo.insertAttack(r)) { row = r; break; }
  }
  if (!row) {
    const seed = (p.attacks + 1) * 7919 + p.trophies;
    const bot = BotColony.generate(p.trophies, seed);
    row = { ...base, id: newId(), defender: null, bot: practice ? { trophies: p.trophies, seed, practice: true } : { trophies: p.trophies, seed }, snapshot: bot.colony.toDict(),
      seed, loot_pool: bot.lootPool };
    if (!(await repo.insertAttack(row))) {
      if (loadout.length) await repo.grant(uid, 0, need);  // refund (dots are lost with the attempt anyway)
      return { error: "busy" };
    }
  }
  await repo.adjustPlayer(uid, 0, 1, null);
  return { attack_id: row.id, snapshot: disguise(row.snapshot), loot_pool: row.loot_pool, seed: row.seed,
    dots: row.dots, bot: row.bot, loadout };
}
