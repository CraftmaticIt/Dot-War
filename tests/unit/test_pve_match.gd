extends GutTest

func _run(level: Dictionary, placement: Array) -> Dictionary:
	var m := PveMatch.new(level, placement, 1)
	var i := 0
	while not m.over and i < 30000:
		m.step()
		i += 1
	assert_true(m.over, "match ends")
	return m.result()

func test_level1_laser_three_stars():
	var r := _run(PveDefs.level(1), [{"slot": 2, "type": "laser"}])
	assert_eq(r.stars, 3)
	assert_eq(r.lost, 0)

func test_level1_empty_loses_core():
	var r := _run(PveDefs.level(1), [])
	assert_eq(r.stars, 0)

func test_stars_formula():
	assert_eq(PveMatch.stars_for(false, 0), 3)
	assert_eq(PveMatch.stars_for(false, 1), 2)
	assert_eq(PveMatch.stars_for(false, 2), 1)
	assert_eq(PveMatch.stars_for(true, 0), 0)

func _arena_like(counts: Array) -> Dictionary:
	var l: Dictionary = PveDefs.level(1).duplicate(true)
	l["arena"] = true
	l.waves = []
	for i in counts.size():
		l.waves.append({"tick": 40 + i * 300, "node": 9, "count": counts[i], "kind": 0})
	return l

func test_arena_never_falling_scores_all_waves():
	var r := _run(_arena_like([1, 1, 1, 1]), [{"slot": 2, "type": "laser"}])
	assert_eq(r.score, 4)

func test_arena_score_is_waves_started_before_fall_minus_one():
	var r := _run(_arena_like([5, 5, 200, 5]), [{"slot": 2, "type": "laser"}])
	assert_eq(r.waves_started, 3)
	assert_eq(r.score, 2)

func test_arena_level_deterministic_per_week():
	var a := PveMatch.arena_level(5)
	assert_eq(a, PveMatch.arena_level(5))
	assert_ne(a.waves, PveMatch.arena_level(6).waves)
	assert_eq(a.waves.size(), int(PveDefs.data().arena.max_waves))
	assert_eq(int(a.waves[0].tick), 40)
	assert_eq(int(a.waves[1].tick), 340)
	assert_eq(int(a.waves[2].count), 14)
	assert_true(a.arena)

func test_week_index():
	var e := int(PveDefs.data().weekly.epoch)
	assert_eq(PveMatch.week_index(e), 0)
	assert_eq(PveMatch.week_index(e + 604799), 0)
	assert_eq(PveMatch.week_index(e + 604800), 1)

func test_campaign_safety_limit():
	var l: Dictionary = PveDefs.level(1).duplicate(true)
	l.waves = [{"tick": 11990, "node": 9, "count": 3, "kind": 0}]
	var m := PveMatch.new(l, [], 1)
	while not m.over:
		m.step()
	assert_lte(m.world.tick, PveMatch.CAMPAIGN_TICKS)
