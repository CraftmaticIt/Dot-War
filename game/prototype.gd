extends Node2D
## Playable stage-1 prototype: player (owner 1) vs SimpleBot (owner 2) on a 12-node map.
## User args: `-- --shot <png> [--seconds N]` runs bot-vs-bot, saves a screenshot and quits.

const BOT_EVERY_TICKS := 40   # 3 s
const PERCENTS := [25, 50, 75, 100]

var world: SimWorld
var renderer: SwarmRenderer
var views: Array[NodeView] = []
var input: InputSend
var percent := 50
var _acc := 0.0
var _status: Label
var _shot_path := ""
var _shot_seconds := 8.0
var _elapsed := 0.0

func _ready() -> void:
	_parse_args()
	world = SimWorld.new(_build_map(), 1)
	renderer = SwarmRenderer.new()
	for id in world.graph.node_ids():
		var v := NodeView.new()
		v.node_id = id
		var n := world.graph.node(id)
		v.position = SwarmRenderer.to_px(Vector2i(n.x, n.y))
		add_child(v)
		v.refresh(n)
		views.append(v)
	add_child(renderer)
	input = InputSend.new()
	input.world = world
	input.views = views
	input.send_requested.connect(_on_send)
	add_child(input)
	_build_ui()

func _draw() -> void:
	var g := world.graph
	for a in g.node_ids():
		for b in g.neighbors(a):
			if a < b:
				var pa := SwarmRenderer.to_px(Vector2i(g.node(a).x, g.node(a).y))
				var pb := SwarmRenderer.to_px(Vector2i(g.node(b).x, g.node(b).y))
				draw_line(pa, pb, Color(0.4, 0.5, 0.7, 0.18), 2.0, true)

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
		elif args[i] == "--seconds" and i + 1 < args.size():
			_shot_seconds = float(args[i + 1])

## Map in sim units (Fx). Screen 1280x720 = 32x18 units.
static func _build_map() -> SimGraph:
	var g := SimGraph.new()
	var u := Fx.ONE
	g.add_node(1, 3 * u, 9 * u, 1, 20, 2)
	g.add_node(2, 7 * u, 4 * u, 0, 6, 1)
	g.add_node(3, 7 * u, 14 * u, 0, 6, 1)
	g.add_node(4, 11 * u, 9 * u, 0, 10, 1, "laser")
	g.add_node(5, 14 * u, 3 * u, 0, 8, 1)
	g.add_node(6, 14 * u, 15 * u, 0, 8, 1)
	g.add_node(7, 18 * u, 3 * u, 0, 8, 1)
	g.add_node(8, 18 * u, 15 * u, 0, 8, 1)
	g.add_node(9, 21 * u, 9 * u, 0, 10, 1, "pulse")
	g.add_node(10, 25 * u, 4 * u, 0, 6, 1)
	g.add_node(11, 25 * u, 14 * u, 0, 6, 1)
	g.add_node(12, 29 * u, 9 * u, 2, 20, 2)
	for l in [[1, 2], [1, 3], [1, 4], [2, 4], [3, 4], [2, 5], [3, 6], [4, 5], [4, 6],
			[5, 7], [6, 8], [7, 9], [8, 9], [9, 10], [9, 11], [7, 10], [8, 11], [10, 12], [11, 12], [9, 12]]:
		g.link(l[0], l[1])
	return g

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
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
	var bench := Button.new()
	bench.text = "Benchmark"
	bench.custom_minimum_size = Vector2(120, 44)
	bench.position = Vector2(1144, 660)
	bench.pressed.connect(func(): get_tree().change_scene_to_file("res://game/benchmark.tscn"))
	layer.add_child(bench)
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_font_size_override("font_size", 22)
	layer.add_child(_status)

func _on_send(from: int, to: int) -> void:
	world.queue({"tick": world.tick, "type": "send", "owner": 1, "from": from, "to": to, "percent": percent})

func _process(delta: float) -> void:
	_acc += delta
	var dt := 1.0 / SimWorld.TICK_HZ
	while _acc >= dt:
		_acc -= dt
		if world.tick % BOT_EVERY_TICKS == BOT_EVERY_TICKS / 2:
			_bot(2)
			if _shot_path != "":
				_bot(1)
		world.step()
	renderer.sync(world, _acc / dt)
	for v in views:
		v.refresh(world.graph.node(v.node_id))
	_update_status()
	if _shot_path != "":
		_elapsed += delta
		if _elapsed >= _shot_seconds:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
			_shot_path = ""

func _bot(owner: int) -> void:
	var cmd := SimpleBot.decide(world, owner)
	if not cmd.is_empty():
		world.queue(cmd)

func _update_status() -> void:
	var owned := {1: 0, 2: 0}
	for id in world.graph.node_ids():
		var o: int = world.graph.node(id).owner
		if owned.has(o):
			owned[o] += 1
	var dots := 0
	for g in world.groups:
		dots += g.count
	var msg := "You %d  |  Bot %d  |  dots in flight %d" % [owned[1], owned[2], dots]
	if owned[2] == 0:
		msg = "VICTORY"
	elif owned[1] == 0:
		msg = "DEFEAT"
	_status.text = msg
