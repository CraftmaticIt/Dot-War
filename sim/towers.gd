class_name SimTowers
## Tower damage pass. dmg is Fx dots per tick (200 = 4 dots/s at 20 Hz).

const SPECS := {
	"laser": {"range": 4000, "dmg": 200},
	"pulse": {"range": 2000, "dmg": 60},
}

static func apply(world: SimWorld) -> void:
	if world.groups.is_empty():
		return
	var pos := {}
	for g in world.groups:
		pos[g.id] = world.group_pos(g)
	for id in world.graph.node_ids():
		var n := world.graph.node(id)
		if n.tower == "" or n.owner == 0:
			continue
		var spec: Dictionary = SPECS[n.tower]
		var dmg: int = spec.dmg * (2 + n.tower_lvl) / 3  # lvl 1 = base damage
		if n.tower == "laser":
			var target := {}
			var best := 0
			for g in world.groups:  # id-sorted, strict < keeps lower id on ties
				if g.owner == n.owner or g.count <= 0:
					continue
				var p: Vector2i = pos[g.id]
				var d := Fx.dist(n.x, n.y, p.x, p.y)
				if d <= spec.range and (target.is_empty() or d < best):
					target = g
					best = d
			if not target.is_empty():
				_hit(target, dmg)
		else:
			for g in world.groups:
				if g.owner == n.owner or g.count <= 0:
					continue
				var p: Vector2i = pos[g.id]
				if Fx.dist(n.x, n.y, p.x, p.y) <= spec.range:
					_hit(g, dmg)
	var alive: Array[Dictionary] = []
	for g in world.groups:
		if g.count > 0:
			alive.append(g)
		else:
			world.events.append({"type": "group_destroyed", "group": g.id})
	world.groups = alive

static func _hit(g: Dictionary, dmg: int) -> void:
	g.dmg_acc += dmg
	if g.dmg_acc >= Fx.ONE:
		g.count -= g.dmg_acc / Fx.ONE
		g.dmg_acc = g.dmg_acc % Fx.ONE
