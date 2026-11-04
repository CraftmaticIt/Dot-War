extends GutTest

func _l1() -> Dictionary:
	return PveDefs.level(1)

func test_level_lookup():
	assert_eq(int(_l1().id), 1)
	assert_true(PveDefs.level(999).is_empty())

func test_validate_accepts_allowed_placement():
	assert_eq(PveLevel.validate(_l1(), [{"slot": 2, "type": "laser"}], false), "")
	assert_eq(PveLevel.validate(_l1(), [], false), "")

func test_validate_rejects_bad_placements():
	var bad := [
		[{"slot": 2, "type": "laser"}, {"slot": 2, "type": "laser"}],   # duplicate slot
		[{"slot": 1, "type": "laser"}],                                # core
		[{"slot": 9, "type": "laser"}],                                # spawn
		[{"slot": 55, "type": "laser"}],                               # unknown
		[{"slot": 2, "type": "wall"}],                                 # not allowed
		[{"slot": 2, "type": "core"}],                                 # not a defense type
		[{"slot": "2", "type": "laser"}], [{"slot": 2}], ["x"], [{"slot": 2.5, "type": "laser"}],
	]
	for p in bad:
		assert_eq(PveLevel.validate(_l1(), p, false), "bad_placement", str(p))
	assert_eq(PveLevel.validate(_l1(), "nope", false), "bad_placement")

func test_validate_counts_limit():
	var l := _l1().duplicate(true)
	l.nodes.append({"id": 3, "x": 3000, "y": 0, "role": "slot"})
	assert_eq(PveLevel.validate(l, [{"slot": 2, "type": "laser"}, {"slot": 3, "type": "laser"}], false), "bad_placement")

func test_validate_arena_budget():
	var a: Dictionary = PveDefs.data().arena
	var lvl := {"nodes": a.map.nodes, "links": a.map.links, "allowed": {}, "level": 1, "waves": []}
	var ok := [{"slot": 2, "type": "laser"}, {"slot": 3, "type": "laser"}, {"slot": 4, "type": "pulse"}, {"slot": 5, "type": "laser"}]
	assert_eq(PveLevel.validate(lvl, ok, true), "", "3+3+3+3 = 12")
	ok.append({"slot": 6, "type": "trap"})
	assert_eq(PveLevel.validate(lvl, ok, true), "bad_placement", "13 > budget 12")

func test_build_world_and_player_nodes():
	var p := [{"slot": 2, "type": "laser"}]
	var w := PveLevel.build_world(_l1(), p, 1)
	var g := w.graph
	assert_eq(g.node(1).owner, 1)
	assert_eq(g.node(1).garrison, Buildings.garrison("core", 1))
	assert_eq(g.node(2).owner, 1)
	assert_eq(g.node(2).tower, "laser")
	assert_eq(g.node(9).owner, 2)
	assert_eq(g.node(9).garrison, 0)
	assert_eq(PveLevel.player_nodes(_l1(), p), [1, 2])
	var empty := PveLevel.build_world(_l1(), [], 1)
	assert_eq(empty.graph.node(2).owner, 0)
	assert_eq(PveLevel.player_nodes(_l1(), []), [1])
