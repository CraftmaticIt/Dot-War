extends SceneTree
## Regenerates tests/battle_vectors/*.json — the cross-language contract for the server
## verifier (bot generation, snapshot, attack setup, match rules). Run:
##   .tools/godot --headless --path . -s tools/gen_battle_vectors.gd

const T0 := 1_800_000_000

## Runs one battle. Commands are recorded from SimpleBot (attacker) unless `fixed` is given.
func _battle(defender: ColonyState, loot_pool: int, dots: int, seed: int, fixed = null, extra := [], stop_tick := -1, loadout := []) -> Dictionary:
	var ids := defender.snapshot_ids()
	var core := 1
	for id in ids:
		if ids[id] == Vector2i.ZERO:
			core = id
	var m := BattleMatch.new(AttackSetup.build(defender.to_sim_graph(AttackSetup.DEFENDER), dots, seed), core, loot_pool, loadout)
	var cmds: Array = [] if fixed == null else fixed.duplicate(true)
	for c in extra:
		cmds.append(c)
	while not m.over:
		if stop_tick >= 0 and m.world.tick >= stop_tick:
			m.surrender()
			break
		if fixed == null and m.world.tick % 40 == 0:
			var d := SimpleBot.decide(m.world, AttackSetup.ATTACKER)
			if not d.is_empty():
				cmds.append({"tick": m.world.tick, "from": d.from, "to": d.to, "percent": d.percent})
		for c in cmds:
			if typeof(c.get("tick")) in [TYPE_INT, TYPE_FLOAT] and int(c.tick) == m.world.tick:
				m.send_raw(c)
		m.step()
	return {"commands": cmds, "result": m.result(), "hash": m.world.state_hash(), "ticks": m.world.tick,
		"surrender_tick": stop_tick}

func _write(name: String, v: Dictionary) -> void:
	var f := FileAccess.open("res://tests/battle_vectors/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(v, "  ", false) + "\n")
	print("%s: stars=%d hash=%d ticks=%d" % [name, v.expected.result.stars, v.expected.hash, v.expected.ticks])

func _bot_vector(name: String, trophies: int, seed: int, dots: int, stop_tick := -1) -> void:
	var bot := BotColony.generate(trophies, seed)
	var r := _battle(bot.colony, bot.loot_pool, dots, seed, null, [], stop_tick)
	_write(name, {"bot": {"trophies": trophies, "seed": seed}, "bot_colony": bot.colony.to_dict(),
		"defender": null, "loot_pool": bot.loot_pool, "dots": dots, "seed": seed,
		"surrender_tick": stop_tick, "commands": r.commands,
		"expected": {"result": r.result, "hash": r.hash, "ticks": r.ticks}})

func _init() -> void:
	_bot_vector("b001_bot_0", 0, 11, 300)
	_bot_vector("b002_bot_600", 600, 23, 120)
	_bot_vector("b003_surrender", 300, 31, 80, 300)
	# b004: player colony with trap, wall, towers.
	var c := ColonyState.new_default(T0)
	c.cells["0,0"].level = 3
	c.cells["0,1"] = {"type": "trap", "level": 2, "build_end": 0, "target_level": 2}
	c.cells["-1,0"] = {"type": "wall", "level": 2, "build_end": 0, "target_level": 2}
	c.cells["-1,1"] = {"type": "laser", "level": 3, "build_end": 0, "target_level": 3}
	c.cells["1,-1"] = {"type": "pulse", "level": 2, "build_end": 0, "target_level": 2}
	c.cells["0,-1"] = {"type": "generator", "level": 2, "build_end": 0, "target_level": 2}
	var r := _battle(c, 900, 90, 5)
	_write("b004_player_colony", {"bot": null, "defender": c.to_dict(), "loot_pool": 900, "dots": 90, "seed": 5,
		"surrender_tick": -1, "commands": r.commands, "expected": {"result": r.result, "hash": r.hash, "ticks": r.ticks}})
	# b005: malformed / hostile commands mixed in (must be ignored identically).
	var bot := BotColony.generate(100, 77)
	var bad := [{"tick": 0, "from": "1001", "to": 1, "percent": 50}, {"tick": 1, "from": 1001, "to": 1},
		{"tick": "x", "from": 1001, "to": 1, "percent": 50}, {"tick": 2, "from": 1, "to": 1001, "percent": 100},
		{"tick": 3, "from": 1002, "to": 999, "percent": 100}, {"tick": 4, "from": 1003, "to": 1, "percent": 0}]
	r = _battle(bot.colony, bot.loot_pool, 250, 77, null, bad)
	_write("b005_malformed_cmds", {"bot": {"trophies": 100, "seed": 77}, "bot_colony": bot.colony.to_dict(),
		"defender": null, "loot_pool": bot.loot_pool, "dots": 250, "seed": 77, "surrender_tick": -1,
		"commands": r.commands, "expected": {"result": r.result, "hash": r.hash, "ticks": r.ticks}})
	# b006: boosters from a loadout (4th and out-of-loadout ones ignored).
	var bb := BotColony.generate(300, 61)
	var bbc: ColonyState = bb.colony
	var ids: Dictionary = bbc.snapshot_ids()
	var tgt := 1
	for id in ids:
		if ids[id] == Vector2i.ZERO:
			tgt = id
	var boosts := [{"tick": 40, "type": "boost", "booster": "rage", "node": tgt},
		{"tick": 41, "type": "boost", "booster": "shield", "node": tgt},
		{"tick": 42, "type": "boost", "booster": "emp", "node": tgt},
		{"tick": 43, "type": "boost", "booster": "split", "node": tgt},
		{"tick": 44, "type": "boost", "booster": "rage", "node": tgt}]
	r = _battle(bb.colony, bb.loot_pool, 160, 61, null, boosts, -1, ["rage", "shield", "emp"])
	_write("b006_boosts", {"bot": {"trophies": 300, "seed": 61}, "bot_colony": bb.colony.to_dict(), "defender": null,
		"loot_pool": bb.loot_pool, "dots": 160, "seed": 61, "surrender_tick": -1, "loadout": ["rage", "shield", "emp"],
		"commands": r.commands, "expected": {"result": r.result, "hash": r.hash, "ticks": r.ticks}})
	quit()
