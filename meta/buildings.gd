class_name Buildings
## Static building definitions. Index = level - 1. Level 0 (under first construction) has no effect.

const TYPES := ["core", "mine", "storage", "generator", "laser", "pulse", "wall", "trap"]
const MAX_LEVEL := 5
const MAX_NODES := [6, 9, 12, 16, 20]

const TABLE := {
	"core": {"cost": [0, 1000, 4000, 12000, 30000], "secs": [0, 300, 3600, 14400, 43200],
		"energy_cap": [1000, 2000, 4000, 8000, 15000]},
	"mine": {"cost": [100, 300, 800, 2000, 5000], "secs": [10, 60, 300, 1800, 7200],
		"energy_per_hour": [100, 200, 350, 550, 800]},
	"storage": {"cost": [150, 400, 1000, 2500, 6000], "secs": [10, 90, 600, 2400, 7200],
		"energy_cap": [1500, 3000, 5000, 8000, 12000]},
	"generator": {"cost": [200, 500, 1200, 3000, 7000], "secs": [20, 120, 600, 2400, 9000],
		"dots_per_hour": [60, 120, 200, 300, 450], "dots_cap": [50, 80, 120, 170, 230]},
	"laser": {"cost": [250, 600, 1500, 3500, 8000], "secs": [30, 180, 900, 3600, 10800]},
	"pulse": {"cost": [250, 600, 1500, 3500, 8000], "secs": [30, 180, 900, 3600, 10800]},
	"wall": {"cost": [50, 150, 400, 1000, 2500], "secs": [5, 30, 180, 900, 3600]},
	"trap": {"cost": [100, 250, 600, 1500, 3500], "secs": [10, 60, 300, 1200, 3600]},
}

static func is_type(type: String) -> bool:
	return TABLE.has(type)

static func _field(type: String, field: String, level: int) -> int:
	if level < 1 or level > MAX_LEVEL or not TABLE.has(type):
		return 0
	var row: Array = TABLE[type].get(field, [])
	return row[level - 1] if row.size() >= level else 0

static func cost(type: String, level: int) -> int:
	return _field(type, "cost", level)

static func build_secs(type: String, level: int) -> int:
	return _field(type, "secs", level)

static func energy_per_hour(type: String, level: int) -> int:
	return _field(type, "energy_per_hour", level)

static func dots_per_hour(type: String, level: int) -> int:
	return _field(type, "dots_per_hour", level)

static func energy_cap(type: String, level: int) -> int:
	return _field(type, "energy_cap", level)

static func dots_cap(type: String, level: int) -> int:
	return _field(type, "dots_cap", level)

static func max_nodes(core_level: int) -> int:
	return MAX_NODES[clampi(core_level, 1, MAX_LEVEL) - 1]

static func tower(type: String) -> String:
	return type if type == "laser" or type == "pulse" else ""

## Battle: defender garrison (fixed, costs the defender nothing).
static func garrison(type: String, level: int) -> int:
	if level < 1 or not TABLE.has(type):
		return 0
	match type:
		"core":
			return 30 * level
		"wall":
			return 25 * level
	return 6 * level  # traps too: a trap must look like any other building

## Battle: dots per second produced by the node during an attack.
static func battle_prod(type: String, level: int) -> int:
	return level if (type == "core" or type == "generator") and level >= 1 else 0

## Battle: dots killed by a trap on the first enemy arrival.
static func trap_dmg(type: String, level: int) -> int:
	return 10 * level if type == "trap" and level >= 1 else 0
