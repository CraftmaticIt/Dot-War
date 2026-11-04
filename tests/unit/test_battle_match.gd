extends GutTest

## Defender nodes: id -> [x, y, garrison]; core is node 1.
func _match(defs: Dictionary, dots: int, pool: int = 1000) -> BattleMatch:
	var g := SimGraph.new()
	for id in defs:
		var d: Array = defs[id]
		g.add_node(id, d[0], d[1], AttackSetup.DEFENDER, d[2], 0)
	var ids := defs.keys()
	for i in range(1, ids.size()):
		g.link(ids[0], ids[i])
	return BattleMatch.new(AttackSetup.build(g, dots, 1), 1, pool)

func _run(m: BattleMatch, limit: int = 4000) -> void:
	var i := 0
	while not m.over and i < limit:
		m.step()
		i += 1

func _send_all(m: BattleMatch, to: int) -> void:
	for e in AttackSetup.ENTRY_IDS:
		m.send(e, to, 100)

func test_full_capture_three_stars():
	var m := _match({1: [6000, 0, 5]}, 30)
	_send_all(m, 1)
	_run(m)
	assert_true(m.over)
	var r := m.result()
	assert_eq(r.stars, 3)
	assert_eq(r.destroyed_pct, 100)
	assert_eq(r.loot, 1000)
	assert_eq(r.trophies, 30)
	assert_lt(m.world.tick, BattleMatch.DURATION_TICKS, "ended early at 100%")

func test_half_capture_one_star():
	var m := _match({1: [9000, 0, 500], 2: [6000, 0, 1]}, 30)
	_send_all(m, 2)
	_run(m)
	var r := m.result()
	assert_eq(r.destroyed_pct, 50)
	assert_eq(r.stars, 1)
	assert_eq(r.loot, 500)
	assert_eq(r.trophies, 10)

func test_time_limit_ends():
	var m := _match({1: [9000, 0, 500], 2: [6000, 0, 1]}, 30)
	_send_all(m, 2)
	_run(m)
	assert_eq(m.world.tick, BattleMatch.DURATION_TICKS)
	assert_eq(m.progress().ticks_left, 0)

func test_core_only_star():
	var m := _match({1: [6000, 0, 1], 2: [6000, 8000, 500], 3: [6000, -8000, 500]}, 30)
	m.send(1002, 1, 100)
	_run(m)
	var r := m.result()
	assert_eq(r.destroyed_pct, 33)
	assert_true(m.progress().core)
	assert_eq(r.stars, 1)

func test_no_dots_left_ends_early():
	var m := _match({1: [6000, 0, 500]}, 3)
	_send_all(m, 1)
	_run(m)
	assert_true(m.over)
	assert_lt(m.world.tick, 200)

func test_zero_stars_no_loot_trophies_minus():
	var m := _match({1: [6000, 0, 500]}, 3)
	_send_all(m, 1)
	_run(m)
	var r := m.result()
	assert_eq(r.stars, 0)
	assert_eq(r.loot, 0)
	assert_eq(r.trophies, -8)

func test_loot_scales_with_destroyed():
	var m := _match({1: [9000, 0, 500], 2: [6000, 0, 1]}, 30, 777)
	_send_all(m, 2)
	_run(m)
	assert_eq(m.result().loot, 777 * 50 / 100)

func test_send_after_over_ignored():
	var m := _match({1: [6000, 0, 5]}, 30)
	_send_all(m, 1)
	_run(m)
	var t := m.world.tick
	m.send(1001, 1, 50)
	m.step()
	assert_eq(m.world.tick, t)

func test_progress_initial():
	var m := _match({1: [6000, 0, 5], 2: [6000, 5000, 5]}, 30)
	assert_eq(m.progress(), {"destroyed_pct": 0, "core": false, "stars": 0, "ticks_left": BattleMatch.DURATION_TICKS})

func test_send_raw_rejects_malformed_without_crash():
	var m := _match({1: [6000, 0, 5]}, 30)
	m.send_raw({"from": "1001", "to": 1, "percent": 50})
	m.send_raw({"to": 1})
	m.step()
	assert_eq(m.world.groups.size(), 0)
	assert_eq(m.world.events.filter(func(e): return e.type == "cmd_rejected").size(), 2)
