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
