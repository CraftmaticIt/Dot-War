class_name SimGraph
## Node graph of a colony/map. Positions in Fx units. Deterministic ordering everywhere.

const TOWERS := ["", "laser", "pulse"]

var _nodes := {}   # id -> Dictionary
var _adj := {}     # id -> Array[int] (kept sorted)

## trap: dots killed by the first enemy group arriving (0 = none). tower_lvl scales tower damage.
func add_node(id: int, x: int, y: int, owner: int, garrison: int, prod_per_sec: int, tower: String = "",
		trap: int = 0, tower_lvl: int = 1) -> void:
	assert(tower in TOWERS, "unknown tower: %s" % tower)
	_nodes[id] = {
		"id": id, "x": x, "y": y, "owner": owner, "garrison": garrison,
		"prod_per_sec": prod_per_sec, "tower": tower, "prod_acc": 0,
		"trap": maxi(trap, 0), "tower_lvl": maxi(tower_lvl, 1),
	}
	if not _adj.has(id):
		_adj[id] = []

func link(a: int, b: int) -> void:
	assert(_nodes.has(a) and _nodes.has(b) and a != b)
	if not _adj[a].has(b):
		_adj[a].append(b); _adj[a].sort()
		_adj[b].append(a); _adj[b].sort()

func has_node(id: int) -> bool:
	return _nodes.has(id)

func node(id: int) -> Dictionary:
	return _nodes[id]

func node_ids() -> PackedInt32Array:
	var ids := PackedInt32Array(_nodes.keys())
	ids.sort()
	return ids

func neighbors(id: int) -> PackedInt32Array:
	return PackedInt32Array(_adj[id])

func edge_length(a: int, b: int) -> int:
	var na: Dictionary = _nodes[a]
	var nb: Dictionary = _nodes[b]
	return Fx.dist(na.x, na.y, nb.x, nb.y)

## Shortest path by Euclidean edge length (Dijkstra). Ties: lower node id first,
## and lower predecessor id. Returns [] when unreachable; includes both ends.
func path(from: int, to: int) -> PackedInt32Array:
	if not _nodes.has(from) or not _nodes.has(to):
		return PackedInt32Array()
	var dist := {from: 0}
	var prev := {}
	var done := {}
	while true:
		var u := -1
		var best := 0
		for id in node_ids():
			if done.has(id) or not dist.has(id):
				continue
			if u == -1 or dist[id] < best:
				u = id
				best = dist[id]
		if u == -1 or u == to:
			break
		done[u] = true
		for v in _adj[u]:
			if done.has(v):
				continue
			var nd: int = best + edge_length(u, v)
			if not dist.has(v) or nd < dist[v] or (nd == dist[v] and u < prev[v]):
				dist[v] = nd
				prev[v] = u
	if not dist.has(to):
		return PackedInt32Array()
	var out := PackedInt32Array([to])
	var cur := to
	while cur != from:
		cur = prev[cur]
		out.append(cur)
	out.reverse()
	return out

func to_dict() -> Dictionary:
	var nodes := []
	for id in node_ids():
		nodes.append(_nodes[id].duplicate())
	var links := []
	for a in node_ids():
		for b in _adj[a]:
			if a < b:
				links.append([a, b])
	return {"nodes": nodes, "links": links}

## Accepts dicts parsed from JSON (numbers as floats) and casts to int.
static func from_dict(d: Dictionary) -> SimGraph:
	var g := SimGraph.new()
	for n in d.nodes:
		g.add_node(int(n.id), int(n.x), int(n.y), int(n.owner), int(n.garrison),
			int(n.prod_per_sec), String(n.get("tower", "")), int(n.get("trap", 0)), int(n.get("tower_lvl", 1)))
		g._nodes[int(n.id)].prod_acc = int(n.get("prod_acc", 0))
	for l in d.links:
		g.link(int(l[0]), int(l[1]))
	return g
