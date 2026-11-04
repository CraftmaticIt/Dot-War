extends GutTest

const T0 := 1_800_000_000
const AUTH := "user://test_auth.json"

class FakeTransport extends Transport:
	var responses: Array = []   # [{status, body}] consumed in order
	var calls: Array = []       # [{method, url, headers, body}]
	func request(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		calls.append({"method": method, "url": url, "headers": headers, "body": body})
		return responses.pop_front() if not responses.is_empty() else {"status": 0, "body": ""}

func _ok(data: Dictionary, status := 200) -> Dictionary:
	return {"status": status, "body": JSON.stringify(data)}

func _backend(t: FakeTransport) -> Backend:
	return Backend.new(t, {"url": "https://x.supabase.co", "anon_key": "anon"}, AUTH)

func _signup() -> Dictionary:
	return _ok({"access_token": "tok1", "refresh_token": "ref1", "expires_in": 3600, "user": {"id": "u1"}})

func before_each():
	if FileAccess.file_exists(AUTH):
		DirAccess.remove_absolute(AUTH)

func test_not_configured_is_offline():
	var b := Backend.new(FakeTransport.new(), {"url": "", "anon_key": ""}, AUTH)
	assert_false(b.is_configured())
	var c := ColonyState.new_default(T0)
	assert_eq((await b.sync(c)).to_dict(), c.to_dict())

func test_signup_once_and_reuse_token():
	var t := FakeTransport.new()
	t.responses = [_signup(), _ok({"accepted": true, "colony": ColonyState.new_default(T0).to_dict()}),
		_ok({"accepted": true, "colony": ColonyState.new_default(T0).to_dict()})]
	var b := _backend(t)
	await b.sync(ColonyState.new_default(T0))
	await b.sync(ColonyState.new_default(T0))
	var signups := t.calls.filter(func(c): return c.url.ends_with("/auth/v1/signup"))
	assert_eq(signups.size(), 1)
	assert_true(Array(t.calls[2].headers).has("Authorization: Bearer tok1"))
	# A new Backend reuses the stored session.
	var t2 := FakeTransport.new()
	t2.responses = [_ok({"accepted": true, "colony": ColonyState.new_default(T0).to_dict()})]
	await _backend(t2).sync(ColonyState.new_default(T0))
	assert_eq(t2.calls.size(), 1)

func test_refresh_on_401_then_retry():
	var t := FakeTransport.new()
	t.responses = [_signup(), _ok({"error": "unauthorized"}, 401),
		_ok({"access_token": "tok2", "refresh_token": "ref2", "expires_in": 3600, "user": {"id": "u1"}}),
		_ok({"accepted": true, "colony": ColonyState.new_default(T0).to_dict()})]
	var b := _backend(t)
	await b.sync(ColonyState.new_default(T0))
	assert_string_contains(t.calls[2].url, "grant_type=refresh_token")
	assert_true(Array(t.calls[3].headers).has("Authorization: Bearer tok2"))
	assert_true(b.online)

func test_offline_returns_local_state():
	var t := FakeTransport.new()   # every call -> status 0
	var b := _backend(t)
	var c := ColonyState.new_default(T0)
	c.energy = 777
	assert_eq((await b.sync(c)).energy, 777)
	assert_false(b.online)

func test_sync_adopts_server_state():
	var server := ColonyState.new_default(T0)
	server.energy = 321
	server.trophies = 55
	var t := FakeTransport.new()
	t.responses = [_signup(), _ok({"accepted": false, "reason": "energy", "colony": server.to_dict()})]
	var got := await _backend(t).sync(ColonyState.new_default(T0))
	assert_eq(got.energy, 321)
	assert_eq(got.trophies, 55)

func test_find_and_finish_payloads():
	var t := FakeTransport.new()
	t.responses = [_signup(), _ok({"attack_id": "id1", "dots": 30, "seed": 9, "loot_pool": 500, "snapshot": {}}),
		_ok({"result": {"stars": 1, "loot": 10, "trophies": 10, "destroyed_pct": 50}})]
	var b := _backend(t)
	var f := await b.find_opponent()
	assert_eq(f.attack_id, "id1")
	var r := await b.finish_attack("id1", [{"tick": 0, "from": 1001, "to": 1, "percent": 50}], 120)
	assert_eq(r.result.stars, 1)
	var body = JSON.parse_string(t.calls[2].body)
	assert_eq(body.attack_id, "id1")
	assert_eq(int(body.surrender_tick), 120)
	assert_eq(body.commands.size(), 1)

func test_failed_refresh_counts_as_offline():
	var t := FakeTransport.new()
	t.responses = [_signup(), _ok({"error": "unauthorized"}, 401), _ok({"error": "bad"}, 400)]
	var b := _backend(t)
	await b.sync(ColonyState.new_default(T0))
	assert_false(b.online, "a dead session must not show online")
	assert_true(b.session_lost)

func test_sync_exposes_reason_and_defenses():
	var t := FakeTransport.new()
	t.responses = [_signup(), _ok({"accepted": false, "reason": "energy", "colony": ColonyState.new_default(T0).to_dict(),
		"defenses": {"count": 2, "loot": 150}})]
	var b := _backend(t)
	await b.sync(ColonyState.new_default(T0))
	assert_eq(b.last_sync.reason, "energy")
	assert_eq(int(b.last_sync.defenses.loot), 150)

func test_adopt_only_when_unchanged_meanwhile():
	var CV = load("res://game/colony_view.gd")
	var before := ColonyState.new_default(T0)
	var server := ColonyState.new_default(T0)
	server.trophies = 9
	assert_eq(CV.after_sync(before.to_dict(), before, server, true).trophies, 9)
	var changed := ColonyState.new_default(T0)
	changed.energy = 1
	assert_null(CV.after_sync(before.to_dict(), changed, server, true), "local action during sync -> keep local, resync")
	assert_null(CV.after_sync(before.to_dict(), before, server, false), "offline -> nothing to adopt")
