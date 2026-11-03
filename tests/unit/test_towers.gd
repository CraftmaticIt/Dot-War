extends GutTest

## Lane: source (owner 1) -> far target (owner 1), plus an unlinked tower node.
func _lane(tower: String, tower_x: int, tower_y: int, tower_owner: int = 2, garrison: int = 40) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, garrison, 0)
	g.add_node(2, 30000, 0, 1, 0, 0)
	g.add_node(9, tower_x, tower_y, tower_owner, 0, 0, tower)
	g.link(1, 2)
	var w := SimWorld.new(g, 1)
	w.queue({"tick": 0, "type": "send", "owner": 1, "from": 1, "to": 2, "percent": 50})
	return w

func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()

func test_specs():
	assert_eq(SimTowers.SPECS.laser, {"range": 4000, "dmg": 200})
	assert_eq(SimTowers.SPECS.pulse, {"range": 2000, "dmg": 60})

func test_laser_kills_4_per_sec():
	var w := _lane("laser", 0, 1000)
	_steps(w, 20)
	assert_eq(w.groups[0].count, 16)

func test_laser_out_of_range_no_dmg():
	var w := _lane("laser", 0, 5000)
	_steps(w, 20)
	assert_eq(w.groups[0].count, 20)
	assert_eq(w.groups[0].dmg_acc, 0)

func test_tower_ignores_own_groups():
	var w := _lane("laser", 0, 1000, 1)
	_steps(w, 20)
	assert_eq(w.groups[0].count, 20)

func test_neutral_tower_does_not_fire():
	var w := _lane("laser", 0, 1000, 0)
	_steps(w, 20)
	assert_eq(w.groups[0].count, 20)

func test_group_destroyed_removed_same_tick():
	var w := _lane("laser", 0, 1000, 2, 2)  # group of 1
	_steps(w, 4)
	assert_eq(w.groups.size(), 1)
	w.step()
	assert_eq(w.groups.size(), 0)
	var found := false
	for e in w.events:
		if e.type == "group_destroyed":
			found = true
	assert_true(found)

func _two_lanes(tower: String, y_a: int, y_b: int, tower_y: int, x0: int, x1: int) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, x0, y_a, 1, 40, 0)
	g.add_node(2, x1, y_a, 1, 0, 0)
	g.add_node(3, x0, y_b, 1, 40, 0)
	g.add_node(4, x1, y_b, 1, 0, 0)
	g.add_node(9, 0, tower_y, 2, 0, 0, tower)
	g.link(1, 2); g.link(3, 4)
	var w := SimWorld.new(g, 1)
	w.queue({"tick": 0, "type": "send", "owner": 1, "from": 1, "to": 2, "percent": 50})  # id0
	w.queue({"tick": 0, "type": "send", "owner": 1, "from": 3, "to": 4, "percent": 50})  # id1
	return w

func test_laser_tie_lower_id():
	var w := _two_lanes("laser", 0, 2000, 1000, 0, 30000)
	_steps(w, 5)  # 5 * 200 = 1000 -> one dot
	assert_eq(w.groups[0].count, 19)
	assert_eq(w.groups[1].count, 20)

func test_pulse_hits_all_in_range():
	var w := _two_lanes("pulse", 0, 200, 100, -10000, 10000)
	_steps(w, 100)
	assert_eq(w.groups.size(), 2)
	assert_eq(w.groups[0].count, 19)
	assert_eq(w.groups[1].count, 19)
