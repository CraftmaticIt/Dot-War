class_name CampaignView
extends Control
## Campaign level select: 15 levels in 3 chapters, stars from the server profile merged with the
## local best (offline play). Level n opens once level n-1 has at least one star.

const LOCAL_PATH := "user://pve_local.json"
const CHAPTERS := ["Rozdział 1: Wieże", "Rozdział 2: Mury i pułapki", "Rozdział 3: Pancerz i odłamki"]

static func unlocked(stars: Dictionary, level_id: int) -> bool:
	return level_id <= 1 or int(stars.get(str(level_id - 1), 0)) >= 1

static func merge_stars(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for d in [a, b]:
		for k in d:
			out[str(k)] = maxi(int(out.get(str(k), 0)), int(d[k]))
	return out

static func load_local() -> Dictionary:
	if not FileAccess.file_exists(LOCAL_PATH):
		return {}
	var j := JSON.new()
	return j.data if j.parse(FileAccess.get_file_as_string(LOCAL_PATH)) == OK and typeof(j.data) == TYPE_DICTIONARY else {}

static func save_local(stars: Dictionary) -> void:
	var f := FileAccess.open(LOCAL_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(stars))

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.055, 0.078)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stars := load_local()
	var be := Backend.shared(get_tree().root)
	if be.is_configured():
		stars = merge_stars(stars, be.profile.get("pve", {}))
	var box := VBoxContainer.new()
	box.position = Vector2(140, 24)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Kampania"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#00E5FF"))
	box.add_child(title)
	var levels := PveDefs.levels()
	for ch in 3:
		var cl := Label.new()
		cl.text = CHAPTERS[ch]
		cl.add_theme_font_size_override("font_size", 18)
		cl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		box.add_child(cl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		for i in 5:
			var l: Dictionary = levels[ch * 5 + i]
			var id := int(l.id)
			var b := Button.new()
			b.custom_minimum_size = Vector2(188, 96)
			b.text = "%d. %s\n%s" % [id, String(l.name), BattleView.stars_text(int(stars.get(str(id), 0)))]
			b.disabled = not unlocked(stars, id)
			b.pressed.connect(func():
				PveView.pending = {"level": id}
				get_tree().change_scene_to_file("res://game/pve_view.tscn"))
			row.add_child(b)
	var back := Button.new()
	back.text = "Wróć"
	back.custom_minimum_size = Vector2(200, 52)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://game/main_menu.tscn"))
	box.add_child(back)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i != -1 and i + 1 < args.size():
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[i + 1])
		get_tree().quit()
