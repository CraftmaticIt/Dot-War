class_name Backend
extends RefCounted
## Supabase client: anonymous account, colony sync, online attacks. Every call degrades to
## offline (returns local data / {offline: true}) when the backend is unreachable or unset.

const CONFIG_PATH := "res://net/config.json"
const AUTH_PATH := "user://auth.json"

static var _shared: Backend = null

var online := false
var _t: Transport
var _url := ""
var _key := ""
var _auth_path: String
var _session := {}

static func shared(host: Node) -> Backend:
	if _shared == null:
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else {}
		_shared = Backend.new(HttpTransport.new(host), cfg if typeof(cfg) == TYPE_DICTIONARY else {}, AUTH_PATH)
	return _shared

func _init(t: Transport, cfg: Dictionary, auth_path: String) -> void:
	_t = t
	_url = String(cfg.get("url", ""))
	_key = String(cfg.get("anon_key", ""))
	_auth_path = auth_path
	if FileAccess.file_exists(_auth_path):
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(_auth_path)) == OK and typeof(j.data) == TYPE_DICTIONARY:
			_session = j.data

func is_configured() -> bool:
	return _url != "" and _key != ""

func user_id() -> String:
	return String(_session.get("user_id", ""))

func _headers(token: String) -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json", "apikey: " + _key, "Authorization: Bearer " + token])

func _parse(res: Dictionary) -> Dictionary:
	var j := JSON.new()
	var data = j.data if j.parse(String(res.body)) == OK else null
	return {"status": int(res.status), "data": data if typeof(data) == TYPE_DICTIONARY else {}}

func _store(data: Dictionary) -> bool:
	if not data.has("access_token"):
		return false
	_session = {"access_token": data.access_token, "refresh_token": data.get("refresh_token", ""),
		"user_id": data.get("user", {}).get("id", "")}
	var f := FileAccess.open(_auth_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_session))
	return true

func ensure_session() -> bool:
	if not is_configured():
		return false
	if _session.has("access_token"):
		return true
	var r := _parse(await _t.request("POST", _url + "/auth/v1/signup", _headers(_key), "{}"))
	return r.status == 200 and _store(r.data)

func _refresh() -> bool:
	var body := JSON.stringify({"refresh_token": _session.get("refresh_token", "")})
	var r := _parse(await _t.request("POST", _url + "/auth/v1/token?grant_type=refresh_token", _headers(_key), body))
	return r.status == 200 and _store(r.data)

## POST to an Edge Function. On 401 refreshes the session once and retries.
func _call(fn: String, payload: Dictionary) -> Dictionary:
	if not await ensure_session():
		online = false
		return {"status": 0, "data": {}}
	var body := JSON.stringify(payload)
	var r := _parse(await _t.request("POST", _url + "/functions/v1/" + fn, _headers(_session.access_token), body))
	if r.status == 401 and await _refresh():
		r = _parse(await _t.request("POST", _url + "/functions/v1/" + fn, _headers(_session.access_token), body))
	online = r.status != 0
	return r

## Server-authoritative colony (accepted upload or the server's own copy). Offline: unchanged.
func sync(colony: ColonyState) -> ColonyState:
	var r := await _call("sync_colony", {"colony": colony.to_dict()})
	if r.status == 200:
		var c := ColonyState.from_dict(r.data.get("colony"))
		if c != null:
			return c
	return colony

## {attack_id, snapshot, loot_pool, seed, dots, bot} | {error} | {offline: true}
func find_opponent() -> Dictionary:
	var r := await _call("find_opponent", {})
	if r.status == 0:
		return {"offline": true}
	return r.data

func finish_attack(attack_id: String, commands: Array, surrender_tick: int) -> Dictionary:
	var r := await _call("finish_attack", {"attack_id": attack_id, "commands": commands, "surrender_tick": surrender_tick})
	if r.status == 0:
		return {"offline": true}
	return r.data
