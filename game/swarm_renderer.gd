class_name SwarmRenderer
extends MultiMeshInstance2D
## Draws every dot of every SimWorld group with one MultiMesh draw call.
## Sim groups are counts; individual dots exist only here.

const PX_PER_UNIT := 40.0       # 1 sim unit (Fx.ONE) = 40 px
const MAX_DOTS := 4096
const DOT_SIZE := 11.0
const SPREAD_PX := 24.0
const OWNER_COLORS := [
	Color("#808080"), Color("#00E5FF"), Color("#FF2E88"), Color("#B6FF00"), Color("#FFB300"),
]

var _prev := {}   # group id -> Vector2 (px) at previous tick
var _cur := {}    # group id -> Vector2 (px) at current tick
var _last_tick := -1

static func to_px(p: Vector2i) -> Vector2:
	return Vector2(p.x, p.y) * (PX_PER_UNIT / Fx.ONE)

## Deterministic offset of dot i inside group gid, within SPREAD_PX (sunflower spiral, hashed rotation).
static func dot_offset(gid: int, i: int) -> Vector2:
	var h := ((gid * 7919 + i) * 2654435761) & 0xFFFFFFFF
	var r := minf(SPREAD_PX, 5.0 * sqrt(float(i) + 0.5))
	var a := float(i) * 2.39996 + float(h % 628) / 100.0
	return Vector2(cos(a), sin(a)) * r

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(DOT_SIZE, DOT_SIZE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_DOTS
	mm.visible_instance_count = 0
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://game/glow.gdshader")
	material = mat

## alpha in [0,1]: interpolation between the previous and the current sim tick.
func sync(world: SimWorld, alpha: float) -> void:
	if world.tick != _last_tick:
		_prev = _cur
		_cur = {}
		for g in world.groups:
			_cur[g.id] = to_px(world.group_pos(g))
		_last_tick = world.tick
	var n := 0
	for g in world.groups:
		var to: Vector2 = _cur.get(g.id, to_px(world.group_pos(g)))
		var from: Vector2 = _prev.get(g.id, to)
		var center := from.lerp(to, alpha)
		var col: Color = OWNER_COLORS[g.owner % OWNER_COLORS.size()]
		for i in g.count:
			if n >= MAX_DOTS:
				break
			multimesh.set_instance_transform_2d(n, Transform2D(0.0, center + dot_offset(g.id, i)))
			multimesh.set_instance_color(n, col)
			n += 1
	multimesh.visible_instance_count = n
