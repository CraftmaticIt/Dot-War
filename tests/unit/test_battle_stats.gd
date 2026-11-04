extends GutTest

const T0 := 1_800_000_000

func test_garrison_table():
	assert_eq(Buildings.garrison("core", 2), 60)
	assert_eq(Buildings.garrison("wall", 3), 75)
	assert_eq(Buildings.garrison("trap", 4), 0)
	assert_eq(Buildings.garrison("mine", 2), 12)
	assert_eq(Buildings.garrison("laser", 1), 6)
	assert_eq(Buildings.garrison("mine", 0), 0)

func test_battle_prod_table():
	assert_eq(Buildings.battle_prod("core", 3), 3)
	assert_eq(Buildings.battle_prod("generator", 2), 2)
	assert_eq(Buildings.battle_prod("mine", 5), 0)

func test_trap_dmg_table():
	assert_eq(Buildings.trap_dmg("trap", 1), 10)
	assert_eq(Buildings.trap_dmg("trap", 4), 40)
	assert_eq(Buildings.trap_dmg("wall", 4), 0)

func _colony() -> ColonyState:
	var c := ColonyState.new_default(T0)
	c.cells["0,0"].level = 2
	c.cells["0,1"] = {"type": "laser", "level": 3, "build_end": 0, "target_level": 3}
	c.cells["-1,0"] = {"type": "trap", "level": 1, "build_end": 0, "target_level": 1}
	return c

func _by_hex(c: ColonyState, g: SimGraph) -> Dictionary:
	var ids := c.snapshot_ids()
	var out := {}
	for id in ids:
		out[ids[id]] = g.node(id)
	return out

func test_snapshot_fills_battle_stats():
	var c := _colony()
	var n := _by_hex(c, c.to_sim_graph(2))
	assert_eq(n[Vector2i(0, 0)].garrison, 60)
	assert_eq(n[Vector2i(0, 0)].prod_per_sec, 2)
	assert_eq(n[Vector2i(0, 1)].tower, "laser")
	assert_eq(n[Vector2i(0, 1)].tower_lvl, 3)
	assert_eq(n[Vector2i(-1, 0)].trap, 10)
	assert_eq(n[Vector2i(-1, 0)].garrison, 0)
	assert_eq(n[Vector2i(1, 0)].garrison, 6)

func test_snapshot_ids_match_graph():
	var c := _colony()
	var g := c.to_sim_graph(2)
	var ids := c.snapshot_ids()
	assert_eq(PackedInt32Array(ids.keys()), g.node_ids())
	for id in ids:
		var pos := Hex.to_fx(ids[id].x, ids[id].y)
		assert_eq(Vector2i(g.node(id).x, g.node(id).y), pos)
