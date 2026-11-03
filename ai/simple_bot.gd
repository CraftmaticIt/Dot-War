class_name SimpleBot
## Minimal deterministic opponent: from its strongest node, send 50% to the
## weakest adjacent node it does not own. Returns {} when it has nothing to do.

static func decide(world: SimWorld, owner: int) -> Dictionary:
	var g := world.graph
	var src := -1
	for id in g.node_ids():
		var n := g.node(id)
		if n.owner == owner and n.garrison >= 2 and (src == -1 or n.garrison > g.node(src).garrison):
			src = id
	if src == -1:
		return {}
	var dst := -1
	for id in g.neighbors(src):
		var n := g.node(id)
		if n.owner != owner and (dst == -1 or n.garrison < g.node(dst).garrison):
			dst = id
	if dst == -1:
		return {}
	return {"tick": world.tick, "type": "send", "owner": owner, "from": src, "to": dst, "percent": 50}
