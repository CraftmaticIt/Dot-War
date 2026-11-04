class_name PveDefs
## Read-only view of server/game/pve_levels.json (the same file the server uses).

const PATH := "res://server/game/pve_levels.json"
static var _d := {}

static func data() -> Dictionary:
	if _d.is_empty():
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(PATH)) == OK and typeof(j.data) == TYPE_DICTIONARY:
			_d = j.data
	return _d

## Campaign level by id; {} when unknown.
static func level(id: int) -> Dictionary:
	for l in data().get("levels", []):
		if int(l.id) == id:
			return l
	return {}

static func levels() -> Array:
	return data().get("levels", [])
