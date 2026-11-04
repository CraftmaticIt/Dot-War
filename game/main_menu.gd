extends Control
## Start screen: Graj / Jak grać / Ustawienia.

const HELP := [
	["Kolonia", "Stuknij pole z „+” obok kolonii i wybierz budynek. Kopalnia daje energię, Generator – kropki. Dwóch budowniczych buduje naraz; kryształami przyspieszysz budowę."],
	["Limit węzłów", "Rdzeń wyznacza, ile budynków zmieścisz (licznik „Węzły” u góry). Ulepsz Rdzeń, żeby mieć miejsce na więcej."],
	["Atak", "„Atak” szuka przeciwnika. Przeciągnij od swojego węzła do celu, żeby wysłać rój. Wieże strzelają do Twoich kropek, Ściany mają duży garnizon, Pułapki są ukryte."],
	["Gwiazdki", "★ za 50% zniszczonych węzłów, ★ za Rdzeń, ★ za 100%. Gwiazdki dają łup energii i trofea; porażka zabiera trofea."],
	["Boostery", "Przed atakiem wybierz do 3 boosterów (Meta → Boostery). W walce stuknij booster, potem węzeł: Szał przyspiesza, Tarcza chroni, EMP wyłącza wieże, Rozszczepienie podwaja grupę."],
	["Meta", "Zadania dzienne, sklep za kryształy i liga. Sezon trwa 14 dni – nagroda zależy od ligi."],
	["Kampania", "15 łamigłówek obrony: rozstaw podane budynki na polach „+”, naciśnij Start i patrz. ★ Rdzeń przetrwał, ★★ straciłeś najwyżej 1 węzeł, ★★★ nic. Za każdą nową gwiazdkę 5 kryształów."],
	["Arena tygodnia", "Co tydzień nowe fale bez końca. Masz 12 punktów na budynki; wynik to liczba przetrwanych fal. Najlepsze 10% tygodnia dostaje nagrodę."],
	["Typy kropek", "Szybkie (×1,5 prędkości), pancerne (połowa obrażeń od wież), rozpryskowe (gdy zginą, zabierają 5 kropek pobliskim węzłom)."],
]

var _box: VBoxContainer

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.055, 0.078)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_box = VBoxContainer.new()
	_box.position = Vector2(390, 60)
	_box.custom_minimum_size = Vector2(500, 0)
	_box.add_theme_constant_override("separation", 14)
	add_child(_box)
	_main()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i != -1 and i + 1 < args.size():
		if args.has("--help"):
			_help()
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[i + 1])
		get_tree().quit()

func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()

func _title(text: String, size: int, color := Color("#00E5FF")) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_box.add_child(l)
	return l

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(500, 64)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b

func _main() -> void:
	_clear()
	_title("DOT WAR", 72)
	_title("Rój neonowych kropek. Buduj, broń się, atakuj.", 20, Color(1, 1, 1, 0.6))
	_button("Graj", func(): get_tree().change_scene_to_file("res://game/colony_view.tscn"))
	_button("Kampania", func(): get_tree().change_scene_to_file("res://game/campaign_view.tscn"))
	_button("Arena tygodnia", func():
		PveView.pending = {"arena": true, "week": PveMatch.week_index(int(Time.get_unix_time_from_system()))}
		get_tree().change_scene_to_file("res://game/pve_view.tscn"))
	_button("Jak grać", _help)
	_button("Ustawienia", _settings)

func _help() -> void:
	_clear()
	_box.position = Vector2(320, 12)
	_box.add_theme_constant_override("separation", 6)
	_title("Jak grać", 36)
	for h in HELP:
		var l := Label.new()
		l.text = "%s — %s" % h
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(640, 0)
		l.add_theme_font_size_override("font_size", 13)
		_box.add_child(l)
	_button("Wróć", _back)

func _settings() -> void:
	_clear()
	_title("Ustawienia", 36)
	var on := CheckButton.new()
	on.text = "Dźwięk"
	on.button_pressed = Sfx.enabled
	on.add_theme_font_size_override("font_size", 24)
	on.toggled.connect(func(v: bool):
		Sfx.enabled = v
		Sfx.save_settings())
	_box.add_child(on)
	_title("Głośność", 20, Color.WHITE)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Sfx.volume
	vol.custom_minimum_size = Vector2(500, 40)
	vol.value_changed.connect(func(v: float):
		Sfx.volume = v
		Sfx.play("capture"))
	vol.drag_ended.connect(func(_c: bool): Sfx.save_settings())
	_box.add_child(vol)
	_button("Wróć", _back)

func _back() -> void:
	_box.position = Vector2(390, 60)
	_box.add_theme_constant_override("separation", 14)
	_main()
