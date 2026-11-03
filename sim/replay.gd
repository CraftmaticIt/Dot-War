class_name SimReplay
## Runs a determinism vector: {graph, seed, commands, ticks, expected_hash}.
## Same contract is implemented by the TS verifier (stage 4).

## `world` lets tests inject a variant; default builds a SimWorld from the vector.
static func run(v: Dictionary, world: SimWorld = null) -> SimWorld:
	var w := world if world != null else SimWorld.new(SimGraph.from_dict(v.graph), int(v.seed))
	for c in v.commands:
		w.queue(c)
	for i in int(v.ticks):
		w.step()
	return w
