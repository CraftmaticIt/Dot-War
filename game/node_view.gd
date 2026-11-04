class_name NodeView
extends Node2D
## Draws one sim node: neon ring in owner colour, garrison count, tower marker.

const RADIUS := 28.0

var node_id := -1
var _owner := 0
var _garrison := 0
var _tower := ""
var _tower_lvl := 1
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font

func refresh(n: Dictionary) -> void:
	var lvl: int = int(n.get("tower_lvl", 1))
	if n.owner != _owner or n.garrison != _garrison or n.tower != _tower or lvl != _tower_lvl:
		_owner = n.owner
		_garrison = n.garrison
		_tower = n.tower
		_tower_lvl = lvl
		queue_redraw()

func _draw() -> void:
	var c: Color = SwarmRenderer.OWNER_COLORS[_owner % SwarmRenderer.OWNER_COLORS.size()]
	draw_circle(Vector2.ZERO, RADIUS + 10, Color(c, 0.08))
	draw_circle(Vector2.ZERO, RADIUS, Color(c, 0.18))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 48, c, 3.0, true)
	if _tower == "laser":
		draw_line(Vector2(0, -RADIUS - 14), Vector2(0, -RADIUS + 4), c, 3.0)
	elif _tower == "pulse":
		draw_arc(Vector2.ZERO, RADIUS + 6, 0, TAU, 48, Color(c, 0.6), 1.5, true)
	if _tower != "" and _tower_lvl > 1:
		var ls := "L%d" % _tower_lvl
		draw_string(_font, Vector2(RADIUS - 6, -RADIUS + 4), ls, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
	var s := str(_garrison)
	var size := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(_font, Vector2(-size.x / 2, 7), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
