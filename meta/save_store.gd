class_name SaveStore
## Local colony persistence (JSON). Atomic write: temp file + rename.

const PATH := "user://colony.json"

static func save(c: ColonyState, path: String = PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(c.to_dict()))
	f.close()
	return DirAccess.rename_absolute(tmp, path)

## Missing save -> fresh default. Corrupt/unknown save -> the file is kept as
## `<path>.bad-<now>` (never overwritten) and `reset` is true so the UI can tell the player.
static func load_result(now: int, path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"colony": ColonyState.new_default(now), "reset": false}
	var json := JSON.new()
	var c: ColonyState = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		c = ColonyState.from_dict(json.data)
	if c != null:
		return {"colony": c, "reset": false}
	var backup := "%s.bad-%d" % [path, now]
	DirAccess.rename_absolute(path, backup)
	push_warning("SaveStore: invalid save moved to %s, starting fresh" % backup)
	return {"colony": ColonyState.new_default(now), "reset": true, "backup": backup}

static func load_or_default(now: int, path: String = PATH) -> ColonyState:
	return load_result(now, path).colony
