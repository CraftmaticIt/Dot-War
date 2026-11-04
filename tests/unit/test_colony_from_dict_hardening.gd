extends GutTest
## from_dict must never be fooled by hostile/corrupt input (mirrored in server/test/colony.test.ts).

const T0 := 1_800_000_000

func _base() -> Dictionary:
	return ColonyState.new_default(T0).to_dict()

func test_bad_keys_skipped_and_cannot_replace_core():
	var d := _base()
	d.cells["abc"] = {"type": "core", "level": 5, "build_end": 0, "target_level": 5}
	d.cells["01,0"] = {"type": "wall", "level": 1, "build_end": 0, "target_level": 1}
	var c := ColonyState.from_dict(d)
	assert_eq(c.cells["0,0"].level, 1)
	assert_eq(c.cells.size(), 2)

func test_non_numeric_fields_skip_cell_or_zero():
	var d := _base()
	d.cells["0,1"] = {"type": "mine", "level": [1], "build_end": 0, "target_level": 1}
	d.cells["-1,0"] = {"type": 5, "level": 1, "build_end": 0, "target_level": 1}
	d.energy = "lots"
	var c := ColonyState.from_dict(d)
	assert_false(c.cells.has("0,1"))
	assert_false(c.cells.has("-1,0"))
	assert_eq(c.energy, 0)

func test_negative_and_out_of_range_values_clamped():
	var d := _base()
	d.energy_rem = -100000
	d.dots_rem = 99999
	d.energy = -5
	d.cells["1,0"].target_level = 0   # below level
	var c := ColonyState.from_dict(d)
	assert_eq(c.energy_rem, 0)
	assert_eq(c.dots_rem, 3599)
	assert_eq(c.energy, 0)
	assert_eq(c.cells["1,0"].target_level, 1)

func test_two_cores_or_core_off_center_rejected():
	var d := _base()
	d.cells["0,1"] = {"type": "core", "level": 1, "build_end": 0, "target_level": 1}
	assert_null(ColonyState.from_dict(d))
	var e := _base()
	e.cells.erase("0,0")
	e.cells["1,1"] = {"type": "core", "level": 1, "build_end": 0, "target_level": 1}
	assert_null(ColonyState.from_dict(e))

func test_cells_outside_grid_dropped():
	var d := _base()
	d.cells["5,0"] = {"type": "wall", "level": 1, "build_end": 0, "target_level": 1}
	assert_false(ColonyState.from_dict(d).cells.has("5,0"))

func test_can_place_outside_grid():
	var c := ColonyState.new_default(T0)
	c.energy = 100000
	for q in range(2, 5):
		c.cells[Hex.key(q, 0)] = {"type": "wall", "level": 1, "build_end": 0, "target_level": 1}
	assert_eq(c.can_place("wall", 5, 0, T0), "out_of_grid")

func test_snapshot_includes_unbuilt_cells_as_empty_nodes():
	var c := ColonyState.new_default(T0)
	c.cells["0,1"] = {"type": "laser", "level": 0, "build_end": T0 + 30, "target_level": 1}
	c.cells["0,2"] = {"type": "wall", "level": 1, "build_end": 0, "target_level": 1}
	var g := c.to_sim_graph(2)
	assert_eq(g.node_ids().size(), 4)
	var ids := c.snapshot_ids()
	for id in ids:
		if ids[id] == Vector2i(0, 1):
			assert_eq(g.node(id).garrison, 0)
			assert_eq(g.node(id).tower, "", "unfinished tower does not fire")
		if ids[id] == Vector2i(0, 2):
			assert_gt(g.neighbors(id).size(), 0, "wall behind the unfinished cell stays reachable")

func test_bot_colonies_stay_in_grid():
	for seed in 30:
		var c: ColonyState = BotColony.generate(900, seed).colony
		for k in c.cells:
			assert_lte(Hex.distance(Hex.parse(k), Vector2i.ZERO), ColonyState.GRID_RADIUS)
