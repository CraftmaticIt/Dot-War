extends GutTest
## Panel must not be rebuilt by the 1 s tick (rebuilding frees buttons mid-tap on phones),
## and countdown labels must still update every second.

const CV := preload("res://game/colony_view.gd")

func _view() -> Node2D:
	var v: Node2D = CV.new()
	var now := int(Time.get_unix_time_from_system())
	v.colony = ColonyState.new_default(now)
	v.colony.place("generator", 0, 1, now)
	v.save_enabled = false
	add_child_autofree(v)
	v.select(Vector2i(0, 1))
	return v

func test_tick_keeps_panel_buttons():
	var v := _view()
	var before: Array = v.panel_nodes()
	v.on_second()
	assert_eq(v.panel_nodes(), before, "same node instances after the tick")

func test_tick_updates_countdown_label():
	var v := _view()
	v.colony.cells["0,1"].build_end += 0  # unchanged
	var lbl: Label = v.timer_label()
	assert_not_null(lbl)
	v.colony.cells["0,1"].build_end -= 5
	v.on_second()
	assert_string_contains(lbl.text, "%ds" % (v.colony.cells["0,1"].build_end - int(Time.get_unix_time_from_system())))

func test_finished_build_rebuilds_panel():
	var v := _view()
	var before: Array = v.panel_nodes()
	v.colony.cells["0,1"].build_end = int(Time.get_unix_time_from_system()) - 1
	v.on_second()
	assert_ne(v.panel_nodes(), before, "structure changed -> rebuilt")
