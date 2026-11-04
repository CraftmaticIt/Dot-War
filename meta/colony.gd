class_name ColonyState
## Player colony on a hex grid: buildings, resources, build timers. Int-only; time is
## always passed in as `now` (unix seconds) so the same logic can run on the server.

const BUILDERS := 2
const OFFLINE_CAP_SECS := 8 * 3600

## Hex.key -> {type, level, build_end (0 = idle), target_level}
var cells := {}
var energy := 0
var crystals := 0
var dots := 0
var last_collect := 0
var trophies := 0
var attacks := 0
var attack_open := 0  # 1 between begin_attack and apply_result (abandoned battle = loss)
var energy_rem := 0  # carried remainder of rate*secs (per 3600)
var dots_rem := 0

static func new_default(now: int) -> ColonyState:
	var c := ColonyState.new()
	c.cells[Hex.key(0, 0)] = _cell("core", 1)
	c.cells[Hex.key(1, 0)] = _cell("mine", 1)
	c.energy = 500
	c.crystals = 50
	c.last_collect = now
	return c

static func _cell(type: String, level: int) -> Dictionary:
	return {"type": type, "level": level, "build_end": 0, "target_level": level}

func core_level() -> int:
	for k in cells:
		if cells[k].type == "core":
			return maxi(cells[k].level, 1)
	return 1

func busy_builders(now: int) -> int:
	var n := 0
	for k in cells:
		if cells[k].build_end > now:
			n += 1
	return n

func _adjacent_to_colony(q: int, r: int) -> bool:
	for nb in Hex.neighbors(q, r):
		if cells.has(Hex.key(nb.x, nb.y)):
			return true
	return false

func can_place(type: String, q: int, r: int, now: int) -> String:
	finish_builds(now)  # due builds count as done (idempotent, no resource change)
	if not Buildings.is_type(type):
		return "bad_type"
	if type == "core":
		return "core_unique"
	if cells.has(Hex.key(q, r)):
		return "occupied"
	if not _adjacent_to_colony(q, r):
		return "not_adjacent"
	if cells.size() >= Buildings.max_nodes(core_level()):
		return "node_limit"
	if busy_builders(now) >= BUILDERS:
		return "no_builder"
	if energy < Buildings.cost(type, 1):
		return "no_energy"
	return ""

func place(type: String, q: int, r: int, now: int) -> String:
	collect(now)
	var err := can_place(type, q, r, now)
	if err != "":
		return err
	energy -= Buildings.cost(type, 1)
	cells[Hex.key(q, r)] = {"type": type, "level": 0, "target_level": 1,
		"build_end": now + Buildings.build_secs(type, 1)}
	finish_builds(now)  # zero-time builds complete immediately
	return ""

func can_upgrade(q: int, r: int, now: int) -> String:
	finish_builds(now)  # due builds count as done (idempotent, no resource change)
	var k := Hex.key(q, r)
	if not cells.has(k):
		return "empty"
	var c: Dictionary = cells[k]
	if c.build_end != 0:
		return "busy"
	if c.level >= Buildings.MAX_LEVEL:
		return "max_level"
	if c.type != "core" and c.level + 1 > core_level():
		return "core_limit"
	if busy_builders(now) >= BUILDERS:
		return "no_builder"
	if energy < Buildings.cost(c.type, c.level + 1):
		return "no_energy"
	return ""

func upgrade(q: int, r: int, now: int) -> String:
	collect(now)
	var err := can_upgrade(q, r, now)
	if err != "":
		return err
	var c: Dictionary = cells[Hex.key(q, r)]
	energy -= Buildings.cost(c.type, c.level + 1)
	c.target_level = c.level + 1
	c.build_end = now + Buildings.build_secs(c.type, c.target_level)
	finish_builds(now)
	return ""

## 1 crystal per started minute of remaining time, min 1. 0 when nothing is building.
func speedup_cost(q: int, r: int, now: int) -> int:
	var k := Hex.key(q, r)
	if not cells.has(k) or cells[k].build_end <= now:
		return 0
	var left: int = cells[k].build_end - now
	return maxi(1, (left + 59) / 60)

func speedup(q: int, r: int, now: int) -> String:
	collect(now)
	var cost := speedup_cost(q, r, now)
	if cost == 0:
		return "not_building"
	if crystals < cost:
		return "no_crystals"
	crystals -= cost
	cells[Hex.key(q, r)].build_end = now
	finish_builds(now)
	return ""

func finish_builds(now: int) -> void:
	for k in cells:
		var c: Dictionary = cells[k]
		if c.build_end != 0 and c.build_end <= now:
			c.level = c.target_level
			c.build_end = 0

func energy_cap() -> int:
	var cap := 0
	for k in cells:
		cap += Buildings.energy_cap(cells[k].type, cells[k].level)
	return cap

func dots_cap() -> int:
	var cap := 0
	for k in cells:
		cap += Buildings.dots_cap(cells[k].type, cells[k].level)
	return cap

func _rates() -> Vector2i:
	var e := 0
	var d := 0
	for k in cells:
		e += Buildings.energy_per_hour(cells[k].type, cells[k].level)
		d += Buildings.dots_per_hour(cells[k].type, cells[k].level)
	return Vector2i(e, d)

## Accrue production up to `now` (offline window capped at 8 h). Builds that finish inside
## the window switch rates at their exact second. Clock going backwards accrues nothing.
func collect(now: int) -> Dictionary:
	if now <= last_collect:
		finish_builds(now)  # clock behind: no production, but due builds still complete
		return {"energy": 0, "dots": 0, "secs": 0}
	var start := maxi(last_collect, now - OFFLINE_CAP_SECS)
	finish_builds(start)
	var points: Array[int] = []
	for k in cells:
		var be: int = cells[k].build_end
		if be > start and be < now and not points.has(be):
			points.append(be)
	points.sort()
	points.append(now)
	var e0 := energy
	var d0 := dots
	var t0 := start
	for t1 in points:
		var rate := _rates()
		energy_rem += rate.x * (t1 - t0)
		energy += energy_rem / 3600
		energy_rem %= 3600
		dots_rem += rate.y * (t1 - t0)
		dots += dots_rem / 3600
		dots_rem %= 3600
		# Full storage: production is lost. Stock already above cap (e.g. loot) is kept.
		var ecap := energy_cap()
		if energy >= ecap:
			energy = maxi(ecap, e0)
			energy_rem = 0
		var dcap := dots_cap()
		if dots >= dcap:
			dots = maxi(dcap, d0)
			dots_rem = 0
		finish_builds(t1)
		t0 = t1
	last_collect = now
	return {"energy": energy - e0, "dots": dots - d0, "secs": now - start}

const SAVE_VERSION := 1
const _INT_FIELDS := ["energy", "crystals", "dots", "last_collect", "energy_rem", "dots_rem", "trophies", "attacks", "attack_open"]
const MIN_ATTACK_DOTS := 10

func to_dict() -> Dictionary:
	var out := {"version": SAVE_VERSION, "cells": {}}
	var keys := cells.keys()
	keys.sort()
	for k in keys:
		out.cells[k] = cells[k].duplicate()
	for f in _INT_FIELDS:
		out[f] = get(f)
	return out

## Builds from a dict (JSON numbers arrive as floats). Unknown building types are dropped.
## Returns null when the data is not a usable colony (no core).
static func from_dict(d) -> ColonyState:
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("cells")) != TYPE_DICTIONARY:
		return null
	var ver = d.get("version", 1)
	if (typeof(ver) != TYPE_INT and typeof(ver) != TYPE_FLOAT) or int(ver) > SAVE_VERSION:
		return null  # unknown/future format: never guess
	var c := ColonyState.new()
	for k in d.cells:
		var cell = d.cells[k]
		if typeof(cell) != TYPE_DICTIONARY or not Buildings.is_type(String(cell.get("type", ""))):
			continue
		var p := Hex.parse(String(k))
		c.cells[Hex.key(p.x, p.y)] = {
			"type": String(cell.type),
			"level": clampi(int(cell.get("level", 0)), 0, Buildings.MAX_LEVEL),
			"build_end": int(cell.get("build_end", 0)),
			"target_level": clampi(int(cell.get("target_level", 0)), 0, Buildings.MAX_LEVEL),
		}
	var has_core := false
	for k in c.cells:
		if c.cells[k].type == "core":
			has_core = true
	if not has_core:
		return null
	for f in _INT_FIELDS:
		var v = d.get(f, 0)
		c.set(f, int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0)
	return c

## node id -> hex, ids 1..n over built cells (level >= 1) in sorted (q, r) order.
## Same ids as to_sim_graph(); the battle UI uses it to map nodes back to hexes.
func snapshot_ids() -> Dictionary:
	var built: Array[Vector2i] = []
	for k in cells:
		if cells[k].level >= 1:
			built.append(Hex.parse(k))
	built.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var out := {}
	for i in built.size():
		out[i + 1] = built[i]
	return out

## Defender snapshot for the swarm simulation: one node per built cell with battle stats
## (garrison, production, trap, tower level), links between adjacent built cells.
func to_sim_graph(owner: int) -> SimGraph:
	var ids := snapshot_ids()
	var by_hex := {}
	var g := SimGraph.new()
	for id in ids:
		var h: Vector2i = ids[id]
		var cell: Dictionary = cells[Hex.key(h.x, h.y)]
		var pos := Hex.to_fx(h.x, h.y)
		var t: String = cell.type
		var lvl: int = cell.level
		g.add_node(id, pos.x, pos.y, owner, Buildings.garrison(t, lvl), Buildings.battle_prod(t, lvl),
			Buildings.tower(t), Buildings.trap_dmg(t, lvl), lvl if Buildings.tower(t) != "" else 1)
		by_hex[h] = id
	for id in ids:
		var h: Vector2i = ids[id]
		for nb in Hex.neighbors(h.x, h.y):
			if by_hex.has(nb) and id < by_hex[nb]:
				g.link(id, by_hex[nb])
	return g

func can_attack(_now: int) -> String:
	return "" if dots >= MIN_ATTACK_DOTS else "few_dots"

## Spends all dots on an attack. Returns {dots, seed} or {error} with state unchanged.
func begin_attack(now: int) -> Dictionary:
	collect(now)
	var err := can_attack(now)
	if err != "":
		return {"error": err}
	var n := dots
	dots = 0
	dots_rem = 0
	attacks += 1
	attack_open = 1
	return {"dots": n, "seed": attacks * 7919 + trophies}

## Loot may exceed the storage cap (kept, see collect()). Trophies never go below 0.
func apply_result(r: Dictionary) -> void:
	energy += int(r.get("loot", 0))
	trophies = maxi(0, trophies + int(r.get("trophies", 0)))
	attack_open = 0

const ABANDON_TROPHIES := -8

## An attack that never reported back (app killed mid-battle) counts as a 0-star loss.
func resolve_abandoned_attack() -> bool:
	if attack_open == 0:
		return false
	apply_result({"loot": 0, "trophies": ABANDON_TROPHIES, "stars": 0, "destroyed_pct": 0})
	return true
