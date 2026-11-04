// Deterministic bot colony (port of ai/bot_colony.gd).
import * as B from "./buildings.ts";
import * as Hex from "./hex.ts";
import { idiv } from "../sim/fx.ts";
import { SimRng } from "../sim/rng.ts";
import { ColonyState, GRID_RADIUS, hexDistance } from "./colony.ts";

/** Bot size per core level, frozen at the pre-balance node limits (keeps battle vectors). */
const BOT_NODES = [6, 9, 12, 16, 20];

const WEIGHTED = ["mine", "mine", "mine", "storage", "generator", "laser", "laser", "pulse", "pulse", "wall", "wall", "trap"];

export const BotColony = {
  generate(trophies: number, seed: number): { colony: ColonyState; lootPool: number } {
    const rng = new SimRng(seed);
    const coreLevel = Math.min(Math.max(1 + idiv(trophies, 200), 1), B.MAX_LEVEL);
    const c = new ColonyState();
    c.cells[Hex.key(0, 0)] = { type: "core", level: coreLevel, build_end: 0, target_level: coreLevel };
    const count = BOT_NODES[coreLevel - 1] - rng.rangeI(3);
    while (Object.keys(c.cells).length < count) {
      const cand = candidates(c);
      const [q, r] = cand[rng.rangeI(cand.length)];
      const type = WEIGHTED[rng.rangeI(WEIGHTED.length)];
      const lvl = Math.max(1, coreLevel - rng.rangeI(2));
      c.cells[Hex.key(q, r)] = { type, level: lvl, build_end: 0, target_level: lvl };
    }
    return { colony: c, lootPool: 300 + 3 * trophies };
  },
};

function candidates(c: ColonyState): [number, number][] {
  const seen = new Map<string, [number, number]>();
  for (const k of Object.keys(c.cells)) {
    const [q, r] = Hex.parse(k);
    for (const nb of Hex.neighbors(q, r)) {
      if (!(Hex.key(...nb) in c.cells) && hexDistance(...nb) <= GRID_RADIUS) seen.set(Hex.key(...nb), nb);
    }
  }
  return [...seen.values()].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
}
