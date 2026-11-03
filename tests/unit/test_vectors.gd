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
