extends Area2D

## Attach to a building's Area2D to enable info popups.
## - Hovering the building for HOVER (see OBaseMap) shows a transient popup.
## - Left-clicking shows a pinned popup (closed via the X in its header).
## Interactions are routed to the overworld map (OBaseMap) found by walking up
## the tree, so this works for any building/field regardless of base_map wiring.

var _building: Node2D
var _base_map: Node


func _ready() -> void:
	input_pickable = true
	_building = get_parent()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


func _get_base_map() -> Node:
	if _base_map != null and is_instance_valid(_base_map):
		return _base_map
	var n: Node = _building
	while n != null:
		if n.has_method("on_building_clicked"):
			_base_map = n
			return n
		n = n.get_parent()
	return null


func _on_mouse_entered() -> void:
	var bm := _get_base_map()
	if bm == null:
		return
	if bm.has_method("is_mouse_over_gui") and bm.is_mouse_over_gui():
		return
	bm.on_building_hover_start(_building)


func _on_mouse_exited() -> void:
	var bm := _get_base_map()
	if bm != null:
		bm.on_building_hover_end(_building)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var bm := _get_base_map()
		if bm == null:
			return
		if bm.has_method("is_mouse_over_gui") and bm.is_mouse_over_gui():
			get_viewport().set_input_as_handled()
			return
		if bm.on_building_clicked(_building):
			get_viewport().set_input_as_handled()
