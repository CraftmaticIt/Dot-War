extends GutTest

func _send(w: SimWorld, from: int, to: int, pct: int, owner := 1) -> void:
	w.queue({"tick": w.tick, "type": "send", "owner": owner, "from": from, "to": to, "percent": pct})

func _boost(w: SimWorld, b: String, node: int, owner := 1) -> void:
	w.queue({"tick": w.tick, "type": "boost", "owner": owner, "booster": b, "node": node})

func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()

## 1 --- 2 (target) and 1 --- 3 (other target), all owner 1 except where noted.
func _fork(t2_owner := 1) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 40, 0)
	g.add_node(2, 30000, 0, t2_owner, 0, 0)
	g.add_node(3, 0, 30000, 1, 0, 0)
	g.link(1, 2); g.link(1, 3)
	return SimWorld.new(g, 1)

func test_rage_speeds_only_matching_groups():
	var w := _fork()
	_send(w, 1, 2, 25)   # g0 -> 2
	_send(w, 1, 3, 25)   # g1 -> 3
	_boost(w, "rage", 2)
	w.step()
	assert_eq(w.groups[0].progress, 225)
	assert_eq(w.groups[1].progress, 150)

func test_effects_expire():
	var w := _fork()
	_boost(w, "rage", 2)
	w.step()
	assert_eq(w.effects.size(), 1)
	_steps(w, SimWorld.BOOST_TICKS.rage - 1)
	assert_eq(w.effects.size(), 0)
	_send(w, 1, 2, 25)
	w.step()
	assert_eq(w.groups[0].progress, 150)

func _tower_lane(tower_owner := 2) -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 40, 0)
	g.add_node(2, 30000, 0, 1, 0, 0)
	g.add_node(9, 0, 1000, tower_owner, 0, 0, "laser")
	g.link(1, 2)
	return SimWorld.new(g, 1)

func test_shield_reduces_damage():
	var w := _tower_lane()
	_send(w, 1, 2, 50)
	_boost(w, "shield", 2)
	w.step()
	assert_eq(w.groups[0].dmg_acc, 80, "200 * 2/5")

func test_emp_silences_towers_in_radius():
	var w := _tower_lane()
	_send(w, 1, 2, 50)
	_boost(w, "emp", 1)   # node 1 is 1000 from the tower
	w.step()
	assert_eq(w.groups[0].dmg_acc, 0)
	var far := _tower_lane()
	_send(far, 1, 2, 50)
	_boost(far, "emp", 2)  # 30000 away: no effect
	far.step()
	assert_eq(far.groups[0].dmg_acc, 200)

func test_split_doubles_first_arrival_only():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 40, 0)
	g.add_node(2, 3000, 0, 2, 5, 0)
	g.link(1, 2)
	var w := SimWorld.new(g, 1)
	_boost(w, "split", 2)
	_send(w, 1, 2, 25)  # 10 dots -> 20 on arrival
	_steps(w, 20)
	assert_eq(w.graph.node(2).owner, 1)
	assert_eq(w.graph.node(2).garrison, 15)
	assert_eq(w.effects.size(), 0, "consumed")

func test_boost_bad_node_or_type_rejected():
	var w := _fork()
	_boost(w, "rage", 99)
	w.queue({"tick": 0, "type": "boost", "owner": 1, "booster": "nuke", "node": 2})
	w.queue({"tick": 0, "type": "boost", "owner": 0, "booster": "rage", "node": 2})
	w.step()
	assert_eq(w.effects.size(), 0)
	assert_eq(w.events.filter(func(e): return e.type == "cmd_rejected").size(), 3)

func test_canonical_with_and_without_effects():
	var w := _fork()
	assert_false(w.canonical().contains("|e"))
	_boost(w, "emp", 3)
	w.step()
	assert_string_contains(w.canonical(), "|eemp,1,3,80")
