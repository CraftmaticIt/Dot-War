class_name PveLevel
## PvE level -> SimWorld. Placement = [{slot, type}], validated the same way as the server.

const PLAYER := 1
const ENEMY := 2
const TYPES := ["laser", "pulse", "wall", "trap"]

static func _int(v) -> int:
	return int(v) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) == floorf(float(v)) else -1

static func _roles(level: Dictionary) -> Dictionary:
	var out := {}
	for n in level.get("nodes", []):
		out[int(n.id)] = String(n.role)
	return out

## "" or "bad_placement". Campaign: counts within `allowed`; arena: total cost within the budget.
static func validate(level: Dictionary, placement, arena: bool) -> String:
	if typeof(placement) != TYPE_ARRAY:
		return "bad_placement"
	var roles := _roles(level)
	var a: Dictionary = PveDefs.data().arena
	var used := {}
	var counts := {}
	var cost := 0
	for e in placement:
		if typeof(e) != TYPE_DICTIONARY or typeof(e.get("type")) != TYPE_STRING:
			return "bad_placement"
		var slot := _int(e.get("slot"))
		var t := String(e.type)
		if roles.get(slot, "") != "slot" or used.has(slot) or not TYPES.has(t):
			return "bad_placement"
		used[slot] = true
		counts[t] = int(counts.get(t, 0)) + 1
		if arena:
			if not a.costs.has(t):
				return "bad_placement"
			cost += int(a.costs[t])
		elif counts[t] > int(level.get("allowed", {}).get(t, 0)):
			return "bad_placement"
	return "bad_placement" if arena and cost > int(a.budget) else ""

static func _types(placement: Array) -> Dictionary:
	var out := {}
	for e in placement:
		out[int(e.slot)] = String(e.type)
	return out

## Assumes a validated placement.
static func build_world(level: Dictionary, placement: Array, seed: int) -> SimWorld:
	var lvl := int(level.get("level", 1))
	var types := _types(placement)
	var g := SimGraph.new()
	for n in level.nodes:
		var id := int(n.id)
		var x := int(n.x)
		var y := int(n.y)
		match String(n.role):
			"core":
				g.add_node(id, x, y, PLAYER, Buildings.garrison("core", lvl), Buildings.battle_prod("core", lvl))
			"spawn":
				g.add_node(id, x, y, ENEMY, 0, 0)
			_:
				if types.has(id):
					var t: String = types[id]
					g.add_node(id, x, y, PLAYER, Buildings.garrison(t, lvl), Buildings.battle_prod(t, lvl),
						Buildings.tower(t), Buildings.trap_dmg(t, lvl), lvl)
				else:
					g.add_node(id, x, y, 0, 0, 0)
	for l in level.links:
		g.link(int(l[0]), int(l[1]))
	return SimWorld.new(g, seed)

static func core_id(level: Dictionary) -> int:
	for n in level.nodes:
		if String(n.role) == "core":
			return int(n.id)
	return -1

## Core + occupied slots, sorted.
static func player_nodes(level: Dictionary, placement: Array) -> Array[int]:
	var out: Array[int] = [core_id(level)]
	for e in placement:
		out.append(int(e.slot))
	out.sort()
	return out
