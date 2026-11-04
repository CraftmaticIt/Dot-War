extends GutTest

func _match(loadout: Array) -> BattleMatch:
	var g := SimGraph.new()
	g.add_node(1, 6000, 0, AttackSetup.DEFENDER, 30, 0)
	return BattleMatch.new(AttackSetup.build(g, 30, 1), 1, 100, loadout)

func test_loadout_limits_and_consumes():
	var m := _match(["rage", "emp", "rage", "split"])
	assert_eq(m.boosts_left, ["rage", "emp", "rage"], "max 3")
	assert_true(m.boost("rage", 1))
	assert_eq(m.boosts_left, ["emp", "rage"])
	m.step()
	assert_eq(m.world.effects.size(), 1)

func test_booster_not_in_loadout_ignored():
	var m := _match(["emp"])
	assert_false(m.boost("rage", 1))
	m.send_raw({"type": "boost", "booster": "split", "node": 1})
	m.step()
	assert_eq(m.world.effects.size(), 0)
	assert_eq(m.boosts_left, ["emp"])

func test_fourth_booster_ignored():
	var m := _match(["emp", "emp", "emp", "emp"])
	for i in 4:
		m.send_raw({"type": "boost", "booster": "emp", "node": 1})
	m.step()
	assert_eq(m.world.effects.size(), 3)

func test_unknown_loadout_entries_dropped():
	var m := _match(["nuke", 5, null, "shield"])
	assert_eq(m.boosts_left, ["shield"])

func test_bad_node_still_consumes():
	var m := _match(["rage"])
	m.send_raw({"type": "boost", "booster": "rage", "node": "x"})
	m.step()
	assert_eq(m.boosts_left, [], "consumed when sent, even if the sim rejects it")
