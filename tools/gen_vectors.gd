extends SceneTree
## Regenerates tests/vectors/*.json. Run:
##   .tools/godot --headless --path . -s tools/gen_vectors.gd

func _cmd(t: int, owner: int, from: int, to: int, pct: int) -> Dictionary:
	return {"tick": t, "type": "send", "owner": owner, "from": from, "to": to, "percent": pct}

func _write(name: String, g: SimGraph, seed: int, cmds: Array, ticks: int) -> void:
	var v := {"graph": g.to_dict(), "seed": seed, "commands": cmds, "ticks": ticks, "expected_hash": 0}
	v.expected_hash = SimReplay.run(JSON.parse_string(JSON.stringify(v))).state_hash()
	var f := FileAccess.open("res://tests/vectors/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(v, "  ", false) + "\n")
	print("%s: %d" % [name, v.expected_hash])

func _init() -> void:
	# v001: production + reinforcement along a line.
	var g := SimGraph.new()
	g.add_node(1, 0, 0, 1, 10, 2)
	g.add_node(2, 4000, 0, 1, 0, 1)
	g.add_node(3, 8000, 1000, 0, 3, 0)
	g.link(1, 2); g.link(2, 3)
	_write("v001_basic", g, 1, [_cmd(0, 1, 1, 2, 50), _cmd(30, 1, 2, 3, 100)], 200)

	# v002: two players fight over neutral centre, recapture, same-tick arrivals.
	g = SimGraph.new()
	g.add_node(1, -6000, 0, 1, 30, 3)
	g.add_node(2, 6000, 0, 2, 30, 3)
	g.add_node(3, 0, 0, 0, 10, 2)
	g.add_node(4, 0, 5000, 0, 5, 1)
	g.link(1, 3); g.link(2, 3); g.link(3, 4); g.link(1, 4); g.link(2, 4)
	_write("v002_capture", g, 7, [
		_cmd(0, 1, 1, 3, 50), _cmd(0, 2, 2, 3, 50), _cmd(60, 1, 1, 4, 75),
		_cmd(61, 2, 2, 3, 100), _cmd(120, 1, 1, 2, 100), _cmd(121, 2, 3, 1, 90),
		_cmd(150, 1, 9, 1, 50), _cmd(151, 2, 2, 3, 0)], 400)

	# v003: towers (laser + pulse) shredding an attack.
	g = SimGraph.new()
	g.add_node(1, 0, 0, 1, 60, 4)
	g.add_node(2, 6000, 0, 2, 5, 1, "laser")
	g.add_node(3, 6000, 3000, 2, 5, 1, "pulse")
	g.add_node(4, 12000, 1500, 2, 15, 2)
	g.add_node(5, 3000, 1500, 0, 2, 0, "pulse")
	g.link(1, 2); g.link(1, 3); g.link(2, 4); g.link(3, 4); g.link(1, 5); g.link(5, 3)
	_write("v003_towers", g, 42, [
		_cmd(0, 1, 1, 2, 5), _cmd(5, 1, 1, 4, 50), _cmd(10, 1, 1, 3, 50), _cmd(80, 1, 1, 4, 100),
		_cmd(90, 2, 4, 1, 60)], 500)
	# v004: attackers move in -x / -y; laser at (13402, 9001) sits where truncating vs floor
	# division disagree on "in range" (tick 110). Ends mid-flight so dmg_acc is in the hash.
	# Pins the TS contract: Math.trunc, not Math.floor.
	g = SimGraph.new()
	g.add_node(1, 30000, 21000, 1, 80, 3)
	g.add_node(2, 29000, 2000, 1, 60, 3)
	g.add_node(3, 1000, 1000, 2, 40, 1)
	g.add_node(4, 1000, 19000, 2, 40, 1)
	g.add_node(5, 13402, 9001, 2, 10, 1, "laser")
	g.add_node(6, 17003, 11999, 2, 10, 1, "pulse")
	g.link(1, 3); g.link(2, 4); g.link(1, 2)
	_write("v004_negative_dirs", g, 99, [_cmd(0, 1, 1, 3, 50), _cmd(40, 1, 1, 3, 30), _cmd(112, 1, 2, 4, 25)], 150)
	quit()
