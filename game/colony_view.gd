extends Node2D
## Colony screen: hex grid, build menu, building panel, resource HUD.
## User args `-- --shot <png>`: fresh colony, auto-builds two buildings, screenshot, quit.

const HEX_PX := 44.0          # hex radius on screen
const GRID_RADIUS := 4
const PLAYER := Color("#00E5FF")
const NAMES := {"core": "Rdzeń", "mine": "Kopalnia", "storage": "Magazyn", "generator": "Generator",
	"laser": "Laser", "pulse": "Puls", "wall": "Ściana", "trap": "Pułapka"}
## What each building is for (shown in the build menu and the building panel).
const INFO := {
	"core": "Serce kolonii. Jego poziom podnosi limit węzłów i maks. poziom budynków. Gdy padnie, wróg dostaje gwiazdkę.",
	"mine": "Produkuje energię – za nią budujesz i ulepszasz.",
	"storage": "Podnosi limit energii. Gdy energia dojdzie do limitu, kopalnie stają.",
	"generator": "Produkuje kropki – Twoją armię do ataku. Ma własny limit kropek.",
	"laser": "Wieża obrony: strzela w jedną wrogą grupę, duży zasięg.",
	"pulse": "Wieża obrony: rani wszystkie wrogie grupy obok siebie, krótki zasięg.",
	"wall": "Twardy węzeł z dużym garnizonem – wróg musi się przez niego przebić.",
	"trap": "Ukryta przed wrogiem mina: zabija kropki pierwszej wrogiej grupy, potem znika.",
}
const LETTERS := {"core": "C", "mine": "M", "storage": "S", "generator": "G",
	"laser": "L", "pulse": "P", "wall": "W", "trap": "T"}

var colony: ColonyState        # may be injected before _ready (tests)
var save_enabled := true
var backend: Backend = null
var _open_meta_on_ready := false
var _sync_in := -1.0   # seconds until a debounced server sync (-1 = none)
const SYNC_DEBOUNCE := 3.0
var origin := Vector2(640, 380)
var selected := Vector2i(999, 999)
var _hud: Label
var _panel: VBoxContainer
var _toast: Label
var _toast_left := 0.0
var _tick := 0.0
var _shot := ""
var _shot_left := 2.0
var _font: Font
var _timer_label: Label = null
var _dyn_buttons: Array = []    # [Button, Callable -> [text, err]] refreshed every second
var _sig := ""

# --- pure helpers (unit-tested) ---

static func hex_to_px(q: int, r: int, o: Vector2) -> Vector2:
	var f := Hex.to_fx(q, r)
	return o + Vector2(f.x, f.y) * (HEX_PX / Hex.SIZE)

## Pixel -> axial hex (cube rounding).
static func cell_at(px: Vector2, o: Vector2) -> Vector2i:
	var p := (px - o) / HEX_PX
	var qf := (sqrt(3.0) / 3.0) * p.x - p.y / 3.0
	var rf := (2.0 / 3.0) * p.y
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)

static func few_dots_text(c: ColonyState) -> String:
	for k in c.cells:
		if c.cells[k].type == "generator" and c.cells[k].level >= 1:
			return "Za mało kropek (%d/%d) – Generator produkuje dalej" % [c.dots, ColonyState.MIN_ATTACK_DOTS]
	return "Za mało kropek – zbuduj Generator"

static func format_secs(s: int) -> String:
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]

## Polish plural: 1 kryształ, 2-4 kryształy, 5+ kryształów (12-14 -> kryształów).
static func crystals_word(n: int) -> String:
	if n == 1:
		return "kryształ"
	if n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14):
		return "kryształy"
	return "kryształów"

## Numbers for this level.
static func describe(type: String, level: int) -> String:
	match type:
		"mine":
			return "+%d energii/h" % Buildings.energy_per_hour(type, level)
		"generator":
			return "+%d kropek/h, limit %d" % [Buildings.dots_per_hour(type, level), Buildings.dots_cap(type, level)]
		"storage":
			return "magazyn +%d" % Buildings.energy_cap(type, level)
		"core":
			return "magazyn +%d, limit węzłów %d" % [Buildings.energy_cap(type, level), Buildings.max_nodes(level)]
		"trap":
			return "zabija %d kropek" % Buildings.trap_dmg(type, level)
	return "garnizon %d" % Buildings.garrison(type, level)

# --- scene ---

func _now() -> int:
	return int(Time.get_unix_time_from_system())

func _ready() -> void:
	_font = ThemeDB.fallback_font
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i != -1 and i + 1 < args.size():
		_shot = args[i + 1]
		colony = ColonyState.new_default(_now())
		colony.place("storage", -1, 1, _now())
		colony.place("laser", -1, 0, _now())
		selected = Vector2i(-1, 1)
		if args.has("--meta"):
			_open_meta_on_ready = true
	elif colony == null:
		var res := SaveStore.load_result(_now())
		colony = res.colony
		if res.reset:
			_show_toast("Zapis był uszkodzony – kopia zachowana, start od nowa")
		backend = Backend.shared(get_tree().root)
		if not backend.is_configured() and colony.resolve_abandoned_attack():
			_show_toast("Przerwana bitwa = porażka (%d trofeów)" % ColonyState.ABANDON_TROPHIES)
		var got := colony.collect(_now())
		if got.energy > 0 or got.dots > 0:
			_show_toast("Zebrano +%d energii, +%d kropek" % [got.energy, got.dots])
		_save()
	_build_ui()
	_refresh()
	if _open_meta_on_ready:
		var m := MetaPanel.new()
		m.backend = Backend.new(Transport.new(), {}, "user://shot_auth.json")
		m.backend.profile = {"league": 1, "league_name": "Srebro", "season_ends": _now() + 9 * 86400, "crystals": 42,
			"boosters": {"rage": 2, "shield": 1, "emp": 0, "split": 1},
			"quests": [{"text": "Wygraj 2 ataki", "progress": 1, "target": 2, "reward": 10, "done": false},
				{"text": "Zdobądź 5 gwiazdek", "progress": 5, "target": 5, "reward": 10, "done": true},
				{"text": "Ulepsz 3 budynki", "progress": 0, "target": 3, "reward": 8, "done": false}]}
		get_child(get_child_count() - 1).add_child(m)
	if backend != null and backend.is_configured():
		_sync_server()

## What to keep after a sync: the server copy, unless the player acted while the request was
## in flight (then keep local and sync again) or we are offline. null = keep current.
static func after_sync(before: Dictionary, current: ColonyState, got: ColonyState, online: bool) -> ColonyState:
	if not online or current.to_dict() != before:
		return null
	return got if got.to_dict() != before else null

## Uploads the colony; adopts the server's copy (server owns trophies/crystals and rejects
## impossible jumps). Tells the player about rejections and attacks on their colony.
func _sync_server() -> void:
	if backend == null or not backend.is_configured():
		return
	var before := colony.to_dict()
	var got := await backend.sync(colony)
	if backend.online and colony.to_dict() != before:
		_sync_in = SYNC_DEBOUNCE  # acted meanwhile: upload again shortly
	var keep := after_sync(before, colony, got, backend.online)
	if keep != null:
		colony = keep
		_save()
	if backend.online:
		var lr = backend.profile.get("last_reward")
		if typeof(lr) == TYPE_DICTIONARY and int(lr.get("season", -1)) > _seen_reward_season():
			_mark_reward_seen(int(lr.season))
			_show_toast("Koniec sezonu: liga %s, +%d kryształów" % [String(lr.get("league_name", "")), int(lr.get("reward", 0))])
		var d: Dictionary = backend.last_sync.get("defenses", {})
		if int(d.get("count", 0)) > 0:
			_show_toast("Twoja kolonia została zaatakowana (%d×): −%d energii" % [int(d.count), int(d.get("loot", 0))])
		elif not backend.last_sync.get("accepted", true) and keep != null:
			_show_toast("Serwer przywrócił zapis (%s)" % backend.last_sync.get("reason", "?"))
	elif backend.session_lost:
		_show_toast("Sesja serwera utracona – gra offline")
	_refresh()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(_hud)
	var attack := Button.new()
	attack.text = "Atak"
	attack.custom_minimum_size = Vector2(120, 48)
	attack.position = Vector2(1144, 12)
	attack.pressed.connect(_on_attack)
	layer.add_child(attack)
	var meta := Button.new()
	meta.text = "Meta"
	meta.custom_minimum_size = Vector2(120, 48)
	meta.position = Vector2(1016, 12)
	meta.pressed.connect(func():
		var m := MetaPanel.new()
		m.backend = backend
		m.profile_changed.connect(_adopt_profile)
		layer.add_child(m))
	layer.add_child(meta)
	var training := Button.new()
	training.text = "Trening"
	training.custom_minimum_size = Vector2(120, 48)
	training.position = Vector2(1144, 668)
	training.pressed.connect(func():
		_save()
		get_tree().change_scene_to_file("res://game/prototype.tscn"))
	layer.add_child(training)
	_panel = VBoxContainer.new()
	_panel.position = Vector2(16, 80)
	_panel.custom_minimum_size = Vector2(300, 0)
	layer.add_child(_panel)
	_toast = Label.new()
	_toast.position = Vector2(440, 660)
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color("#B6FF00"))
	layer.add_child(_toast)

func _show_toast(msg: String) -> void:
	if _toast:
		_toast.text = msg
	else:
		call_deferred("_show_toast", msg)
	_toast_left = 4.0

const SEEN_PATH := "user://meta_seen.json"

## The server owns the crystal balance: show what it says (purchases, rewards).
func _adopt_profile(p: Dictionary) -> void:
	if p.has("crystals"):
		colony.crystals = int(p.crystals)
		_save()
		_refresh()

var _attacking := false

func _seen_reward_season() -> int:
	var j := JSON.new()
	if FileAccess.file_exists(SEEN_PATH) and j.parse(FileAccess.get_file_as_string(SEEN_PATH)) == OK and typeof(j.data) == TYPE_DICTIONARY:
		return int(j.data.get("season", -1))
	return -1

func _mark_reward_seen(season: int) -> void:
	var f := FileAccess.open(SEEN_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"season": season}))

func _on_attack() -> void:
	if _attacking:
		return  # a second tap would abandon the first attack (and its boosters)
	_attacking = true
	await _on_attack_inner()
	_attacking = false

func _on_attack_inner() -> void:
	if backend != null and backend.is_configured():
		await _sync_server()  # server must see the dots produced since the last upload
		var res := await backend.find_opponent(MetaPanel.loadout)
		if not res.has("offline"):
			if res.has("error"):
				_show_toast(few_dots_text(colony) if res.error == "few_dots"
				else ("Brak boosterów z zestawu" if res.error == "no_boosters" else "Serwer: %s" % res.error))
				return
			colony.dots = 0
			colony.dots_rem = 0
			colony.attacks += 1
			colony.attack_open = 1
			_save()
			BattleView.pending = {"colony": colony, "dots": int(res.dots), "seed": int(res.seed),
				"snapshot": res.snapshot, "loot_pool": int(res.loot_pool), "attack_id": String(res.attack_id),
				"loadout": res.get("loadout", [])}
			MetaPanel.loadout = []
			get_tree().change_scene_to_file("res://game/battle_view.tscn")
			return
	var a := colony.begin_attack(_now())
	if a.has("error"):
		_show_toast(few_dots_text(colony))
		return
	_save()
	BattleView.pending = {"colony": colony, "dots": a.dots, "seed": a.seed}
	get_tree().change_scene_to_file("res://game/battle_view.tscn")

func _save() -> void:
	if _shot == "" and save_enabled:
		if SaveStore.save(colony) != OK:
			_show_toast("Nie udało się zapisać gry")

func _notification(what: int) -> void:
	if colony == null:
		return
	if what == NOTIFICATION_APPLICATION_RESUMED:
		var got := colony.collect(_now())
		if got.energy > 0 or got.dots > 0:
			_show_toast("Zebrano +%d energii, +%d kropek" % [got.energy, got.dots])
		_refresh()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		_sync_server()

func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		on_second()
	if _sync_in > 0.0:
		_sync_in -= delta
		if _sync_in <= 0.0:
			_sync_in = -1.0
			_sync_server()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.text = ""
	if _shot != "":
		_shot_left -= delta
		if _shot_left <= 0.0:
			var path := _shot
			_shot = ""
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:
	# Touch arrives as emulated mouse too (emulate_mouse_from_touch): handle the mouse event only.
	var tap: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed
	if not tap:
		return
	var h := cell_at(e.position, origin)
	select(h if Hex.distance(h, Vector2i.ZERO) <= GRID_RADIUS else Vector2i(999, 999))

# --- refresh model: the panel is rebuilt only when the structure changes (selection,
# player action, build finished). The 1 s tick only updates texts, so buttons are never
# freed between finger-down and finger-up.

func select(h: Vector2i) -> void:
	selected = h
	_refresh()

func panel_nodes() -> Array:
	return _panel.get_children()

func timer_label() -> Label:
	return _timer_label

func on_second() -> void:
	var now := _now()
	colony.collect(now)
	if _structure_sig(now) != _sig:
		_refresh()
	else:
		_update_dynamic(now)

func _structure_sig(now: int) -> String:
	var parts := PackedStringArray([Hex.key(selected.x, selected.y)])
	var keys := colony.cells.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = colony.cells[k]
		parts.append("%s:%s:%d:%d:%s" % [k, c.type, c.level, c.target_level, str(c.build_end > now)])
	return "|".join(parts)

func _refresh() -> void:
	var now := _now()
	_sig = _structure_sig(now)
	_rebuild_panel(now)
	_update_dynamic(now)

func _update_dynamic(now: int) -> void:
	var net := "" if backend == null or not backend.is_configured() else ("● online    " if backend.online else "○ offline    ")
	if backend != null and not backend.profile.is_empty():
		net += MetaPanel.league_text(backend.profile, now) + "    "
	_hud.text = "Energia %d / %d    Kropki %d / %d    Kryształy %d    Budowniczowie %d/%d    Węzły %d/%d    Trofea %d" % [
		colony.energy, colony.energy_cap(), colony.dots, colony.dots_cap(), colony.crystals,
		colony.busy_builders(now), ColonyState.BUILDERS, colony.cells.size(), Buildings.max_nodes(colony.core_level()),
		colony.trophies] + ("" if net == "" else "\n" + net.strip_edges())
	var k := Hex.key(selected.x, selected.y)
	if _timer_label != null and colony.cells.has(k):
		var cell: Dictionary = colony.cells[k]
		_timer_label.text = "Budowa → poz. %d: %s" % [cell.target_level, format_secs(maxi(0, cell.build_end - now))]
	for pair in _dyn_buttons:
		var b: Button = pair[0]
		var st: Array = pair[1].call(now)
		b.text = st[0] if st[1] == "" else "%s  (%s)" % [st[0], st[1]]
		b.disabled = st[1] != ""
	queue_redraw()

func _rebuild_panel(now: int) -> void:
	_timer_label = null
	_dyn_buttons.clear()
	for c in _panel.get_children():
		_panel.remove_child(c)
		c.queue_free()
	if Hex.distance(selected, Vector2i.ZERO) > GRID_RADIUS:
		return
	var k := Hex.key(selected.x, selected.y)
	if colony.cells.has(k):
		_panel_building(colony.cells[k], now)
	else:
		_panel_build_menu(now)

func _info(text: String) -> void:
	var l := _label(text, 14, Color(1, 1, 1, 0.6))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)

func _label(text: String, size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_panel.add_child(l)
	return l

## state: Callable(now) -> [text, err]; re-evaluated every second without rebuilding.
func _button(state: Callable, cb: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 44)
	b.size = Vector2(300, 44)
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_panel.add_child(b)
	_dyn_buttons.append([b, state])

func _panel_building(cell: Dictionary, now: int) -> void:
	var q := selected.x
	var r := selected.y
	_label("%s  poz. %d" % [NAMES[cell.type], cell.level], 22, PLAYER)
	_info(INFO[cell.type])
	if cell.level > 0:
		_label(describe(cell.type, cell.level))
	if cell.build_end > now:
		_timer_label = _label("")
		_button(func(t: int):
			var cost := colony.speedup_cost(q, r, t)
			return ["Przyspiesz (%d %s)" % [cost, crystals_word(cost)], "" if colony.crystals >= cost else "brak kryształów"],
			func(): _act(colony.speedup(q, r, _now())))
	elif cell.level < Buildings.MAX_LEVEL:
		var nl: int = cell.level + 1
		_button(func(t: int):
			return ["Ulepsz → %d: %d energii, %s" % [nl, Buildings.cost(cell.type, nl), format_secs(Buildings.build_secs(cell.type, nl))],
				_err_text(colony.can_upgrade(q, r, t))],
			func(): _act(colony.upgrade(q, r, _now())))

func _panel_build_menu(now: int) -> void:
	var q := selected.x
	var r := selected.y
	var first := colony.can_place("wall", q, r, now)
	if first == "not_adjacent":
		_label("Buduj tylko obok kolonii", 18, Color(1, 1, 1, 0.6))
		return
	_label("Buduj", 22, PLAYER)
	for t in Buildings.TYPES:
		if t == "core":
			continue
		var type: String = t
		_button(func(t: int):
			return ["%s: %d energii, %s" % [NAMES[type], Buildings.cost(type, 1), format_secs(Buildings.build_secs(type, 1))],
				_err_text(colony.can_place(type, q, r, t))],
			func(): _act(colony.place(type, q, r, _now())))
		_info(INFO[type])

static func _err_text(code: String) -> String:
	return {"": "", "no_energy": "brak energii", "no_builder": "brak budowniczych",
		"node_limit": "limit węzłów – ulepsz Rdzeń", "core_limit": "ulepsz Rdzeń", "max_level": "maks. poziom",
		"busy": "w budowie", "occupied": "zajęte", "not_adjacent": "za daleko", "out_of_grid": "poza mapą"}.get(code, code)

func _act(err: String) -> void:
	if err != "":
		_show_toast(_err_text(err))
	_save()
	_sync_in = SYNC_DEBOUNCE
	_refresh()

func _draw() -> void:
	var now := _now()
	# links between neighbouring buildings, under the cells
	for k in colony.cells:
		var a := Hex.parse(k)
		for nb in Hex.neighbors(a.x, a.y):
			var nk := Hex.key(nb.x, nb.y)
			if colony.cells.has(nk) and k < nk:
				draw_line(hex_to_px(a.x, a.y, origin), hex_to_px(nb.x, nb.y, origin), Color(PLAYER, 0.25), 2.0, true)
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var h := Vector2i(q, r)
			if Hex.distance(h, Vector2i.ZERO) > GRID_RADIUS:
				continue
			_draw_cell(h, now)

func _hex_points(c: Vector2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 7:
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	return pts

func _draw_cell(h: Vector2i, now: int) -> void:
	var c := hex_to_px(h.x, h.y, origin)
	var k := Hex.key(h.x, h.y)
	var pts := _hex_points(c, HEX_PX - 3)
	var is_sel := h == selected
	if colony.cells.has(k):
		var cell: Dictionary = colony.cells[k]
		var building: bool = cell.build_end > now
		draw_colored_polygon(pts, Color(PLAYER, 0.10 if building else 0.18))
		if building:
			for i in 6:
				draw_line(pts[i], pts[i].lerp(pts[i + 1], 0.5), PLAYER, 3.0 if is_sel else 2.0, true)
			if is_sel:
				draw_polyline(_hex_points(c, HEX_PX + 1), Color.WHITE, 1.5, true)
		else:
			draw_polyline(pts, PLAYER, 3.0 if is_sel else 2.0, true)
		_text(c + Vector2(0, -2), LETTERS[cell.type], 24, Color.WHITE)
		var sub := format_secs(cell.build_end - now) if building else "%d" % cell.level
		_text(c + Vector2(0, 20), sub, 14, Color(1, 1, 1, 0.75))
	else:
		var adjacent := false
		for nb in Hex.neighbors(h.x, h.y):
			if colony.cells.has(Hex.key(nb.x, nb.y)):
				adjacent = true
		var col := Color(PLAYER, 0.35) if adjacent else Color(0.5, 0.6, 0.8, 0.10)
		draw_polyline(pts, Color.WHITE if is_sel else col, 2.0 if is_sel else 1.0, true)
		if adjacent:
			_text(c + Vector2(0, 6), "+", 20, col)

func _text(center: Vector2, s: String, size: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, center - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
