class_name PveView
extends Node2D
## PvE defense: place the level's buildings on free slots, press Start, watch the enemy swarm.
## Entered via `pending` = {level: id} (campaign) or {week: n, arena: true}.
## `-- --shot <png>` plays level 1 with its reference placement.

const NAMES := {"laser": "Laser", "pulse": "Puls", "wall": "Ściana", "trap": "Pułapka"}
const LETTERS := {"laser": "L", "pulse": "P", "wall": "Ś", "trap": "T"}
const MAX_FRAME_CATCHUP := 0.25

static var pending := {}

var level: Dictionary
var arena := false
var placement: Array = []
var match_: PveMatch = null
var backend: Backend = null
var _selected := ""
var _map: Node2D
var _views: Array[NodeView] = []
var _renderer: SwarmRenderer
var _overlay: Node2D
var _hud: Label
var _info: Label
var _palette: HBoxContainer
var _start: Button
var _end: VBoxContainer
var _acc := 0.0
var _shot := ""
var _elapsed := 0.0
var _font: Font
var percent := 50
var _percents: HBoxContainer

# --- pure helpers (unit-tested) ---

## Campaign: type -> pieces left. Arena: {"budget": points left}.
static func remaining(lvl: Dictionary, p: Array, is_arena: bool) -> Dictionary:
	if is_arena:
		var a: Dictionary = PveDefs.data().arena
		var left := int(a.budget)
		for e in p:
			left -= int(a.costs.get(e.type, 0))
		return {"budget": left}
	var out := {}
	for t in lvl.get("allowed", {}):
		out[t] = int(lvl.allowed[t])
	for e in p:
		out[e.type] = int(out.get(e.type, 0)) - 1
	return out

## Empty slot gets the type; the same type again removes it; another type replaces it.
static func toggle(p: Array, slot: int, type: String) -> Array:
	var out := []
	var had := ""
	for e in p:
		if int(e.slot) == slot:
			had = String(e.type)
		else:
			out.append(e)
	if had != type:
		var placed := false
		for i in out.size():
			if int(out[i].slot) > slot:
				out.insert(i, {"slot": slot, "type": type})
				placed = true
				break
		if not placed:
			out.append({"slot": slot, "type": type})
	return out

static func end_text(result: Dictionary, is_arena: bool, reward: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if is_arena:
		out.append("Koniec areny")
		out.append("Przetrwane fale: %d" % int(result.score))
		if reward.has("best"):
			out.append("Rekord tygodnia: %d" % int(reward.best))
	else:
		out.append("Zwycięstwo!" if int(result.stars) > 0 else "Porażka")
		out.append(BattleView.stars_text(int(result.stars)))
		if int(reward.get("crystals", 0)) > 0:
			out.append("+%d kryształów" % int(reward.crystals))
	if reward.get("offline", false):
		out.append("Nagroda wymaga połączenia")
	elif reward.has("error"):
		out.append({"locked": "Najpierw zalicz online poprzedni poziom", "bad_week": "Tydzień areny się zmienił – zagraj nową arenę"}
			.get(String(reward.error), "Serwer: %s" % String(reward.error)))
	return out

# --- scene ---

func _ready() -> void:
	_font = ThemeDB.fallback_font
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i != -1 and i + 1 < args.size():
		_shot = args[i + 1]
		pending = {"level": 1}
	if pending.get("arena", false):
		arena = true
		level = PveMatch.arena_level(int(pending.week))
	else:
		level = PveDefs.level(int(pending.get("level", 1)))
	pending = {}
	if level.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://game/main_menu.tscn")
		return
	backend = Backend.shared(get_tree().root)
	_build_ui()
	_rebuild_map()
	if _shot != "":
		placement = [{"slot": 2, "type": "laser"}]
		_rebuild_map()
		_on_start()

func _sfx(sound: String) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s and sound != "":
		s.play(sound)

func _world() -> SimWorld:
	return match_.world if match_ != null else PveLevel.build_world(level, placement, 1)

func _rebuild_map() -> void:
	if _map:
		_map.queue_free()
	_views.clear()
	var w := _world()
	var g := w.graph
	var ids := g.node_ids()
	var r := Rect2i(g.node(ids[0]).x, g.node(ids[0]).y, 0, 0)
	for id in ids:
		r = r.expand(Vector2i(g.node(id).x, g.node(id).y))
	_map = Node2D.new()
	_map.transform = BattleView.fit_transform(r, get_viewport_rect().size - Vector2(0, 160), 70.0)
	_map.position += Vector2(0, 60)
	add_child(_map)
	var edges := Node2D.new()
	edges.draw.connect(func():
		for a in g.node_ids():
			for b in g.neighbors(a):
				if a < b:
					edges.draw_line(SwarmRenderer.to_px(Vector2i(g.node(a).x, g.node(a).y)),
						SwarmRenderer.to_px(Vector2i(g.node(b).x, g.node(b).y)), Color(0.4, 0.5, 0.7, 0.18), 2.0, true))
	_map.add_child(edges)
	for id in ids:
		var v := NodeView.new()
		v.node_id = id
		v.position = SwarmRenderer.to_px(Vector2i(g.node(id).x, g.node(id).y))
		_map.add_child(v)
		v.refresh(g.node(id))
		_views.append(v)
	_renderer = SwarmRenderer.new()
	_map.add_child(_renderer)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	_map.add_child(_overlay)
	if match_ != null:
		var input := InputSend.new()   # drag from your node to another: send dots (like an attack)
		input.world = match_.world
		input.views = _views
		input.send_requested.connect(func(from: int, to: int):
			match_.send(from, to, percent)
			_sfx("send"))
		_map.add_child(input)

## Slot markers: "+" on a free slot during setup, the building letter on a placed one;
## "C" on the core and "!" on enemy spawns.
func _draw_overlay() -> void:
	var types := {}
	for e in placement:
		types[int(e.slot)] = String(e.type)
	for n in level.nodes:
		var p := SwarmRenderer.to_px(Vector2i(int(n.x), int(n.y))) + Vector2(-6, -40)
		var s := ""
		match String(n.role):
			"core":
				s = "C"
			"spawn":
				s = "!"
			_:
				s = LETTERS.get(types.get(int(n.id), ""), "+" if match_ == null else "")
		if s != "":
			_overlay.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#B6FF00"))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 22)
	layer.add_child(_hud)
	_palette = HBoxContainer.new()
	_palette.position = Vector2(16, 600)
	layer.add_child(_palette)
	_info = Label.new()
	_info.position = Vector2(16, 660)
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	layer.add_child(_info)
	_start = Button.new()
	_start.text = "Start"
	_start.custom_minimum_size = Vector2(160, 56)
	_start.position = Vector2(1100, 600)
	_start.pressed.connect(_on_start)
	layer.add_child(_start)
	var back := Button.new()
	back.text = "Wróć"
	back.custom_minimum_size = Vector2(120, 44)
	back.position = Vector2(1140, 12)
	back.pressed.connect(_go_back)
	layer.add_child(back)
	_percents = HBoxContainer.new()
	_percents.position = Vector2(16, 600)
	_percents.visible = false
	var group := ButtonGroup.new()
	for p in BattleView.PERCENTS:
		var b := Button.new()
		b.text = "%d%%" % p
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = p == percent
		b.custom_minimum_size = Vector2(72, 44)
		b.pressed.connect(func(): percent = p)
		_percents.add_child(b)
	layer.add_child(_percents)
	_end = VBoxContainer.new()
	_end.position = Vector2(440, 200)
	_end.custom_minimum_size = Vector2(400, 0)
	_end.visible = false
	layer.add_child(_end)
	_refresh_setup()

func _types() -> Array:
	return PveDefs.data().arena.costs.keys() if arena else level.get("allowed", {}).keys()

func _refresh_setup() -> void:
	if arena:
		var a: Dictionary = PveDefs.data().arena
		_hud.text = "Arena · tydzień %d" % int(level.week)
		_info.text = "Budżet: %d / %d pkt. Wybierz budynek, potem stuknij wolne pole „+”." % [
			int(remaining(level, placement, true).budget), int(a.budget)]
	else:
		_hud.text = "Poziom %d: %s" % [int(level.id), String(level.name)]
		_info.text = "Wybierz budynek, potem stuknij wolne pole „+”. Ponowne stuknięcie zdejmuje budynek."
	for c in _palette.get_children():
		c.queue_free()
	var left := remaining(level, placement, arena)
	for t in _types():
		var b := Button.new()
		var cost: int = int(PveDefs.data().arena.costs.get(t, 0))
		b.text = ("%s (%d pkt)" % [NAMES.get(t, t), cost]) if arena else ("%s ×%d" % [NAMES.get(t, t), int(left.get(t, 0))])
		if _selected == t:
			b.text += " ◉"
		b.custom_minimum_size = Vector2(150, 48)
		b.pressed.connect(func():
			_selected = "" if _selected == t else t
			_refresh_setup())
		_palette.add_child(b)
	if _overlay:
		_overlay.queue_redraw()

func _unhandled_input(e: InputEvent) -> void:
	if match_ != null or _map == null:
		return
	# Mouse only: on phones Godot also emits a mouse click for every touch, so handling both
	# would place and remove the building in one tap (same as colony_view).
	var tap: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed
	if not tap:
		return
	var p: Vector2 = _map.get_global_transform().affine_inverse() * e.position
	for v in _views:
		if v.position.distance_to(p) <= NodeView.RADIUS + 12:
			_tap_node(v.node_id)
			return

func _tap_node(id: int) -> void:
	var role := ""
	for n in level.nodes:
		if int(n.id) == id:
			role = String(n.role)
	if role != "slot":
		return
	var current := ""
	for e in placement:
		if int(e.slot) == id:
			current = String(e.type)
	var t := _selected if _selected != "" else current
	if t == "":
		return
	var next := toggle(placement, id, t)
	if PveLevel.validate(level, next, arena) != "":
		_sfx("error")
		return
	placement = next
	_sfx("build")
	_rebuild_map()
	_refresh_setup()

func _on_start() -> void:
	if match_ != null:
		return
	match_ = PveMatch.new(level, placement, 1)
	_palette.visible = false
	_start.visible = false
	_percents.visible = true
	_info.text = "Przeciągnij od swojego węzła do innego, żeby wysłać kropki (nie do węzłów startowych wroga)."
	_rebuild_map()

func _process(delta: float) -> void:
	if match_ == null:
		return
	if not match_.over:
		_acc = minf(_acc + delta, MAX_FRAME_CATCHUP)
		var dt := 1.0 / SimWorld.TICK_HZ
		while _acc >= dt and not match_.over:
			_acc -= dt
			match_.step()
			for ev in match_.world.events:
				_sfx({"group_destroyed": "hit", "node_captured": "capture", "trap_triggered": "hit", "splash": "error"}.get(ev.type, ""))
		_renderer.sync(match_.world, _acc / dt)
		for v in _views:
			v.refresh(match_.world.graph.node(v.node_id))
		var r := match_.result()
		_hud.text = "%s    fale: %d / %d" % [BattleView.format_clock(match_.world.tick), int(r.waves_started),
			level.waves.size()]
		if match_.over:
			_finish()
	if _shot != "":
		_elapsed += delta
		if _elapsed >= 10.0:
			var path := _shot
			_shot = ""
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()

func _finish() -> void:
	var r := match_.result()
	_sfx("win" if (arena and int(r.score) > 0) or int(r.stars) > 0 else "lose")
	if not arena:
		var local := CampaignView.load_local()
		CampaignView.save_local(CampaignView.merge_stars(local, {str(int(level.id)): int(r.stars)}))
	_end.visible = true
	var wait := Label.new()
	wait.text = "Weryfikacja wyniku…"
	_end.add_child(wait)
	var reward := {"offline": true}
	if _shot == "" and backend != null and backend.is_configured():
		var body := {"placement": placement, "commands": match_.commands}
		if arena:
			body["week"] = int(level.week)
		else:
			body["level"] = int(level.id)
		reward = await backend.finish_pve(body)
	wait.queue_free()
	for t in end_text(r, arena, reward):
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 32 if t.contains("★") or t.contains("☆") else 22)
		_end.add_child(l)
	if arena and not reward.get("offline", false):
		var rk := await backend.pve_ranking()
		for row in rk.get("top", []).slice(0, 5):
			var l := Label.new()
			l.text = "%s — %d" % [String(row.name), int(row.score)]
			_end.add_child(l)
		if typeof(rk.get("me")) == TYPE_DICTIONARY:
			var me := Label.new()
			me.text = "Twoje miejsce: %d" % int(rk.me.rank)
			me.add_theme_color_override("font_color", Color("#B6FF00"))
			_end.add_child(me)
	var back := Button.new()
	back.text = "Wróć"
	back.custom_minimum_size = Vector2(400, 56)
	back.pressed.connect(_go_back)
	_end.add_child(back)

func _go_back() -> void:
	get_tree().change_scene_to_file("res://game/main_menu.tscn" if arena else "res://game/campaign_view.tscn")
