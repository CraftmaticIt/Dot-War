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

## Missing, corrupt or invalid save -> fresh default colony (never crashes).
static func load_or_default(now: int, path: String = PATH) -> ColonyState:
	if not FileAccess.file_exists(path):
		return ColonyState.new_default(now)
	var json := JSON.new()
	var c: ColonyState = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		c = ColonyState.from_dict(json.data)
	if c == null:
		push_warning("SaveStore: invalid save at %s, starting fresh" % path)
		return ColonyState.new_default(now)
	return c
