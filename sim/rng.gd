class_name SimRng
## Deterministic xorshift32 RNG. The only randomness allowed in sim/.

const MASK := 0xFFFFFFFF
const ZERO_SEED := 2463534242

var _state: int

func _init(seed: int) -> void:
	_state = seed & MASK
	if _state == 0:
		_state = ZERO_SEED

func next_u32() -> int:
	var x := _state
	x = (x ^ (x << 13)) & MASK
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & MASK
	_state = x
	return x

## Uniform-ish integer in [0, n).
func range_i(n: int) -> int:
	return next_u32() % n
