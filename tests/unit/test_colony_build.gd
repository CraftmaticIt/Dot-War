extends GutTest

const T0 := 1_800_000_000

func _c() -> ColonyState:
	return ColonyState.new_default(T0)

func _snapshot(c: ColonyState) -> Dictionary:
	return {"cells": c.cells.duplicate(true), "energy": c.energy, "crystals": c.crystals}

func test_default_state():
	var c := _c()
	assert_eq(c.energy, 500)
	assert_eq(c.crystals, 50)
	assert_eq(c.dots, 0)
	assert_eq(c.cells["0,0"].type, "core")
	assert_eq(c.cells["0,0"].level, 1)
	assert_eq(c.cells["1,0"].type, "mine")
	assert_eq(c.cells["1,0"].level, 1)
	assert_eq(c.core_level(), 1)
	assert_eq(c.last_collect, T0)

func test_place_ok_charges_energy_and_starts_timer():
	var c := _c()
	assert_eq(c.place("generator", 0, 1, T0), "")
	var cell: Dictionary = c.cells["0,1"]
	assert_eq(cell.level, 0)
	assert_eq(cell.target_level, 1)
	assert_eq(cell.build_end, T0 + 20)
	assert_eq(c.energy, 300)
	assert_eq(c.busy_builders(T0), 1)

func _expect_place_error(c: ColonyState, type: String, q: int, r: int, code: String) -> void:
	var before := _snapshot(c)
	assert_eq(c.place(type, q, r, T0), code, code)
	assert_eq(_snapshot(c), before, "state unchanged on " + code)

func test_place_errors():
	var c := _c()
	_expect_place_error(c, "castle", 0, 1, "bad_type")
	_expect_place_error(c, "core", 0, 1, "core_unique")
	_expect_place_error(c, "mine", 1, 0, "occupied")
	_expect_place_error(c, "mine", 3, 0, "not_adjacent")
	_expect_place_error(c, "mine", 5, 0, "out_of_grid")
	c.energy = 10
	_expect_place_error(c, "mine", 0, 1, "no_energy")

func test_node_limit():
	var c := _c()
	c.energy = 100000
	for k in ["0,1", "-1,0", "0,-1", "-1,1"]:
		c.cells[k] = {"type": "wall", "level": 1, "build_end": 0, "target_level": 1}
	assert_eq(c.cells.size(), 6)
	_expect_place_error(c, "wall", 1, -1, "node_limit")

func test_third_build_needs_free_builder():
	var c := _c()
	c.energy = 100000
	assert_eq(c.place("wall", 0, 1, T0), "")
	assert_eq(c.place("wall", -1, 0, T0), "")
	_expect_place_error(c, "wall", 0, -1, "no_builder")

func test_adjacent_to_unfinished_is_allowed():
	var c := _c()
	c.energy = 100000
	assert_eq(c.place("wall", 0, 1, T0), "")
	assert_eq(c.can_place("wall", 0, 2, T0), "", "adjacent to an unfinished building is fine")

func test_upgrade_ok():
	var c := _c()
	c.energy = 2000
	assert_eq(c.upgrade(0, 0, T0), "")
	var cell: Dictionary = c.cells["0,0"]
	assert_eq(cell.level, 1, "keeps working on old level")
	assert_eq(cell.target_level, 2)
	assert_eq(cell.build_end, T0 + 300)
	assert_eq(c.energy, 1000)

func _expect_upgrade_error(c: ColonyState, q: int, r: int, code: String) -> void:
	var before := _snapshot(c)
	assert_eq(c.upgrade(q, r, T0), code, code)
	assert_eq(_snapshot(c), before, "state unchanged on " + code)

func test_upgrade_errors():
	var c := _c()
	c.cells["0,0"].level = 2
	_expect_upgrade_error(c, 5, 5, "empty")
	c.energy = 100
	_expect_upgrade_error(c, 1, 0, "no_energy")
	c.energy = 100000
	assert_eq(c.upgrade(1, 0, T0), "")
	_expect_upgrade_error(c, 1, 0, "busy")
	assert_eq(c.place("wall", 0, 1, T0), "")
	_expect_upgrade_error(c, 0, 0, "no_builder")

func test_max_level():
	var c := _c()
	c.cells["0,0"].level = 5
	c.cells["1,0"].level = 5
	c.energy = 100000
	_expect_upgrade_error(c, 1, 0, "max_level")
	_expect_upgrade_error(c, 0, 0, "max_level")

func test_non_core_capped_by_core_level():
	var c := _c()
	c.energy = 100000
	# Core level 1: other buildings may not exceed level 1.
	_expect_upgrade_error(c, 1, 0, "core_limit")
	assert_eq(c.upgrade(0, 0, T0), "", "core itself can be upgraded")

func test_finish_builds_levels_up():
	var c := _c()
	c.place("generator", 0, 1, T0)
	c.finish_builds(T0 + 19)
	assert_eq(c.cells["0,1"].level, 0)
	c.finish_builds(T0 + 20)
	assert_eq(c.cells["0,1"].level, 1)
	assert_eq(c.cells["0,1"].build_end, 0)
	assert_eq(c.busy_builders(T0 + 20), 0)

func test_speedup_cost_rounding():
	var c := _c()
	c.energy = 100000
	c.place("laser", 0, 1, T0)  # 30 s
	assert_eq(c.speedup_cost(0, 1, T0), 1)
	assert_eq(c.speedup_cost(0, 1, T0 + 29), 1)
	c.upgrade(0, 0, T0)  # core 1->2: 300 s
	assert_eq(c.speedup_cost(0, 0, T0), 5)
	assert_eq(c.speedup_cost(0, 0, T0 + 240), 1)
	assert_eq(c.speedup_cost(0, 0, T0 + 239), 2)
	assert_eq(c.speedup_cost(1, 0, T0), 0, "not building")

func test_speedup_finishes_now():
	var c := _c()
	c.place("generator", 0, 1, T0)
	assert_eq(c.speedup(0, 1, T0 + 5), "")
	assert_eq(c.cells["0,1"].level, 1)
	assert_eq(c.crystals, 49)

func test_speedup_errors():
	var c := _c()
	assert_eq(c.speedup(1, 0, T0), "not_building")
	c.place("generator", 0, 1, T0)
	c.crystals = 0
	assert_eq(c.speedup(0, 1, T0), "no_crystals")
	assert_eq(c.cells["0,1"].level, 0)

func test_speedup_increments_spent_counter():
	var c := _c()
	c.place("generator", 0, 1, T0)
	c.speedup(0, 1, T0)
	assert_eq(c.crystals_spent, 1)
	var back := ColonyState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.crystals_spent, 1)
