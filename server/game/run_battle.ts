// Server-side replay of an attack from recorded commands (same loop as tools/gen_battle_vectors.gd).
import { ColonyState } from "./colony.ts";
import { buildAttack, DEFENDER } from "./attack_setup.ts";
import { BattleMatch, type Result } from "./match.ts";

export const MAX_COMMANDS = 2000;

export function runBattle(defender: ColonyState, lootPool: number, dots: number, seed: number,
  commands: unknown, surrenderTick = -1): { result: Result; hash: number; ticks: number } {
  const cmds = Array.isArray(commands) ? commands.slice(0, MAX_COMMANDS) : [];
  const m = new BattleMatch(buildAttack(defender.toSimGraph(DEFENDER), dots, seed), defender.coreNodeId(), lootPool);
  while (!m.over) {
    if (surrenderTick >= 0 && m.world.tick >= surrenderTick) { m.surrender(); break; }
    for (const c of cmds) {
      if (c && typeof c === "object" && typeof (c as any).tick === "number" && Math.trunc((c as any).tick) === m.world.tick) {
        m.sendRaw(c);
      }
    }
    m.step();
  }
  return { result: m.result(), hash: m.world.stateHash(), ticks: m.world.tick };
}
