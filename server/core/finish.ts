// Attack verification: replays the client's commands on the stored (real) snapshot and
// settles it. The open -> settling claim is atomic, so only one request ever settles.
import { idiv } from "../sim/fx.ts";
import { ColonyState } from "../game/colony.ts";
import { runBattle, MAX_COMMANDS } from "../game/run_battle.ts";
import type { Result } from "../game/match.ts";
import type { Repo } from "./repo.ts";

export const SHIELD_SECS = 8 * 3600;

export async function finishAttack(repo: Repo, uid: string, attackId: unknown, commands: unknown,
  surrenderTick: unknown, now: number): Promise<{ error?: string; result?: Result }> {
  const id = String(attackId);
  const a = await repo.claimAttack(id, uid);
  if (!a) {
    const cur = await repo.getAttack(id);
    if (!cur) return { error: "not_found" };
    if (cur.attacker !== uid) return { error: "forbidden" };
    if (cur.status === "done") return { result: cur.result };
    return { error: cur.status === "settling" ? "in_progress" : "abandoned" };
  }
  const defender = ColonyState.fromDict(a.snapshot)!;
  const st = typeof surrenderTick === "number" && Number.isFinite(surrenderTick) ? Math.trunc(surrenderTick) : -1;
  const cmds = Array.isArray(commands) ? commands.slice(0, MAX_COMMANDS) : [];
  const { result } = runBattle(defender, a.loot_pool, a.dots, a.seed, cmds, st);
  await repo.completeAttack(a.id, result, cmds, now);
  await repo.adjustPlayer(uid, result.trophies, 0, null);
  await repo.creditEnergy(uid, result.loot, true);
  if (a.defender && result.stars >= 1) {
    await repo.adjustPlayer(a.defender, -idiv(result.trophies, 2), 0, now + SHIELD_SECS);
    if (result.loot > 0) await repo.creditEnergy(a.defender, -result.loot, false);
  }
  return { result };
}
