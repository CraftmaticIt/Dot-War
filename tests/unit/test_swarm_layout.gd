extends GutTest

func test_dot_offset_deterministic_and_bounded():
	for gid in 20:
		for i in 50:
			var a := SwarmRenderer.dot_offset(gid, i)
			assert_eq(a, SwarmRenderer.dot_offset(gid, i))
			assert_true(a.length() <= SwarmRenderer.SPREAD_PX + 0.001, "offset within spread")

func test_dot_offsets_spread():
	var seen := {}
	for i in 50:
		seen[SwarmRenderer.dot_offset(3, i)] = true
	assert_gt(seen.size(), 40, "dots do not collapse onto one point")

func test_to_px():
	assert_eq(SwarmRenderer.to_px(Vector2i(1000, 2000)), Vector2(SwarmRenderer.PX_PER_UNIT, 2 * SwarmRenderer.PX_PER_UNIT))

func test_owner_colors():
	assert_eq(SwarmRenderer.OWNER_COLORS[0], Color("#808080"))
	assert_eq(SwarmRenderer.OWNER_COLORS[1], Color("#00E5FF"))
	assert_eq(SwarmRenderer.OWNER_COLORS[2], Color("#FF2E88"))
	assert_eq(SwarmRenderer.OWNER_COLORS[3], Color("#B6FF00"))
	assert_eq(SwarmRenderer.OWNER_COLORS[4], Color("#FFB300"))
