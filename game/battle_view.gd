class_name BattleView
extends Node2D
## Attack screen: player (owner 1) vs a bot colony snapshot (owner 2).
## Entered from the colony screen via `pending`; `-- --shot <png>` runs a bot-vs-bot demo.

const MAX_ZOOM := 1.5
const PERCENTS := [25, 50, 75, 100]
const BOT_EVERY_TICKS := 40

## Handoff from the colony screen: {"colony": ColonyState, "dots": int, "seed": int}
static var pending := {}

var battle: BattleMatch
var colony: ColonyState
var renderer: SwarmRenderer
var views: Array[NodeView] = []
var map: Node2D
var percent := 50
var save_enabled := true
var _applied := false
## Online attack: server attack id, recorded commands and surrender tick for verification.
var attack_id := ""
var commands: Array = []
var surrender_tick := -1
var _loadout: Array = []
var _armed := ""
var _boost_bar: HBoxContainer = null
var backend: Backend = null
var _give_up: Button = null
var _rewards := {}
var _save_failed := false
const MAX_FRAME_CATCHUP := 0.25  # never fast-forward more than this after a long frame/resume
var _acc := 0.0
var _hud: Label
var _end: VBoxContainer
var _shot := ""
var _elapsed := 0.0

# --- pure helpers (unit-tested) ---

## Transform from SwarmRenderer.to_px space to the screen, fitting `bounds` (Fx).
static func fit_transform(bounds: Rect2i, screen: Vector2, margin: float) -> Transform2D:
	var a := SwarmRenderer.to_px(bounds.position)
	var b := SwarmRenderer.to_px(bounds.end)
	var size := (b - a).abs()
	var avail := screen - Vector2(margin, margin) * 2.0
	var s := MAX_ZOOM
	if size.x > 0.0:
		s = minf(s, avail.x / size.x)
	if size.y > 0.0:
		s = minf(s, avail.y / size.y)
	var center := (a + b) / 2.0
	return Transform2D(0.0, Vector2(s, s), 0.0, screen / 2.0 - center * s)

static func format_clock(ticks: int) -> String:
	var s := ticks / SimWorld.TICK_HZ
	return "%d:%02d" % [s / 60, s % 60]

static func stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(3 - n)

# --- scene ---

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	var dots := 0
	var seed := 1
	var trophies := 300
	if i != -1 and i + 1 < args.size():
		_shot = args[i + 1]
		dots = 60
		seed = 7
		_loadout = ["rage", "shield", "emp"]
	elif not pending.is_empty():
		colony = pending.colony
		dots = pending.dots
		seed = pending.seed
		trophies = colony.trophies
		if pending.has("snapshot"):
			attack_id = String(pending.get("attack_id", ""))
			_loadout = pending.get("loadout", [])
			var snap := ColonyState.from_dict(pending.snapshot)
			if snap != null:
				_start(snap, int(pending.loot_pool), dots, seed)
				pending = {}
				return
		pending = {}
	else:
		get_tree().change_scene_to_file.call_deferred("res://game/colony_view.tscn")
		return
	var bot: Dictionary = BotColony.generate(trophies, seed)
	_start(bot.colony, bot.loot_pool, dots, seed)

func _start(defender: ColonyState, loot_pool: int, dots: int, seed: int) -> void:
	var core_id := 1
	var ids := defender.snapshot_ids()
	for id in ids:
		if ids[id] == Vector2i.ZERO:
			core_id = id
	var world := AttackSetup.build(defender.to_sim_graph(AttackSetup.DEFENDER), dots, seed)
	battle = BattleMatch.new(world, core_id, loot_pool, _loadout)
	_build_scene()
	_build_ui()

## Every player command goes through here so the server can replay the battle.
func send_cmd(from: int, to: int, pct: int) -> void:
	if battle.over:
		return
	var g := battle.world.graph
	if g.has_node(from) and g.node(from).garrison * pct / 100 == 0:
		pct = 100  # a small node would send nothing at this %: send what it has
	commands.append({"tick": battle.world.tick, "from": from, "to": to, "percent": pct})
	battle.send(from, to, pct)
	_sfx("send")

var _confirm_left := 0.0

## Two taps within 3 s: the first only asks ("Na pewno?").
func request_surrender() -> bool:
	if _confirm_left <= 0.0:
		_confirm_left = 3.0
		if _give_up:
			_give_up.text = "Na pewno?"
		return false
	surrender_now()
	return true

## Booster flow: tap a booster button (arm), then tap the target node.
func arm_booster(b: String) -> void:
	_armed = b if battle.boosts_left.has(b) else ""
	_refresh_boost_bar()

func on_node_tapped(id: int) -> void:
	if _armed == "" or battle.over:
		return
	var b := _armed
	_armed = ""
	commands.append({"tick": battle.world.tick, "type": "boost", "booster": b, "node": id})
	battle.boost(b, id)
	_refresh_boost_bar()

func _refresh_boost_bar() -> void:
	if _boost_bar == null:
		return
	for c in _boost_bar.get_children():
		_boost_bar.remove_child(c)
		c.queue_free()
	_boost_bar.visible = not battle.boosts_left.is_empty()
	var seen := {}
	for b in battle.boosts_left:
		if seen.has(b):
			continue
		seen[b] = true
		var btn := Button.new()
		btn.text = "%s ×%d%s" % [MetaDefs.booster_name(b), battle.boosts_left.count(b), " ◉" if _armed == b else ""]
		btn.custom_minimum_size = Vector2(130, 44)
		btn.pressed.connect(func(): arm_booster(b))
		_boost_bar.add_child(btn)

func surrender_now() -> void:
	if not battle.over:
		surrender_tick = battle.world.tick
		battle.surrender()

func _bounds() -> Rect2i:
	var g := battle.world.graph
	var ids := g.node_ids()
	var r := Rect2i(g.node(ids[0]).x, g.node(ids[0]).y, 0, 0)
	for id in ids:
		r = r.expand(Vector2i(g.node(id).x, g.node(id).y))
	return r

func _build_scene() -> void:
	map = Node2D.new()
	map.transform = fit_transform(_bounds(), get_viewport_rect().size - Vector2(0, 80), 60.0)
	map.position += Vector2(0, 50)
	add_child(map)
	var edges := Node2D.new()
	edges.draw.connect(func():
		var g := battle.world.graph
		for a in g.node_ids():
			for b in g.neighbors(a):
				if a < b:
					edges.draw_line(SwarmRenderer.to_px(Vector2i(g.node(a).x, g.node(a).y)),
						SwarmRenderer.to_px(Vector2i(g.node(b).x, g.node(b).y)), Color(0.4, 0.5, 0.7, 0.18), 2.0, true))
	map.add_child(edges)
	for id in battle.world.graph.node_ids():
		var v := NodeView.new()
		v.node_id = id
		var n := battle.world.graph.node(id)
		v.position = SwarmRenderer.to_px(Vector2i(n.x, n.y))
		map.add_child(v)
		v.refresh(_visible_node(n))
		views.append(v)
	renderer = SwarmRenderer.new()
	map.add_child(renderer)
	var input := InputSend.new()
	input.world = battle.world
	input.views = views
	input.send_requested.connect(func(from: int, to: int): send_cmd(from, to, percent))
	input.node_tapped.connect(on_node_tapped)
	map.add_child(input)

## The attacker never sees traps: strip trap info before drawing.
func _visible_node(n: Dictionary) -> Dictionary:
	var d := n.duplicate()
	d.erase("trap")
	return d

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 24)
	layer.add_child(_hud)
	var box := HBoxContainer.new()
	box.position = Vector2(16, 660)
	layer.add_child(box)
	var group := ButtonGroup.new()
	for p in PERCENTS:
		var b := Button.new()
		b.text = "%d%%" % p
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = p == percent
		b.custom_minimum_size = Vector2(72, 44)
		b.pressed.connect(func(): percent = p)
		box.add_child(b)
	var give_up := Button.new()
	give_up.text = "Poddaj się"
	give_up.custom_minimum_size = Vector2(140, 44)
	give_up.position = Vector2(1124, 660)
	give_up.pressed.connect(request_surrender)
	_give_up = give_up
	layer.add_child(give_up)
	_boost_bar = HBoxContainer.new()
	_boost_bar.position = Vector2(420, 660)
	layer.add_child(_boost_bar)
	_refresh_boost_bar()
	_end = VBoxContainer.new()
	_end.position = Vector2(440, 220)
	_end.custom_minimum_size = Vector2(400, 0)
	_end.visible = false
	layer.add_child(_end)

func _process(delta: float) -> void:
	if battle == null:
		return
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0 and _give_up:
			_give_up.text = "Poddaj się"
	if not battle.over:
		_acc = minf(_acc + delta, MAX_FRAME_CATCHUP)
		var dt := 1.0 / SimWorld.TICK_HZ
		while _acc >= dt and not battle.over:
			_acc -= dt
			if _shot != "" and battle.world.tick % BOT_EVERY_TICKS == 0:
				var cmd := SimpleBot.decide(battle.world, AttackSetup.ATTACKER)
				if not cmd.is_empty():
					send_cmd(cmd.from, cmd.to, cmd.percent)
			battle.step()
			for e in battle.world.events:
				_sfx(EVENT_SOUNDS.get(e.type, ""))
		renderer.sync(battle.world, _acc / dt)
		for v in views:
			v.refresh(_visible_node(battle.world.graph.node(v.node_id)))
		var p := battle.progress()
		_hud.text = "%s    %s    zniszczono %d%%" % [format_clock(p.ticks_left), stars_text(p.stars), p.destroyed_pct]
	if battle.over and not _end.visible:
		_show_end()  # also after surrender(), which ends the match outside the tick loop
	if _shot != "":
		_elapsed += delta
		if _elapsed >= 15.0:
			var path := _shot
			_shot = ""
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()

## Leaving the battle (back button, app paused/closed) = surrender; the result is
## applied and saved immediately so it cannot be lost or dodged.
func _notification(what: int) -> void:
	if battle == null:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		surrender_now()
		if not _applied:
			_show_end()

## Applies the result once. Online: the server replays the commands and its result wins.
func _apply_once(r: Dictionary) -> Dictionary:
	if _applied or colony == null:
		_applied = true
		return r
	_applied = true
	if attack_id != "":
		if backend == null:
			backend = Backend.shared(get_tree().root)
		var sr := await backend.finish_attack(attack_id, commands, surrender_tick)
		if typeof(sr.get("rewards")) == TYPE_DICTIONARY:
			_rewards = sr.rewards
		if typeof(sr.get("result")) == TYPE_DICTIONARY:
			r = sr.result
		elif sr.has("error"):
			# The server refused (e.g. attack expired): nothing is credited locally either.
			r = {"stars": 0, "destroyed_pct": int(r.get("destroyed_pct", 0)), "loot": 0, "trophies": 0}
	colony.apply_result(r)
	if backend != null and backend.profile.has("crystals"):
		colony.crystals = int(backend.profile.crystals)  # rewards (quests, chests) are server-side
	if save_enabled and SaveStore.save(colony) != OK:
		push_warning("BattleView: save failed")
		_save_failed = true
	return r

const EVENT_SOUNDS := {"group_destroyed": "hit", "node_captured": "capture", "boost_applied": "boost",
	"trap_triggered": "hit"}

## Sounds go through the Sfx autoload when it is running (it is absent in headless tests).
func _sfx(sound: String) -> void:
	var s := get_node_or_null("/root/Sfx")
	if s and sound != "":
		s.play(sound)

func _show_end() -> void:
	if _end.visible:
		return
	renderer.sync(battle.world, 1.0)
	_end.visible = true
	var wait := Label.new()
	wait.text = "Weryfikacja wyniku…"
	_end.add_child(wait)
	var r: Dictionary = await _apply_once(battle.result())
	wait.queue_free()
	_sfx("win" if r.stars > 0 else "lose")
	for q in _rewards.get("quests", []):
		var ql := Label.new()
		ql.text = "Zadanie ukończone: %s" % q
		ql.add_theme_color_override("font_color", Color("#B6FF00"))
		_end.add_child(ql)
	if typeof(_rewards.get("chest")) == TYPE_DICTIONARY:
		var ch: Dictionary = _rewards.chest
		var parts := PackedStringArray()
		for b in ch.get("boosters", {}):
			parts.append("%s ×%d" % [MetaDefs.booster_name(b), int(ch.boosters[b])])
		var cl := Label.new()
		cl.text = "Skrzynka: %s, +%d kryształów" % [", ".join(parts), int(ch.get("crystals", 0))]
		cl.add_theme_color_override("font_color", Color("#FFB300"))
		_end.add_child(cl)
	if _save_failed:
		var warn := Label.new()
		warn.text = "Nie udało się zapisać gry!"
		warn.add_theme_color_override("font_color", Color("#FF2E88"))
		_end.add_child(warn)
	for t in ["Zwycięstwo!" if r.stars > 0 else "Porażka", stars_text(r.stars),
			"Zniszczono %d%%" % r.destroyed_pct, "Łup: +%d energii" % r.loot, "Trofea: %+d" % r.trophies]:
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 32 if t == stars_text(r.stars) else 24)
		_end.add_child(l)
	var back := Button.new()
	back.text = "Wróć do kolonii"
	back.custom_minimum_size = Vector2(400, 56)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://game/colony_view.tscn"))
	_end.add_child(back)
