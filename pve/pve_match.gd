class_name PveMatch
## PvE defense: waves of enemy dots (spawn commands) march on the core. The player placed
## buildings and may send dots from their own nodes (never into or through a spawn).
## Enemy-held nodes forward their garrison to the core every tick (the AI swarm).
## Placement + player commands are the whole replay; the server re-runs this to verify a result.

const CAMPAIGN_TICKS := 12000
const ARENA_TAIL_TICKS := 2400   # arena: time after the last wave for the field to clear
const WEEK_SECS := 604800
const MAX_COMMANDS := 2000

## Player sends recorded as {tick, from, to, percent} (the replay input).
var commands: Array = []
var _cmds: Array = []   # pending, applied at their tick before the waves
var world: SimWorld
var over := false
var _level: Dictionary
var _core: int
var _start: Array[int]
var _spawns := {}
var _waves: Array = []
var _limit: int
var _waves_started := 0
var _started_at_fall := -1

func _init(level: Dictionary, placement: Array, seed: int) -> void:
	_level = level
	world = PveLevel.build_world(level, placement, seed)
	_core = PveLevel.core_id(level)
	_start = PveLevel.player_nodes(level, placement)
	for n in level.nodes:
		if String(n.role) == "spawn":
			_spawns[int(n.id)] = true
	_waves = level.get("waves", [])
	var last := 0
	for w in _waves:
		last = maxi(last, int(w.tick))
	_limit = last + ARENA_TAIL_TICKS if level.get("arena", false) else CAMPAIGN_TICKS

## Player send at the current tick (live play); recorded for the server replay.
func send(from: int, to: int, percent: int) -> void:
	if over:
		return
	var c := {"tick": world.tick, "from": from, "to": to, "percent": percent}
	commands.append(c)
	_cmds.append(c)

## Untrusted replay input: only well-formed {tick, from, to, percent} entries are kept.
func load_commands(cmds) -> void:
	if typeof(cmds) != TYPE_ARRAY:
		return
	for c in cmds.slice(0, MAX_COMMANDS):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var ok := true
		for k in ["tick", "from", "to", "percent"]:
			if typeof(c.get(k)) != TYPE_INT and typeof(c.get(k)) != TYPE_FLOAT:
				ok = false
		if ok:
			_cmds.append({"tick": int(c.tick), "from": int(c.from), "to": int(c.to), "percent": int(c.percent)})

func _touches_spawn(from: int, to: int) -> bool:
	if _spawns.has(from) or _spawns.has(to):
		return true
	if not world.graph.has_node(from) or not world.graph.has_node(to):
		return false
	for id in world.graph.path(from, to):
		if _spawns.has(id):
			return true
	return false

func step() -> void:
	if over:
		return
	var t := world.tick
	var later := []
	for c in _cmds:
		if int(c.tick) == t:
			if not _touches_spawn(int(c.from), int(c.to)):
				world.queue({"tick": t, "type": "send", "owner": PveLevel.PLAYER, "from": int(c.from), "to": int(c.to),
					"percent": int(c.percent)})
		elif int(c.tick) > t:
			later.append(c)
	_cmds = later
	for w in _waves:
		if int(w.tick) == t:
			world.queue({"tick": t, "type": "spawn", "owner": PveLevel.ENEMY, "node": int(w.node), "to": _core,
				"count": int(w.count), "kind": int(w.kind)})
			_waves_started += 1
	for id in world.graph.node_ids():
		var n := world.graph.node(id)
		if n.owner == PveLevel.ENEMY and not _spawns.has(id) and n.garrison > 0 and id != _core:
			world.queue({"tick": t, "type": "send", "owner": PveLevel.ENEMY, "from": id, "to": _core, "percent": 100})
	world.step()
	if world.graph.node(_core).owner != PveLevel.PLAYER:
		_started_at_fall = _waves_started
		over = true
	elif _waves_started == _waves.size() and not _enemy_alive():
		over = true
	elif world.tick >= _limit:
		over = true

func _enemy_alive() -> bool:
	for g in world.groups:
		if g.owner == PveLevel.ENEMY:
			return true
	for id in world.graph.node_ids():
		var n := world.graph.node(id)
		if n.owner == PveLevel.ENEMY and not _spawns.has(id) and n.garrison > 0:
			return true
	return false

static func stars_for(core_lost: bool, lost: int) -> int:
	if core_lost:
		return 0
	return 1 + (1 if lost <= 1 else 0) + (1 if lost == 0 else 0)

## {stars, lost, score, waves_started, ticks}. score is the arena result.
func result() -> Dictionary:
	var lost := 0
	for id in _start:
		if world.graph.node(id).owner != PveLevel.PLAYER:
			lost += 1
	var core_lost := _started_at_fall >= 0
	var score := maxi(0, _started_at_fall - 1) if core_lost else _waves.size()
	return {"stars": stars_for(core_lost, lost), "lost": lost, "score": score,
		"waves_started": _waves_started, "ticks": world.tick}

## Runs to the end: {result, hash} (PvE vectors, server replay).
static func run(level: Dictionary, placement: Array, seed: int, cmds = []) -> Dictionary:
	var m := PveMatch.new(level, placement, seed)
	m.load_commands(cmds)
	while not m.over:
		m.step()
	return {"result": m.result(), "hash": m.world.state_hash()}

static func week_index(now: int) -> int:
	return (now - int(PveDefs.data().weekly.epoch)) / WEEK_SECS

## The weekly arena: fixed map, waves from the week's seed. Wave i: tick 40 + i*wave_gap,
## count 8 + 3i, spawn = rng pick, kind 0 for the first 3 waves then rng pick (rng order: node, kind).
static func arena_level(week: int) -> Dictionary:
	var a: Dictionary = PveDefs.data().arena
	var spawns: Array[int] = []
	for n in a.map.nodes:
		if String(n.role) == "spawn":
			spawns.append(int(n.id))
	spawns.sort()
	var rng := SimRng.new(week + 1)
	var waves := []
	for i in int(a.max_waves):
		var node := spawns[rng.range_i(spawns.size())]
		var kind := 0 if i < 3 else rng.range_i(4)
		waves.append({"tick": 40 + i * int(a.wave_gap), "node": node, "count": 8 + 3 * i, "kind": kind})
	return {"nodes": a.map.nodes, "links": a.map.links, "allowed": {}, "level": 1, "waves": waves, "arena": true,
		"week": week}
