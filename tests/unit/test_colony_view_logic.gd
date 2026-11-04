extends GutTest

const CV := preload("res://game/colony_view.gd")
const O := Vector2(640, 360)

func test_hex_px_center_roundtrip():
	for h in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 3), Vector2i(4, -4)]:
		assert_eq(CV.cell_at(CV.hex_to_px(h.x, h.y, O), O), h)

func test_cell_at_center():
	assert_eq(CV.cell_at(O, O), Vector2i(0, 0))

func test_cell_at_neighbor():
	assert_eq(CV.cell_at(CV.hex_to_px(1, 0, O), O), Vector2i(1, 0))

func test_cell_at_edge_rounding():
	# 80% of the way from (0,0) to (0,1) lands in (0,1); 20% stays in (0,0).
	var a := CV.hex_to_px(0, 0, O)
	var b := CV.hex_to_px(0, 1, O)
	assert_eq(CV.cell_at(a.lerp(b, 0.8), O), Vector2i(0, 1))
	assert_eq(CV.cell_at(a.lerp(b, 0.2), O), Vector2i(0, 0))

func test_format_secs():
	assert_eq(CV.format_secs(45), "45s")
	assert_eq(CV.format_secs(185), "3m 05s")
	assert_eq(CV.format_secs(7200), "2h 00m")
	assert_eq(CV.format_secs(0), "0s")

func test_describe():
	assert_eq(CV.describe("mine", 1), "+500 energii/h")
	assert_eq(CV.describe("generator", 2), "+600 kropek/h, limit 80")
	assert_eq(CV.describe("storage", 1), "magazyn +1500")
	assert_eq(CV.describe("core", 1), "magazyn +2000, limit węzłów 8")
	assert_eq(CV.describe("trap", 2), "zabija 20 kropek")
	assert_eq(CV.describe("wall", 1), "garnizon 25")
	for t in Buildings.TYPES:
		assert_true(CV.INFO.has(t), "every building has a description: " + t)

func test_crystals_word():
	assert_eq(CV.crystals_word(1), "kryształ")
	assert_eq(CV.crystals_word(3), "kryształy")
	assert_eq(CV.crystals_word(5), "kryształów")
	assert_eq(CV.crystals_word(12), "kryształów")
	assert_eq(CV.crystals_word(22), "kryształy")

func test_attack_block_message():
	var c := ColonyState.new_default(1_800_000_000)
	assert_string_contains(CV.few_dots_text(c), "Generator")
	c.cells["0,1"] = {"type": "generator", "level": 1, "build_end": 0, "target_level": 1}
	c.dots = 4
	assert_string_contains(CV.few_dots_text(c), "4/10")
	assert_false(CV.few_dots_text(c).contains("zbuduj"))
