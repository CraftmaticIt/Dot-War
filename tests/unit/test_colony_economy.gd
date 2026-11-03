extends GutTest

const T0 := 1_800_000_000
const H := 3600

func _c() -> ColonyState:
	return ColonyState.new_default(T0)

func test_one_hour_mine_lvl1():
	var c := _c()
	var got := c.collect(T0 + H)
	assert_eq(c.energy, 600)
	assert_eq(got, {"energy": 100, "dots": 0, "secs": H})
	assert_eq(c.last_collect, T0 + H)

func test_partial_seconds_carry_remainder():
	var c := _c()
	for i in range(1, H + 1):
		c.collect(T0 + i)
	assert_eq(c.energy, 600, "3600 one-second collects add the full hour")

func test_offline_cap_8h():
	var c := _c()
	c.cells["0,1"] = {"type": "storage", "level": 1, "build_end": 0, "target_level": 1}
	var got := c.collect(T0 + 24 * H)
	assert_eq(got.secs, 8 * H)
	assert_eq(c.energy, 1300)

func test_clock_backwards_no_gain():
	var c := _c()
	assert_eq(c.collect(T0 - 100), {"energy": 0, "dots": 0, "secs": 0})
	assert_eq(c.last_collect, T0)
	assert_eq(c.energy, 500)

func test_build_finishing_mid_window():
	var c := _c()
	c.cells["0,0"].level = 2
	c.energy = 1000
	assert_eq(c.upgrade(1, 0, T0), "")
	c.cells["1,0"].build_end = T0 + 1800
	c.collect(T0 + H)
	assert_eq(c.energy, 700 + 50 + 100)
	assert_eq(c.cells["1,0"].level, 2)

func test_build_finished_in_discarded_offline_part():
	var c := _c()
	c.cells["0,0"].level = 2
	c.energy = 300
	c.upgrade(1, 0, T0)          # energy 0, mine -> lvl2 at T0+60
	c.collect(T0 + 20 * H)       # window = last 8 h, all at lvl2
	assert_eq(c.energy, 1600)

func test_storage_cap_clamps():
	var c := _c()
	c.collect(T0 + 8 * H)
	assert_eq(c.energy, 1000)
	assert_eq(c.energy_rem, 0)
	assert_eq(c.energy_cap(), 1000)

func test_generator_dots_and_cap():
	var c := _c()
	c.cells["0,1"] = {"type": "generator", "level": 1, "build_end": 0, "target_level": 1}
	assert_eq(c.dots_cap(), 50)
	c.collect(T0 + H / 2)
	assert_eq(c.dots, 30)
	c.collect(T0 + 9 * H)
	assert_eq(c.dots, 50)

func test_unbuilt_generator_produces_nothing():
	var c := _c()
	c.place("generator", 0, 1, T0)
	c.collect(T0 + 10)
	assert_eq(c.dots, 0)

func test_place_collects_first():
	var c := _c()
	assert_eq(c.place("generator", 0, 1, T0 + H), "")
	assert_eq(c.energy, 400)

func test_stock_above_cap_is_kept():
	var c := _c()
	c.energy = 5000
	c.collect(T0 + H)
	assert_eq(c.energy, 5000)
