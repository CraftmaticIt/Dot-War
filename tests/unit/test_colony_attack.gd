extends GutTest

const T0 := 1_800_000_000

func _c(dots: int) -> ColonyState:
	var c := ColonyState.new_default(T0)
	c.dots = dots
	return c

func test_can_attack_few_dots():
	var c := _c(9)
	assert_eq(c.can_attack(T0), "few_dots")
	var before := c.to_dict()
	assert_eq(c.begin_attack(T0), {"error": "few_dots"})
	assert_eq(c.to_dict(), before)

func test_begin_attack_consumes_dots():
	var c := _c(25)
	c.trophies = 40
	var a := c.begin_attack(T0)
	assert_eq(a.dots, 25)
	assert_eq(a.seed, 1 * 7919 + 40)
	assert_eq(c.dots, 0)
	assert_eq(c.attacks, 1)
	assert_eq(c.can_attack(T0), "few_dots")

func test_apply_result_loot_above_cap():
	var c := _c(0)
	c.energy = 900
	c.apply_result({"loot": 700, "trophies": 20, "stars": 2, "destroyed_pct": 60})
	assert_eq(c.energy, 1600, "loot may exceed storage cap")
	assert_eq(c.trophies, 20)

func test_trophies_floor_zero():
	var c := _c(0)
	c.trophies = 5
	c.apply_result({"loot": 0, "trophies": -8, "stars": 0, "destroyed_pct": 0})
	assert_eq(c.trophies, 0)

func test_old_save_without_trophies_loads():
	var d := ColonyState.new_default(T0).to_dict()
	d.erase("trophies")
	d.erase("attacks")
	var c := ColonyState.from_dict(d)
	assert_not_null(c)
	assert_eq(c.trophies, 0)
	assert_eq(c.attacks, 0)

func test_trophies_roundtrip():
	var c := _c(0)
	c.trophies = 123
	c.attacks = 4
	var back := ColonyState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.trophies, 123)
	assert_eq(back.attacks, 4)

func test_begin_attack_marks_open():
	var c := _c(20)
	c.begin_attack(T0)
	assert_eq(c.attack_open, 1)

func test_apply_result_clears_open():
	var c := _c(20)
	c.begin_attack(T0)
	c.apply_result({"loot": 0, "trophies": 10, "stars": 1, "destroyed_pct": 50})
	assert_eq(c.attack_open, 0)

func test_abandoned_attack_counts_as_loss():
	var c := _c(20)
	c.trophies = 30
	c.begin_attack(T0)
	var back := ColonyState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_true(back.resolve_abandoned_attack())
	assert_eq(back.trophies, 22)
	assert_eq(back.attack_open, 0)
	assert_false(back.resolve_abandoned_attack(), "only once")
