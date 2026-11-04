extends GutTest

const BV := preload("res://game/battle_view.gd")
const MP := preload("res://game/meta_panel.gd")
const T0 := 1_800_000_000

class Fake extends Transport:
	var responses: Array = []
	var calls: Array = []
	func request(m: String, url: String, h: PackedStringArray, b: String) -> Dictionary:
		calls.append({"url": url, "body": b})
		return responses.pop_front() if not responses.is_empty() else {"status": 0, "body": ""}

func _ok(d: Dictionary) -> Dictionary:
	return {"status": 200, "body": JSON.stringify(d)}

func _signup() -> Dictionary:
	return _ok({"access_token": "t", "refresh_token": "r", "user": {"id": "u"}})

func before_each():
	if FileAccess.file_exists("user://test_auth_meta.json"):
		DirAccess.remove_absolute("user://test_auth_meta.json")

func test_booster_tap_then_node_records_command():
	BV.pending = {"colony": ColonyState.new_default(T0), "dots": 30, "seed": 4,
		"snapshot": ColonyState.new_default(T0).to_dict(), "loot_pool": 100, "attack_id": "a", "loadout": ["rage", "emp"]}
	var v: Node2D = BV.new()
	v.save_enabled = false
	add_child_autofree(v)
	assert_eq(v.battle.boosts_left, ["rage", "emp"])
	v.arm_booster("rage")
	v.on_node_tapped(1)
	assert_eq(v.commands, [{"tick": 0, "type": "boost", "booster": "rage", "node": 1}])
	assert_eq(v.battle.boosts_left, ["emp"])
	v.on_node_tapped(1)
	assert_eq(v.commands.size(), 1, "disarmed after use")

func test_loadout_max_three():
	var l: Array = []
	for b in ["rage", "emp", "rage", "split"]:
		l = MP.toggle_loadout(l, b, {"rage": 2, "emp": 1, "split": 1})
	assert_eq(l, ["rage", "emp", "rage"])
	l = MP.toggle_loadout(l, "emp", {"emp": 1})
	assert_eq(l, ["rage", "rage"], "tap again removes one")
	assert_eq(MP.toggle_loadout([], "split", {"split": 0}), [], "cannot pick what you do not own")

func test_profile_parse_and_league_text():
	var t := Fake.new()
	t.responses = [_signup(), _ok({"accepted": true, "colony": ColonyState.new_default(T0).to_dict(),
		"profile": {"league": 2, "league_name": "Złoto", "season_ends": T0 + 3 * 86400 + 5, "boosters": {"rage": 2},
			"crystals": 40, "quests": [], "trophies": 850}})]
	var b := Backend.new(t, {"url": "https://x", "anon_key": "k"}, "user://test_auth_meta.json")
	await b.sync(ColonyState.new_default(T0))
	assert_eq(b.profile.league_name, "Złoto")
	assert_eq(MP.league_text(b.profile, T0), "Złoto · koniec sezonu za 3 d")

func test_backend_shop_buy_payload():
	var t := Fake.new()
	t.responses = [_signup(), _ok({"profile": {"crystals": 25, "boosters": {"rage": 2}}})]
	var b := Backend.new(t, {"url": "https://x", "anon_key": "k"}, "user://test_auth_meta.json")
	var r := await b.shop_buy("rage")
	assert_true(t.calls[1].url.ends_with("/functions/v1/shop_buy"))
	assert_eq(JSON.parse_string(t.calls[1].body).item, "rage")
	assert_eq(int(b.profile.crystals), 25)
	assert_false(r.has("error"))

func test_auto_loadout_takes_one_of_each_owned_up_to_limit():
	assert_eq(MetaPanel.auto_loadout({}), [])
	var l := MetaPanel.auto_loadout({"rage": 2, "shield": 0, "emp": 1, "split": 3})
	assert_eq(l.size(), mini(3, MetaDefs.max_loadout()))
	assert_false(l.has("shield"), "not owned")
	for b in l:
		assert_eq(l.count(b), 1)
