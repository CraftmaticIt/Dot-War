extends GutTest
## Every campaign level is a real puzzle: the reference solution gets 3 stars, an empty map does not.

func _solutions() -> Dictionary:
	var j := JSON.new()
	assert_eq(j.parse(FileAccess.get_file_as_string("res://tests/pve_solutions.json")), OK)
	return j.data

func test_fifteen_levels_in_three_chapters():
	var ls := PveDefs.levels()
	assert_eq(ls.size(), 15)
	var names := {}
	for i in ls.size():
		assert_eq(int(ls[i].id), i + 1)
		assert_eq(int(ls[i].chapter), i / 5 + 1)
		names[String(ls[i].name)] = true
	assert_eq(names.size(), 15, "unique names")

func test_solution_three_stars_empty_less():
	var sol := _solutions()
	for l in PveDefs.levels():
		var p: Array = sol[str(int(l.id))]
		assert_eq(PveLevel.validate(l, p, false), "", "valid solution %d" % int(l.id))
		assert_eq(int(PveMatch.run(l, p, 1).result.stars), 3, "solution 3 stars on %d" % int(l.id))
		assert_lt(int(PveMatch.run(l, [], 1).result.stars), 3, "empty map fails on %d" % int(l.id))

func test_waves_reach_the_core():
	for l in PveDefs.levels():
		var w := PveLevel.build_world(l, [], 1)
		var core := PveLevel.core_id(l)
		assert_gt(l.waves.size(), 0)
		for wv in l.waves:
			assert_false(w.graph.path(int(wv.node), core).is_empty(), "path from %d on level %d" % [int(wv.node), int(l.id)])

func test_chapter_rules():
	var ch2_types := {}
	var ch2_kinds := {}
	var ch3_kinds := {}
	for l in PveDefs.levels():
		var ch := int(l.chapter)
		for wv in l.waves:
			var k := int(wv.kind)
			if ch == 1:
				assert_eq(k, 0, "chapter 1 only normal dots (level %d)" % int(l.id))
			elif ch == 2:
				assert_lte(k, 1, "chapter 2 normal + fast (level %d)" % int(l.id))
				ch2_kinds[k] = true
			else:
				ch3_kinds[k] = true
		for t in l.allowed:
			if ch == 1:
				assert_true(t in ["laser", "pulse"], "chapter 1 towers only (level %d)" % int(l.id))
			elif ch == 2:
				ch2_types[t] = true
	assert_true(ch2_types.has("wall") and ch2_types.has("trap"))
	assert_true(ch2_kinds.has(1))
	assert_true(ch3_kinds.has(2) and ch3_kinds.has(3))
