extends Node2D

@export var player_owner = 0
# Movement points refilled to this value at the start of each turn.
@export var movement_points := 10

var base_map
# Movement points left this turn; each tile stepped costs 1.
var movement_left := movement_points

var _outline_material: ShaderMaterial

const OUTLINE_SHADER := preload("res://objects/overworld/army/army_map_unit/selection_outline.gdshader")

const GREYED_MODULATE := Color(0.5, 0.5, 0.5, 1.0)
const NORMAL_MODULATE := Color(1, 1, 1, 1)


func _ready() -> void:
	# Read after the scene has applied the exported value.
	movement_left = movement_points


func setup_building() -> void:
	set_flags()


func set_flags():
	$Flag.setup_flag()


func reset_movement() -> void:
	movement_left = movement_points


func set_greyed(state: bool) -> void:
	var figure := get_node_or_null("figure")
	if figure == null:
		return
	figure.modulate = GREYED_MODULATE if state else NORMAL_MODULATE


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if base_map == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		base_map.on_army_clicked(self)
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
