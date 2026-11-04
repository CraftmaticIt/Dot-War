extends GutTest

const DIR := "res://tests/vectors/"

func _vector_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out

func test_at_least_three_vectors():
	assert_gte(_vector_files().size(), 3)

func test_vectors_match_expected_hash():
	for f in _vector_files():
		var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var w := SimReplay.run(v)
		assert_eq(w.state_hash(), int(v.expected_hash), f)

func test_replay_twice_same_hash():
	for f in _vector_files():
		var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		assert_eq(SimReplay.run(v).state_hash(), SimReplay.run(v).state_hash(), f)

func test_replay_malformed_command_does_not_crash():
	var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + "v001_basic.json"))
	v.commands.append({"tick": 3, "type": "send", "owner": 1, "to": 2})
	v.commands.append({"type": "send"})
	var w := SimReplay.run(v)
	assert_eq(w.state_hash(), int(v.expected_hash), "malformed commands are no-ops")

class FloorDivWorld extends SimWorld:
	static func _fdiv(a: int, b: int) -> int:
		var q := a / b
		if a % b != 0 and ((a < 0) != (b < 0)):
			q -= 1
		return q
	func group_pos(g: Dictionary) -> Vector2i:
		var a := graph.node(g.path[g.seg])
		var b := graph.node(g.path[g.seg + 1])
		var seg_len := graph.edge_length(a.id, b.id)
		if seg_len == 0:
			return Vector2i(a.x, a.y)
		return Vector2i(a.x + _fdiv((b.x - a.x) * g.progress, seg_len), a.y + _fdiv((b.y - a.y) * g.progress, seg_len))

## A TS port using Math.floor instead of truncation must fail at least one vector.
func test_vectors_pin_truncating_division():
	var differs := false
	for f in _vector_files():
		var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var w := FloorDivWorld.new(SimGraph.from_dict(v.graph), int(v.seed))
		var ref := SimReplay.run(v, w)
		if ref.state_hash() != int(v.expected_hash):
			differs = true
	assert_true(differs)

func test_vectors_pin_armed_trap_suffix():
	var found := false
	for f in _vector_files():
		var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		if SimReplay.run(v).canonical().contains(",t"):
			found = true
	assert_true(found, "some vector ends with an armed trap in canonical()")

func test_vectors_pin_pulse_level():
	var differs := false
	for f in _vector_files():
		var v = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var changed := false
		for n in v.graph.nodes:
			if n.get("tower", "") == "pulse" and int(n.get("tower_lvl", 1)) > 1:
				n.tower_lvl = 1
				changed = true
		if changed and SimReplay.run(v).state_hash() != int(v.expected_hash):
			differs = true
	assert_true(differs, "a vector's hash depends on pulse tower level")
