extends GutTest

const BV := preload("res://game/battle_view.gd")

func _corners(b: Rect2i) -> Array:
	return [SwarmRenderer.to_px(b.position), SwarmRenderer.to_px(b.end)]

func test_fit_transform_maps_bounds_into_screen():
	var b := Rect2i(-20000, -5000, 40000, 30000)
	var screen := Vector2(1280, 720)
	var t := BV.fit_transform(b, screen, 60.0)
	for c in _corners(b):
		var p: Vector2 = t * c
		assert_between(p.x, 60.0 - 0.01, screen.x - 60.0 + 0.01)
		assert_between(p.y, 60.0 - 0.01, screen.y - 60.0 + 0.01)

func test_fit_transform_keeps_aspect():
	var t := BV.fit_transform(Rect2i(0, 0, 40000, 10000), Vector2(1280, 720), 60.0)
	assert_almost_eq(t.x.x, t.y.y, 0.0001)
	assert_eq(t.x.y, 0.0)

func test_fit_transform_centers():
	var b := Rect2i(0, 0, 10000, 10000)
	var t := BV.fit_transform(b, Vector2(1280, 720), 60.0)
	var mid: Vector2 = t * SwarmRenderer.to_px(Vector2i(5000, 5000))
	assert_almost_eq(mid.x, 640.0, 0.5)
	assert_almost_eq(mid.y, 360.0, 0.5)

func test_fit_transform_caps_zoom():
	var t := BV.fit_transform(Rect2i(0, 0, 100, 100), Vector2(1280, 720), 60.0)
	assert_lte(t.x.x, BV.MAX_ZOOM)

func test_format_clock():
	assert_eq(BV.format_clock(3600), "3:00")
	assert_eq(BV.format_clock(1210), "1:00")
	assert_eq(BV.format_clock(19), "0:00")
	assert_eq(BV.format_clock(25), "0:01")

func test_stars_text():
	assert_eq(BV.stars_text(2), "★★☆")

func test_flow_pending_to_end_screen():
	var c := ColonyState.new_default(1_800_000_000)
	c.dots = 30
	var a := c.begin_attack(1_800_000_000)
	BV.pending = {"colony": c, "dots": a.dots, "seed": a.seed}
	var v: Node2D = BV.new()
	add_child_autofree(v)
	assert_not_null(v.battle)
	assert_true(BV.pending.is_empty(), "handoff consumed")
	var total := 0
	for id in AttackSetup.ENTRY_IDS:
		total += v.battle.world.graph.node(id).garrison
	assert_eq(total, 30)
	v.battle.surrender()
	v._process(0.016)
	assert_true(v._end.visible)

func test_traps_hidden_from_attacker_view():
	var v: Node2D = BV.new()
	assert_false(v._visible_node({"id": 1, "trap": 20, "owner": 2}).has("trap"))
	v.free()
