extends Node2D

@export var player_owner = 0

var base_map

var _selection_input_connected := false
var _outline_material: ShaderMaterial

const OUTLINE_SHADER := preload("res://objects/overworld/army/army_map_unit/selection_outline.gdshader")


func setup_building() -> void:
	set_flags()


func set_flags():
	$Flag.setup_flag()


func setup_selection_input() -> void:
	if _selection_input_connected or base_map == null:
		return
	var area := get_node_or_null("Area2D")
	if area == null:
		return
	area.input_pickable = true
	if not area.input_event.is_connected(_on_area_input_event):
		area.input_event.connect(_on_area_input_event)
	_selection_input_connected = true


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if base_map == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		base_map.select_army(self)
		get_viewport().set_input_as_handled()


func set_selected(selected: bool) -> void:
	var figure := get_node_or_null("figure")
	if figure == null:
		return
	if selected:
		if _outline_material == null:
			_outline_material = ShaderMaterial.new()
			_outline_material.shader = OUTLINE_SHADER
		figure.material = _outline_material
	else:
		figure.material = null
