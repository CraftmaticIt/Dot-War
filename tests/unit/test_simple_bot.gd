extends GutTest

func _world() -> SimWorld:
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 2, 30, 0)
	g.add_node(2, 1000, 0, 2, 10, 0)
	g.add_node(3, 2000, 0, 0, 8, 0)
	g.add_node(4, -1000, 0, 1, 4, 0)
	g.add_node(5, 3000, 0, 1, 1, 0)
	g.link(1, 2); g.link(2, 3); g.link(1, 4); g.link(3, 5)
	return SimWorld.new(g, 1)

func test_bot_attacks_weakest_neighbour_from_strongest_node():
	var cmd := SimpleBot.decide(_world(), 2)
	assert_eq(cmd, {"tick": 0, "type": "send", "owner": 2, "from": 1, "to": 4, "percent": 50})

func test_bot_idle_when_no_targets():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 2, 30, 0)
	assert_eq(SimpleBot.decide(SimWorld.new(g, 1), 2), {})

func test_bot_idle_when_too_weak():
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 2, 1, 0)
	g.add_node(2, 1000, 0, 0, 0, 0)
	g.link(1, 2)
	assert_eq(SimpleBot.decide(SimWorld.new(g, 1), 2), {})
