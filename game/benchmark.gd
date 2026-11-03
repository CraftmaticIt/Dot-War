extends Node2D
## Benchmark: 40 groups x 50 dots crossing the screen.
## Headless:  godot --headless --path . res://game/benchmark.tscn -- --sim-only
##   prints sim_step_ms, exit 1 if >= 2 ms.
## Rendered:  godot --path . res://game/benchmark.tscn -- --benchmark [--shot out.png]
##   runs 10 s, prints avg_fps / p95_frame_ms, exit 1 if avg_fps < 60.

const GROUPS := 40
const DOTS := 50
const SIM_TICKS := 150  # all groups still in flight (crossing takes 200 ticks)
const MAX_STEP_MS := 2.0
const MIN_FPS := 60.0
const RUN_SECONDS := 10.0

var world: SimWorld
var renderer: SwarmRenderer
var _frames: PackedFloat32Array = []
var _elapsed := 0.0
var _acc := 0.0
var _shot := ""

static func build_world() -> SimWorld:
	var g := SimGraph.new()
	var u := Fx.ONE
	for i in GROUPS:
		var y := u + (i % 20) * 800
		var x0 := 1 * u if i < 20 else 3 * u
		g.add_node(i * 2 + 1, x0, y, 1, DOTS * 2, 0)
		g.add_node(i * 2 + 2, 31 * u, y, 1, 0, 0)
		g.link(i * 2 + 1, i * 2 + 2)
	g.add_node(999, 16 * u, 9 * u, 2, 0, 0, "pulse")
	var w := SimWorld.new(g, 1)
	for i in GROUPS:
		w.queue({"tick": 0, "type": "send", "owner": 1, "from": i * 2 + 1, "to": i * 2 + 2, "percent": 50})
	return w

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i != -1 and i + 1 < args.size():
		_shot = args[i + 1]
	world = build_world()
	if "--sim-only" in args:
		_run_sim_only()
		return
	renderer = SwarmRenderer.new()
	add_child(renderer)

func _run_sim_only() -> void:
	world.step()  # spawn
	var t0 := Time.get_ticks_usec()
	for i in SIM_TICKS:
		world.step()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / SIM_TICKS
	var dots := 0
	for g in world.groups:
		dots += g.count
	print("sim_step_ms=%.3f groups=%d dots=%d" % [ms, world.groups.size(), dots])
	get_tree().quit(0 if ms < MAX_STEP_MS else 1)

func _process(delta: float) -> void:
	if renderer == null:
		return
	_acc += delta
	var dt := 1.0 / SimWorld.TICK_HZ
	while _acc >= dt:
		_acc -= dt
		world.step()
		if world.groups.is_empty():
			world = build_world()
	renderer.sync(world, _acc / dt)
	_elapsed += delta
	if _elapsed > 1.0:
		_frames.append(delta * 1000.0)
	if _shot != "" and _elapsed >= 3.0:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot)
		_shot = ""
	if _elapsed >= RUN_SECONDS + 1.0:
		_finish()

func _finish() -> void:
	set_process(false)
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	var avg_fps := 1000.0 / (total / _frames.size())
	var p95: float = sorted[int(sorted.size() * 0.95)]
	var line := "avg_fps=%.1f p95_frame_ms=%.2f frames=%d" % [avg_fps, p95, _frames.size()]
	print(line)
	if "--benchmark" in OS.get_cmdline_user_args():
		get_tree().quit(0 if avg_fps >= MIN_FPS else 1)
		return
	# On a phone: show the result, tap to go back to the prototype.
	var label := Label.new()
	label.text = "%s\n%s\n(tap to return)" % [line, "PASS" if avg_fps >= MIN_FPS else "FAIL < 60 FPS"]
	label.add_theme_font_size_override("font_size", 28)
	label.position = Vector2(40, 300)
	add_child(label)
	_done = true

var _done := false

func _unhandled_input(e: InputEvent) -> void:
	if _done and (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed:
		get_tree().change_scene_to_file("res://game/prototype.tscn")
