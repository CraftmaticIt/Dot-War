extends GutTest

const SFX := preload("res://game/sfx.gd")
const MENU := preload("res://game/main_menu.gd")

func test_tone_is_16bit_pcm_of_right_length_and_not_silent():
	var d: PackedByteArray = SFX.tone(440, 880, 0.1, "square", 0.5)
	assert_eq(d.size(), int(SFX.RATE * 0.1) * 2)
	var peak := 0
	for i in range(0, d.size(), 2):
		peak = maxi(peak, absi(d.decode_s16(i)))
	assert_between(peak, 1000, 32767)

func test_menu_has_three_buttons_and_help_lists_every_topic():
	var m: Control = MENU.new()
	add_child_autofree(m)
	var labels := []
	for c in m._box.get_children():
		if c is Button:
			labels.append(c.text)
	assert_eq(labels, ["Graj", "Jak grać", "Ustawienia"])
	m._help()
	var texts := 0
	for c in m._box.get_children():
		if c is Label and not c.is_queued_for_deletion() and c.text.contains(" — "):
			texts += 1
	assert_eq(texts, MENU.HELP.size())
