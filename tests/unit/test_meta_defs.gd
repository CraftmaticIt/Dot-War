extends GutTest

func test_leagues_match_server_table():
	assert_eq([0, 399, 400, 800, 1200, 1600, 5000].map(func(t): return MetaDefs.league_of(t)), [0, 0, 1, 2, 3, 4, 4])
	assert_eq(MetaDefs.league_name(2), "Złoto")

func test_boosters_and_prices():
	assert_eq(MetaDefs.booster_ids(), ["rage", "shield", "emp", "split"])
	assert_eq(MetaDefs.booster_price("split"), 25)
	assert_eq(MetaDefs.booster_name("rage"), "Szał")
	for b in MetaDefs.booster_ids():
		assert_true(SimWorld.BOOST_TICKS.has(b), "every shop booster exists in the sim")

func test_quest_lookup():
	assert_eq(MetaDefs.quest("win2").target, 2.0)
	assert_eq(MetaDefs.quest("nope"), {})
	assert_eq(MetaDefs.max_loadout(), BattleMatch.MAX_BOOSTS)
