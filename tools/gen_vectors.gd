extends SceneTree
## Regenerates tests/vectors/*.json. Run:
##   .tools/godot --headless --path . -s tools/gen_vectors.gd

func _cmd(t: int, owner: int, from: int, to: int, pct: int) -> Dictionary:
	return {"tick": t, "type": "send", "owner": owner, "from": from, "to": to, "percent": pct}

func _write(name: String, g: SimGraph, seed: int, cmds: Array, ticks: int) -> void:
	var v := {"graph": g.to_dict(), "seed": seed, "commands": cmds, "ticks": ticks, "expected_hash": 0}
	var w := SimReplay.run(JSON.parse_string(JSON.stringify(v)))
	v.expected_hash = w.state_hash()
	v["expected_canonical"] = w.canonical()
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
	# v005: hidden trap, wall (big garrison), laser lvl 3, pulse lvl 2; ends mid-flight.
	g = SimGraph.new()
	g.add_node(1, 0, 0, 1, 90, 3)
	g.add_node(2, 0, 6000, 1, 40, 2)
	g.add_node(3, 6000, 1000, 2, 0, 0, "", 10)          # trap
	g.add_node(4, 9000, 4000, 2, 50, 0)                 # wall
	g.add_node(5, 12000, 0, 2, 12, 1, "laser", 0, 3)
	g.add_node(6, 12000, 7000, 2, 12, 1, "pulse", 0, 2)
	g.add_node(7, 16000, 3500, 2, 60, 2)                # core
	g.link(1, 3); g.link(2, 3); g.link(2, 4); g.link(3, 4); g.link(3, 5); g.link(4, 6)
	g.link(5, 7); g.link(6, 7); g.link(4, 7)
	_write("v005_traps_levels", g, 5, [_cmd(0, 1, 1, 3, 30), _cmd(3, 1, 2, 3, 50), _cmd(40, 1, 3, 4, 100),
		_cmd(70, 1, 1, 5, 60), _cmd(90, 1, 2, 6, 80), _cmd(150, 1, 4, 7, 100)], 230)
	# v006: ends with a trap still armed (canonical ",t" suffix) and a pulse whose level
	# changes the outcome (lvl 4 vs 1). Pins both for the TS port.
	g = SimGraph.new()
	g.add_node(1, 0, 0, 1, 80, 2)
	g.add_node(2, 6000, 0, 2, 30, 0, "pulse", 0, 4)
	g.add_node(3, 6000, 6000, 2, 6, 0, "", 20)          # trap, never reached
	g.add_node(4, 12000, 0, 2, 40, 1)
	g.link(1, 2); g.link(2, 4); g.link(2, 3)
	_write("v006_armed_trap_pulse_lvl", g, 6, [_cmd(0, 1, 1, 2, 50), _cmd(20, 1, 1, 2, 50), _cmd(45, 1, 1, 2, 100)], 120)
	# v007: boosters — rage + shield on a lane past a laser, emp on a pulse, split on capture.
	g = SimGraph.new()
	g.add_node(1, 0, 0, 1, 90, 2)
	g.add_node(2, 9000, 0, 2, 20, 1)
	g.add_node(3, 4500, 1500, 2, 5, 0, "laser", 0, 2)
	g.add_node(4, 9000, 6000, 2, 15, 0, "pulse", 0, 3)
	g.link(1, 2); g.link(2, 4); g.link(1, 3)
	var cmds := [_cmd(0, 1, 1, 2, 40), {"tick": 0, "type": "boost", "owner": 1, "booster": "rage", "node": 2},
		{"tick": 1, "type": "boost", "owner": 1, "booster": "shield", "node": 2},
		_cmd(30, 1, 1, 2, 50), {"tick": 40, "type": "boost", "owner": 1, "booster": "split", "node": 2},
		{"tick": 90, "type": "boost", "owner": 1, "booster": "emp", "node": 4}, _cmd(100, 1, 2, 4, 100),
		{"tick": 101, "type": "boost", "owner": 2, "booster": "nuke", "node": 4}]
	_write("v007_boosts", g, 7, cmds, 150)
	# v008: enemy kinds (fast + rage, armored, splash near a player node) under laser and pulse.
	g = SimGraph.new()
	g.add_node(1, 0, 0, 1, 70, 1)                       # core
	g.add_node(2, 4000, 0, 1, 6, 0, "laser", 0, 2)
	g.add_node(3, 4000, 2500, 1, 9, 0, "pulse", 0, 1)
	g.add_node(9, 14000, 0, 2, 0, 0)                    # spawn
	g.add_node(8, 14000, 5000, 2, 0, 0)                 # spawn
	g.link(1, 2); g.link(1, 3); g.link(2, 9); g.link(3, 8)
	cmds = [_spawn(0, 9, 1, 3, 1), _spawn(5, 9, 1, 5, 2), _spawn(10, 8, 1, 1, 3), _spawn(12, 8, 1, 3, 0),
		{"tick": 0, "type": "boost", "owner": 2, "booster": "rage", "node": 1}, _spawn(40, 9, 1, 2, 3), _spawn(60, 9, 1, 30, 1)]
	_write("v008_kinds", g, 8, cmds, 300)
	# v009: spawn validation — every rejection plus one valid spawn after a malformed one.
	g = SimGraph.new()
	g.add_node(1, 0, 0, 1, 20, 0)
	g.add_node(2, 6000, 0, 0, 0, 0)
	g.add_node(9, 12000, 0, 2, 4, 0)
	g.add_node(7, 30000, 0, 2, 0, 0)                    # spawn with no path
	g.link(1, 2); g.link(2, 9)
	cmds = [_spawn(0, 9, 1, 0, 0), _spawn(0, 9, 1, 5, 4), _spawn(0, 2, 1, 5, 0), _spawn(0, 77, 1, 5, 0),
		_spawn(0, 7, 1, 5, 0), {"tick": 1, "type": "spawn", "owner": 2, "node": 9, "to": 1, "count": "5", "kind": 0},
		{"tick": 2, "type": "spawn", "owner": 0, "node": 9, "to": 1, "count": 5, "kind": 0},
		_spawn(3, 9, 9, 5, 0), _spawn(3, 9, 1, 25, 1)]
	_write("v009_spawn", g, 9, cmds, 120)
	quit()

func _spawn(t: int, node: int, to: int, count: int, kind: int) -> Dictionary:
	return {"tick": t, "type": "spawn", "owner": 2, "node": node, "to": to, "count": count, "kind": kind}
