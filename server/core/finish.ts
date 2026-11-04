// Attack verification: replays the client's commands on the stored snapshot and settles it.
import { idiv } from "../sim/fx.ts";
import { ColonyState } from "../game/colony.ts";
import { runBattle, MAX_COMMANDS } from "../game/run_battle.ts";
import type { Result } from "../game/match.ts";
import type { Repo } from "./repo.ts";

export const SHIELD_SECS = 8 * 3600;

export async function finishAttack(repo: Repo, uid: string, attackId: string, commands: unknown,
  surrenderTick: unknown, now: number): Promise<{ error?: string; result?: Result }> {
  const a = await repo.getAttack(String(attackId));
  if (!a) return { error: "not_found" };
  if (a.attacker !== uid) return { error: "forbidden" };
  if (a.status === "done") return { result: a.result };
  if (a.status !== "open") return { error: "abandoned" };
  const defender = ColonyState.fromDict(a.snapshot)!;
  const st = typeof surrenderTick === "number" && Number.isFinite(surrenderTick) ? Math.trunc(surrenderTick) : -1;
  const cmds = Array.isArray(commands) ? commands.slice(0, MAX_COMMANDS) : [];
  const { result } = runBattle(defender, a.loot_pool, a.dots, a.seed, cmds, st);
  await repo.updateAttack(a.id, { status: "done", result, commands: cmds, finished_at: now });

  const p = await repo.getPlayer(uid);
  if (p) await repo.putPlayer({ ...p, trophies: Math.max(0, p.trophies + result.trophies) });
  const mine = await repo.getColony(uid);
  const mc = mine && ColonyState.fromDict(mine.data);
  if (mine && mc) {
    mc.energy += result.loot;
    mc.attackOpen = 0;
    mc.trophies = Math.max(0, (p?.trophies ?? 0) + result.trophies);
    await repo.putColony(uid, { data: mc.toDict(), synced_at: mine.synced_at });
  }
  if (a.defender) {
    const d = await repo.getPlayer(a.defender);
    const won = result.stars >= 1;
    if (d) {
      await repo.putPlayer({ ...d, trophies: Math.max(0, d.trophies - (won ? idiv(result.trophies, 2) : 0)),
        shield_until: won ? now + SHIELD_SECS : d.shield_until });
    }
    const dcol = await repo.getColony(a.defender);
    const dc = dcol && ColonyState.fromDict(dcol.data);
    if (dcol && dc && result.loot > 0) {
      dc.energy = Math.max(0, dc.energy - result.loot);
      await repo.putColony(a.defender, { data: dc.toDict(), synced_at: dcol.synced_at });
    }
  }
  return { result };
}
