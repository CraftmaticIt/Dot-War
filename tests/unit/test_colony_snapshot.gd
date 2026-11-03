extends GutTest

const T0 := 1_800_000_000

func _c() -> ColonyState:
	var c := ColonyState.new_default(T0)
	c.cells["0,1"] = {"type": "laser", "level": 1, "build_end": 0, "target_level": 1}  # neighbour of (0,0) and (1,0)? (0,1)-(1,0): dq=1, dr=-1 -> yes
	return c

func test_dict_roundtrip_through_json():
	var c := _c()
	c.energy_rem = 1234
	c.dots = 7
	var parsed = JSON.parse_string(JSON.stringify(c.to_dict()))
	assert_eq(ColonyState.from_dict(parsed).to_dict(), c.to_dict())

func test_snapshot_nodes_and_links():
	var g := _c().to_sim_graph(2)
	assert_eq(g.node_ids().size(), 3)
	assert_eq(g.to_dict().links.size(), 3)
	var towers := []
	for id in g.node_ids():
		assert_eq(g.node(id).owner, 2)
		if g.node(id).tower != "":
			towers.append(g.node(id).tower)
	assert_eq(towers, ["laser"])

func test_snapshot_positions_from_hex():
	var g := _c().to_sim_graph(1)
	var found := false
	for id in g.node_ids():
		var n := g.node(id)
		if n.x == 3464 and n.y == 0:
			found = true
	assert_true(found, "mine at hex (1,0)")

func test_snapshot_skips_unbuilt():
	var c := _c()
	c.cells["-1,0"] = {"type": "wall", "level": 0, "build_end": T0 + 5, "target_level": 1}
	assert_eq(c.to_sim_graph(1).node_ids().size(), 3)

func test_snapshot_ids_stable():
	var c := _c()
	assert_eq(c.to_sim_graph(1).to_dict(), c.to_sim_graph(1).to_dict())

func test_from_dict_skips_unknown_building():
	var d := _c().to_dict()
	d.cells["5,5"] = {"type": "castle", "level": 1, "build_end": 0, "target_level": 1}
	assert_false(ColonyState.from_dict(d).cells.has("5,5"))
