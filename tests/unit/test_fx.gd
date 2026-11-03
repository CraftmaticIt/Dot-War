extends GutTest

func test_mul():
	assert_eq(Fx.mul(1500, 2000), 3000)

func test_mul_neg():
	assert_eq(Fx.mul(-1500, 1000), -1500)

func test_mul_truncates_toward_zero():
	assert_eq(Fx.mul(-1, 1), 0)

func test_div():
	assert_eq(Fx.div(3000, 2000), 1500)

func test_from_int():
	assert_eq(Fx.from_int(3), 3000)

func test_dist_345():
	assert_eq(Fx.dist(0, 0, 3000, 4000), 5000)

func test_dist_zero():
	assert_eq(Fx.dist(5, 5, 5, 5), 0)
