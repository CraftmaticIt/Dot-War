extends GutTest

func _defender() -> SimGraph:
	var g := SimGraph.new()
	g.add_node(1, 10000, 0, 2, 30, 1)
	g.add_node(2, 10000, 10000, 2, 6, 0)
	g.add_node(3, 14000, 5000, 2, 6, 0, "laser")
	g.add_node(4, 10000, 20000, 2, 6, 0)
	g.link(1, 2); g.link(2, 3); g.link(2, 4)
	return g

func test_three_entries_left_of_colony():
	var w := AttackSetup.build(_defender(), 30, 1)
	var ys := []
	for id in AttackSetup.ENTRY_IDS:
		var n := w.graph.node(id)
		assert_eq(n.owner, AttackSetup.ATTACKER)
		assert_eq(n.x, 10000 - AttackSetup.ENTRY_GAP)
		assert_eq(n.prod_per_sec, 0)
		ys.append(n.y)
	assert_eq(ys, [0, 10000, 20000])

func test_dots_split_with_remainder():
	var w := AttackSetup.build(_defender(), 10, 1)
	var got := []
	for id in AttackSetup.ENTRY_IDS:
		got.append(w.graph.node(id).garrison)
	assert_eq(got, [4, 3, 3])

func test_entry_links_two_nearest():
	var w := AttackSetup.build(_defender(), 30, 1)
	assert_eq(w.graph.neighbors(1001), PackedInt32Array([1, 3]))
	assert_eq(w.graph.neighbors(1002), PackedInt32Array([2, 3]))
	assert_eq(w.graph.neighbors(1003), PackedInt32Array([2, 4]))

func test_middle_entry_tie_takes_lower_ids():
	# Entry 1002 at y=10000: node 2 is nearest; nodes 1 and 4 tie -> lower id (1).
	var g := SimGraph.new()
	g.add_node(1, 10000, 0, 2, 30, 1)
	g.add_node(2, 10000, 10000, 2, 6, 0)
	g.add_node(4, 10000, 20000, 2, 6, 0)
	g.link(1, 2); g.link(2, 4)
	var w := AttackSetup.build(g, 30, 1)
	assert_eq(w.graph.neighbors(1002), PackedInt32Array([1, 2]))

func test_single_node_colony():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 2, 30, 1)
	var w := AttackSetup.build(g, 9, 1)
	var ys := []
	for id in AttackSetup.ENTRY_IDS:
		assert_eq(w.graph.neighbors(id), PackedInt32Array([1]))
		ys.append(w.graph.node(id).y)
	assert_eq(ys, [-4000, 0, 4000])

func test_defender_nodes_untouched():
	var d := _defender()
	var before := d.to_dict()
	var w := AttackSetup.build(d, 30, 1)
	assert_eq(d.to_dict(), before, "input graph not mutated")
	assert_eq(w.graph.node(3).tower, "laser")
	assert_eq(w.graph.node(1).garrison, 30)
