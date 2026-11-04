// Attack verification: replays the client's commands on the stored (real) snapshot and
// settles it. The open -> settling claim is atomic, so only one request ever settles,
// which also makes quest progress and chests one-shot.
import { idiv } from "../sim/fx.ts";
import { ColonyState } from "../game/colony.ts";
import { runBattle, MAX_COMMANDS } from "../game/run_battle.ts";
import type { Result } from "../game/match.ts";
import { rollChest } from "../game/meta.ts";
import type { Repo } from "./repo.ts";
import { questEvents, type QuestRewards } from "./profile.ts";

export const SHIELD_SECS = 8 * 3600;

export type FinishResult = {
  error?: string; result?: Result;
  rewards?: { quests: string[]; chest: { boosters: Record<string, number>; crystals: number } | null };
};

export async function finishAttack(repo: Repo, uid: string, attackId: unknown, commands: unknown,
  surrenderTick: unknown, now: number, rand: () => number = Math.random): Promise<FinishResult> {
  const id = String(attackId);
  const a = await repo.claimAttack(id, uid);
  if (!a) {
    const cur = await repo.getAttack(id);
    if (!cur) return { error: "not_found" };
    if (cur.attacker !== uid) return { error: "forbidden" };
    if (cur.status === "done") return { result: cur.result };
    return { error: cur.status === "settling" ? "in_progress" : "abandoned" };
  }
  const practice = !!a.bot?.practice;
  const defender = ColonyState.fromDict(a.snapshot)!;
  const st = typeof surrenderTick === "number" && Number.isFinite(surrenderTick) ? Math.trunc(surrenderTick) : -1;
  const cmds = Array.isArray(commands) ? commands.slice(0, MAX_COMMANDS) : [];
  const replay = runBattle(defender, a.loot_pool, a.dots, a.seed, cmds, st, a.loadout ?? []);
  const result = practice ? { ...replay.result, loot: 0, trophies: 0 } : replay.result;
  await repo.completeAttack(a.id, result, cmds, now);
  await repo.adjustPlayer(uid, result.trophies, 0, null);
  await repo.creditEnergy(uid, result.loot, true);
  if (a.defender && result.stars >= 1) {
    await repo.adjustPlayer(a.defender, -idiv(result.trophies, 2), 0, now + SHIELD_SECS);
    if (result.loot > 0) await repo.creditEnergy(a.defender, -result.loot, false);
  }
  if (practice) return { result, rewards: { quests: [], chest: null } };

  const q: QuestRewards = await questEvents(repo, uid, [
    ["attack_win", result.stars >= 1 ? 1 : 0], ["stars", result.stars], ["destroyed_pct", result.destroyed_pct],
    ["boost_used", replay.boostsUsed]], now, rand);
  let chest = q.chest;
  if (result.stars === 3) {
    const c = rollChest(rand);
    await repo.grant(uid, c.crystals, c.boosters);
    chest = chest ? { boosters: { ...chest.boosters }, crystals: chest.crystals + c.crystals } : c;
    if (q.chest) for (const [k, n] of Object.entries(c.boosters)) chest.boosters[k] = (chest.boosters[k] ?? 0) + n;
  }
  if (a.defender && result.stars <= 1) await questEvents(repo, a.defender, [["defense", 1]], now, rand);
  return { result, rewards: { quests: q.completed.map((d) => d.text), chest } };
}
