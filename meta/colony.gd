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

## Accrue production up to `now`. Filled in by Task 4.
func collect(now: int) -> Dictionary:
	return {"energy": 0, "dots": 0, "secs": 0}
