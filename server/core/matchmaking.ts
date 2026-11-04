// Opponent selection: players within ±200 trophies without shield/open attack, else a bot.
import { idiv } from "../sim/fx.ts";
import { ColonyState } from "../game/colony.ts";
import { BotColony } from "../game/bot_colony.ts";
import type { AttackRow, Repo } from "./repo.ts";

export const RANGE = 200;
export const MAX_CANDIDATES = 20;
export const ABANDON_SECS = 600;
export const ABANDON_TROPHIES = -8;
export const MIN_ATTACK_DOTS = 10;
export const UNPROTECTED_PCT = 80;

export type FindResult = {
  error?: string; attack_id?: string; snapshot?: any; loot_pool?: number; seed?: number; dots?: number;
  bot?: { trophies: number; seed: number } | null;
};

async function abandon(repo: Repo, a: AttackRow, now: number): Promise<void> {
  await repo.updateAttack(a.id, { status: "abandoned", finished_at: now,
    result: { stars: 0, destroyed_pct: 0, loot: 0, trophies: ABANDON_TROPHIES } });
  const p = await repo.getPlayer(a.attacker);
  if (p) await repo.putPlayer({ ...p, trophies: Math.max(0, p.trophies + ABANDON_TROPHIES) });
}

export async function resolveStale(repo: Repo, now: number): Promise<void> {
  for (const a of await repo.openAttacks(now - ABANDON_SECS)) await abandon(repo, a, now);
}

export async function findOpponent(repo: Repo, uid: string, now: number, rand: () => number,
  newId: () => string = () => crypto.randomUUID()): Promise<FindResult> {
  await resolveStale(repo, now);
  for (const a of await repo.openAttacksBy(uid)) await abandon(repo, a, now);  // starting a new attack forfeits the old one
  const stored = await repo.getColony(uid);
  const p = await repo.getPlayer(uid);
  if (!stored || !p) return { error: "no_colony" };
  const me = ColonyState.fromDict(stored.data)!;
  if (me.dots < MIN_ATTACK_DOTS) return { error: "few_dots" };

  const cands = await repo.candidates(p.trophies - RANGE, p.trophies + RANGE, uid, now, MAX_CANDIDATES);
  for (let i = cands.length - 1; i > 0; i--) {  // Fisher-Yates with injected rand
    const j = Math.floor(rand() * (i + 1));
    [cands[i], cands[j]] = [cands[j], cands[i]];
  }
  const base = { attacker: uid, dots: me.dots, status: "open" as const, commands: null, result: null,
    created_at: now, finished_at: null };
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
    row = { ...base, id: newId(), defender: null, bot: { trophies: p.trophies, seed }, snapshot: bot.colony.toDict(),
      seed, loot_pool: bot.lootPool };
    await repo.insertAttack(row);
  }
  me.dots = 0;
  me.dotsRem = 0;
  me.attackOpen = 1;
  await repo.putColony(uid, { data: me.toDict(), synced_at: stored.synced_at });
  await repo.putPlayer({ ...p, attacks: p.attacks + 1 });
  return { attack_id: row.id, snapshot: row.snapshot, loot_pool: row.loot_pool, seed: row.seed, dots: row.dots, bot: row.bot };
}
