extends GutTest
## Enemy dot kinds (fast/armored/splash) and the PvE-only spawn command.

func _line(tower := "", g2 := 0) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 50, 0, tower)
	g.add_node(2, 6000, 0, 1 if g2 > 0 else 0, g2, 0)
	g.add_node(9, 12000, 0, 2, 0, 0)
	g.link(1, 2)
	g.link(2, 9)
	return SimWorld.new(g, 1)

func _spawn(w: SimWorld, count: int, kind: int, t := 0, node := 9, owner := 2) -> void:
	w.queue({"tick": t, "type": "spawn", "owner": owner, "node": node, "to": 1, "count": count, "kind": kind})

func _rejections(w: SimWorld) -> Array:
	var out := []
	for e in w.events:
		if e.type == "cmd_rejected":
			out.append(e.reason)
	return out

func test_spawn_creates_group_without_touching_garrison():
	var w := _line()
	_spawn(w, 12, 0)
	w.step()
	assert_eq(w.groups.size(), 1)
	assert_eq(w.groups[0].owner, 2)
	assert_eq(w.groups[0].count, 12)
	assert_eq(w.groups[0].kind, 0)
	assert_eq(w.graph.node(9).garrison, 0)

func test_spawn_rejections():
	for c in [[0, 0, 9, 2, "empty"], [5, 4, 9, 2, "bad_kind"], [5, 0, 9, 1, "not_owner"], [5, 0, 77, 2, "bad_node"]]:
		var w := _line()
		_spawn(w, c[0], c[1], 0, c[2], c[3])
		w.step()
		assert_eq(_rejections(w), [c[4]], str(c))
		assert_eq(w.groups.size(), 0)

func test_spawn_with_bad_field_types_is_bad_cmd():
	var w := _line()
	w.queue({"tick": 0, "type": "spawn", "owner": 2, "node": 9, "to": 1, "count": "12", "kind": 0})
	w.step()
	assert_eq(_rejections(w), ["bad_cmd"])

func test_fast_moves_three_halves():
	var w := _line()
	_spawn(w, 5, 1)
	for i in 10:
		w.step()
	assert_eq(w.groups[0].progress, 10 * 225)

func _loss_after(kind: int, ticks: int) -> int:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 50, 0, "laser")
	g.add_node(9, 6000, 0, 2, 0, 0)
	g.link(1, 9)
	var w := SimWorld.new(g, 1)
	_spawn(w, 40, kind)
	for i in ticks:
		w.step()
	return 40 - w.groups[0].count

func test_armored_takes_half_tower_damage():
	# In laser range (4000) from tick 14; 34 ticks = 21 ticks of fire: 4 vs 2 dots.
	var normal := _loss_after(0, 34)
	var armored := _loss_after(2, 34)
	assert_gt(normal, 0)
	assert_eq(armored, normal / 2)

func test_splash_on_tower_death_hits_nearby_enemy_nodes():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 50, 0, "laser")
	g.add_node(2, 2500, 1000, 1, 8, 0)
	g.add_node(9, 6000, 0, 2, 0, 0)
	g.link(1, 9)
	g.link(1, 2)
	var w := SimWorld.new(g, 1)
	_spawn(w, 1, 3)
	var splashed := false
	for i in 60:
		w.step()
		for e in w.events:
			if e.type == "splash":
				splashed = true
				assert_eq(e.nodes, [2])
		if splashed:
			break
	assert_true(splashed)
	assert_eq(w.graph.node(2).garrison, 3)
	assert_eq(w.graph.node(1).garrison, 50, "node 1 farther than SPLASH_RANGE")

func test_splash_not_on_trap_death():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 50, 0, "", 10)
	g.add_node(2, 1000, 1000, 1, 8, 0)
	g.add_node(9, 3000, 0, 2, 0, 0)
	g.link(1, 9)
	var w := SimWorld.new(g, 1)
	_spawn(w, 5, 3)
	for i in 40:
		w.step()
		for e in w.events:
			assert_ne(e.type, "splash")
	assert_eq(w.graph.node(2).garrison, 8)

func test_canonical_kind_segment_only_when_nonzero():
	var w := _line()
	_spawn(w, 5, 0)
	_spawn(w, 5, 2)
	w.step()
	var segs := Array(w.canonical().split("|")).filter(func(s): return s.begins_with("g"))
	assert_eq(segs.size(), 2)
	assert_false(segs[0].contains(",k"))
	assert_true(segs[1].ends_with(",k2"))
