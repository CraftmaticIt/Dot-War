extends GutTest
## GDScript side of the battle contract (server/test/battle_vectors.test.ts is the TS side).

const DIR := "res://tests/battle_vectors/"

func test_battle_vectors_replay():
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".json"))
	assert_gte(files.size(), 5)
	for f in files:
		var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var defender: ColonyState
		var pool: int = int(v.loot_pool)
		if v.bot != null:
			var bot := BotColony.generate(int(v.bot.trophies), int(v.bot.seed))
			assert_eq(bot.colony.to_dict(), ColonyState.from_dict(v.bot_colony).to_dict(), f)
			defender = bot.colony
		else:
			defender = ColonyState.from_dict(v.defender)
		var ids := defender.snapshot_ids()
		var core := 1
		for id in ids:
			if ids[id] == Vector2i.ZERO:
				core = id
		var m := BattleMatch.new(AttackSetup.build(defender.to_sim_graph(AttackSetup.DEFENDER), int(v.dots), int(v.seed)), core, pool,
			v.get("loadout", []))
		var stop := int(v.surrender_tick)
		while not m.over:
			if stop >= 0 and m.world.tick >= stop:
				m.surrender()
				break
			for c in v.commands:
				if typeof(c.get("tick")) in [TYPE_INT, TYPE_FLOAT] and int(c.tick) == m.world.tick:
					m.send_raw(c)
			m.step()
		var r := m.result()
		assert_eq(r.stars, int(v.expected.result.stars), f)
		assert_eq(r.loot, int(v.expected.result.loot), f)
		assert_eq(r.trophies, int(v.expected.result.trophies), f)
		assert_eq(m.world.state_hash(), int(v.expected.hash), f)
