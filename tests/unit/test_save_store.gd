extends GutTest

const T0 := 1_800_000_000
const P := "user://test_colony.json"

func after_each():
	if FileAccess.file_exists(P):
		DirAccess.remove_absolute(P)

func test_save_load_roundtrip():
	var c := ColonyState.new_default(T0)
	c.energy = 777
	assert_eq(SaveStore.save(c, P), OK)
	assert_eq(SaveStore.load_or_default(T0 + 5, P).to_dict(), c.to_dict())

func test_load_missing_file_default():
	var c := SaveStore.load_or_default(T0, "user://does_not_exist.json")
	assert_eq(c.to_dict(), ColonyState.new_default(T0).to_dict())

func test_load_corrupt_file_default():
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_eq(SaveStore.load_or_default(T0, P).to_dict(), ColonyState.new_default(T0).to_dict())

func test_load_wrong_shape_default():
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("[1,2,3]")
	f.close()
	assert_eq(SaveStore.load_or_default(T0, P).to_dict(), ColonyState.new_default(T0).to_dict())

func test_load_without_core_default():
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string(JSON.stringify({"cells": {}, "energy": 5}))
	f.close()
	assert_eq(SaveStore.load_or_default(T0, P).to_dict(), ColonyState.new_default(T0).to_dict())

func _bad_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("test_colony.json.bad-"):
			out.append(f)
	return out

func before_each():
	for f in _bad_files():
		DirAccess.remove_absolute("user://" + f)

func test_corrupt_save_is_backed_up_and_flagged():
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var res := SaveStore.load_result(T0, P)
	assert_true(res.reset)
	assert_eq(res.colony.to_dict(), ColonyState.new_default(T0).to_dict())
	assert_false(FileAccess.file_exists(P), "corrupt file moved away")
	assert_eq(_bad_files(), PackedStringArray(["test_colony.json.bad-%d" % T0]))
	assert_eq(FileAccess.get_file_as_string("user://test_colony.json.bad-%d" % T0), "{not json")

func test_missing_save_not_flagged():
	var res := SaveStore.load_result(T0, "user://does_not_exist.json")
	assert_false(res.reset)

func test_valid_save_not_flagged():
	SaveStore.save(ColonyState.new_default(T0), P)
	assert_false(SaveStore.load_result(T0, P).reset)

func test_future_version_rejected():
	var d := ColonyState.new_default(T0).to_dict()
	d.version = ColonyState.SAVE_VERSION + 1
	assert_null(ColonyState.from_dict(d))

func test_to_dict_has_version():
	assert_eq(ColonyState.new_default(T0).to_dict().version, ColonyState.SAVE_VERSION)
