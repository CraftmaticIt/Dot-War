extends GutTest

func _row(f: Callable, type: String) -> Array:
	var out := []
	for lvl in range(1, 6):
		out.append(f.call(type, lvl))
	return out

func test_costs_table():
	assert_eq(_row(Buildings.cost, "core"), [0, 1000, 4000, 12000, 30000])
	assert_eq(_row(Buildings.cost, "mine"), [100, 300, 800, 2000, 5000])
	assert_eq(_row(Buildings.cost, "storage"), [150, 400, 1000, 2500, 6000])
	assert_eq(_row(Buildings.cost, "generator"), [200, 500, 1200, 3000, 7000])
	assert_eq(_row(Buildings.cost, "laser"), [250, 600, 1500, 3500, 8000])
	assert_eq(_row(Buildings.cost, "pulse"), [250, 600, 1500, 3500, 8000])
	assert_eq(_row(Buildings.cost, "wall"), [50, 150, 400, 1000, 2500])
	assert_eq(_row(Buildings.cost, "trap"), [100, 250, 600, 1500, 3500])

func test_build_secs_table():
	assert_eq(_row(Buildings.build_secs, "core"), [0, 300, 3600, 14400, 43200])
	assert_eq(_row(Buildings.build_secs, "mine"), [10, 60, 300, 1800, 7200])
	assert_eq(_row(Buildings.build_secs, "storage"), [10, 90, 600, 2400, 7200])
	assert_eq(_row(Buildings.build_secs, "generator"), [20, 120, 600, 2400, 9000])
	assert_eq(_row(Buildings.build_secs, "laser"), [30, 180, 900, 3600, 10800])
	assert_eq(_row(Buildings.build_secs, "pulse"), [30, 180, 900, 3600, 10800])
	assert_eq(_row(Buildings.build_secs, "wall"), [5, 30, 180, 900, 3600])
	assert_eq(_row(Buildings.build_secs, "trap"), [10, 60, 300, 1200, 3600])

func test_mine_rates():
	assert_eq(_row(Buildings.energy_per_hour, "mine"), [100, 200, 350, 550, 800])
	assert_eq(Buildings.energy_per_hour("storage", 3), 0)

func test_generator_rates_and_caps():
	assert_eq(_row(Buildings.dots_per_hour, "generator"), [60, 120, 200, 300, 450])
	assert_eq(_row(Buildings.dots_cap, "generator"), [50, 80, 120, 170, 230])
	assert_eq(Buildings.dots_cap("mine", 1), 0)

func test_energy_caps_core_storage():
	assert_eq(_row(Buildings.energy_cap, "core"), [1000, 2000, 4000, 8000, 15000])
	assert_eq(_row(Buildings.energy_cap, "storage"), [1500, 3000, 5000, 8000, 12000])
	assert_eq(Buildings.energy_cap("mine", 1), 0)

func test_level_zero_has_no_effect():
	assert_eq(Buildings.energy_per_hour("mine", 0), 0)
	assert_eq(Buildings.energy_cap("storage", 0), 0)

func test_max_nodes():
	assert_eq(_row(func(_t, l): return Buildings.max_nodes(l), ""), [6, 9, 12, 16, 20])

func test_tower_mapping():
	assert_eq(Buildings.tower("laser"), "laser")
	assert_eq(Buildings.tower("pulse"), "pulse")
	assert_eq(Buildings.tower("mine"), "")

func test_unknown_type_returns_zero():
	assert_eq(Buildings.cost("castle", 1), 0)
	assert_eq(Buildings.build_secs("castle", 1), 0)
	assert_false(Buildings.is_type("castle"))
	assert_true(Buildings.is_type("trap"))
