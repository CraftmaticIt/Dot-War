class_name SimReplay
## Runs a determinism vector: {graph, seed, commands, ticks, expected_hash}.
## Same contract is implemented by the TS verifier (stage 4).

static func run(v: Dictionary) -> SimWorld:
	var w := SimWorld.new(SimGraph.from_dict(v.graph), int(v.seed))
	for c in v.commands:
		w.queue({"tick": int(c.tick), "type": String(c.type), "owner": int(c.owner),
			"from": int(c.from), "to": int(c.to), "percent": int(c.percent)})
	for i in int(v.ticks):
		w.step()
	return w
