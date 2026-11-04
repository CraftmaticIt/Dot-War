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
var _bad: Array[Dictionary] = []   # malformed commands, reported on the next step
var _next_group_id := 0

const NUM_KEYS := ["tick", "owner", "from", "to", "percent"]

func _init(p_graph: SimGraph, seed: int) -> void:
	graph = p_graph
	rng = SimRng.new(seed)

## Commands are untrusted (replays come from clients). Malformed ones are rejected,
## never crash: every numeric key must exist and be a number (JSON gives floats).
func queue(cmd: Dictionary) -> void:
	if String(cmd.get("type", "")) != "send":
		_bad.append(cmd)
		return
	var clean := {"type": "send"}
	for k in NUM_KEYS:
		var v = cmd.get(k)
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			_bad.append(cmd)
			return
		clean[k] = int(v)
	_queue.append(clean)

func step() -> void:
	events.clear()
	_apply_commands()
	_produce()
	_move()
	_towers()
	tick += 1

func _apply_commands() -> void:
	for cmd in _bad:
		_reject(cmd, "bad_cmd")
	_bad.clear()
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
	if owner <= 0:
		return _reject(cmd, "bad_owner")
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
	if n.trap > 0:
		var kill: int = mini(n.trap, g.count)
		g.count -= kill
		n.trap = 0
		events.append({"type": "trap_triggered", "node": node_id, "group": g.id, "killed": kill})
		if g.count == 0:
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
	SimTowers.apply(self)

## Canonical, portable state string (same format must be produced by the TS verifier).
func canonical() -> String:
	var parts := PackedStringArray(["t%d" % tick])
	for id in graph.node_ids():
		var n := graph.node(id)
		var seg := "n%d,%d,%d,%d" % [id, n.owner, n.garrison, n.prod_acc]
		if n.trap > 0:
			seg += ",t%d" % n.trap  # only armed traps: keeps pre-trap vector hashes stable
		parts.append(seg)
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
