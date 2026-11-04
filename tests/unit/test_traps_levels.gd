extends GutTest

func _send(w: SimWorld, from: int, to: int, pct: int, owner: int = 1) -> void:
	w.queue({"tick": w.tick, "type": "send", "owner": owner, "from": from, "to": to, "percent": pct})

func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()

func _events(w: SimWorld, type: String) -> Array:
	return w.events.filter(func(e): return e.type == type)

func _trap_world(trap: int, src_garrison: int, target_owner: int = 2, target_garrison: int = 0) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, src_garrison, 0)
	g.add_node(2, 3000, 0, target_owner, target_garrison, 0, "", trap)
	g.link(1, 2)
	return SimWorld.new(g, 1)

func test_trap_kills_and_disarms():
	var w := _trap_world(10, 30)   # group of 15
	_send(w, 1, 2, 50)
	_steps(w, 19)
	w.step()
	var n := w.graph.node(2)
	assert_eq(n.trap, 0)
	assert_eq(n.owner, 1)
	assert_eq(n.garrison, 5)
	var ev := _events(w, "trap_triggered")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0].killed, 10)

func test_trap_ignores_owner_groups():
	var w := _trap_world(10, 30, 1, 0)
	_send(w, 1, 2, 50)
	_steps(w, 20)
	assert_eq(w.graph.node(2).trap, 10)
	assert_eq(w.graph.node(2).garrison, 15)

func test_trap_kills_whole_small_group_no_fight():
	var w := _trap_world(10, 8, 2, 3)  # group of 4
	_send(w, 1, 2, 50)
	_steps(w, 20)
	var n := w.graph.node(2)
	assert_eq(n.owner, 2)
	assert_eq(n.garrison, 3, "no fight happened")
	assert_eq(n.trap, 0)

func test_trap_same_tick_lower_id_only():
	var g := SimGraph.new()
	g.add_node(1, -3000, 0, 1, 30, 0)
	g.add_node(3, 3000, 0, 1, 10, 0)
	g.add_node(2, 0, 0, 2, 0, 0, "", 10)
	g.link(1, 2); g.link(3, 2)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 2, 50)  # id0: 15
	_send(w, 3, 2, 50)  # id1: 5
	_steps(w, 19)
	w.step()
	var ev := _events(w, "trap_triggered")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0].group, 0)
	assert_eq(w.graph.node(2).owner, 1)
	assert_eq(w.graph.node(2).garrison, 10)

func _laser_lane(lvl: int) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 40, 0)
	g.add_node(2, 30000, 0, 1, 0, 0)
	g.add_node(9, 0, 1000, 2, 0, 0, "laser", 0, lvl)
	g.link(1, 2)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 2, 50)
	return w

func test_tower_lvl_scales_damage():
	var w1 := _laser_lane(1)
	w1.step()
	assert_eq(w1.groups[0].dmg_acc, 200)
	var w4 := _laser_lane(4)
	w4.step()
	assert_eq(w4.groups[0].dmg_acc, 400)

func test_graph_dict_has_trap_and_lvl():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 2, 0, 0, "pulse", 0, 3)
	g.add_node(2, 0, 0, 2, 0, 0, "", 20)
	var d := g.to_dict()
	assert_eq(d.nodes[0].tower_lvl, 3)
	assert_eq(d.nodes[1].trap, 20)
	var back := SimGraph.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.to_dict(), d)

func test_from_dict_defaults():
	var back := SimGraph.from_dict({"nodes": [{"id": 1, "x": 0, "y": 0, "owner": 1, "garrison": 1, "prod_per_sec": 0}], "links": []})
	assert_eq(back.node(1).trap, 0)
	assert_eq(back.node(1).tower_lvl, 1)

func test_canonical_unchanged_without_trap():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 5, 0)
	assert_eq(SimWorld.new(g, 1).canonical(), "t0|n1,1,5,0")

func test_canonical_includes_armed_trap():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 2, 0, 0, "", 10)
	assert_eq(SimWorld.new(g, 1).canonical(), "t0|n1,2,0,0,t10")
