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
	elif not pending.is_empty():
		colony = pending.colony
		dots = pending.dots
		seed = pending.seed
		trophies = colony.trophies
		pending = {}
	else:
		get_tree().change_scene_to_file.call_deferred("res://game/colony_view.tscn")
		return
	var bot: Dictionary = BotColony.generate(trophies, seed)
	var bc: ColonyState = bot.colony
	var core_id := 1
	var ids := bc.snapshot_ids()
	for id in ids:
		if ids[id] == Vector2i.ZERO:
			core_id = id
	var world := AttackSetup.build(bc.to_sim_graph(AttackSetup.DEFENDER), dots, seed)
	battle = BattleMatch.new(world, core_id, bot.loot_pool)
	_build_scene()
	_build_ui()

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
	input.send_requested.connect(func(from: int, to: int): battle.send(from, to, percent))
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
	give_up.pressed.connect(func(): battle.surrender())
	layer.add_child(give_up)
	_end = VBoxContainer.new()
	_end.position = Vector2(440, 220)
	_end.custom_minimum_size = Vector2(400, 0)
	_end.visible = false
	layer.add_child(_end)

func _process(delta: float) -> void:
	if battle == null:
		return
	if not battle.over:
		_acc += delta
		var dt := 1.0 / SimWorld.TICK_HZ
		while _acc >= dt and not battle.over:
			_acc -= dt
			if _shot != "" and battle.world.tick % BOT_EVERY_TICKS == 0:
				var cmd := SimpleBot.decide(battle.world, AttackSetup.ATTACKER)
				if not cmd.is_empty():
					battle.send(cmd.from, cmd.to, cmd.percent)
			battle.step()
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
		if not battle.over:
			battle.surrender()
		if not _applied:
			_show_end()

func _apply_once(r: Dictionary) -> void:
	if _applied or colony == null:
		_applied = true
		return
	_applied = true
	colony.apply_result(r)
	if save_enabled and SaveStore.save(colony) != OK:
		push_warning("BattleView: save failed")

func _show_end() -> void:
	if _end.visible:
		return
	renderer.sync(battle.world, 1.0)
	var r := battle.result()
	_apply_once(r)
	_end.visible = true
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
