extends SceneTree
## Regenerates tests/pve_vectors/*.json (PvE level/arena + placement -> result, hash). Run:
##   .tools/godot --headless --path . -s tools/gen_pve_vectors.gd

func _write(name: String, v: Dictionary) -> void:
	var lvl: Dictionary = PveMatch.arena_level(int(v.week)) if v.has("week") else PveDefs.level(int(v.level))
	var r := PveMatch.run(lvl, v.placement, int(v.seed), v.get("commands", []))
	v["expected"] = r
	var f := FileAccess.open("res://tests/pve_vectors/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(v, "  ", false) + "\n")
	print("%s: %s hash=%d" % [name, JSON.stringify(r.result), r.hash])

func _init() -> void:
	_write("p001_level1", {"level": 1, "placement": [{"slot": 2, "type": "laser"}], "seed": 1})
	_write("p002_level1_empty", {"level": 1, "placement": [], "seed": 1})
	_write("p003_arena_week5", {"week": 5, "seed": 5, "placement": [{"slot": 2, "type": "laser"},
		{"slot": 5, "type": "pulse"}, {"slot": 8, "type": "wall"}, {"slot": 9, "type": "trap"}, {"slot": 3, "type": "wall"}]})
	# p004: empty slots on the path are captured and their garrison forwarded to the core.
	_write("p004_level7_forwarding", {"level": 7, "placement": [], "seed": 1})
	# p005: player sends (reinforce a slot, pull back, a send into the spawn that must be ignored).
	_write("p005_level1_commands", {"level": 1, "placement": [], "seed": 1, "commands": [
		{"tick": 5, "from": 1, "to": 2, "percent": 50}, {"tick": 150, "from": 2, "to": 1, "percent": 100},
		{"tick": 160, "from": 1, "to": 9, "percent": 100}, {"tick": 200, "from": 1, "to": 2, "percent": 25}]})
	quit()
