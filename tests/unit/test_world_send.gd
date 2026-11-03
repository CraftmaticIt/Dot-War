extends GutTest

func _line_world(garrison: int = 10, prod: int = 0) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, garrison, prod)
	g.add_node(2, 3000, 0, 0, 5, 0)
	g.add_node(3, 9000, 0, 2, 5, 0)  # not linked
	g.link(1, 2)
	return SimWorld.new(g, 1)

func _send(w: SimWorld, from: int, to: int, pct: int, owner: int = 1, tick: int = -1) -> void:
	w.queue({"tick": w.tick if tick < 0 else tick, "type": "send", "owner": owner,
		"from": from, "to": to, "percent": pct})

func _has_event(w: SimWorld, type: String) -> bool:
	for e in w.events:
		if e.type == type:
			return true
	return false

func test_production_one_per_sec():
	var w := _line_world(10, 1)
	for i in SimWorld.TICK_HZ:
		w.step()
	assert_eq(w.graph.node(1).garrison, 11)

func test_production_not_early():
	var w := _line_world(10, 1)
	for i in SimWorld.TICK_HZ - 1:
		w.step()
	assert_eq(w.graph.node(1).garrison, 10)

func test_neutral_no_production():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 0, 3, 5)
	var w := SimWorld.new(g, 1)
	for i in 100:
		w.step()
	assert_eq(w.graph.node(1).garrison, 3)

func test_send_half():
	var w := _line_world(10)
	_send(w, 1, 2, 50)
	w.step()
	assert_eq(w.graph.node(1).garrison, 5)
	assert_eq(w.groups.size(), 1)
	assert_eq(w.groups[0].count, 5)
	assert_eq(w.groups[0].owner, 1)
	assert_eq(w.groups[0].path, PackedInt32Array([1, 2]))
	assert_true(_has_event(w, "group_spawned"))

func test_send_future_tick_waits():
	var w := _line_world(10)
	_send(w, 1, 2, 50, 1, 3)
	w.step(); w.step(); w.step()
	assert_eq(w.groups.size(), 0)
	w.step()
	assert_eq(w.groups.size(), 1)

func test_send_rejected_not_owner():
	var w := _line_world(10)
	_send(w, 1, 2, 50, 2)
	w.step()
	assert_eq(w.groups.size(), 0)
	assert_true(_has_event(w, "cmd_rejected"))

func test_send_rejected_percent_0_and_101():
	var w := _line_world(10)
	_send(w, 1, 2, 0)
	_send(w, 1, 2, 101)
	w.step()
	assert_eq(w.groups.size(), 0)
	assert_eq(w.graph.node(1).garrison, 10)

func test_send_rejected_no_path():
	var w := _line_world(10)
	_send(w, 1, 3, 50)
	w.step()
	assert_eq(w.groups.size(), 0)
	assert_true(_has_event(w, "cmd_rejected"))

func test_send_rejected_zero_count():
	var w := _line_world(1)
	_send(w, 1, 2, 50)  # 1*50/100 = 0
	w.step()
	assert_eq(w.groups.size(), 0)
	assert_true(_has_event(w, "cmd_rejected"))

func test_send_rejected_unknown_node():
	var w := _line_world(10)
	_send(w, 99, 2, 50)
	w.step()
	assert_true(_has_event(w, "cmd_rejected"))

func test_events_cleared_each_step():
	var w := _line_world(10)
	_send(w, 1, 2, 0)
	w.step()
	w.step()
	assert_eq(w.events.size(), 0)

func _run(cmds: Array) -> int:
	var w := _line_world(10, 2)
	for c in cmds:
		w.queue(c)
	for i in 200:
		w.step()
	return w.state_hash()

func test_hash_same_for_same_input():
	var c := [{"tick": 5, "type": "send", "owner": 1, "from": 1, "to": 2, "percent": 50}]
	assert_eq(_run(c), _run(c.duplicate(true)))

func test_hash_differs_on_different_cmd():
	var a := [{"tick": 5, "type": "send", "owner": 1, "from": 1, "to": 2, "percent": 50}]
	var b := [{"tick": 5, "type": "send", "owner": 1, "from": 1, "to": 2, "percent": 60}]
	assert_ne(_run(a), _run(b))

func test_hash_is_u32():
	var h := _run([])
	assert_true(h >= 0 and h <= 0xFFFFFFFF)

func test_malformed_cmd_missing_field_rejected():
	var w := _line_world(10)
	w.queue({"tick": 0, "type": "send", "owner": 1, "to": 2, "percent": 50})
	w.step()
	assert_eq(w.groups.size(), 0)
	assert_true(_has_event(w, "cmd_rejected"))

func test_malformed_cmd_non_numeric_rejected():
	var w := _line_world(10)
	w.queue({"tick": 0, "type": "send", "owner": 1, "from": "x", "to": 2, "percent": 50})
	w.queue({"type": "send"})
	w.step()
	assert_eq(w.groups.size(), 0)
	var n := 0
	for e in w.events:
		if e.type == "cmd_rejected":
			n += 1
	assert_eq(n, 2)

func test_owner_zero_rejected():
	var w := _line_world(10)
	_send(w, 2, 1, 50, 0)  # node 2 is neutral (owner 0)
	w.step()
	assert_eq(w.groups.size(), 0)
	assert_true(_has_event(w, "cmd_rejected"))
