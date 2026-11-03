class_name Hex
## Axial hex coordinates (pointy-top). Int-only, positions in Fx.

const SIZE := 2000  # hex radius in Fx
const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]

static func parse(k: String) -> Vector2i:
	var p := k.split(",")
	return Vector2i(int(p[0]), int(p[1]))

static func neighbors(q: int, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(Vector2i(q + d.x, r + d.y))
	return out

## Centre of hex in Fx (sqrt(3) ~ 1.732).
static func to_fx(q: int, r: int) -> Vector2i:
	return Vector2i(SIZE * (1732 * q + 866 * r) / 1000, SIZE * (1500 * r) / 1000)

static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
