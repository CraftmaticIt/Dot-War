class_name SimWorld
## Deterministic swarm simulation. Input: commands stamped with a tick. Output: state, events, hash.

const TICK_HZ := 20
const GROUP_SPEED := 150  # Fx per tick = 3 units/s

var graph: SimGraph
var rng: SimRng
var tick := 0
## Group: {id, owner, count, path: PackedInt32Array, seg, progress, dmg_acc}
var groups: Array[Dictionary] = []
var events: Array[Dictionary] = []

var _queue: Array[Dictionary] = []
var _next_group_id := 0

func _init(p_graph: SimGraph, seed: int) -> void:
	graph = p_graph
	rng = SimRng.new(seed)

func queue(cmd: Dictionary) -> void:
	_queue.append(cmd)

func step() -> void:
	events.clear()
	_apply_commands()
	_produce()
	_move()
	_towers()
	tick += 1

func _apply_commands() -> void:
	var keep: Array[Dictionary] = []
	for cmd in _queue:
		var t := int(cmd.tick)
		if t == tick:
			_apply(cmd)
		elif t > tick:
			keep.append(cmd)
		else:
			_reject(cmd, "past_tick")
	_queue = keep

func _apply(cmd: Dictionary) -> void:
	match String(cmd.get("type", "")):
		"send":
			_apply_send(cmd)
		_:
			_reject(cmd, "unknown_type")

func _apply_send(cmd: Dictionary) -> void:
	var from := int(cmd.from)
	var to := int(cmd.to)
	var owner := int(cmd.owner)
	var pct := int(cmd.percent)
	if not graph.has_node(from) or not graph.has_node(to) or from == to:
		return _reject(cmd, "bad_node")
	var n := graph.node(from)
	if n.owner != owner:
		return _reject(cmd, "not_owner")
	if pct < 1 or pct > 100:
		return _reject(cmd, "bad_percent")
	var p := graph.path(from, to)
	if p.is_empty():
		return _reject(cmd, "no_path")
	var count: int = n.garrison * pct / 100
	if count <= 0:
		return _reject(cmd, "empty")
	n.garrison -= count
	var g := {"id": _next_group_id, "owner": owner, "count": count, "path": p,
		"seg": 0, "progress": 0, "dmg_acc": 0}
	_next_group_id += 1
	groups.append(g)
	events.append({"type": "group_spawned", "group": g.id, "owner": owner, "count": count})

func _reject(cmd: Dictionary, reason: String) -> void:
	events.append({"type": "cmd_rejected", "reason": reason, "cmd": cmd})

func _produce() -> void:
	for id in graph.node_ids():
		var n := graph.node(id)
		if n.owner == 0 or n.prod_per_sec <= 0:
			continue
		n.prod_acc += n.prod_per_sec
		while n.prod_acc >= TICK_HZ:
			n.garrison += 1
			n.prod_acc -= TICK_HZ

## Advance every group; resolve arrivals in group-id order (groups are kept id-sorted).
func _move() -> void:
	var alive: Array[Dictionary] = []
	for g in groups:
		if not _advance(g):
			alive.append(g)
	groups = alive

## Returns true when the group was consumed by a node this tick.
func _advance(g: Dictionary) -> bool:
	g.progress += GROUP_SPEED
	while true:
		var a: int = g.path[g.seg]
		var b: int = g.path[g.seg + 1]
		var seg_len := graph.edge_length(a, b)
		if g.progress < seg_len:
			return false
		g.progress -= seg_len
		g.seg += 1
		var last: bool = g.seg == g.path.size() - 1
		if last or graph.node(b).owner != g.owner:
			_arrive(g, b)
			return true
	return false

func _arrive(g: Dictionary, node_id: int) -> void:
	var n := graph.node(node_id)
	events.append({"type": "group_arrived", "group": g.id, "node": node_id})
	if n.owner == g.owner:
		n.garrison += g.count
		return
	n.garrison -= g.count
	if n.garrison < 0:
		n.owner = g.owner
		n.garrison = -n.garrison
		n.prod_acc = 0
		events.append({"type": "node_captured", "node": node_id, "owner": g.owner})

## Current position of a group in Fx, interpolated along its segment.
func group_pos(g: Dictionary) -> Vector2i:
	var a := graph.node(g.path[g.seg])
	var b := graph.node(g.path[g.seg + 1])
	var seg_len := graph.edge_length(a.id, b.id)
	if seg_len == 0:
		return Vector2i(a.x, a.y)
	return Vector2i(a.x + (b.x - a.x) * g.progress / seg_len, a.y + (b.y - a.y) * g.progress / seg_len)

func _towers() -> void:
	pass  # Task 6

## Canonical, portable state string (same format must be produced by the TS verifier).
func canonical() -> String:
	var parts := PackedStringArray(["t%d" % tick])
	for id in graph.node_ids():
		var n := graph.node(id)
		parts.append("n%d,%d,%d,%d" % [id, n.owner, n.garrison, n.prod_acc])
	for g in groups:
		var p := PackedStringArray()
		for v in g.path:
			p.append(str(v))
		parts.append("g%d,%d,%d,%d,%d,%d,%s" % [g.id, g.owner, g.count, g.seg, g.progress, g.dmg_acc, "-".join(p)])
	return "|".join(parts)

## FNV-1a 32-bit over the UTF-8 bytes of canonical().
func state_hash() -> int:
	var h := 0x811C9DC5
	for b in canonical().to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h
