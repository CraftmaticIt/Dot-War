extends GutTest

func test_bot_deterministic():
	var a := BotColony.generate(250, 42)
	var b := BotColony.generate(250, 42)
	assert_eq(a.colony.to_dict(), b.colony.to_dict())
	assert_eq(a.loot_pool, b.loot_pool)

func test_bot_seed_changes_layout():
	assert_ne(BotColony.generate(250, 1).colony.to_dict(), BotColony.generate(250, 2).colony.to_dict())

func test_bot_scales_with_trophies():
	assert_eq(BotColony.generate(0, 1).colony.core_level(), 1)
	assert_eq(BotColony.generate(450, 1).colony.core_level(), 3)
	assert_eq(BotColony.generate(900, 1).colony.core_level(), 5)
	assert_eq(BotColony.generate(5000, 1).colony.core_level(), 5)

func test_bot_loot_pool():
	assert_eq(BotColony.generate(100, 1).loot_pool, 600)

func test_bot_connected():
	for seed in 20:
		var col: ColonyState = BotColony.generate(seed * 50, seed).colony
		var g := col.to_sim_graph(2)
		var ids := g.node_ids()
		for id in ids:
			assert_false(g.path(ids[0], id).is_empty(), "node %d reachable (seed %d)" % [id, seed])

func test_bot_within_node_limit():
	for seed in 20:
		var c: ColonyState = BotColony.generate(seed * 50, seed).colony
		var lim: int = BotColony.NODES[c.core_level() - 1]
		assert_between(c.cells.size(), lim - 2, lim)
		for k in c.cells:
			assert_between(c.cells[k].level, 1, c.core_level())
			assert_eq(c.cells[k].build_end, 0)
