class_name MetaPanel
extends PanelContainer
## Meta screen over the colony: daily quests, booster shop, loadout for the next attack.

## Loadout chosen for the next online attack (kept across scenes).
static var loadout: Array = []

## Emitted after the server changed the balance (purchase): {crystals, boosters}.
signal profile_changed(profile: Dictionary)

var backend: Backend
var _tabs: TabContainer
var _busy := false
var _msg: Label

# --- pure helpers (unit-tested) ---

## Tap a booster: adds it (max MetaDefs.max_loadout, only as many as owned); tap again
## when no more can be added removes one.
static func toggle_loadout(l: Array, b: String, owned: Dictionary) -> Array:
	var out := l.duplicate()
	var have := int(owned.get(b, 0))
	if out.count(b) < have and out.size() < MetaDefs.max_loadout():
		out.append(b)
	elif out.has(b):
		out.erase(b)
	return out

## Used when the player picked no loadout: one of each owned booster, up to the limit.
static func auto_loadout(owned: Dictionary) -> Array:
	var out := []
	for b in MetaDefs.booster_ids():
		if int(owned.get(b, 0)) > 0 and out.size() < MetaDefs.max_loadout():
			out.append(b)
	return out

static func league_text(p: Dictionary, now: int) -> String:
	if p.is_empty():
		return ""
	var days := maxi(0, (int(p.get("season_ends", now)) - now) / 86400)
	return "%s · koniec sezonu za %d d" % [String(p.get("league_name", "?")), days]

# --- UI ---

func _ready() -> void:
	custom_minimum_size = Vector2(560, 420)
	position = Vector2(360, 150)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#11161F")
	bg.border_color = Color("#00E5FF")
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(12)
	add_theme_stylebox_override("panel", bg)
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_msg = Label.new()
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_msg)
	var close := Button.new()
	close.text = "Zamknij"
	close.pressed.connect(queue_free)
	head.add_child(close)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(540, 360)
	box.add_child(_tabs)
	rebuild()

func rebuild() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var p: Dictionary = backend.profile if backend else {}
	_msg.text = "Kryształy %d    %s" % [int(p.get("crystals", 0)), league_text(p, int(Time.get_unix_time_from_system()))]
	_tabs.add_child(_quests_tab(p))
	_tabs.add_child(_shop_tab(p))
	_tabs.add_child(_loadout_tab(p))

func _quests_tab(p: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.name = "Zadania"
	for q in p.get("quests", []):
		var l := Label.new()
		l.text = "%s  %s  %d/%d  (+%d kryształów)" % ["✔" if q.done else "•", q.text, int(q.progress), int(q.target), int(q.reward)]
		v.add_child(l)
	if p.get("quests", []).is_empty():
		var l := Label.new()
		l.text = "Zadania pojawią się po połączeniu z serwerem."
		v.add_child(l)
	return v

func _shop_tab(p: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.name = "Sklep"
	var owned: Dictionary = p.get("boosters", {})
	for b in MetaDefs.booster_ids():
		var btn := Button.new()
		btn.text = "%s (masz %d) – %d kryształów · %s" % [MetaDefs.booster_name(b), int(owned.get(b, 0)), MetaDefs.booster_price(b), MetaDefs.booster_info(b)]
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(520, 40)
		btn.disabled = backend == null or not backend.online
		btn.pressed.connect(func(): _buy(b))
		v.add_child(btn)
	return v

func _buy(b: String) -> void:
	if _busy:
		return
	if backend == null or not backend.online:
		_msg.text = "Sklep działa tylko online"
		return
	_busy = true
	var r := await backend.shop_buy(b)
	_busy = false
	if r.has("error"):
		_msg.text = "Za mało kryształów" if r.error == "no_crystals" else "Błąd: %s" % r.error
		return
	profile_changed.emit(backend.profile)
	rebuild()

func _loadout_tab(p: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.name = "Boostery"
	var owned: Dictionary = p.get("boosters", {})
	var info := Label.new()
	info.text = "Zestaw na następny atak (max %d): %s" % [MetaDefs.max_loadout(),
		", ".join(loadout.map(func(x): return MetaDefs.booster_name(x))) if not loadout.is_empty() else "pusty"]
	v.add_child(info)
	for b in MetaDefs.booster_ids():
		var btn := Button.new()
		btn.text = "%s ×%d (masz %d)" % [MetaDefs.booster_name(b), loadout.count(b), int(owned.get(b, 0))]
		btn.custom_minimum_size = Vector2(520, 40)
		btn.pressed.connect(func():
			loadout = toggle_loadout(loadout, b, owned)
			rebuild()
			_tabs.current_tab = 2)
		v.add_child(btn)
	return v
