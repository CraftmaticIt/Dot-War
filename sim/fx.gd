class_name Fx
## Fixed-point integer math for the deterministic simulation. Scale: ONE = 1000.

const ONE := 1000

static func from_int(i: int) -> int:
	return i * ONE

## Product of two fixed values; GDScript int division truncates toward zero.
static func mul(a: int, b: int) -> int:
	return (a * b) / ONE

static func div(a: int, b: int) -> int:
	return (a * ONE) / b

## Integer square root (floor) via Newton's method.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x

## Euclidean distance between two fixed-point points, in fixed-point.
static func dist(ax: int, ay: int, bx: int, by: int) -> int:
	var dx := bx - ax
	var dy := by - ay
	return isqrt(dx * dx + dy * dy)
