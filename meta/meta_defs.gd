class_name MetaDefs
## Read-only view of server/game/meta_defs.json (the same file the server uses).

const PATH := "res://server/game/meta_defs.json"
static var _d := {}

static func data() -> Dictionary:
	if _d.is_empty():
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(PATH)) == OK and typeof(j.data) == TYPE_DICTIONARY:
			_d = j.data
	return _d

static func league_of(trophies: int) -> int:
	var i := 0
	var leagues: Array = data().get("leagues", [])
	for j in leagues.size():
		if trophies >= int(leagues[j].min):
			i = j
	return i

static func league_name(i: int) -> String:
	var leagues: Array = data().get("leagues", [])
	return String(leagues[clampi(i, 0, leagues.size() - 1)].name) if leagues.size() > 0 else "?"

static func booster_ids() -> Array:
	return data().get("boosters", {}).keys()

static func booster_name(b: String) -> String:
	return String(data().get("boosters", {}).get(b, {}).get("name", b))

static func booster_price(b: String) -> int:
	return int(data().get("boosters", {}).get(b, {}).get("price", 0))

static func booster_info(b: String) -> String:
	return String(data().get("boosters", {}).get(b, {}).get("info", ""))

static func quest(id: String) -> Dictionary:
	for q in data().get("quests", []):
		if q.id == id:
			return q
	return {}

static func max_loadout() -> int:
	return int(data().get("max_loadout", 3))
