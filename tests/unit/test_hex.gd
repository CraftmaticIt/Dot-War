extends GutTest

func test_key_roundtrip():
	assert_eq(Hex.key(-3, 2), "-3,2")
	assert_eq(Hex.parse(Hex.key(-3, 2)), Vector2i(-3, 2))

func test_neighbors_order():
	assert_eq(Hex.neighbors(0, 0), [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)])

func test_neighbors_offset():
	assert_eq(Hex.neighbors(2, -1)[0], Vector2i(3, -1))

func test_to_fx_origin():
	assert_eq(Hex.to_fx(0, 0), Vector2i(0, 0))

func test_to_fx_q1():
	assert_eq(Hex.to_fx(1, 0), Vector2i(3464, 0))

func test_to_fx_r1():
	assert_eq(Hex.to_fx(0, 1), Vector2i(1732, 3000))

func test_distance():
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -1)), 2)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(-2, -1)), 3)
	assert_eq(Hex.distance(Vector2i(1, 1), Vector2i(1, 1)), 0)
