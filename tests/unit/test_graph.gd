extends GutTest

func _diamond(len_top: int, len_bottom: int) -> SimGraph:
	# 1 at origin, 4 at (10,0). 2 above, 3 below; offsets set path lengths.
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 0, 0)
	g.add_node(2, 5000, len_top, 0, 0, 0)
	g.add_node(3, 5000, -len_bottom, 0, 0, 0)
	g.add_node(4, 10000, 0, 2, 0, 0)
	g.link(1, 2); g.link(2, 4); g.link(1, 3); g.link(3, 4)
	return g

func test_path_prefers_shorter():
	var g := _diamond(1000, 5000)
	assert_eq(g.path(1, 4), PackedInt32Array([1, 2, 4]))

func test_path_prefers_shorter_other_side():
	var g := _diamond(5000, 1000)
	assert_eq(g.path(1, 4), PackedInt32Array([1, 3, 4]))

func test_path_tie_lower_id():
	var g := _diamond(3000, 3000)
	assert_eq(g.path(1, 4), PackedInt32Array([1, 2, 4]))

func test_path_none_when_disconnected():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 0, 0)
	g.add_node(2, 1000, 0, 0, 0, 0)
	assert_eq(g.path(1, 2), PackedInt32Array())

func test_path_to_self():
	var g := _diamond(1000, 1000)
	assert_eq(g.path(1, 1), PackedInt32Array([1]))

func test_neighbors_sorted():
	var g := _diamond(1000, 1000)
	assert_eq(g.neighbors(1), PackedInt32Array([2, 3]))

func test_node_ids_sorted():
	var g := SimGraph.new()
	g.add_node(5, 0, 0, 0, 0, 0)
	g.add_node(2, 0, 0, 0, 0, 0)
	assert_eq(g.node_ids(), PackedInt32Array([2, 5]))

func test_node_fields():
	var g := SimGraph.new()
	g.add_node(7, 100, 200, 1, 10, 2, "laser")
	var n := g.node(7)
	assert_eq(n.owner, 1)
	assert_eq(n.garrison, 10)
	assert_eq(n.prod_per_sec, 2)
	assert_eq(n.tower, "laser")
	assert_eq(n.prod_acc, 0)

func test_roundtrip_dict():
	var g := _diamond(1000, 2000)
	g.node(2).tower = "pulse"
	assert_eq(SimGraph.from_dict(g.to_dict()).to_dict(), g.to_dict())

func test_roundtrip_through_json():
	var g := _diamond(1000, 2000)
	var parsed = JSON.parse_string(JSON.stringify(g.to_dict()))
	assert_eq(SimGraph.from_dict(parsed).to_dict(), g.to_dict())
