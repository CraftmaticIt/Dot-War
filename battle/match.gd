class_name BattleMatch
## One attack: wraps the SimWorld, ends on time / 100% / attacker out of dots,
## scores stars, loot and trophy delta. Int-only.

const DURATION_TICKS := 180 * SimWorld.TICK_HZ

var world: SimWorld
var over := false
var _core: int
var _pool: int
var _defender_ids: Array[int] = []

func _init(p_world: SimWorld, core_node: int, loot_pool: int) -> void:
	world = p_world
	_core = core_node
	_pool = loot_pool
	for id in world.graph.node_ids():
		if world.graph.node(id).owner == AttackSetup.DEFENDER:
			_defender_ids.append(id)

func send(from: int, to: int, percent: int) -> void:
	if over:
		return
	world.queue({"tick": world.tick, "type": "send", "owner": AttackSetup.ATTACKER,
		"from": from, "to": to, "percent": percent})

## Untrusted command (replay from a client): {tick, from, to, percent} with any value types.
## Stamped with the attacker owner and the current tick; SimWorld rejects malformed fields.
func send_raw(c: Dictionary) -> void:
	if over:
		return
	world.queue({"tick": world.tick, "type": "send", "owner": AttackSetup.ATTACKER,
		"from": c.get("from"), "to": c.get("to"), "percent": c.get("percent")})

func step() -> void:
	if over:
		return
	world.step()
	var p := progress()
	if world.tick >= DURATION_TICKS or p.destroyed_pct == 100 or _attacker_out():
		over = true

func surrender() -> void:
	over = true

func _attacker_out() -> bool:
	for g in world.groups:
		if g.owner == AttackSetup.ATTACKER and g.count > 0:
			return false
	for id in world.graph.node_ids():
		var n := world.graph.node(id)
		if n.owner == AttackSetup.ATTACKER and (n.garrison > 0 or n.prod_per_sec > 0):
			return false
	return true

func progress() -> Dictionary:
	var taken := 0
	for id in _defender_ids:
		if world.graph.node(id).owner != AttackSetup.DEFENDER:
			taken += 1
	var pct := 100 * taken / maxi(_defender_ids.size(), 1)
	var core: bool = world.graph.has_node(_core) and world.graph.node(_core).owner != AttackSetup.DEFENDER
	var stars := (1 if pct >= 50 else 0) + (1 if core else 0) + (1 if pct == 100 else 0)
	return {"destroyed_pct": pct, "core": core, "stars": stars,
		"ticks_left": maxi(0, DURATION_TICKS - world.tick)}

func result() -> Dictionary:
	var p := progress()
	var won: bool = p.stars >= 1
	return {"stars": p.stars, "destroyed_pct": p.destroyed_pct,
		"loot": _pool * p.destroyed_pct / 100 if won else 0,
		"trophies": 10 * p.stars if won else -8}
