class_name BotColony
## Deterministic bot colony for a trophy level (stand-in opponents until the backend).

const WEIGHTED := ["mine", "mine", "mine", "storage", "generator", "laser", "laser",
	"pulse", "pulse", "wall", "wall", "trap"]
## Bot size per core level, frozen at the pre-balance node limits so bot layouts (and battle vectors) stay put.
const NODES := [6, 9, 12, 16, 20]

static func generate(trophies: int, seed: int) -> Dictionary:
	var rng := SimRng.new(seed)
	var core_level := clampi(1 + trophies / 200, 1, Buildings.MAX_LEVEL)
	var c := ColonyState.new()
	c.cells[Hex.key(0, 0)] = {"type": "core", "level": core_level, "build_end": 0, "target_level": core_level}
	var count: int = NODES[core_level - 1] - rng.range_i(3)
	while c.cells.size() < count:
		var cand := _candidates(c)
		var h: Vector2i = cand[rng.range_i(cand.size())]
		var type: String = WEIGHTED[rng.range_i(WEIGHTED.size())]
		var lvl := maxi(1, core_level - rng.range_i(2))
		c.cells[Hex.key(h.x, h.y)] = {"type": type, "level": lvl, "build_end": 0, "target_level": lvl}
	return {"colony": c, "loot_pool": 300 + 3 * trophies}

## Free cells adjacent to the colony, sorted by (q, r) for determinism.
static func _candidates(c: ColonyState) -> Array[Vector2i]:
	var seen := {}
	for k in c.cells:
		var h := Hex.parse(k)
		for nb in Hex.neighbors(h.x, h.y):
			if not c.cells.has(Hex.key(nb.x, nb.y)) and Hex.distance(nb, Vector2i.ZERO) <= ColonyState.GRID_RADIUS:
				seen[nb] = true
	var out: Array[Vector2i] = []
	for h in seen:
		out.append(h)
	out.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out
