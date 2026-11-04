// Cross-language contract: battles generated in GDScript must replay identically in TS.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { ColonyState } from "../game/colony.ts";
import { BotColony } from "../game/bot_colony.ts";
import { runBattle } from "../game/run_battle.ts";

const DIR = new URL("../../tests/battle_vectors/", import.meta.url);
const files = readdirSync(DIR).filter((f) => f.endsWith(".json")).sort();

test("at least five battle vectors", () => assert.ok(files.length >= 5));

for (const f of files) {
  test(`battle ${f}`, () => {
    const v = JSON.parse(readFileSync(new URL(f, DIR), "utf8"));
    let defender: ColonyState;
    if (v.bot) {
      const bot = BotColony.generate(v.bot.trophies, v.bot.seed);
      assert.deepEqual(bot.colony.toDict(), v.bot_colony, "bot colony identical");
      assert.equal(bot.lootPool, v.loot_pool);
      defender = bot.colony;
    } else {
      defender = ColonyState.fromDict(v.defender)!;
    }
    const r = runBattle(defender, v.loot_pool, v.dots, v.seed, v.commands, v.surrender_tick);
    assert.deepEqual(r.result, v.expected.result);
    assert.equal(r.ticks, v.expected.ticks);
    assert.equal(r.hash, v.expected.hash);
  });
}
