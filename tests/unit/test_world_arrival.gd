extends GutTest

func _send(w: SimWorld, from: int, to: int, pct: int, owner: int) -> void:
	w.queue({"tick": w.tick, "type": "send", "owner": owner, "from": from, "to": to, "percent": pct})

func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()

func _pair(target_owner: int, target_garrison: int, src_garrison: int = 20) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, src_garrison, 0)
	g.add_node(2, 3000, 0, target_owner, target_garrison, 0)
	g.link(1, 2)
	return SimWorld.new(g, 1)

func test_group_reaches_target_after_expected_ticks():
	var w := _pair(1, 0)
	_send(w, 1, 2, 50, 1)
	_steps(w, 19)
	assert_eq(w.groups.size(), 1, "still flying after 19 ticks")
	w.step()
	assert_eq(w.groups.size(), 0, "arrived on tick 20")
	assert_eq(w.graph.node(2).garrison, 10)

func test_reinforce_own_node():
	var w := _pair(1, 3)
	_send(w, 1, 2, 50, 1)
	_steps(w, 20)
	assert_eq(w.graph.node(2).garrison, 13)
	assert_eq(w.graph.node(2).owner, 1)

func test_capture_enemy_node():
	var w := _pair(2, 4)
	_send(w, 1, 2, 50, 1)  # 10 dots
	_steps(w, 20)
	var n := w.graph.node(2)
	assert_eq(n.owner, 1)
	assert_eq(n.garrison, 6)

func test_capture_emits_event():
	var w := _pair(0, 4)
	_send(w, 1, 2, 50, 1)
	_steps(w, 19)
	w.step()
	var found := false
	for e in w.events:
		if e.type == "node_captured" and e.node == 2 and e.owner == 1:
			found = true
	assert_true(found)

func test_capture_resets_prod_acc():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 20, 0)
	g.add_node(2, 2850, 0, 2, 1, 1)  # 19 ticks away: prod_acc = 19 just before capture
	g.link(1, 2)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 2, 50, 1)
	_steps(w, 18)
	assert_eq(w.graph.node(2).prod_acc, 18)
	w.step()
	assert_eq(w.graph.node(2).owner, 1)
	assert_eq(w.graph.node(2).prod_acc, 0)

func test_tie_defender_keeps():
	var w := _pair(2, 10)
	_send(w, 1, 2, 50, 1)
	_steps(w, 20)
	assert_eq(w.graph.node(2).owner, 2)
	assert_eq(w.graph.node(2).garrison, 0)

func test_owner_changed_midflight():
	# Owner 1 reinforces node 2, but owner 2 captures it first; reinforcement must fight.
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 20, 0)
	g.add_node(2, 6000, 0, 1, 1, 0)
	g.add_node(3, 7500, 0, 2, 20, 0)
	g.link(1, 2); g.link(2, 3)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 2, 50, 1)   # 10 dots, arrives tick 40
	_send(w, 3, 2, 50, 2)   # 10 dots, arrives tick 10 -> captures with 9
	_steps(w, 40)
	var n := w.graph.node(2)
	assert_eq(n.owner, 1, "reinforcement re-captures")
	assert_eq(n.garrison, 1)

func test_same_tick_two_attackers_order_by_id():
	var g := SimGraph.new()
	g.add_node(1, -3000, 0, 1, 14, 0)
	g.add_node(2, 3000, 0, 2, 8, 0)
	g.add_node(3, 0, 0, 0, 5, 0)
	g.link(1, 3); g.link(2, 3)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 3, 50, 1)  # id0: 7
	_send(w, 2, 3, 50, 2)  # id1: 4
	_steps(w, 20)
	var n := w.graph.node(3)
	assert_eq(n.owner, 2)
	assert_eq(n.garrison, 2)

func test_passes_through_own_intermediate_node():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 20, 0)
	g.add_node(2, 1500, 0, 1, 0, 0)
	g.add_node(3, 3000, 0, 2, 1, 0)
	g.link(1, 2); g.link(2, 3)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 3, 50, 1)
	_steps(w, 20)
	assert_eq(w.graph.node(2).garrison, 0)
	assert_eq(w.graph.node(3).owner, 1)
	assert_eq(w.graph.node(3).garrison, 9)

func test_stops_at_enemy_intermediate_node():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 20, 0)
	g.add_node(2, 1500, 0, 2, 3, 0)
	g.add_node(3, 3000, 0, 2, 1, 0)
	g.link(1, 2); g.link(2, 3)
	var w := SimWorld.new(g, 1)
	_send(w, 1, 3, 50, 1)
	_steps(w, 40)
	assert_eq(w.groups.size(), 0)
	assert_eq(w.graph.node(2).owner, 1)
	assert_eq(w.graph.node(2).garrison, 7)
	assert_eq(w.graph.node(3).owner, 2)

func test_group_position_interpolates():
	var w := _pair(1, 0)
	_send(w, 1, 2, 50, 1)
	_steps(w, 10)
	assert_eq(w.group_pos(w.groups[0]), Vector2i(1500, 0))
