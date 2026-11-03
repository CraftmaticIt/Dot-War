extends GutTest

func test_rng_repeatable():
	var a := SimRng.new(42)
	var b := SimRng.new(42)
	for i in 100:
		assert_eq(a.next_u32(), b.next_u32())

func test_rng_range_bounds():
	var r := SimRng.new(7)
	for i in 1000:
		var v := r.range_i(5)
		assert_true(v >= 0 and v < 5)

func test_rng_seed_zero_not_stuck():
	var r := SimRng.new(0)
	assert_ne(r.next_u32(), 0)

func test_rng_u32_range():
	var r := SimRng.new(123)
	for i in 1000:
		var v := r.next_u32()
		assert_true(v >= 0 and v <= 0xFFFFFFFF)
