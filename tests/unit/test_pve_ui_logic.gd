extends GutTest

const PV := preload("res://game/pve_view.gd")
const CV := preload("res://game/campaign_view.gd")

func test_unlock_chain():
	assert_true(CV.unlocked({}, 1))
	assert_false(CV.unlocked({}, 2))
	assert_true(CV.unlocked({"1": 1}, 2))
	assert_false(CV.unlocked({"1": 1}, 3))
	assert_true(CV.unlocked({"2": 3.0}, 3), "JSON floats")

func test_merge_stars_keeps_best():
	assert_eq(CV.merge_stars({"1": 1, "2": 3}, {"1": 3.0}), {"1": 3, "2": 3})

func test_remaining_campaign_and_arena():
	var l := PveDefs.level(1)
	assert_eq(PV.remaining(l, [], false), {"laser": 1})
	assert_eq(PV.remaining(l, [{"slot": 2, "type": "laser"}], false), {"laser": 0})
	var arena := PveMatch.arena_level(1)
	assert_eq(PV.remaining(arena, [{"slot": 2, "type": "laser"}], true), {"budget": 9})

func test_toggle_add_remove_replace():
	var p := PV.toggle([], 2, "laser")
	assert_eq(p, [{"slot": 2, "type": "laser"}])
	assert_eq(PV.toggle(p, 2, "laser"), [], "same type again removes")
	assert_eq(PV.toggle(p, 2, "pulse"), [{"slot": 2, "type": "pulse"}], "other type replaces")
	assert_eq(PV.toggle(p, 3, "wall"), [{"slot": 2, "type": "laser"}, {"slot": 3, "type": "wall"}])

func test_end_text():
	var won := PV.end_text({"stars": 3, "score": 0}, false, {"gained": 3, "crystals": 15})
	assert_true("★★★" in won)
	assert_true("+15 kryształów" in won)
	var off := PV.end_text({"stars": 1, "score": 0}, false, {"offline": true})
	assert_true("Nagroda wymaga połączenia" in off)
	var lost := PV.end_text({"stars": 0, "score": 0}, false, {})
	assert_true("Porażka" in lost)
	var ar := PV.end_text({"stars": 0, "score": 7}, true, {"score": 7, "best": 9})
	assert_true("Przetrwane fale: 7" in ar)
	assert_true("Rekord tygodnia: 9" in ar)
