class_name InputSend
extends Node2D
## Drag from an own node to another node -> queue a send command. Draws the drag line.

signal send_requested(from: int, to: int)

var views: Array[NodeView] = []
var player_owner := 1
var world: SimWorld

var _drag_from := -1
var _drag_pos := Vector2.ZERO

func _node_at(p: Vector2) -> int:
	for v in views:
		if v.position.distance_to(p) <= NodeView.RADIUS + 12:
			return v.node_id
	return -1

func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch
	if pressed and e.pressed:
		var id: int = _node_at(e.position)
		if id != -1 and world.graph.node(id).owner == player_owner:
			_drag_from = id
			_drag_pos = e.position
	elif pressed and not e.pressed and _drag_from != -1:
		var to: int = _node_at(e.position)
		if to != -1 and to != _drag_from:
			send_requested.emit(_drag_from, to)
		_drag_from = -1
		queue_redraw()
	elif (e is InputEventMouseMotion or e is InputEventScreenDrag) and _drag_from != -1:
		_drag_pos = e.position
		queue_redraw()

func _draw() -> void:
	if _drag_from == -1:
		return
	var from := views.filter(func(v): return v.node_id == _drag_from)[0].position as Vector2
	draw_dashed_line(from, _drag_pos, SwarmRenderer.OWNER_COLORS[player_owner], 3.0, 10.0)
