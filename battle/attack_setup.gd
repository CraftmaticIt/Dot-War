class_name AttackSetup
## Builds the battle world: a copy of the defender snapshot plus three attacker entry
## nodes left of the colony, each linked to its two nearest defender nodes.

const ATTACKER := 1
const DEFENDER := 2
const ENTRY_IDS := [1001, 1002, 1003]
const ENTRY_GAP := 6000
const MIN_SPREAD := 8000

static func build(defender: SimGraph, attacker_dots: int, seed: int) -> SimWorld:
	var g := SimGraph.from_dict(defender.to_dict())
	var ids := g.node_ids()
	var min_x := 0
	var min_y := 0
	var max_y := 0
	for i in ids.size():
		var n := g.node(ids[i])
		if i == 0 or n.x < min_x:
			min_x = n.x
		if i == 0 or n.y < min_y:
			min_y = n.y
		if i == 0 or n.y > max_y:
			max_y = n.y
	var ys: Array[int] = []
	if max_y - min_y < MIN_SPREAD:
		var c := (min_y + max_y) / 2
		ys = [c - MIN_SPREAD / 2, c, c + MIN_SPREAD / 2]
	else:
		ys = [min_y, min_y + (max_y - min_y) / 2, max_y]
	var share := attacker_dots / ENTRY_IDS.size()
	var rest := attacker_dots % ENTRY_IDS.size()
	for i in ENTRY_IDS.size():
		var x := min_x - ENTRY_GAP
		g.add_node(ENTRY_IDS[i], x, ys[i], ATTACKER, share + (1 if i < rest else 0), 0)
		for target in _nearest(g, ids, x, ys[i], 2):
			g.link(ENTRY_IDS[i], target)
	return SimWorld.new(g, seed)

## The k defender ids closest to (x, y); ties -> lower id.
static func _nearest(g: SimGraph, ids: PackedInt32Array, x: int, y: int, k: int) -> Array[int]:
	var scored := []
	for id in ids:
		var n := g.node(id)
		scored.append([Fx.dist(x, y, n.x, n.y), id])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[int] = []
	for i in mini(k, scored.size()):
		out.append(scored[i][1])
	return out
